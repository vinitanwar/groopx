package httpapi

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
)

func normalizeSharedContact(name, phone string) (string, string, bool) {
	name = strings.TrimSpace(name)
	if name == "" || utf8.RuneCountInString(name) > 120 {
		return "", "", false
	}
	for _, character := range name {
		if unicode.IsControl(character) {
			return "", "", false
		}
	}
	name = strings.Join(strings.Fields(name), " ")
	rawPhone := strings.TrimSpace(phone)
	digits := contactPhoneDigits(rawPhone)
	if len(digits) < 7 || len(digits) > 15 {
		return "", "", false
	}
	if strings.HasPrefix(rawPhone, "+") {
		digits = "+" + digits
	}
	return name, digits, true
}

func sendContactMessage(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		Name  string `json:"name"`
		Phone string `json:"phone"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "contact name and phone are required"})
		return
	}
	name, phone, valid := normalizeSharedContact(input.Name, input.Phone)
	if !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid contact name and phone are required"})
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

	metadata, _ := json.Marshal(gin.H{"display_name": name, "phone": phone})
	status := "sent"
	if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) {
		status = "delivered"
	}
	body := "Contact: " + name
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "contact could not be sent"})
		return
	}
	defer tx.Rollback(ctx)
	var id string
	var createdAt time.Time
	err = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status)
		VALUES($1,$2,'contact',$3,$4,$5) RETURNING id::text,created_at`, conversationID, userID, body, metadata, status).Scan(&id, &createdAt)
	if err == nil {
		_, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, createdAt)
	}
	if err == nil {
		_, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID)
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "contact could not be sent"})
		return
	}

	senderName, senderAvatar := messageSenderIdentity(ctx, conversationID, userID)
	attachment := gin.H{"display_name": name, "phone": phone}
	payload := gin.H{"type": "message", "id": id, "conversation_id": conversationID, "sender_id": userID, "sender_name": senderName, "sender_avatar_url": senderAvatar, "text": body, "kind": "contact", "attachment": attachment, "status": status, "created_at": createdAt}
	broadcast(conversationID, userID, payload)
	notifyConversation(conversationID, userID, "contact", "Contact shared", name, map[string]any{"conversation_id": conversationID, "message_id": id})
	payload["mine"] = true
	c.JSON(http.StatusCreated, payload)
}
