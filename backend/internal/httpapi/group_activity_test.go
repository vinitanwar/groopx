package httpapi

import "testing"

func TestGroupActivityText(t *testing.T) {
	tests := []struct {
		event, actor, target, detail, want string
	}{
		{event: "group_created", actor: "Vinod", want: "Vinod created this group"},
		{event: "group_renamed", actor: "Vinod", detail: "Family", want: "Vinod changed the group name to “Family”"},
		{event: "group_permissions_updated", actor: "Vinod", want: "Vinod updated group permissions"},
		{event: "member_added", actor: "Vinod", target: "Pooja", want: "Vinod added Pooja"},
		{event: "member_joined", actor: "Pooja", want: "Pooja joined using an invite link"},
		{event: "admin_granted", actor: "Vinod", target: "Pooja", want: "Vinod made Pooja a group admin"},
		{event: "member_display_name_updated", actor: "Vinod", target: "Pooja", detail: "Maa", want: "Vinod changed Pooja's group name to “Maa”"},
		{event: "member_display_name_reset", actor: "Vinod", target: "Pooja", want: "Vinod reset Pooja's group name"},
		{event: "member_left", actor: "Pooja", want: "Pooja left the group"},
		{event: "community_created", actor: "Vinod", want: "Vinod created this community"},
		{event: "community_renamed", actor: "Vinod", detail: "Neighbours", want: "Vinod changed the community name to “Neighbours”"},
		{event: "community_group_added", actor: "Vinod", target: "Building A", want: "Vinod linked Building A to this community"},
		{event: "community_admin_granted", actor: "Vinod", target: "Pooja", want: "Vinod made Pooja a community admin"},
		{event: "community_member_display_name_updated", actor: "Vinod", target: "Pooja", detail: "Treasurer", want: "Vinod changed Pooja's community name to “Treasurer”"},
		{event: "community_member_left", actor: "Pooja", want: "Pooja left the community"},
	}
	for _, test := range tests {
		t.Run(test.event, func(t *testing.T) {
			if got := groupActivityText(test.event, test.actor, test.target, test.detail); got != test.want {
				t.Fatalf("groupActivityText() = %q, want %q", got, test.want)
			}
		})
	}
}
