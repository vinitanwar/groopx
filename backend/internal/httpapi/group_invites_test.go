package httpapi

import (
	"testing"
	"time"
)

func TestGroupInviteStatus(t *testing.T) {
	now := time.Date(2026, time.October, 25, 12, 0, 0, 0, time.UTC)
	revokedAt := now.Add(-time.Hour)
	tests := []struct {
		name      string
		expiresAt time.Time
		revokedAt *time.Time
		useCount  int
		maxUses   int
		want      string
	}{
		{name: "active", expiresAt: now.Add(time.Hour), useCount: 2, maxUses: 10, want: "active"},
		{name: "revoked takes precedence", expiresAt: now.Add(time.Hour), revokedAt: &revokedAt, maxUses: 10, want: "revoked"},
		{name: "expired", expiresAt: now, maxUses: 10, want: "expired"},
		{name: "usage exhausted", expiresAt: now.Add(time.Hour), useCount: 10, maxUses: 10, want: "exhausted"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := groupInviteStatus(now, test.expiresAt, test.revokedAt, test.useCount, test.maxUses); got != test.want {
				t.Fatalf("groupInviteStatus() = %q, want %q", got, test.want)
			}
		})
	}
}
