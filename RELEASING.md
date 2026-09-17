# Maintaining releases

The only authored version is `GHS_VERSION` in `bin/ghs`. Packaging reads
`bin/ghs --version`; tags, asset names and formula versions follow it.

## First release and subsequent releases

1. Review the changes and run `/bin/bash scripts/check.sh`. For later releases,
   first increment `GHS_VERSION` (plain `major.minor.patch`). For the first release,
   the prepared version is `0.1.0`.
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
   commit, publishes the archive/checksum/formula, and opens a PR adding or
   updating `Formula/ghs.rb`.
5. Review the PR (or open it using the manual link in the run summary) and
   validate the **published** archive with Homebrew (below).
   Merge the PR to make installation/upgrades available. Do not enable the
   website's published installation state until this succeeds. For the first
   release, also update README's bootstrap status in a follow-up change.

The default `GITHUB_TOKEN` does not trigger new push/pull-request workflows from
its own changes. Explicitly run **CI** via workflow_dispatch on the formula PR's
branch if needed. Required PR checks may need that manual run or a maintainer
commit; do not bypass branch protections. See GitHub's
[workflow triggering rules](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow).

When fixing a failed check, push the fix and start a **new** Release run on `main`.
Re-running an old failed run uses its original commit, so it cannot pick up the fix.

## Archive and formula bootstrap

`bash scripts/package.sh` writes these ignored, local artifacts:

- `dist/ghs-<version>.tar.gz`
- `dist/ghs-<version>.tar.gz.sha256`
- `dist/ghs.rb` (rendered from `Formula/ghs.rb.in` with the actual checksum)

The archive contains only `bin/ghs`, `README.md` and the existing MIT `LICENSE`.
Fixed file order, modes, timestamps, ownership and gzip headers make repeated
builds reproducible with the same tar/gzip toolchain. Both BSD tar (macOS) and GNU
tar (Linux) are supported; the published bytes always come from the Linux release
job. Formula changes cannot change the archive or create a checksum cycle.

Do not copy an unpublished local formula into `Formula/ghs.rb` and present it as
installable. There is intentionally no live formula before the first publication.
Never replace an existing release archive: version bumps produce new URLs.

If publication succeeds but PR creation fails, retain the published assets and
fix permissions. Download the published `ghs.rb` and checksum with
`gh release download v<version> --repo peterlapin/ghs --dir <empty-directory>`,
verify the archive using `shasum -a 256 -c ghs-<version>.tar.gz.sha256`, and open
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
brew install --build-from-source peterlapin/ghs/ghs
brew test peterlapin/ghs/ghs
brew audit --strict peterlapin/ghs/ghs
```

The formula installs only the wrapper; `gh` and `gh-stack` are user-managed
prerequisites, not Homebrew dependencies of GHS. Its test uses a fake `gh`
and works offline without credentials or the extension. Installation must never
authenticate or install extensions. Return the tap checkout to `main` after
testing. The full download/install/audit path requires a published archive; local
syntax, packaging and fake-gh tests do not establish public installability.

The website lives in the separate `peterlapin/ghstacked` repository. Its current
configuration still uses `brew install <owner>/tap/ghs` as a planned placeholder.
After release verification, its eventual command is `brew install peterlapin/ghs/ghs`
and setup must include the explicit tap URL above. No website changes are part
of this implementation. The website also currently says Homebrew will install
GitHub CLI as a dependency; that copy needs to change to reflect the requirement
that users already have `gh` and `gh stack` installed.
