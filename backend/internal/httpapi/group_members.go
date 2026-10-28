package httpapi

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

const (
	defaultGroupMemberPageSize = 20
	maximumGroupMemberPageSize = 50
	maximumGroupMemberOffset   = 100000
)

type groupMemberListQuery struct {
	search string
	role   string
	limit  int
	offset int
}

func normalizeGroupMemberListQuery(search, role, rawLimit, rawOffset string) (groupMemberListQuery, error) {
	query := groupMemberListQuery{
		search: strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(search), "@")),
		role:   strings.ToLower(strings.TrimSpace(role)),
		limit:  defaultGroupMemberPageSize,
	}
	if utf8.RuneCountInString(query.search) > 80 {
		return groupMemberListQuery{}, errors.New("search is too long")
	}
	if query.role == "all" {
		query.role = ""
	}
	if query.role != "" && query.role != "admin" && query.role != "member" {
		return groupMemberListQuery{}, errors.New("role must be all, admin or member")
	}
	if strings.TrimSpace(rawLimit) != "" {
		limit, err := strconv.Atoi(rawLimit)
		if err != nil || limit < 1 || limit > maximumGroupMemberPageSize {
			return groupMemberListQuery{}, errors.New("limit must be between 1 and 50")
		}
		query.limit = limit
	}
	if strings.TrimSpace(rawOffset) != "" {
		offset, err := strconv.Atoi(rawOffset)
		if err != nil || offset < 0 || offset > maximumGroupMemberOffset {
			return groupMemberListQuery{}, errors.New("offset is invalid")
		}
		query.offset = offset
	}
	return query, nil
}

func normalizeGroupMemberDisplayName(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", nil
	}
	for _, character := range value {
		if unicode.IsControl(character) || unicode.Is(unicode.Cf, character) {
			return "", errors.New("group name contains invalid characters")
		}
	}
	value = strings.Join(strings.Fields(value), " ")
	length := utf8.RuneCountInString(value)
	if length < 2 || length > 80 {
		return "", errors.New("group name must be between 2 and 80 characters")
	}
	return value, nil
}

func listGroupMembers(c *gin.Context) {
	groupID, userID := c.Param("id"), c.GetString("user_id")
	query, err := normalizeGroupMemberListQuery(c.Query("q"), c.Query("role"), c.Query("limit"), c.Query("offset"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var requesterRole string
	var membersCanAddMembers bool
	err = db.QueryRow(c.Request.Context(), `SELECT member.role,COALESCE(conversation.members_can_add_members,FALSE)
		FROM conversation_members member
		JOIN conversations conversation ON conversation.id=member.conversation_id
		WHERE member.conversation_id=$1 AND member.user_id=$2
		AND conversation.kind IN ('group','community') AND conversation.deleted_at IS NULL`, groupID, userID).Scan(&requesterRole, &membersCanAddMembers)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a group member"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "members could not be loaded"})
		return
	}

	filter := "%" + query.search + "%"
	var total int
	err = db.QueryRow(c.Request.Context(), `SELECT COUNT(*)::int
		FROM conversation_members member
		JOIN users account ON account.id=member.user_id
		WHERE member.conversation_id=$1
		AND ($2='' OR member.role=$2)
		AND ($3='' OR COALESCE(member.group_display_name,'') ILIKE $4 OR COALESCE(account.full_name,'') ILIKE $4 OR COALESCE(account.username,'') ILIKE $4)`, groupID, query.role, query.search, filter).Scan(&total)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "members could not be loaded"})
		return
	}

	rows, err := db.Query(c.Request.Context(), `SELECT account.id::text,
		COALESCE(NULLIF(member.group_display_name,''),NULLIF(account.full_name,''),NULLIF(account.username,''),'GroopX member'),
		COALESCE(NULLIF(account.full_name,''),NULLIF(account.username,''),'GroopX member'),COALESCE(member.group_display_name,''),
		COALESCE(account.username,''),COALESCE(account.avatar_url,''),member.role,account.account_status
		FROM conversation_members member
		JOIN users account ON account.id=member.user_id
		WHERE member.conversation_id=$1
		AND ($2='' OR member.role=$2)
		AND ($3='' OR COALESCE(member.group_display_name,'') ILIKE $4 OR COALESCE(account.full_name,'') ILIKE $4 OR COALESCE(account.username,'') ILIKE $4)
		ORDER BY (member.user_id=$5) DESC,(member.role='admin') DESC,
		LOWER(COALESCE(NULLIF(member.group_display_name,''),NULLIF(account.full_name,''),NULLIF(account.username,''),'GroopX member')),account.id
		LIMIT $6 OFFSET $7`, groupID, query.role, query.search, filter, userID, query.limit, query.offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "members could not be loaded"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0, query.limit)
	for rows.Next() {
		var memberID, name, profileName, displayName, username, avatarURL, role, accountStatus string
		if rows.Scan(&memberID, &name, &profileName, &displayName, &username, &avatarURL, &role, &accountStatus) != nil {
			continue
		}
		mention := ""
		if accountStatus == "active" {
			mention = mentionHandle(memberID, profileName, username)
		}
		items = append(items, gin.H{
			"id": memberID, "name": name, "username": username, "avatar_url": avatarURL,
			"profile_name": profileName, "display_name": displayName,
			"mention": mention, "role": role, "mine": memberID == userID,
		})
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "members could not be loaded"})
		return
	}

	returned := len(items)
	c.JSON(http.StatusOK, gin.H{
		"items": items, "total": total, "limit": query.limit, "offset": query.offset,
		"has_more": query.offset+returned < total,
		"admin": requesterRole == "admin",
		"can_add_members": groupCanAddMembers(requesterRole, membersCanAddMembers),
	})
}

func updateGroupMemberDisplayName(c *gin.Context) {
	groupID, actorID, targetID := c.Param("id"), c.GetString("user_id"), c.Param("userId")
	var input struct {
		DisplayName *string `json:"display_name"`
	}
	if c.ShouldBindJSON(&input) != nil || input.DisplayName == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "display_name is required"})
		return
	}
	displayName, err := normalizeGroupMemberDisplayName(*input.DisplayName)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member name could not be updated"})
		return
	}
	defer tx.Rollback(ctx)

	var actorRole, conversationKind string
	err = tx.QueryRow(ctx, `SELECT member.role,conversation.kind::text FROM conversation_members member
		JOIN conversations conversation ON conversation.id=member.conversation_id
		WHERE member.conversation_id=$1 AND member.user_id=$2
		AND conversation.kind IN ('group','community') AND conversation.deleted_at IS NULL
		FOR UPDATE OF conversation,member`, groupID, actorID).Scan(&actorRole, &conversationKind)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusForbidden, gin.H{"error": "admin access required"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member name could not be updated"})
		return
	}
	if actorRole != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "admin access required"})
		return
	}

	var profileName, currentDisplayName string
	err = tx.QueryRow(ctx, `SELECT COALESCE(NULLIF(account.full_name,''),NULLIF(account.username,''),'GroopX member'),COALESCE(member.group_display_name,'')
		FROM conversation_members member JOIN users account ON account.id=member.user_id
		WHERE member.conversation_id=$1 AND member.user_id=$2 FOR UPDATE OF member`, groupID, targetID).Scan(&profileName, &currentDisplayName)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member name could not be updated"})
		return
	}
	if currentDisplayName == displayName {
		c.JSON(http.StatusOK, gin.H{"display_name": displayName, "name": effectiveGroupMemberName(displayName, profileName), "profile_name": profileName})
		return
	}
	if _, err = tx.Exec(ctx, `UPDATE conversation_members SET group_display_name=NULLIF($3,'') WHERE conversation_id=$1 AND user_id=$2`, groupID, targetID, displayName); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member name could not be updated"})
		return
	}
	actorName, err := groupActivityUserName(ctx, tx, groupID, actorID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group activity could not be saved"})
		return
	}
	event := "member_display_name_updated"
	if displayName == "" {
		event = "member_display_name_reset"
	}
	if conversationKind == "community" {
		event = "community_member_display_name_updated"
		if displayName == "" {
			event = "community_member_display_name_reset"
		}
	}
	activity, err := recordGroupActivity(ctx, tx, groupID, event, actorID, targetID, groupActivityText(event, actorName, profileName, displayName))
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "member name could not be updated"})
		return
	}

	name := effectiveGroupMemberName(displayName, profileName)
	publishGroupActivity(&activity)
	broadcast(groupID, actorID, gin.H{"type": "group_member_update", "conversation_id": groupID, "user_id": targetID, "display_name": displayName, "name": name})
	broadcastConversationUpdate(groupID, "group_member_display_name_update")
	c.JSON(http.StatusOK, gin.H{"display_name": displayName, "name": name, "profile_name": profileName})
}

func effectiveGroupMemberName(displayName, profileName string) string {
	if strings.TrimSpace(displayName) != "" {
		return displayName
	}
	return profileName
}
