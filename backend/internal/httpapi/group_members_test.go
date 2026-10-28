package httpapi

import "testing"

func TestNormalizeGroupMemberListQuery(t *testing.T) {
	tests := []struct {
		name                 string
		search, role         string
		limit, offset        string
		wantSearch, wantRole string
		wantLimit, wantOffset int
		wantError            bool
	}{
		{name: "defaults", wantLimit: 20},
		{name: "trim search and all role", search: "  @Pooja  ", role: "ALL", wantSearch: "Pooja", wantLimit: 20},
		{name: "admin page", role: "admin", limit: "50", offset: "100", wantRole: "admin", wantLimit: 50, wantOffset: 100},
		{name: "invalid role", role: "owner", wantError: true},
		{name: "invalid limit", limit: "51", wantError: true},
		{name: "invalid offset", offset: "-1", wantError: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := normalizeGroupMemberListQuery(test.search, test.role, test.limit, test.offset)
			if (err != nil) != test.wantError {
				t.Fatalf("normalizeGroupMemberListQuery() error = %v, wantError %v", err, test.wantError)
			}
			if test.wantError {
				return
			}
			if got.search != test.wantSearch || got.role != test.wantRole || got.limit != test.wantLimit || got.offset != test.wantOffset {
				t.Fatalf("normalizeGroupMemberListQuery() = %#v", got)
			}
		})
	}
}

func TestNormalizeGroupMemberDisplayName(t *testing.T) {
	tests := []struct {
		name, value, want string
		wantError         bool
	}{
		{name: "reset", value: "  ", want: ""},
		{name: "trim and collapse", value: "  Pooja   Sharma  ", want: "Pooja Sharma"},
		{name: "unicode", value: "माँ", want: "माँ"},
		{name: "too short", value: "A", wantError: true},
		{name: "control character", value: "Pooja\nSharma", wantError: true},
		{name: "format character", value: "Pooja\u202e", wantError: true},
		{name: "too long", value: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", wantError: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := normalizeGroupMemberDisplayName(test.value)
			if (err != nil) != test.wantError {
				t.Fatalf("normalizeGroupMemberDisplayName() error = %v, wantError %v", err, test.wantError)
			}
			if !test.wantError && got != test.want {
				t.Fatalf("normalizeGroupMemberDisplayName() = %q, want %q", got, test.want)
			}
		})
	}
}

func TestEffectiveGroupMemberName(t *testing.T) {
	if got := effectiveGroupMemberName("Maa", "Pooja"); got != "Maa" {
		t.Fatalf("effectiveGroupMemberName() = %q, want Maa", got)
	}
	if got := effectiveGroupMemberName("", "Pooja"); got != "Pooja" {
		t.Fatalf("effectiveGroupMemberName() reset = %q, want Pooja", got)
	}
}
