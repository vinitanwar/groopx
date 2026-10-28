package httpapi

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"path"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

const maximumStatusPrivacyContacts = 500
const maximumStatusShareConversations = 5

type statusShareMessage struct {
	ID, ConversationID, Kind, Body, Status string
	Metadata                               map[string]any
	CreatedAt                              time.Time
}

var textStatusColors = map[string]bool{
	"#6335FF": true,
	"#E91E63": true,
	"#0F8B8D": true,
	"#1565C0": true,
	"#F57C00": true,
	"#263238": true,
	"#7B1FA2": true,
	"#2E7D32": true,
}

var statusReactionEmojis = map[string]bool{
	"❤️": true,
	"😂": true,
	"😮": true,
	"😢": true,
	"🙏": true,
	"👏": true,
}

func normalizeTextStatus(text, backgroundColor string) (string, string, error) {
	text = strings.TrimSpace(text)
	if text == "" {
		return "", "", errors.New("status text is required")
	}
	if utf8.RuneCountInString(text) > 700 {
		return "", "", errors.New("status text is too long")
	}
	backgroundColor = strings.ToUpper(strings.TrimSpace(backgroundColor))
	if backgroundColor == "" {
		backgroundColor = "#6335FF"
	}
	if !textStatusColors[backgroundColor] {
		return "", "", errors.New("invalid status background")
	}
	return text, backgroundColor, nil
}

func normalizeStatusReplyText(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", errors.New("status reply is required")
	}
	if utf8.RuneCountInString(value) > 1000 {
		return "", errors.New("status reply is too long")
	}
	return value, nil
}

func normalizeStatusReaction(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "❤" {
		value = "❤️"
	}
	if !statusReactionEmojis[value] {
		return "", errors.New("invalid status reaction")
	}
	return value, nil
}

func normalizeStatusPrivacyInput(audience string, userIDs []string) (string, []string, error) {
	audience = strings.ToLower(strings.TrimSpace(audience))
	if audience != "contacts" && audience != "contacts_except" && audience != "only_share_with" {
		return "", nil, errors.New("invalid status audience")
	}
	if len(userIDs) > maximumStatusPrivacyContacts {
		return "", nil, errors.New("too many status privacy contacts")
	}
	if audience == "contacts" {
		return audience, []string{}, nil
	}
	selected := make([]string, 0, len(userIDs))
	seen := make(map[string]bool, len(userIDs))
	for _, rawID := range userIDs {
		userID := strings.ToLower(strings.TrimSpace(rawID))
		if !validStatusPrivacyUserID(userID) {
			return "", nil, errors.New("invalid status privacy contact")
		}
		if !seen[userID] {
			seen[userID] = true
			selected = append(selected, userID)
		}
	}
	return audience, selected, nil
}

func validStatusPrivacyUserID(value string) bool {
	if len(value) != 36 {
		return false
	}
	for index := 0; index < len(value); index++ {
		if index == 8 || index == 13 || index == 18 || index == 23 {
			if value[index] != '-' {
				return false
			}
			continue
		}
		character := value[index]
		if !((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f')) {
			return false
		}
	}
	return true
}

func uniqueStatusShareConversationIDs(values []string) []string {
	unique := make([]string, 0, len(values))
	seen := make(map[string]bool, len(values))
	for _, value := range values {
		if !seen[value] {
			seen[value] = true
			unique = append(unique, value)
			if len(unique) == maximumStatusShareConversations {
				break
			}
		}
	}
	return unique
}

func createStatus(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		ObjectKey   string `json:"object_key" binding:"required,max=500"`
		FileName    string `json:"file_name" binding:"required,max=180"`
		ContentType string `json:"content_type" binding:"required,max=120"`
		Size        int64  `json:"size" binding:"required,gt=0,lte=209715200"`
		Caption     string `json:"caption" binding:"max=500"`
	}
	if c.ShouldBindJSON(&input) != nil || !strings.HasPrefix(input.ObjectKey, "uploads/"+userID+"/") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status media"})
		return
	}
	kind := ""
	if strings.HasPrefix(input.ContentType, "image/") {
		kind = "image"
	} else if strings.HasPrefix(input.ContentType, "video/") {
		kind = "video"
	}
	if kind == "" || cfg.S3PublicBaseURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be an image or video"})
		return
	}
	publicURL := strings.TrimRight(cfg.S3PublicBaseURL, "/") + "/" + escapeObjectKey(input.ObjectKey)
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be saved"})
		return
	}
	defer tx.Rollback(ctx)
	var mediaID, statusID string
	var createdAt, expiresAt time.Time
	err = tx.QueryRow(ctx, `INSERT INTO media_objects(owner_id,object_key,file_name,content_type,size_bytes) VALUES($1,$2,$3,$4,$5) RETURNING id::text`, userID, input.ObjectKey, input.FileName, input.ContentType, input.Size).Scan(&mediaID)
	if err == nil {
		err = tx.QueryRow(ctx, `INSERT INTO statuses(user_id,media_id,media_url,media_type,caption) VALUES($1,$2,$3,$4,NULLIF($5,'')) RETURNING id::text,created_at,expires_at`, userID, mediaID, publicURL, kind, input.Caption).Scan(&statusID, &createdAt, &expiresAt)
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "status could not be saved"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": statusID, "media_url": publicURL, "media_type": kind, "caption": input.Caption, "created_at": createdAt, "expires_at": expiresAt, "mine": true, "viewed": true, "liked": false, "view_count": 0, "like_count": 0, "muted": false})
}

func createTextStatus(c *gin.Context) {
	var input struct {
		Text            string `json:"text"`
		BackgroundColor string `json:"background_color"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status text is required"})
		return
	}
	text, backgroundColor, err := normalizeTextStatus(input.Text, input.BackgroundColor)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var statusID string
	var createdAt, expiresAt time.Time
	err = db.QueryRow(c.Request.Context(), `INSERT INTO statuses(user_id,media_id,media_url,media_type,text_content,background_color)
		VALUES($1,NULL,'','text',$2,$3) RETURNING id::text,created_at,expires_at`, c.GetString("user_id"), text, backgroundColor).Scan(&statusID, &createdAt, &expiresAt)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "text status could not be saved"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": statusID, "media_url": "", "media_type": "text", "caption": "", "text_content": text, "background_color": backgroundColor, "created_at": createdAt, "expires_at": expiresAt, "mine": true, "viewed": true, "liked": false, "view_count": 0, "like_count": 0, "muted": false})
}

func uploadStatus(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 27*1024*1024)
	fileHeader, err := c.FormFile("file")
	if err != nil || fileHeader.Size <= 0 || fileHeader.Size > 25*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Without external storage, status must be smaller than 25 MB"})
		return
	}
	file, err := fileHeader.Open()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status media could not be read"})
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, 25*1024*1024+1))
	if err != nil || len(data) == 0 || len(data) > 25*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Without external storage, status must be smaller than 25 MB"})
		return
	}
	fileName := unsafeFileName.ReplaceAllString(path.Base(fileHeader.Filename), "_")
	if fileName == "" {
		fileName = "status"
	}
	contentType := strings.TrimSpace(fileHeader.Header.Get("Content-Type"))
	if contentType == "" || contentType == "application/octet-stream" {
		contentType = http.DetectContentType(data)
	}
	kind := ""
	if strings.HasPrefix(contentType, "image/") {
		kind = "image"
	} else if strings.HasPrefix(contentType, "video/") {
		kind = "video"
	}
	if kind == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status must be an image or video"})
		return
	}
	caption := strings.TrimSpace(c.PostForm("caption"))
	if len([]rune(caption)) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "caption is too long"})
		return
	}
	random := make([]byte, 16)
	if _, err = rand.Read(random); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be saved"})
		return
	}
	objectKey := "database/statuses/" + hex.EncodeToString(random) + "-" + fileName
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be saved"})
		return
	}
	defer tx.Rollback(ctx)
	userID := c.GetString("user_id")
	var mediaID, statusID string
	var createdAt, expiresAt time.Time
	err = tx.QueryRow(ctx, `INSERT INTO media_objects(owner_id,object_key,file_name,content_type,size_bytes) VALUES($1,$2,$3,$4,$5) RETURNING id::text`, userID, objectKey, fileName, contentType, len(data)).Scan(&mediaID)
	if err == nil {
		_, err = tx.Exec(ctx, `INSERT INTO media_blobs(media_id,file_data) VALUES($1,$2)`, mediaID, data)
	}
	scheme := c.GetHeader("X-Forwarded-Proto")
	if scheme == "" {
		scheme = "http"
		if c.Request.TLS != nil {
			scheme = "https"
		}
	}
	publicURL := scheme + "://" + c.Request.Host + "/api/v1/media/files/" + mediaID
	if err == nil {
		err = tx.QueryRow(ctx, `INSERT INTO statuses(user_id,media_id,media_url,media_type,caption) VALUES($1,$2,$3,$4,NULLIF($5,'')) RETURNING id::text,created_at,expires_at`, userID, mediaID, publicURL, kind, caption).Scan(&statusID, &createdAt, &expiresAt)
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be saved"})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"id": statusID, "media_url": publicURL, "media_type": kind, "caption": caption, "created_at": createdAt, "expires_at": expiresAt, "mine": true, "viewed": true, "liked": false, "view_count": 0, "like_count": 0, "muted": false})
}

func listStatuses(c *gin.Context) {
	userID := c.GetString("user_id")
	_, _ = db.Exec(c.Request.Context(), `WITH expired AS (DELETE FROM statuses WHERE expires_at<=NOW() RETURNING media_id) DELETE FROM media_objects media WHERE media.id IN (SELECT media_id FROM expired) AND NOT EXISTS(SELECT 1 FROM message_attachments attachment WHERE attachment.media_id=media.id)`)
	rows, err := db.Query(c.Request.Context(), `SELECT s.id::text,s.user_id::text,COALESCE(u.full_name,u.username,'GroopX user'),COALESCE(u.avatar_url,''),s.media_url,s.media_type,s.caption,COALESCE(s.text_content,''),s.background_color,s.created_at,s.expires_at,(s.user_id=$1),EXISTS(SELECT 1 FROM status_views status_view WHERE status_view.status_id=s.id AND status_view.user_id=$1),CASE WHEN s.user_id=$1 AND u.read_receipts THEN (SELECT COUNT(*) FROM status_views status_view JOIN users viewer ON viewer.id=status_view.user_id AND (viewer.read_receipts=TRUE OR EXISTS(SELECT 1 FROM status_likes status_like WHERE status_like.status_id=s.id AND status_like.user_id=status_view.user_id)) WHERE status_view.status_id=s.id AND status_view.user_id<>s.user_id) ELSE 0 END,EXISTS(SELECT 1 FROM status_likes status_like WHERE status_like.status_id=s.id AND status_like.user_id=$1) AS liked,CASE WHEN s.user_id=$1 AND u.read_receipts THEN (SELECT COUNT(*) FROM status_likes status_like WHERE status_like.status_id=s.id AND status_like.user_id<>s.user_id) ELSE 0 END AS like_count,EXISTS(SELECT 1 FROM muted_status_users muted_status WHERE muted_status.owner_id=$1 AND muted_status.muted_user_id=s.user_id) AS muted
		FROM statuses s JOIN users u ON u.id=s.user_id
		WHERE s.expires_at>NOW() AND u.account_status='active'
		AND (s.user_id=$1 OR (
			EXISTS(SELECT 1 FROM contacts contact WHERE contact.owner_id=s.user_id AND contact.contact_user_id=$1)
			AND EXISTS(SELECT 1 FROM contacts contact WHERE contact.owner_id=$1 AND contact.contact_user_id=s.user_id)
			AND (
				COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='contacts'
				OR (COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='contacts_except' AND NOT EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=s.user_id AND selected.contact_user_id=$1))
				OR (COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='only_share_with' AND EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=s.user_id AND selected.contact_user_id=$1))
			)
		))
		AND NOT EXISTS(SELECT 1 FROM user_blocks blocked WHERE (blocked.blocker_id=$1 AND blocked.blocked_id=s.user_id) OR (blocked.blocker_id=s.user_id AND blocked.blocked_id=$1))
		ORDER BY (s.user_id=$1) DESC,muted ASC,s.created_at DESC`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "statuses could not be loaded"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, ownerID, name, avatar, url, kind, textContent, backgroundColor string
		var caption *string
		var createdAt, expiresAt time.Time
		var mine, viewed, liked, muted bool
		var views, likes int
		if rows.Scan(&id, &ownerID, &name, &avatar, &url, &kind, &caption, &textContent, &backgroundColor, &createdAt, &expiresAt, &mine, &viewed, &views, &liked, &likes, &muted) == nil {
			items = append(items, gin.H{"id": id, "user_id": ownerID, "user_name": name, "avatar_url": avatar, "media_url": url, "media_type": kind, "caption": caption, "text_content": textContent, "background_color": backgroundColor, "created_at": createdAt, "expires_at": expiresAt, "mine": mine, "viewed": viewed, "view_count": views, "liked": liked, "like_count": likes, "muted": muted})
		}
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "statuses could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func getStatusPrivacy(c *gin.Context) {
	userID := c.GetString("user_id")
	var audience string
	if err := db.QueryRow(c.Request.Context(), `SELECT COALESCE((SELECT audience FROM status_privacy_settings WHERE user_id=$1),'contacts')`, userID).Scan(&audience); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status privacy could not be loaded"})
		return
	}
	rows, err := db.Query(c.Request.Context(), `WITH saved_contacts AS (
		SELECT DISTINCT ON (contact.contact_user_id) account.id,COALESCE(NULLIF(contact.display_name,''),NULLIF(account.full_name,''),NULLIF(account.username,''),'GroopX user') AS name,COALESCE(account.username,'') AS username,COALESCE(account.avatar_url,'') AS avatar_url
		FROM contacts contact JOIN users account ON account.id=contact.contact_user_id
		WHERE contact.owner_id=$1 AND account.account_status='active'
		ORDER BY contact.contact_user_id,contact.created_at DESC
	)
	SELECT saved.id::text,saved.name,saved.username,saved.avatar_url,EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=$1 AND selected.contact_user_id=saved.id) AS selected
	FROM saved_contacts saved ORDER BY LOWER(saved.name),saved.id`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status privacy contacts could not be loaded"})
		return
	}
	defer rows.Close()
	contacts := make([]gin.H, 0)
	for rows.Next() {
		var id, name, username, avatarURL string
		var selected bool
		if rows.Scan(&id, &name, &username, &avatarURL, &selected) == nil {
			contacts = append(contacts, gin.H{"id": id, "name": name, "username": username, "avatar_url": avatarURL, "selected": selected})
		}
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status privacy contacts could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"audience": audience, "contacts": contacts})
}

func updateStatusPrivacy(c *gin.Context) {
	var input struct {
		Audience string   `json:"audience" binding:"required"`
		UserIDs  []string `json:"user_ids" binding:"max=500"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid status privacy settings are required"})
		return
	}
	audience, selected, normalizeErr := normalizeStatusPrivacyInput(input.Audience, input.UserIDs)
	if normalizeErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": normalizeErr.Error()})
		return
	}
	selectedJSON, _ := json.Marshal(selected)
	userID := c.GetString("user_id")
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status privacy could not be saved"})
		return
	}
	defer tx.Rollback(ctx)
	if len(selected) > 0 {
		var eligible int
		err = tx.QueryRow(ctx, `WITH requested AS (SELECT value::uuid AS user_id FROM jsonb_array_elements_text($2::jsonb) requested(value))
			SELECT COUNT(DISTINCT requested.user_id)::int FROM requested
			JOIN contacts contact ON contact.owner_id=$1 AND contact.contact_user_id=requested.user_id
			JOIN users account ON account.id=requested.user_id AND account.account_status='active'`, userID, string(selectedJSON)).Scan(&eligible)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "status privacy contacts could not be checked"})
			return
		}
		if eligible != len(selected) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "status privacy can only include saved contacts"})
			return
		}
	}
	_, err = tx.Exec(ctx, `INSERT INTO status_privacy_settings(user_id,audience,updated_at) VALUES($1,$2,NOW()) ON CONFLICT(user_id) DO UPDATE SET audience=EXCLUDED.audience,updated_at=NOW()`, userID, audience)
	if err == nil {
		_, err = tx.Exec(ctx, `DELETE FROM status_privacy_contacts WHERE user_id=$1`, userID)
	}
	if err == nil && len(selected) > 0 {
		_, err = tx.Exec(ctx, `WITH requested AS (SELECT value::uuid AS user_id FROM jsonb_array_elements_text($2::jsonb) requested(value))
			INSERT INTO status_privacy_contacts(user_id,contact_user_id)
			SELECT DISTINCT $1,requested.user_id FROM requested`, userID, string(selectedJSON))
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status privacy could not be saved"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"audience": audience, "selected_count": len(selected)})
}

func muteStatusUser(c *gin.Context) {
	ownerID := c.GetString("user_id")
	mutedUserID := strings.ToLower(strings.TrimSpace(c.Param("userId")))
	if !validStatusPrivacyUserID(mutedUserID) || mutedUserID == strings.ToLower(ownerID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status account"})
		return
	}
	command, err := db.Exec(c.Request.Context(), `INSERT INTO muted_status_users(owner_id,muted_user_id)
		SELECT $1,account.id FROM users account WHERE account.id=$2 AND account.account_status='active'
		ON CONFLICT(owner_id,muted_user_id) DO NOTHING`, ownerID, mutedUserID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status updates could not be muted"})
		return
	}
	if command.RowsAffected() == 0 {
		var exists bool
		if db.QueryRow(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM muted_status_users WHERE owner_id=$1 AND muted_user_id=$2)`, ownerID, mutedUserID).Scan(&exists) != nil || !exists {
			c.JSON(http.StatusNotFound, gin.H{"error": "status account not found"})
			return
		}
	}
	c.Status(http.StatusNoContent)
}

func unmuteStatusUser(c *gin.Context) {
	mutedUserID := strings.ToLower(strings.TrimSpace(c.Param("userId")))
	if !validStatusPrivacyUserID(mutedUserID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status account"})
		return
	}
	if _, err := db.Exec(c.Request.Context(), `DELETE FROM muted_status_users WHERE owner_id=$1 AND muted_user_id=$2`, c.GetString("user_id"), mutedUserID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status updates could not be unmuted"})
		return
	}
	c.Status(http.StatusNoContent)
}

func viewStatus(c *gin.Context) {
	userID := c.GetString("user_id")
	command, err := db.Exec(c.Request.Context(), `INSERT INTO status_views(status_id,user_id)
		SELECT s.id,$2 FROM statuses s WHERE s.id=$1 AND s.expires_at>NOW()
		AND EXISTS(SELECT 1 FROM users account WHERE account.id=s.user_id AND account.account_status='active')
		AND (s.user_id=$2 OR (
			EXISTS(SELECT 1 FROM contacts contact WHERE contact.owner_id=s.user_id AND contact.contact_user_id=$2)
			AND EXISTS(SELECT 1 FROM contacts contact WHERE contact.owner_id=$2 AND contact.contact_user_id=s.user_id)
			AND (
				COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='contacts'
				OR (COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='contacts_except' AND NOT EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=s.user_id AND selected.contact_user_id=$2))
				OR (COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='only_share_with' AND EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=s.user_id AND selected.contact_user_id=$2))
			)
		))
		AND NOT EXISTS(SELECT 1 FROM user_blocks blocked WHERE (blocked.blocker_id=$2 AND blocked.blocked_id=s.user_id) OR (blocked.blocker_id=s.user_id AND blocked.blocked_id=$2))
		ON CONFLICT(status_id,user_id) DO UPDATE SET viewed_at=status_views.viewed_at`, c.Param("id"), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status view could not be saved"})
		return
	}
	if command.RowsAffected() == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "status is no longer available"})
		return
	}
	c.Status(http.StatusNoContent)
}

func likeStatus(c *gin.Context) {
	setStatusLike(c, true)
}

func unlikeStatus(c *gin.Context) {
	setStatusLike(c, false)
}

func setStatusLike(c *gin.Context, liked bool) {
	userID := c.GetString("user_id")
	statusID := c.Param("id")
	if !liked {
		if _, err := db.Exec(c.Request.Context(), `DELETE FROM status_likes WHERE status_id=$1 AND user_id=$2`, statusID, userID); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "status like could not be removed"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"liked": false})
		return
	}

	var eligible bool
	err := db.QueryRow(c.Request.Context(), `SELECT EXISTS(
		SELECT 1 FROM statuses s JOIN users owner ON owner.id=s.user_id AND owner.account_status='active'
		WHERE s.id=$1 AND s.expires_at>NOW() AND s.user_id<>$2
		AND EXISTS(SELECT 1 FROM contacts contact WHERE contact.owner_id=s.user_id AND contact.contact_user_id=$2)
		AND EXISTS(SELECT 1 FROM contacts contact WHERE contact.owner_id=$2 AND contact.contact_user_id=s.user_id)
		AND (
			COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='contacts'
			OR (COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='contacts_except' AND NOT EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=s.user_id AND selected.contact_user_id=$2))
			OR (COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='only_share_with' AND EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=s.user_id AND selected.contact_user_id=$2))
		)
		AND NOT EXISTS(SELECT 1 FROM user_blocks blocked WHERE (blocked.blocker_id=$2 AND blocked.blocked_id=s.user_id) OR (blocked.blocker_id=s.user_id AND blocked.blocked_id=$2))
	)`, statusID, userID).Scan(&eligible)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status like could not be saved"})
		return
	}
	if !eligible {
		c.JSON(http.StatusNotFound, gin.H{"error": "status is no longer available"})
		return
	}

	tx, err := db.Begin(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status like could not be saved"})
		return
	}
	defer tx.Rollback(c.Request.Context())
	_, err = tx.Exec(c.Request.Context(), `INSERT INTO status_views(status_id,user_id) SELECT id,$2 FROM statuses WHERE id=$1 AND expires_at>NOW() ON CONFLICT(status_id,user_id) DO NOTHING`, statusID, userID)
	likeCreated := false
	if err == nil {
		command, executeErr := tx.Exec(c.Request.Context(), `INSERT INTO status_likes(status_id,user_id) SELECT id,$2 FROM statuses WHERE id=$1 AND expires_at>NOW() ON CONFLICT(status_id,user_id) DO NOTHING`, statusID, userID)
		err = executeErr
		likeCreated = err == nil && command.RowsAffected() > 0
	}
	if err == nil && !likeCreated {
		var saved bool
		err = tx.QueryRow(c.Request.Context(), `SELECT EXISTS(SELECT 1 FROM status_likes WHERE status_id=$1 AND user_id=$2)`, statusID, userID).Scan(&saved)
		if err == nil && !saved {
			c.JSON(http.StatusNotFound, gin.H{"error": "status is no longer available"})
			return
		}
	}
	var ownerID, likerName string
	if err == nil && likeCreated {
		err = tx.QueryRow(c.Request.Context(), `SELECT s.user_id::text,COALESCE(NULLIF(liker.full_name,''),NULLIF(liker.username,''),'A contact') FROM statuses s JOIN users liker ON liker.id=$2 WHERE s.id=$1`, statusID, userID).Scan(&ownerID, &likerName)
	}
	if err == nil && likeCreated {
		payload, _ := json.Marshal(gin.H{"status_id": statusID, "liker_id": userID})
		_, err = tx.Exec(c.Request.Context(), `INSERT INTO notifications(user_id,type,title,body,data) VALUES($1,'status_like','New status like',$2,$3)`, ownerID, likerName+" liked your status", payload)
	}
	if err != nil || tx.Commit(c.Request.Context()) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status like could not be saved"})
		return
	}
	if likeCreated {
		go sendPushToUsers([]string{ownerID}, "status_like", "New status like", likerName+" liked your status", map[string]any{"status_id": statusID, "liker_id": userID})
	}
	c.JSON(http.StatusOK, gin.H{"liked": true})
}

func replyToStatus(c *gin.Context) {
	var input struct {
		Text string `json:"text"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status reply is required"})
		return
	}
	text, normalizeErr := normalizeStatusReplyText(input.Text)
	if normalizeErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": normalizeErr.Error()})
		return
	}
	sendStatusChatMessage(c, text, "")
}

func reactToStatus(c *gin.Context) {
	var input struct {
		Emoji string `json:"emoji"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "status reaction is required"})
		return
	}
	emoji, normalizeErr := normalizeStatusReaction(input.Emoji)
	if normalizeErr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": normalizeErr.Error()})
		return
	}
	sendStatusChatMessage(c, emoji, emoji)
}

func shareStatus(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		ConversationIDs []string `json:"conversation_ids" binding:"required,min=1,max=5,dive,uuid"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "select 1 to 5 conversations"})
		return
	}
	conversationIDs := uniqueStatusShareConversationIDs(input.ConversationIDs)
	if len(conversationIDs) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "select at least one conversation"})
		return
	}

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be shared"})
		return
	}
	defer tx.Rollback(ctx)

	var mediaID *string
	var mediaType, caption, textContent, mediaURL, fileName, contentType, objectKey string
	var size int64
	var durationMS int
	err = tx.QueryRow(ctx, `SELECT s.media_id::text,s.media_type,COALESCE(s.caption,''),COALESCE(s.text_content,''),s.media_url,
		COALESCE(media.file_name,''),COALESCE(media.content_type,''),COALESCE(media.object_key,''),COALESCE(media.size_bytes,0),COALESCE(media.duration_ms,0)
		FROM statuses s LEFT JOIN media_objects media ON media.id=s.media_id
		WHERE s.id=$1 AND s.user_id=$2 AND s.expires_at>NOW() FOR SHARE OF s`, c.Param("id"), userID).Scan(&mediaID, &mediaType, &caption, &textContent, &mediaURL, &fileName, &contentType, &objectKey, &size, &durationMS)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "active status not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be shared"})
		return
	}

	body := textContent
	metadata := gin.H{"forwarded": true, "status_share": true}
	if mediaType != "text" {
		if mediaID == nil {
			c.JSON(http.StatusConflict, gin.H{"error": "status media is unavailable"})
			return
		}
		body = strings.TrimSpace(caption)
		if body == "" {
			body = "Photo status"
			if mediaType == "video" {
				body = "Video status"
			}
		}
		metadata["file_name"] = fileName
		metadata["content_type"] = contentType
		metadata["object_key"] = objectKey
		metadata["size"] = size
		metadata["duration_ms"] = durationMS
		metadata["url"] = mediaURL
		metadata["caption"] = caption
	}
	metadataJSON, _ := json.Marshal(metadata)
	created := make([]statusShareMessage, 0, len(conversationIDs))
	for _, conversationID := range conversationIDs {
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
		if tx.QueryRow(ctx, `SELECT member.user_id::text FROM conversations conversation JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id<>$2 WHERE conversation.id=$1 AND conversation.kind='direct' LIMIT 1`, conversationID, userID).Scan(&otherID) == nil && usersBlocked(userID, otherID) {
			c.JSON(http.StatusForbidden, gin.H{"error": "a selected conversation is blocked"})
			return
		}
		deliveryStatus := "sent"
		if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) {
			deliveryStatus = "delivered"
		}
		item := statusShareMessage{ConversationID: conversationID, Kind: mediaType, Body: body, Status: deliveryStatus, Metadata: metadata}
		err = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status) VALUES($1,$2,$3,$4,$5,$6) RETURNING id::text,created_at`, conversationID, userID, mediaType, body, metadataJSON, deliveryStatus).Scan(&item.ID, &item.CreatedAt)
		if err == nil && mediaID != nil {
			_, err = tx.Exec(ctx, `INSERT INTO message_attachments(message_id,media_id) VALUES($1,$2)`, item.ID, *mediaID)
		}
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, item.CreatedAt)
		}
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID)
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be shared"})
			return
		}
		created = append(created, item)
	}
	if tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be shared"})
		return
	}

	for _, item := range created {
		senderName, senderAvatar := messageSenderIdentity(ctx, item.ConversationID, userID)
		payload := gin.H{"type": "message", "id": item.ID, "conversation_id": item.ConversationID, "sender_id": userID, "sender_name": senderName, "sender_avatar_url": senderAvatar, "text": item.Body, "kind": item.Kind, "status": item.Status, "created_at": item.CreatedAt, "forwarded": true}
		if item.Kind != "text" {
			payload["attachment"] = item.Metadata
		}
		broadcast(item.ConversationID, userID, payload)
		notifyConversation(item.ConversationID, userID, "message", "Shared status", item.Body, map[string]any{"conversation_id": item.ConversationID, "message_id": item.ID, "status_id": c.Param("id")})
	}
	c.JSON(http.StatusCreated, gin.H{"shared_count": len(created)})
}

func sendStatusChatMessage(c *gin.Context, text, reaction string) {
	userID := c.GetString("user_id")
	action := "reply"
	if reaction != "" {
		action = "reaction"
	}
	failureMessage := "status " + action + " could not be sent"

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": failureMessage})
		return
	}
	defer tx.Rollback(ctx)

	var ownerID, ownerName, mediaURL, mediaType, caption, textContent, backgroundColor string
	err = tx.QueryRow(ctx, `SELECT s.user_id::text,COALESCE(NULLIF(owner.full_name,''),NULLIF(owner.username,''),'GroopX user'),s.media_url,s.media_type,COALESCE(s.caption,''),COALESCE(s.text_content,''),s.background_color
		FROM statuses s JOIN users owner ON owner.id=s.user_id
		WHERE s.id=$1 AND s.user_id<>$2 AND s.expires_at>NOW() AND owner.account_status='active'
		AND EXISTS(SELECT 1 FROM contacts contact WHERE contact.owner_id=s.user_id AND contact.contact_user_id=$2)
		AND EXISTS(SELECT 1 FROM contacts contact WHERE contact.owner_id=$2 AND contact.contact_user_id=s.user_id)
		AND (
			COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='contacts'
			OR (COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='contacts_except' AND NOT EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=s.user_id AND selected.contact_user_id=$2))
			OR (COALESCE((SELECT privacy.audience FROM status_privacy_settings privacy WHERE privacy.user_id=s.user_id),'contacts')='only_share_with' AND EXISTS(SELECT 1 FROM status_privacy_contacts selected WHERE selected.user_id=s.user_id AND selected.contact_user_id=$2))
		)
		AND NOT EXISTS(SELECT 1 FROM user_blocks blocked WHERE (blocked.blocker_id=$2 AND blocked.blocked_id=s.user_id) OR (blocked.blocker_id=s.user_id AND blocked.blocked_id=$2))
		FOR SHARE OF s`, c.Param("id"), userID).Scan(&ownerID, &ownerName, &mediaURL, &mediaType, &caption, &textContent, &backgroundColor)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "status is no longer available"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": failureMessage})
		return
	}

	conversationID, err := ensureDirectConversation(ctx, tx, userID, ownerID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status " + action + " chat could not be opened"})
		return
	}
	statusReference := gin.H{"id": c.Param("id"), "user_id": ownerID, "user_name": ownerName, "media_url": mediaURL, "media_type": mediaType, "caption": caption, "text_content": textContent, "background_color": backgroundColor}
	if reaction != "" {
		statusReference["reaction"] = reaction
	}
	metadata, _ := json.Marshal(gin.H{"status_reply": statusReference})
	deliveryStatus := "sent"
	if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) {
		deliveryStatus = "delivered"
	}
	var messageID string
	var createdAt time.Time
	err = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status)
		VALUES($1,$2,'text',$3,$4,$5) RETURNING id::text,created_at`, conversationID, userID, text, metadata, deliveryStatus).Scan(&messageID, &createdAt)
	if err == nil {
		_, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, createdAt)
	}
	if err == nil {
		_, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1`, conversationID)
	}
	if err == nil {
		_, err = tx.Exec(ctx, `INSERT INTO status_views(status_id,user_id) VALUES($1,$2) ON CONFLICT(status_id,user_id) DO NOTHING`, c.Param("id"), userID)
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": failureMessage})
		return
	}

	senderName, senderAvatar := messageSenderIdentity(ctx, conversationID, userID)
	payload := gin.H{"type": "message", "id": messageID, "conversation_id": conversationID, "sender_id": userID, "sender_name": senderName, "sender_avatar_url": senderAvatar, "text": text, "kind": "text", "status": deliveryStatus, "created_at": createdAt, "status_reply": statusReference}
	broadcast(conversationID, userID, payload)
	notificationTitle := "Status reply"
	if reaction != "" {
		notificationTitle = "Status reaction"
	}
	notificationData := map[string]any{"conversation_id": conversationID, "message_id": messageID, "status_id": c.Param("id")}
	if reaction != "" {
		notificationData["reaction"] = reaction
	}
	notifyConversation(conversationID, userID, "message", notificationTitle, text, notificationData)
	payload["mine"] = true
	c.JSON(http.StatusCreated, payload)
}

func listStatusViewers(c *gin.Context) {
	var readReceiptsEnabled bool
	err := db.QueryRow(c.Request.Context(), `SELECT owner.read_receipts FROM statuses status_item JOIN users owner ON owner.id=status_item.user_id WHERE status_item.id=$1 AND status_item.user_id=$2`, c.Param("id"), c.GetString("user_id")).Scan(&readReceiptsEnabled)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "status not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status viewers could not be loaded"})
		return
	}
	if !readReceiptsEnabled {
		c.JSON(http.StatusOK, gin.H{"items": []gin.H{}, "read_receipts_enabled": false})
		return
	}
	rows, err := db.Query(c.Request.Context(), `SELECT u.id::text,COALESCE(u.full_name,u.username,'GroopX user'),COALESCE(u.avatar_url,''),v.viewed_at,
		COALESCE((SELECT reaction_message.metadata->'status_reply'->>'reaction' FROM messages reaction_message
			WHERE reaction_message.sender_id=v.user_id AND reaction_message.deleted_at IS NULL
			AND reaction_message.metadata->'status_reply'->>'id'=v.status_id::text
			AND COALESCE(reaction_message.metadata->'status_reply'->>'reaction','')<>''
			ORDER BY reaction_message.created_at DESC,reaction_message.id DESC LIMIT 1),'') AS reaction,
		EXISTS(SELECT 1 FROM status_likes status_like WHERE status_like.status_id=v.status_id AND status_like.user_id=v.user_id) AS liked
		FROM status_views v JOIN statuses s ON s.id=v.status_id JOIN users u ON u.id=v.user_id
			AND (u.read_receipts=TRUE OR EXISTS(SELECT 1 FROM status_likes status_like WHERE status_like.status_id=v.status_id AND status_like.user_id=v.user_id))
		WHERE v.status_id=$1 AND s.user_id=$2 AND v.user_id<>s.user_id ORDER BY v.viewed_at DESC`, c.Param("id"), c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status viewers could not be loaded"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, name, avatar, reaction string
		var liked bool
		var viewedAt time.Time
		if rows.Scan(&id, &name, &avatar, &viewedAt, &reaction, &liked) == nil {
			items = append(items, gin.H{"user_id": id, "name": name, "avatar_url": avatar, "viewed_at": viewedAt, "reaction": reaction, "liked": liked})
		}
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status viewers could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "read_receipts_enabled": true})
}

func deleteStatus(c *gin.Context) {
	tx, err := db.Begin(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be deleted"})
		return
	}
	defer tx.Rollback(c.Request.Context())
	var mediaID *string
	if tx.QueryRow(c.Request.Context(), `DELETE FROM statuses WHERE id=$1 AND user_id=$2 RETURNING media_id::text`, c.Param("id"), c.GetString("user_id")).Scan(&mediaID) != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "status not found"})
		return
	}
	if mediaID != nil {
		_, err = tx.Exec(c.Request.Context(), `DELETE FROM media_objects media WHERE media.id=$1 AND NOT EXISTS(SELECT 1 FROM message_attachments attachment WHERE attachment.media_id=media.id)`, *mediaID)
	}
	if err != nil || tx.Commit(c.Request.Context()) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "status could not be deleted"})
		return
	}
	c.Status(http.StatusNoContent)
}
