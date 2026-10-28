package httpapi

import "testing"

func TestValidLiveCoordinatesAcceptsZeroCoordinates(t *testing.T) {
	latitude, longitude, accuracy := 0.0, 0.0, 12.5
	if !validLiveCoordinates(&latitude, &longitude, &accuracy) {
		t.Fatal("zero latitude and longitude should be valid")
	}
	latitude = 91
	if validLiveCoordinates(&latitude, &longitude, &accuracy) {
		t.Fatal("latitude outside the valid range should be rejected")
	}
}

func TestValidLiveLocationDuration(t *testing.T) {
	for _, seconds := range []int{900, 3600, 28800} {
		if !validLiveLocationDuration(seconds) {
			t.Fatalf("duration %d should be valid", seconds)
		}
	}
	if validLiveLocationDuration(1200) {
		t.Fatal("unsupported duration should be rejected")
	}
}

func TestValidLiveLocationTrackingKey(t *testing.T) {
	if !validLiveLocationTrackingKey("device_0123456789abcdef") {
		t.Fatal("generated device key should be valid")
	}
	for _, value := range []string{"short", "device key with spaces", "device/key/with/slashes"} {
		if validLiveLocationTrackingKey(value) {
			t.Fatalf("tracking key %q should be rejected", value)
		}
	}
}
