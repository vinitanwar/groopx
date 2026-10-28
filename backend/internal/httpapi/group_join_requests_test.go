package httpapi

import "testing"

func TestGroupJoinNeedsApproval(t *testing.T) {
	tests := []struct {
		name          string
		kind          string
		required      bool
		alreadyMember bool
		want          bool
	}{
		{name: "approval enabled for new group member", kind: "group", required: true, want: true},
		{name: "approval disabled", kind: "group", required: false, want: false},
		{name: "existing member remains idempotent", kind: "group", required: true, alreadyMember: true, want: false},
		{name: "community invite remains immediate", kind: "community", required: true, want: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := groupJoinNeedsApproval(test.kind, test.required, test.alreadyMember); got != test.want {
				t.Fatalf("groupJoinNeedsApproval() = %v, want %v", got, test.want)
			}
		})
	}
}
