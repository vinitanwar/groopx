package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

func listReminders(c *gin.Context) {
	userID := c.GetString("user_id")
	status := c.DefaultQuery("status", "all")
	itemType := c.Query("item_type")
	if status != "all" && status != "upcoming" && status != "completed" && status != "cancelled" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reminder status"})
		return
	}
	if itemType != "" && itemType != "reminder" && itemType != "meeting" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reminder type"})
		return
	}
	rows, err := db.Query(c.Request.Context(), `
		SELECT r.id::text,r.title,COALESCE(r.notes,''),r.scheduled_at,r.status::text,
			COALESCE(r.conversation_id::text,''),COALESCE(NULLIF(c.title,''),other.title,''),
			r.item_type,COALESCE(r.call_kind::text,''),r.repeat_rule,r.user_id=$1,
			CASE WHEN r.user_id=$1 THEN 'organizer' ELSE COALESCE(ma.response,'pending') END,
			COALESCE(NULLIF(organizer.full_name,''),NULLIF(organizer.username,''),'GroopX member'),
			invite_summary.invited_count,invite_summary.accepted_count,invite_summary.pending_count,invite_summary.declined_count
		FROM reminders r
		LEFT JOIN conversations c ON c.id=r.conversation_id
		JOIN users organizer ON organizer.id=r.user_id
		LEFT JOIN meeting_attendees ma ON ma.meeting_id=r.id AND ma.user_id=$1
		LEFT JOIN LATERAL (
			SELECT COUNT(*)::int AS invited_count,
				COUNT(*) FILTER(WHERE response='accepted')::int AS accepted_count,
				COUNT(*) FILTER(WHERE response='pending')::int AS pending_count,
				COUNT(*) FILTER(WHERE response='declined')::int AS declined_count
			FROM meeting_attendees invited
			JOIN conversation_members invited_member ON invited_member.conversation_id=r.conversation_id AND invited_member.user_id=invited.user_id
			WHERE invited.meeting_id=r.id
		) invite_summary ON TRUE
		LEFT JOIN LATERAL (
			SELECT COALESCE(NULLIF(u.full_name,''),NULLIF(u.username,''),u.phone,'Conversation') AS title
			FROM conversation_members cm JOIN users u ON u.id=cm.user_id
			WHERE cm.conversation_id=r.conversation_id AND cm.user_id<>$1
			ORDER BY cm.joined_at LIMIT 1
		) other ON TRUE
		WHERE (r.user_id=$1 OR (ma.user_id=$1 AND r.item_type='meeting'
			AND EXISTS(SELECT 1 FROM conversation_members current_member WHERE current_member.conversation_id=r.conversation_id AND current_member.user_id=$1)))
			AND ($2='all' OR r.status::text=$2) AND ($3='' OR r.item_type=$3)
		ORDER BY CASE WHEN r.status='upcoming' THEN 0 ELSE 1 END,r.scheduled_at ASC`, userID, status, itemType)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "reminders could not be loaded"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, title, notes, reminderStatus, conversationID, conversationTitle, reminderType, callKind, repeatRule, inviteStatus, organizerName string
		var scheduledAt time.Time
		var isOrganizer bool
		var invitedCount, acceptedCount, pendingCount, declinedCount int
		if rows.Scan(&id, &title, &notes, &scheduledAt, &reminderStatus, &conversationID, &conversationTitle, &reminderType, &callKind, &repeatRule, &isOrganizer, &inviteStatus, &organizerName, &invitedCount, &acceptedCount, &pendingCount, &declinedCount) != nil { continue }
		items = append(items, gin.H{"id":id,"title":title,"notes":notes,"scheduled_at":scheduledAt,"status":reminderStatus,"conversation_id":conversationID,"conversation_title":conversationTitle,"item_type":reminderType,"call_kind":callKind,"repeat_rule":repeatRule,"is_organizer":isOrganizer,"invite_status":inviteStatus,"organizer_name":organizerName,"invited_count":invitedCount,"accepted_count":acceptedCount,"pending_count":pendingCount,"declined_count":declinedCount})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func listMeetingAttendees(c *gin.Context) {
	ctx := c.Request.Context()
	var exists bool
	if err := db.QueryRow(ctx, `SELECT EXISTS(
		SELECT 1 FROM reminders WHERE id=$1 AND user_id=$2 AND item_type='meeting'
	)`, c.Param("id"), c.GetString("user_id")).Scan(&exists); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting attendees could not be loaded"})
		return
	}
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error":"meeting not found"})
		return
	}
	rows, err := db.Query(ctx, `SELECT attendee.user_id::text,
		COALESCE(NULLIF(member.full_name,''),NULLIF(member.username,''),member.phone,'GroopX member'),
		COALESCE(member.username,''),COALESCE(member.avatar_url,''),attendee.response,attendee.responded_at
		FROM meeting_attendees attendee
		JOIN reminders meeting ON meeting.id=attendee.meeting_id
		JOIN conversation_members active_member ON active_member.conversation_id=meeting.conversation_id
			AND active_member.user_id=attendee.user_id AND active_member.hidden_at IS NULL
		JOIN users member ON member.id=attendee.user_id
		WHERE attendee.meeting_id=$1 AND member.account_status='active'
		ORDER BY CASE attendee.response WHEN 'accepted' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
			COALESCE(NULLIF(member.full_name,''),NULLIF(member.username,''),member.phone)`, c.Param("id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting attendees could not be loaded"})
		return
	}
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var userID, name, username, avatarURL, response string
		var respondedAt *time.Time
		if rows.Scan(&userID, &name, &username, &avatarURL, &response, &respondedAt) != nil { continue }
		items = append(items, gin.H{"user_id":userID,"name":name,"username":username,"avatar_url":avatarURL,"response":response,"responded_at":respondedAt})
	}
	if rows.Err() != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting attendees could not be loaded"}); return }
	c.JSON(http.StatusOK, gin.H{"meeting_id":c.Param("id"),"items":items})
}

func createReminder(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		Title string `json:"title" binding:"required,max=160"`
		ScheduledAt time.Time `json:"scheduled_at" binding:"required"`
		ConversationID string `json:"conversation_id" binding:"omitempty,uuid"`
		Notes string `json:"notes" binding:"max=1000"`
		ItemType string `json:"item_type" binding:"omitempty,oneof=reminder meeting"`
		CallKind string `json:"call_kind" binding:"omitempty,oneof=audio video"`
		RepeatRule string `json:"repeat_rule" binding:"omitempty,oneof=none daily weekly monthly"`
		RepeatAnchorDay int `json:"repeat_anchor_day" binding:"omitempty,min=1,max=31"`
		InviteParticipants bool `json:"invite_participants"`
	}
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Title) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reminder"}); return
	}
	if input.ScheduledAt.Before(time.Now().Add(-time.Minute)) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "scheduled time must be in the future"}); return
	}
	if input.ItemType == "" { input.ItemType = "reminder" }
	if input.RepeatRule == "" { input.RepeatRule = "none" }
	if input.ItemType == "meeting" {
		if input.ConversationID == "" { c.JSON(http.StatusBadRequest, gin.H{"error":"a meeting must be linked to a chat"}); return }
		if input.CallKind == "" { input.CallKind = "video" }
	} else { input.CallKind = "" }
	if input.ConversationID != "" && !isConversationMember(c, input.ConversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return
	}
	repeatAnchorDay := 0
	if input.RepeatRule == "monthly" {
		repeatAnchorDay = input.RepeatAnchorDay
		if repeatAnchorDay == 0 { repeatAnchorDay = input.ScheduledAt.Day() }
	}
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "reminder could not be saved"}); return }
	defer tx.Rollback(ctx)
	var id string
	err = tx.QueryRow(ctx, `INSERT INTO reminders(user_id,conversation_id,title,notes,scheduled_at,item_type,call_kind,repeat_rule,repeat_anchor_day)
		VALUES($1,NULLIF($2,'')::uuid,$3,NULLIF($4,''),$5,$6,NULLIF($7,'')::call_kind,$8,NULLIF($9,0)::smallint) RETURNING id::text`, userID, input.ConversationID, strings.TrimSpace(input.Title), strings.TrimSpace(input.Notes), input.ScheduledAt, input.ItemType, input.CallKind, input.RepeatRule, repeatAnchorDay).Scan(&id)
	attendeeIDs := make([]string, 0)
	organizerName := ""
	if err == nil && input.ItemType == "meeting" && input.InviteParticipants {
		attendeeIDs, err = syncMeetingAttendees(ctx, tx, id, input.ConversationID, userID, true)
		if err == nil { err = tx.QueryRow(ctx, `SELECT COALESCE(NULLIF(full_name,''),NULLIF(username,''),'GroopX member') FROM users WHERE id=$1`, userID).Scan(&organizerName) }
		if err == nil { err = createMeetingInviteNotifications(ctx, tx, attendeeIDs, id, strings.TrimSpace(input.Title), organizerName, input.ConversationID, input.CallKind, input.ScheduledAt) }
	}
	if err != nil || tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "reminder could not be saved"}); return }
	if len(attendeeIDs) > 0 {
		body := meetingInviteBody(organizerName, input.CallKind)
		for _, attendeeID := range attendeeIDs { go sendMeetingEventPush(attendeeID, "meeting_invite", id, "Meeting invite: "+strings.TrimSpace(input.Title), body, input.ConversationID, input.CallKind) }
	}
	c.JSON(http.StatusCreated, gin.H{"id":id,"title":strings.TrimSpace(input.Title),"notes":strings.TrimSpace(input.Notes),"scheduled_at":input.ScheduledAt,"status":"upcoming","conversation_id":input.ConversationID,"item_type":input.ItemType,"call_kind":input.CallKind,"repeat_rule":input.RepeatRule,"is_organizer":true,"invite_status":"organizer","organizer_name":organizerName,"invited_count":len(attendeeIDs)})
}

func updateReminder(c *gin.Context) {
	var input struct {
		Status *string `json:"status" binding:"omitempty,oneof=completed cancelled upcoming"`
		Title *string `json:"title" binding:"omitempty,max=160"`
		Notes *string `json:"notes" binding:"omitempty,max=1000"`
		ScheduledAt *time.Time `json:"scheduled_at"`
		ConversationID *string `json:"conversation_id"`
		ItemType *string `json:"item_type" binding:"omitempty,oneof=reminder meeting"`
		CallKind *string `json:"call_kind" binding:"omitempty,oneof=audio video"`
		RepeatRule *string `json:"repeat_rule" binding:"omitempty,oneof=none daily weekly monthly"`
		RepeatAnchorDay *int `json:"repeat_anchor_day" binding:"omitempty,min=1,max=31"`
		InviteParticipants *bool `json:"invite_participants"`
	}
	if c.ShouldBindJSON(&input) != nil || (input.Title != nil && strings.TrimSpace(*input.Title) == "") || (input.ScheduledAt != nil && input.ScheduledAt.Before(time.Now().Add(-time.Minute))) { c.JSON(http.StatusBadRequest, gin.H{"error":"invalid reminder update"}); return }
	userID := c.GetString("user_id")
	if input.ConversationID != nil {
		conversationID := strings.TrimSpace(*input.ConversationID)
		input.ConversationID = &conversationID
		if conversationID != "" && !isConversationMember(c, conversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error":"not a conversation member"}); return }
	}
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be updated"}); return }
	defer tx.Rollback(ctx)
	var previousItemType, previousConversationID, previousTitle, previousNotes, previousStatus, previousCallKind, previousRepeatRule string
	var previousScheduledAt time.Time
	err = tx.QueryRow(ctx, `SELECT item_type,COALESCE(conversation_id::text,''),title,COALESCE(notes,''),status::text,
		COALESCE(call_kind::text,''),repeat_rule,scheduled_at FROM reminders WHERE id=$1 AND user_id=$2 FOR UPDATE`, c.Param("id"), userID).Scan(
		&previousItemType, &previousConversationID, &previousTitle, &previousNotes, &previousStatus, &previousCallKind, &previousRepeatRule, &previousScheduledAt)
	if errors.Is(err, pgx.ErrNoRows) { c.JSON(http.StatusNotFound, gin.H{"error":"reminder not found"}); return }
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be updated"}); return }
	previousAttendeeIDs, err := meetingAttendeeIDs(ctx, tx, c.Param("id"))
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be updated"}); return }
	var finalItemType, finalConversationID, finalTitle, finalNotes, finalStatus, finalCallKind, finalRepeatRule string
	var finalScheduledAt time.Time
	err = tx.QueryRow(ctx, `UPDATE reminders SET
		title=COALESCE(NULLIF(BTRIM($3::text),''),title),notes=CASE WHEN $4::text IS NULL THEN notes ELSE NULLIF(BTRIM($4::text),'') END,
		scheduled_at=COALESCE($5::timestamptz,scheduled_at),status=COALESCE(NULLIF($6::text,'')::reminder_status,status),
		conversation_id=CASE WHEN $7::text IS NULL THEN conversation_id ELSE NULLIF(BTRIM($7::text),'')::uuid END,
		item_type=COALESCE(NULLIF($8::text,''),item_type),
		call_kind=CASE WHEN COALESCE(NULLIF($8::text,''),item_type)='reminder' THEN NULL ELSE COALESCE(NULLIF($9::text,'')::call_kind,call_kind,'video'::call_kind) END,
		repeat_rule=CASE WHEN $6::text IN ('completed','cancelled') THEN 'none' ELSE COALESCE(NULLIF($10::text,''),repeat_rule) END,
		repeat_anchor_day=CASE
			WHEN $6::text IN ('completed','cancelled') THEN NULL
			WHEN COALESCE(NULLIF($10::text,''),repeat_rule)<>'monthly' THEN NULL
			WHEN $11::int IS NOT NULL THEN $11::smallint
			ELSE COALESCE(repeat_anchor_day,EXTRACT(DAY FROM COALESCE($5::timestamptz,scheduled_at) AT TIME ZONE 'UTC')::smallint)
		END,
		notified_at=CASE WHEN $5::timestamptz IS NOT NULL OR $6::text='upcoming' THEN NULL ELSE notified_at END
		WHERE id=$1 AND user_id=$2
		RETURNING item_type,COALESCE(conversation_id::text,''),title,COALESCE(notes,''),status::text,
			COALESCE(call_kind::text,''),repeat_rule,scheduled_at`, c.Param("id"), userID, input.Title, input.Notes, input.ScheduledAt, input.Status, input.ConversationID, input.ItemType, input.CallKind, input.RepeatRule, input.RepeatAnchorDay).Scan(
		&finalItemType, &finalConversationID, &finalTitle, &finalNotes, &finalStatus, &finalCallKind, &finalRepeatRule, &finalScheduledAt)
	if errors.Is(err, pgx.ErrNoRows) { c.JSON(http.StatusNotFound, gin.H{"error":"reminder not found"}); return }
	if err != nil { c.JSON(http.StatusBadRequest, gin.H{"error":"invalid reminder update"}); return }
	newAttendeeIDs := make([]string, 0)
	if finalItemType != "meeting" {
		_, err = syncMeetingAttendees(ctx, tx, c.Param("id"), "", userID, false)
	} else if finalStatus == "upcoming" && (input.InviteParticipants != nil || input.ConversationID != nil) {
		inviteParticipants := false
		if input.InviteParticipants != nil {
			inviteParticipants = *input.InviteParticipants
		} else {
			err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM meeting_attendees WHERE meeting_id=$1)`, c.Param("id")).Scan(&inviteParticipants)
		}
		if err == nil { newAttendeeIDs, err = syncMeetingAttendees(ctx, tx, c.Param("id"), finalConversationID, userID, inviteParticipants) }
	}
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be updated"}); return }
	currentAttendeeIDs := make([]string, 0)
	if finalItemType == "meeting" {
		currentAttendeeIDs, err = meetingAttendeeIDs(ctx, tx, c.Param("id"))
		if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be updated"}); return }
	}
	organizerName := ""
	if len(previousAttendeeIDs) > 0 || len(newAttendeeIDs) > 0 {
		err = tx.QueryRow(ctx, `SELECT COALESCE(NULLIF(full_name,''),NULLIF(username,''),'GroopX member') FROM users WHERE id=$1`, userID).Scan(&organizerName)
	}
	if err == nil && len(newAttendeeIDs) > 0 {
		err = createMeetingInviteNotifications(ctx, tx, newAttendeeIDs, c.Param("id"), finalTitle, organizerName, finalConversationID, finalCallKind, finalScheduledAt)
	}
	pushes := make([]meetingEventPush, 0)
	if err == nil {
		cancelled := previousItemType == "meeting" && (finalItemType != "meeting" || (finalStatus == "cancelled" && previousStatus != "cancelled"))
		if cancelled {
			body := organizerName + " cancelled " + previousTitle + "."
			err = createMeetingEventNotifications(ctx, tx, previousAttendeeIDs, "meeting_cancelled", c.Param("id"), previousTitle, body, previousConversationID, previousCallKind, previousScheduledAt)
			pushes = appendMeetingPushes(pushes, previousAttendeeIDs, "meeting_cancelled", c.Param("id"), previousTitle, body, previousConversationID, previousCallKind)
		} else if finalItemType == "meeting" {
			removedAttendeeIDs := attendeeDifference(previousAttendeeIDs, currentAttendeeIDs)
			if len(removedAttendeeIDs) > 0 {
				body := "You are no longer invited to " + finalTitle + "."
				err = createMeetingEventNotifications(ctx, tx, removedAttendeeIDs, "meeting_cancelled", c.Param("id"), finalTitle, body, previousConversationID, previousCallKind, finalScheduledAt)
				pushes = appendMeetingPushes(pushes, removedAttendeeIDs, "meeting_cancelled", c.Param("id"), finalTitle, body, previousConversationID, previousCallKind)
			}
			meetingChanged := previousItemType != finalItemType || previousConversationID != finalConversationID || previousTitle != finalTitle ||
				previousNotes != finalNotes || previousStatus != finalStatus || previousCallKind != finalCallKind || previousRepeatRule != finalRepeatRule ||
				!previousScheduledAt.Equal(finalScheduledAt)
			if err == nil && meetingChanged && finalStatus == "upcoming" {
				updatedAttendeeIDs := attendeeIntersection(previousAttendeeIDs, currentAttendeeIDs)
				body := organizerName + " updated " + finalTitle + ". Open Schedule for the latest details."
				err = createMeetingEventNotifications(ctx, tx, updatedAttendeeIDs, "meeting_update", c.Param("id"), finalTitle, body, finalConversationID, finalCallKind, finalScheduledAt)
				pushes = appendMeetingPushes(pushes, updatedAttendeeIDs, "meeting_update", c.Param("id"), finalTitle, body, finalConversationID, finalCallKind)
			}
		}
	}
	if err != nil || tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be updated"}); return }
	if len(newAttendeeIDs) > 0 {
		body := meetingInviteBody(organizerName, finalCallKind)
		for _, attendeeID := range newAttendeeIDs { go sendMeetingEventPush(attendeeID, "meeting_invite", c.Param("id"), "Meeting invite: "+finalTitle, body, finalConversationID, finalCallKind) }
	}
	for _, push := range pushes { go sendMeetingEventPush(push.userID, push.eventType, push.reminderID, push.title, push.body, push.conversationID, push.callKind) }
	c.JSON(http.StatusOK, gin.H{"id":c.Param("id")})
}

type meetingEventPush struct {
	userID, eventType, reminderID, title, body, conversationID, callKind string
}

func meetingAttendeeIDs(ctx context.Context, tx pgx.Tx, meetingID string) ([]string, error) {
	rows, err := tx.Query(ctx, `SELECT user_id::text FROM meeting_attendees WHERE meeting_id=$1 ORDER BY created_at`, meetingID)
	if err != nil { return nil, err }
	defer rows.Close()
	userIDs := make([]string, 0)
	for rows.Next() {
		var userID string
		if err = rows.Scan(&userID); err != nil { return nil, err }
		userIDs = append(userIDs, userID)
	}
	return userIDs, rows.Err()
}

func attendeeDifference(first, second []string) []string {
	secondSet := make(map[string]struct{}, len(second))
	for _, userID := range second { secondSet[userID] = struct{}{} }
	result := make([]string, 0)
	for _, userID := range first {
		if _, found := secondSet[userID]; !found { result = append(result, userID) }
	}
	return result
}

func attendeeIntersection(first, second []string) []string {
	secondSet := make(map[string]struct{}, len(second))
	for _, userID := range second { secondSet[userID] = struct{}{} }
	result := make([]string, 0)
	for _, userID := range first {
		if _, found := secondSet[userID]; found { result = append(result, userID) }
	}
	return result
}

func appendMeetingPushes(pushes []meetingEventPush, userIDs []string, eventType, reminderID, title, body, conversationID, callKind string) []meetingEventPush {
	for _, userID := range userIDs {
		pushes = append(pushes, meetingEventPush{userID:userID,eventType:eventType,reminderID:reminderID,title:title,body:body,conversationID:conversationID,callKind:callKind})
	}
	return pushes
}

func syncMeetingAttendees(ctx context.Context, tx pgx.Tx, meetingID, conversationID, organizerID string, invite bool) ([]string, error) {
	if !invite || conversationID == "" {
		if _, err := tx.Exec(ctx, `DELETE FROM meeting_attendees WHERE meeting_id=$1`, meetingID); err != nil { return nil, err }
		_, err := tx.Exec(ctx, `DELETE FROM notifications WHERE type='meeting_invite' AND data->>'reminder_id'=$1`, meetingID)
		return nil, err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM meeting_attendees attendee WHERE attendee.meeting_id=$1 AND attendee.user_id NOT IN (
		SELECT cm.user_id FROM conversation_members cm JOIN users u ON u.id=cm.user_id
		WHERE cm.conversation_id=$2 AND cm.user_id<>$3 AND cm.hidden_at IS NULL AND u.account_status='active'
	)`, meetingID, conversationID, organizerID); err != nil { return nil, err }
	if _, err := tx.Exec(ctx, `DELETE FROM notifications invite WHERE invite.type='meeting_invite' AND invite.data->>'reminder_id'=$1
		AND NOT EXISTS(SELECT 1 FROM meeting_attendees attendee WHERE attendee.meeting_id=$1 AND attendee.user_id=invite.user_id)`, meetingID); err != nil { return nil, err }
	rows, err := tx.Query(ctx, `INSERT INTO meeting_attendees(meeting_id,user_id)
		SELECT $1,cm.user_id FROM conversation_members cm JOIN users u ON u.id=cm.user_id
		WHERE cm.conversation_id=$2 AND cm.user_id<>$3 AND cm.hidden_at IS NULL AND u.account_status='active'
		ON CONFLICT(meeting_id,user_id) DO NOTHING RETURNING user_id::text`, meetingID, conversationID, organizerID)
	if err != nil { return nil, err }
	defer rows.Close()
	userIDs := make([]string, 0)
	for rows.Next() { var userID string; if rows.Scan(&userID) == nil { userIDs = append(userIDs, userID) } }
	return userIDs, rows.Err()
}

func createMeetingInviteNotifications(ctx context.Context, tx pgx.Tx, attendeeIDs []string, meetingID, title, organizerName, conversationID, callKind string, scheduledAt time.Time) error {
	if len(attendeeIDs) == 0 { return nil }
	body := meetingInviteBody(organizerName, callKind)
	data, err := json.Marshal(gin.H{"type":"meeting_invite","reminder_id":meetingID,"item_type":"meeting","conversation_id":conversationID,"call_kind":callKind,"scheduled_at":scheduledAt})
	if err != nil { return err }
	for _, attendeeID := range attendeeIDs {
		if _, err = tx.Exec(ctx, `DELETE FROM notifications WHERE user_id=$1 AND type IN ('meeting_update','meeting_cancelled')
			AND data->>'reminder_id'=$2 AND read_at IS NULL`, attendeeID, meetingID); err != nil { return err }
		if _, err = tx.Exec(ctx, `INSERT INTO notifications(user_id,type,title,body,data) VALUES($1,'meeting_invite',$2,$3,$4)`, attendeeID, title, body, data); err != nil { return err }
	}
	return nil
}

func createMeetingEventNotifications(ctx context.Context, tx pgx.Tx, attendeeIDs []string, eventType, meetingID, title, body, conversationID, callKind string, scheduledAt time.Time) error {
	if len(attendeeIDs) == 0 { return nil }
	data, err := json.Marshal(gin.H{"type":eventType,"reminder_id":meetingID,"item_type":"meeting","conversation_id":conversationID,"call_kind":callKind,"scheduled_at":scheduledAt})
	if err != nil { return err }
	for _, attendeeID := range attendeeIDs {
		if eventType == "meeting_cancelled" {
			if _, err = tx.Exec(ctx, `UPDATE notifications SET read_at=COALESCE(read_at,NOW())
				WHERE user_id=$1 AND type='meeting_invite' AND data->>'reminder_id'=$2`, attendeeID, meetingID); err != nil { return err }
		}
		if _, err = tx.Exec(ctx, `DELETE FROM notifications WHERE user_id=$1 AND type IN ('meeting_update','meeting_cancelled')
			AND data->>'reminder_id'=$2 AND read_at IS NULL`, attendeeID, meetingID); err != nil { return err }
		if _, err = tx.Exec(ctx, `INSERT INTO notifications(user_id,type,title,body,data) VALUES($1,$2,$3,$4,$5)`, attendeeID, eventType, title, body, data); err != nil { return err }
	}
	return nil
}

func meetingInviteBody(organizerName, callKind string) string {
	mode := "video"
	if callKind == "audio" { mode = "audio" }
	return organizerName + " invited you to a " + mode + " meeting. Open Schedule to respond."
}

func respondToMeeting(c *gin.Context) {
	var input struct { Response string `json:"response" binding:"required,oneof=accepted declined"` }
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error":"response must be accepted or declined"}); return }
	ctx := c.Request.Context()
	userID := c.GetString("user_id")
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting response could not be saved"}); return }
	defer tx.Rollback(ctx)
	var organizerID, title, conversationID, callKind, responderName string
	err = tx.QueryRow(ctx, `UPDATE meeting_attendees attendee SET response=$3,responded_at=NOW()
		FROM reminders reminder,users responder
		WHERE attendee.meeting_id=$1 AND attendee.user_id=$2 AND reminder.id=attendee.meeting_id
			AND reminder.item_type='meeting' AND reminder.status='upcoming' AND responder.id=$2
			AND EXISTS(SELECT 1 FROM conversation_members member WHERE member.conversation_id=reminder.conversation_id AND member.user_id=attendee.user_id)
		RETURNING reminder.user_id::text,reminder.title,COALESCE(reminder.conversation_id::text,''),COALESCE(reminder.call_kind::text,''),
			COALESCE(NULLIF(responder.full_name,''),NULLIF(responder.username,''),'GroopX member')`, c.Param("id"), userID, input.Response).Scan(&organizerID, &title, &conversationID, &callKind, &responderName)
	if errors.Is(err, pgx.ErrNoRows) { c.JSON(http.StatusNotFound, gin.H{"error":"active meeting invite not found"}); return }
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting response could not be saved"}); return }
	body := responderName + " " + input.Response + " your meeting invitation."
	data, _ := json.Marshal(gin.H{"type":"meeting_response","reminder_id":c.Param("id"),"item_type":"meeting","conversation_id":conversationID,"call_kind":callKind,"response":input.Response,"responder_name":responderName})
	if _, err = tx.Exec(ctx, `INSERT INTO notifications(user_id,type,title,body,data) VALUES($1,'meeting_response',$2,$3,$4)`, organizerID, title, body, data); err == nil {
		_, err = tx.Exec(ctx, `UPDATE notifications SET read_at=COALESCE(read_at,NOW()) WHERE user_id=$1 AND type='meeting_invite' AND data->>'reminder_id'=$2`, userID, c.Param("id"))
	}
	if err != nil || tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting response could not be saved"}); return }
	go sendMeetingEventPush(organizerID, "meeting_response", c.Param("id"), "Meeting "+input.Response, body, conversationID, callKind)
	c.JSON(http.StatusOK, gin.H{"id":c.Param("id"),"response":input.Response})
}

func deleteReminder(c *gin.Context) {
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be deleted"}); return }
	defer tx.Rollback(ctx)
	var itemType, title, conversationID, callKind, organizerName string
	var scheduledAt time.Time
	err = tx.QueryRow(ctx, `SELECT reminder.item_type,reminder.title,COALESCE(reminder.conversation_id::text,''),
		COALESCE(reminder.call_kind::text,''),reminder.scheduled_at,
		COALESCE(NULLIF(owner.full_name,''),NULLIF(owner.username,''),'GroopX member')
		FROM reminders reminder JOIN users owner ON owner.id=reminder.user_id
		WHERE reminder.id=$1 AND reminder.user_id=$2 FOR UPDATE`, c.Param("id"), c.GetString("user_id")).Scan(
		&itemType, &title, &conversationID, &callKind, &scheduledAt, &organizerName)
	if errors.Is(err, pgx.ErrNoRows) { c.JSON(http.StatusNotFound, gin.H{"error":"reminder not found"}); return }
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be deleted"}); return }
	attendeeIDs, err := meetingAttendeeIDs(ctx, tx, c.Param("id"))
	if err == nil {
		_, err = tx.Exec(ctx, `DELETE FROM reminders WHERE id=$1 AND user_id=$2`, c.Param("id"), c.GetString("user_id"))
	}
	body := organizerName + " cancelled " + title + "."
	if err == nil && itemType == "meeting" {
		err = createMeetingEventNotifications(ctx, tx, attendeeIDs, "meeting_cancelled", c.Param("id"), title, body, conversationID, callKind, scheduledAt)
	}
	if err != nil || tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"reminder could not be deleted"}); return }
	if itemType == "meeting" {
		for _, attendeeID := range attendeeIDs { go sendMeetingEventPush(attendeeID, "meeting_cancelled", c.Param("id"), title, body, conversationID, callKind) }
	}
	c.Status(http.StatusNoContent)
}

type dueReminder struct {
	id, userID, title, body, itemType, conversationID, callKind, repeatRule string
	scheduledAt time.Time
	repeatAnchorDay int
	recipientIDs []string
}

func startReminderScheduler() {
	go func() {
		dispatchDueReminders(context.Background())
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for range ticker.C { dispatchDueReminders(context.Background()) }
	}()
}

func dispatchDueReminders(ctx context.Context) {
	tx, err := db.Begin(ctx); if err != nil { return }
	defer tx.Rollback(ctx)
	rows, err := tx.Query(ctx, `WITH due AS (
		SELECT r.id FROM reminders r JOIN users u ON u.id=r.user_id
		WHERE r.status='upcoming' AND r.notified_at IS NULL AND r.scheduled_at<=NOW()
		AND ((u.account_status='active' AND u.push_notifications=TRUE AND u.reminder_notifications=TRUE)
			OR EXISTS(SELECT 1 FROM meeting_attendees attendee JOIN users invited ON invited.id=attendee.user_id
				WHERE attendee.meeting_id=r.id AND attendee.response='accepted' AND invited.account_status='active'
				AND EXISTS(SELECT 1 FROM conversation_members member WHERE member.conversation_id=r.conversation_id AND member.user_id=attendee.user_id)
				AND invited.push_notifications=TRUE AND invited.reminder_notifications=TRUE))
		ORDER BY r.scheduled_at FOR UPDATE OF r SKIP LOCKED LIMIT 100
	) UPDATE reminders r SET notified_at=NOW() FROM due WHERE r.id=due.id
	RETURNING r.id::text,r.user_id::text,r.title,COALESCE(r.notes,''),r.item_type,COALESCE(r.conversation_id::text,''),COALESCE(r.call_kind::text,''),r.scheduled_at,r.repeat_rule,COALESCE(r.repeat_anchor_day,0)`)
	if err != nil { return }
	items := make([]dueReminder, 0)
	for rows.Next() { var item dueReminder; if rows.Scan(&item.id,&item.userID,&item.title,&item.body,&item.itemType,&item.conversationID,&item.callKind,&item.scheduledAt,&item.repeatRule,&item.repeatAnchorDay)==nil { items=append(items,item) } }
	rows.Close()
	for index := range items {
		item := &items[index]
		recipients, recipientErr := tx.Query(ctx, `SELECT reminder.user_id::text FROM reminders reminder JOIN users owner ON owner.id=reminder.user_id
			WHERE reminder.id=$1 AND owner.account_status='active' AND owner.push_notifications=TRUE AND owner.reminder_notifications=TRUE
			UNION
			SELECT attendee.user_id::text FROM meeting_attendees attendee
			JOIN reminders meeting ON meeting.id=attendee.meeting_id
			JOIN conversation_members member ON member.conversation_id=meeting.conversation_id AND member.user_id=attendee.user_id
			JOIN users invited ON invited.id=attendee.user_id
			WHERE attendee.meeting_id=$1 AND attendee.response='accepted' AND invited.account_status='active'
				AND invited.push_notifications=TRUE AND invited.reminder_notifications=TRUE`, item.id)
		if recipientErr != nil { return }
		for recipients.Next() { var recipientID string; if recipients.Scan(&recipientID) == nil { item.recipientIDs = append(item.recipientIDs, recipientID) } }
		recipientErr = recipients.Err()
		recipients.Close()
		if recipientErr != nil { return }
		body := item.body; if body == "" { if item.itemType=="meeting" { body="Your scheduled meeting is ready to start." } else { body = "Your scheduled reminder is due now." } }
		payload := gin.H{"type":"reminder","reminder_id":item.id,"item_type":item.itemType,"conversation_id":item.conversationID,"call_kind":item.callKind,"repeat_rule":item.repeatRule}
		if item.itemType == "meeting" { payload["meeting_title"] = item.title }
		data, _ := json.Marshal(payload)
		for _, recipientID := range item.recipientIDs {
			if _, err = tx.Exec(ctx, `INSERT INTO notifications(user_id,type,title,body,data) VALUES($1,'reminder',$2,$3,$4)`,recipientID,item.title,body,data); err != nil { return }
		}
		if item.repeatRule != "none" {
			next := nextReminderOccurrence(item.scheduledAt, item.repeatRule, item.repeatAnchorDay, time.Now())
			if _, err = tx.Exec(ctx, `UPDATE reminders SET scheduled_at=$2,notified_at=NULL WHERE id=$1`, item.id, next); err != nil { return }
		}
	}
	if err = tx.Commit(ctx); err != nil { log.Printf("reminder dispatch commit failed: %v", err); return }
	for _, item := range items {
		body:=item.body; if body=="" { if item.itemType=="meeting" { body="Your scheduled meeting is ready to start." } else { body="Your scheduled reminder is due now." } }
		for _, recipientID := range item.recipientIDs { go sendReminderPush(recipientID,item.id,item.title,body,item.itemType,item.conversationID,item.callKind) }
	}
}

func nextReminderOccurrence(scheduledAt time.Time, repeatRule string, anchorDay int, now time.Time) time.Time {
	next := scheduledAt
	for !next.After(now) {
		switch repeatRule {
		case "daily":
			next = next.AddDate(0, 0, 1)
		case "weekly":
			next = next.AddDate(0, 0, 7)
		case "monthly":
			next = addReminderMonth(next, anchorDay)
		default:
			return next
		}
	}
	return next
}

func addReminderMonth(value time.Time, anchorDay int) time.Time {
	if anchorDay < 1 || anchorDay > 31 { anchorDay = value.Day() }
	first := time.Date(value.Year(), value.Month()+1, 1, value.Hour(), value.Minute(), value.Second(), value.Nanosecond(), value.Location())
	lastDay := time.Date(first.Year(), first.Month()+1, 0, 0, 0, 0, 0, first.Location()).Day()
	if anchorDay > lastDay { anchorDay = lastDay }
	return time.Date(first.Year(), first.Month(), anchorDay, value.Hour(), value.Minute(), value.Second(), value.Nanosecond(), value.Location())
}
