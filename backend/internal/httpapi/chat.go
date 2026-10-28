package httpapi

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

type socketClient struct {
	connection *websocket.Conn
	userID string
	writeMu sync.Mutex
}

func (client *socketClient) writeJSON(value any) error {
	client.writeMu.Lock()
	defer client.writeMu.Unlock()
	return client.connection.WriteJSON(value)
}

var chatHub = struct {
	sync.RWMutex
	rooms map[string]map[*socketClient]struct{}
}{rooms: make(map[string]map[*socketClient]struct{})}

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

func listConversations(c *gin.Context) {
	userID := c.GetString("user_id")
	_,_=db.Exec(c.Request.Context(),`UPDATE messages SET body='',metadata='{}'::jsonb,deleted_at=NOW() WHERE deleted_at IS NULL AND expires_at<=NOW()`)
	archived := c.Query("archived") == "true"
	rows, err := db.Query(c.Request.Context(), `
		SELECT c.id::text, c.kind::text,
			COALESCE(c.title, other.full_name, other.phone, 'Conversation') AS title,
			COALESCE(c.avatar_url, other.avatar_url),
			COALESCE(last_message.body, ''), last_message.created_at,
			COALESCE(last_message.sender_id::text, ''), COALESCE(last_message.sender_name, ''),
			other.id::text,other.show_online_status,
			GREATEST(COUNT(unread.id)::int,CASE WHEN mine.manual_unread THEN 1 ELSE 0 END),mine.favorite,mine.pinned_at,mine.archived_at,mine.muted_until
		FROM conversation_members mine
		JOIN conversations c ON c.id=mine.conversation_id
		LEFT JOIN conversation_members other_member ON c.kind='direct' AND other_member.conversation_id=c.id AND other_member.user_id<>mine.user_id
		LEFT JOIN users other ON other.id=other_member.user_id
		LEFT JOIN LATERAL (
			SELECT m.body, m.created_at, m.sender_id,
				CASE WHEN m.kind='system' THEN '' ELSE COALESCE(NULLIF(sender_member.group_display_name,''),NULLIF(sender.full_name,''),NULLIF(sender.username,''),'GroopX member') END AS sender_name
			FROM messages m
			LEFT JOIN users sender ON sender.id=m.sender_id
			LEFT JOIN conversation_members sender_member ON sender_member.conversation_id=m.conversation_id AND sender_member.user_id=m.sender_id
			WHERE m.conversation_id=c.id AND m.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM message_hidden_for h WHERE h.message_id=m.id AND h.user_id=mine.user_id) ORDER BY m.created_at DESC LIMIT 1
		) last_message ON TRUE
		LEFT JOIN messages unread ON unread.conversation_id=c.id AND unread.sender_id<>mine.user_id
			AND unread.deleted_at IS NULL AND unread.created_at>COALESCE(mine.last_read_at, mine.joined_at) AND NOT EXISTS(SELECT 1 FROM message_hidden_for h WHERE h.message_id=unread.id AND h.user_id=mine.user_id)
		WHERE mine.user_id=$1 AND (($2=TRUE AND mine.archived_at IS NOT NULL) OR ($2=FALSE AND mine.archived_at IS NULL)) AND mine.hidden_at IS NULL
		GROUP BY c.id, other.id,other.full_name,other.phone,other.avatar_url,other.show_online_status,last_message.body,last_message.created_at,last_message.sender_id,last_message.sender_name,mine.favorite,mine.pinned_at,mine.archived_at,mine.muted_until,mine.last_read_at,mine.manual_unread
		ORDER BY mine.pinned_at DESC NULLS LAST,mine.favorite DESC,COALESCE(last_message.created_at, c.created_at) DESC`, userID, archived)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "conversations could not be loaded"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, kind, title, preview, previewSenderID, previewSenderName string
		var avatar,otherID *string
		var showOnline *bool
		var lastAt *time.Time
		var unread int; var favorite bool; var pinnedAt, archivedAt, mutedUntil *time.Time
		if rows.Scan(&id, &kind, &title, &avatar, &preview, &lastAt, &previewSenderID, &previewSenderName, &otherID, &showOnline, &unread, &favorite, &pinnedAt, &archivedAt, &mutedUntil) != nil { continue }
		online:=kind=="direct"&&otherID!=nil&&showOnline!=nil&&*showOnline&&isUserOnline(*otherID)
		items = append(items, gin.H{"id": id, "kind": kind, "title": title, "avatar_url": avatar, "preview": preview, "preview_sender_name":previewSenderName, "preview_mine":previewSenderID==userID, "online":online, "last_message_at": lastAt, "unread": unread, "favorite":favorite, "pinned":pinnedAt!=nil, "archived":archivedAt!=nil, "muted":mutedUntil!=nil && mutedUntil.After(time.Now())})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func createConversation(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		Kind string `json:"kind" binding:"required,oneof=direct group community"`
		Title string `json:"title" binding:"omitempty,max=160"`
		MemberIDs []string `json:"member_ids" binding:"required,min=1"`
	}
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid conversation"}); return }
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx); if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "conversation could not be created"}); return }
	defer tx.Rollback(ctx)
	var id string
	err = tx.QueryRow(ctx, `INSERT INTO conversations(kind,title,created_by) VALUES($1,NULLIF($2,''),$3) RETURNING id::text`, input.Kind, strings.TrimSpace(input.Title), userID).Scan(&id)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "conversation could not be created"}); return }
	memberIDs := append([]string{userID}, input.MemberIDs...)
	for _, memberID := range memberIDs {
		if _, err = tx.Exec(ctx, `INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`, id, memberID, map[bool]string{true:"admin", false:"member"}[memberID == userID]); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "one or more members are invalid"}); return
		}
	}
	if tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "conversation could not be saved"}); return }
	c.JSON(http.StatusCreated, gin.H{"id": id, "kind": input.Kind, "title": input.Title})
}

func getConversationDetails(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	if !isConversationMember(c, conversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return }
	var kind, title string
	var avatar, otherID *string
	var showOnline *bool
	var lastSeen *time.Time
	var memberCount int
	var blockedByMe, communicationBlocked bool
	var disappearingSeconds int
	var announcementOnly bool
	var memberRole string
	err := db.QueryRow(c.Request.Context(), `SELECT c.kind::text, COALESCE(c.title,other.full_name,other.phone,'Conversation'),
		COALESCE(c.avatar_url,other.avatar_url),other.id::text,other.show_online_status,other.last_seen_at,
		(SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id=c.id),
		COALESCE(EXISTS(SELECT 1 FROM user_blocks b WHERE b.blocker_id=$2 AND b.blocked_id=other.id),FALSE),
		COALESCE(EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$2 AND b.blocked_id=other.id) OR (b.blocker_id=other.id AND b.blocked_id=$2)),FALSE),c.disappearing_seconds,
		COALESCE(c.announcement_only,FALSE),mine.role
		FROM conversations c JOIN conversation_members mine ON mine.conversation_id=c.id AND mine.user_id=$2
		LEFT JOIN conversation_members om ON c.kind='direct' AND om.conversation_id=c.id AND om.user_id<>$2
		LEFT JOIN users other ON other.id=om.user_id WHERE c.id=$1`, conversationID, userID).Scan(&kind, &title, &avatar, &otherID, &showOnline, &lastSeen, &memberCount, &blockedByMe, &communicationBlocked,&disappearingSeconds,&announcementOnly,&memberRole)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"}); return }
	response := gin.H{"id":conversationID,"kind":kind,"title":title,"avatar_url":avatar,"member_count":memberCount,"online":false,"other_user_id":otherID,"blocked_by_me":blockedByMe,"communication_blocked":communicationBlocked,"disappearing_seconds":disappearingSeconds,"announcement_only":announcementOnly,"admin":memberRole=="admin","can_send":groupAllowsSender(kind,announcementOnly,memberRole)}
	if kind == "direct" && otherID != nil && showOnline != nil && *showOnline {
		response["online"] = isUserOnline(*otherID)
		response["last_seen_at"] = lastSeen
	}
	c.JSON(http.StatusOK, response)
}

func listMessages(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	if !isConversationMember(c, conversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return }
	expireConversationMessages(c.Request.Context(),conversationID)
	beforeTime, beforeID := time.Now().Add(time.Second), "ffffffff-ffff-ffff-ffff-ffffffffffff"
	if raw := c.Query("before"); raw != "" {
		decoded, err := base64.RawURLEncoding.DecodeString(raw)
		parts := strings.SplitN(string(decoded), "|", 2)
		if err != nil || len(parts) != 2 { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid message cursor"}); return }
		beforeTime, err = time.Parse(time.RFC3339Nano,parts[0]); if err != nil { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid message cursor"}); return }; beforeID=parts[1]
	}
	rows, err := db.Query(c.Request.Context(), `SELECT messages.id::text, COALESCE(messages.sender_id::text,''),
		COALESCE(NULLIF(sender_member.group_display_name,''),NULLIF(sender.full_name,''),NULLIF(sender.username,''),'GroopX member'),COALESCE(sender.avatar_url,''),
		messages.body, messages.kind::text, messages.metadata, messages.status::text, messages.created_at, messages.edited_at,
		COALESCE((SELECT jsonb_agg(jsonb_build_object('emoji',reaction.emoji,'count',reaction.total,'mine',reaction.mine)) FROM
			(SELECT emoji,COUNT(*)::int total,BOOL_OR(user_id=$2) mine FROM message_reactions WHERE message_id=messages.id GROUP BY emoji) reaction),'[]'::jsonb),
		messages.reply_to_id::text, reply.body, COALESCE(reply.sender_id::text,''),
		COALESCE(NULLIF(reply_sender_member.group_display_name,''),NULLIF(reply_sender.full_name,''),NULLIF(reply_sender.username,''),'GroopX member'),
		EXISTS(SELECT 1 FROM message_stars star WHERE star.message_id=messages.id AND star.user_id=$2),
		EXISTS(SELECT 1 FROM message_pins pin WHERE pin.message_id=messages.id),messages.view_once,
		EXISTS(SELECT 1 FROM view_once_opens opened WHERE opened.message_id=messages.id AND opened.user_id=$2),
		(SELECT COUNT(*)::int FROM view_once_opens opened WHERE opened.message_id=messages.id),
		(SELECT COUNT(*)::int FROM conversation_members recipient WHERE recipient.conversation_id=messages.conversation_id AND recipient.user_id<>messages.sender_id),
		COALESCE((SELECT array_agg(mention.user_id::text ORDER BY mention.user_id::text) FROM message_mentions mention WHERE mention.message_id=messages.id),ARRAY[]::text[])
		FROM messages
		LEFT JOIN users sender ON sender.id=messages.sender_id
		LEFT JOIN conversation_members sender_member ON sender_member.conversation_id=messages.conversation_id AND sender_member.user_id=messages.sender_id
		LEFT JOIN messages reply ON reply.id=messages.reply_to_id
		LEFT JOIN users reply_sender ON reply_sender.id=reply.sender_id
		LEFT JOIN conversation_members reply_sender_member ON reply_sender_member.conversation_id=messages.conversation_id AND reply_sender_member.user_id=reply.sender_id
		WHERE messages.conversation_id=$1 AND messages.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM message_hidden_for hidden WHERE hidden.message_id=messages.id AND hidden.user_id=$2) AND (messages.created_at,messages.id)<($3,$4::uuid)
		ORDER BY messages.created_at DESC,messages.id DESC LIMIT 50`, conversationID, userID, beforeTime, beforeID)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "messages could not be loaded"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	var oldestTime time.Time; var oldestID string
	for rows.Next() {
		var id, senderID, senderName, senderAvatar, body, kind, status string; var metadata, reactions []byte; var createdAt time.Time; var editedAt *time.Time
		var replyID, replyText, replySenderID *string;var replySenderName string;var starred,pinned,viewOnce,opened bool;var openedCount,recipientCount int;var mentionUserIDs []string
		if rows.Scan(&id, &senderID, &senderName, &senderAvatar, &body, &kind, &metadata, &status, &createdAt, &editedAt, &reactions, &replyID, &replyText, &replySenderID,&replySenderName,&starred,&pinned,&viewOnce,&opened,&openedCount,&recipientCount,&mentionUserIDs) != nil { continue }
		var reactionItems []map[string]any; _ = json.Unmarshal(reactions, &reactionItems)
		item := gin.H{"id": id, "sender_id": senderID, "sender_name":senderName,"sender_avatar_url":senderAvatar,"text": body, "kind": kind, "status": status, "created_at": createdAt, "mine": senderID == userID, "edited": editedAt != nil, "reactions": reactionItems,"starred":starred,"pinned":pinned,"mention_user_ids":mentionUserIDs,"mentioned":containsString(mentionUserIDs,userID)}
		if replyID != nil { item["reply"] = gin.H{"id":*replyID,"text":replyText,"sender_id":replySenderID,"sender_name":replySenderName,"mine":replySenderID != nil && *replySenderID == userID} }
		var messageMetadata map[string]any
		if json.Unmarshal(metadata,&messageMetadata)==nil {
			item["forwarded"] = messageMetadata["forwarded"] == true
			if statusReply, ok := messageMetadata["status_reply"].(map[string]any); ok { item["status_reply"] = statusReply }
			if viewOnce { messageMetadata=protectViewOnceAttachment(messageMetadata,senderID==userID,opened,openedCount,recipientCount) }
			if kind != "text" && kind != "system" { item["attachment"] = messageMetadata }
		}
		if kind == "poll" {
			if poll, pollErr := loadPollSnapshotByMessage(c.Request.Context(), id, userID); pollErr == nil {
				item["attachment"] = poll.attachment
			}
		}
		items = append(items, item)
		oldestTime, oldestID = createdAt, id
	}
	var nextCursor *string
	if len(items)==50 { value:=base64.RawURLEncoding.EncodeToString([]byte(oldestTime.Format(time.RFC3339Nano)+"|"+oldestID)); nextCursor=&value }
	c.JSON(http.StatusOK, gin.H{"items": items,"next_cursor":nextCursor})
}

func searchMessages(c *gin.Context) {
	conversationID,userID:=c.Param("id"),c.GetString("user_id"); query:=strings.TrimSpace(c.Query("q"))
	if !isConversationMember(c,conversationID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a conversation member"});return}
	expireConversationMessages(c.Request.Context(),conversationID)
	if len([]rune(query))<2 { c.JSON(http.StatusOK,gin.H{"items":[]gin.H{}});return }
	rows,err:=db.Query(c.Request.Context(),`SELECT m.id::text,COALESCE(m.sender_id::text,''),COALESCE(NULLIF(sender_member.group_display_name,''),NULLIF(sender.full_name,''),NULLIF(sender.username,''),'GroopX member'),COALESCE(sender.avatar_url,''),m.body,m.kind::text,m.status::text,m.created_at,m.edited_at,COALESCE((SELECT array_agg(mention.user_id::text ORDER BY mention.user_id::text) FROM message_mentions mention WHERE mention.message_id=m.id),ARRAY[]::text[]) FROM messages m
		LEFT JOIN users sender ON sender.id=m.sender_id
		LEFT JOIN conversation_members sender_member ON sender_member.conversation_id=m.conversation_id AND sender_member.user_id=m.sender_id
		WHERE m.conversation_id=$1 AND m.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM message_hidden_for hidden WHERE hidden.message_id=m.id AND hidden.user_id=$3) AND m.body ILIKE $2 ORDER BY m.created_at DESC LIMIT 50`,conversationID,"%"+query+"%",userID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message search unavailable"});return};defer rows.Close();items:=make([]gin.H,0)
	for rows.Next(){var id,senderID,senderName,senderAvatar,body,kind,status string;var createdAt time.Time;var editedAt *time.Time;var mentionUserIDs []string;if rows.Scan(&id,&senderID,&senderName,&senderAvatar,&body,&kind,&status,&createdAt,&editedAt,&mentionUserIDs)==nil{items=append(items,gin.H{"id":id,"sender_id":senderID,"sender_name":senderName,"sender_avatar_url":senderAvatar,"text":body,"kind":kind,"status":status,"created_at":createdAt,"mine":senderID==userID,"edited":editedAt!=nil,"mention_user_ids":mentionUserIDs,"mentioned":containsString(mentionUserIDs,userID)})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func searchAllMessages(c *gin.Context) {
	userID,query:=c.GetString("user_id"),strings.TrimSpace(c.Query("q"))
	if len([]rune(query))<2 { c.JSON(http.StatusOK,gin.H{"items":[]gin.H{}});return }
	rows,err:=db.Query(c.Request.Context(),`SELECT m.id::text,m.conversation_id::text,c.kind::text,
		COALESCE(c.title,other.full_name,other.phone,'Conversation'),COALESCE(c.avatar_url,other.avatar_url,''),
		COALESCE(NULLIF(sender_member.group_display_name,''),NULLIF(sender.full_name,''),NULLIF(sender.username,''),'GroopX member'),
		m.body,m.created_at,COALESCE(m.sender_id::text,'')
		FROM messages m
		JOIN conversation_members mine ON mine.conversation_id=m.conversation_id AND mine.user_id=$1 AND mine.hidden_at IS NULL
		JOIN conversations c ON c.id=m.conversation_id AND c.deleted_at IS NULL
		LEFT JOIN conversation_members other_member ON c.kind='direct' AND other_member.conversation_id=c.id AND other_member.user_id<>mine.user_id
		LEFT JOIN users other ON other.id=other_member.user_id
		LEFT JOIN users sender ON sender.id=m.sender_id
		LEFT JOIN conversation_members sender_member ON sender_member.conversation_id=m.conversation_id AND sender_member.user_id=m.sender_id
		WHERE m.deleted_at IS NULL AND (m.expires_at IS NULL OR m.expires_at>NOW()) AND m.body ILIKE $2
		AND NOT EXISTS(SELECT 1 FROM message_hidden_for hidden WHERE hidden.message_id=m.id AND hidden.user_id=$1)
		ORDER BY m.created_at DESC LIMIT 50`,userID,"%"+query+"%")
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"global message search unavailable"});return};defer rows.Close()
	items:=make([]gin.H,0)
	for rows.Next(){var id,conversationID,conversationKind,title,avatar,senderName,body,senderID string;var createdAt time.Time;if rows.Scan(&id,&conversationID,&conversationKind,&title,&avatar,&senderName,&body,&createdAt,&senderID)==nil{items=append(items,gin.H{"id":id,"conversation_id":conversationID,"conversation_kind":conversationKind,"conversation_title":title,"avatar_url":avatar,"sender_name":senderName,"text":body,"created_at":createdAt,"mine":senderID==userID})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func listStarredMessages(c *gin.Context) {
	conversationID,userID:=c.Param("id"),c.GetString("user_id")
	if !isConversationMember(c,conversationID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a conversation member"});return}
	expireConversationMessages(c.Request.Context(),conversationID)
	rows,err:=db.Query(c.Request.Context(),`SELECT m.id::text,COALESCE(m.sender_id::text,''),COALESCE(NULLIF(sender_member.group_display_name,''),NULLIF(sender.full_name,''),NULLIF(sender.username,''),'GroopX member'),COALESCE(sender.avatar_url,''),m.body,m.kind::text,m.metadata,m.status::text,m.created_at,m.edited_at,COALESCE((SELECT array_agg(mention.user_id::text ORDER BY mention.user_id::text) FROM message_mentions mention WHERE mention.message_id=m.id),ARRAY[]::text[])
		FROM message_stars s JOIN messages m ON m.id=s.message_id LEFT JOIN users sender ON sender.id=m.sender_id
		LEFT JOIN conversation_members sender_member ON sender_member.conversation_id=m.conversation_id AND sender_member.user_id=m.sender_id
		WHERE s.user_id=$1 AND m.conversation_id=$2 AND m.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM message_hidden_for hidden WHERE hidden.message_id=m.id AND hidden.user_id=$1) ORDER BY s.created_at DESC LIMIT 200`,userID,conversationID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"starred messages could not be loaded"});return};defer rows.Close()
	items:=make([]gin.H,0)
	for rows.Next(){var id,senderID,senderName,senderAvatar,body,kind,status string;var metadata []byte;var createdAt time.Time;var editedAt *time.Time;var mentionUserIDs []string;if rows.Scan(&id,&senderID,&senderName,&senderAvatar,&body,&kind,&metadata,&status,&createdAt,&editedAt,&mentionUserIDs)!=nil{continue};item:=gin.H{"id":id,"sender_id":senderID,"sender_name":senderName,"sender_avatar_url":senderAvatar,"text":body,"kind":kind,"status":status,"created_at":createdAt,"mine":senderID==userID,"edited":editedAt!=nil,"starred":true,"mention_user_ids":mentionUserIDs,"mentioned":containsString(mentionUserIDs,userID)};var messageMetadata map[string]any;if json.Unmarshal(metadata,&messageMetadata)==nil{item["forwarded"]=messageMetadata["forwarded"]==true;if statusReply,ok:=messageMetadata["status_reply"].(map[string]any);ok{item["status_reply"]=statusReply};if kind!="text"{item["attachment"]=messageMetadata}};items=append(items,item)}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func starMessage(c *gin.Context){userID:=c.GetString("user_id");result,err:=db.Exec(c.Request.Context(),`INSERT INTO message_stars(message_id,user_id) SELECT m.id,$2 FROM messages m JOIN conversation_members cm ON cm.conversation_id=m.conversation_id AND cm.user_id=$2 WHERE m.id=$1 AND m.deleted_at IS NULL ON CONFLICT DO NOTHING`,c.Param("id"),userID);if err!=nil||result.RowsAffected()==0{var exists bool;_ = db.QueryRow(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM message_stars WHERE message_id=$1 AND user_id=$2)`,c.Param("id"),userID).Scan(&exists);if !exists{c.JSON(http.StatusNotFound,gin.H{"error":"message not found"});return}};c.Status(http.StatusNoContent)}
func unstarMessage(c *gin.Context){_,err:=db.Exec(c.Request.Context(),`DELETE FROM message_stars WHERE message_id=$1 AND user_id=$2`,c.Param("id"),c.GetString("user_id"));if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be unstarred"});return};c.Status(http.StatusNoContent)}

func listPinnedMessages(c *gin.Context){
	conversationID,userID:=c.Param("id"),c.GetString("user_id")
	if !isConversationMember(c,conversationID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a conversation member"});return}
	expireConversationMessages(c.Request.Context(),conversationID)
	rows,err:=db.Query(c.Request.Context(),`SELECT m.id::text,COALESCE(m.sender_id::text,''),COALESCE(NULLIF(sender_member.group_display_name,''),NULLIF(sender.full_name,''),NULLIF(sender.username,''),'GroopX member'),COALESCE(sender.avatar_url,''),m.body,m.kind::text,m.metadata,m.status::text,m.created_at,m.edited_at,COALESCE((SELECT array_agg(mention.user_id::text ORDER BY mention.user_id::text) FROM message_mentions mention WHERE mention.message_id=m.id),ARRAY[]::text[])
		FROM message_pins p JOIN messages m ON m.id=p.message_id LEFT JOIN users sender ON sender.id=m.sender_id
		LEFT JOIN conversation_members sender_member ON sender_member.conversation_id=m.conversation_id AND sender_member.user_id=m.sender_id
		WHERE p.conversation_id=$1 AND m.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM message_hidden_for hidden WHERE hidden.message_id=m.id AND hidden.user_id=$2) ORDER BY p.created_at DESC`,conversationID,userID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"pinned messages could not be loaded"});return};defer rows.Close()
	items:=make([]gin.H,0)
	for rows.Next(){var id,senderID,senderName,senderAvatar,body,kind,status string;var metadata []byte;var createdAt time.Time;var editedAt *time.Time;var mentionUserIDs []string;if rows.Scan(&id,&senderID,&senderName,&senderAvatar,&body,&kind,&metadata,&status,&createdAt,&editedAt,&mentionUserIDs)!=nil{continue};item:=gin.H{"id":id,"sender_id":senderID,"sender_name":senderName,"sender_avatar_url":senderAvatar,"text":body,"kind":kind,"status":status,"created_at":createdAt,"mine":senderID==userID,"edited":editedAt!=nil,"pinned":true,"mention_user_ids":mentionUserIDs,"mentioned":containsString(mentionUserIDs,userID)};var messageMetadata map[string]any;if json.Unmarshal(metadata,&messageMetadata)==nil{item["forwarded"]=messageMetadata["forwarded"]==true;if statusReply,ok:=messageMetadata["status_reply"].(map[string]any);ok{item["status_reply"]=statusReply};if kind!="text"{item["attachment"]=messageMetadata}};items=append(items,item)}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func pinMessage(c *gin.Context){
	messageID,userID:=c.Param("id"),c.GetString("user_id");var conversationID string
	ctx:=c.Request.Context()
	if db.QueryRow(ctx,`SELECT m.conversation_id::text FROM messages m JOIN conversation_members cm ON cm.conversation_id=m.conversation_id AND cm.user_id=$2 WHERE m.id=$1 AND m.deleted_at IS NULL`,messageID,userID).Scan(&conversationID)!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"message not found"});return}
	tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be pinned"});return};defer tx.Rollback(ctx)
	var lock any;if tx.QueryRow(ctx,`SELECT pg_advisory_xact_lock(hashtext($1))`,conversationID).Scan(&lock)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be pinned"});return}
	var exists bool;if tx.QueryRow(ctx,`SELECT EXISTS(SELECT 1 FROM message_pins WHERE message_id=$1)`,messageID).Scan(&exists)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be pinned"});return}
	if !exists{var count int;if tx.QueryRow(ctx,`SELECT COUNT(*)::int FROM message_pins p JOIN messages m ON m.id=p.message_id WHERE p.conversation_id=$1 AND m.deleted_at IS NULL`,conversationID).Scan(&count)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be pinned"});return};if count>=3{c.JSON(http.StatusConflict,gin.H{"error":"A conversation can have maximum 3 pinned messages"});return};if _,err=tx.Exec(ctx,`INSERT INTO message_pins(message_id,conversation_id,pinned_by) VALUES($1,$2,$3)`,messageID,conversationID,userID);err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be pinned"});return}}
	if tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be pinned"});return}
	broadcast(conversationID,userID,gin.H{"type":"message_pin","conversation_id":conversationID,"message_id":messageID,"pinned":true});c.Status(http.StatusNoContent)
}

func unpinMessage(c *gin.Context){
	messageID,userID:=c.Param("id"),c.GetString("user_id");var conversationID string
	if db.QueryRow(c.Request.Context(),`SELECT m.conversation_id::text FROM messages m JOIN conversation_members cm ON cm.conversation_id=m.conversation_id AND cm.user_id=$2 WHERE m.id=$1`,messageID,userID).Scan(&conversationID)!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"message not found"});return}
	if _,err:=db.Exec(c.Request.Context(),`DELETE FROM message_pins WHERE message_id=$1`,messageID);err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be unpinned"});return}
	broadcast(conversationID,userID,gin.H{"type":"message_pin","conversation_id":conversationID,"message_id":messageID,"pinned":false});c.Status(http.StatusNoContent)
}

func markConversationRead(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	if !isConversationMember(c, conversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return }
	_,_=db.Exec(c.Request.Context(),`UPDATE conversation_members SET manual_unread=FALSE WHERE conversation_id=$1 AND user_id=$2`,conversationID,userID)
	var messageID string
	var messageCreatedAt time.Time
	err := db.QueryRow(c.Request.Context(), `SELECT id::text,created_at FROM messages WHERE conversation_id=$1 AND deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM message_hidden_for hidden WHERE hidden.message_id=messages.id AND hidden.user_id=$2) ORDER BY created_at DESC,id DESC LIMIT 1`, conversationID,userID).Scan(&messageID,&messageCreatedAt)
	if err == nil {
		_, _ = db.Exec(c.Request.Context(), `UPDATE conversation_members SET last_read_message_id=$3,last_read_at=GREATEST(COALESCE(last_read_at,'epoch'::timestamptz),$4),manual_unread=FALSE WHERE conversation_id=$1 AND user_id=$2`, conversationID, userID, messageID, messageCreatedAt)
		var receipts bool
		_ = db.QueryRow(c.Request.Context(), `SELECT read_receipts FROM users WHERE id=$1`, userID).Scan(&receipts)
		if receipts {
			_, _ = db.Exec(c.Request.Context(), `UPDATE message_receipts r SET delivered_at=COALESCE(delivered_at,NOW()),read_at=NOW() FROM messages m WHERE r.message_id=m.id AND r.user_id=$2 AND m.conversation_id=$1 AND m.created_at<=$3 AND r.read_at IS NULL`, conversationID,userID,messageCreatedAt)
			_, _ = db.Exec(c.Request.Context(), `UPDATE messages m SET status=CASE WHEN NOT EXISTS(SELECT 1 FROM message_receipts r WHERE r.message_id=m.id AND r.read_at IS NULL) THEN 'read'::message_status WHEN NOT EXISTS(SELECT 1 FROM message_receipts r WHERE r.message_id=m.id AND r.delivered_at IS NULL) THEN 'delivered'::message_status ELSE m.status END WHERE m.conversation_id=$1 AND m.sender_id<>$2`, conversationID,userID)
			broadcast(conversationID, userID, gin.H{"type":"read_receipt","conversation_id":conversationID})
		}
	}
	c.Status(http.StatusNoContent)
}

func setConversationReadState(c *gin.Context){
	conversationID,userID:=c.Param("id"),c.GetString("user_id");if !isConversationMember(c,conversationID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a conversation member"});return}
	var input struct{Unread bool `json:"unread"`};if c.ShouldBindJSON(&input)!=nil{c.JSON(http.StatusBadRequest,gin.H{"error":"invalid read state"});return}
	if input.Unread{_,err:=db.Exec(c.Request.Context(),`UPDATE conversation_members SET manual_unread=TRUE WHERE conversation_id=$1 AND user_id=$2`,conversationID,userID);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"read state could not be updated"});return};c.Status(http.StatusNoContent);return}
	markConversationRead(c)
}

func chatSocket(c *gin.Context) {
	conversationID := c.Query("conversation_id")
	userID, err := parseAccessToken(c.Query("access_token"))
	if err != nil { c.JSON(http.StatusUnauthorized, gin.H{"error": "valid session is required"}); return }
	if conversationID != "" && !isConversationMember(c, conversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return }
	senderName,senderAvatar:=messageSenderIdentity(c.Request.Context(),conversationID,userID)
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil); if err != nil { return }
	client := &socketClient{connection: conn, userID: userID}
	room := conversationID; if room == "" { room = "user:"+userID }
	joinRoom(room, client)
	if conversationID!=""{
		_,_=db.Exec(c.Request.Context(),`UPDATE message_receipts r SET delivered_at=COALESCE(delivered_at,NOW()) FROM messages m WHERE r.message_id=m.id AND r.user_id=$2 AND m.conversation_id=$1 AND r.delivered_at IS NULL`,conversationID,userID)
		broadcast(conversationID,userID,gin.H{"type":"delivery_receipt","conversation_id":conversationID})
	}
	announceUserPresence(userID, true)
	defer func() {
		if conversationID != "" { broadcast(conversationID,userID,gin.H{"type":"typing","user_id":userID,"sender_name":senderName,"typing":false}) }
		leaveRoom(room, client)
		stillOnline := isUserOnline(userID)
		if !stillOnline { _, _ = db.Exec(context.Background(), `UPDATE users SET last_seen_at=NOW() WHERE id=$1`, userID) }
		announceUserPresence(userID, stillOnline)
		conn.Close()
	}()
	for {
		_, data, err := conn.ReadMessage(); if err != nil { return }
		if conversationID == "" { continue }
		var input struct { Type string `json:"type"`; Text string `json:"text"`; ReplyToID string `json:"reply_to_id"`; MentionUserIDs []string `json:"mention_user_ids"`; Typing bool `json:"typing"` }
		if json.Unmarshal(data, &input) != nil { continue }
		var otherID string
		if db.QueryRow(c.Request.Context(),`SELECT cm.user_id::text FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id<>$2 WHERE c.id=$1 AND c.kind='direct' LIMIT 1`,conversationID,userID).Scan(&otherID)==nil && usersBlocked(userID,otherID) { _ = client.writeJSON(gin.H{"type":"error","error":"communication is blocked"}); continue }
		allowed,permissionErr:=conversationAllowsSender(c.Request.Context(),db,conversationID,userID)
		if permissionErr!=nil{_ = client.writeJSON(gin.H{"type":"error","error":"conversation is unavailable"});continue}
		if !allowed{
			if input.Type!="typing"{_ = client.writeJSON(gin.H{"type":"error","error":announcementOnlyMessage})}
			continue
		}
		senderName,senderAvatar=messageSenderIdentity(c.Request.Context(),conversationID,userID)
		if input.Type == "typing" { broadcast(conversationID,userID,gin.H{"type":"typing","user_id":userID,"sender_name":senderName,"typing":input.Typing}); continue }
		if strings.TrimSpace(input.Text) == "" { continue }
		text:=strings.TrimSpace(input.Text)
		mentions,mentionErr:=validateMessageMentions(c.Request.Context(),conversationID,userID,text,input.MentionUserIDs)
		if mentionErr!=nil{_ = client.writeJSON(gin.H{"type":"error","error":errInvalidMessageMentions.Error()});continue}
		status := "sent"
		if onlineRecipients(conversationID, userID) > 0 { status = "delivered" }
		var reply gin.H
		if input.ReplyToID != "" {
			var replyText, replySenderID,replySenderName string
			if db.QueryRow(c.Request.Context(),`SELECT m.body,COALESCE(m.sender_id::text,''),COALESCE(NULLIF(member.group_display_name,''),NULLIF(u.full_name,''),NULLIF(u.username,''),'GroopX member') FROM messages m LEFT JOIN users u ON u.id=m.sender_id LEFT JOIN conversation_members member ON member.conversation_id=m.conversation_id AND member.user_id=m.sender_id WHERE m.id=$1 AND m.conversation_id=$2 AND m.deleted_at IS NULL`,input.ReplyToID,conversationID).Scan(&replyText,&replySenderID,&replySenderName)!=nil { _ = client.writeJSON(gin.H{"type":"error","error":"reply target is unavailable"}); continue }
			reply=gin.H{"id":input.ReplyToID,"text":replyText,"sender_id":replySenderID,"sender_name":replySenderName,"mine":replySenderID==userID}
		}
		ctx:=c.Request.Context();tx,txErr:=db.Begin(ctx)
		if txErr!=nil{_ = client.writeJSON(gin.H{"type":"error","error":"message could not be saved"});continue}
		var id string; var createdAt time.Time
		txErr = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,body,status,reply_to_id) VALUES($1,$2,$3,$4,NULLIF($5,'')::uuid) RETURNING id::text, created_at`, conversationID, userID, text, status, input.ReplyToID).Scan(&id, &createdAt)
		if txErr==nil{txErr=insertMessageMentions(ctx,tx,id,mentions)}
		if txErr==nil{_,txErr=tx.Exec(ctx,`UPDATE conversations SET last_message_at=$2, updated_at=NOW() WHERE id=$1`,conversationID,createdAt)}
		if txErr==nil{_,txErr=tx.Exec(ctx,`UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`,conversationID,userID)}
		if txErr!=nil||tx.Commit(ctx)!=nil{_ = tx.Rollback(ctx);_ = client.writeJSON(gin.H{"type":"error", "error":"message could not be saved"}); continue }
		mentionIDs:=mentionUserIDs(mentions)
		broadcast(conversationID, userID, gin.H{"type":"message", "id":id, "conversation_id":conversationID, "sender_id":userID,"sender_name":senderName,"sender_avatar_url":senderAvatar, "text":text, "kind":"text", "status":status, "created_at":createdAt, "reply":reply,"mention_user_ids":mentionIDs,"mentioned":false})
		notifyMessageConversation(conversationID,userID,text,map[string]any{"conversation_id":conversationID,"message_id":id,"mention_user_ids":mentionIDs},mentionIDs)
	}
}

func announceUserPresence(userID string, online bool) {
	var visible bool
	if db.QueryRow(context.Background(), `SELECT show_online_status FROM users WHERE id=$1`, userID).Scan(&visible) != nil || !visible { return }
	broadcastUserPresence(userID,online)
}

func broadcastUserPresence(userID string,online bool){
	rows,err:=db.Query(context.Background(),`SELECT mine.conversation_id::text,c.kind::text,COALESCE(peer.user_id::text,'')
		FROM conversation_members mine
		JOIN conversations c ON c.id=mine.conversation_id AND c.deleted_at IS NULL
		LEFT JOIN conversation_members peer ON c.kind='direct' AND peer.conversation_id=mine.conversation_id AND peer.user_id<>mine.user_id AND peer.hidden_at IS NULL
		WHERE mine.user_id=$1 AND mine.hidden_at IS NULL`,userID);if err!=nil{return};defer rows.Close()
	for rows.Next(){var room,kind,peerID string;if rows.Scan(&room,&kind,&peerID)==nil{payload:=gin.H{"type":"presence","conversation_id":room,"user_id":userID,"online":online,"at":time.Now()};broadcast(room,userID,payload);if kind=="direct"&&peerID!=""{broadcast("user:"+peerID,userID,payload)}}}
}

func isConversationMember(c *gin.Context, conversationID, userID string) bool {
	var exists bool
	err := db.QueryRow(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2)`, conversationID, userID).Scan(&exists)
	return err == nil && exists
}

func messageSenderIdentity(ctx context.Context,conversationID,userID string)(string,string){
	var name,avatar string
	if db.QueryRow(ctx,`SELECT COALESCE(NULLIF(member.group_display_name,''),NULLIF(account.full_name,''),NULLIF(account.username,''),'GroopX member'),COALESCE(account.avatar_url,'')
		FROM users account LEFT JOIN conversation_members member ON member.conversation_id=NULLIF($1,'')::uuid AND member.user_id=account.id
		WHERE account.id=$2`,conversationID,userID).Scan(&name,&avatar)!=nil{return "GroopX member",""}
	return name,avatar
}

func joinRoom(room string, client *socketClient) { chatHub.Lock(); defer chatHub.Unlock(); if chatHub.rooms[room] == nil { chatHub.rooms[room] = make(map[*socketClient]struct{}) }; chatHub.rooms[room][client] = struct{}{} }
func leaveRoom(room string, client *socketClient) { chatHub.Lock(); defer chatHub.Unlock(); delete(chatHub.rooms[room], client); if len(chatHub.rooms[room]) == 0 { delete(chatHub.rooms, room) } }
func disconnectRoomUser(room,userID string){
	chatHub.Lock();clients:=make([]*socketClient,0);for client:=range chatHub.rooms[room]{if client.userID==userID{delete(chatHub.rooms[room],client);clients=append(clients,client)}};if len(chatHub.rooms[room])==0{delete(chatHub.rooms,room)};chatHub.Unlock()
	for _,client:=range clients{_ = client.connection.Close()}
}
func onlineRecipients(room, senderID string) int { chatHub.RLock(); defer chatHub.RUnlock(); count := 0; for client := range chatHub.rooms[room] { if client.userID != senderID { count++ } }; return count }
func isUserOnline(userID string) bool { chatHub.RLock(); defer chatHub.RUnlock(); for _, clients := range chatHub.rooms { for client := range clients { if client.userID == userID { return true } } }; return false }
func announcePresence(room, userID string, online bool) {
	var visible bool
	if db.QueryRow(context.Background(), `SELECT show_online_status FROM users WHERE id=$1`, userID).Scan(&visible) != nil || !visible { return }
	broadcast(room, userID, gin.H{"type":"presence","user_id":userID,"online":online,"at":time.Now()})
}
func broadcast(room, senderID string, payload gin.H) {
	chatHub.RLock(); clients := make([]*socketClient, 0, len(chatHub.rooms[room])); for client := range chatHub.rooms[room] { clients = append(clients, client) }; chatHub.RUnlock()
	for _, client := range clients { message := gin.H{}; for key, value := range payload { message[key] = value }; message["mine"] = client.userID == senderID;if payload["type"]=="message"{message["mentioned"]=payloadMentionsUser(payload["mention_user_ids"],client.userID);if client.userID!=senderID{if id,ok:=payload["id"].(string);ok{_,_=db.Exec(context.Background(),`UPDATE message_receipts SET delivered_at=COALESCE(delivered_at,NOW()) WHERE message_id=$1 AND user_id=$2`,id,client.userID)}}}; if client.writeJSON(message) != nil { leaveRoom(room, client) } }
	if !strings.HasPrefix(room,"user:") { eventType,_:=payload["type"].(string);if eventType=="message"||eventType=="message_update"||eventType=="message_delete"||eventType=="read_receipt" { broadcastConversationUpdate(room,eventType) } }
}

func broadcastConversationUpdate(conversationID,reason string){
	rows,err:=db.Query(context.Background(),`SELECT user_id::text FROM conversation_members WHERE conversation_id=$1`,conversationID);if err!=nil{return};defer rows.Close()
	userIDs:=make([]string,0);for rows.Next(){var userID string;if rows.Scan(&userID)==nil{userIDs=append(userIDs,userID)}}
	for _,userID:=range userIDs{room:="user:"+userID;chatHub.RLock();clients:=make([]*socketClient,0,len(chatHub.rooms[room]));for client:=range chatHub.rooms[room]{clients=append(clients,client)};chatHub.RUnlock();for _,client:=range clients{if client.writeJSON(gin.H{"type":"conversation_update","conversation_id":conversationID,"reason":reason})!=nil{leaveRoom(room,client)}}}
}
