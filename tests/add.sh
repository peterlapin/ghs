#!/bin/bash
set -eo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
wrapper=${GHS_UNDER_TEST:-$root/build/ghs}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'FAKE'
#!/bin/bash
printf '%s\0' "$@" >> "$GHS_ADD_ARGS"
git symbolic-ref --short HEAD >> "$GHS_ADD_BRANCHES"
if [ "${GHS_ADD_ECHO:-}" = yes ]; then
  while IFS= read -r line; do printf '%s\n' "$line"; done
fi
exit "${GHS_ADD_EXIT:-0}"
FAKE
chmod +x "$tmp/bin/gh"
export GHS_ADD_ARGS="$tmp/args" GHS_ADD_BRANCHES="$tmp/branches"
export PATH="$tmp/bin:$PATH"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
new_repo() {
  repo=$(mktemp -d "$tmp/repo.XXXXXX")
  cd "$repo"
  git init -q -b main
  git config user.name 'GHS tests'
  git config user.email 'ghs@example.invalid'
  printf 'base\n' > tracked
  git add tracked
  git commit -qm base
  git checkout -qb A
  git commit -qm A --allow-empty
  cat > .git/gh-stack <<'JSON'
{"schemaVersion":1,"stacks":[{"trunk":{"branch":"main"},"branches":[{"branch":"A"}]}]}
JSON
}
run_add() {
  : > "$tmp/args"
  : > "$tmp/branches"
  status=0
  "$wrapper" add > "$tmp/stdout" 2> "$tmp/stderr" || status=$?
}
expect_call() {
  printf '%s\0' stack add "$@" > "$tmp/expected"
  cmp "$tmp/expected" "$tmp/args" || fail 'wrong add arguments'
}
expect_failure() {
  [ "$status" -ne 0 ] || fail 'expected failure'
  [ ! -s "$tmp/args" ] || fail 'called gh after validation failure'
}

# Adopt from the nearest tracked ancestor without changing commits or metadata.
new_repo
git branch lower main
cat > "$tmp/state" <<'JSON'
{"schemaVersion":1,"stacks":[{"trunk":{"branch":"main"},"branches":[{"branch":"lower"},{"branch":"A"}]}]}
JSON
cp "$tmp/state" .git/gh-stack
git checkout -qb B
git commit -qm B --allow-empty
before=$(git rev-parse HEAD)
run_add < /dev/null
[ "$status" -eq 0 ] || fail 'automatic adoption failed'
expect_call -- B
[ "$(cat "$tmp/branches")" = A ] || fail 'did not add from nearest parent'
[ "$(git branch --show-current)" = B ] || fail 'did not return to original branch'
[ "$(git rev-parse HEAD)" = "$before" ] || fail 'rewrote branch history'
cmp "$tmp/state" .git/gh-stack || fail 'wrapper wrote upstream metadata'

GHS_ADD_EXIT=42 run_add < /dev/null
[ "$status" -eq 42 ] || fail 'adoption failure status lost'
[ "$(git branch --show-current)" = B ] || fail 'failed adoption left parent checked out'
printf 'dirty\n' >> tracked
run_add < /dev/null
expect_failure
grep -q 'Commit or stash' "$tmp/stderr"
git restore tracked

# An inferred parent in the middle must never attach to the top instead.
git checkout -qb middle-child lower
run_add < /dev/null
expect_failure
grep -q 'middle of a stack' "$tmp/stderr"
[ "$(git branch --show-current)" = middle-child ] || fail 'middle-parent failure switched branches'

# Equal tips in separate stacks need a choice; cancellation has no side effects.
new_repo
git branch other A
cat > "$tmp/state" <<'JSON'
{"schemaVersion":1,"stacks":[{"trunk":{"branch":"main"},"branches":[{"branch":"A"}]},{"trunk":{"branch":"main"},"branches":[{"branch":"other"}]}]}
JSON
cp "$tmp/state" .git/gh-stack
git checkout -qb B
run_add < /dev/null
expect_failure
run_add <<< 'not-a-parent'
expect_failure
run_add <<< other
[ "$status" -eq 0 ] || fail 'explicit parent selection failed'
expect_call -- B
[ "$(cat "$tmp/branches")" = other ] || fail 'ignored parent selection'

# Parent moved forward since branching: no guess, allow explicit selection.
new_repo
git branch B
git commit -qm 'A moved' --allow-empty
git checkout -q B
run_add <<< A
[ "$status" -eq 0 ] || fail 'explicit diverged parent failed'
expect_call -- B

# Collect all input before invoking gh; leave staging and commits to upstream.
new_repo
printf 'staged\n' >> tracked
git add tracked
printf 'unstaged\n' >> tracked
printf 'new\n' > untracked
git diff > "$tmp/unstaged"
git diff --cached > "$tmp/staged"
run_add <<'INPUT'
1
feature/staged
Message with $HOME and "quotes"
INPUT
[ "$status" -eq 0 ] || fail 'staged flow failed'
# shellcheck disable=SC2016
expect_call -m 'Message with $HOME and "quotes"' -- feature/staged
[ "$(cat "$tmp/branches")" = A ] || fail 'guided create switched early'
git diff > "$tmp/actual"
cmp "$tmp/unstaged" "$tmp/actual"
git diff --cached > "$tmp/actual"
cmp "$tmp/staged" "$tmp/actual"
run_add <<'INPUT'
all
feature/all
Include all changes
INPUT
[ "$status" -eq 0 ] || fail 'all flow failed'
expect_call -A -m 'Include all changes' -- feature/all
GHS_ADD_ECHO=yes run_add <<'INPUT'
1
feature/stdin
Keep input available
input for the child
INPUT
[ "$status" -eq 0 ]
[ "$(cat "$tmp/stdout")" = 'input for the child' ] || fail 'prompts swallowed child stdin'
run_add <<< invalid
expect_failure
run_add <<< staged
expect_failure
run_add <<'INPUT'
1
bad branch name
INPUT
expect_failure
run_add <<'INPUT'
1
A
INPUT
expect_failure
run_add <<'INPUT'
1
HEAD
INPUT
expect_failure
run_add <<'INPUT'
1
valid-name
   
INPUT
expect_failure
git reset -q
run_add <<< staged
expect_failure
grep -q 'No staged changes' "$tmp/stderr"

# Preserve upstream's empty-tip behavior instead of asking for an ignored name.
new_repo
git reset --hard -q main
printf 'first change\n' >> tracked
git add tracked
run_add <<'INPUT'
1
First commit on A
INPUT
[ "$status" -eq 0 ] || fail 'empty-tip flow failed'
expect_call -m 'First commit on A' -- A
grep -q 'no new branch is created' "$tmp/stderr"
if grep -q 'New branch name' "$tmp/stderr"; then fail 'asked for ignored branch name'; fi

# Metadata and repository errors never turn into an add or a new stack.
new_repo
printf '{broken' > .git/gh-stack
run_add < /dev/null
expect_failure
printf '{"schemaVersion":2,"stacks":[]}' > .git/gh-stack
run_add < /dev/null
expect_failure
rm .git/gh-stack
run_add < /dev/null
expect_failure
git checkout -q --detach
run_add < /dev/null
expect_failure

# Shared metadata is found from linked worktrees too.
new_repo
git checkout -q main
git worktree add -q -b B "$tmp/worktree" A
cd "$tmp/worktree"
run_add < /dev/null
[ "$status" -eq 0 ] || fail 'linked-worktree adoption failed'
expect_call -- B
[ "$(git branch --show-current)" = B ] || fail 'worktree branch not restored'

# Guided add only needs Git and gh on PATH: no jq or language runtime.
mkdir "$tmp/no-jq"
ln -s "$(command -v git)" "$tmp/no-jq/git"
ln -s "$tmp/bin/gh" "$tmp/no-jq/gh"
PATH="$tmp/no-jq" run_add < /dev/null
[ "$status" -eq 0 ] || fail 'guided add required a runtime or jq'
expect_call -- B
printf 'Guided add tests passed.\n'
