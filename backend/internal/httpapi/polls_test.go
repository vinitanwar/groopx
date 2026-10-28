package httpapi

import (
	"strings"
	"testing"
)

func TestNormalizePoll(t *testing.T) {
	question, options, valid := normalizePoll("  Where   should we meet?  ", []string{"  Office  ", "Coffee   shop"})
	if !valid || question != "Where should we meet?" || len(options) != 2 || options[0] != "Office" || options[1] != "Coffee shop" {
		t.Fatalf("normalized poll = %q, %#v, %v", question, options, valid)
	}
}

func TestNormalizePollRejectsInvalidValues(t *testing.T) {
	tests := []struct {
		name     string
		question string
		options  []string
	}{
		{name: "blank question", question: " ", options: []string{"One", "Two"}},
		{name: "too few options", question: "Pick", options: []string{"One"}},
		{name: "too many options", question: "Pick", options: make([]string, 13)},
		{name: "blank option", question: "Pick", options: []string{"One", " "}},
		{name: "duplicate options", question: "Pick", options: []string{"Office", " office "}},
		{name: "control character", question: "Pick\nnow", options: []string{"One", "Two"}},
		{name: "long question", question: strings.Repeat("q", 301), options: []string{"One", "Two"}},
		{name: "long option", question: "Pick", options: []string{strings.Repeat("o", 121), "Two"}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, _, valid := normalizePoll(test.question, test.options); valid {
				t.Fatal("poll should be rejected")
			}
		})
	}
}
