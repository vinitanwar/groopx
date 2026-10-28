package httpapi

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

var pushClient *messaging.Client

func initializePush() {
	ctx := context.Background()
	options := make([]option.ClientOption, 0, 1)
	source := "GOOGLE_APPLICATION_CREDENTIALS"
	if raw := strings.TrimSpace(os.Getenv("FIREBASE_SERVICE_ACCOUNT_JSON")); raw != "" {
		options = append(options, option.WithCredentialsJSON([]byte(raw)))
		source = "FIREBASE_SERVICE_ACCOUNT_JSON"
	} else if encoded := strings.TrimSpace(os.Getenv("FIREBASE_SERVICE_ACCOUNT_BASE64")); encoded != "" {
		credentials, err := base64.StdEncoding.DecodeString(encoded)
		if err != nil {
			log.Print("FCM disabled: FIREBASE_SERVICE_ACCOUNT_BASE64 is invalid")
			return
		}
		options = append(options, option.WithCredentialsJSON(credentials))
		source = "FIREBASE_SERVICE_ACCOUNT_BASE64"
	} else if strings.TrimSpace(os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")) == "" {
		log.Print("FCM disabled: configure FIREBASE_SERVICE_ACCOUNT_JSON, FIREBASE_SERVICE_ACCOUNT_BASE64, or GOOGLE_APPLICATION_CREDENTIALS")
		return
	}
	app, err := firebase.NewApp(ctx, nil, options...)
	if err != nil {
		log.Printf("FCM disabled: %v", err)
		return
	}
	pushClient, err = app.Messaging(ctx)
	if err != nil {
		log.Printf("FCM disabled: %v", err)
		pushClient = nil
		return
	}
	log.Printf("FCM enabled using %s", source)
}

func androidPushConfig(kind string, data map[string]any) *messaging.AndroidConfig {
	channelID, tag := "groopx_messages", ""
	ttl := 24 * time.Hour
	priority := messaging.PriorityDefault
	switch kind {
	case "call":
		channelID = "groopx_calls"
		ttl = 90 * time.Second
		priority = messaging.PriorityMax
		tag = pushTag("call", data["call_id"])
	case "reminder":
		channelID = "groopx_reminders"
		priority = messaging.PriorityHigh
		tag = pushTag("reminder", data["reminder_id"])
	case "announcement":
		channelID = "groopx_updates"
		tag = "groopx-announcement"
	default:
		tag = pushTag("chat", data["conversation_id"])
	}
	return &messaging.AndroidConfig{
		Priority: "high",
		TTL:      &ttl,
		Notification: &messaging.AndroidNotification{
			ChannelID:             channelID,
			Sound:                 "default",
			Tag:                   tag,
			ClickAction:           "FLUTTER_NOTIFICATION_CLICK",
			Priority:              priority,
			DefaultVibrateTimings: true,
		},
	}
}

func pushTag(prefix string, value any) string {
	text := strings.TrimSpace(fmt.Sprint(value))
	if text == "" || text == "<nil>" {
		return ""
	}
	return prefix + "-" + text
}

func sendConversationPush(conversationID, senderID, kind, title, body string, data map[string]any) {
	if pushClient == nil { return }
	rows, err := db.Query(context.Background(), `SELECT d.push_token FROM user_devices d JOIN conversation_members m ON m.user_id=d.user_id JOIN users u ON u.id=d.user_id
		WHERE m.conversation_id=$1 AND m.user_id<>$2 AND m.hidden_at IS NULL AND (m.muted_until IS NULL OR m.muted_until<=NOW())
		AND u.push_notifications=TRUE AND (CASE WHEN $3='call' THEN u.call_notifications ELSE u.message_notifications END)=TRUE`, conversationID, senderID, kind)
	if err != nil { return }
	tokens := make([]string, 0)
	for rows.Next() { var token string; if rows.Scan(&token) == nil { tokens = append(tokens, token) } }
	rows.Close()
	sendPushTokens(tokens, kind, title, body, data)
}

func sendConversationMentionPush(conversationID, senderID, body string, regularData, mentionedData map[string]any, mentionUserIDs []string) {
	if pushClient == nil || len(mentionUserIDs) == 0 { return }
	mentionedUsers := make(map[string]bool, len(mentionUserIDs))
	for _, userID := range mentionUserIDs { mentionedUsers[userID] = true }
	rows, err := db.Query(context.Background(), `SELECT d.push_token,m.user_id::text FROM user_devices d JOIN conversation_members m ON m.user_id=d.user_id JOIN users u ON u.id=d.user_id
		WHERE m.conversation_id=$1 AND m.user_id<>$2 AND m.hidden_at IS NULL AND (m.muted_until IS NULL OR m.muted_until<=NOW())
		AND u.push_notifications=TRUE AND u.message_notifications=TRUE`, conversationID, senderID)
	if err != nil { return }
	regularTokens, mentionedTokens := make([]string, 0), make([]string, 0)
	for rows.Next() {
		var token, userID string
		if rows.Scan(&token, &userID) != nil { continue }
		if mentionedUsers[userID] { mentionedTokens = append(mentionedTokens, token) } else { regularTokens = append(regularTokens, token) }
	}
	rows.Close()
	sendPushTokens(regularTokens, "message", "New message", body, regularData)
	sendPushTokens(mentionedTokens, "mention", "You were mentioned", body, mentionedData)
}

func sendPushTokens(tokens []string, kind, title, body string, data map[string]any) {
	if pushClient == nil || len(tokens) == 0 { return }
	stringData := make(map[string]string, len(data))
	for key, value := range data { stringData[key] = fmt.Sprint(value) }
	stringData["type"] = kind
	for start := 0; start < len(tokens); start += 500 {
		end := start + 500; if end > len(tokens) { end = len(tokens) }
		batchTokens := tokens[start:end]
		response, err := pushClient.SendEachForMulticast(context.Background(), &messaging.MulticastMessage{
			Tokens: batchTokens,
			Notification: &messaging.Notification{Title:title,Body:body},
			Data: stringData,
			Android: androidPushConfig(kind,data),
			APNS: &messaging.APNSConfig{Payload:&messaging.APNSPayload{Aps:&messaging.Aps{Sound:"default"}}},
		})
		if err != nil { continue }
		for index, result := range response.Responses { if result.Error != nil && messaging.IsUnregistered(result.Error) { _, _ = db.Exec(context.Background(), `DELETE FROM user_devices WHERE push_token=$1`, batchTokens[index]) } }
	}
}

func sendPushToUsers(userIDs []string, kind, title, body string, data map[string]any) {
	if pushClient == nil || len(userIDs) == 0 { return }
	rows, err := db.Query(context.Background(), `SELECT device.push_token FROM user_devices device
		JOIN users recipient ON recipient.id=device.user_id
		WHERE device.user_id::text=ANY($1::text[]) AND recipient.account_status='active' AND recipient.push_notifications=TRUE`, userIDs)
	if err != nil { return }
	tokens := make([]string, 0)
	for rows.Next() { var token string; if rows.Scan(&token) == nil { tokens = append(tokens, token) } }
	rows.Close()
	sendPushTokens(tokens, kind, title, body, data)
}

func sendCallPush(callID, senderID, title, body string, data map[string]any) {
	if pushClient == nil { return }
	rows, err := db.Query(context.Background(), `SELECT device.push_token
		FROM user_devices device
		JOIN call_participants participant ON participant.user_id=device.user_id
		JOIN calls active_call ON active_call.id=participant.call_id
		JOIN users recipient ON recipient.id=participant.user_id
		LEFT JOIN conversation_members member ON member.conversation_id=active_call.conversation_id AND member.user_id=participant.user_id
		WHERE participant.call_id=$1 AND participant.user_id<>$2
			AND recipient.account_status='active' AND recipient.push_notifications=TRUE AND recipient.call_notifications=TRUE
			AND member.hidden_at IS NULL AND (member.muted_until IS NULL OR member.muted_until<=NOW())`, callID, senderID)
	if err != nil { return }
	tokens := make([]string, 0)
	for rows.Next() { var token string; if rows.Scan(&token) == nil { tokens = append(tokens, token) } }
	rows.Close()
	stringData := make(map[string]string, len(data)+1)
	for key, value := range data { stringData[key] = fmt.Sprint(value) }
	stringData["type"] = "call"
	for start:=0; start<len(tokens); start+=500 {
		end:=start+500; if end>len(tokens){end=len(tokens)}
		batch:=tokens[start:end]
		response, sendErr := pushClient.SendEachForMulticast(context.Background(), &messaging.MulticastMessage{
			Tokens:batch,
			Notification:&messaging.Notification{Title:title,Body:body},
			Data:stringData,
			Android:androidPushConfig("call",data),
			APNS:&messaging.APNSConfig{Payload:&messaging.APNSPayload{Aps:&messaging.Aps{Sound:"default"}}},
		})
		if sendErr!=nil{continue}
		for index,result:=range response.Responses{if result.Error!=nil&&messaging.IsUnregistered(result.Error){_,_=db.Exec(context.Background(),`DELETE FROM user_devices WHERE push_token=$1`,batch[index])}}
	}
}

func sendAdminPush(title,body,audience string){if pushClient==nil{return};query:=`SELECT d.push_token FROM user_devices d JOIN users u ON u.id=d.user_id WHERE u.account_status<>'deleted' AND u.push_notifications=TRUE`;if audience=="active"{query+=` AND u.account_status='active'`};rows,err:=db.Query(context.Background(),query);if err!=nil{return};defer rows.Close();tokens:=make([]string,0);for rows.Next(){var token string;if rows.Scan(&token)==nil{tokens=append(tokens,token)}};for start:=0;start<len(tokens);start+=500{end:=start+500;if end>len(tokens){end=len(tokens)};batch:=tokens[start:end];response,err:=pushClient.SendEachForMulticast(context.Background(),&messaging.MulticastMessage{Tokens:batch,Notification:&messaging.Notification{Title:title,Body:body},Data:map[string]string{"type":"announcement"},Android:androidPushConfig("announcement",nil),APNS:&messaging.APNSConfig{Payload:&messaging.APNSPayload{Aps:&messaging.Aps{Sound:"default"}}}});if err!=nil{continue};for index,result:=range response.Responses{if result.Error!=nil&&messaging.IsUnregistered(result.Error){_,_=db.Exec(context.Background(),`DELETE FROM user_devices WHERE push_token=$1`,batch[index])}}}}

func sendReminderPush(userID, reminderID, title, body, itemType, conversationID, callKind string) {
	if pushClient == nil { return }
	rows, err := db.Query(context.Background(), `SELECT d.push_token FROM user_devices d JOIN users u ON u.id=d.user_id
		WHERE d.user_id=$1 AND u.account_status='active' AND u.push_notifications=TRUE AND u.reminder_notifications=TRUE`, userID)
	if err != nil { return }
	defer rows.Close()
	tokens := make([]string, 0)
	for rows.Next() { var token string; if rows.Scan(&token) == nil { tokens = append(tokens, token) } }
	for start := 0; start < len(tokens); start += 500 {
		end := start + 500; if end > len(tokens) { end = len(tokens) }
		batch := tokens[start:end]
		data := map[string]string{"type":"reminder", "reminder_id":reminderID, "item_type":itemType}
		if conversationID != "" { data["conversation_id"] = conversationID }
		if callKind != "" { data["call_kind"] = callKind }
		if itemType == "meeting" { data["meeting_title"] = title }
		response, err := pushClient.SendEachForMulticast(context.Background(), &messaging.MulticastMessage{
			Tokens: batch,
			Notification: &messaging.Notification{Title:title, Body:body},
			Data: data,
			Android: androidPushConfig("reminder",map[string]any{"reminder_id":reminderID}),
			APNS: &messaging.APNSConfig{Payload:&messaging.APNSPayload{Aps:&messaging.Aps{Sound:"default"}}},
		})
		if err != nil { continue }
		for index, result := range response.Responses { if result.Error != nil && messaging.IsUnregistered(result.Error) { _, _ = db.Exec(context.Background(), `DELETE FROM user_devices WHERE push_token=$1`, batch[index]) } }
	}
}

func sendMeetingEventPush(userID, eventType, reminderID, title, body, conversationID, callKind string) {
	if pushClient == nil { return }
	rows, err := db.Query(context.Background(), `SELECT d.push_token FROM user_devices d JOIN users u ON u.id=d.user_id
		WHERE d.user_id=$1 AND u.account_status='active' AND u.push_notifications=TRUE AND u.reminder_notifications=TRUE`, userID)
	if err != nil { return }
	defer rows.Close()
	tokens := make([]string, 0)
	for rows.Next() { var token string; if rows.Scan(&token) == nil { tokens = append(tokens, token) } }
	for start := 0; start < len(tokens); start += 500 {
		end := start + 500; if end > len(tokens) { end = len(tokens) }
		batch := tokens[start:end]
		data := map[string]string{"type":eventType, "reminder_id":reminderID, "item_type":"meeting"}
		if conversationID != "" { data["conversation_id"] = conversationID }
		if callKind != "" { data["call_kind"] = callKind }
		response, err := pushClient.SendEachForMulticast(context.Background(), &messaging.MulticastMessage{
			Tokens: batch,
			Notification: &messaging.Notification{Title:title, Body:body},
			Data: data,
			Android: androidPushConfig("reminder",map[string]any{"reminder_id":reminderID}),
			APNS: &messaging.APNSConfig{Payload:&messaging.APNSPayload{Aps:&messaging.Aps{Sound:"default"}}},
		})
		if err != nil { continue }
		for index, result := range response.Responses { if result.Error != nil && messaging.IsUnregistered(result.Error) { _, _ = db.Exec(context.Background(), `DELETE FROM user_devices WHERE push_token=$1`, batch[index]) } }
	}
}
