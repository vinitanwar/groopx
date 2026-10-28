package httpapi

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

const viewOnceAccessTTL = 5 * time.Minute

func protectViewOnceAttachment(metadata map[string]any, mine, opened bool, openedCount, recipientCount int) map[string]any {
	protected := make(map[string]any, len(metadata)+5)
	for key, value := range metadata {
		protected[key] = value
	}
	delete(protected, "url")
	delete(protected, "object_key")
	protected["view_once"] = true
	protected["opened"] = !mine && opened
	protected["available"] = !mine && !opened
	protected["opened_count"] = openedCount
	protected["recipient_count"] = recipientCount
	return protected
}

func viewOnceSignature(secret, messageID, userID string, expires int64) string {
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte("view-once\n" + messageID + "\n" + userID + "\n" + strconv.FormatInt(expires, 10)))
	return hex.EncodeToString(mac.Sum(nil))
}

func validViewOnceAccess(messageID, userID, expiresRaw, signature, secret string, now time.Time) bool {
	expires, err := strconv.ParseInt(expiresRaw, 10, 64)
	if err != nil || expires <= now.Unix() || expires > now.Add(10*time.Minute).Unix() {
		return false
	}
	expected := viewOnceSignature(secret, messageID, userID, expires)
	return hmac.Equal([]byte(expected), []byte(strings.ToLower(signature)))
}

func openViewOnceMedia(c *gin.Context) {
	messageID, userID := c.Param("id"), c.GetString("user_id")
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "view once media could not be opened"})
		return
	}
	defer tx.Rollback(ctx)

	var conversationID, senderID, kind, fileName, contentType string
	var size int64
	err = tx.QueryRow(ctx, `SELECT m.conversation_id::text,m.sender_id::text,m.kind::text,
		media.file_name,media.content_type,media.size_bytes
		FROM messages m
		JOIN conversation_members member ON member.conversation_id=m.conversation_id AND member.user_id=$2
		JOIN message_attachments attachment ON attachment.message_id=m.id
		JOIN media_objects media ON media.id=attachment.media_id
		JOIN media_blobs blob ON blob.media_id=media.id
		WHERE m.id=$1 AND m.view_once=TRUE AND m.kind IN ('image','video') AND m.deleted_at IS NULL
		ORDER BY attachment.sort_order LIMIT 1 FOR UPDATE OF m`, messageID, userID).Scan(&conversationID, &senderID, &kind, &fileName, &contentType, &size)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "view once media is unavailable"})
		return
	}
	if senderID == userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "sent view once media cannot be reopened"})
		return
	}
	var opened bool
	if tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM view_once_opens WHERE message_id=$1 AND user_id=$2)`, messageID, userID).Scan(&opened) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "view once media could not be opened"})
		return
	}
	if opened {
		c.JSON(http.StatusConflict, gin.H{"error": "view once media was already opened"})
		return
	}
	if _, err = tx.Exec(ctx, `INSERT INTO view_once_opens(message_id,user_id) VALUES($1,$2)`, messageID, userID); err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "view once media was already opened"})
		return
	}
	var openedCount int
	if tx.QueryRow(ctx, `SELECT COUNT(*)::int FROM view_once_opens WHERE message_id=$1`, messageID).Scan(&openedCount) != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "view once media could not be opened"})
		return
	}

	expires := time.Now().Add(viewOnceAccessTTL).Unix()
	signature := viewOnceSignature(cfg.JWTSecret, messageID, userID, expires)
	scheme := c.GetHeader("X-Forwarded-Proto")
	if scheme == "" {
		scheme = "http"
		if c.Request.TLS != nil {
			scheme = "https"
		}
	}
	mediaURL := scheme + "://" + c.Request.Host + "/api/v1/media/view-once/" + messageID +
		"?viewer=" + userID + "&expires=" + strconv.FormatInt(expires, 10) + "&signature=" + signature
	broadcast(conversationID, userID, gin.H{"type": "view_once_opened", "conversation_id": conversationID, "message_id": messageID, "opened_by": userID, "opened_count": openedCount})
	c.JSON(http.StatusOK, gin.H{"url": mediaURL, "kind": kind, "file_name": fileName, "content_type": contentType, "size": size, "expires_at": time.Unix(expires, 0).UTC()})
}

func serveViewOnceMedia(c *gin.Context) {
	messageID := c.Param("messageId")
	userID := strings.TrimSpace(c.Query("viewer"))
	if userID == "" || !validViewOnceAccess(messageID, userID, c.Query("expires"), c.Query("signature"), cfg.JWTSecret, time.Now()) {
		c.Status(http.StatusForbidden)
		return
	}
	var contentType, fileName string
	var data []byte
	var createdAt time.Time
	err := db.QueryRow(c.Request.Context(), `SELECT media.content_type,media.file_name,blob.file_data,media.created_at
		FROM messages m
		JOIN conversation_members member ON member.conversation_id=m.conversation_id AND member.user_id=$2
		JOIN view_once_opens opened ON opened.message_id=m.id AND opened.user_id=$2
		JOIN message_attachments attachment ON attachment.message_id=m.id
		JOIN media_objects media ON media.id=attachment.media_id
		JOIN media_blobs blob ON blob.media_id=media.id
		WHERE m.id=$1 AND m.view_once=TRUE AND m.deleted_at IS NULL
		ORDER BY attachment.sort_order LIMIT 1`, messageID, userID).Scan(&contentType, &fileName, &data, &createdAt)
	if err != nil {
		c.Status(http.StatusNotFound)
		return
	}
	c.Header("Content-Disposition", `inline; filename="`+unsafeFileName.ReplaceAllString(fileName, "_")+`"`)
	c.Header("Cache-Control", "private, no-store, max-age=0")
	c.Header("Pragma", "no-cache")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Content-Type", contentType)
	http.ServeContent(c.Writer, c.Request, fileName, createdAt, bytes.NewReader(data))
}
