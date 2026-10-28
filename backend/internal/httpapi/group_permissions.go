package httpapi

import (
	"context"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

const announcementOnlyMessage = "Only group admins can send messages in announcement mode"

type conversationPermissionQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

type groupManagementAccess struct {
	role                 string
	membersCanEditInfo   bool
	membersCanAddMembers bool
}

func groupAllowsSender(kind string, announcementOnly bool, role string) bool {
	return kind != "group" || !announcementOnly || role == "admin"
}

func groupCanEditInfo(role string, membersCanEditInfo bool) bool {
	return role == "admin" || membersCanEditInfo
}

func groupCanAddMembers(role string, membersCanAddMembers bool) bool {
	return role == "admin" || membersCanAddMembers
}

func loadGroupManagementAccess(ctx context.Context, query conversationPermissionQuerier, groupID, userID string) (groupManagementAccess, error) {
	var access groupManagementAccess
	err := query.QueryRow(ctx, `SELECT member.role,COALESCE(conversation.members_can_edit_info,FALSE),COALESCE(conversation.members_can_add_members,FALSE)
		FROM conversations conversation
		JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$2
		WHERE conversation.id=$1 AND conversation.kind IN ('group','community') AND conversation.deleted_at IS NULL
		FOR UPDATE OF conversation,member`, groupID, userID).
		Scan(&access.role, &access.membersCanEditInfo, &access.membersCanAddMembers)
	return access, err
}

func conversationAllowsSender(ctx context.Context, query conversationPermissionQuerier, conversationID, userID string) (bool, error) {
	var kind, role string
	var announcementOnly bool
	err := query.QueryRow(ctx, `SELECT conversation.kind::text,COALESCE(conversation.announcement_only,FALSE),member.role
		FROM conversations conversation
		JOIN conversation_members member ON member.conversation_id=conversation.id AND member.user_id=$2
		WHERE conversation.id=$1 AND conversation.deleted_at IS NULL`, conversationID, userID).
		Scan(&kind, &announcementOnly, &role)
	if err != nil {
		return false, err
	}
	return groupAllowsSender(kind, announcementOnly, role), nil
}

func requireConversationSender(c *gin.Context, conversationID, userID string) bool {
	allowed, err := conversationAllowsSender(c.Request.Context(), db, conversationID, userID)
	if err != nil {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"})
		return false
	}
	if !allowed {
		c.JSON(http.StatusForbidden, gin.H{"error": announcementOnlyMessage})
		return false
	}
	return true
}
