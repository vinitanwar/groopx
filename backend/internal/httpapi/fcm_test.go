package httpapi

import (
	"encoding/xml"
	"os"
	"testing"

	"firebase.google.com/go/v4/messaging"
)

// The server's click action must resolve to the Flutter activity on Android.
func TestPushClickActionMatchesAndroidActivity(t *testing.T) {
	contents, err := os.ReadFile("../../../mobile/android/app/src/main/AndroidManifest.xml")
	if err != nil {
		t.Fatal(err)
	}
	var manifest struct {
		Application struct {
			Activities []struct {
				Name    string `xml:"name,attr"`
				Filters []struct {
					Actions []struct {
						Name string `xml:"name,attr"`
					} `xml:"action"`
					Categories []struct {
						Name string `xml:"name,attr"`
					} `xml:"category"`
				} `xml:"intent-filter"`
			} `xml:"activity"`
		} `xml:"application"`
	}
	if err := xml.Unmarshal(contents, &manifest); err != nil {
		t.Fatal(err)
	}
	action := androidPushConfig("message", nil).Notification.ClickAction
	for _, activity := range manifest.Application.Activities {
		if activity.Name != ".MainActivity" {
			continue
		}
		for _, filter := range activity.Filters {
			hasAction, hasDefault := false, false
			for _, a := range filter.Actions {
				hasAction = hasAction || a.Name == action
			}
			for _, c := range filter.Categories {
				hasDefault = hasDefault || c.Name == "android.intent.category.DEFAULT"
			}
			if hasAction && hasDefault {
				return
			}
		}
	}
	t.Fatalf("MainActivity cannot resolve push click action %q", action)
}

func TestChatPushPriority(t *testing.T) {
	for _, kind := range []string{"message", "mention"} {
		config := androidPushConfig(kind, map[string]any{"conversation_id": "chat-123"})
		if config.Priority != "high" || config.Notification.Priority != messaging.PriorityHigh {
			t.Errorf("%s must use high delivery and notification priority", kind)
		}
	}
}

func TestActionablePushIsDataOnlyAndAccountBound(t *testing.T) {
	original := map[string]string{"type": "message", "conversation_id": "conversation", "message_id": "message"}
	message := actionableChatMessage("token", "recipient", "message", "Sender", "Hello", original)
	if message.Notification != nil || message.Android.Notification != nil {
		t.Fatal("actionable Android messages must not be rendered twice by FCM and Flutter")
	}
	if message.Data["recipient_id"] != "recipient" || message.Data["notification_reply"] != "1" {
		t.Fatal("reply payload must be bound to its recipient")
	}
	if _, mutated := original["recipient_id"]; mutated {
		t.Fatal("recipient leaked into shared payload")
	}
}

func TestPushPreviewTruncationPreservesUnicode(t *testing.T) {
	input := ""
	for i := 0; i < 600; i++ {
		input += "🙂"
	}
	output := truncatePushPreview(input)
	if len([]rune(output)) != 501 {
		t.Fatal("preview must cap Unicode characters and append ellipsis")
	}
}
