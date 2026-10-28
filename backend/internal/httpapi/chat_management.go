package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

var sharedURLPattern = regexp.MustCompile(`(?i)https?://[^\s<>"']+`)

func expireConversationMessages(ctx context.Context,conversationID string){
	_,_=db.Exec(ctx,`UPDATE messages SET body='',metadata='{}'::jsonb,deleted_at=NOW() WHERE conversation_id=$1 AND deleted_at IS NULL AND expires_at<=NOW()`,conversationID)
}

func updateDisappearingMessages(c *gin.Context){
	conversationID,userID:=c.Param("id"),c.GetString("user_id")
	var input struct{Seconds int `json:"seconds"`}
	if c.ShouldBindJSON(&input)!=nil || (input.Seconds!=0 && input.Seconds!=86400 && input.Seconds!=604800 && input.Seconds!=7776000){c.JSON(http.StatusBadRequest,gin.H{"error":"timer must be off, 24 hours, 7 days, or 90 days"});return}
	var allowed bool
	err:=db.QueryRow(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM conversations conv JOIN conversation_members cm ON cm.conversation_id=conv.id WHERE conv.id=$1 AND cm.user_id=$2 AND (conv.kind='direct' OR cm.role='admin'))`,conversationID,userID).Scan(&allowed)
	if err!=nil||!allowed{c.JSON(http.StatusForbidden,gin.H{"error":"Only group admins can change this timer"});return}
	if _,err=db.Exec(c.Request.Context(),`UPDATE conversations SET disappearing_seconds=$2,updated_at=NOW() WHERE id=$1`,conversationID,input.Seconds);err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"timer could not be updated"});return}
	broadcast(conversationID,userID,gin.H{"type":"disappearing_update","conversation_id":conversationID,"seconds":input.Seconds})
	c.JSON(http.StatusOK,gin.H{"conversation_id":conversationID,"disappearing_seconds":input.Seconds})
}

func messageInfo(c *gin.Context){
	messageID,userID:=c.Param("id"),c.GetString("user_id")
	var conversationID,body,kind string;var createdAt time.Time
	err:=db.QueryRow(c.Request.Context(),`SELECT conversation_id::text,COALESCE(body,''),kind::text,created_at FROM messages WHERE id=$1 AND sender_id=$2 AND deleted_at IS NULL`,messageID,userID).Scan(&conversationID,&body,&kind,&createdAt)
	if err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"message info is available for your messages only"});return}
	rows,err:=db.Query(c.Request.Context(),`SELECT r.user_id::text,COALESCE(NULLIF(member.group_display_name,''),NULLIF(u.full_name,''),NULLIF(u.username,''),'GroopX member'),COALESCE(u.avatar_url,''),r.delivered_at,r.read_at
		FROM message_receipts r JOIN users u ON u.id=r.user_id
		LEFT JOIN conversation_members member ON member.conversation_id=$2 AND member.user_id=r.user_id
		WHERE r.message_id=$1 ORDER BY COALESCE(r.read_at,r.delivered_at) DESC NULLS LAST`,messageID,conversationID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message info could not be loaded"});return};defer rows.Close()
	recipients:=make([]gin.H,0);for rows.Next(){var id,name,avatar string;var deliveredAt,readAt *time.Time;if rows.Scan(&id,&name,&avatar,&deliveredAt,&readAt)==nil{recipients=append(recipients,gin.H{"user_id":id,"name":name,"avatar_url":avatar,"delivered_at":deliveredAt,"read_at":readAt})}}
	c.JSON(http.StatusOK,gin.H{"id":messageID,"conversation_id":conversationID,"text":body,"kind":kind,"created_at":createdAt,"recipients":recipients})
}

func listConversationMedia(c *gin.Context) {
	conversationID,userID:=c.Param("id"),c.GetString("user_id")
	if !isConversationMember(c,conversationID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a conversation member"});return}
	expireConversationMessages(c.Request.Context(),conversationID)
	rows,err:=db.Query(c.Request.Context(),`SELECT id::text,kind::text,COALESCE(body,''),metadata,created_at FROM messages WHERE conversation_id=$1 AND view_once=FALSE AND (kind NOT IN ('text','contact','poll') OR (kind='text' AND (body ILIKE '%http://%' OR body ILIKE '%https://%'))) AND deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM message_hidden_for hidden WHERE hidden.message_id=messages.id AND hidden.user_id=$2) ORDER BY created_at DESC LIMIT 400`,conversationID,userID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"shared media could not be loaded"});return}
	defer rows.Close();items:=make([]gin.H,0)
	for rows.Next(){
		var id,kind,body string;var metadata []byte;var createdAt time.Time
		if rows.Scan(&id,&kind,&body,&metadata,&createdAt)!=nil{continue}
		if kind!="text"{var attachment map[string]any;if json.Unmarshal(metadata,&attachment)!=nil{attachment=map[string]any{}};items=append(items,gin.H{"id":id,"kind":kind,"attachment":attachment,"created_at":createdAt})}
		seen:=map[string]bool{}
		for index,match:=range sharedURLPattern.FindAllString(body,10){
			link:=strings.TrimRight(match,".,;:!?)]}")
			if link==""||seen[link]{continue};seen[link]=true
			items=append(items,gin.H{"id":id+"-link-"+strconv.Itoa(index),"message_id":id,"kind":"link","attachment":gin.H{"url":link,"file_name":link},"created_at":createdAt})
		}
		if len(items)>=200{break}
	}
	if len(items)>200{items=items[:200]}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func setArchive(archived bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		var commandTag interface{ RowsAffected() int64 }
		var err error
		if archived {
			commandTag, err = db.Exec(c.Request.Context(), `UPDATE conversation_members SET archived_at=NOW() WHERE conversation_id=$1 AND user_id=$2 AND hidden_at IS NULL`, c.Param("id"), c.GetString("user_id"))
		} else {
			commandTag, err = db.Exec(c.Request.Context(), `UPDATE conversation_members SET archived_at=NULL WHERE conversation_id=$1 AND user_id=$2 AND hidden_at IS NULL`, c.Param("id"), c.GetString("user_id"))
		}
		if err != nil || commandTag.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error":"conversation not found"}); return }
		c.JSON(http.StatusOK, gin.H{"conversation_id":c.Param("id"),"archived":archived})
	}
}

func deleteConversation(c *gin.Context) {
	ctx,conversationID,userID:=c.Request.Context(),c.Param("id"),c.GetString("user_id")
	tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"conversation could not be deleted"});return};defer tx.Rollback(ctx)
	locations,err:=stopLiveLocationsInTransaction(ctx,tx,conversationID,userID)
	var affected int64
	if err==nil{command,updateErr:=tx.Exec(ctx,`UPDATE conversation_members SET hidden_at=NOW(),archived_at=NULL WHERE conversation_id=$1 AND user_id=$2`,conversationID,userID);err=updateErr;affected=command.RowsAffected()}
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"conversation could not be deleted"});return}
	if affected==0{c.JSON(http.StatusNotFound,gin.H{"error":"conversation not found"});return}
	if tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"conversation could not be deleted"});return}
	for _,location:=range locations{broadcastLiveLocation(location)}
	c.Status(http.StatusNoContent)
}

func clearConversation(c *gin.Context){
	conversationID,userID:=c.Param("id"),c.GetString("user_id")
	if !isConversationMember(c,conversationID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a conversation member"});return}
	tx,err:=db.Begin(c.Request.Context());if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"chat could not be cleared"});return};defer tx.Rollback(c.Request.Context())
	locations,err:=stopLiveLocationsInTransaction(c.Request.Context(),tx,conversationID,userID)
	if err==nil{_,err=tx.Exec(c.Request.Context(),`INSERT INTO message_hidden_for(message_id,user_id) SELECT id,$2 FROM messages WHERE conversation_id=$1 AND deleted_at IS NULL ON CONFLICT DO NOTHING`,conversationID,userID)}
	if err==nil{_,err=tx.Exec(c.Request.Context(),`UPDATE conversation_members SET last_read_message_id=NULL,last_read_at=NOW(),manual_unread=FALSE WHERE conversation_id=$1 AND user_id=$2`,conversationID,userID)}
	if err!=nil||tx.Commit(c.Request.Context())!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"chat could not be cleared"});return}
	for _,location:=range locations{broadcastLiveLocation(location)}
	c.Status(http.StatusNoContent)
}

func updateConversationPreferences(c *gin.Context) {
	var input struct { Favorite *bool `json:"favorite"`; Pinned *bool `json:"pinned"`; Muted *bool `json:"muted"`; MuteSeconds *int `json:"mute_seconds"` }
	if c.ShouldBindJSON(&input) != nil || (input.Favorite == nil && input.Pinned == nil && input.Muted == nil && input.MuteSeconds == nil) { c.JSON(http.StatusBadRequest,gin.H{"error":"favorite, pinned, or mute setting is required"}); return }
	if input.MuteSeconds!=nil&&*input.MuteSeconds!=0&&*input.MuteSeconds!=28800&&*input.MuteSeconds!=604800&&*input.MuteSeconds!=-1{c.JSON(http.StatusBadRequest,gin.H{"error":"mute duration must be 8 hours, 1 week, always, or off"});return}
	command,err:=db.Exec(c.Request.Context(),`UPDATE conversation_members SET favorite=COALESCE($3::boolean,favorite),pinned_at=CASE WHEN $6::boolean IS NULL THEN pinned_at WHEN $6 THEN NOW() ELSE NULL END,muted_until=CASE WHEN $5::int IS NOT NULL THEN CASE WHEN $5=0 THEN NULL WHEN $5=-1 THEN NOW()+INTERVAL '100 years' ELSE NOW()+($5*INTERVAL '1 second') END WHEN $4::boolean IS NULL THEN muted_until WHEN $4 THEN NOW()+INTERVAL '100 years' ELSE NULL END WHERE conversation_id=$1 AND user_id=$2 AND hidden_at IS NULL`,c.Param("id"),c.GetString("user_id"),input.Favorite,input.Muted,input.MuteSeconds,input.Pinned)
	if err!=nil||command.RowsAffected()==0{c.JSON(http.StatusNotFound,gin.H{"error":"conversation not found"});return}
	c.JSON(http.StatusOK,gin.H{"conversation_id":c.Param("id"),"favorite":input.Favorite,"pinned":input.Pinned,"muted":input.Muted,"mute_seconds":input.MuteSeconds})
}

func editMessage(c *gin.Context) {
	var input struct { Text string `json:"text" binding:"required,max=10000"` }
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Text) == "" { c.JSON(http.StatusBadRequest, gin.H{"error":"message text is required"}); return }
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"message could not be updated"}); return }
	defer tx.Rollback(ctx)
	var conversationID string
	userID:=c.GetString("user_id")
	err = tx.QueryRow(ctx, `SELECT conversation_id::text FROM messages WHERE id=$1 AND sender_id=$2 AND kind='text' AND deleted_at IS NULL FOR UPDATE`, c.Param("id"), userID).Scan(&conversationID)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error":"editable message not found"}); return }
	allowed,err:=conversationAllowsSender(ctx,tx,conversationID,userID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be updated"});return}
	if !allowed{c.JSON(http.StatusForbidden,gin.H{"error":announcementOnlyMessage});return}
	if _,err=tx.Exec(ctx,`UPDATE messages SET body=$3,edited_at=NOW() WHERE id=$1 AND sender_id=$2`,c.Param("id"),userID,strings.TrimSpace(input.Text));err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"message could not be updated"});return}
	if _, err = tx.Exec(ctx, `DELETE FROM message_mentions WHERE message_id=$1`, c.Param("id")); err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"message could not be updated"}); return }
	if tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"message could not be updated"}); return }
	broadcast(conversationID,userID,gin.H{"type":"message_update","id":c.Param("id"),"text":strings.TrimSpace(input.Text),"edited":true})
	c.JSON(http.StatusOK, gin.H{"id":c.Param("id"),"text":strings.TrimSpace(input.Text),"edited":true})
}

func deleteMessage(c *gin.Context) {
	if c.Query("scope")=="me"{
		result,err:=db.Exec(c.Request.Context(),`INSERT INTO message_hidden_for(message_id,user_id) SELECT m.id,$2 FROM messages m JOIN conversation_members cm ON cm.conversation_id=m.conversation_id AND cm.user_id=$2 WHERE m.id=$1 AND m.deleted_at IS NULL ON CONFLICT DO NOTHING`,c.Param("id"),c.GetString("user_id"))
		if err!=nil||result.RowsAffected()==0{var exists bool;_ = db.QueryRow(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM message_hidden_for WHERE message_id=$1 AND user_id=$2)`,c.Param("id"),c.GetString("user_id")).Scan(&exists);if !exists{c.JSON(http.StatusNotFound,gin.H{"error":"message not found"});return}}
		c.Status(http.StatusNoContent);return
	}
	stopLiveLocationForMessage(c.Request.Context(), c.Param("id"), c.GetString("user_id"))
	var conversationID string
	err := db.QueryRow(c.Request.Context(), `UPDATE messages SET body='',metadata='{}'::jsonb,deleted_at=NOW() WHERE id=$1 AND sender_id=$2 AND deleted_at IS NULL RETURNING conversation_id::text`, c.Param("id"), c.GetString("user_id")).Scan(&conversationID)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error":"message not found"}); return }
	_, _ = db.Exec(c.Request.Context(), `DELETE FROM message_pins WHERE message_id=$1`, c.Param("id"))
	broadcast(conversationID,c.GetString("user_id"),gin.H{"type":"message_delete","id":c.Param("id")})
	c.Status(http.StatusNoContent)
}

func addReaction(c *gin.Context) { setReaction(c, true) }
func removeReaction(c *gin.Context) { setReaction(c, false) }

func listMessageReactions(c *gin.Context) {
	messageID,userID:=c.Param("id"),c.GetString("user_id")
	var allowed bool
	err:=db.QueryRow(c.Request.Context(),`SELECT EXISTS(
		SELECT 1 FROM messages m
		JOIN conversation_members cm ON cm.conversation_id=m.conversation_id AND cm.user_id=$2 AND cm.hidden_at IS NULL
		WHERE m.id=$1 AND m.deleted_at IS NULL
		AND NOT EXISTS(SELECT 1 FROM message_hidden_for hidden WHERE hidden.message_id=m.id AND hidden.user_id=$2)
	)`,messageID,userID).Scan(&allowed)
	if err!=nil||!allowed{c.JSON(http.StatusNotFound,gin.H{"error":"message not found"});return}
	rows,err:=db.Query(c.Request.Context(),`SELECT reaction.emoji,reaction.user_id::text,
		COALESCE(NULLIF(group_member.group_display_name,''),NULLIF(member.full_name,''),NULLIF(member.username,''),'GroopX member'),
		COALESCE(member.avatar_url,''),reaction.created_at
		FROM message_reactions reaction
		JOIN messages message ON message.id=reaction.message_id
		JOIN users member ON member.id=reaction.user_id
		LEFT JOIN conversation_members group_member ON group_member.conversation_id=message.conversation_id AND group_member.user_id=reaction.user_id
		WHERE reaction.message_id=$1 ORDER BY reaction.created_at DESC`,messageID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"reactions could not be loaded"});return}
	defer rows.Close()
	items:=make([]gin.H,0)
	for rows.Next(){var emoji,reactionUserID,name,avatar string;var createdAt time.Time;if rows.Scan(&emoji,&reactionUserID,&name,&avatar,&createdAt)==nil{items=append(items,gin.H{"emoji":emoji,"user_id":reactionUserID,"name":name,"avatar_url":avatar,"mine":reactionUserID==userID,"created_at":createdAt})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func setReaction(c *gin.Context, add bool) {
	var input struct { Emoji string `json:"emoji" binding:"required,max=16"` }
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Emoji) == "" { c.JSON(http.StatusBadRequest, gin.H{"error":"emoji is required"}); return }
	var conversationID string
	err := db.QueryRow(c.Request.Context(), `SELECT conversation_id::text FROM messages WHERE id=$1 AND deleted_at IS NULL AND EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id=messages.conversation_id AND user_id=$2)`, c.Param("id"), c.GetString("user_id")).Scan(&conversationID)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error":"message not found"}); return }
	if add { _,err=db.Exec(c.Request.Context(),`INSERT INTO message_reactions(message_id,user_id,emoji) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`,c.Param("id"),c.GetString("user_id"),input.Emoji) } else { _,err=db.Exec(c.Request.Context(),`DELETE FROM message_reactions WHERE message_id=$1 AND user_id=$2 AND emoji=$3`,c.Param("id"),c.GetString("user_id"),input.Emoji) }
	if err != nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"reaction could not be updated"}); return }
	broadcast(conversationID,c.GetString("user_id"),gin.H{"type":"reaction","message_id":c.Param("id"),"emoji":input.Emoji,"added":add})
	c.JSON(http.StatusOK,gin.H{"message_id":c.Param("id"),"emoji":input.Emoji,"added":add})
}
