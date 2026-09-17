# ghs

A small Go CLI around GitHub's official [`gh stack`](https://github.com/github/gh-stack)
extension. Website: [ghstacked.com](https://ghstacked.com).

## Installation

```sh
brew tap peterlapin/ghs https://github.com/peterlapin/ghs.git
brew install peterlapin/ghs/ghs
```

The explicit Git URL is required because this repository is named `ghs`, not
`homebrew-ghs`. The fully qualified formula name avoids collisions with other taps.
GitHub CLI (`gh`) and its `github/gh-stack` extension must already be installed.
The formula installs only GHS and does not install or manage either prerequisite.
GHS ships as a compiled executable for macOS and Linux, on arm64 and amd64.
Git, GitHub CLI, and gh-stack are the runtime prerequisites. Go and jq are not
required to run GHS. GHS never installs dependencies automatically.

If your existing GitHub CLI setup is incomplete, configure it separately,
**only if needed**:

```sh
gh auth login
gh extension install github/gh-stack
```

Neither installation nor invocation of GHS performs this setup automatically.
For local use, build with Go using `go build -o build/ghs .`, then run
`./build/ghs` (or copy that executable into a directory on your PATH).

## Commands

| GHS command | Runs |
| --- | --- |
| `add` without arguments | Attach the current branch or guide creation of a new layer |
| `add <arguments>` | `gh stack add <arguments>` |
| `create`, `c` | `gh stack add` |
| `ls` | `gh stack view --short` |
| `checkout`, `co` | `gh stack checkout` |
| `restack`, `r` | `gh stack rebase --no-trunk` |
| `submit`, `s` | `gh stack submit --auto`, then `gh pr view --web` |
| `submit --interactive`, `s --interactive` | `gh stack submit` |
| `reshape` | `gh stack modify` |

Every other command passes through unchanged, including `init`, `view`,
`switch`, `up`, `down`, `top`, `bottom`, `trunk`, `rebase`, `sync`, `push`, `merge`,
`link`, `modify`, and `unstack`. In particular, `ghs modify` retains the upstream
stack-restructuring behaviour. Unknown commands are handled by upstream too.

```sh
ghs create -Am "Add login"
ghs add                   # Attach this branch or prompt for the next layer
ghs ls
ghs restack --upstack
ghs submit
ghs submit --interactive   # Original submit with the PR details editor
ghs create --help          # gh stack add --help
```

`ghs` and `ghs --help` show wrapper help. `ghs --version` shows the installed GHS
version. These work without `gh` and outside a repository. Command-specific help
is forwarded to upstream with the same mapping and flags as normal execution.

### Guided add

Run `ghs add` without arguments in a repository with an existing stack:

- On an untracked branch, GHS finds the nearest tracked ancestor. If there is
  exactly one, it checks out that parent and runs `gh stack add <current-branch>`
  to adopt the branch, returning to it afterward. If ancestry is ambiguous or no
  tracked ancestor exists, it asks for a parent branch. Git does not record a
  definitive parent branch, so detection uses the current commit graph.
- On a tracked stack tip, choose **staged** (the default) or **all**, then enter
  a new branch name and a separate commit message. Staged runs
  `gh stack add -m "message" <branch>`; all runs
  `gh stack add -A -m "message" <branch>`, including untracked files. If the
  current tip has no commits beyond its parent, GHS explains that upstream will
  commit on the current branch and skips the branch-name prompt.

Upstream supports adding only above the stack tip. For a parent in the middle,
GHS stops and suggests `ghs reshape`. Check out a stack tip before using guided
add from a trunk. Attaching an existing branch requires a clean working tree;
GHS does not stash changes or force a checkout. If attachment fails, it attempts
to return to the original branch and preserves the upstream failure status.
Prompts can be cancelled with Ctrl+C or end-of-input before any mutation. If a
commit fails after a new layer is created, that layer remains for recovery.

GHS only reads gh-stack's schema-v1 metadata; gh-stack performs all stack writes
and commits. Use `ghs create`/`ghs c`, or `ghs add` with explicit arguments, for
direct upstream behavior without detection or GHS prompts. `ghs add --help`
continues to show upstream help.

### Submit

`ghs submit` (or `ghs s`) skips the PR details editor and creates new PRs as
drafts by default. After submission succeeds, it opens the current branch's PR
in your system browser. Existing PRs retain their draft status; passing the
upstream `--open` flag explicitly marks PRs ready for review. Help (`--help` or
`-h`) and failed submissions never open the browser. A browser-opening failure
returns a nonzero exit status even though submission has already succeeded.

Use `ghs submit --interactive` (or `ghs s --interactive`) for the original
upstream submit behavior: GHS adds no `--auto` flag and does not open the browser.
The PR details editor is available in an interactive terminal. GHS removes
`--interactive` and forwards any other arguments unchanged; put it before `--`.

Arguments, standard streams, terminal interaction, working directory, environment,
and exit status are forwarded to GitHub CLI. Most commands use `exec`; guided
add performs local detection and prompts, and submit waits for
`gh stack submit --auto` to succeed before opening the PR.
GHS does not capture upstream output,
check authentication, or probe extensions on invocation. Missing `gh` gets an
actionable error; all other upstream errors are left to GitHub CLI.

`sync` may push changes. `restack` inherits `rebase --no-trunk`: it skips fetching
and rebasing onto trunk, and rebases stack branches onto each other; upstream
flags determine scope. GHS adds no repository metadata; GitHub Stack maintains
its own state. Compatibility and command behaviour follow the installed upstream
extension. Older versions may reject newer flags. Guided add additionally reads
the upstream metadata schema and uses Git ancestry to select a parent.

Mappings were checked on 2026-09-17 against the official
[command reference](https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands)
and [upstream README](https://github.com/github/gh-stack). No mapping discrepancies
were found. Submit draft behavior was also checked against the installed
extension's `gh stack submit --help`. Use `gh stack <command> --help` to check
supported arguments.

## Upgrades and removal

After publication, upgrade GHS through Homebrew:

```sh
brew update
brew upgrade peterlapin/ghs/ghs
```

The extension has its own lifecycle: update it separately when needed with
`gh extension upgrade gh-stack`. GHS provides no self-updater (`ghs update` is
simply forwarded as an upstream command).

```sh
brew uninstall peterlapin/ghs/ghs
brew untap peterlapin/ghs
```

GitHub CLI, authentication and the extension remain separately managed.

## Development

Install the Go version specified in `go.mod`. The CLI uses only the Go standard
library, with no third-party modules or CLI framework. `VERSION` is embedded in
the binary and is the single source of truth for the GHS version.

```sh
go build -o build/ghs .
./build/ghs --help
/bin/bash scripts/check.sh
```

Go unit tests cover metadata parsing, parent selection, flags, and exit codes.
Behavior tests inject a fake `gh` through PATH and never contact GitHub or
mutate the working repository. Guided add tests create disposable Git repositories
to check ancestry, parent selection, worktrees, prompts, cancellation, and recovery.
Checks cover exact arguments, command help, shell metacharacters,
process handoff, streams, exit codes, missing dependencies, archive contents,
checksums, repeatable packaging and the extracted executable. Checks include
`go vet`, race-enabled Go tests, and signal forwarding/recovery tests. Bash is
used only for development/release scripts and the behavior test harness, which
also receive syntax and ShellCheck checks. Offline release-PR tests cover automatic creation, a manual fallback,
and branch-push failures. ShellCheck runs when installed locally and is required
by macOS/Linux CI. Ruby is used for workflow parsing and Homebrew formula checks.
When Homebrew is available, checks also load its formula DSL, verify the archive
checksum, install into a temporary prefix and run the wrapper tests there.

MIT licensed; see [LICENSE](LICENSE).
