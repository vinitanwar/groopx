package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

const scheduledMessageMaximumDelay = 365 * 24 * time.Hour

type scheduledMessage struct {
	id             string
	conversationID string
	senderID       string
	body           string
	scheduledAt    time.Time
	createdAt      time.Time
	replyID        *string
	replyText      *string
	replySenderID  *string
	replySender    *string
}

type scheduledMessageEvent struct {
	message scheduledMessage
	messageID string
	status string
	createdAt time.Time
	senderName string
	senderAvatar string
	reply gin.H
}

func listScheduledMessages(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	if !isConversationMember(c, conversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"})
		return
	}
	rows, err := db.Query(c.Request.Context(), scheduledMessageSelect+`
		WHERE scheduled.sender_id=$1 AND scheduled.conversation_id=$2 AND scheduled.status='pending'
		ORDER BY scheduled.scheduled_at,scheduled.created_at`, userID, conversationID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scheduled messages could not be loaded"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var item scheduledMessage
		if scanScheduledMessage(rows, &item) != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scheduled messages could not be loaded"})
			return
		}
		items = append(items, scheduledMessageJSON(item, userID))
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scheduled messages could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func createScheduledMessage(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		Text string `json:"text" binding:"required,max=10000"`
		ScheduledAt time.Time `json:"scheduled_at" binding:"required"`
		ReplyToID string `json:"reply_to_id" binding:"omitempty,uuid"`
	}
	input.Text = ""
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Text) == "" || !validScheduledMessageTime(input.ScheduledAt) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message and a future time are required"})
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
	if input.ReplyToID != "" && !scheduledReplyAvailable(c.Request.Context(), conversationID, input.ReplyToID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reply target is unavailable"})
		return
	}
	var id string
	err := db.QueryRow(c.Request.Context(), `INSERT INTO scheduled_messages(conversation_id,sender_id,body,reply_to_id,scheduled_at)
		VALUES($1,$2,$3,NULLIF($4,'')::uuid,$5) RETURNING id::text`, conversationID, userID, strings.TrimSpace(input.Text), input.ReplyToID, input.ScheduledAt).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "message could not be scheduled"})
		return
	}
	item, err := loadScheduledMessage(c.Request.Context(), id, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scheduled message could not be loaded"})
		return
	}
	c.JSON(http.StatusCreated, scheduledMessageJSON(item, userID))
}

func updateScheduledMessage(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		Text *string `json:"text" binding:"omitempty,max=10000"`
		ScheduledAt *time.Time `json:"scheduled_at"`
	}
	if c.ShouldBindJSON(&input) != nil || (input.Text == nil && input.ScheduledAt == nil) || (input.Text != nil && strings.TrimSpace(*input.Text) == "") || (input.ScheduledAt != nil && !validScheduledMessageTime(*input.ScheduledAt)) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid message text or future time is required"})
		return
	}
	var text *string
	if input.Text != nil {
		trimmed := strings.TrimSpace(*input.Text)
		text = &trimmed
	}
	existing, err := loadScheduledMessage(c.Request.Context(), c.Param("id"), userID)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "pending scheduled message not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scheduled message could not be loaded"})
		return
	}
	if !requireConversationSender(c, existing.conversationID, userID) { return }
	command, err := db.Exec(c.Request.Context(), `UPDATE scheduled_messages SET body=COALESCE($3,body),scheduled_at=COALESCE($4,scheduled_at),updated_at=NOW()
		WHERE id=$1 AND sender_id=$2 AND status='pending'`, c.Param("id"), userID, text, input.ScheduledAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scheduled message could not be updated"})
		return
	}
	if command.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "pending scheduled message not found"})
		return
	}
	item, err := loadScheduledMessage(c.Request.Context(), c.Param("id"), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scheduled message could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, scheduledMessageJSON(item, userID))
}

func cancelScheduledMessage(c *gin.Context) {
	command, err := db.Exec(c.Request.Context(), `UPDATE scheduled_messages SET status='cancelled',cancelled_at=NOW(),processed_at=NOW(),updated_at=NOW()
		WHERE id=$1 AND sender_id=$2 AND status='pending'`, c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "scheduled message could not be cancelled"})
		return
	}
	if command.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "pending scheduled message not found"})
		return
	}
	c.Status(http.StatusNoContent)
}

func validScheduledMessageTime(value time.Time) bool {
	now := time.Now()
	return value.After(now.Add(30*time.Second)) && value.Before(now.Add(scheduledMessageMaximumDelay))
}

const scheduledMessageSelect = `SELECT scheduled.id::text,scheduled.conversation_id::text,scheduled.sender_id::text,scheduled.body,
	 scheduled.scheduled_at,scheduled.created_at,reply.id::text,reply.body,reply.sender_id::text,
	 COALESCE(NULLIF(reply_member.group_display_name,''),NULLIF(reply_sender.full_name,''),NULLIF(reply_sender.username,''),'GroopX member')
	 FROM scheduled_messages scheduled
	 LEFT JOIN messages reply ON reply.id=scheduled.reply_to_id AND reply.deleted_at IS NULL
	 LEFT JOIN users reply_sender ON reply_sender.id=reply.sender_id
	 LEFT JOIN conversation_members reply_member ON reply_member.conversation_id=scheduled.conversation_id AND reply_member.user_id=reply.sender_id`

type scheduledMessageScanner interface {
	Scan(dest ...any) error
}

func scanScheduledMessage(scanner scheduledMessageScanner, item *scheduledMessage) error {
	return scanner.Scan(&item.id, &item.conversationID, &item.senderID, &item.body, &item.scheduledAt, &item.createdAt, &item.replyID, &item.replyText, &item.replySenderID, &item.replySender)
}

func loadScheduledMessage(ctx context.Context, id, userID string) (scheduledMessage, error) {
	var item scheduledMessage
	err := scanScheduledMessage(db.QueryRow(ctx, scheduledMessageSelect+` WHERE scheduled.id=$1 AND scheduled.sender_id=$2 AND scheduled.status='pending'`, id, userID), &item)
	return item, err
}

func scheduledMessageJSON(item scheduledMessage, viewerID string) gin.H {
	result := gin.H{"id": item.id, "conversation_id": item.conversationID, "text": item.body, "scheduled_at": item.scheduledAt, "created_at": item.createdAt}
	if item.replyID != nil {
		result["reply"] = gin.H{"id": *item.replyID, "text": valueOr(item.replyText, "Message"), "sender_id": valueOr(item.replySenderID, ""), "sender_name": valueOr(item.replySender, "GroopX member"), "mine": item.replySenderID != nil && *item.replySenderID == viewerID}
	}
	return result
}

func valueOr(value *string, fallback string) string {
	if value == nil { return fallback }
	return *value
}

func scheduledReplyAvailable(ctx context.Context, conversationID, replyID string) bool {
	var available bool
	err := db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM messages WHERE id=$1 AND conversation_id=$2 AND deleted_at IS NULL)`, replyID, conversationID).Scan(&available)
	return err == nil && available
}

func scheduledCommunicationBlocked(ctx context.Context, conversationID, senderID string) bool {
	var blocked bool
	err := db.QueryRow(ctx, `SELECT EXISTS(
		SELECT 1 FROM conversations conversation
		JOIN conversation_members peer ON peer.conversation_id=conversation.id AND peer.user_id<>$2
		JOIN user_blocks block ON (block.blocker_id=$2 AND block.blocked_id=peer.user_id) OR (block.blocker_id=peer.user_id AND block.blocked_id=$2)
		WHERE conversation.id=$1 AND conversation.kind='direct'
	)`, conversationID, senderID).Scan(&blocked)
	return err == nil && blocked
}

func startScheduledMessageScheduler() {
	go func() {
		dispatchScheduledMessages(context.Background())
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for range ticker.C { dispatchScheduledMessages(context.Background()) }
	}()
}

func dispatchScheduledMessages(ctx context.Context) {
	tx, err := db.Begin(ctx)
	if err != nil { return }
	defer tx.Rollback(ctx)
	rows, err := tx.Query(ctx, `SELECT scheduled.id::text,scheduled.conversation_id::text,scheduled.sender_id::text,scheduled.body,
		scheduled.scheduled_at,scheduled.created_at,scheduled.reply_to_id::text,
		COALESCE(NULLIF(sender_member.group_display_name,''),NULLIF(sender.full_name,''),NULLIF(sender.username,''),'GroopX member'),COALESCE(sender.avatar_url,'')
		FROM scheduled_messages scheduled JOIN users sender ON sender.id=scheduled.sender_id
		LEFT JOIN conversation_members sender_member ON sender_member.conversation_id=scheduled.conversation_id AND sender_member.user_id=scheduled.sender_id
		WHERE scheduled.status='pending' AND scheduled.scheduled_at<=NOW()
		ORDER BY scheduled.scheduled_at,scheduled.id FOR UPDATE OF scheduled SKIP LOCKED LIMIT 100`)
	if err != nil { return }
	type dueMessage struct {
		scheduledMessage
		senderName string
		senderAvatar string
	}
	due := make([]dueMessage, 0)
	for rows.Next() {
		var item dueMessage
		if rows.Scan(&item.id, &item.conversationID, &item.senderID, &item.body, &item.scheduledAt, &item.createdAt, &item.replyID, &item.senderName, &item.senderAvatar) != nil { rows.Close(); return }
		due = append(due, item)
	}
	if rows.Err() != nil { rows.Close(); return }
	rows.Close()
	events := make([]scheduledMessageEvent, 0, len(due))
	for _, item := range due {
		var available bool
		err = tx.QueryRow(ctx, `SELECT EXISTS(
			SELECT 1 FROM conversations conversation
			JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$2 AND member.hidden_at IS NULL
			JOIN users sender ON sender.id=$2 AND sender.account_status='active'
			WHERE conversation.id=$1 AND conversation.deleted_at IS NULL AND (conversation.kind<>'direct' OR NOT EXISTS(
				SELECT 1 FROM conversation_members peer JOIN user_blocks block
				ON (block.blocker_id=$2 AND block.blocked_id=peer.user_id) OR (block.blocker_id=peer.user_id AND block.blocked_id=$2)
				WHERE peer.conversation_id=conversation.id AND peer.user_id<>$2
			))
		)`, item.conversationID, item.senderID).Scan(&available)
		if err != nil { return }
		if !available {
			if err = failScheduledMessage(ctx, tx, item.scheduledMessage, "The chat is no longer available or communication is blocked."); err != nil { return }
			continue
		}
		allowed, permissionErr := conversationAllowsSender(ctx, tx, item.conversationID, item.senderID)
		if permissionErr != nil { return }
		if !allowed {
			if err = failScheduledMessage(ctx, tx, item.scheduledMessage, announcementOnlyMessage); err != nil { return }
			continue
		}
		replyID := ""
		var reply gin.H
		if item.replyID != nil {
			var replyText, replySenderID, replySenderName string
			err = tx.QueryRow(ctx, `SELECT message.body,COALESCE(message.sender_id::text,''),COALESCE(NULLIF(sender_member.group_display_name,''),NULLIF(sender.full_name,''),NULLIF(sender.username,''),'GroopX member')
				FROM messages message LEFT JOIN users sender ON sender.id=message.sender_id
				LEFT JOIN conversation_members sender_member ON sender_member.conversation_id=message.conversation_id AND sender_member.user_id=message.sender_id
				WHERE message.id=$1 AND message.conversation_id=$2 AND message.deleted_at IS NULL`, *item.replyID, item.conversationID).Scan(&replyText, &replySenderID, &replySenderName)
			if err == nil {
				replyID = *item.replyID
				reply = gin.H{"id": replyID, "text": replyText, "sender_id": replySenderID, "sender_name": replySenderName, "mine": replySenderID == item.senderID}
			} else if !errors.Is(err, pgx.ErrNoRows) { return }
		}
		status := "sent"
		if onlineRecipients(item.conversationID, item.senderID) > 0 || isConversationPeerOnline(item.conversationID, item.senderID) { status = "delivered" }
		var messageID string
		var createdAt time.Time
		err = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,body,status,reply_to_id)
			VALUES($1,$2,$3,$4,NULLIF($5,'')::uuid) RETURNING id::text,created_at`, item.conversationID, item.senderID, item.body, status, replyID).Scan(&messageID, &createdAt)
		if err != nil { return }
		if _, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, item.conversationID, createdAt); err != nil { return }
		if _, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, item.conversationID, item.senderID); err != nil { return }
		if _, err = tx.Exec(ctx, `UPDATE scheduled_messages SET status='sent',sent_message_id=$2,processed_at=NOW(),updated_at=NOW() WHERE id=$1`, item.id, messageID); err != nil { return }
		events = append(events, scheduledMessageEvent{message: item.scheduledMessage, messageID: messageID, status: status, createdAt: createdAt, senderName: item.senderName, senderAvatar: item.senderAvatar, reply: reply})
	}
	if err = tx.Commit(ctx); err != nil {
		log.Printf("scheduled message dispatch commit failed: %v", err)
		return
	}
	for _, event := range events {
		payload := gin.H{"type": "message", "id": event.messageID, "conversation_id": event.message.conversationID, "sender_id": event.message.senderID, "sender_name": event.senderName, "sender_avatar_url": event.senderAvatar, "text": event.message.body, "kind": "text", "status": event.status, "created_at": event.createdAt, "reply": event.reply}
		broadcast(event.message.conversationID, event.message.senderID, payload)
		notifyConversation(event.message.conversationID, event.message.senderID, "message", "New message", event.message.body, map[string]any{"conversation_id": event.message.conversationID, "message_id": event.messageID})
	}
}

func failScheduledMessage(ctx context.Context, tx pgx.Tx, item scheduledMessage, reason string) error {
	if _, err := tx.Exec(ctx, `UPDATE scheduled_messages SET status='failed',failure_reason=$2,processed_at=NOW(),updated_at=NOW() WHERE id=$1`, item.id, reason); err != nil { return err }
	data, _ := json.Marshal(gin.H{"type": "scheduled_message_failed", "scheduled_message_id": item.id})
	_, err := tx.Exec(ctx, `INSERT INTO notifications(user_id,type,title,body,data) VALUES($1,'scheduled_message_failed','Scheduled message not sent',$2,$3)`, item.senderID, reason, data)
	return err
}
