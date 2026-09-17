package main

import (
	_ "embed"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

//go:embed VERSION
var version string

const usage = `Usage: ghs <command> [arguments...]

Aliases                 Runs
  add                   Attach the current branch or prompt for a new layer
  create, c             gh stack add
  ls                    gh stack view --short
  checkout, co          gh stack checkout
  restack, r            gh stack rebase --no-trunk
  submit, s             gh stack submit --auto, then gh pr view --web
  reshape               gh stack modify

Submit creates new PRs as drafts and opens the current branch PR on success.
submit --interactive runs the original gh stack submit without opening the browser.
Bare add guides you; add with arguments and create/c pass through to gh stack add.
All other commands and arguments pass through to gh stack unchanged.
ghs <command> --help shows upstream command help.
ghs --version shows the installed version.
`

func main() {
	if err := run(os.Args[1:]); err != nil {
		// Child processes already wrote their errors to stderr.
		if _, childExit := err.(*exec.ExitError); !childExit {
			if _, interrupted := err.(signalExit); !interrupted {
				fmt.Fprintln(os.Stderr, "ghs:", err)
			}
		}
		os.Exit(exitCode(err))
	}
}

func run(args []string) error {
	if len(args) == 0 || args[0] == "--help" {
		fmt.Print(usage)
		return nil
	}
	if args[0] == "--version" {
		fmt.Printf("ghs %s\n", strings.TrimSpace(version))
		return nil
	}
	if _, err := exec.LookPath("gh"); err != nil {
		return &exec.Error{Name: "GitHub CLI (gh) is required. Install it with: brew install gh (or visit https://cli.github.com)", Err: exec.ErrNotFound}
	}
	command, rest := args[0], args[1:]
	switch command {
	case "add":
		if len(rest) == 0 {
			return guidedAdd()
		}
	case "create", "c":
		command = "add"
	case "ls":
		command, rest = "view", append([]string{"--short"}, rest...)
	case "checkout", "co":
		command = "checkout"
	case "restack", "r":
		command, rest = "rebase", append([]string{"--no-trunk"}, rest...)
	case "reshape":
		command = "modify"
	case "submit", "s":
		return submit(rest)
	}
	return replaceProcess("gh", append([]string{"stack", command}, rest...)...)
}

func submitArgs(args []string) (forward []string, interactive, help bool) {
	for i, arg := range args {
		switch arg {
		case "--":
			return append(forward, args[i:]...), interactive, help
		case "--interactive":
			interactive = true
		case "--help", "-h":
			help = true
			forward = append(forward, arg)
		default:
			forward = append(forward, arg)
		}
	}
	return
}

func submit(args []string) error {
	forward, interactive, help := submitArgs(args)
	command := []string{"stack", "submit"}
	if !interactive {
		command = append(command, "--auto")
	}
	command = append(command, forward...)
	if interactive || help {
		return replaceProcess("gh", command...)
	}
	session := newCommandSession()
	err := session.run("gh", command...)
	session.close()
	if err != nil {
		return err
	}
	return replaceProcess("gh", "pr", "view", "--web")
}

func gitOutput(args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	return strings.TrimSuffix(string(out), "\n"), err
}

// Git predicates use exit 1 for false; other failures must not look like false.
func gitTest(args ...string) (bool, error) {
	err := exec.Command("git", args...).Run()
	if err == nil {
		return true, nil
	}
	var status *exec.ExitError
	if errors.As(err, &status) && status.ExitCode() == 1 {
		return false, nil
	}
	return false, fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
}
