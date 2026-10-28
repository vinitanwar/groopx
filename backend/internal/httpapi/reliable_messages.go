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
		Text            string `json:"text" binding:"required,max=10000"`
		ReplyToID       string `json:"reply_to_id"`
		ClientMessageID string `json:"client_message_id" binding:"omitempty,max=80"`
		MentionUserIDs  []string `json:"mention_user_ids" binding:"omitempty,max=20,dive,uuid"`
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
	if !requireConversationSender(c, conversationID, userID) { return }
	var otherID string
	if db.QueryRow(c.Request.Context(), `SELECT cm.user_id::text FROM conversations cv JOIN conversation_members cm ON cm.conversation_id=cv.id AND cm.user_id<>$2 WHERE cv.id=$1 AND cv.kind='direct' LIMIT 1`, conversationID, userID).Scan(&otherID) == nil && usersBlocked(userID, otherID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "communication is blocked"})
		return
	}
	text := strings.TrimSpace(input.Text)
	mentions, mentionErr := validateMessageMentions(c.Request.Context(), conversationID, userID, text, input.MentionUserIDs)
	if mentionErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": errInvalidMessageMentions.Error()})
		return
	}
	var reply gin.H
	if input.ReplyToID != "" {
		var replyText, replySenderID,replySenderName string
		if db.QueryRow(c.Request.Context(), `SELECT m.body,COALESCE(m.sender_id::text,''),COALESCE(NULLIF(member.group_display_name,''),NULLIF(u.full_name,''),NULLIF(u.username,''),'GroopX member') FROM messages m LEFT JOIN users u ON u.id=m.sender_id LEFT JOIN conversation_members member ON member.conversation_id=m.conversation_id AND member.user_id=m.sender_id WHERE m.id=$1 AND m.conversation_id=$2 AND m.deleted_at IS NULL`, input.ReplyToID, conversationID).Scan(&replyText, &replySenderID,&replySenderName) != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "reply target is unavailable"})
			return
		}
		reply = gin.H{"id": input.ReplyToID, "text": replyText, "sender_id": replySenderID,"sender_name":replySenderName, "mine": replySenderID == userID}
	}
	status := "sent"
	if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) {
		status = "delivered"
	}
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be saved"})
		return
	}
	defer tx.Rollback(ctx)
	var id string
	var createdAt time.Time
	var inserted bool
	err = tx.QueryRow(ctx, `WITH saved AS (
		INSERT INTO messages(conversation_id,sender_id,body,status,reply_to_id,client_message_id)
		VALUES($1,$2,$3,$4,NULLIF($5,'')::uuid,NULLIF($6,''))
		ON CONFLICT (sender_id,client_message_id) DO NOTHING
		RETURNING id,created_at,status,true AS inserted
	)
	SELECT id::text,created_at,status::text,inserted FROM saved
	UNION ALL
	SELECT id::text,created_at,status::text,false FROM messages
	WHERE conversation_id=$1 AND sender_id=$2 AND client_message_id=NULLIF($6,'')
	LIMIT 1`, conversationID, userID, text, status, input.ReplyToID, input.ClientMessageID).Scan(&id, &createdAt, &status, &inserted)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be saved"})
		return
	}
	mentionIDs := mentionUserIDs(mentions)
	if inserted {
		if err = insertMessageMentions(ctx, tx, id, mentions); err == nil {
			_, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, createdAt)
		}
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID)
		}
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be saved"})
		return
	}
	if !inserted {
		mentionIDs, err = loadMessageMentionIDs(ctx, id)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be loaded"})
			return
		}
	}
	senderName,senderAvatar:=messageSenderIdentity(c.Request.Context(),conversationID,userID)
	payload := gin.H{"type": "message", "id": id, "conversation_id": conversationID, "sender_id": userID,"sender_name":senderName,"sender_avatar_url":senderAvatar, "text": text, "kind": "text", "status": status, "created_at": createdAt, "reply": reply, "mention_user_ids": mentionIDs, "mentioned": false}
	if inserted {
		broadcast(conversationID, userID, payload)
		notifyMessageConversation(conversationID, userID, text, map[string]any{"conversation_id": conversationID, "message_id": id, "mention_user_ids": mentionIDs}, mentionIDs)
	}
	payload["mine"] = true
	if inserted {
		c.JSON(http.StatusCreated, payload)
	} else {
		c.JSON(http.StatusOK, payload)
	}
}

func sendLocationMessage(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		Latitude  *float64 `json:"latitude"`
		Longitude *float64 `json:"longitude"`
		Label     string  `json:"label" binding:"omitempty,max=180"`
	}
	if c.ShouldBindJSON(&input) != nil || !validLiveCoordinates(input.Latitude, input.Longitude, nil) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid location is required"})
		return
	}
	if !isConversationMember(c, conversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"})
		return
	}
	if !requireConversationSender(c, conversationID, userID) { return }
	if scheduledCommunicationBlocked(c.Request.Context(), conversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "communication is blocked"})
		return
	}
	label := strings.TrimSpace(input.Label)
	if label == "" { label = "Shared location" }
	metadata, _ := json.Marshal(gin.H{"latitude": *input.Latitude, "longitude": *input.Longitude, "label": label, "map_url": "https://www.google.com/maps/search/?api=1&query=" + strings.ReplaceAll(strings.TrimSpace(strings.Join([]string{formatCoordinate(*input.Latitude), formatCoordinate(*input.Longitude)}, ",")), " ", "")})
	status := "sent"
	if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) { status = "delivered" }
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "location could not be sent"}); return }
	defer tx.Rollback(ctx)
	var id string; var createdAt time.Time
	err = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status) VALUES($1,$2,'location',$3,$4,$5) RETURNING id::text,created_at`, conversationID, userID, label, metadata, status).Scan(&id, &createdAt)
	if err == nil { _, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, createdAt) }
	if err == nil { _, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID) }
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "location could not be sent"}); return
	}
	senderName,senderAvatar:=messageSenderIdentity(c.Request.Context(),conversationID,userID)
	payload := gin.H{"type":"message","id":id,"conversation_id":conversationID,"sender_id":userID,"sender_name":senderName,"sender_avatar_url":senderAvatar,"text":label,"kind":"location","attachment":json.RawMessage(metadata),"status":status,"created_at":createdAt}
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
