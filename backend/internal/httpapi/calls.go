package httpapi

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

func listCalls(c *gin.Context) {
	userID:=c.GetString("user_id")
	_,_=db.Exec(c.Request.Context(),`UPDATE calls SET status='missed',ended_at=NOW() WHERE status='ringing' AND started_at<NOW()-INTERVAL '60 seconds'`)
	rows,err:=db.Query(c.Request.Context(),`SELECT calls.id::text,COALESCE(calls.conversation_id::text,''),calls.kind::text,calls.status::text,calls.started_at,calls.ended_at,
		COALESCE(conv.title,other.full_name,other.username,'GroopX call') AS title,COALESCE(other.avatar_url,'')
		FROM calls JOIN call_participants mine ON mine.call_id=calls.id AND mine.user_id=$1
		LEFT JOIN conversations conv ON conv.id=calls.conversation_id
		LEFT JOIN LATERAL (SELECT u.full_name,u.username,u.avatar_url FROM call_participants cp JOIN users u ON u.id=cp.user_id WHERE cp.call_id=calls.id AND cp.user_id<>$1 LIMIT 1) other ON TRUE
		ORDER BY calls.started_at DESC LIMIT 100`,userID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"call history could not be loaded"});return};defer rows.Close();items:=make([]gin.H,0)
	for rows.Next(){var id,conversationID,kind,status,title,avatar string;var started time.Time;var ended *time.Time;if rows.Scan(&id,&conversationID,&kind,&status,&started,&ended,&title,&avatar)==nil{items=append(items,gin.H{"id":id,"conversation_id":conversationID,"kind":kind,"status":status,"title":title,"avatar_url":avatar,"started_at":started,"ended_at":ended})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func createCallToken(c *gin.Context) {
	if !liveKitConfigured() { c.JSON(http.StatusServiceUnavailable, gin.H{"error":"LiveKit is not configured"}); return }
	userID := c.GetString("user_id")
	var input struct {
		ConversationID string `json:"conversation_id" binding:"required,uuid"`
		Kind string `json:"kind" binding:"required,oneof=audio video"`
	}
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error":"invalid call request"}); return }
	if !isConversationMember(c, input.ConversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error":"not a conversation member"}); return }
	var blocked bool
	_ = db.QueryRow(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM conversations c JOIN conversation_members other ON other.conversation_id=c.id AND other.user_id<>$2 JOIN user_blocks b ON (b.blocker_id=$2 AND b.blocked_id=other.user_id) OR (b.blocker_id=other.user_id AND b.blocked_id=$2) WHERE c.id=$1 AND c.kind='direct')`,input.ConversationID,userID).Scan(&blocked)
	if blocked { c.JSON(http.StatusForbidden,gin.H{"error":"call unavailable because communication is blocked"}); return }
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx); if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call could not be created"}); return }; defer tx.Rollback(ctx)
	var callID, room string
	err = tx.QueryRow(ctx, `INSERT INTO calls(conversation_id,initiated_by,room_name,kind) VALUES($1,$2,'groopx-'||gen_random_uuid()::text,$3) RETURNING id::text,room_name`, input.ConversationID, userID, input.Kind).Scan(&callID, &room)
	if err == nil { _, err = tx.Exec(ctx, `INSERT INTO call_participants(call_id,user_id) SELECT $1,user_id FROM conversation_members WHERE conversation_id=$2`, callID, input.ConversationID) }
	if err == nil { _, err = tx.Exec(ctx, `UPDATE call_participants SET joined_at=NOW() WHERE call_id=$1 AND user_id=$2`, callID, userID) }
	if err != nil || tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call could not be created"}); return }
	token, err := liveKitToken(room, userID); if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call token could not be created"}); return }
	notifyConversation(input.ConversationID,userID,"call","Incoming call",input.Kind+" call",map[string]any{"conversation_id":input.ConversationID,"call_id":callID,"kind":input.Kind})
	c.JSON(http.StatusCreated, gin.H{"id":callID,"conversation_id":input.ConversationID,"kind":input.Kind,"status":"ringing","url":os.Getenv("LIVEKIT_URL"),"token":token,"room":room})
}

func joinCall(c *gin.Context) {
	if !liveKitConfigured() { c.JSON(http.StatusServiceUnavailable, gin.H{"error":"LiveKit is not configured"}); return }
	userID := c.GetString("user_id")
	var room, kind, status string
	err := db.QueryRow(c.Request.Context(), `SELECT calls.room_name,calls.kind::text,calls.status::text FROM calls JOIN call_participants p ON p.call_id=calls.id JOIN conversations c ON c.id=calls.conversation_id
		WHERE calls.id=$1 AND p.user_id=$2 AND (c.kind<>'direct' OR NOT EXISTS(SELECT 1 FROM conversation_members other JOIN user_blocks b ON (b.blocker_id=$2 AND b.blocked_id=other.user_id) OR (b.blocker_id=other.user_id AND b.blocked_id=$2)
			WHERE other.conversation_id=calls.conversation_id AND other.user_id<>$2))`, c.Param("id"), userID).Scan(&room,&kind,&status)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error":"call not found"}); return }
	if status == "ended" || status == "declined" || status == "missed" { c.JSON(http.StatusConflict, gin.H{"error":"call is no longer active"}); return }
	_, _ = db.Exec(c.Request.Context(), `UPDATE call_participants SET joined_at=COALESCE(joined_at,NOW()) WHERE call_id=$1 AND user_id=$2`, c.Param("id"), userID)
	_, _ = db.Exec(c.Request.Context(), `UPDATE calls SET status='answered',answered_at=COALESCE(answered_at,NOW()) WHERE id=$1 AND status='ringing'`, c.Param("id"))
	token, err := liveKitToken(room,userID); if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call token could not be created"}); return }
	c.JSON(http.StatusOK, gin.H{"id":c.Param("id"),"kind":kind,"status":"answered","url":os.Getenv("LIVEKIT_URL"),"token":token,"room":room})
}

func declineCall(c *gin.Context) {
	userID:=c.GetString("user_id")
	command,err:=db.Exec(c.Request.Context(),`UPDATE calls SET status='declined',ended_at=NOW() WHERE id=$1 AND status='ringing' AND initiated_by<>$2 AND EXISTS(SELECT 1 FROM call_participants WHERE call_id=calls.id AND user_id=$2)`,c.Param("id"),userID)
	if err!=nil||command.RowsAffected()==0{c.JSON(http.StatusNotFound,gin.H{"error":"ringing call not found"});return}
	_,_=db.Exec(c.Request.Context(),`UPDATE call_participants SET left_at=COALESCE(left_at,NOW()) WHERE call_id=$1 AND user_id=$2`,c.Param("id"),userID)
	c.JSON(http.StatusOK,gin.H{"id":c.Param("id"),"status":"declined"})
}

func endCall(c *gin.Context) {
	userID := c.GetString("user_id")
	ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"call could not be ended"});return};defer tx.Rollback(ctx)
	var initiatorID,status string
	err=tx.QueryRow(ctx,`SELECT initiated_by::text,status::text FROM calls WHERE id=$1 AND status IN ('ringing','answered') AND EXISTS(SELECT 1 FROM call_participants WHERE call_id=calls.id AND user_id=$2) FOR UPDATE`,c.Param("id"),userID).Scan(&initiatorID,&status)
	if err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"active call not found"});return}
	_,err=tx.Exec(ctx,`UPDATE call_participants SET left_at=COALESCE(left_at,NOW()) WHERE call_id=$1 AND user_id=$2`,c.Param("id"),userID)
	var activeOthers int;if err==nil{err=tx.QueryRow(ctx,`SELECT COUNT(*) FROM call_participants WHERE call_id=$1 AND user_id<>$2 AND joined_at IS NOT NULL AND left_at IS NULL`,c.Param("id"),userID).Scan(&activeOthers)}
	ended:=initiatorID==userID||activeOthers==0
	if err==nil&&ended{_,err=tx.Exec(ctx,`UPDATE calls SET status='ended',ended_at=NOW() WHERE id=$1`,c.Param("id"))}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"call could not be ended"});return}
	resultStatus:="left";if ended{resultStatus="ended"};c.JSON(http.StatusOK,gin.H{"id":c.Param("id"),"status":resultStatus,"ended_at":time.Now()})
}

func liveKitConfigured() bool { return os.Getenv("LIVEKIT_API_KEY") != "" && os.Getenv("LIVEKIT_API_SECRET") != "" && os.Getenv("LIVEKIT_URL") != "" }

func liveKitToken(room, userID string) (string,error) {
	now := time.Now().Unix()
	header := map[string]any{"alg":"HS256","typ":"JWT"}
	payload := map[string]any{"iss":os.Getenv("LIVEKIT_API_KEY"),"sub":userID,"nbf":now-5,"exp":now+3600,"video":map[string]any{"roomJoin":true,"room":room,"canPublish":true,"canSubscribe":true}}
	return signJWT(header,payload,os.Getenv("LIVEKIT_API_SECRET"))
}

func signJWT(header,payload map[string]any,secret string)(string,error){
	headerJSON,err:=json.Marshal(header);if err!=nil{return "",err};payloadJSON,err:=json.Marshal(payload);if err!=nil{return "",err}
	encode:=base64.RawURLEncoding.EncodeToString;unsigned:=encode(headerJSON)+"."+encode(payloadJSON);mac:=hmac.New(sha256.New,[]byte(secret));_,_=mac.Write([]byte(unsigned));return unsigned+"."+encode(mac.Sum(nil)),nil
}
