package main

import (
	"errors"
	"os/exec"
	"reflect"
	"testing"
)

func TestSubmitArgumentBoundaries(t *testing.T) {
	tests := []struct {
		args, want        []string
		interactive, help bool
	}{
		{[]string{"--help", "--interactive", "two words", ""}, []string{"--help", "two words", ""}, true, true},
		{[]string{"--", "--interactive", "--help"}, []string{"--", "--interactive", "--help"}, false, false},
		{[]string{"--interactive", "--", "-h"}, []string{"--", "-h"}, true, false},
	}
	for _, tt := range tests {
		got, interactive, help := submitArgs(tt.args)
		if !reflect.DeepEqual(got, tt.want) || interactive != tt.interactive || help != tt.help {
			t.Errorf("submitArgs(%q) = %q, %v, %v", tt.args, got, interactive, help)
		}
	}
}

func TestParseStackMetadata(t *testing.T) {
	for _, input := range []string{
		`{"schemaVersion":1,"stacks":[]}`,
		`{"schemaVersion":1,"repository":"example","stacks":[{"trunk":{"branch":"main","head":"abc"},"branches":[{"branch":"feature","base":"abc","pullRequest":{"number":1,"merged":true}}]}]}`,
	} {
		if _, err := parseStacks([]byte(input)); err != nil {
			t.Errorf("valid metadata: %v", err)
		}
	}
	for _, input := range []string{
		`{broken`, `null`, `{}`, `{"schemaVersion":2,"stacks":[]}`,
		`{"schemaVersion":1,"stacks":null}`,
		`{"schemaVersion":1,"stacks":[{"trunk":{"branch":"main"},"branches":null}]}`,
		`{"schemaVersion":1,"stacks":[{"trunk":{"branch":"main"},"branches":[null]}]}`,
		`{"schemaVersion":1,"stacks":[{"branches":[]}]}`,
	} {
		if _, err := parseStacks([]byte(input)); err == nil {
			t.Errorf("accepted malformed metadata: %s", input)
		}
	}
}

func TestNearestAncestors(t *testing.T) {
	// A linear history a -> b -> c, plus an incomparable merge parent d.
	ancestor := func(a, b string) (bool, error) {
		return (a == "a" && (b == "b" || b == "c")) || (a == "b" && b == "c"), nil
	}
	tests := []struct {
		name           string
		branches, want []localBranch
	}{
		{"linear", []localBranch{{"A", "a"}, {"B", "b"}, {"C", "c"}}, []localBranch{{"C", "c"}}},
		{"equal tips", []localBranch{{"B", "b"}, {"alias", "b"}}, []localBranch{{"B", "b"}, {"alias", "b"}}},
		{"merge", []localBranch{{"A", "a"}, {"C", "c"}, {"D", "d"}}, []localBranch{{"C", "c"}, {"D", "d"}}},
		{"none", nil, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := nearestAncestors(tt.branches, ancestor)
			if err != nil || !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("got %v, %v; want %v", got, err, tt.want)
			}
		})
	}
	broken := errors.New("Git failed")
	_, err := nearestAncestors([]localBranch{{"A", "a"}, {"B", "b"}}, func(string, string) (bool, error) { return false, broken })
	if !errors.Is(err, broken) {
		t.Fatal("Git error was mistaken for missing ancestry")
	}
}

func TestChildExitCodes(t *testing.T) {
	for _, tt := range []struct {
		command string
		code    int
	}{{"exit 42", 42}, {"kill -TERM $$", 143}} {
		err := exec.Command("/bin/sh", "-c", tt.command).Run()
		if got := exitCode(err); got != tt.code {
			t.Errorf("%s returned %d, want %d", tt.command, got, tt.code)
		}
	}
}
