package httpapi

import "testing"

func TestGroupAllowsSender(t *testing.T) {
	tests := []struct {
		name             string
		kind             string
		announcementOnly bool
		role             string
		want             bool
	}{
		{name: "direct chat", kind: "direct", announcementOnly: true, role: "member", want: true},
		{name: "regular group member", kind: "group", announcementOnly: false, role: "member", want: true},
		{name: "announcement group admin", kind: "group", announcementOnly: true, role: "admin", want: true},
		{name: "announcement group member", kind: "group", announcementOnly: true, role: "member", want: false},
		{name: "community unchanged", kind: "community", announcementOnly: true, role: "member", want: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := groupAllowsSender(test.kind, test.announcementOnly, test.role); got != test.want {
				t.Fatalf("groupAllowsSender() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestGroupManagementPermissions(t *testing.T) {
	tests := []struct {
		name       string
		role       string
		permission bool
		edit       bool
		add        bool
	}{
		{name: "admin keeps both capabilities", role: "admin", edit: true, add: true},
		{name: "member permissions disabled", role: "member"},
		{name: "member permissions enabled", role: "member", permission: true, edit: true, add: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := groupCanEditInfo(test.role, test.permission); got != test.edit {
				t.Fatalf("groupCanEditInfo() = %v, want %v", got, test.edit)
			}
			if got := groupCanAddMembers(test.role, test.permission); got != test.add {
				t.Fatalf("groupCanAddMembers() = %v, want %v", got, test.add)
			}
		})
	}
}
