package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

type queuedGroupJoinRequest struct {
	id       string
	created  bool
	adminIDs []string
}

func groupJoinNeedsApproval(kind string, required, alreadyMember bool) bool {
	return kind == "group" && required && !alreadyMember
}

func queueGroupJoinRequest(ctx context.Context, tx pgx.Tx, inviteID, groupID, userID, groupName string) (queuedGroupJoinRequest, error) {
	var result queuedGroupJoinRequest
	var status string
	err := tx.QueryRow(ctx, `SELECT id::text,status FROM group_join_requests
		WHERE conversation_id=$1 AND user_id=$2 FOR UPDATE`, groupID, userID).Scan(&result.id, &status)
	if err == nil && status == "pending" {
		return result, nil
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return result, err
	}
	if errors.Is(err, pgx.ErrNoRows) {
		err = tx.QueryRow(ctx, `INSERT INTO group_join_requests(conversation_id,user_id,invite_id)
			VALUES($1,$2,$3) RETURNING id::text`, groupID, userID, inviteID).Scan(&result.id)
	} else {
		err = tx.QueryRow(ctx, `UPDATE group_join_requests SET invite_id=$3,status='pending',reviewed_by=NULL,
			reviewed_at=NULL,created_at=NOW(),updated_at=NOW() WHERE conversation_id=$1 AND user_id=$2
			RETURNING id::text`, groupID, userID, inviteID).Scan(&result.id)
	}
	if err != nil {
		return result, err
	}
	result.created = true
	command, err := tx.Exec(ctx, `UPDATE group_invites SET use_count=use_count+1 WHERE id=$1 AND use_count<max_uses`, inviteID)
	if err != nil || command.RowsAffected() == 0 {
		if err == nil { err = errors.New("invite usage limit reached") }
		return result, err
	}
	var requesterName string
	if err = tx.QueryRow(ctx, `SELECT COALESCE(NULLIF(full_name,''),NULLIF(username,''),'GroopX user') FROM users WHERE id=$1`, userID).Scan(&requesterName); err != nil {
		return result, err
	}
	rows, err := tx.Query(ctx, `SELECT user_id::text FROM conversation_members
		WHERE conversation_id=$1 AND role='admin'`, groupID)
	if err != nil { return result, err }
	for rows.Next() {
		var adminID string
		if rows.Scan(&adminID) == nil { result.adminIDs = append(result.adminIDs, adminID) }
	}
	if rows.Err() != nil { rows.Close(); return result, rows.Err() }
	rows.Close()
	payload, _ := json.Marshal(gin.H{"type":"group_join_request","group_id":groupID,"request_id":result.id})
	_, err = tx.Exec(ctx, `INSERT INTO notifications(user_id,type,title,body,data)
		SELECT user_id,'group_join_request','New group join request',$2,$3
		FROM conversation_members WHERE conversation_id=$1 AND role='admin'`, groupID, requesterName+" requested to join "+groupName, payload)
	return result, err
}

func listGroupJoinRequests(c *gin.Context) {
	groupID, userID := c.Param("id"), c.GetString("user_id")
	if !isGroupAdmin(groupID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error":"admin access required"})
		return
	}
	rows, err := db.Query(c.Request.Context(), `SELECT request.id::text,request.user_id::text,
		COALESCE(NULLIF(applicant.full_name,''),NULLIF(applicant.username,''),'GroopX user'),
		COALESCE(applicant.username,''),COALESCE(applicant.avatar_url,''),request.created_at
		FROM group_join_requests request JOIN users applicant ON applicant.id=request.user_id
		WHERE request.conversation_id=$1 AND request.status='pending'
		AND applicant.account_status='active'
		AND NOT EXISTS(SELECT 1 FROM conversation_members member WHERE member.conversation_id=request.conversation_id AND member.user_id=request.user_id)
		ORDER BY request.created_at`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"join requests could not be loaded"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, applicantID, name, username, avatarURL string
		var requestedAt time.Time
		if rows.Scan(&id, &applicantID, &name, &username, &avatarURL, &requestedAt) == nil {
			items = append(items, gin.H{"id":id,"user_id":applicantID,"name":name,"username":username,"avatar_url":avatarURL,"requested_at":requestedAt})
		}
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"join requests could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items":items,"count":len(items)})
}

func reviewGroupJoinRequest(c *gin.Context) {
	groupID, reviewerID := c.Param("id"), c.GetString("user_id")
	if !isGroupAdmin(groupID, reviewerID) {
		c.JSON(http.StatusForbidden, gin.H{"error":"admin access required"})
		return
	}
	var input struct { Action string `json:"action" binding:"required,oneof=approve reject"` }
	if c.ShouldBindJSON(&input) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error":"action must be approve or reject"})
		return
	}
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"join request could not be reviewed"})
		return
	}
	defer tx.Rollback(ctx)
	var applicantID, applicantName, groupName string
	err = tx.QueryRow(ctx, `SELECT request.user_id::text,
		COALESCE(NULLIF(applicant.full_name,''),NULLIF(applicant.username,''),'GroopX user'),
		COALESCE(conversation.title,'Group')
		FROM group_join_requests request
		JOIN users applicant ON applicant.id=request.user_id
		JOIN conversations conversation ON conversation.id=request.conversation_id
		WHERE request.id=$1 AND request.conversation_id=$2 AND request.status='pending'
		AND applicant.account_status='active'
		FOR UPDATE OF request`, c.Param("requestId"), groupID).Scan(&applicantID, &applicantName, &groupName)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error":"pending join request not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"join request could not be reviewed"})
		return
	}
	status, notificationType, title, body := "rejected", "group_join_rejected", "Group request declined", "Your request to join "+groupName+" was declined."
	var activity *groupActivityMessage
	if input.Action == "approve" {
		status, notificationType, title, body = "approved", "group_join_approved", "Group request approved", "You can now open "+groupName+"."
		result, insertErr := tx.Exec(ctx, `INSERT INTO conversation_members(conversation_id,user_id,role)
			VALUES($1,$2,'member') ON CONFLICT DO NOTHING`, groupID, applicantID)
		if insertErr != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error":"member could not be added"})
			return
		}
		if result.RowsAffected() > 0 {
			reviewerName, nameErr := groupActivityUserName(ctx, tx, groupID, reviewerID)
			if nameErr != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error":"group activity could not be saved"})
				return
			}
			saved, activityErr := recordGroupActivity(ctx, tx, groupID, "join_approved", reviewerID, applicantID, groupActivityText("join_approved", reviewerName, applicantName, ""))
			if activityErr != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error":"group activity could not be saved"})
				return
			}
			activity = &saved
		}
	}
	_, err = tx.Exec(ctx, `UPDATE group_join_requests SET status=$3,reviewed_by=$4,reviewed_at=NOW(),updated_at=NOW()
		WHERE id=$1 AND conversation_id=$2`, c.Param("requestId"), groupID, status, reviewerID)
	if err == nil {
		_, err = tx.Exec(ctx, `UPDATE notifications SET read_at=COALESCE(read_at,NOW())
			WHERE type='group_join_request' AND data->>'request_id'=$1`, c.Param("requestId"))
	}
	payload, _ := json.Marshal(gin.H{"type":notificationType,"group_id":groupID,"request_id":c.Param("requestId"),"status":status})
	if err == nil {
		_, err = tx.Exec(ctx, `INSERT INTO notifications(user_id,type,title,body,data) VALUES($1,$2,$3,$4,$5)`, applicantID, notificationType, title, body, payload)
	}
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"join request could not be reviewed"})
		return
	}
	if status == "approved" {
		publishGroupActivity(activity)
		broadcast(groupID, reviewerID, gin.H{"type":"group_member_update","conversation_id":groupID,"user_id":applicantID})
		broadcastConversationUpdate(groupID, "group_member_joined")
	}
	go sendPushToUsers([]string{applicantID}, notificationType, title, body, map[string]any{"group_id":groupID,"request_id":c.Param("requestId"),"status":status})
	c.JSON(http.StatusOK, gin.H{"id":c.Param("requestId"),"status":status,"user_id":applicantID,"name":applicantName})
}

func pendingGroupJoinRequestCount(ctx context.Context, groupID, userID string) int {
	var count int
	_ = db.QueryRow(ctx, `SELECT COUNT(*)::int FROM group_join_requests request
		WHERE request.conversation_id=$1 AND request.status='pending'
		AND EXISTS(SELECT 1 FROM users applicant WHERE applicant.id=request.user_id AND applicant.account_status='active')
		AND EXISTS(SELECT 1 FROM conversation_members admin WHERE admin.conversation_id=$1 AND admin.user_id=$2 AND admin.role='admin')
		AND NOT EXISTS(SELECT 1 FROM conversation_members member WHERE member.conversation_id=$1 AND member.user_id=request.user_id)`, groupID, userID).Scan(&count)
	return count
}
