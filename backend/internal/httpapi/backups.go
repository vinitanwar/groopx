package httpapi

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func getLatestBackup(c *gin.Context) {
	var id string; var createdAt time.Time; var conversations, messages int
	err := db.QueryRow(c.Request.Context(), `SELECT id::text,created_at,conversation_count,message_count FROM chat_backups WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1`, c.GetString("user_id")).Scan(&id,&createdAt,&conversations,&messages)
	if err != nil { c.JSON(http.StatusOK,gin.H{"backup":nil,"automatic":true}); return }
	c.JSON(http.StatusOK,gin.H{"automatic":true,"backup":gin.H{"id":id,"created_at":createdAt,"conversation_count":conversations,"message_count":messages}})
}

func createBackup(c *gin.Context) {
	userID := c.GetString("user_id")
	var conversationsJSON, messagesJSON []byte; var conversations, messages int
	err := db.QueryRow(c.Request.Context(), `SELECT COALESCE(jsonb_agg(jsonb_build_object('id',cv.id,'kind',cv.kind,'title',cv.title,'avatar_url',cv.avatar_url,'created_at',cv.created_at)),'[]'::jsonb),COUNT(*)::int FROM conversations cv JOIN conversation_members cm ON cm.conversation_id=cv.id WHERE cm.user_id=$1 AND cv.deleted_at IS NULL`,userID).Scan(&conversationsJSON,&conversations)
	if err == nil { err = db.QueryRow(c.Request.Context(), `SELECT COALESCE(jsonb_agg(jsonb_build_object('id',m.id,'conversation_id',m.conversation_id,'sender_id',m.sender_id,'kind',m.kind,'body',m.body,'metadata',m.metadata,'status',m.status,'created_at',m.created_at) ORDER BY m.created_at),'[]'::jsonb),COUNT(*)::int FROM messages m JOIN conversation_members cm ON cm.conversation_id=m.conversation_id WHERE cm.user_id=$1 AND m.deleted_at IS NULL`,userID).Scan(&messagesJSON,&messages) }
	if err != nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"backup could not be created"}); return }
	var conversationItems, messageItems any; _=json.Unmarshal(conversationsJSON,&conversationItems); _=json.Unmarshal(messagesJSON,&messageItems)
	payload,_:=json.Marshal(gin.H{"version":1,"user_id":userID,"conversations":conversationItems,"messages":messageItems,"created_at":time.Now().UTC()})
	var id string; var createdAt time.Time
	err=db.QueryRow(c.Request.Context(),`INSERT INTO chat_backups(user_id,payload,conversation_count,message_count) VALUES($1,$2,$3,$4) RETURNING id::text,created_at`,userID,payload,conversations,messages).Scan(&id,&createdAt)
	if err != nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"backup could not be saved"}); return }
	_,_=db.Exec(c.Request.Context(),`DELETE FROM chat_backups WHERE user_id=$1 AND id NOT IN (SELECT id FROM chat_backups WHERE user_id=$1 ORDER BY created_at DESC LIMIT 5)`,userID)
	c.JSON(http.StatusCreated,gin.H{"backup":gin.H{"id":id,"created_at":createdAt,"conversation_count":conversations,"message_count":messages}})
}

func restoreBackup(c *gin.Context) {
	userID:=c.GetString("user_id"); var exists bool
	_ = db.QueryRow(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM chat_backups WHERE id=$1 AND user_id=$2)`,c.Param("id"),userID).Scan(&exists)
	if !exists { c.JSON(http.StatusNotFound,gin.H{"error":"backup not found"}); return }
	// Server data is authoritative; restoring makes all backed-up conversations visible again.
	_,err:=db.Exec(c.Request.Context(),`UPDATE conversation_members SET hidden_at=NULL WHERE user_id=$1 AND conversation_id IN (SELECT (item->>'id')::uuid FROM chat_backups b CROSS JOIN LATERAL jsonb_array_elements(b.payload->'conversations') item WHERE b.id=$2 AND b.user_id=$1)`,userID,c.Param("id"))
	if err!=nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"backup could not be restored"}); return }
	c.JSON(http.StatusOK,gin.H{"message":"backup restored"})
}
