#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
wrapper=${GHS_UNDER_TEST:-$root/build/ghs}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
mkdir "$tmp/bin" "$tmp/repo"
cat > "$tmp/bin/gh" <<'FAKE'
#!/bin/bash
if [ "$1" = pr ]; then
  touch "$GHS_BROWSER_OPENED"
  exit 0
fi
trap 'exit 0' INT TERM
printf '%s\n' ready > "$GHS_SIGNAL_READY"
while :; do sleep 0.05; done
FAKE
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GHS_SIGNAL_READY="$tmp/ready" GHS_BROWSER_OPENED="$tmp/browser"
cd "$tmp/repo"
git init -q -b main
git config user.name 'GHS signal test'
git config user.email 'signal@example.invalid'
git commit -qm base --allow-empty
git checkout -qb A
git commit -qm A --allow-empty
git checkout -qb B
cat > .git/gh-stack <<'JSON'
{"schemaVersion":1,"stacks":[{"trunk":{"branch":"main"},"branches":[{"branch":"A"}]}]}
JSON
for command in add submit; do
  for signal in INT TERM; do
    rm -f "$tmp/ready"
    "$wrapper" "$command" > "$tmp/stdout" 2> "$tmp/stderr" &
    child=$!
    # Bound every case, including regressions in signal handling.
    (sleep 10; kill -KILL "$child" 2>/dev/null || true) &
    watchdog=$!
    for ((attempt=0; attempt<100; attempt++)); do
      [ ! -e "$tmp/ready" ] || break
      sleep 0.05
    done
    [ -e "$tmp/ready" ] || { kill "$child"; printf 'Child did not start\n' >&2; exit 1; }
    kill -"$signal" "$child"
    status=0
    wait "$child" || status=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    expected=130
    [ "$signal" != TERM ] || expected=143
    [ "$status" -eq "$expected" ] || { printf 'Wrong signal status: %s\n' "$status" >&2; exit 1; }
    [ "$(git branch --show-current)" = B ]
    [ ! -e "$tmp/browser" ]
  done
done
printf 'Signal forwarding, branch recovery, and browser cancellation checks passed.\n'
