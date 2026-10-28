package httpapi

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
)

func listCalls(c *gin.Context) {
	userID:=c.GetString("user_id")
	expireRingingCalls(c.Request.Context(),"","")
	rows,err:=db.Query(c.Request.Context(),`SELECT calls.id::text,COALESCE(calls.conversation_id::text,''),COALESCE(calls.reminder_id::text,''),calls.kind::text,calls.status::text,calls.started_at,calls.answered_at,calls.ended_at,
		COALESCE(calls.initiated_by=$1,FALSE) AS outgoing,
		CASE WHEN calls.answered_at IS NULL THEN 0 ELSE GREATEST(0,EXTRACT(EPOCH FROM (COALESCE(calls.ended_at,NOW())-calls.answered_at))::int) END AS duration_seconds,
		(SELECT COUNT(*)::int FROM call_participants everyone WHERE everyone.call_id=calls.id) AS participant_count,
		COALESCE(NULLIF(meeting.title,''),NULLIF(conv.title,''),NULLIF(other.full_name,''),NULLIF(other.username,''),'GroopX call') AS title,
		COALESCE(NULLIF(conv.avatar_url,''),NULLIF(other.avatar_url,''),'')
		FROM calls JOIN call_participants mine ON mine.call_id=calls.id AND mine.user_id=$1
		LEFT JOIN conversations conv ON conv.id=calls.conversation_id
		LEFT JOIN reminders meeting ON meeting.id=calls.reminder_id
		LEFT JOIN LATERAL (SELECT u.full_name,u.username,u.avatar_url FROM call_participants cp JOIN users u ON u.id=cp.user_id WHERE cp.call_id=calls.id AND cp.user_id<>$1 LIMIT 1) other ON TRUE
		ORDER BY calls.started_at DESC LIMIT 100`,userID)
	if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"call history could not be loaded"});return};defer rows.Close();items:=make([]gin.H,0)
	for rows.Next(){var id,conversationID,reminderID,kind,status,title,avatar string;var started time.Time;var answered,ended *time.Time;var outgoing bool;var duration,participants int;if rows.Scan(&id,&conversationID,&reminderID,&kind,&status,&started,&answered,&ended,&outgoing,&duration,&participants,&title,&avatar)==nil{items=append(items,gin.H{"id":id,"conversation_id":conversationID,"reminder_id":reminderID,"kind":kind,"status":status,"title":title,"avatar_url":avatar,"started_at":started,"answered_at":answered,"ended_at":ended,"outgoing":outgoing,"duration_seconds":duration,"participant_count":participants})}}
	c.JSON(http.StatusOK,gin.H{"items":items})
}

func getCallStatus(c *gin.Context) {
	userID:=c.GetString("user_id")
	expireRingingCalls(c.Request.Context(),"",c.Param("id"))
	var status,kind,reminderID,meetingTitle string;var answeredAt,endedAt *time.Time
	err:=db.QueryRow(c.Request.Context(),`SELECT calls.status::text,calls.kind::text,calls.answered_at,calls.ended_at,COALESCE(calls.reminder_id::text,''),COALESCE(reminder.title,'') FROM calls JOIN call_participants cp ON cp.call_id=calls.id LEFT JOIN reminders reminder ON reminder.id=calls.reminder_id WHERE calls.id=$1 AND cp.user_id=$2`,c.Param("id"),userID).Scan(&status,&kind,&answeredAt,&endedAt,&reminderID,&meetingTitle)
	if err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"call not found"});return}
	c.JSON(http.StatusOK,gin.H{"id":c.Param("id"),"status":status,"kind":kind,"reminder_id":reminderID,"meeting_title":meetingTitle,"answered_at":answeredAt,"ended_at":endedAt})
}

type scheduledMeetingAccess struct {
	title string
	kind string
	isOrganizer bool
}

func createCallToken(c *gin.Context) {
	if !liveKitConfigured() { c.JSON(http.StatusServiceUnavailable, gin.H{"error":"LiveKit is not configured"}); return }
	userID := c.GetString("user_id")
	var input struct {
		ConversationID string `json:"conversation_id" binding:"required,uuid"`
		Kind string `json:"kind" binding:"required,oneof=audio video"`
		ReminderID string `json:"reminder_id" binding:"omitempty,uuid"`
	}
	if c.ShouldBindJSON(&input) != nil { c.JSON(http.StatusBadRequest, gin.H{"error":"invalid call request"}); return }
	if !isConversationMember(c, input.ConversationID, userID) { c.JSON(http.StatusForbidden, gin.H{"error":"not a conversation member"}); return }
	var conversationKind string
	if err:=db.QueryRow(c.Request.Context(),`SELECT kind::text FROM conversations WHERE id=$1`,input.ConversationID).Scan(&conversationKind);err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"conversation not found"});return}
	input.ReminderID = strings.TrimSpace(input.ReminderID)
	meeting := scheduledMeetingAccess{}
	if input.ReminderID != "" {
		err := db.QueryRow(c.Request.Context(), `SELECT meeting.title,meeting.call_kind::text,meeting.user_id=$3
			FROM reminders meeting
			LEFT JOIN meeting_attendees attendee ON attendee.meeting_id=meeting.id AND attendee.user_id=$3
			WHERE meeting.id=$1 AND meeting.conversation_id=$2 AND meeting.item_type='meeting' AND meeting.status='upcoming'
				AND (meeting.user_id=$3 OR attendee.response='accepted')
				AND EXISTS(SELECT 1 FROM conversation_members member WHERE member.conversation_id=meeting.conversation_id
					AND member.user_id=$3 AND member.hidden_at IS NULL)`, input.ReminderID, input.ConversationID, userID).Scan(&meeting.title, &meeting.kind, &meeting.isOrganizer)
		if errors.Is(err, pgx.ErrNoRows) { c.JSON(http.StatusForbidden, gin.H{"error":"scheduled meeting is unavailable or its invitation has not been accepted"}); return }
		if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"scheduled meeting could not be checked"}); return }
		if meeting.kind != input.Kind { c.JSON(http.StatusBadRequest, gin.H{"error":"call type does not match the scheduled meeting"}); return }
	}
	if conversationKind=="direct"{var blocked bool;_ = db.QueryRow(c.Request.Context(),`SELECT EXISTS(SELECT 1 FROM conversation_members other JOIN user_blocks b ON (b.blocker_id=$2 AND b.blocked_id=other.user_id) OR (b.blocker_id=other.user_id AND b.blocked_id=$2) WHERE other.conversation_id=$1 AND other.user_id<>$2)`,input.ConversationID,userID).Scan(&blocked);if blocked{c.JSON(http.StatusForbidden,gin.H{"error":"call unavailable because communication is blocked"});return}}
	expireRingingCalls(c.Request.Context(),input.ConversationID,"")
	if input.ReminderID != "" {
		var activeCallID, room, activeKind, activeStatus, initiatorID string
		err := db.QueryRow(c.Request.Context(), `SELECT id::text,room_name,kind::text,status::text,initiated_by::text
			FROM calls WHERE reminder_id=$1 AND status IN ('ringing','answered') AND started_at>NOW()-INTERVAL '2 hours'
			ORDER BY started_at DESC LIMIT 1`, input.ReminderID).Scan(&activeCallID, &room, &activeKind, &activeStatus, &initiatorID)
		if err == nil {
			if _, err = db.Exec(c.Request.Context(), `INSERT INTO call_participants(call_id,user_id) VALUES($1,$2) ON CONFLICT(call_id,user_id) DO NOTHING`, activeCallID, userID); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting call could not be joined"}); return
			}
			if _, err = db.Exec(c.Request.Context(), `UPDATE call_participants SET joined_at=COALESCE(joined_at,NOW()),left_at=NULL WHERE call_id=$1 AND user_id=$2`, activeCallID, userID); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting call could not be joined"}); return
			}
			answered := false
			if initiatorID != userID && activeStatus == "ringing" {
				command, updateErr := db.Exec(c.Request.Context(), `UPDATE calls SET status='answered',answered_at=COALESCE(answered_at,NOW()) WHERE id=$1 AND status='ringing'`, activeCallID)
				if updateErr != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting call could not be joined"}); return }
				answered = command.RowsAffected() > 0
				activeStatus = "answered"
			}
			token, tokenErr := liveKitToken(room, input.ConversationID, userID)
			if tokenErr != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call token could not be created"}); return }
			markMeetingReminderRead(userID,input.ReminderID)
			if answered { syncCallNotification(activeCallID,"answered",userID); broadcastCallUpdate(activeCallID,"answered") }
			c.JSON(http.StatusOK, gin.H{"id":activeCallID,"conversation_id":input.ConversationID,"reminder_id":input.ReminderID,"meeting_title":meeting.title,"kind":activeKind,"status":activeStatus,"url":os.Getenv("LIVEKIT_URL"),"token":token,"room":room})
			return
		}
		if !errors.Is(err, pgx.ErrNoRows) { c.JSON(http.StatusInternalServerError, gin.H{"error":"meeting call could not be checked"}); return }
		if !meeting.isOrganizer { c.JSON(http.StatusConflict, gin.H{"error":"The organizer has not started this meeting yet.","code":"meeting_not_started","reminder_id":input.ReminderID}); return }
		var activeCallID string
		if db.QueryRow(c.Request.Context(),`SELECT id::text FROM calls WHERE conversation_id=$1 AND status IN ('ringing','answered') AND started_at>NOW()-INTERVAL '2 hours' ORDER BY started_at DESC LIMIT 1`,input.ConversationID).Scan(&activeCallID)==nil{c.JSON(http.StatusConflict,gin.H{"error":"an active call already exists","call_id":activeCallID});return}
	} else {
		var activeCallID string
		if db.QueryRow(c.Request.Context(),`SELECT id::text FROM calls WHERE conversation_id=$1 AND status IN ('ringing','answered') AND started_at>NOW()-INTERVAL '2 hours' ORDER BY started_at DESC LIMIT 1`,input.ConversationID).Scan(&activeCallID)==nil{c.JSON(http.StatusConflict,gin.H{"error":"an active call already exists","call_id":activeCallID});return}
	}
	ctx := c.Request.Context()
	tx, err := db.Begin(ctx); if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call could not be created"}); return }; defer tx.Rollback(ctx)
	var callID, room string
	err = tx.QueryRow(ctx, `INSERT INTO calls(conversation_id,initiated_by,room_name,kind,reminder_id) VALUES($1,$2,'groopx-'||gen_random_uuid()::text,$3,NULLIF($4,'')::uuid) RETURNING id::text,room_name`, input.ConversationID, userID, input.Kind, input.ReminderID).Scan(&callID, &room)
	if err == nil && input.ReminderID == "" { _, err = tx.Exec(ctx, `INSERT INTO call_participants(call_id,user_id)
		SELECT $1,$3::uuid
		UNION
		SELECT $1,member.user_id FROM conversation_members member
		JOIN users recipient ON recipient.id=member.user_id AND recipient.account_status='active'
		WHERE member.conversation_id=$2 AND member.hidden_at IS NULL`, callID, input.ConversationID, userID) }
	if err == nil && input.ReminderID != "" { _, err = tx.Exec(ctx, `INSERT INTO call_participants(call_id,user_id)
		SELECT $1,meeting.user_id FROM reminders meeting WHERE meeting.id=$2
		UNION
		SELECT $1,attendee.user_id FROM meeting_attendees attendee
		JOIN reminders meeting ON meeting.id=attendee.meeting_id
		JOIN conversation_members member ON member.conversation_id=meeting.conversation_id AND member.user_id=attendee.user_id AND member.hidden_at IS NULL
		JOIN users invited ON invited.id=attendee.user_id AND invited.account_status='active'
		WHERE attendee.meeting_id=$2 AND attendee.response='accepted'`, callID, input.ReminderID) }
	if err == nil { _, err = tx.Exec(ctx, `UPDATE call_participants SET joined_at=NOW() WHERE call_id=$1 AND user_id=$2`, callID, userID) }
	if err != nil || tx.Commit(ctx) != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call could not be created"}); return }
	token, err := liveKitToken(room, input.ConversationID, userID); if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call token could not be created"}); return }
	if input.ReminderID != "" { markMeetingReminderRead(userID,input.ReminderID) }
	caller,_:=messageSenderIdentity(c.Request.Context(),input.ConversationID,userID)
	data:=map[string]any{"conversation_id":input.ConversationID,"call_id":callID,"kind":input.Kind,"caller":caller,"status":"ringing","group_call":conversationKind!="direct"}
	notificationTitle, notificationBody := caller, "Incoming "+input.Kind+" call"
	if input.ReminderID != "" {
		data["reminder_id"] = input.ReminderID
		data["meeting_title"] = meeting.title
		notificationTitle = meeting.title
		notificationBody = caller+" started the scheduled "+input.Kind+" meeting"
	}
	broadcastIncomingCall(callID,input.ConversationID,userID,input.Kind,caller,input.ReminderID,meeting.title,conversationKind!="direct")
	notifyCallParticipants(callID,userID,notificationTitle,notificationBody,data)
	c.JSON(http.StatusCreated, gin.H{"id":callID,"conversation_id":input.ConversationID,"reminder_id":input.ReminderID,"meeting_title":meeting.title,"kind":input.Kind,"status":"ringing","url":os.Getenv("LIVEKIT_URL"),"token":token,"room":room})
}

func markMeetingReminderRead(userID,reminderID string){
	_,_=db.Exec(context.Background(),`UPDATE notifications SET read_at=COALESCE(read_at,NOW())
		WHERE user_id=$1 AND type='reminder' AND data->>'reminder_id'=$2`,userID,reminderID)
}

func notifyCallParticipants(callID,senderID,title,body string,data map[string]any){
	payload,_:=json.Marshal(data)
	_,_=db.Exec(context.Background(),`INSERT INTO notifications(user_id,type,title,body,data)
		SELECT participant.user_id,'call',$3,$4,$5 FROM call_participants participant
		WHERE participant.call_id=$1 AND participant.user_id<>$2`,callID,senderID,title,body,payload)
	go sendCallPush(callID,senderID,title,body,data)
}

func broadcastIncomingCall(callID,conversationID,callerID,kind,caller,reminderID,meetingTitle string,groupCall bool){
	rows,err:=db.Query(context.Background(),`SELECT user_id::text FROM call_participants WHERE call_id=$1 AND user_id<>$2`,callID,callerID);if err!=nil{return};defer rows.Close()
	userIDs:=make([]string,0);for rows.Next(){var userID string;if rows.Scan(&userID)==nil{userIDs=append(userIDs,userID)}}
	payload:=gin.H{"type":"incoming_call","conversation_id":conversationID,"call_id":callID,"kind":kind,"caller":caller,"group_call":groupCall}
	if reminderID!=""{payload["reminder_id"]=reminderID;payload["meeting_title"]=meetingTitle}
	for _,userID:=range userIDs{room:="user:"+userID;chatHub.RLock();clients:=make([]*socketClient,0,len(chatHub.rooms[room]));for client:=range chatHub.rooms[room]{clients=append(clients,client)};chatHub.RUnlock();for _,client:=range clients{if client.writeJSON(payload)!=nil{leaveRoom(room,client)}}}
}

func broadcastCallUpdate(callID,status string){
	rows,err:=db.Query(context.Background(),`SELECT user_id::text FROM call_participants WHERE call_id=$1`,callID);if err!=nil{return};defer rows.Close()
	userIDs:=make([]string,0);for rows.Next(){var userID string;if rows.Scan(&userID)==nil{userIDs=append(userIDs,userID)}}
	for _,userID:=range userIDs{room:="user:"+userID;chatHub.RLock();clients:=make([]*socketClient,0,len(chatHub.rooms[room]));for client:=range chatHub.rooms[room]{clients=append(clients,client)};chatHub.RUnlock();for _,client:=range clients{if client.writeJSON(gin.H{"type":"call_update","call_id":callID,"status":status})!=nil{leaveRoom(room,client)}}}
}

func broadcastCallUpdateToUser(userID,callID,status string){
	room:="user:"+userID
	chatHub.RLock();clients:=make([]*socketClient,0,len(chatHub.rooms[room]));for client:=range chatHub.rooms[room]{clients=append(clients,client)};chatHub.RUnlock()
	for _,client:=range clients{if client.writeJSON(gin.H{"type":"call_update","call_id":callID,"status":status})!=nil{leaveRoom(room,client)}}
}

func expireRingingCalls(ctx context.Context,conversationID,callID string){
	query:=`UPDATE calls SET status='missed',ended_at=NOW() WHERE status='ringing'
		AND started_at<NOW()-(CASE WHEN reminder_id IS NULL THEN INTERVAL '60 seconds' ELSE INTERVAL '30 minutes' END)`
	args:=make([]any,0,1)
	if callID!=""{query+=` AND id=$1`;args=append(args,callID)}else if conversationID!=""{query+=` AND conversation_id=$1`;args=append(args,conversationID)}
	rows,err:=db.Query(ctx,query+` RETURNING id::text`,args...);if err!=nil{return}
	ids:=make([]string,0);for rows.Next(){var id string;if rows.Scan(&id)==nil{ids=append(ids,id)}};rows.Close()
	for _,id:=range ids{syncCallNotification(id,"missed","");broadcastCallUpdate(id,"missed")}
}

func syncCallNotification(callID,status,readUserID string){
	body:=map[string]string{"answered":"Call in progress · Tap to join","declined":"Call declined","missed":"Missed call · Tap to call back","ended":"Call ended"}[status]
	if body==""{body="Call updated"}
	markAllRead:=status=="declined"||status=="ended"
	_,_=db.Exec(context.Background(),`UPDATE notifications SET title=COALESCE(NULLIF(data->>'meeting_title',''),NULLIF(data->>'caller',''),'GroopX call'),body=$2,data=jsonb_set(data,'{status}',to_jsonb($3::text),TRUE),read_at=CASE WHEN $4 OR user_id=NULLIF($5,'')::uuid THEN COALESCE(read_at,NOW()) ELSE read_at END WHERE type='call' AND data->>'call_id'=$1`,callID,body,status,markAllRead,readUserID)
}

func syncCallNotificationForUser(callID,status,userID string){
	body:=map[string]string{"declined":"Call declined","answered":"Call in progress · Tap to join","ended":"Call ended"}[status]
	if body==""{body="Call updated"}
	_,_=db.Exec(context.Background(),`UPDATE notifications SET title=COALESCE(NULLIF(data->>'meeting_title',''),NULLIF(data->>'caller',''),'GroopX call'),body=$3,data=jsonb_set(data,'{status}',to_jsonb($4::text),TRUE),read_at=COALESCE(read_at,NOW()) WHERE type='call' AND data->>'call_id'=$1 AND user_id=$2`,callID,userID,body,status)
}

func joinCall(c *gin.Context) {
	if !liveKitConfigured() { c.JSON(http.StatusServiceUnavailable, gin.H{"error":"LiveKit is not configured"}); return }
	userID := c.GetString("user_id")
	var room, conversationID, kind, status string
	err := db.QueryRow(c.Request.Context(), `SELECT calls.room_name,calls.conversation_id::text,calls.kind::text,calls.status::text FROM calls JOIN call_participants p ON p.call_id=calls.id JOIN conversations c ON c.id=calls.conversation_id
		WHERE calls.id=$1 AND p.user_id=$2 AND (c.kind<>'direct' OR NOT EXISTS(SELECT 1 FROM conversation_members other JOIN user_blocks b ON (b.blocker_id=$2 AND b.blocked_id=other.user_id) OR (b.blocker_id=other.user_id AND b.blocked_id=$2)
			WHERE other.conversation_id=calls.conversation_id AND other.user_id<>$2))
			AND (calls.reminder_id IS NULL OR EXISTS(
				SELECT 1 FROM reminders meeting
				LEFT JOIN meeting_attendees attendee ON attendee.meeting_id=meeting.id AND attendee.user_id=$2
				WHERE meeting.id=calls.reminder_id AND meeting.status='upcoming'
					AND (meeting.user_id=$2 OR attendee.response='accepted')
			))`, c.Param("id"), userID).Scan(&room,&conversationID,&kind,&status)
	if err != nil { c.JSON(http.StatusNotFound, gin.H{"error":"call not found"}); return }
	if status == "ended" || status == "declined" || status == "missed" { c.JSON(http.StatusConflict, gin.H{"error":"call is no longer active"}); return }
	_, _ = db.Exec(c.Request.Context(), `UPDATE call_participants SET joined_at=COALESCE(joined_at,NOW()),left_at=NULL WHERE call_id=$1 AND user_id=$2`, c.Param("id"), userID)
	_, _ = db.Exec(c.Request.Context(), `UPDATE calls SET status='answered',answered_at=COALESCE(answered_at,NOW()) WHERE id=$1 AND status='ringing'`, c.Param("id"))
	token, err := liveKitToken(room,conversationID,userID); if err != nil { c.JSON(http.StatusInternalServerError, gin.H{"error":"call token could not be created"}); return }
	syncCallNotification(c.Param("id"),"answered",userID)
	broadcastCallUpdate(c.Param("id"),"answered")
	c.JSON(http.StatusOK, gin.H{"id":c.Param("id"),"kind":kind,"status":"answered","url":os.Getenv("LIVEKIT_URL"),"token":token,"room":room})
}

func declineCall(c *gin.Context) {
	userID:=c.GetString("user_id")
	ctx:=c.Request.Context()
	tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"call could not be declined"});return};defer tx.Rollback(ctx)
	var conversationKind,callStatus string
	var alreadyJoined bool
	var availableParticipants int
	err=tx.QueryRow(ctx,`SELECT conversation.kind::text,active_call.status::text,mine.joined_at IS NOT NULL,
		(SELECT COUNT(*)::int FROM call_participants available WHERE available.call_id=active_call.id AND available.left_at IS NULL)
		FROM calls active_call
		JOIN conversations conversation ON conversation.id=active_call.conversation_id
		JOIN call_participants mine ON mine.call_id=active_call.id AND mine.user_id=$2 AND mine.left_at IS NULL
		WHERE active_call.id=$1 AND active_call.initiated_by<>$2
			AND (active_call.status='ringing' OR (active_call.status='answered' AND conversation.kind<>'direct'))
		FOR UPDATE OF active_call`,c.Param("id"),userID).Scan(&conversationKind,&callStatus,&alreadyJoined,&availableParticipants)
	if err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"active call invitation not found"});return}
	if !alreadyJoined{_,err=tx.Exec(ctx,`UPDATE call_participants SET left_at=COALESCE(left_at,NOW()) WHERE call_id=$1 AND user_id=$2`,c.Param("id"),userID)}
	endForEveryone:=callStatus=="ringing"&&(conversationKind=="direct"||availableParticipants<=2)
	if err==nil&&endForEveryone{_,err=tx.Exec(ctx,`UPDATE calls SET status='declined',ended_at=NOW() WHERE id=$1`,c.Param("id"))}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"call could not be declined"});return}
	if endForEveryone{syncCallNotification(c.Param("id"),"declined","");broadcastCallUpdate(c.Param("id"),"declined")}else if alreadyJoined{syncCallNotificationForUser(c.Param("id"),"answered",userID)}else{syncCallNotificationForUser(c.Param("id"),"declined",userID);broadcastCallUpdateToUser(userID,c.Param("id"),"declined")}
	c.JSON(http.StatusOK,gin.H{"id":c.Param("id"),"status":"declined","call_active":!endForEveryone})
}

func endCall(c *gin.Context) {
	userID := c.GetString("user_id")
	ctx:=c.Request.Context();tx,err:=db.Begin(ctx);if err!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"call could not be ended"});return};defer tx.Rollback(ctx)
	var initiatorID,status,conversationKind string
	err=tx.QueryRow(ctx,`SELECT calls.initiated_by::text,calls.status::text,conversations.kind::text FROM calls JOIN conversations ON conversations.id=calls.conversation_id WHERE calls.id=$1 AND calls.status IN ('ringing','answered') AND EXISTS(SELECT 1 FROM call_participants WHERE call_id=calls.id AND user_id=$2) FOR UPDATE OF calls`,c.Param("id"),userID).Scan(&initiatorID,&status,&conversationKind)
	if err!=nil{c.JSON(http.StatusNotFound,gin.H{"error":"active call not found"});return}
	_,err=tx.Exec(ctx,`UPDATE call_participants SET left_at=COALESCE(left_at,NOW()) WHERE call_id=$1 AND user_id=$2`,c.Param("id"),userID)
	var activeOthers int;if err==nil{err=tx.QueryRow(ctx,`SELECT COUNT(*) FROM call_participants WHERE call_id=$1 AND user_id<>$2 AND joined_at IS NOT NULL AND left_at IS NULL`,c.Param("id"),userID).Scan(&activeOthers)}
	ended:=initiatorID==userID||activeOthers==0||conversationKind=="direct"
	if err==nil&&ended{_,err=tx.Exec(ctx,`UPDATE calls SET status='ended',ended_at=NOW() WHERE id=$1`,c.Param("id"))}
	if err!=nil||tx.Commit(ctx)!=nil{c.JSON(http.StatusInternalServerError,gin.H{"error":"call could not be ended"});return}
	resultStatus:="left";if ended{resultStatus="ended";syncCallNotification(c.Param("id"),"ended","");broadcastCallUpdate(c.Param("id"),"ended")};c.JSON(http.StatusOK,gin.H{"id":c.Param("id"),"status":resultStatus,"ended_at":time.Now()})
}

func liveKitConfigured() bool { return os.Getenv("LIVEKIT_API_KEY") != "" && os.Getenv("LIVEKIT_API_SECRET") != "" && os.Getenv("LIVEKIT_URL") != "" }

func liveKitToken(room, conversationID, userID string) (string,error) {
	now := time.Now().Unix()
	name,_:=messageSenderIdentity(context.Background(),conversationID,userID)
	header := map[string]any{"alg":"HS256","typ":"JWT"}
	payload := map[string]any{"iss":os.Getenv("LIVEKIT_API_KEY"),"sub":userID,"name":name,"nbf":now-5,"exp":now+3600,"video":map[string]any{"roomJoin":true,"room":room,"canPublish":true,"canSubscribe":true}}
	return signJWT(header,payload,os.Getenv("LIVEKIT_API_SECRET"))
}

func signJWT(header,payload map[string]any,secret string)(string,error){
	headerJSON,err:=json.Marshal(header);if err!=nil{return "",err};payloadJSON,err:=json.Marshal(payload);if err!=nil{return "",err}
	encode:=base64.RawURLEncoding.EncodeToString;unsigned:=encode(headerJSON)+"."+encode(payloadJSON);mac:=hmac.New(sha256.New,[]byte(secret));_,_=mac.Write([]byte(unsigned));return unsigned+"."+encode(mac.Sum(nil)),nil
}
