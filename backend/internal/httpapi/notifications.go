package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func registerDevice(c *gin.Context) {
	var input struct { Token string `json:"token" binding:"required,max=4096"`; Platform string `json:"platform" binding:"required,oneof=android ios web"` }
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Token) == "" { c.JSON(http.StatusBadRequest, gin.H{"error":"invalid device"}); return }
	var id string
	err := db.QueryRow(c.Request.Context(), `INSERT INTO user_devices(user_id,platform,push_token) VALUES($1,$2,$3)
		ON CONFLICT(push_token) DO UPDATE SET user_id=EXCLUDED.user_id,platform=EXCLUDED.platform,last_seen_at=NOW() RETURNING id::text`, c.GetString("user_id"), input.Platform, strings.TrimSpace(input.Token)).Scan(&id)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"device could not be registered"}); return }
	c.JSON(http.StatusCreated, gin.H{"id":id,"registered":true,"platform":input.Platform})
}

func unregisterDevice(c *gin.Context) {
	var input struct { Token string `json:"token" binding:"required"` }
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest,gin.H{"error":"token is required"}); return }
	_, _ = db.Exec(c.Request.Context(), `DELETE FROM user_devices WHERE user_id=$1 AND push_token=$2`, c.GetString("user_id"), input.Token)
	c.Status(http.StatusNoContent)
}

func listNotifications(c *gin.Context) {
	rows,err:=db.Query(c.Request.Context(),`SELECT id::text,type,title,body,data,read_at,created_at FROM notifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100`,c.GetString("user_id"))
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"notifications could not be loaded"});return};defer rows.Close()
	items:=make([]gin.H,0);unread:=0
	for rows.Next(){var id,kind,title,body string;var data []byte;var readAt *time.Time;var createdAt time.Time;if rows.Scan(&id,&kind,&title,&body,&data,&readAt,&createdAt)!=nil{continue};var payload map[string]any;_ = json.Unmarshal(data,&payload);if readAt==nil{unread++};items=append(items,gin.H{"id":id,"type":kind,"title":title,"body":body,"data":payload,"read":readAt!=nil,"created_at":createdAt})}
	c.JSON(http.StatusOK,gin.H{"items":items,"unread":unread})
}

func markNotificationRead(c *gin.Context){command,err:=db.Exec(c.Request.Context(),`UPDATE notifications SET read_at=COALESCE(read_at,NOW()) WHERE id=$1 AND user_id=$2`,c.Param("id"),c.GetString("user_id"));if err!=nil||command.RowsAffected()==0{c.JSON(http.StatusNotFound,gin.H{"error":"notification not found"});return};c.Status(http.StatusNoContent)}
func markAllNotificationsRead(c *gin.Context){_,err:=db.Exec(c.Request.Context(),`UPDATE notifications SET read_at=COALESCE(read_at,NOW()) WHERE user_id=$1 AND read_at IS NULL`,c.GetString("user_id"));if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"notifications could not be updated"});return};c.Status(http.StatusNoContent)}

func notifyConversation(conversationID,senderID,kind,title,body string,data map[string]any){payload,_:=json.Marshal(data);_,_=db.Exec(context.Background(),`INSERT INTO notifications(user_id,type,title,body,data) SELECT user_id,$3,$4,$5,$6 FROM conversation_members WHERE conversation_id=$1 AND user_id<>$2 AND hidden_at IS NULL`,conversationID,senderID,kind,title,body,payload);go sendConversationPush(conversationID,senderID,kind,title,body,data)}
