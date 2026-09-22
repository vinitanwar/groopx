package httpapi

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func listReminders(c *gin.Context) {
	userID := c.GetString("user_id")
	status := c.DefaultQuery("status", "all")
	if status != "all" && status != "upcoming" && status != "completed" && status != "cancelled" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reminder status"})
		return
	}
	rows, err := db.Query(c.Request.Context(), `
		SELECT r.id::text,r.title,COALESCE(r.notes,''),r.scheduled_at,r.status::text,
			COALESCE(r.conversation_id::text,''),COALESCE(c.title,'')
		FROM reminders r LEFT JOIN conversations c ON c.id=r.conversation_id
		WHERE r.user_id=$1 AND ($2='all' OR r.status::text=$2)
		ORDER BY CASE WHEN r.status='upcoming' THEN 0 ELSE 1 END,r.scheduled_at ASC`, userID, status)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "reminders could not be loaded"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, title, notes, reminderStatus, conversationID, conversationTitle string
		var scheduledAt time.Time
		if rows.Scan(&id, &title, &notes, &scheduledAt, &reminderStatus, &conversationID, &conversationTitle) != nil { continue }
		items = append(items, gin.H{"id":id,"title":title,"notes":notes,"scheduled_at":scheduledAt,"status":reminderStatus,"conversation_id":conversationID,"conversation_title":conversationTitle})
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func createReminder(c *gin.Context) {
	userID := c.GetString("user_id")
	var input struct {
		Title string `json:"title" binding:"required,max=160"`
		ScheduledAt time.Time `json:"scheduled_at" binding:"required"`
		ConversationID string `json:"conversation_id" binding:"omitempty,uuid"`
		Notes string `json:"notes" binding:"max=1000"`
	}
	if c.ShouldBindJSON(&input) != nil || strings.TrimSpace(input.Title) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reminder"}); return
	}
	if input.ScheduledAt.Before(time.Now().Add(-time.Minute)) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "scheduled time must be in the future"}); return
	}
	if input.ConversationID != "" && !isConversationMember(c, input.ConversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"}); return
	}
	var id string
	err := db.QueryRow(c.Request.Context(), `INSERT INTO reminders(user_id,conversation_id,title,notes,scheduled_at)
		VALUES($1,NULLIF($2,'')::uuid,$3,NULLIF($4,''),$5) RETURNING id::text`, userID, input.ConversationID, strings.TrimSpace(input.Title), strings.TrimSpace(input.Notes), input.ScheduledAt).Scan(&id)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "reminder could not be saved"}); return }
	c.JSON(http.StatusCreated, gin.H{"id":id,"title":strings.TrimSpace(input.Title),"notes":strings.TrimSpace(input.Notes),"scheduled_at":input.ScheduledAt,"status":"upcoming","conversation_id":input.ConversationID})
}

func updateReminder(c *gin.Context) {
	var input struct {
		Status *string `json:"status" binding:"omitempty,oneof=completed cancelled upcoming"`
		Title *string `json:"title" binding:"omitempty,max=160"`
		Notes *string `json:"notes" binding:"omitempty,max=1000"`
		ScheduledAt *time.Time `json:"scheduled_at"`
	}
	if c.ShouldBindJSON(&input) != nil || (input.Title != nil && strings.TrimSpace(*input.Title) == "") || (input.ScheduledAt != nil && input.ScheduledAt.Before(time.Now().Add(-time.Minute))) { c.JSON(http.StatusBadRequest, gin.H{"error":"invalid reminder update"}); return }
	command, err := db.Exec(c.Request.Context(), `UPDATE reminders SET
		title=COALESCE(NULLIF(BTRIM($3::text),''),title),notes=CASE WHEN $4::text IS NULL THEN notes ELSE NULLIF(BTRIM($4::text),'') END,
		scheduled_at=COALESCE($5::timestamptz,scheduled_at),status=COALESCE(NULLIF($6::text,'')::reminder_status,status),
		notified_at=CASE WHEN $5::timestamptz IS NOT NULL OR $6::text='upcoming' THEN NULL ELSE notified_at END
		WHERE id=$1 AND user_id=$2`, c.Param("id"), c.GetString("user_id"), input.Title, input.Notes, input.ScheduledAt, input.Status)
	if err != nil || command.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error":"reminder not found"}); return }
	c.JSON(http.StatusOK, gin.H{"id":c.Param("id")})
}

func deleteReminder(c *gin.Context) {
	command, err := db.Exec(c.Request.Context(), `DELETE FROM reminders WHERE id=$1 AND user_id=$2`, c.Param("id"), c.GetString("user_id"))
	if err != nil || command.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error":"reminder not found"}); return }
	c.Status(http.StatusNoContent)
}

type dueReminder struct { id, userID, title, body string }

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
		AND u.account_status='active' AND u.push_notifications=TRUE AND u.reminder_notifications=TRUE
		ORDER BY r.scheduled_at FOR UPDATE OF r SKIP LOCKED LIMIT 100
	) UPDATE reminders r SET notified_at=NOW() FROM due WHERE r.id=due.id
	RETURNING r.id::text,r.user_id::text,r.title,COALESCE(r.notes,'')`)
	if err != nil { return }
	items := make([]dueReminder, 0)
	for rows.Next() { var item dueReminder; if rows.Scan(&item.id,&item.userID,&item.title,&item.body)==nil { items=append(items,item) } }
	rows.Close()
	for _, item := range items {
		body := item.body; if body == "" { body = "Your scheduled reminder is due now." }
		data, _ := json.Marshal(gin.H{"type":"reminder","reminder_id":item.id})
		if _, err = tx.Exec(ctx, `INSERT INTO notifications(user_id,type,title,body,data) VALUES($1,'reminder',$2,$3,$4)`,item.userID,item.title,body,data); err != nil { return }
	}
	if err = tx.Commit(ctx); err != nil { log.Printf("reminder dispatch commit failed: %v", err); return }
	for _, item := range items { body:=item.body; if body=="" { body="Your scheduled reminder is due now." }; go sendReminderPush(item.userID,item.id,item.title,body) }
}
