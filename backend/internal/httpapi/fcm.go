package httpapi

import (
	"context"
	"fmt"
	"log"
	"os"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
)

var pushClient *messaging.Client

func initializePush() {
	if os.Getenv("GOOGLE_APPLICATION_CREDENTIALS") == "" { log.Print("FCM disabled: GOOGLE_APPLICATION_CREDENTIALS is not set"); return }
	app, err := firebase.NewApp(context.Background(), nil)
	if err != nil { log.Printf("FCM disabled: %v", err); return }
	pushClient, err = app.Messaging(context.Background())
	if err != nil { log.Printf("FCM disabled: %v", err); pushClient = nil }
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
	stringData := make(map[string]string, len(data))
	for key, value := range data { stringData[key] = fmt.Sprint(value) }
	for start := 0; start < len(tokens); start += 500 {
		end := start + 500; if end > len(tokens) { end = len(tokens) }
		batchTokens := tokens[start:end]
		response, err := pushClient.SendEachForMulticast(context.Background(), &messaging.MulticastMessage{
			Tokens: batchTokens,
			Notification: &messaging.Notification{Title:title,Body:body},
			Data: stringData,
			Android: &messaging.AndroidConfig{Priority:"high"},
			APNS: &messaging.APNSConfig{Payload:&messaging.APNSPayload{Aps:&messaging.Aps{Sound:"default"}}},
		})
		if err != nil { continue }
		for index, result := range response.Responses { if result.Error != nil && messaging.IsUnregistered(result.Error) { _, _ = db.Exec(context.Background(), `DELETE FROM user_devices WHERE push_token=$1`, batchTokens[index]) } }
	}
}

func sendAdminPush(title,body,audience string){if pushClient==nil{return};query:=`SELECT d.push_token FROM user_devices d JOIN users u ON u.id=d.user_id WHERE u.account_status<>'deleted' AND u.push_notifications=TRUE`;if audience=="active"{query+=` AND u.account_status='active'`};rows,err:=db.Query(context.Background(),query);if err!=nil{return};defer rows.Close();tokens:=make([]string,0);for rows.Next(){var token string;if rows.Scan(&token)==nil{tokens=append(tokens,token)}};for start:=0;start<len(tokens);start+=500{end:=start+500;if end>len(tokens){end=len(tokens)};batch:=tokens[start:end];response,err:=pushClient.SendEachForMulticast(context.Background(),&messaging.MulticastMessage{Tokens:batch,Notification:&messaging.Notification{Title:title,Body:body},Data:map[string]string{"type":"announcement"},Android:&messaging.AndroidConfig{Priority:"high"},APNS:&messaging.APNSConfig{Payload:&messaging.APNSPayload{Aps:&messaging.Aps{Sound:"default"}}}});if err!=nil{continue};for index,result:=range response.Responses{if result.Error!=nil&&messaging.IsUnregistered(result.Error){_,_=db.Exec(context.Background(),`DELETE FROM user_devices WHERE push_token=$1`,batch[index])}}}}
