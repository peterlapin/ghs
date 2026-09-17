# ghs

A small Bash wrapper around GitHub's official [`gh stack`](https://github.com/github/gh-stack)
extension. Website: [ghstacked.com](https://ghstacked.com).

## Installation

**First-release bootstrap:** no release has been published yet. The commands below
become usable after the first release is published and its formula PR is merged.
`Formula/ghs.rb.in` is a template, not an installable formula. See
[RELEASING.md](RELEASING.md) for the publication steps.

```sh
brew tap peterlapin/ghs https://github.com/peterlapin/ghs.git
brew install peterlapin/ghs/ghs
```

The explicit Git URL is required because this repository is named `ghs`, not
`homebrew-ghs`. The fully qualified formula name avoids collisions with other taps.
GitHub CLI (`gh`) and its `github/gh-stack` extension must already be installed.
The formula installs only GHS and does not install or manage either prerequisite.
GHS runs on macOS's bundled Bash 3.2 and Linux Bash; no language runtime or package
manager is needed to run it.

If your existing GitHub CLI setup is incomplete, configure it separately,
**only if needed**:

```sh
gh auth login
gh extension install github/gh-stack
```

Neither installation nor invocation of GHS performs this setup automatically.
For local use before publication, run `./bin/ghs` from this checkout (or copy
`bin/ghs` into a directory on your PATH).

## Commands

| GHS command | Runs |
| --- | --- |
| `create`, `c` | `gh stack add` |
| `ls` | `gh stack view --short` |
| `checkout`, `co` | `gh stack checkout` |
| `restack`, `r` | `gh stack rebase --no-trunk` |
| `submit`, `s` | `gh stack submit --auto`, then `gh pr view --web` |
| `reshape` | `gh stack modify` |

Every other command passes through unchanged, including `init`, `add`, `view`,
`switch`, `up`, `down`, `top`, `bottom`, `trunk`, `rebase`, `sync`, `push`, `merge`,
`link`, `modify`, and `unstack`. In particular, `ghs modify` retains the upstream
stack-restructuring behaviour. Unknown commands are handled by upstream too.

```sh
ghs create -Am "Add login"
ghs ls
ghs restack --upstack
ghs submit
ghs create --help          # gh stack add --help
```

`ghs` and `ghs --help` show wrapper help. `ghs --version` shows the installed GHS
version. These work without `gh` and outside a repository. Command-specific help
is forwarded to upstream with the same mapping and flags as normal execution.

`ghs submit` (or `ghs s`) skips the PR details editor and creates new PRs as
drafts by default. After submission succeeds, it opens the current branch's PR
in your system browser. Existing PRs retain their draft status; passing the
upstream `--open` flag explicitly marks PRs ready for review. Help (`--help` or
`-h`) and failed submissions never open the browser. A browser-opening failure
returns a nonzero exit status even though submission has already succeeded.

Arguments, standard streams, terminal interaction, working directory, environment,
and exit status are forwarded to GitHub CLI. Commands use `exec`, except that
submit first waits for `gh stack submit --auto` to succeed before opening the PR.
GHS does not capture upstream output,
check authentication, or probe extensions on invocation. Missing `gh` gets an
actionable error; all other upstream errors are left to GitHub CLI.

`sync` may push changes. `restack` inherits `rebase --no-trunk`: it skips fetching
and rebasing onto trunk, and rebases stack branches onto each other; upstream
flags determine scope. GHS adds no repository metadata; GitHub Stack maintains
its own state. Compatibility and command behaviour follow the installed upstream
extension. Older versions may reject newer flags; GHS adds no compensating Git logic.

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

```sh
/bin/bash scripts/check.sh
```

Tests inject a fake `gh` through PATH and never contact GitHub or mutate a real
repository. Checks cover exact arguments, command help, shell metacharacters,
process handoff, streams, exit codes, missing dependencies, archive contents,
checksums, repeatable packaging and the extracted executable. Bash syntax checks
always run. Offline release-PR tests cover automatic creation, a manual fallback,
and branch-push failures. ShellCheck runs when installed locally and is required
by macOS/Linux CI. Ruby is used for workflow parsing and Homebrew formula checks.
When Homebrew is available, checks also load its formula DSL, verify the archive
checksum, install into a temporary prefix and run the wrapper tests there.

MIT licensed; see [LICENSE](LICENSE).
