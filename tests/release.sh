#!/bin/bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"

# Exercise the actual workflow step without contacting GitHub or pushing a branch.
ruby -ryaml -e '
  workflow = YAML.load_file(ARGV.fetch(0))
  step = workflow.fetch("jobs").fetch("publish").fetch("steps").find do |item|
    item["name"] == "Open formula-update pull request"
  end
  puts step.fetch("run")
' "$root/.github/workflows/release.yml" > "$tmp/formula-step.sh"
bash -n "$tmp/formula-step.sh"

cat > "$tmp/bin/git" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$RELEASE_GIT_LOG"
if [ "$1" = ls-remote ] && [ "${RELEASE_TAG_EXISTS:-0}" = 1 ]; then
  printf 'abc123\trefs/tags/v%s\n' "$VERSION"
fi
if [ "$1" = push ] && [ "$RELEASE_PUSH_FAIL" = 1 ]; then
  exit 1
fi
FAKE
cat > "$tmp/bin/gh" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$RELEASE_GH_LOG"
exit "$RELEASE_PR_STATUS"
FAKE
chmod +x "$tmp/bin/git" "$tmp/bin/gh"

for scenario in automatic manual push-failure; do
  work="$tmp/$scenario"
  mkdir -p "$work/dist" "$work/Formula"
  printf '# formula fixture\n' > "$work/dist/ghs.rb"
  export PATH="$tmp/bin:$PATH" VERSION=1.2.3 GH_REPO=example/ghs DEFAULT_BRANCH=main
  export RUNNER_TEMP="$work" GITHUB_STEP_SUMMARY="$work/summary"
  export RELEASE_GIT_LOG="$work/git.log" RELEASE_GH_LOG="$work/gh.log"
  export RELEASE_PR_STATUS=0 RELEASE_PUSH_FAIL=0
  case "$scenario" in
    manual) export RELEASE_PR_STATUS=1 ;;
    push-failure) export RELEASE_PUSH_FAIL=1 ;;
  esac
  status=0
  (cd "$work" && bash -eo pipefail "$tmp/formula-step.sh") > "$work/output" 2>&1 || status=$?
  if [ "$scenario" = push-failure ]; then
    [ "$status" -ne 0 ]
    [ ! -e "$work/summary" ]
    [ ! -e "$work/gh.log" ]
    continue
  fi
  [ "$status" -eq 0 ]
  cmp "$work/dist/ghs.rb" "$work/Formula/ghs.rb"
  grep -q '^push origin codex/ghs-formula-v1.2.3$' "$work/git.log"
  grep -q '^pr create --base main --head codex/ghs-formula-v1.2.3 ' "$work/gh.log"
  if [ "$scenario" = manual ]; then
    grep -q '^::warning::' "$work/output"
    grep -Fq 'https://github.com/example/ghs/compare/main...codex/ghs-formula-v1.2.3?expand=1' "$work/summary"
  else
    grep -q 'Review and merge the Homebrew formula PR' "$work/summary"
  fi
done
printf 'Release PR success, manual fallback and push-failure checks passed.\n'

# The publish step must upload exactly the four platform archives/checksums,
# never stale archives left in dist from the former Bash release format.
ruby -ryaml -e '
  workflow = YAML.load_file(ARGV.fetch(0))
  step = workflow.fetch("jobs").fetch("publish").fetch("steps").find do |item|
    item["name"] == "Publish versioned archive"
  end
  puts step.fetch("run")
' "$root/.github/workflows/release.yml" > "$tmp/publish-step.sh"
work="$tmp/publish"
mkdir -p "$work/dist"
export RELEASE_GIT_LOG="$work/git.log" RELEASE_GH_LOG="$work/gh.log"
export RELEASE_PR_STATUS=0 RELEASE_PUSH_FAIL=0 RELEASE_TAG_EXISTS=0 GITHUB_SHA=abc123
(cd "$work" && bash -eo pipefail "$tmp/publish-step.sh")
for platform in darwin-arm64 darwin-amd64 linux-arm64 linux-amd64; do
  grep -Fq "dist/ghs-$VERSION-$platform.tar.gz dist/ghs-$VERSION-$platform.tar.gz.sha256" "$work/gh.log"
done
grep -Fq 'dist/ghs.rb --target abc123' "$work/gh.log"
if grep -Fq "dist/ghs-$VERSION.tar.gz" "$work/gh.log"; then
  printf 'Published an obsolete archive name\n' >&2
  exit 1
fi
: > "$work/gh.log"
status=0
(cd "$work" && RELEASE_TAG_EXISTS=1 bash -eo pipefail "$tmp/publish-step.sh") > "$work/output" 2>&1 || status=$?
[ "$status" -ne 0 ]
[ ! -s "$work/gh.log" ]
printf 'Platform upload and existing-tag refusal checks passed.\n'
