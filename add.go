package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type branchRef struct {
	Branch      string `json:"branch"`
	PullRequest *struct {
		Merged bool `json:"merged"`
	} `json:"pullRequest"`
}

type stack struct {
	Trunk    branchRef   `json:"trunk"`
	Branches []branchRef `json:"branches"`
}

type stackFile struct {
	SchemaVersion int     `json:"schemaVersion"`
	Stacks        []stack `json:"stacks"`
}

func parseStacks(data []byte) (stackFile, error) {
	var state stackFile
	err := json.Unmarshal(data, &state)
	valid := err == nil && state.SchemaVersion == 1 && state.Stacks != nil
	for _, s := range state.Stacks {
		valid = valid && s.Trunk.Branch != "" && s.Branches != nil
		for _, b := range s.Branches {
			valid = valid && b.Branch != ""
		}
	}
	if !valid {
		return state, errors.New("Cannot read supported gh-stack metadata; use gh stack directly.")
	}
	return state, nil
}

func (s stack) contains(name string) bool {
	for _, b := range s.Branches {
		if b.Branch == name {
			return true
		}
	}
	return false
}

func (s stack) fullyMerged() bool {
	for _, b := range s.Branches {
		if b.PullRequest == nil || !b.PullRequest.Merged {
			return false
		}
	}
	return true
}

func currentBranch() (string, error) {
	ref, err := gitOutput("symbolic-ref", "--quiet", "HEAD")
	if err != nil || !strings.HasPrefix(ref, "refs/heads/") {
		return "", errors.New("Run add on a local branch in a Git repository.")
	}
	return strings.TrimPrefix(ref, "refs/heads/"), nil
}

func prompt(input io.Reader, text string) (string, error) {
	fmt.Fprint(os.Stderr, text)
	// Do not read ahead: unread stdin must remain available to the gh process.
	var line strings.Builder
	var b [1]byte
	for {
		if _, err := io.ReadFull(input, b[:]); err != nil {
			return "", errors.New("Add cancelled; no further changes made.")
		}
		if b[0] == '\n' {
			return line.String(), nil
		}
		line.WriteByte(b[0])
	}
}

type localBranch struct{ name, head string }

func nearestAncestors(branches []localBranch, ancestor func(string, string) (bool, error)) ([]localBranch, error) {
	var nearest []localBranch
	for _, branch := range branches {
		keep := true
		for _, other := range branches {
			if branch.head == other.head {
				continue
			}
			before, err := ancestor(branch.head, other.head)
			if err != nil {
				return nil, err
			}
			if before {
				keep = false
				break
			}
		}
		if keep {
			nearest = append(nearest, branch)
		}
	}
	return nearest, nil
}

func guidedAdd() error {
	current, err := currentBranch()
	if err != nil {
		return err
	}
	dir, err := gitOutput("rev-parse", "--git-common-dir")
	if err != nil {
		return err
	}
	data, err := os.ReadFile(filepath.Join(dir, "gh-stack"))
	if errors.Is(err, os.ErrNotExist) {
		return errors.New("No local stack found. Run ghs init first.")
	}
	if err != nil {
		return err
	}
	state, err := parseStacks(data)
	if err != nil {
		return err
	}
	names := make(map[string]bool)
	for _, s := range state.Stacks {
		if s.Trunk.Branch == current {
			return errors.New("Current branch is a stack trunk. Check out the intended stack tip before running ghs add.")
		}
		for _, b := range s.Branches {
			names[b.Branch] = true
		}
	}
	var sorted []string
	for name := range names {
		sorted = append(sorted, name)
	}
	sort.Strings(sorted)
	var branches []string
	var ancestors []localBranch
	parent := ""
	isAncestor := func(a, b string) (bool, error) { return gitTest("merge-base", "--is-ancestor", a, b) }
	for _, name := range sorted {
		exists, err := gitTest("show-ref", "--verify", "--quiet", "refs/heads/"+name)
		if err != nil {
			return err
		}
		if !exists {
			continue
		}
		branches = append(branches, name)
		if name == current {
			parent = current
			continue
		}
		head, err := gitOutput("rev-parse", "--verify", "refs/heads/"+name)
		if err != nil {
			return err
		}
		before, err := isAncestor(head, "HEAD")
		if err != nil {
			return err
		}
		if before {
			ancestors = append(ancestors, localBranch{name, head})
		}
	}
	if len(branches) == 0 {
		return errors.New("No local stack branches found. Run ghs init first.")
	}
	input := os.Stdin
	if parent == "" {
		candidates, err := nearestAncestors(ancestors, isAncestor)
		if err != nil {
			return err
		}
		if len(candidates) == 1 {
			parent = candidates[0].name
			fmt.Fprintf(os.Stderr, "Attaching %s above %s.\n", current, parent)
		} else {
			fmt.Fprintf(os.Stderr, "Cannot determine a unique parent for %s. Local stack branches:\n", current)
			for _, name := range branches {
				fmt.Fprintf(os.Stderr, "  %s\n", name)
			}
			reply, err := prompt(input, "Parent branch (exact name): ")
			if err != nil {
				return err
			}
			for _, name := range branches {
				if name == reply {
					parent = name
				}
			}
			if parent == "" {
				return errors.New("Choose an existing local stack branch.")
			}
		}
	}
	var selected *stack
	for i := range state.Stacks {
		if state.Stacks[i].contains(parent) {
			if selected != nil {
				return errors.New("Parent belongs to multiple stacks; use gh stack directly.")
			}
			selected = &state.Stacks[i]
		}
	}
	if selected == nil {
		return errors.New("Choose an existing local stack branch.")
	}
	top := selected.Branches[len(selected.Branches)-1].Branch
	if parent != top {
		return fmt.Errorf("Cannot add above %s in the middle of a stack. Use ghs reshape, or add from the top branch %s.", parent, top)
	}
	if selected.fullyMerged() {
		return errors.New("This stack is fully merged. Run ghs init to start a new stack.")
	}
	if parent != current {
		return attachBranch(current, parent)
	}
	return addLayer(input, current, *selected)
}

func attachBranch(current, parent string) (result error) {
	if _, err := gitOutput("merge-base", "refs/heads/"+parent, "HEAD"); err != nil {
		return errors.New("The selected parent has no common history with this branch.")
	}
	changes, err := gitOutput("status", "--porcelain")
	if err != nil {
		return err
	}
	if changes != "" {
		return errors.New("Commit or stash your changes before attaching an existing branch.")
	}
	session := newCommandSession()
	defer session.close()
	defer func() {
		branch, err := currentBranch()
		if err == nil && branch == current {
			return
		}
		// Recovery remains possible after cancellation; never force a checkout.
		if err := attachedCommand("git", "checkout", "--quiet", current).Run(); err != nil {
			fmt.Fprintf(os.Stderr, "ghs: Could not return to %s.\n", current)
			if result == nil {
				result = err
			}
		}
	}()
	if err := session.run("git", "checkout", "--quiet", parent); err != nil {
		return err
	}
	return session.run("gh", "stack", "add", "--", current)
}

func addLayer(input io.Reader, current string, s stack) error {
	fmt.Fprintf(os.Stderr, "Current branch %s is already in the stack.\n", current)
	reply, err := prompt(input, "Commit [1] staged changes or [2] all changes, including untracked files? [1]: ")
	if err != nil {
		return err
	}
	args := []string{"stack", "add"}
	switch reply {
	case "", "1", "staged":
		clean, err := gitTest("diff", "--cached", "--quiet")
		if err != nil {
			return err
		}
		if clean {
			return errors.New("No staged changes to commit.")
		}
	case "2", "all":
		changes, err := gitOutput("status", "--porcelain")
		if err != nil {
			return err
		}
		if changes == "" {
			return errors.New("No changes to commit.")
		}
		args = append(args, "-A")
	default:
		return errors.New("Choose 1 (staged) or 2 (all).")
	}
	base := s.Trunk.Branch
	if len(s.Branches) > 1 {
		base = s.Branches[len(s.Branches)-2].Branch
	}
	baseHead, err := gitOutput("rev-parse", "--verify", "refs/heads/"+base)
	if err != nil {
		return err
	}
	currentHead, err := gitOutput("rev-parse", "HEAD")
	if err != nil {
		return err
	}
	name := current
	if baseHead == currentHead {
		fmt.Fprintf(os.Stderr, "%s has no commits beyond %s. gh-stack will commit here; no new branch is created.\n", current, base)
	} else {
		name, err = prompt(input, "New branch name: ")
		if err != nil {
			return err
		}
		valid, err := gitTest("check-ref-format", "refs/heads/"+name)
		if err != nil || !valid {
			return errors.New("Invalid branch name.")
		}
		valid, err = gitTest("check-ref-format", "--branch", name)
		if err != nil || !valid {
			return errors.New("Invalid branch name.")
		}
		exists, err := gitTest("show-ref", "--verify", "--quiet", "refs/heads/"+name)
		if err != nil {
			return err
		}
		if exists {
			return errors.New("That branch already exists; choose a new branch name.")
		}
	}
	message, err := prompt(input, "Commit message: ")
	if err != nil {
		return err
	}
	if strings.TrimSpace(message) == "" {
		return errors.New("Commit message cannot be empty.")
	}
	return replaceProcess("gh", append(args, "-m", message, "--", name)...)
}
