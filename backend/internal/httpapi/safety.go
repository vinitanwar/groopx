package httpapi

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func blockUser(c *gin.Context) {
	userID, targetID := c.GetString("user_id"), c.Param("id")
	if userID == targetID { c.JSON(http.StatusBadRequest, gin.H{"error":"you cannot block yourself"}); return }
	command, err := db.Exec(c.Request.Context(), `INSERT INTO user_blocks(blocker_id,blocked_id)
		SELECT $1,id FROM users WHERE id=$2 ON CONFLICT DO NOTHING`, userID, targetID)
	if err != nil || command.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error":"user not found or already blocked"}); return }
	c.Status(http.StatusNoContent)
}

func unblockUser(c *gin.Context) {
	command, err := db.Exec(c.Request.Context(), `DELETE FROM user_blocks WHERE blocker_id=$1 AND blocked_id=$2`, c.GetString("user_id"), c.Param("id"))
	if err != nil || command.RowsAffected() == 0 { c.JSON(http.StatusNotFound, gin.H{"error":"blocked user not found"}); return }
	c.Status(http.StatusNoContent)
}

func listBlockedUsers(c *gin.Context) {
	rows, err := db.Query(c.Request.Context(), `SELECT u.id::text,COALESCE(u.full_name,u.phone),COALESCE(u.username,''),u.avatar_url,b.created_at
		FROM user_blocks b JOIN users u ON u.id=b.blocked_id WHERE b.blocker_id=$1 ORDER BY b.created_at DESC`, c.GetString("user_id"))
	if err != nil { c.JSON(http.StatusInternalServerError,gin.H{"error":"blocked users could not be loaded"}); return }
	defer rows.Close(); items:=make([]gin.H,0)
	for rows.Next(){var id,name,username string;var avatar *string;var created time.Time;if rows.Scan(&id,&name,&username,&avatar,&created)==nil{items=append(items,gin.H{"id":id,"name":name,"username":username,"avatar_url":avatar,"blocked_at":created})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func reportUser(c *gin.Context) {
	userID, targetID := c.GetString("user_id"), c.Param("id")
	var input struct { ConversationID string `json:"conversation_id" binding:"omitempty,uuid"`; Reason string `json:"reason" binding:"required,oneof=spam harassment impersonation inappropriate other"`; Details string `json:"details" binding:"max=500"` }
	if userID==targetID || c.ShouldBindJSON(&input)!=nil { c.JSON(http.StatusBadRequest,gin.H{"error":"invalid report"}); return }
	var id string
	err:=db.QueryRow(c.Request.Context(),`INSERT INTO user_reports(reporter_id,reported_user_id,conversation_id,reason,details)
		SELECT $1,u.id,NULLIF($3,'')::uuid,$4,NULLIF($5,'') FROM users u WHERE u.id=$2
		AND ($3='' OR EXISTS(SELECT 1 FROM conversation_members reporter JOIN conversation_members reported ON reported.conversation_id=reporter.conversation_id
			WHERE reporter.conversation_id=NULLIF($3,'')::uuid AND reporter.user_id=$1 AND reported.user_id=$2)) RETURNING id::text`,userID,targetID,input.ConversationID,input.Reason,strings.TrimSpace(input.Details)).Scan(&id)
	if err!=nil { c.JSON(http.StatusBadRequest,gin.H{"error":"report could not be submitted"}); return }
	c.JSON(http.StatusCreated,gin.H{"id":id,"status":"open","message":"report submitted"})
}

func usersBlocked(firstID, secondID string) bool {
	var blocked bool
	err:=db.QueryRow(context.Background(),`SELECT EXISTS(SELECT 1 FROM user_blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1))`,firstID,secondID).Scan(&blocked)
	return err==nil && blocked
}
