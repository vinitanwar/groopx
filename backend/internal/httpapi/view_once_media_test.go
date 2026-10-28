package httpapi

import (
	"strconv"
	"testing"
	"time"
)

func TestViewOnceSignatureIsBoundToViewerAndMessage(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	expires := now.Add(viewOnceAccessTTL).Unix()
	signature := viewOnceSignature("test-secret", "message-a", "user-a", expires)
	if validViewOnceAccess("message-a", "user-a", "not-a-timestamp", signature, "test-secret", now) {
		t.Fatal("non-Unix expiry should be rejected")
	}
	expiresRaw := strconv.FormatInt(expires, 10)
	if !validViewOnceAccess("message-a", "user-a", expiresRaw, signature, "test-secret", now) {
		t.Fatal("valid signed access should be accepted")
	}
	if validViewOnceAccess("message-b", "user-a", expiresRaw, signature, "test-secret", now) {
		t.Fatal("signature must not work for another message")
	}
	if validViewOnceAccess("message-a", "user-b", expiresRaw, signature, "test-secret", now) {
		t.Fatal("signature must not work for another viewer")
	}
	if validViewOnceAccess("message-a", "user-a", expiresRaw, signature, "wrong-secret", now) {
		t.Fatal("signature must not work with another secret")
	}
}

func TestProtectViewOnceAttachmentRemovesDirectMediaAccess(t *testing.T) {
	protected := protectViewOnceAttachment(map[string]any{
		"url":        "https://example.test/original.jpg",
		"object_key": "uploads/private.jpg",
		"file_name":  "photo.jpg",
	}, false, false, 2, 4)
	if protected["url"] != nil || protected["object_key"] != nil {
		t.Fatal("protected attachment must not expose direct media access")
	}
	if protected["view_once"] != true || protected["available"] != true || protected["opened"] != false {
		t.Fatalf("unexpected protected state: %#v", protected)
	}
	if protected["opened_count"] != 2 || protected["recipient_count"] != 4 {
		t.Fatalf("unexpected open counts: %#v", protected)
	}
}
