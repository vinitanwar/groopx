package httpapi

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

type forwardedMessage struct {
	ID, ConversationID, Kind, Body, Status string
	Metadata                               map[string]any
	CreatedAt                              time.Time
}

func forwardMessage(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		ConversationIDs []string `json:"conversation_ids" binding:"required,min=1,max=5,dive,uuid"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "select 1 to 5 conversations"})
		return
	}

	unique := make([]string, 0, len(input.ConversationIDs))
	seen := make(map[string]bool)
	for _, id := range input.ConversationIDs {
		if !seen[id] {
			seen[id] = true
			unique = append(unique, id)
		}
	}

	ctx := c.Request.Context()
	var sourceConversationID, body, kind string
	var viewOnce bool
	var rawMetadata []byte
	if db.QueryRow(ctx, `SELECT m.conversation_id::text,m.body,m.kind::text,m.metadata,m.view_once
		FROM messages m JOIN conversation_members cm ON cm.conversation_id=m.conversation_id AND cm.user_id=$2
		WHERE m.id=$1 AND m.deleted_at IS NULL`, c.Param("id"), userID).Scan(&sourceConversationID, &body, &kind, &rawMetadata, &viewOnce) != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "message not found"})
		return
	}
	if kind == "system" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "group activity messages cannot be forwarded"})
		return
	}
	if kind == "poll" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "poll messages cannot be forwarded"})
		return
	}
	if viewOnce {
		c.JSON(http.StatusBadRequest, gin.H{"error": "view once media cannot be forwarded"})
		return
	}

	metadata := map[string]any{}
	_ = json.Unmarshal(rawMetadata, &metadata)
	delete(metadata, "status_reply")
	if kind == "location" && metadata["live"] == true {
		body = "Shared location"
		metadata["label"] = body
		metadata["live"] = false
		metadata["active"] = false
		delete(metadata, "live_location_id")
		delete(metadata, "started_at")
		delete(metadata, "expires_at")
		delete(metadata, "stopped_at")
	}
	metadata["forwarded"] = true
	forwardMetadata, _ := json.Marshal(metadata)

	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be forwarded"})
		return
	}
	defer tx.Rollback(ctx)
	created := make([]forwardedMessage, 0, len(unique))
	for _, conversationID := range unique {
		var allowed bool
		err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id=$1 AND user_id=$2)`, conversationID, userID).Scan(&allowed)
		if err != nil || !allowed {
			c.JSON(http.StatusForbidden, gin.H{"error": "one selected conversation is unavailable"})
			return
		}
		allowed, err = conversationAllowsSender(ctx, tx, conversationID, userID)
		if err != nil || !allowed {
			c.JSON(http.StatusForbidden, gin.H{"error": announcementOnlyMessage})
			return
		}
		var otherID string
		if tx.QueryRow(ctx, `SELECT cm.user_id::text FROM conversations cv JOIN conversation_members cm ON cm.conversation_id=cv.id AND cm.user_id<>$2 WHERE cv.id=$1 AND cv.kind='direct' LIMIT 1`, conversationID, userID).Scan(&otherID) == nil && usersBlocked(userID, otherID) {
			c.JSON(http.StatusForbidden, gin.H{"error": "a selected conversation is blocked"})
			return
		}
		status := "sent"
		if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) {
			status = "delivered"
		}
		item := forwardedMessage{ConversationID: conversationID, Kind: kind, Body: body, Status: status, Metadata: metadata}
		err = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status) VALUES($1,$2,$3,$4,$5,$6) RETURNING id::text,created_at`, conversationID, userID, kind, body, forwardMetadata, status).Scan(&item.ID, &item.CreatedAt)
		if err == nil && kind != "text" {
			_, err = tx.Exec(ctx, `INSERT INTO message_attachments(message_id,media_id) SELECT $1,media_id FROM message_attachments WHERE message_id=$2`, item.ID, c.Param("id"))
		}
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, item.CreatedAt)
		}
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID)
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be forwarded"})
			return
		}
		created = append(created, item)
	}
	if tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be forwarded"})
		return
	}

	for _, item := range created {
		senderName,senderAvatar:=messageSenderIdentity(ctx,item.ConversationID,userID)
		payload := gin.H{"type": "message", "id": item.ID, "conversation_id": item.ConversationID, "sender_id": userID,"sender_name":senderName,"sender_avatar_url":senderAvatar, "text": item.Body, "kind": item.Kind, "status": item.Status, "created_at": item.CreatedAt, "forwarded": true}
		if item.Kind != "text" {
			payload["attachment"] = item.Metadata
		}
		broadcast(item.ConversationID, userID, payload)
		preview := strings.TrimSpace(item.Body)
		if preview == "" {
			preview = "Forwarded message"
		}
		notifyConversation(item.ConversationID, userID, "message", "Forwarded message", preview, map[string]any{"conversation_id": item.ConversationID, "message_id": item.ID})
	}
	c.JSON(http.StatusCreated, gin.H{"forwarded_count": len(created)})
}
