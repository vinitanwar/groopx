package httpapi

import (
	"strings"
	"testing"
)

func TestNormalizeStatusPrivacyInput(t *testing.T) {
	firstID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	secondID := "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
	audience, selected, err := normalizeStatusPrivacyInput("  CONTACTS_EXCEPT ", []string{strings.ToUpper(firstID), firstID, secondID})
	if err != nil {
		t.Fatalf("normalizeStatusPrivacyInput() error = %v", err)
	}
	if audience != "contacts_except" || len(selected) != 2 || selected[0] != firstID || selected[1] != secondID {
		t.Fatalf("normalizeStatusPrivacyInput() = %q, %#v", audience, selected)
	}

	audience, selected, err = normalizeStatusPrivacyInput("contacts", []string{"ignored"})
	if err != nil || audience != "contacts" || len(selected) != 0 {
		t.Fatalf("contacts audience = %q, %#v, %v", audience, selected, err)
	}
}

func TestNormalizeStatusPrivacyInputRejectsInvalidValues(t *testing.T) {
	validID := "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
	tests := []struct {
		name     string
		audience string
		userIDs  []string
	}{
		{name: "invalid audience", audience: "everyone"},
		{name: "invalid contact", audience: "contacts_except", userIDs: []string{"not-a-user"}},
		{name: "empty contact", audience: "only_share_with", userIDs: []string{""}},
		{name: "too many contacts", audience: "only_share_with", userIDs: make([]string, maximumStatusPrivacyContacts+1)},
	}
	for index := range tests[3].userIDs {
		tests[3].userIDs[index] = validID
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, _, err := normalizeStatusPrivacyInput(test.audience, test.userIDs); err == nil {
				t.Fatal("privacy input should be rejected")
			}
		})
	}
}

func TestValidStatusPrivacyUserID(t *testing.T) {
	if !validStatusPrivacyUserID("01234567-89ab-4def-8abc-0123456789ab") {
		t.Fatal("valid UUID was rejected")
	}
	for _, value := range []string{"", "01234567-89ab-4def-8abc-0123456789ag", "0123456789ab-4def-8abc-0123456789ab"} {
		if validStatusPrivacyUserID(value) {
			t.Fatalf("invalid UUID %q was accepted", value)
		}
	}
}

func TestUniqueStatusShareConversationIDs(t *testing.T) {
	values := []string{"chat-1", "chat-2", "chat-1", "chat-3", "chat-4", "chat-5", "chat-6"}
	unique := uniqueStatusShareConversationIDs(values)
	want := []string{"chat-1", "chat-2", "chat-3", "chat-4", "chat-5"}
	if len(unique) != len(want) {
		t.Fatalf("uniqueStatusShareConversationIDs() length = %d, want %d", len(unique), len(want))
	}
	for index := range want {
		if unique[index] != want[index] {
			t.Fatalf("uniqueStatusShareConversationIDs()[%d] = %q, want %q", index, unique[index], want[index])
		}
	}
}

func TestNormalizeStatusReplyText(t *testing.T) {
	value, err := normalizeStatusReplyText("  Great update!  ")
	if err != nil || value != "Great update!" {
		t.Fatalf("normalizeStatusReplyText() = %q, %v", value, err)
	}
	if _, err = normalizeStatusReplyText("   "); err == nil {
		t.Fatal("empty status reply should be rejected")
	}
	if _, err = normalizeStatusReplyText(strings.Repeat("a", 1001)); err == nil {
		t.Fatal("oversized status reply should be rejected")
	}
	if _, err = normalizeStatusReplyText(strings.Repeat("🙂", 1000)); err != nil {
		t.Fatalf("1000 Unicode characters should be accepted: %v", err)
	}
}

func TestNormalizeStatusReaction(t *testing.T) {
	for _, emoji := range []string{"❤️", "😂", "😮", "😢", "🙏", "👏"} {
		value, err := normalizeStatusReaction("  " + emoji + "  ")
		if err != nil || value != emoji {
			t.Fatalf("normalizeStatusReaction(%q) = %q, %v", emoji, value, err)
		}
	}
	value, err := normalizeStatusReaction("❤")
	if err != nil || value != "❤️" {
		t.Fatalf("plain heart reaction = %q, %v", value, err)
	}
	for _, value := range []string{"", "👍", "hello", "❤️❤️"} {
		if _, err := normalizeStatusReaction(value); err == nil {
			t.Fatalf("unsupported reaction %q should be rejected", value)
		}
	}
}

func TestNormalizeTextStatus(t *testing.T) {
	text, color, err := normalizeTextStatus("  Launch update 🚀  ", " #e91e63 ")
	if err != nil || text != "Launch update 🚀" || color != "#E91E63" {
		t.Fatalf("normalizeTextStatus() = %q, %q, %v", text, color, err)
	}
	_, color, err = normalizeTextStatus("Hello", "")
	if err != nil || color != "#6335FF" {
		t.Fatalf("default background = %q, %v", color, err)
	}
	if _, _, err = normalizeTextStatus(strings.Repeat("🙂", 700), "#2E7D32"); err != nil {
		t.Fatalf("700 Unicode characters should be accepted: %v", err)
	}
}

func TestNormalizeTextStatusRejectsInvalidValues(t *testing.T) {
	for _, test := range []struct {
		name  string
		text  string
		color string
	}{
		{name: "empty text", text: "   ", color: "#6335FF"},
		{name: "long text", text: strings.Repeat("a", 701), color: "#6335FF"},
		{name: "unknown color", text: "Hello", color: "#FFFFFF"},
	} {
		t.Run(test.name, func(t *testing.T) {
			if _, _, err := normalizeTextStatus(test.text, test.color); err == nil {
				t.Fatal("text status should be rejected")
			}
		})
	}
}
