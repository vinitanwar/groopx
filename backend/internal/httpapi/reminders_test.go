package httpapi

import (
	"testing"
	"time"
)

func TestNextReminderOccurrenceSkipsMissedRuns(t *testing.T) {
	tests := []struct {
		name       string
		start      time.Time
		repeatRule string
		anchorDay  int
		now        time.Time
		want       time.Time
	}{
		{name: "daily", start: time.Date(2026, time.January, 1, 9, 30, 0, 0, time.UTC), repeatRule: "daily", now: time.Date(2026, time.January, 3, 10, 0, 0, 0, time.UTC), want: time.Date(2026, time.January, 4, 9, 30, 0, 0, time.UTC)},
		{name: "weekly", start: time.Date(2026, time.January, 1, 9, 30, 0, 0, time.UTC), repeatRule: "weekly", now: time.Date(2026, time.January, 10, 10, 0, 0, 0, time.UTC), want: time.Date(2026, time.January, 15, 9, 30, 0, 0, time.UTC)},
		{name: "monthly", start: time.Date(2026, time.January, 31, 9, 30, 0, 0, time.UTC), repeatRule: "monthly", anchorDay: 31, now: time.Date(2026, time.March, 1, 10, 0, 0, 0, time.UTC), want: time.Date(2026, time.March, 31, 9, 30, 0, 0, time.UTC)},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got := nextReminderOccurrence(test.start, test.repeatRule, test.anchorDay, test.now)
			if !got.Equal(test.want) {
				t.Fatalf("next occurrence = %s, want %s", got, test.want)
			}
		})
	}
}

func TestAddReminderMonthKeepsOriginalDay(t *testing.T) {
	january := time.Date(2026, time.January, 31, 9, 30, 0, 0, time.UTC)
	february := addReminderMonth(january, 31)
	wantFebruary := time.Date(2026, time.February, 28, 9, 30, 0, 0, time.UTC)
	if !february.Equal(wantFebruary) {
		t.Fatalf("February occurrence = %s, want %s", february, wantFebruary)
	}

	march := addReminderMonth(february, 31)
	wantMarch := time.Date(2026, time.March, 31, 9, 30, 0, 0, time.UTC)
	if !march.Equal(wantMarch) {
		t.Fatalf("March occurrence = %s, want %s", march, wantMarch)
	}
}
