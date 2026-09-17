package httpapi

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var otpStore = struct {
	sync.RWMutex
	codes map[string]string
}{codes: make(map[string]string)}

func Register(router *gin.Engine) {
	v1 := router.Group("/api/v1")
	v1.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "groopx-api"})
	})
	v1.POST("/auth/request-otp", requestOTP)
	v1.POST("/auth/verify-otp", verifyOTP)
	v1.PUT("/users/me/profile", requireBearer(), updateProfile)
	v1.GET("/ws", chatSocket)
	v1.POST("/contacts", requireBearer(), createContact)
	v1.POST("/groups", requireBearer(), createGroup)
	v1.POST("/conversations/:id/archive", requireBearer(), setArchive(true))
	v1.DELETE("/conversations/:id/archive", requireBearer(), setArchive(false))
	v1.DELETE("/conversations/:id", requireBearer(), deleteConversation)
	v1.POST("/media/presign", requireBearer(), presignMedia)
	v1.GET("/reminders", requireBearer(), listReminders)
	v1.POST("/reminders", requireBearer(), createReminder)
	v1.DELETE("/reminders/:id", requireBearer(), deleteReminder)
	v1.POST("/devices", requireBearer(), registerDevice)
	v1.POST("/calls/token", requireBearer(), createCallToken)
	v1.POST("/calls/:id/end", requireBearer(), endCall)
}

var upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}

type incomingMessage struct { Text string `json:"text"` }

func chatSocket(c *gin.Context) {
	conversationID := c.Query("conversation_id")
	if conversationID == "" { c.JSON(http.StatusBadRequest, gin.H{"error": "conversation_id is required"}); return }
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil { return }
	defer conn.Close()
	for {
		_, data, err := conn.ReadMessage(); if err != nil { return }
		var input incomingMessage
		if json.Unmarshal(data, &input) != nil || strings.TrimSpace(input.Text) == "" { continue }
		response := gin.H{"id": time.Now().Format("20060102150405.000000"), "conversation_id": conversationID, "text": input.Text, "time": time.Now().Format("3:04 PM"), "mine": true, "status": "sent"}
		if conn.WriteJSON(response) != nil { return }
	}
}

type phoneRequest struct { Phone string `json:"phone" binding:"required"` }
type verifyRequest struct {
	Phone string `json:"phone" binding:"required"`
	Code string `json:"code" binding:"required,len=6"`
}

func requestOTP(c *gin.Context) {
	var input phoneRequest
	if err := c.ShouldBindJSON(&input); err != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "valid phone is required"}); return }
	otpStore.Lock(); otpStore.codes[input.Phone] = "123456"; otpStore.Unlock()
	c.JSON(http.StatusAccepted, gin.H{"message": "otp sent", "expires_in": 600})
}

func verifyOTP(c *gin.Context) {
	var input verifyRequest
	if err := c.ShouldBindJSON(&input); err != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "phone and 6-digit code are required"}); return }
	otpStore.RLock(); code := otpStore.codes[input.Phone]; otpStore.RUnlock()
	if code == "" || code != input.Code { c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid otp"}); return }
	c.JSON(http.StatusOK, gin.H{"access_token": "dev-access-token", "refresh_token": "dev-refresh-token", "is_new_user": true})
}

func requireBearer() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !strings.HasPrefix(c.GetHeader("Authorization"), "Bearer ") { c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing bearer token"}); return }
		c.Next()
	}
}

func updateProfile(c *gin.Context) {
	var profile map[string]any
	if err := c.ShouldBindJSON(&profile); err != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid profile"}); return }
	c.JSON(http.StatusOK, gin.H{"message": "profile updated", "profile": profile})
}

func createContact(c *gin.Context) {
	var input map[string]any
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid contact"}); return }
	c.JSON(http.StatusCreated, gin.H{"id": time.Now().UnixNano(), "contact": input})
}

func createGroup(c *gin.Context) {
	var input struct {
		Name string `json:"name" binding:"required,max=50"`
		Description string `json:"description"`
		Privacy string `json:"privacy" binding:"required,oneof=private public"`
		MemberIDs []string `json:"member_ids"`
	}
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group"}); return }
	c.JSON(http.StatusCreated, gin.H{"id": time.Now().UnixNano(), "name": input.Name, "privacy": input.Privacy, "members": len(input.MemberIDs)})
}

func setArchive(archived bool) gin.HandlerFunc {
	return func(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"conversation_id": c.Param("id"), "archived": archived}) }
}

func deleteConversation(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"conversation_id": c.Param("id"), "deleted": true})
}

func presignMedia(c *gin.Context) {
	var input struct { FileName string `json:"file_name" binding:"required"`; ContentType string `json:"content_type" binding:"required"`; Size int64 `json:"size" binding:"required,max=209715200"` }
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid media metadata"}); return }
	c.JSON(http.StatusOK, gin.H{"object_key": "uploads/dev/" + input.FileName, "upload_url": "https://storage.example.invalid/presigned-upload", "expires_in": 900})
}

var reminderStore = struct { sync.RWMutex; items []map[string]any }{items: []map[string]any{}}

func listReminders(c *gin.Context) { reminderStore.RLock(); defer reminderStore.RUnlock(); c.JSON(http.StatusOK, gin.H{"items": reminderStore.items}) }

func createReminder(c *gin.Context) {
	var input struct { Title string `json:"title" binding:"required,max=160"`; ScheduledAt time.Time `json:"scheduled_at" binding:"required"`; ConversationID string `json:"conversation_id"`; Notes string `json:"notes"` }
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reminder"}); return }
	item := map[string]any{"id": time.Now().UnixNano(), "title": input.Title, "scheduled_at": input.ScheduledAt, "conversation_id": input.ConversationID, "notes": input.Notes, "status": "upcoming"}
	reminderStore.Lock(); reminderStore.items = append(reminderStore.items, item); reminderStore.Unlock()
	c.JSON(http.StatusCreated, item)
}

func deleteReminder(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"id": c.Param("id"), "deleted": true}) }

func registerDevice(c *gin.Context) {
	var input struct { Token string `json:"token" binding:"required"`; Platform string `json:"platform" binding:"required,oneof=android ios web"` }
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid device"}); return }
	c.JSON(http.StatusCreated, gin.H{"registered": true, "platform": input.Platform})
}

func createCallToken(c *gin.Context) {
	apiKey, secret, livekitURL := os.Getenv("LIVEKIT_API_KEY"), os.Getenv("LIVEKIT_API_SECRET"), os.Getenv("LIVEKIT_URL")
	if apiKey == "" || secret == "" || livekitURL == "" { c.JSON(http.StatusServiceUnavailable, gin.H{"error": "LiveKit is not configured"}); return }
	var input struct { Room string `json:"room" binding:"required"`; Identity string `json:"identity" binding:"required"`; Video bool `json:"video"` }
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "room and identity are required"}); return }
	now := time.Now().Unix()
	header := map[string]any{"alg": "HS256", "typ": "JWT"}
	payload := map[string]any{"iss": apiKey, "sub": input.Identity, "nbf": now - 5, "exp": now + 3600, "video": map[string]any{"roomJoin": true, "room": input.Room, "canPublish": true, "canSubscribe": true}}
	token, err := signJWT(header, payload, secret); if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "token generation failed"}); return }
	c.JSON(http.StatusOK, gin.H{"url": livekitURL, "token": token, "room": input.Room})
}

func signJWT(header, payload map[string]any, secret string) (string, error) {
	headerJSON, err := json.Marshal(header); if err != nil { return "", err }
	payloadJSON, err := json.Marshal(payload); if err != nil { return "", err }
	encode := base64.RawURLEncoding.EncodeToString
	unsigned := encode(headerJSON) + "." + encode(payloadJSON)
	mac := hmac.New(sha256.New, []byte(secret)); _, _ = mac.Write([]byte(unsigned))
	return unsigned + "." + encode(mac.Sum(nil)), nil
}

func endCall(c *gin.Context) { c.JSON(http.StatusOK, gin.H{"id": c.Param("id"), "status": "ended", "ended_at": time.Now()}) }
