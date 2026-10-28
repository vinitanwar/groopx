package httpapi

import (
	"errors"
	"net/http"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

func normalizeCommunityDetails(name, description string) (string, string, error) {
	clean := func(value string, multiline bool) (string, bool) {
		for _, character := range value {
			if unicode.Is(unicode.Cf, character) || (unicode.IsControl(character) && !(multiline && unicode.IsSpace(character))) {
				return "", false
			}
		}
		return strings.Join(strings.Fields(value), " "), true
	}

	name, valid := clean(strings.TrimSpace(name), false)
	if !valid || utf8.RuneCountInString(name) < 2 || utf8.RuneCountInString(name) > 80 {
		return "", "", errors.New("community name must be between 2 and 80 characters")
	}
	description, valid = clean(strings.TrimSpace(description), true)
	if !valid || utf8.RuneCountInString(description) > 200 {
		return "", "", errors.New("community description must be 200 characters or less")
	}
	return name, description, nil
}

func listCommunities(c *gin.Context) {
	userID := c.GetString("user_id")
	rows, err := db.Query(c.Request.Context(), `SELECT conversation.id::text,COALESCE(conversation.title,''),
		COALESCE(conversation.description,''),member.role,
		(SELECT COUNT(*) FROM community_groups link WHERE link.community_id=conversation.id),
		(SELECT COUNT(*) FROM conversation_members members WHERE members.conversation_id=conversation.id)
		FROM conversations conversation
		JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$1
		WHERE conversation.kind='community' AND conversation.deleted_at IS NULL
		ORDER BY conversation.updated_at DESC`, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "communities could not be loaded"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id, name, description, role string
		var groupCount, memberCount int
		if rows.Scan(&id, &name, &description, &role, &groupCount, &memberCount) != nil {
			continue
		}
		items = append(items, gin.H{
			"id": id, "name": name, "description": description, "role": role,
			"group_count": groupCount, "member_count": memberCount,
		})
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "communities could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func listManageableGroups(c *gin.Context) {
	rows, err := db.Query(c.Request.Context(), `SELECT conversation.id::text,COALESCE(conversation.title,''),
		(SELECT COUNT(*) FROM conversation_members WHERE conversation_id=conversation.id)
		FROM conversations conversation
		JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$1 AND member.role='admin'
		WHERE conversation.kind='group' AND conversation.deleted_at IS NULL ORDER BY conversation.title`, c.GetString("user_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "groups could not be loaded"})
		return
	}
	defer rows.Close()

	items := make([]gin.H, 0)
	for rows.Next() {
		var id, name string
		var members int
		if rows.Scan(&id, &name, &members) == nil {
			items = append(items, gin.H{"id": id, "name": name, "member_count": members})
		}
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "groups could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func createCommunity(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		Name        string `json:"name" binding:"required"`
		Description string `json:"description"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid community"})
		return
	}
	name, description, err := normalizeCommunityDetails(input.Name, input.Description)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be created"})
		return
	}
	defer tx.Rollback(ctx)

	var id string
	err = tx.QueryRow(ctx, `INSERT INTO conversations(kind,title,description,privacy,created_by)
		VALUES('community',$1,NULLIF($2,''),'private',$3) RETURNING id::text`, name, description, userID).Scan(&id)
	if err == nil {
		_, err = tx.Exec(ctx, `INSERT INTO conversation_members(conversation_id,user_id,role) VALUES($1,$2,'admin')`, id, userID)
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be saved"})
		return
	}
	creatorName, err := groupActivityUserName(ctx, tx, id, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community activity could not be saved"})
		return
	}
	activity, err := recordGroupActivity(ctx, tx, id, "community_created", userID, "", groupActivityText("community_created", creatorName, "", ""))
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be saved"})
		return
	}
	publishGroupActivity(&activity)
	c.JSON(http.StatusCreated, gin.H{"id": id, "name": name, "description": description, "role": "admin", "member_count": 1})
}

func getCommunity(c *gin.Context) {
	id, userID := c.Param("id"), c.GetString("user_id")
	var name, description, role string
	var memberCount int
	err := db.QueryRow(c.Request.Context(), `SELECT COALESCE(conversation.title,''),COALESCE(conversation.description,''),
		member.role,(SELECT COUNT(*) FROM conversation_members WHERE conversation_id=conversation.id)
		FROM conversations conversation
		JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$2
		WHERE conversation.id=$1 AND conversation.kind='community' AND conversation.deleted_at IS NULL`, id, userID).
		Scan(&name, &description, &role, &memberCount)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a community member"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be loaded"})
		return
	}

	rows, err := db.Query(c.Request.Context(), `SELECT linked.id::text,COALESCE(linked.title,''),
		(SELECT COUNT(*) FROM conversation_members WHERE conversation_id=linked.id)
		FROM community_groups link JOIN conversations linked ON linked.id=link.group_id
		WHERE link.community_id=$1 AND linked.deleted_at IS NULL ORDER BY linked.title`, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community groups could not be loaded"})
		return
	}
	defer rows.Close()

	groups := make([]gin.H, 0)
	for rows.Next() {
		var groupID, title string
		var groupMemberCount int
		if rows.Scan(&groupID, &title, &groupMemberCount) == nil {
			groups = append(groups, gin.H{"id": groupID, "name": title, "member_count": groupMemberCount})
		}
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community groups could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"id": id, "name": name, "description": description, "role": role,
		"member_count": memberCount, "groups": groups,
	})
}

func updateCommunity(c *gin.Context) {
	communityID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		Name        string `json:"name" binding:"required"`
		Description string `json:"description"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid community"})
		return
	}
	name, description, err := normalizeCommunityDetails(input.Name, input.Description)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be updated"})
		return
	}
	defer tx.Rollback(ctx)

	var oldName, oldDescription, role string
	err = tx.QueryRow(ctx, `SELECT COALESCE(conversation.title,''),COALESCE(conversation.description,''),member.role
		FROM conversations conversation
		JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$2
		WHERE conversation.id=$1 AND conversation.kind='community' AND conversation.deleted_at IS NULL
		FOR UPDATE OF conversation,member`, communityID, userID).Scan(&oldName, &oldDescription, &role)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusForbidden, gin.H{"error": "community admin access required"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be updated"})
		return
	}
	if role != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "community admin access required"})
		return
	}
	if name == oldName && description == oldDescription {
		if tx.Commit(ctx) != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be updated"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"id": communityID, "name": name, "description": description, "role": role})
		return
	}
	if _, err = tx.Exec(ctx, `UPDATE conversations SET title=$2,description=NULLIF($3,''),updated_at=NOW() WHERE id=$1`, communityID, name, description); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be updated"})
		return
	}
	actorName, err := groupActivityUserName(ctx, tx, communityID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community activity could not be saved"})
		return
	}
	activities := make([]groupActivityMessage, 0, 2)
	if name != oldName {
		activity, activityErr := recordGroupActivity(ctx, tx, communityID, "community_renamed", userID, "", groupActivityText("community_renamed", actorName, "", name))
		if activityErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "community activity could not be saved"})
			return
		}
		activities = append(activities, activity)
	}
	if description != oldDescription {
		activity, activityErr := recordGroupActivity(ctx, tx, communityID, "community_settings_updated", userID, "", groupActivityText("community_settings_updated", actorName, "", ""))
		if activityErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "community activity could not be saved"})
			return
		}
		activities = append(activities, activity)
	}
	if tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community could not be updated"})
		return
	}
	for index := range activities {
		publishGroupActivity(&activities[index])
	}
	broadcast(communityID, userID, gin.H{"type": "group_settings_update", "conversation_id": communityID, "name": name, "description": description})
	broadcastConversationUpdate(communityID, "community_settings_update")
	c.JSON(http.StatusOK, gin.H{"id": communityID, "name": name, "description": description, "role": role})
}

func addCommunityGroup(c *gin.Context) {
	communityID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		GroupID string `json:"group_id" binding:"required,uuid"`
	}
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid group_id is required"})
		return
	}

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be linked"})
		return
	}
	defer tx.Rollback(ctx)

	var communityRole, groupRole, groupName string
	err = tx.QueryRow(ctx, `SELECT community_member.role,linked_member.role,COALESCE(linked.title,'Group')
		FROM conversations community
		JOIN conversation_members community_member ON community_member.conversation_id=community.id AND community_member.user_id=$2
		JOIN conversations linked ON linked.id=$3 AND linked.kind='group' AND linked.deleted_at IS NULL
		JOIN conversation_members linked_member ON linked_member.conversation_id=linked.id AND linked_member.user_id=$2
		WHERE community.id=$1 AND community.kind='community' AND community.deleted_at IS NULL
		FOR UPDATE OF community,community_member,linked,linked_member`, communityID, userID, input.GroupID).
		Scan(&communityRole, &groupRole, &groupName)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusForbidden, gin.H{"error": "you must be an admin of both the community and group"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be linked"})
		return
	}
	if communityRole != "admin" || groupRole != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "you must be an admin of both the community and group"})
		return
	}
	result, err := tx.Exec(ctx, `INSERT INTO community_groups(community_id,group_id,added_by)
		VALUES($1,$2,$3) ON CONFLICT DO NOTHING`, communityID, input.GroupID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be linked"})
		return
	}
	if result.RowsAffected() == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "group is already linked"})
		return
	}
	actorName, err := groupActivityUserName(ctx, tx, communityID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community activity could not be saved"})
		return
	}
	activity, err := recordGroupActivity(ctx, tx, communityID, "community_group_added", userID, input.GroupID, groupActivityText("community_group_added", actorName, groupName, ""))
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be linked"})
		return
	}
	publishGroupActivity(&activity)
	broadcast(communityID, userID, gin.H{"type": "group_settings_update", "conversation_id": communityID, "linked_group_id": input.GroupID})
	broadcastConversationUpdate(communityID, "community_group_added")
	c.Status(http.StatusNoContent)
}

func removeCommunityGroup(c *gin.Context) {
	communityID, groupID, userID := c.Param("id"), c.Param("groupId"), c.GetString("user_id")
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be unlinked"})
		return
	}
	defer tx.Rollback(ctx)

	var role string
	err = tx.QueryRow(ctx, `SELECT member.role FROM conversations community
		JOIN conversation_members member ON member.conversation_id=community.id AND member.user_id=$2
		WHERE community.id=$1 AND community.kind='community' AND community.deleted_at IS NULL
		FOR UPDATE OF community,member`, communityID, userID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusForbidden, gin.H{"error": "community admin access required"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be unlinked"})
		return
	}
	if role != "admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "community admin access required"})
		return
	}
	var groupName string
	err = tx.QueryRow(ctx, `SELECT COALESCE(linked.title,'Group') FROM community_groups link
		JOIN conversations linked ON linked.id=link.group_id
		WHERE link.community_id=$1 AND link.group_id=$2 FOR UPDATE OF linked`, communityID, groupID).Scan(&groupName)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error": "linked group not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be unlinked"})
		return
	}
	if _, err = tx.Exec(ctx, `DELETE FROM community_groups WHERE community_id=$1 AND group_id=$2`, communityID, groupID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be unlinked"})
		return
	}
	actorName, err := groupActivityUserName(ctx, tx, communityID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "community activity could not be saved"})
		return
	}
	activity, err := recordGroupActivity(ctx, tx, communityID, "community_group_removed", userID, groupID, groupActivityText("community_group_removed", actorName, groupName, ""))
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "group could not be unlinked"})
		return
	}
	publishGroupActivity(&activity)
	broadcast(communityID, userID, gin.H{"type": "group_settings_update", "conversation_id": communityID, "unlinked_group_id": groupID})
	broadcastConversationUpdate(communityID, "community_group_removed")
	c.Status(http.StatusNoContent)
}
