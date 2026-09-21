package httpapi

import (
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
	var input struct { Status string `json:"status" binding:"required,oneof=completed cancelled upcoming"` }
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error":"invalid reminder status"}); return }
	command, err := db.Exec(c.Request.Context(), `UPDATE reminders SET status=$3 WHERE id=$1 AND user_id=$2`, c.Param("id"), c.GetString("user_id"), input.Status)
	if err != nil || command.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error":"reminder not found"}); return }
	c.JSON(http.StatusOK, gin.H{"id":c.Param("id"),"status":input.Status})
}

func deleteReminder(c *gin.Context) {
	command, err := db.Exec(c.Request.Context(), `DELETE FROM reminders WHERE id=$1 AND user_id=$2`, c.Param("id"), c.GetString("user_id"))
	if err != nil || command.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error":"reminder not found"}); return }
	c.Status(http.StatusNoContent)
}
