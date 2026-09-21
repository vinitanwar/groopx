package httpapi

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"groopx/backend/internal/config"
)

var (
	db  *pgxpool.Pool
	cfg config.Config
	phonePattern = regexp.MustCompile(`^\+[1-9][0-9]{7,14}$`)
)

type phoneRequest struct { Phone string `json:"phone" binding:"required"` }
type verifyRequest struct {
	Phone string `json:"phone" binding:"required"`
	Code string `json:"code" binding:"required,len=6,numeric"`
}
type refreshRequest struct { RefreshToken string `json:"refresh_token" binding:"required"` }

func requestOTP(c *gin.Context) {
	var input phoneRequest
	if c.ShouldBindJSON(&input) != nil || !phonePattern.MatchString(input.Phone) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid E.164 phone is required"}); return
	}
	var lastSent time.Time
	err := db.QueryRow(c.Request.Context(), `SELECT created_at FROM otp_challenges WHERE phone=$1`, input.Phone).Scan(&lastSent)
	if err == nil && time.Since(lastSent) < time.Minute {
		c.Header("Retry-After", "60")
		c.JSON(http.StatusTooManyRequests, gin.H{"error": "please wait before requesting another otp", "retry_after": int((time.Minute-time.Since(lastSent)).Seconds()) + 1})
		return
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "otp service unavailable"}); return
	}

	codeHash := "twilio-verify"
	if cfg.DevelopmentMode {
		codeHash = otpHash(input.Phone, "123456")
	} else {
		if !twilioConfigured() {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "production SMS provider is not configured"}); return
		}
		if err := sendTwilioOTP(input.Phone); err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "otp delivery failed"}); return
		}
	}

	_, err = db.Exec(c.Request.Context(), `INSERT INTO otp_challenges(phone, code_hash, expires_at, attempts)
		VALUES($1,$2,NOW() + INTERVAL '10 minutes',0)
		ON CONFLICT(phone) DO UPDATE SET code_hash=EXCLUDED.code_hash, expires_at=EXCLUDED.expires_at, attempts=0, created_at=NOW()`, input.Phone, codeHash)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "otp could not be created"}); return }
	c.JSON(http.StatusAccepted, gin.H{"message": "otp sent", "expires_in": 600, "resend_after": 60})
}

func verifyOTP(c *gin.Context) {
	var input verifyRequest
	if c.ShouldBindJSON(&input) != nil || !phonePattern.MatchString(input.Phone) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "phone and 6-digit code are required"}); return
	}
	ctx := c.Request.Context()
	var stored string
	var expires time.Time
	var attempts int
	err := db.QueryRow(ctx, `SELECT code_hash, expires_at, attempts FROM otp_challenges WHERE phone=$1`, input.Phone).Scan(&stored, &expires, &attempts)
	if errors.Is(err, pgx.ErrNoRows) || time.Now().After(expires) || attempts >= 5 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired otp"}); return
	}
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "verification unavailable"}); return }

	verified := false
	if cfg.DevelopmentMode {
		verified = stored == otpHash(input.Phone, input.Code)
	} else {
		if !twilioConfigured() { c.JSON(http.StatusServiceUnavailable, gin.H{"error": "production SMS provider is not configured"}); return }
		verified, err = checkTwilioOTP(input.Phone, input.Code)
		if err != nil { c.JSON(http.StatusBadGateway, gin.H{"error": "otp verification service unavailable"}); return }
	}
	if !verified {
		_, _ = db.Exec(ctx, `UPDATE otp_challenges SET attempts=attempts+1 WHERE phone=$1`, input.Phone)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired otp"}); return
	}

	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "verification unavailable"}); return }
	defer tx.Rollback(ctx)
	var userID string
	var fullName *string
	err = tx.QueryRow(ctx, `INSERT INTO users(phone) VALUES($1) ON CONFLICT(phone) DO UPDATE SET updated_at=NOW()
		RETURNING id::text, full_name`, input.Phone).Scan(&userID, &fullName)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "user could not be loaded"}); return }
	_, _ = tx.Exec(ctx, `DELETE FROM otp_challenges WHERE phone=$1`, input.Phone)
	access, err := createAccessToken(userID, input.Phone)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "session could not be created"}); return }
	refresh, refreshHash, err := newRefreshToken()
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "session could not be created"}); return }
	_, err = tx.Exec(ctx, `INSERT INTO refresh_tokens(user_id, token_hash, expires_at, device_name, user_agent, ip_address)
		VALUES($1,$2,$3,$4,$5,NULLIF($6,'')::inet)`, userID, refreshHash, time.Now().Add(cfg.RefreshTokenTTL), deviceName(c), c.GetHeader("User-Agent"), c.ClientIP())
	if err != nil || tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "session could not be saved"}); return }
	c.JSON(http.StatusOK, gin.H{"access_token": access, "refresh_token": refresh, "expires_in": int(cfg.AccessTokenTTL.Seconds()), "is_new_user": fullName == nil})
}

func otpHash(phone, code string) string {
	hash := sha256.Sum256([]byte(phone + ":" + code + ":" + cfg.JWTSecret))
	return hex.EncodeToString(hash[:])
}

func refreshSession(c *gin.Context) {
	var input refreshRequest
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "refresh_token is required"}); return }
	hash := tokenHash(input.RefreshToken)
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "session unavailable"}); return }
	defer tx.Rollback(ctx)
	var tokenID, userID, phone string
	err = tx.QueryRow(ctx, `SELECT rt.id::text, u.id::text, u.phone FROM refresh_tokens rt JOIN users u ON u.id=rt.user_id
		WHERE rt.token_hash=$1 AND rt.revoked_at IS NULL AND rt.expires_at>NOW() FOR UPDATE`, hash).Scan(&tokenID, &userID, &phone)
	if err != nil { c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"}); return }
	_, _ = tx.Exec(ctx, `UPDATE refresh_tokens SET revoked_at=NOW() WHERE id=$1`, tokenID)
	newToken, newHash, err := newRefreshToken()
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "session could not be refreshed"}); return }
	_, err = tx.Exec(ctx, `INSERT INTO refresh_tokens(user_id, token_hash, expires_at, device_name, user_agent, ip_address)
		VALUES($1,$2,$3,$4,$5,NULLIF($6,'')::inet)`, userID, newHash, time.Now().Add(cfg.RefreshTokenTTL), deviceName(c), c.GetHeader("User-Agent"), c.ClientIP())
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "session could not be refreshed"}); return }
	access, err := createAccessToken(userID, phone)
	if err != nil || tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "session could not be refreshed"}); return }
	c.JSON(http.StatusOK, gin.H{"access_token": access, "refresh_token": newToken, "expires_in": int(cfg.AccessTokenTTL.Seconds())})
}

func logout(c *gin.Context) {
	var input refreshRequest
	if c.ShouldBindJSON(&input) == nil { _, _ = db.Exec(c.Request.Context(), `UPDATE refresh_tokens SET revoked_at=NOW() WHERE token_hash=$1 AND revoked_at IS NULL`, tokenHash(input.RefreshToken)) }
	c.Status(http.StatusNoContent)
}

func deviceName(c *gin.Context) string {
	name := strings.TrimSpace(c.GetHeader("X-Device-Name"))
	if name == "" {
		name = "GroopX device"
	}
	if len(name) > 120 {
		name = name[:120]
	}
	return name
}

func validCurrentSession(c *gin.Context, hash string) bool {
	var valid bool
	err := db.QueryRow(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM refresh_tokens
		WHERE user_id=$1 AND token_hash=$2 AND revoked_at IS NULL AND expires_at>NOW())`, c.GetString("user_id"), hash).Scan(&valid)
	return err == nil && valid
}

func listSessions(c *gin.Context) {
	var input refreshRequest
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "refresh_token is required"})
		return
	}
	currentHash := tokenHash(input.RefreshToken)
	if !validCurrentSession(c, currentHash) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "current session is invalid"})
		return
	}
	rows, err := db.Query(c.Request.Context(), `SELECT id::text, COALESCE(device_name,'GroopX device'), COALESCE(user_agent,''),
		COALESCE(host(ip_address),''), created_at, last_seen_at, expires_at, token_hash=$2
		FROM refresh_tokens WHERE user_id=$1 AND revoked_at IS NULL AND expires_at>NOW()
		ORDER BY (token_hash=$2) DESC, last_seen_at DESC`, c.GetString("user_id"), currentHash)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "sessions unavailable"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, name, agent, ip string
		var created, seen, expires time.Time
		var current bool
		if rows.Scan(&id, &name, &agent, &ip, &created, &seen, &expires, &current) != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "sessions unavailable"})
			return
		}
		items = append(items, gin.H{"id": id, "device_name": name, "user_agent": agent, "ip_address": ip, "created_at": created, "last_seen_at": seen, "expires_at": expires, "current": current})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func revokeSession(c *gin.Context) {
	tag, err := db.Exec(c.Request.Context(), `UPDATE refresh_tokens SET revoked_at=NOW()
		WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL`, c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "device could not be logged out"})
		return
	}
	if tag.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "active session not found"})
		return
	}
	c.Status(http.StatusNoContent)
}

func revokeOtherSessions(c *gin.Context) {
	var input refreshRequest
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "refresh_token is required"})
		return
	}
	currentHash := tokenHash(input.RefreshToken)
	if !validCurrentSession(c, currentHash) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "current session is invalid"})
		return
	}
	tag, err := db.Exec(c.Request.Context(), `UPDATE refresh_tokens SET revoked_at=NOW()
		WHERE user_id=$1 AND token_hash<>$2 AND revoked_at IS NULL`, c.GetString("user_id"), currentHash)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "other devices could not be logged out"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "other sessions revoked", "count": tag.RowsAffected()})
}

func requireBearer() gin.HandlerFunc {
	return func(c *gin.Context) {
		raw := strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer ")
		if raw == "" { c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing bearer token"}); return }
		userID, err := parseAccessToken(raw)
		if err != nil { c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid access token"}); return }
		if !ensureActiveUser(c, userID) { c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "account is not active"}); return }
		c.Set("user_id", userID); c.Next()
	}
}

func parseAccessToken(raw string) (string, error) {
	token, err := jwt.Parse(raw, func(token *jwt.Token) (any, error) {
		if token.Method.Alg() != jwt.SigningMethodHS256.Alg() { return nil, errors.New("unexpected signing method") }
		return []byte(cfg.JWTSecret), nil
	}, jwt.WithExpirationRequired(), jwt.WithIssuer("groopx-api"))
	if err != nil || !token.Valid { return "", errors.New("invalid access token") }
	claims, ok := token.Claims.(jwt.MapClaims); if !ok { return "", errors.New("invalid claims") }
	userID, err := claims.GetSubject(); if err != nil || userID == "" { return "", errors.New("missing subject") }
	return userID, nil
}

func updateProfile(c *gin.Context) {
	var input struct {
		FullName string `json:"full_name" binding:"required,max=120"`
		Username string `json:"username" binding:"required,min=3,max=40"`
		DateOfBirth string `json:"date_of_birth" binding:"omitempty,datetime=2006-01-02"`
		Gender string `json:"gender" binding:"omitempty,max=30"`
		Bio string `json:"bio" binding:"max=160"`
	}
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid profile"}); return }
	userID := c.GetString("user_id")
	var profile map[string]any
	var id, phone string
	err := db.QueryRow(c.Request.Context(), `UPDATE users SET full_name=$2, username=$3, date_of_birth=NULLIF($4,'')::date, gender=NULLIF($5,''), bio=NULLIF($6,''), updated_at=NOW()
		WHERE id=$1 RETURNING id::text, phone`, userID, strings.TrimSpace(input.FullName), strings.ToLower(strings.TrimSpace(input.Username)), input.DateOfBirth, input.Gender, strings.TrimSpace(input.Bio)).Scan(&id, &phone)
	if err != nil { c.JSON(http.StatusConflict, gin.H{"error": "profile could not be updated; username may already exist"}); return }
	profile = map[string]any{"id": id, "phone": phone, "full_name": strings.TrimSpace(input.FullName), "username": strings.ToLower(strings.TrimSpace(input.Username)), "date_of_birth": input.DateOfBirth, "gender": input.Gender, "bio": strings.TrimSpace(input.Bio)}
	c.JSON(http.StatusOK, gin.H{"message": "profile updated", "profile": profile})
}

func getCurrentUser(c *gin.Context) {
	var id, phone string
	var fullName, username, dateOfBirth, gender, bio, avatarURL *string
	var showOnline, readReceipts, push, messages, calls, reminders bool
	err := db.QueryRow(c.Request.Context(), `SELECT id::text, phone, full_name, username, date_of_birth::text, gender, bio, avatar_url,
		show_online_status, read_receipts, push_notifications, message_notifications, call_notifications, reminder_notifications
		FROM users WHERE id=$1`, c.GetString("user_id")).Scan(&id, &phone, &fullName, &username, &dateOfBirth, &gender, &bio, &avatarURL, &showOnline, &readReceipts, &push, &messages, &calls, &reminders)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error": "profile not found"}); return }
	c.JSON(http.StatusOK, gin.H{
		"id": id, "phone": phone, "full_name": fullName, "username": username, "date_of_birth": dateOfBirth,
		"gender": gender, "bio": bio, "avatar_url": avatarURL,
		"settings": gin.H{"show_online_status": showOnline, "read_receipts": readReceipts, "push_notifications": push,
			"message_notifications": messages, "call_notifications": calls, "reminder_notifications": reminders},
	})
}

func updateSettings(c *gin.Context) {
	var input struct {
		ShowOnlineStatus *bool `json:"show_online_status"`
		ReadReceipts *bool `json:"read_receipts"`
		PushNotifications *bool `json:"push_notifications"`
		MessageNotifications *bool `json:"message_notifications"`
		CallNotifications *bool `json:"call_notifications"`
		ReminderNotifications *bool `json:"reminder_notifications"`
	}
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error": "invalid settings"}); return }
	_, err := db.Exec(c.Request.Context(), `UPDATE users SET
		show_online_status=COALESCE($2,show_online_status), read_receipts=COALESCE($3,read_receipts),
		push_notifications=COALESCE($4,push_notifications), message_notifications=COALESCE($5,message_notifications),
		call_notifications=COALESCE($6,call_notifications), reminder_notifications=COALESCE($7,reminder_notifications), updated_at=NOW()
		WHERE id=$1`, c.GetString("user_id"), input.ShowOnlineStatus, input.ReadReceipts, input.PushNotifications, input.MessageNotifications, input.CallNotifications, input.ReminderNotifications)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "settings could not be updated"}); return }
	c.JSON(http.StatusOK, gin.H{"message": "settings updated"})
}

func createAccessToken(userID, phone string) (string, error) {
	now := time.Now()
	claims := jwt.MapClaims{"iss": "groopx-api", "sub": userID, "phone": phone, "iat": now.Unix(), "exp": now.Add(cfg.AccessTokenTTL).Unix()}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(cfg.JWTSecret))
}

func newRefreshToken() (string, string, error) {
	b := make([]byte, 48)
	if _, err := rand.Read(b); err != nil { return "", "", err }
	token := base64.RawURLEncoding.EncodeToString(b)
	return token, tokenHash(token), nil
}

func tokenHash(token string) string { sum := sha256.Sum256([]byte(token)); return hex.EncodeToString(sum[:]) }
