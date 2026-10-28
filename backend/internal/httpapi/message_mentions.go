package httpapi

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"unicode"

	"github.com/jackc/pgx/v5"
)

const maximumMessageMentions = 20

var errInvalidMessageMentions = errors.New("mentions must be current group members present in the message")

type messageMention struct {
	userID string
	handle string
}

func mentionHandle(userID, name, username string) string {
	raw := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(username), "@"))
	fromName := raw == ""
	if fromName {
		raw = strings.TrimSpace(name)
	}
	var value strings.Builder
	lastUnderscore := false
	for _, current := range raw {
		allowed := unicode.IsLetter(current) || unicode.IsDigit(current) || current == '_'
		if allowed {
			if value.Len() >= 36 {
				break
			}
			value.WriteRune(current)
			lastUnderscore = current == '_'
		} else if value.Len() > 0 && !lastUnderscore {
			value.WriteByte('_')
			lastUnderscore = true
		}
	}
	handle := strings.Trim(value.String(), "_")
	if handle == "" {
		handle = "member"
	}
	if fromName {
		suffix := strings.ReplaceAll(userID, "-", "")
		if len(suffix) > 4 {
			suffix = suffix[:4]
		}
		if suffix != "" {
			handle += "_" + suffix
		}
	}
	return handle
}

func textContainsMention(text, handle string) bool {
	if strings.TrimSpace(handle) == "" {
		return false
	}
	pattern := `(?i)(^|[\s\(\[\{])@` + regexp.QuoteMeta(handle) + `($|[\s\.,!\?;:\)\]\}])`
	return regexp.MustCompile(pattern).MatchString(text)
}

func validateMessageMentions(ctx context.Context, conversationID, senderID, text string, requested []string) ([]messageMention, error) {
	if len(requested) == 0 {
		return nil, nil
	}
	unique := make([]string, 0, len(requested))
	seen := make(map[string]bool, len(requested))
	for _, userID := range requested {
		userID = strings.TrimSpace(userID)
		if userID == "" || seen[userID] {
			continue
		}
		seen[userID] = true
		unique = append(unique, userID)
	}
	if len(unique) == 0 || len(unique) > maximumMessageMentions {
		return nil, errInvalidMessageMentions
	}
	var kind string
	if err := db.QueryRow(ctx, `SELECT kind::text FROM conversations WHERE id=$1 AND deleted_at IS NULL`, conversationID).Scan(&kind); err != nil || (kind != "group" && kind != "community") {
		return nil, errInvalidMessageMentions
	}
	rows, err := db.Query(ctx, `SELECT users.id::text,
		COALESCE(NULLIF(users.full_name,''),NULLIF(users.username,''),'GroopX member'),
		COALESCE(users.username,'')
		FROM conversation_members member
		JOIN users ON users.id=member.user_id AND users.account_status='active'
		WHERE member.conversation_id=$1 AND member.user_id<>$2 AND users.id::text=ANY($3::text[])`, conversationID, senderID, unique)
	if err != nil {
		return nil, errInvalidMessageMentions
	}
	defer rows.Close()
	found := make(map[string]messageMention, len(unique))
	for rows.Next() {
		var userID, name, username string
		if rows.Scan(&userID, &name, &username) != nil {
			return nil, errInvalidMessageMentions
		}
		found[userID] = messageMention{userID: userID, handle: mentionHandle(userID, name, username)}
	}
	if rows.Err() != nil || len(found) != len(unique) {
		return nil, errInvalidMessageMentions
	}
	mentions := make([]messageMention, 0, len(unique))
	for _, userID := range unique {
		mention, ok := found[userID]
		if !ok || !textContainsMention(text, mention.handle) {
			return nil, errInvalidMessageMentions
		}
		mentions = append(mentions, mention)
	}
	return mentions, nil
}

func insertMessageMentions(ctx context.Context, tx pgx.Tx, messageID string, mentions []messageMention) error {
	for _, mention := range mentions {
		if _, err := tx.Exec(ctx, `INSERT INTO message_mentions(message_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`, messageID, mention.userID); err != nil {
			return err
		}
	}
	return nil
}

func mentionUserIDs(mentions []messageMention) []string {
	ids := make([]string, 0, len(mentions))
	for _, mention := range mentions {
		ids = append(ids, mention.userID)
	}
	return ids
}

func loadMessageMentionIDs(ctx context.Context, messageID string) ([]string, error) {
	rows, err := db.Query(ctx, `SELECT user_id::text FROM message_mentions WHERE message_id=$1 ORDER BY user_id`, messageID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	ids := make([]string, 0)
	for rows.Next() {
		var userID string
		if rows.Scan(&userID) != nil {
			return nil, errInvalidMessageMentions
		}
		ids = append(ids, userID)
	}
	return ids, rows.Err()
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func payloadMentionsUser(value any, userID string) bool {
	switch values := value.(type) {
	case []string:
		return containsString(values, userID)
	case []any:
		for _, value := range values {
			if text, ok := value.(string); ok && text == userID {
				return true
			}
		}
	}
	return false
}
