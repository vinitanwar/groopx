package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
)

type pollSnapshot struct {
	attachment     gin.H
	messageID      string
	conversationID string
}

func normalizePoll(question string, options []string) (string, []string, bool) {
	question, valid := normalizePollValue(question, 300)
	if !valid || len(options) < 2 || len(options) > 12 {
		return "", nil, false
	}
	normalized := make([]string, 0, len(options))
	seen := make(map[string]bool, len(options))
	for _, option := range options {
		value, optionValid := normalizePollValue(option, 120)
		key := strings.ToLower(value)
		if !optionValid || seen[key] {
			return "", nil, false
		}
		seen[key] = true
		normalized = append(normalized, value)
	}
	return question, normalized, true
}

func normalizePollValue(value string, maximum int) (string, bool) {
	if !utf8.ValidString(value) {
		return "", false
	}
	for _, character := range value {
		if unicode.IsControl(character) {
			return "", false
		}
	}
	value = strings.Join(strings.Fields(value), " ")
	return value, value != "" && utf8.RuneCountInString(value) <= maximum
}

func createPoll(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		Question      string   `json:"question"`
		Options       []string `json:"options"`
		AllowMultiple bool     `json:"allow_multiple"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "poll question and options are required"})
		return
	}
	question, options, valid := normalizePoll(input.Question, input.Options)
	if !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": "add a question and 2 to 12 unique options"})
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

	status := "sent"
	if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) {
		status = "delivered"
	}
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "poll could not be created"})
		return
	}
	defer tx.Rollback(ctx)

	var messageID, pollID string
	var createdAt time.Time
	err = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status)
		VALUES($1,$2,'poll',$3,'{}'::jsonb,$4) RETURNING id::text,created_at`, conversationID, userID, "Poll: "+question, status).Scan(&messageID, &createdAt)
	if err == nil {
		err = tx.QueryRow(ctx, `INSERT INTO message_polls(message_id,question,allow_multiple)
			VALUES($1,$2,$3) RETURNING id::text`, messageID, question, input.AllowMultiple).Scan(&pollID)
	}
	optionItems := make([]gin.H, 0, len(options))
	if err == nil {
		for position, option := range options {
			var optionID string
			err = tx.QueryRow(ctx, `INSERT INTO poll_options(poll_id,position,label) VALUES($1,$2,$3) RETURNING id::text`, pollID, position, option).Scan(&optionID)
			if err != nil {
				break
			}
			optionItems = append(optionItems, gin.H{"id": optionID, "text": option, "votes": 0, "selected": false})
		}
	}
	attachment := gin.H{"poll_id": pollID, "question": question, "allow_multiple": input.AllowMultiple, "closed": false, "total_votes": 0, "total_voters": 0, "options": optionItems}
	if err == nil {
		metadata, _ := json.Marshal(attachment)
		_, err = tx.Exec(ctx, `UPDATE messages SET metadata=$2 WHERE id=$1`, messageID, metadata)
	}
	if err == nil {
		_, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, createdAt)
	}
	if err == nil {
		_, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID)
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "poll could not be created"})
		return
	}

	senderName, senderAvatar := messageSenderIdentity(ctx, conversationID, userID)
	payload := gin.H{"type": "message", "id": messageID, "conversation_id": conversationID, "sender_id": userID, "sender_name": senderName, "sender_avatar_url": senderAvatar, "text": "Poll: " + question, "kind": "poll", "attachment": attachment, "status": status, "created_at": createdAt}
	broadcast(conversationID, userID, payload)
	notifyConversation(conversationID, userID, "poll", "New poll", question, map[string]any{"conversation_id": conversationID, "message_id": messageID, "poll_id": pollID})
	payload["mine"] = true
	c.JSON(http.StatusCreated, payload)
}

func setPollVotes(c *gin.Context) {
	pollID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		OptionIDs []string `json:"option_ids"`
	}
	if c.ShouldBindJSON(&input) != nil || len(input.OptionIDs) > 12 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid poll choices"})
		return
	}
	optionIDs := make([]string, 0, len(input.OptionIDs))
	seen := make(map[string]bool, len(input.OptionIDs))
	for _, optionID := range input.OptionIDs {
		optionID = strings.TrimSpace(optionID)
		if optionID == "" || seen[optionID] {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid poll choices"})
			return
		}
		seen[optionID] = true
		optionIDs = append(optionIDs, optionID)
	}

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "vote could not be saved"})
		return
	}
	defer tx.Rollback(ctx)
	var allowMultiple bool
	var closedAt *time.Time
	var conversationID string
	err = tx.QueryRow(ctx, `SELECT poll.allow_multiple,poll.closed_at,message.conversation_id::text
		FROM message_polls poll
		JOIN messages message ON message.id=poll.message_id AND message.deleted_at IS NULL
		JOIN conversation_members member ON member.conversation_id=message.conversation_id AND member.user_id=$2 AND member.hidden_at IS NULL
		WHERE poll.id::text=$1 FOR UPDATE OF poll`, pollID, userID).Scan(&allowMultiple, &closedAt, &conversationID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "poll not found"})
		return
	}
	if closedAt != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "this poll is closed"})
		return
	}
	if !allowMultiple && len(optionIDs) > 1 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "select only one option"})
		return
	}
	if scheduledCommunicationBlocked(ctx, conversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "communication is blocked"})
		return
	}
	if len(optionIDs) > 0 {
		var matching int
		if tx.QueryRow(ctx, `SELECT COUNT(*)::int FROM poll_options WHERE poll_id=$1 AND id::text=ANY($2::text[])`, pollID, optionIDs).Scan(&matching) != nil || matching != len(optionIDs) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "one or more poll choices are invalid"})
			return
		}
	}
	if _, err = tx.Exec(ctx, `DELETE FROM poll_votes WHERE poll_id=$1 AND user_id=$2`, pollID, userID); err == nil {
		for _, optionID := range optionIDs {
			if _, err = tx.Exec(ctx, `INSERT INTO poll_votes(poll_id,option_id,user_id) VALUES($1,$2,$3)`, pollID, optionID, userID); err != nil {
				break
			}
		}
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "vote could not be saved"})
		return
	}

	personal, err := loadPollSnapshot(ctx, pollID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "poll result could not be loaded"})
		return
	}
	broadcastPollUpdate(ctx, pollID, userID)
	c.JSON(http.StatusOK, gin.H{"attachment": personal.attachment})
}

func closePoll(c *gin.Context) {
	pollID, userID := c.Param("id"), c.GetString("user_id")
	ctx := c.Request.Context()
	result, err := db.Exec(ctx, `UPDATE message_polls poll SET closed_at=COALESCE(poll.closed_at,NOW())
		FROM messages message
		WHERE poll.id::text=$1 AND message.id=poll.message_id AND message.sender_id=$2 AND message.deleted_at IS NULL
		AND EXISTS(SELECT 1 FROM conversation_members member WHERE member.conversation_id=message.conversation_id AND member.user_id=$2 AND member.hidden_at IS NULL)`, pollID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "poll could not be closed"})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the poll creator can close this poll"})
		return
	}
	personal, err := loadPollSnapshot(ctx, pollID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "poll result could not be loaded"})
		return
	}
	broadcastPollUpdate(ctx, pollID, userID)
	c.JSON(http.StatusOK, gin.H{"attachment": personal.attachment})
}

func loadPollSnapshotByMessage(ctx context.Context, messageID, userID string) (pollSnapshot, error) {
	var pollID string
	if err := db.QueryRow(ctx, `SELECT id::text FROM message_polls WHERE message_id=$1`, messageID).Scan(&pollID); err != nil {
		return pollSnapshot{}, err
	}
	return loadPollSnapshot(ctx, pollID, userID)
}

func loadPollSnapshot(ctx context.Context, pollID, userID string) (pollSnapshot, error) {
	var snapshot pollSnapshot
	var question string
	var allowMultiple bool
	var closedAt *time.Time
	err := db.QueryRow(ctx, `SELECT poll.question,poll.allow_multiple,poll.closed_at,message.id::text,message.conversation_id::text
		FROM message_polls poll JOIN messages message ON message.id=poll.message_id
		WHERE poll.id::text=$1 AND message.deleted_at IS NULL`, pollID).Scan(&question, &allowMultiple, &closedAt, &snapshot.messageID, &snapshot.conversationID)
	if err != nil {
		return pollSnapshot{}, err
	}
	rows, err := db.Query(ctx, `SELECT choice.id::text,choice.label,COUNT(vote.user_id)::int,
		COALESCE(BOOL_OR(vote.user_id::text=$2),FALSE)
		FROM poll_options choice LEFT JOIN poll_votes vote ON vote.poll_id=choice.poll_id AND vote.option_id=choice.id
		WHERE choice.poll_id=$1 GROUP BY choice.id,choice.label,choice.position ORDER BY choice.position`, pollID, userID)
	if err != nil {
		return pollSnapshot{}, err
	}
	defer rows.Close()
	options := make([]gin.H, 0)
	totalVotes := 0
	for rows.Next() {
		var id, label string
		var votes int
		var selected bool
		if scanErr := rows.Scan(&id, &label, &votes, &selected); scanErr != nil {
			return pollSnapshot{}, scanErr
		}
		totalVotes += votes
		options = append(options, gin.H{"id": id, "text": label, "votes": votes, "selected": selected})
	}
	if err = rows.Err(); err != nil {
		return pollSnapshot{}, err
	}
	var totalVoters int
	if err = db.QueryRow(ctx, `SELECT COUNT(DISTINCT user_id)::int FROM poll_votes WHERE poll_id=$1`, pollID).Scan(&totalVoters); err != nil {
		return pollSnapshot{}, err
	}
	snapshot.attachment = gin.H{"poll_id": pollID, "question": question, "allow_multiple": allowMultiple, "closed": closedAt != nil, "closed_at": closedAt, "total_votes": totalVotes, "total_voters": totalVoters, "options": options}
	return snapshot, nil
}

func broadcastPollUpdate(ctx context.Context, pollID, senderID string) {
	publicSnapshot, err := loadPollSnapshot(ctx, pollID, "")
	if err != nil {
		return
	}
	personalSnapshot, personalErr := loadPollSnapshot(ctx, pollID, senderID)
	chatHub.RLock()
	clients := make([]*socketClient, 0, len(chatHub.rooms[publicSnapshot.conversationID]))
	for client := range chatHub.rooms[publicSnapshot.conversationID] {
		clients = append(clients, client)
	}
	chatHub.RUnlock()
	for _, client := range clients {
		attachment := publicSnapshot.attachment
		mine := client.userID == senderID
		if mine && personalErr == nil {
			attachment = personalSnapshot.attachment
		}
		payload := gin.H{"type": "poll_update", "conversation_id": publicSnapshot.conversationID, "message_id": publicSnapshot.messageID, "poll_id": pollID, "attachment": attachment, "mine": mine}
		if client.writeJSON(payload) != nil {
			leaveRoom(publicSnapshot.conversationID, client)
		}
	}
}
