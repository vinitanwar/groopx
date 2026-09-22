package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

func sendMessage(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		Text      string `json:"text" binding:"required,max=10000"`
		ReplyToID string `json:"reply_to_id"`
	}
	input.Text = ""
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Text) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message text is required"})
		return
	}
	if !isConversationMember(c, conversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"})
		return
	}
	var otherID string
	if db.QueryRow(c.Request.Context(), `SELECT cm.user_id::text FROM conversations cv JOIN conversation_members cm ON cm.conversation_id=cv.id AND cm.user_id<>$2 WHERE cv.id=$1 AND cv.kind='direct' LIMIT 1`, conversationID, userID).Scan(&otherID) == nil && usersBlocked(userID, otherID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "communication is blocked"})
		return
	}
	var reply gin.H
	if input.ReplyToID != "" {
		var replyText, replySenderID string
		if db.QueryRow(c.Request.Context(), `SELECT body,COALESCE(sender_id::text,'') FROM messages WHERE id=$1 AND conversation_id=$2 AND deleted_at IS NULL`, input.ReplyToID, conversationID).Scan(&replyText, &replySenderID) != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "reply target is unavailable"})
			return
		}
		reply = gin.H{"id": input.ReplyToID, "text": replyText, "sender_id": replySenderID, "mine": replySenderID == userID}
	}
	status := "sent"
	if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) {
		status = "delivered"
	}
	var id string
	var createdAt time.Time
	err := db.QueryRow(c.Request.Context(), `INSERT INTO messages(conversation_id,sender_id,body,status,reply_to_id) VALUES($1,$2,$3,$4,NULLIF($5,'')::uuid) RETURNING id::text,created_at`, conversationID, userID, strings.TrimSpace(input.Text), status, input.ReplyToID).Scan(&id, &createdAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be saved"})
		return
	}
	_, _ = db.Exec(c.Request.Context(), `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, createdAt)
	_, _ = db.Exec(c.Request.Context(), `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID)
	payload := gin.H{"type": "message", "id": id, "conversation_id": conversationID, "sender_id": userID, "text": strings.TrimSpace(input.Text), "kind": "text", "status": status, "created_at": createdAt, "reply": reply}
	broadcast(conversationID, userID, payload)
	notifyConversation(conversationID, userID, "message", "New message", strings.TrimSpace(input.Text), map[string]any{"conversation_id": conversationID, "message_id": id})
	payload["mine"] = true
	c.JSON(http.StatusCreated, payload)
}

func sendLocationMessage(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		Latitude  float64 `json:"latitude" binding:"required,gte=-90,lte=90"`
		Longitude float64 `json:"longitude" binding:"required,gte=-180,lte=180"`
		Label     string  `json:"label" binding:"omitempty,max=180"`
	}
	if c.ShouldBindJSON(&input) != nil || !isConversationMember(c, conversationID, userID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid location is required"})
		return
	}
	label := strings.TrimSpace(input.Label)
	if label == "" { label = "Shared location" }
	metadata, _ := json.Marshal(gin.H{"latitude": input.Latitude, "longitude": input.Longitude, "label": label, "map_url": "https://www.google.com/maps/search/?api=1&query=" + strings.ReplaceAll(strings.TrimSpace(strings.Join([]string{formatCoordinate(input.Latitude), formatCoordinate(input.Longitude)}, ",")), " ", "")})
	status := "sent"
	if isConversationPeerOnline(conversationID, userID) { status = "delivered" }
	var id string; var createdAt time.Time
	if db.QueryRow(c.Request.Context(), `INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status) VALUES($1,$2,'location',$3,$4,$5) RETURNING id::text,created_at`, conversationID, userID, label, metadata, status).Scan(&id, &createdAt) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "location could not be sent"}); return
	}
	payload := gin.H{"type":"message","id":id,"conversation_id":conversationID,"sender_id":userID,"text":label,"kind":"location","attachment":json.RawMessage(metadata),"status":status,"created_at":createdAt}
	broadcast(conversationID,userID,payload)
	notifyConversation(conversationID,userID,"location","Location shared",label,map[string]any{"conversation_id":conversationID,"message_id":id})
	payload["mine"] = true; c.JSON(http.StatusCreated,payload)
}

func formatCoordinate(value float64) string { return strconv.FormatFloat(value, 'f', 6, 64) }

func isConversationPeerOnline(conversationID, senderID string) bool {
	rows, err := db.Query(context.Background(), `SELECT user_id::text FROM conversation_members WHERE conversation_id=$1 AND user_id<>$2`, conversationID, senderID)
	if err != nil { return false }
	defer rows.Close()
	for rows.Next() { var userID string; if rows.Scan(&userID) == nil && isUserOnline(userID) { return true } }
	return false
}
