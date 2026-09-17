# Maintaining releases

The only authored version is `VERSION`, embedded in the Go executable. Packaging
reads the same file; tags, asset names and formula versions follow it. Use the
Go toolchain specified in `go.mod` for checks and release builds.

## First release and subsequent releases

1. Review the changes and run `/bin/bash scripts/check.sh`. For later releases,
   first increment `VERSION` (plain `major.minor.patch`). Never reuse a published
   version, including when migrating the implementation from Bash to Go.
2. Commit and push the reviewed files to `main` **when publication is authorized**.
   This implementation task does not push or publish anything.
3. For automatic formula PR creation, in repository Settings → Actions → General,
   enable **Allow GitHub Actions to create and approve pull requests**.
   Organization policy must permit it. If PR creation is blocked, the release
   finishes with a warning and a manual PR link in the run summary instead.
   The release job requests
   `contents: write` to publish releases and push a formula branch, and
   `pull-requests: write` to open its PR. Checks only need `contents: read`.
   No personal access token is needed. Branch rules must allow the bot to create
   `codex/ghs-formula-v*` branches; the workflow never pushes to `main`.
4. Intentionally run **Release** from the Actions UI on the default branch (or
   `gh workflow run release.yml --repo peterlapin/ghs --ref main`). It runs macOS
   and Linux checks, then builds on Linux, creates tag `v<version>` at the checked
   commit, publishes four binary archives with checksums and the formula, and opens a PR adding or
   updating `Formula/ghs.rb`.
5. Review the PR (or open it using the manual link in the run summary) and
   validate the **published** archive with Homebrew (below).
   Merge the PR to make installation/upgrades available. Website updates belong
   with the local CLI changes and do not wait for this release step. For the
   first release, also update README's bootstrap status in a follow-up change.

The default `GITHUB_TOKEN` does not trigger new push/pull-request workflows from
its own changes. Explicitly run **CI** via workflow_dispatch on the formula PR's
branch if needed. Required PR checks may need that manual run or a maintainer
commit; do not bypass branch protections. See GitHub's
[workflow triggering rules](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow).

When fixing a failed check, push the fix and start a **new** Release run on `main`.
Re-running an old failed run uses its original commit, so it cannot pick up the fix.

## Binary archives and formula

`bash scripts/package.sh` writes these ignored, local artifacts:

- `dist/ghs-<version>-<os>-<arch>.tar.gz`
- `dist/ghs-<version>-<os>-<arch>.tar.gz.sha256`
- `dist/ghs.rb` (rendered from `Formula/ghs.rb.in` with the actual checksum)

The targets are `darwin-arm64`, `darwin-amd64`, `linux-arm64`, and `linux-amd64`.
The formula selects the correct URL and checksum for the user's OS and CPU.
Every archive contains only the compiled `bin/ghs`, `README.md`, and MIT `LICENSE`.
Builds disable cgo and VCS stamping, trim source paths, and remove the build ID.
Fixed file order, modes, timestamps, ownership and gzip headers make repeated
builds reproducible with the same Go and tar/gzip toolchains. Both BSD tar (macOS) and GNU
tar (Linux) are supported; the published bytes always come from the Linux release
job. Formula changes cannot change the archive or create a checksum cycle.

Do not copy an unpublished local formula into `Formula/ghs.rb` and present it as
installable. Keep the published formula unchanged until the release workflow
generates its update from the new archives.
Never replace an existing release archive: version bumps produce new URLs.

If publication succeeds but PR creation fails, retain the published assets and
fix permissions. Download the published `ghs.rb` and checksum with
`gh release download v<version> --repo peterlapin/ghs --dir <empty-directory>`,
verify the matching archive using `shasum -a 256 -c ghs-<version>-<os>-<arch>.tar.gz.sha256`, and open
or finish the formula PR manually from those exact assets. Do not rebuild or
overwrite the release; the workflow refuses an existing tag. If a partial release
is unusable, inspect it and publish a new version instead of silently replacing it.

## Published-archive Homebrew verification

After publication, tap with the explicit URL, then check out the formula PR:

```sh
brew tap peterlapin/ghs https://github.com/peterlapin/ghs.git
cd "$(brew --repository peterlapin/ghs)"
gh pr checkout <number>
```

With that PR checked out, run:

```sh
brew style peterlapin/ghs/ghs
brew install peterlapin/ghs/ghs
brew test peterlapin/ghs/ghs
brew audit --strict peterlapin/ghs/ghs
```

The formula installs only the compiled executable; `gh` and `gh-stack` are user-managed
prerequisites, not Homebrew dependencies of GHS. Go and jq are not runtime
dependencies. Its test uses a fake `gh`
and works offline without credentials or the extension. Installation must never
authenticate or install extensions. Return the tap checkout to `main` after
testing. The full download/install/audit path requires a published archive; local
syntax, packaging and fake-gh tests do not establish public installability.

The website lives in the separate `peterlapin/ghstacked` repository, checked out
at `../ghstacked`. Every CLI change must include a review and update of its
command reference, examples, behavior notes, and installation instructions.
See [AGENTS.md](AGENTS.md). Use local CLI code and version, including uncommitted
changes, as the source of truth. Update the website in the same task without
waiting for or checking a release or formula merge, and describe local behavior
without release-dependent caveats. Run the website typecheck and build before
an authorized deploy.
