package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

const (
	defaultGroupInviteHours = 24
	defaultGroupInviteUses  = 50
)

type groupInviteSettings struct {
	ExpiresInHours int `json:"expires_in_hours" binding:"omitempty,gte=1,lte=168"`
	MaxUses        int `json:"max_uses" binding:"omitempty,gte=1,lte=500"`
}

type groupInviteRowQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

type createdGroupInvite struct {
	id        string
	token     string
	link      string
	expiresAt time.Time
	createdAt time.Time
	maxUses   int
}

func (settings *groupInviteSettings) defaults() {
	if settings.ExpiresInHours == 0 {
		settings.ExpiresInHours = defaultGroupInviteHours
	}
	if settings.MaxUses == 0 {
		settings.MaxUses = defaultGroupInviteUses
	}
}

func createGroupInviteRecord(ctx context.Context, querier groupInviteRowQuerier, groupID, userID string, settings groupInviteSettings) (createdGroupInvite, error) {
	settings.defaults()
	token, hash, err := newRefreshToken()
	if err != nil {
		return createdGroupInvite{}, err
	}
	invite := createdGroupInvite{
		token:     token,
		link:      "groopx:///join/" + token,
		expiresAt: time.Now().UTC().Add(time.Duration(settings.ExpiresInHours) * time.Hour),
		maxUses:   settings.MaxUses,
	}
	err = querier.QueryRow(ctx, `INSERT INTO group_invites(conversation_id,token_hash,created_by,expires_at,max_uses)
		VALUES($1,$2,$3,$4,$5) RETURNING id::text,created_at`, groupID, hash, userID, invite.expiresAt, invite.maxUses).Scan(&invite.id, &invite.createdAt)
	return invite, err
}

func (invite createdGroupInvite) response() gin.H {
	return gin.H{
		"id":          invite.id,
		"token":       invite.token,
		"invite_link": invite.link,
		"expires_at":  invite.expiresAt,
		"created_at":  invite.createdAt,
		"max_uses":    invite.maxUses,
		"use_count":   0,
		"status":      "active",
	}
}

func createGroupInvite(c *gin.Context) {
	groupID, userID := c.Param("id"), c.GetString("user_id")
	if !isGroupAdmin(groupID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error":"admin access required"})
		return
	}
	var settings groupInviteSettings
	if c.ShouldBindJSON(&settings) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error":"invalid invite settings"})
		return
	}
	invite, err := createGroupInviteRecord(c.Request.Context(), db, groupID, userID, settings)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"invite could not be saved"})
		return
	}
	c.JSON(http.StatusCreated, invite.response())
}

func listGroupInvites(c *gin.Context) {
	groupID, userID := c.Param("id"), c.GetString("user_id")
	if !isGroupAdmin(groupID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error":"admin access required"})
		return
	}
	rows, err := db.Query(c.Request.Context(), `SELECT invite.id::text,
		COALESCE(NULLIF(creator.full_name,''),NULLIF(creator.username,''),'Former member'),
		invite.expires_at,invite.max_uses,invite.use_count,invite.revoked_at,invite.created_at
		FROM group_invites invite LEFT JOIN users creator ON creator.id=invite.created_by
		WHERE invite.conversation_id=$1 ORDER BY invite.created_at DESC LIMIT 50`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"invite links could not be loaded"})
		return
	}
	defer rows.Close()
	now := time.Now()
	items := make([]gin.H, 0)
	for rows.Next() {
		var id, creatorName string
		var expiresAt, createdAt time.Time
		var revokedAt *time.Time
		var maxUses, useCount int
		if rows.Scan(&id, &creatorName, &expiresAt, &maxUses, &useCount, &revokedAt, &createdAt) == nil {
			items = append(items, gin.H{
				"id":           id,
				"creator_name": creatorName,
				"expires_at":   expiresAt,
				"max_uses":     maxUses,
				"use_count":    useCount,
				"revoked_at":   revokedAt,
				"created_at":   createdAt,
				"status":       groupInviteStatus(now, expiresAt, revokedAt, useCount, maxUses),
			})
		}
	}
	if rows.Err() != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"invite links could not be loaded"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items":items,"count":len(items)})
}

func revokeGroupInvite(c *gin.Context) {
	groupID, userID := c.Param("id"), c.GetString("user_id")
	if !isGroupAdmin(groupID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error":"admin access required"})
		return
	}
	var revokedAt time.Time
	err := db.QueryRow(c.Request.Context(), `UPDATE group_invites
		SET revoked_at=COALESCE(revoked_at,NOW())
		WHERE id=$1 AND conversation_id=$2 RETURNING revoked_at`, c.Param("inviteId"), groupID).Scan(&revokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		c.JSON(http.StatusNotFound, gin.H{"error":"invite link not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"invite link could not be revoked"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id":c.Param("inviteId"),"status":"revoked","revoked_at":revokedAt})
}

func resetGroupInvites(c *gin.Context) {
	groupID, userID := c.Param("id"), c.GetString("user_id")
	if !isGroupAdmin(groupID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error":"admin access required"})
		return
	}
	var settings groupInviteSettings
	if c.ShouldBindJSON(&settings) != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error":"invalid invite settings"})
		return
	}
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"invite links could not be reset"})
		return
	}
	defer tx.Rollback(ctx)
	command, err := tx.Exec(ctx, `UPDATE group_invites SET revoked_at=NOW()
		WHERE conversation_id=$1 AND revoked_at IS NULL AND expires_at>NOW() AND use_count<max_uses`, groupID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"invite links could not be reset"})
		return
	}
	invite, err := createGroupInviteRecord(ctx, tx, groupID, userID, settings)
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error":"new invite link could not be created"})
		return
	}
	response := invite.response()
	response["revoked_count"] = command.RowsAffected()
	c.JSON(http.StatusCreated, response)
}

func groupInviteStatus(now, expiresAt time.Time, revokedAt *time.Time, useCount, maxUses int) string {
	if revokedAt != nil {
		return "revoked"
	}
	if !expiresAt.After(now) {
		return "expired"
	}
	if useCount >= maxUses {
		return "exhausted"
	}
	return "active"
}
