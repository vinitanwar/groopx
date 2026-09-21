package httpapi

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func listConversationMedia(c *gin.Context) {
	conversationID,userID:=c.Param("id"),c.GetString("user_id")
	if !isConversationMember(c,conversationID,userID){c.JSON(http.StatusForbidden,gin.H{"error":"not a conversation member"});return}
	rows,err:=db.Query(c.Request.Context(),`SELECT id::text,kind::text,metadata,created_at FROM messages WHERE conversation_id=$1 AND kind<>'text' AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 200`,conversationID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"shared media could not be loaded"});return}
	defer rows.Close();items:=make([]gin.H,0)
	for rows.Next(){var id,kind string;var metadata []byte;var createdAt time.Time;if rows.Scan(&id,&kind,&metadata,&createdAt)==nil{var attachment map[string]any;if json.Unmarshal(metadata,&attachment)!=nil{attachment=map[string]any{}};items=append(items,gin.H{"id":id,"kind":kind,"attachment":attachment,"created_at":createdAt})}}
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
	command, err := db.Exec(c.Request.Context(), `UPDATE conversation_members SET hidden_at=NOW(),archived_at=NULL WHERE conversation_id=$1 AND user_id=$2`, c.Param("id"), c.GetString("user_id"))
	if err != nil || command.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error":"conversation not found"}); return }
	c.Status(http.StatusNoContent)
}

func updateConversationPreferences(c *gin.Context) {
	var input struct { Favorite *bool `json:"favorite"`; Muted *bool `json:"muted"` }
	if c.ShouldBindJSON(&input) != nil || (input.Favorite == nil && input.Muted == nil) { c.JSON(http.StatusBadRequest,gin.H{"error":"favorite or muted is required"}); return }
	command,err:=db.Exec(c.Request.Context(),`UPDATE conversation_members SET favorite=COALESCE($3::boolean,favorite),muted_until=CASE WHEN $4::boolean IS NULL THEN muted_until WHEN $4 THEN NOW()+INTERVAL '100 years' ELSE NULL END WHERE conversation_id=$1 AND user_id=$2 AND hidden_at IS NULL`,c.Param("id"),c.GetString("user_id"),input.Favorite,input.Muted)
	if err!=nil||command.RowsAffected()==0{c.JSON(http.StatusNotFound,gin.H{"error":"conversation not found"});return}
	c.JSON(http.StatusOK,gin.H{"conversation_id":c.Param("id"),"favorite":input.Favorite,"muted":input.Muted})
}

func editMessage(c *gin.Context) {
	var input struct { Text string `json:"text" binding:"required,max=10000"` }
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Text) == "" { c.JSON(http.StatusBadRequest, gin.H{"error":"message text is required"}); return }
	var conversationID string
	err := db.QueryRow(c.Request.Context(), `UPDATE messages SET body=$3,edited_at=NOW() WHERE id=$1 AND sender_id=$2 AND kind='text' AND deleted_at IS NULL RETURNING conversation_id::text`, c.Param("id"), c.GetString("user_id"), strings.TrimSpace(input.Text)).Scan(&conversationID)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error":"editable message not found"}); return }
	broadcast(conversationID,c.GetString("user_id"),gin.H{"type":"message_update","id":c.Param("id"),"text":strings.TrimSpace(input.Text),"edited":true})
	c.JSON(http.StatusOK, gin.H{"id":c.Param("id"),"text":strings.TrimSpace(input.Text),"edited":true})
}

func deleteMessage(c *gin.Context) {
	var conversationID string
	err := db.QueryRow(c.Request.Context(), `UPDATE messages SET body='',metadata='{}'::jsonb,deleted_at=NOW() WHERE id=$1 AND sender_id=$2 AND deleted_at IS NULL RETURNING conversation_id::text`, c.Param("id"), c.GetString("user_id")).Scan(&conversationID)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error":"message not found"}); return }
	broadcast(conversationID,c.GetString("user_id"),gin.H{"type":"message_delete","id":c.Param("id")})
	c.Status(http.StatusNoContent)
}

func addReaction(c *gin.Context) { setReaction(c, true) }
func removeReaction(c *gin.Context) { setReaction(c, false) }

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
