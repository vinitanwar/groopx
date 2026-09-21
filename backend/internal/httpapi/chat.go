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
	archived := c.Query("archived") == "true"
	rows, err := db.Query(c.Request.Context(), `
		SELECT c.id::text, c.kind::text,
			COALESCE(c.title, other.full_name, other.phone, 'Conversation') AS title,
			COALESCE(c.avatar_url, other.avatar_url),
			COALESCE(last_message.body, ''), last_message.created_at,
			COUNT(unread.id)::int,mine.favorite,mine.archived_at,mine.muted_until
		FROM conversation_members mine
		JOIN conversations c ON c.id=mine.conversation_id
		LEFT JOIN conversation_members other_member ON c.kind='direct' AND other_member.conversation_id=c.id AND other_member.user_id<>mine.user_id
		LEFT JOIN users other ON other.id=other_member.user_id
		LEFT JOIN LATERAL (
			SELECT m.body, m.created_at FROM messages m
			WHERE m.conversation_id=c.id AND m.deleted_at IS NULL ORDER BY m.created_at DESC LIMIT 1
		) last_message ON TRUE
		LEFT JOIN messages last_read ON last_read.id=mine.last_read_message_id
		LEFT JOIN messages unread ON unread.conversation_id=c.id AND unread.sender_id<>mine.user_id
			AND unread.deleted_at IS NULL AND unread.created_at>COALESCE(last_read.created_at, mine.joined_at)
		WHERE mine.user_id=$1 AND (($2=TRUE AND mine.archived_at IS NOT NULL) OR ($2=FALSE AND mine.archived_at IS NULL)) AND mine.hidden_at IS NULL
		GROUP BY c.id, other.full_name, other.phone, other.avatar_url, last_message.body, last_message.created_at,mine.favorite,mine.archived_at,mine.muted_until
		ORDER BY mine.favorite DESC,COALESCE(last_message.created_at, c.created_at) DESC`, userID, archived)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "conversations could not be loaded"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, kind, title, preview string
		var avatar *string
		var lastAt *time.Time
		var unread int; var favorite bool; var archivedAt, mutedUntil *time.Time
		if rows.Scan(&id, &kind, &title, &avatar, &preview, &lastAt, &unread, &favorite, &archivedAt, &mutedUntil) != nil { continue }
		items = append(items, gin.H{"id": id, "kind": kind, "title": title, "avatar_url": avatar, "preview": preview, "last_message_at": lastAt, "unread": unread, "favorite":favorite, "archived":archivedAt!=nil, "muted":mutedUntil!=nil && mutedUntil.After(time.Now())})
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
	err := db.QueryRow(c.Request.Context(), `SELECT c.kind::text, COALESCE(c.title,other.full_name,other.phone,'Conversation'),
		COALESCE(c.avatar_url,other.avatar_url),other.id::text,other.show_online_status,other.last_seen_at,
		(SELECT COUNT(*)::int FROM conversation_members cm WHERE cm.conversation_id=c.id),
		COALESCE(EXISTS(SELECT 1 FROM user_blocks b WHERE b.blocker_id=$2 AND b.blocked_id=other.id),FALSE),
		COALESCE(EXISTS(SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$2 AND b.blocked_id=other.id) OR (b.blocker_id=other.id AND b.blocked_id=$2)),FALSE)
		FROM conversations c JOIN conversation_members mine ON mine.conversation_id=c.id AND mine.user_id=$2
		LEFT JOIN conversation_members om ON c.kind='direct' AND om.conversation_id=c.id AND om.user_id<>$2
		LEFT JOIN users other ON other.id=om.user_id WHERE c.id=$1`, conversationID, userID).Scan(&kind, &title, &avatar, &otherID, &showOnline, &lastSeen, &memberCount, &blockedByMe, &communicationBlocked)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error": "conversation not found"}); return }
	response := gin.H{"id":conversationID,"kind":kind,"title":title,"avatar_url":avatar,"member_count":memberCount,"online":false,"other_user_id":otherID,"blocked_by_me":blockedByMe,"communication_blocked":communicationBlocked}
	if kind == "direct" && otherID != nil && showOnline != nil && *showOnline {
		response["online"] = isUserOnline(*otherID)
		response["last_seen_at"] = lastSeen
	}
	c.JSON(http.StatusOK, response)
}

func listMessages(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	if !isConversationMember(c, conversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return }
	beforeTime, beforeID := time.Now().Add(time.Second), "ffffffff-ffff-ffff-ffff-ffffffffffff"
	if raw := c.Query("before"); raw != "" {
		decoded, err := base64.RawURLEncoding.DecodeString(raw)
		parts := strings.SplitN(string(decoded), "|", 2)
		if err != nil || len(parts) != 2 { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid message cursor"}); return }
		beforeTime, err = time.Parse(time.RFC3339Nano,parts[0]); if err != nil { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid message cursor"}); return }; beforeID=parts[1]
	}
	rows, err := db.Query(c.Request.Context(), `SELECT messages.id::text, COALESCE(messages.sender_id::text,''), messages.body, messages.kind::text, messages.metadata, messages.status::text, messages.created_at, messages.edited_at,
		COALESCE((SELECT jsonb_agg(jsonb_build_object('emoji',reaction.emoji,'count',reaction.total,'mine',reaction.mine)) FROM
			(SELECT emoji,COUNT(*)::int total,BOOL_OR(user_id=$2) mine FROM message_reactions WHERE message_id=messages.id GROUP BY emoji) reaction),'[]'::jsonb),
		messages.reply_to_id::text, reply.body, COALESCE(reply.sender_id::text,'')
		FROM messages LEFT JOIN messages reply ON reply.id=messages.reply_to_id
		WHERE messages.conversation_id=$1 AND messages.deleted_at IS NULL AND (messages.created_at,messages.id)<($3,$4::uuid)
		ORDER BY messages.created_at DESC,messages.id DESC LIMIT 50`, conversationID, userID, beforeTime, beforeID)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "messages could not be loaded"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	var oldestTime time.Time; var oldestID string
	for rows.Next() {
		var id, senderID, body, kind, status string; var metadata, reactions []byte; var createdAt time.Time; var editedAt *time.Time
		var replyID, replyText, replySenderID *string
		if rows.Scan(&id, &senderID, &body, &kind, &metadata, &status, &createdAt, &editedAt, &reactions, &replyID, &replyText, &replySenderID) != nil { continue }
		var reactionItems []map[string]any; _ = json.Unmarshal(reactions, &reactionItems)
		item := gin.H{"id": id, "sender_id": senderID, "text": body, "kind": kind, "status": status, "created_at": createdAt, "mine": senderID == userID, "edited": editedAt != nil, "reactions": reactionItems}
		if replyID != nil { item["reply"] = gin.H{"id":*replyID,"text":replyText,"sender_id":replySenderID,"mine":replySenderID != nil && *replySenderID == userID} }
		if kind != "text" { var attachment map[string]any; if json.Unmarshal(metadata, &attachment) == nil { item["attachment"] = attachment } }
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
	if len([]rune(query))<2 { c.JSON(http.StatusOK,gin.H{"items":[]gin.H{}});return }
	rows,err:=db.Query(c.Request.Context(),`SELECT id::text,COALESCE(sender_id::text,''),body,kind::text,status::text,created_at,edited_at FROM messages
		WHERE conversation_id=$1 AND deleted_at IS NULL AND body ILIKE $2 ORDER BY created_at DESC LIMIT 50`,conversationID,"%"+query+"%")
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message search unavailable"});return};defer rows.Close();items:=make([]gin.H,0)
	for rows.Next(){var id,senderID,body,kind,status string;var createdAt time.Time;var editedAt *time.Time;if rows.Scan(&id,&senderID,&body,&kind,&status,&createdAt,&editedAt)==nil{items=append(items,gin.H{"id":id,"sender_id":senderID,"text":body,"kind":kind,"status":status,"created_at":createdAt,"mine":senderID==userID,"edited":editedAt!=nil})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func markConversationRead(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	if !isConversationMember(c, conversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return }
	var messageID string
	err := db.QueryRow(c.Request.Context(), `SELECT id::text FROM messages WHERE conversation_id=$1 AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1`, conversationID).Scan(&messageID)
	if err == nil {
		_, _ = db.Exec(c.Request.Context(), `UPDATE conversation_members SET last_read_message_id=$3 WHERE conversation_id=$1 AND user_id=$2`, conversationID, userID, messageID)
		var receipts bool
		_ = db.QueryRow(c.Request.Context(), `SELECT read_receipts FROM users WHERE id=$1`, userID).Scan(&receipts)
		if receipts {
			_, _ = db.Exec(c.Request.Context(), `UPDATE messages SET status='read' WHERE conversation_id=$1 AND sender_id<>$2 AND status<>'read'`, conversationID, userID)
			broadcast(conversationID, userID, gin.H{"type":"read_receipt","conversation_id":conversationID})
		}
	}
	c.Status(http.StatusNoContent)
}

func chatSocket(c *gin.Context) {
	conversationID := c.Query("conversation_id")
	userID, err := parseAccessToken(c.Query("access_token"))
	if err != nil || conversationID == "" { c.JSON(http.StatusUnauthorized, gin.H{"error": "valid session and conversation are required"}); return }
	if !isConversationMember(c, conversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return }
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil); if err != nil { return }
	client := &socketClient{connection: conn, userID: userID}
	joinRoom(conversationID, client)
	announcePresence(conversationID, userID, true)
	defer func() {
		broadcast(conversationID,userID,gin.H{"type":"typing","user_id":userID,"typing":false})
		leaveRoom(conversationID, client)
		stillOnline := isUserOnline(userID)
		if !stillOnline { _, _ = db.Exec(context.Background(), `UPDATE users SET last_seen_at=NOW() WHERE id=$1`, userID) }
		announcePresence(conversationID, userID, stillOnline)
		conn.Close()
	}()
	for {
		_, data, err := conn.ReadMessage(); if err != nil { return }
		var input struct { Type string `json:"type"`; Text string `json:"text"`; ReplyToID string `json:"reply_to_id"`; Typing bool `json:"typing"` }
		if json.Unmarshal(data, &input) != nil { continue }
		var otherID string
		if db.QueryRow(c.Request.Context(),`SELECT cm.user_id::text FROM conversations c JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id<>$2 WHERE c.id=$1 AND c.kind='direct' LIMIT 1`,conversationID,userID).Scan(&otherID)==nil && usersBlocked(userID,otherID) { _ = client.writeJSON(gin.H{"type":"error","error":"communication is blocked"}); continue }
		if input.Type == "typing" { broadcast(conversationID,userID,gin.H{"type":"typing","user_id":userID,"typing":input.Typing}); continue }
		if strings.TrimSpace(input.Text) == "" { continue }
		status := "sent"
		if onlineRecipients(conversationID, userID) > 0 { status = "delivered" }
		var reply gin.H
		if input.ReplyToID != "" {
			var replyText, replySenderID string
			if db.QueryRow(c.Request.Context(),`SELECT body,COALESCE(sender_id::text,'') FROM messages WHERE id=$1 AND conversation_id=$2 AND deleted_at IS NULL`,input.ReplyToID,conversationID).Scan(&replyText,&replySenderID)!=nil { _ = client.writeJSON(gin.H{"type":"error","error":"reply target is unavailable"}); continue }
			reply=gin.H{"id":input.ReplyToID,"text":replyText,"sender_id":replySenderID,"mine":replySenderID==userID}
		}
		var id string; var createdAt time.Time
		err = db.QueryRow(c.Request.Context(), `INSERT INTO messages(conversation_id,sender_id,body,status,reply_to_id) VALUES($1,$2,$3,$4,NULLIF($5,'')::uuid) RETURNING id::text, created_at`, conversationID, userID, strings.TrimSpace(input.Text), status, input.ReplyToID).Scan(&id, &createdAt)
		if err != nil { _ = client.writeJSON(gin.H{"type":"error", "error":"message could not be saved"}); continue }
		_, _ = db.Exec(c.Request.Context(), `UPDATE conversations SET last_message_at=$2, updated_at=NOW() WHERE id=$1`, conversationID, createdAt)
		_, _ = db.Exec(c.Request.Context(), `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID)
		broadcast(conversationID, userID, gin.H{"type":"message", "id":id, "conversation_id":conversationID, "sender_id":userID, "text":strings.TrimSpace(input.Text), "kind":"text", "status":status, "created_at":createdAt, "reply":reply})
		notifyConversation(conversationID,userID,"message","New message",strings.TrimSpace(input.Text),map[string]any{"conversation_id":conversationID,"message_id":id})
	}
}

func isConversationMember(c *gin.Context, conversationID, userID string) bool {
	var exists bool
	err := db.QueryRow(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2)`, conversationID, userID).Scan(&exists)
	return err == nil && exists
}

func joinRoom(room string, client *socketClient) { chatHub.Lock(); defer chatHub.Unlock(); if chatHub.rooms[room] == nil { chatHub.rooms[room] = make(map[*socketClient]struct{}) }; chatHub.rooms[room][client] = struct{}{} }
func leaveRoom(room string, client *socketClient) { chatHub.Lock(); defer chatHub.Unlock(); delete(chatHub.rooms[room], client); if len(chatHub.rooms[room]) == 0 { delete(chatHub.rooms, room) } }
func onlineRecipients(room, senderID string) int { chatHub.RLock(); defer chatHub.RUnlock(); count := 0; for client := range chatHub.rooms[room] { if client.userID != senderID { count++ } }; return count }
func isUserOnline(userID string) bool { chatHub.RLock(); defer chatHub.RUnlock(); for _, clients := range chatHub.rooms { for client := range clients { if client.userID == userID { return true } } }; return false }
func announcePresence(room, userID string, online bool) {
	var visible bool
	if db.QueryRow(context.Background(), `SELECT show_online_status FROM users WHERE id=$1`, userID).Scan(&visible) != nil || !visible { return }
	broadcast(room, userID, gin.H{"type":"presence","user_id":userID,"online":online,"at":time.Now()})
}
func broadcast(room, senderID string, payload gin.H) {
	chatHub.RLock(); clients := make([]*socketClient, 0, len(chatHub.rooms[room])); for client := range chatHub.rooms[room] { clients = append(clients, client) }; chatHub.RUnlock()
	for _, client := range clients { message := gin.H{}; for key, value := range payload { message[key] = value }; message["mine"] = client.userID == senderID; if client.writeJSON(message) != nil { leaveRoom(room, client) } }
}
