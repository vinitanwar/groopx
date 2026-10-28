package httpapi

import "testing"

func TestNormalizeCommunityDetails(t *testing.T) {
	tests := []struct {
		name, description, wantName, wantDescription string
		wantError                                bool
	}{
		{name: "  Building   Residents  ", description: "  Notices   and events ", wantName: "Building Residents", wantDescription: "Notices and events"},
		{name: "Residents", description: "Notices\nand events", wantName: "Residents", wantDescription: "Notices and events"},
		{name: "A", wantError: true},
		{name: "Valid\nname", wantError: true},
	}
	for _, test := range tests {
		gotName, gotDescription, err := normalizeCommunityDetails(test.name, test.description)
		if (err != nil) != test.wantError {
			t.Fatalf("normalizeCommunityDetails(%q) error = %v, wantError %v", test.name, err, test.wantError)
		}
		if !test.wantError && (gotName != test.wantName || gotDescription != test.wantDescription) {
			t.Fatalf("normalizeCommunityDetails() = (%q, %q), want (%q, %q)", gotName, gotDescription, test.wantName, test.wantDescription)
		}
	}
}
