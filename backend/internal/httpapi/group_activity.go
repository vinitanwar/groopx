package httpapi

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

type groupActivityRowQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

type groupActivityMessage struct {
	id             string
	conversationID string
	body           string
	createdAt      time.Time
}

func groupActivityUserName(ctx context.Context, querier groupActivityRowQuerier, conversationID, userID string) (string, error) {
	var name string
	err := querier.QueryRow(ctx, `SELECT COALESCE(NULLIF(member.group_display_name,''),NULLIF(account.full_name,''),NULLIF(account.username,''),'GroopX member')
		FROM users account
		LEFT JOIN conversation_members member ON member.conversation_id=$1 AND member.user_id=account.id
		WHERE account.id=$2`, conversationID, userID).Scan(&name)
	return name, err
}

func recordGroupActivity(ctx context.Context, querier groupActivityRowQuerier, conversationID, event, actorID, targetID, body string) (groupActivityMessage, error) {
	metadata, _ := json.Marshal(gin.H{"event":event,"actor_id":actorID,"target_id":targetID})
	message := groupActivityMessage{conversationID: conversationID, body: strings.TrimSpace(body)}
	err := querier.QueryRow(ctx, `WITH saved AS (
		INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status)
		VALUES($1,NULL,'system',$2,$3,'sent') RETURNING id,created_at
	), updated_conversation AS (
		UPDATE conversations SET last_message_at=(SELECT created_at FROM saved),updated_at=NOW() WHERE id=$1 RETURNING id
	), unhidden_members AS (
		UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 RETURNING user_id
	)
	SELECT id::text,created_at FROM saved`, conversationID, message.body, metadata).Scan(&message.id, &message.createdAt)
	return message, err
}

func publishGroupActivity(message *groupActivityMessage) {
	if message == nil || message.id == "" {
		return
	}
	broadcast(message.conversationID, "", gin.H{
		"type":              "message",
		"id":                message.id,
		"conversation_id":   message.conversationID,
		"sender_id":         "",
		"sender_name":       "",
		"sender_avatar_url": "",
		"text":              message.body,
		"kind":              "system",
		"status":            "sent",
		"created_at":        message.createdAt,
	})
}

func groupActivityText(event, actor, target, detail string) string {
	switch event {
	case "community_created":
		return actor + " created this community"
	case "community_renamed":
		return actor + " changed the community name to “" + detail + "”"
	case "community_settings_updated":
		return actor + " updated community info"
	case "community_group_added":
		return actor + " linked " + target + " to this community"
	case "community_group_removed":
		return actor + " unlinked " + target + " from this community"
	case "community_admin_granted":
		return actor + " made " + target + " a community admin"
	case "community_admin_revoked":
		return actor + " removed " + target + " as community admin"
	case "community_member_display_name_updated":
		return actor + " changed " + target + "'s community name to “" + detail + "”"
	case "community_member_display_name_reset":
		return actor + " reset " + target + "'s community name"
	case "community_member_left":
		return actor + " left the community"
	case "group_created":
		return actor + " created this group"
	case "group_renamed":
		return actor + " changed the group name to “" + detail + "”"
	case "announcement_enabled":
		return actor + " enabled announcement mode"
	case "announcement_disabled":
		return actor + " turned off announcement mode"
	case "group_settings_updated":
		return actor + " updated group settings"
	case "group_permissions_updated":
		return actor + " updated group permissions"
	case "group_photo_updated":
		return actor + " changed the group photo"
	case "group_photo_removed":
		return actor + " removed the group photo"
	case "member_added":
		return actor + " added " + target
	case "member_removed":
		return actor + " removed " + target
	case "member_joined":
		return actor + " joined using an invite link"
	case "join_approved":
		return actor + " approved " + target + " to join"
	case "admin_granted":
		return actor + " made " + target + " a group admin"
	case "admin_revoked":
		return actor + " removed " + target + " as group admin"
	case "member_display_name_updated":
		return actor + " changed " + target + "'s group name to “" + detail + "”"
	case "member_display_name_reset":
		return actor + " reset " + target + "'s group name"
	case "member_left":
		return actor + " left the group"
	default:
		return actor + " updated the group"
	}
}
