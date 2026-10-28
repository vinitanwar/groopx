package httpapi

import "testing"

func TestMentionHandleUsesUsernameOrStableMemberSuffix(t *testing.T) {
	if handle := mentionHandle("11111111-2222-3333-4444-555555555555", "Pooja Sharma", "pooja"); handle != "pooja" {
		t.Fatalf("username handle = %q", handle)
	}
	if handle := mentionHandle("abcdef12-2222-3333-4444-555555555555", "Pooja Sharma", ""); handle != "Pooja_Sharma_abcd" {
		t.Fatalf("name handle = %q", handle)
	}
}

func TestTextContainsMentionRequiresTokenBoundary(t *testing.T) {
	for _, value := range []string{"@pooja hello", "Hello (@pooja), are you free?", "Hi @POOJA!"} {
		if !textContainsMention(value, "pooja") {
			t.Fatalf("expected mention in %q", value)
		}
	}
	for _, value := range []string{"mail@pooja.com", "@pooja_extra", "plain text"} {
		if textContainsMention(value, "pooja") {
			t.Fatalf("unexpected mention in %q", value)
		}
	}
}

func TestPayloadMentionsOnlySelectedRecipient(t *testing.T) {
	values := []string{"user-a", "user-b"}
	if !payloadMentionsUser(values, "user-b") || payloadMentionsUser(values, "user-c") {
		t.Fatal("recipient mention lookup is incorrect")
	}
}
