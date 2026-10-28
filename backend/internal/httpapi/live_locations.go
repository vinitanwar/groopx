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

const liveLocationMaximumDuration = 8 * time.Hour

type liveLocationState struct {
	id             string
	messageID      string
	conversationID string
	ownerID        string
	latitude       float64
	longitude      float64
	accuracy       float64
	startedAt      time.Time
	expiresAt      time.Time
	updatedAt      time.Time
	stoppedAt      *time.Time
}

const liveLocationSelect = `SELECT location.id::text,location.message_id::text,location.conversation_id::text,
	location.owner_id::text,location.latitude,location.longitude,location.accuracy_meters,
	location.started_at,location.expires_at,location.updated_at,location.stopped_at
	FROM live_locations location`

type liveLocationScanner interface {
	Scan(dest ...any) error
}

func scanLiveLocation(scanner liveLocationScanner, location *liveLocationState) error {
	return scanner.Scan(&location.id, &location.messageID, &location.conversationID, &location.ownerID,
		&location.latitude, &location.longitude, &location.accuracy, &location.startedAt,
		&location.expiresAt, &location.updatedAt, &location.stoppedAt)
}

func createLiveLocation(c *gin.Context) {
	conversationID, userID := c.Param("id"), c.GetString("user_id")
	var input struct {
		Latitude        *float64 `json:"latitude"`
		Longitude       *float64 `json:"longitude"`
		AccuracyMeters  *float64 `json:"accuracy_meters"`
		DurationSeconds int      `json:"duration_seconds" binding:"required"`
		TrackingKey     string   `json:"tracking_key" binding:"required,min=16,max=128"`
	}
	if c.ShouldBindJSON(&input) != nil || !validLiveCoordinates(input.Latitude, input.Longitude, input.AccuracyMeters) || !validLiveLocationDuration(input.DurationSeconds) || !validLiveLocationTrackingKey(input.TrackingKey) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid location and duration are required"})
		return
	}
	if !isConversationMember(c, conversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "not a conversation member"})
		return
	}
	if !requireConversationSender(c, conversationID, userID) { return }
	if scheduledCommunicationBlocked(c.Request.Context(), conversationID, userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "communication is blocked"})
		return
	}
	accuracy := 0.0
	if input.AccuracyMeters != nil { accuracy = *input.AccuracyMeters }
	status := "sent"
	if onlineRecipients(conversationID, userID) > 0 || isConversationPeerOnline(conversationID, userID) { status = "delivered" }

	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be started"}); return }
	defer tx.Rollback(ctx)
	var lock any
	if tx.QueryRow(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, "live-location:"+conversationID+":"+userID).Scan(&lock) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be started"}); return
	}
	previous, err := liveLocationsForUpdate(ctx, tx, ` WHERE location.conversation_id=$1 AND location.owner_id=$2 AND location.stopped_at IS NULL FOR UPDATE`, conversationID, userID)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be started"}); return }
	for index := range previous {
		if err = stopLiveLocationState(ctx, tx, &previous[index]); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be started"}); return
		}
	}

	var messageID string
	var createdAt time.Time
	err = tx.QueryRow(ctx, `INSERT INTO messages(conversation_id,sender_id,kind,body,metadata,status)
		VALUES($1,$2,'location','Live location','{}'::jsonb,$3) RETURNING id::text,created_at`, conversationID, userID, status).Scan(&messageID, &createdAt)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be started"}); return }
	location := liveLocationState{messageID: messageID, conversationID: conversationID, ownerID: userID, latitude: *input.Latitude, longitude: *input.Longitude, accuracy: accuracy}
	err = tx.QueryRow(ctx, `INSERT INTO live_locations(message_id,conversation_id,owner_id,tracking_key,latitude,longitude,accuracy_meters,expires_at)
		VALUES($1,$2,$3,$4,$5,$6,$7,NOW()+($8*INTERVAL '1 second'))
		RETURNING id::text,started_at,expires_at,updated_at`, messageID, conversationID, userID, input.TrackingKey, location.latitude, location.longitude, location.accuracy, input.DurationSeconds).
		Scan(&location.id, &location.startedAt, &location.expiresAt, &location.updatedAt)
	if err == nil { err = saveLiveLocationAttachment(ctx, tx, location) }
	if err == nil { _, err = tx.Exec(ctx, `UPDATE conversations SET last_message_at=$2,updated_at=NOW() WHERE id=$1`, conversationID, createdAt) }
	if err == nil { _, err = tx.Exec(ctx, `UPDATE conversation_members SET hidden_at=NULL WHERE conversation_id=$1 AND user_id<>$2`, conversationID, userID) }
	if err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be started"}); return
	}
	for _, stopped := range previous { broadcastLiveLocation(stopped) }
	senderName, senderAvatar := messageSenderIdentity(ctx, conversationID, userID)
	attachment := liveLocationAttachment(location)
	payload := gin.H{"type": "message", "id": messageID, "conversation_id": conversationID, "sender_id": userID,
		"sender_name": senderName, "sender_avatar_url": senderAvatar, "text": "Live location", "kind": "location",
		"attachment": attachment, "status": status, "created_at": createdAt}
	broadcast(conversationID, userID, payload)
	notifyConversation(conversationID, userID, "location", "Live location shared", "Tap to view live location", map[string]any{"conversation_id": conversationID, "message_id": messageID})
	payload["mine"] = true
	c.JSON(http.StatusCreated, gin.H{"live_location": liveLocationJSON(location), "message": payload})
}

func listActiveLiveLocations(c *gin.Context) {
	userID, trackingKey := c.GetString("user_id"), c.GetHeader("X-Live-Location-Device")
	if !validLiveLocationTrackingKey(trackingKey) { c.JSON(http.StatusBadRequest, gin.H{"error": "live location device is required"}); return }
	expireLiveLocations(c.Request.Context())
	rows, err := db.Query(c.Request.Context(), liveLocationSelect+` WHERE location.owner_id=$1 AND location.tracking_key=$2 AND location.stopped_at IS NULL AND location.expires_at>NOW() ORDER BY location.expires_at`, userID, trackingKey)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live locations could not be loaded"}); return }
	defer rows.Close()
	items := make([]gin.H, 0)
	for rows.Next() {
		var location liveLocationState
		if scanLiveLocation(rows, &location) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live locations could not be loaded"}); return }
		items = append(items, liveLocationJSON(location))
	}
	if rows.Err() != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live locations could not be loaded"}); return }
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func updateActiveLiveLocations(c *gin.Context) {
	userID, trackingKey := c.GetString("user_id"), c.GetHeader("X-Live-Location-Device")
	if !validLiveLocationTrackingKey(trackingKey) { c.JSON(http.StatusBadRequest, gin.H{"error": "live location device is required"}); return }
	var input struct {
		Latitude       *float64 `json:"latitude"`
		Longitude      *float64 `json:"longitude"`
		AccuracyMeters *float64 `json:"accuracy_meters"`
	}
	if c.ShouldBindJSON(&input) != nil || !validLiveCoordinates(input.Latitude, input.Longitude, input.AccuracyMeters) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "valid location is required"})
		return
	}
	accuracy := 0.0
	if input.AccuracyMeters != nil { accuracy = *input.AccuracyMeters }
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be updated"}); return }
	defer tx.Rollback(ctx)
	locations, err := liveLocationsForUpdate(ctx, tx, ` WHERE location.owner_id=$1 AND location.tracking_key=$2 AND location.stopped_at IS NULL FOR UPDATE`, userID, trackingKey)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be updated"}); return }
	active := make([]liveLocationState, 0, len(locations))
	changed := make([]liveLocationState, 0, len(locations))
	for index := range locations {
		location := &locations[index]
		allowed, checkErr := liveLocationCanContinue(ctx, tx, location.conversationID, userID)
		if checkErr != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be updated"}); return }
		if !allowed || !location.expiresAt.After(time.Now()) {
			if err = stopLiveLocationState(ctx, tx, location); err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be updated"}); return }
			changed = append(changed, *location)
			continue
		}
		location.latitude, location.longitude, location.accuracy = *input.Latitude, *input.Longitude, accuracy
		err = tx.QueryRow(ctx, `UPDATE live_locations SET latitude=$2,longitude=$3,accuracy_meters=$4,updated_at=NOW()
			WHERE id=$1 AND stopped_at IS NULL RETURNING updated_at`, location.id, location.latitude, location.longitude, location.accuracy).Scan(&location.updatedAt)
		if err == nil { err = saveLiveLocationAttachment(ctx, tx, *location) }
		if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be updated"}); return }
		active = append(active, *location)
		changed = append(changed, *location)
	}
	if tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be updated"}); return }
	for _, location := range changed { broadcastLiveLocation(location) }
	items := make([]gin.H, 0, len(active))
	for _, location := range active { items = append(items, liveLocationJSON(location)) }
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func stopActiveLiveLocations(c *gin.Context) {
	ctx, userID, trackingKey := c.Request.Context(), c.GetString("user_id"), c.GetHeader("X-Live-Location-Device")
	if !validLiveLocationTrackingKey(trackingKey) { c.JSON(http.StatusBadRequest, gin.H{"error": "live location device is required"}); return }
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live locations could not be stopped"}); return }
	defer tx.Rollback(ctx)
	locations, err := liveLocationsForUpdate(ctx, tx, ` WHERE location.owner_id=$1 AND location.tracking_key=$2 AND location.stopped_at IS NULL FOR UPDATE`, userID, trackingKey)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live locations could not be stopped"}); return }
	for index := range locations {
		if err = stopLiveLocationState(ctx, tx, &locations[index]); err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live locations could not be stopped"}); return }
	}
	if tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live locations could not be stopped"}); return }
	for _, location := range locations { broadcastLiveLocation(location) }
	c.Status(http.StatusNoContent)
}

func stopLiveLocation(c *gin.Context) {
	ctx, userID := c.Request.Context(), c.GetString("user_id")
	tx, err := db.Begin(ctx)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be stopped"}); return }
	defer tx.Rollback(ctx)
	locations, err := liveLocationsForUpdate(ctx, tx, ` WHERE location.id=$1 AND location.owner_id=$2 AND location.stopped_at IS NULL FOR UPDATE`, c.Param("id"), userID)
	if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be stopped"}); return }
	if len(locations) == 0 { c.JSON(http.StatusNotFound, gin.H{"error": "active live location not found"}); return }
	location := locations[0]
	if err = stopLiveLocationState(ctx, tx, &location); err != nil || tx.Commit(ctx) != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "live location could not be stopped"}); return
	}
	broadcastLiveLocation(location)
	c.Status(http.StatusNoContent)
}

func validLiveCoordinates(latitude, longitude, accuracy *float64) bool {
	if latitude == nil || longitude == nil || *latitude < -90 || *latitude > 90 || *longitude < -180 || *longitude > 180 { return false }
	return accuracy == nil || (*accuracy >= 0 && *accuracy <= 5000)
}

func validLiveLocationDuration(seconds int) bool {
	return seconds == int((15*time.Minute)/time.Second) || seconds == int(time.Hour/time.Second) || seconds == int(liveLocationMaximumDuration/time.Second)
}

func validLiveLocationTrackingKey(value string) bool {
	if len(value) < 16 || len(value) > 128 { return false }
	for _, character := range value {
		if (character < 'a' || character > 'z') && (character < 'A' || character > 'Z') && (character < '0' || character > '9') && character != '-' && character != '_' { return false }
	}
	return true
}

func liveLocationsForUpdate(ctx context.Context, tx pgx.Tx, suffix string, arguments ...any) ([]liveLocationState, error) {
	rows, err := tx.Query(ctx, liveLocationSelect+suffix, arguments...)
	if err != nil { return nil, err }
	defer rows.Close()
	items := make([]liveLocationState, 0)
	for rows.Next() {
		var item liveLocationState
		if err = scanLiveLocation(rows, &item); err != nil { return nil, err }
		items = append(items, item)
	}
	return items, rows.Err()
}

func liveLocationCanContinue(ctx context.Context, tx pgx.Tx, conversationID, ownerID string) (bool, error) {
	var allowed bool
	err := tx.QueryRow(ctx, `SELECT EXISTS(
		SELECT 1 FROM conversations conversation
		JOIN conversation_members owner ON owner.conversation_id=conversation.id AND owner.user_id=$2 AND owner.hidden_at IS NULL
		JOIN users account ON account.id=$2 AND account.account_status='active'
		WHERE conversation.id=$1 AND conversation.deleted_at IS NULL
		AND (conversation.kind<>'group' OR NOT conversation.announcement_only OR owner.role='admin')
		AND (conversation.kind<>'direct' OR (
			EXISTS(SELECT 1 FROM conversation_members peer WHERE peer.conversation_id=conversation.id AND peer.user_id<>$2 AND peer.hidden_at IS NULL)
			AND NOT EXISTS(
				SELECT 1 FROM conversation_members peer JOIN user_blocks block
				ON (block.blocker_id=$2 AND block.blocked_id=peer.user_id) OR (block.blocker_id=peer.user_id AND block.blocked_id=$2)
				WHERE peer.conversation_id=conversation.id AND peer.user_id<>$2
			)
		))
	)`, conversationID, ownerID).Scan(&allowed)
	return allowed, err
}

func stopLiveLocationState(ctx context.Context, tx pgx.Tx, location *liveLocationState) error {
	var stoppedAt time.Time
	err := tx.QueryRow(ctx, `UPDATE live_locations SET stopped_at=NOW(),updated_at=NOW() WHERE id=$1 AND stopped_at IS NULL RETURNING stopped_at,updated_at`, location.id).
		Scan(&stoppedAt, &location.updatedAt)
	if errors.Is(err, pgx.ErrNoRows) { return nil }
	if err != nil { return err }
	location.stoppedAt = &stoppedAt
	return saveLiveLocationAttachment(ctx, tx, *location)
}

func saveLiveLocationAttachment(ctx context.Context, tx pgx.Tx, location liveLocationState) error {
	encoded, err := json.Marshal(liveLocationAttachment(location))
	if err != nil { return err }
	_, err = tx.Exec(ctx, `UPDATE messages SET metadata=$2::jsonb WHERE id=$1 AND deleted_at IS NULL`, location.messageID, encoded)
	return err
}

func liveLocationAttachment(location liveLocationState) gin.H {
	active := location.stoppedAt == nil && location.expiresAt.After(time.Now())
	attachment := gin.H{
		"latitude": location.latitude, "longitude": location.longitude, "accuracy_meters": location.accuracy,
		"label": "Live location", "map_url": liveLocationMapURL(location.latitude, location.longitude),
		"live": true, "active": active, "live_location_id": location.id,
		"started_at": location.startedAt, "expires_at": location.expiresAt, "updated_at": location.updatedAt,
	}
	if location.stoppedAt != nil { attachment["stopped_at"] = *location.stoppedAt }
	return attachment
}

func liveLocationJSON(location liveLocationState) gin.H {
	return gin.H{
		"id": location.id, "message_id": location.messageID, "conversation_id": location.conversationID,
		"expires_at": location.expiresAt, "updated_at": location.updatedAt, "attachment": liveLocationAttachment(location),
	}
}

func liveLocationMapURL(latitude, longitude float64) string {
	return "https://www.google.com/maps/search/?api=1&query=" + formatCoordinate(latitude) + "," + formatCoordinate(longitude)
}

func broadcastLiveLocation(location liveLocationState) {
	payload := gin.H{
		"type": "live_location_update", "conversation_id": location.conversationID,
		"live_location_id": location.id, "message_id": location.messageID,
		"sender_id": location.ownerID, "attachment": liveLocationAttachment(location),
	}
	broadcast(location.conversationID, location.ownerID, payload)
	broadcast("user:"+location.ownerID, location.ownerID, payload)
}

func startLiveLocationScheduler() {
	go func() {
		expireLiveLocations(context.Background())
		ticker := time.NewTicker(15 * time.Second)
		defer ticker.Stop()
		for range ticker.C { expireLiveLocations(context.Background()) }
	}()
}

func expireLiveLocations(ctx context.Context) {
	tx, err := db.Begin(ctx)
	if err != nil { return }
	defer tx.Rollback(ctx)
	locations, err := liveLocationsForUpdate(ctx, tx, ` WHERE location.stopped_at IS NULL AND (
		location.expires_at<=NOW() OR NOT EXISTS(
			SELECT 1 FROM conversations conversation
			JOIN conversation_members owner ON owner.conversation_id=conversation.id AND owner.user_id=location.owner_id AND owner.hidden_at IS NULL
			JOIN users account ON account.id=location.owner_id AND account.account_status='active'
			WHERE conversation.id=location.conversation_id AND conversation.deleted_at IS NULL
			AND (conversation.kind<>'group' OR NOT conversation.announcement_only OR owner.role='admin')
			AND (conversation.kind<>'direct' OR (
				EXISTS(SELECT 1 FROM conversation_members peer WHERE peer.conversation_id=conversation.id AND peer.user_id<>location.owner_id AND peer.hidden_at IS NULL)
				AND NOT EXISTS(
					SELECT 1 FROM conversation_members peer JOIN user_blocks block
					ON (block.blocker_id=location.owner_id AND block.blocked_id=peer.user_id) OR (block.blocker_id=peer.user_id AND block.blocked_id=location.owner_id)
					WHERE peer.conversation_id=conversation.id AND peer.user_id<>location.owner_id
				)
			))
		)
	) ORDER BY location.expires_at LIMIT 200 FOR UPDATE SKIP LOCKED`)
	if err != nil { return }
	for index := range locations {
		if err = stopLiveLocationState(ctx, tx, &locations[index]); err != nil { return }
	}
	if tx.Commit(ctx) != nil { return }
	for _, location := range locations { broadcastLiveLocation(location) }
}

func stopLiveLocationForMessage(ctx context.Context, messageID, ownerID string) {
	var location liveLocationState
	err := scanLiveLocation(db.QueryRow(ctx, liveLocationSelect+` WHERE location.message_id=$1 AND location.owner_id=$2 AND location.stopped_at IS NULL`, messageID, ownerID), &location)
	if err != nil { return }
	var stoppedAt time.Time
	if db.QueryRow(ctx, `UPDATE live_locations SET stopped_at=NOW(),updated_at=NOW() WHERE id=$1 AND stopped_at IS NULL RETURNING stopped_at`, location.id).Scan(&stoppedAt) != nil { return }
	location.stoppedAt, location.updatedAt = &stoppedAt, stoppedAt
	broadcastLiveLocation(location)
}

func stopLiveLocationsInTransaction(ctx context.Context, tx pgx.Tx, conversationID, ownerID string) ([]liveLocationState, error) {
	locations, err := liveLocationsForUpdate(ctx, tx, ` WHERE location.conversation_id=$1 AND location.owner_id=$2 AND location.stopped_at IS NULL FOR UPDATE`, conversationID, ownerID)
	if err != nil { return nil, err }
	for index := range locations {
		if err = stopLiveLocationState(ctx, tx, &locations[index]); err != nil { return nil, err }
	}
	return locations, nil
}
