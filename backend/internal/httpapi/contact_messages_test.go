package httpapi

import "testing"

func TestNormalizeSharedContact(t *testing.T) {
	name, phone, valid := normalizeSharedContact("  Pooja   Sharma  ", "+91 70564-07000")
	if !valid || name != "Pooja Sharma" || phone != "+917056407000" {
		t.Fatalf("normalized contact = %q, %q, %v", name, phone, valid)
	}
	name, phone, valid = normalizeSharedContact("Local contact", "09876 543210")
	if !valid || name != "Local contact" || phone != "09876543210" {
		t.Fatalf("local contact = %q, %q, %v", name, phone, valid)
	}
}

func TestNormalizeSharedContactRejectsInvalidValues(t *testing.T) {
	for _, test := range []struct{ name, phone string }{
		{name: "", phone: "7056407000"},
		{name: "Pooja", phone: "123"},
		{name: "Pooja\nSharma", phone: "7056407000"},
	} {
		if _, _, valid := normalizeSharedContact(test.name, test.phone); valid {
			t.Fatalf("contact %q, %q should be rejected", test.name, test.phone)
		}
	}
}
