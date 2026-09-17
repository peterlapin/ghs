#!/bin/bash
# Bash 3.2 treats expansion of an empty array as unset under nounset.
set -eo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
wrapper=${GHS_UNDER_TEST:-$root/bin/ghs}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/empty" "$tmp/work"

cat > "$tmp/bin/gh" <<'FAKE'
#!/bin/bash
printf 'call\n' >> "$GHS_TEST_CALLS"
printf '%s\0' "$@" >> "$GHS_TEST_ARGS"
if [ "$1" = pr ]; then
  exit "${GHS_TEST_BROWSER_EXIT:-0}"
fi
if [ "${GHS_TEST_IO:-}" = yes ]; then
  printf '%s\n' "$PWD" "$GHS_TEST_ENV" "$$" > "$GHS_TEST_CONTEXT"
  while IFS= read -r line; do printf '%s\n' "$line"; done
  printf 'upstream stderr\n' >&2
fi
exit "${GHS_TEST_EXIT:-0}"
FAKE
chmod +x "$tmp/bin/gh"
export GHS_TEST_ARGS="$tmp/args" GHS_TEST_CALLS="$tmp/calls"
export GHS_TEST_CONTEXT="$tmp/context" GHS_TEST_ENV='environment with spaces'
export PATH="$tmp/bin:$PATH"
# Every wrapper invocation runs outside a repository.
cd "$tmp/work"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

check() {
  input=$1
  shift
  printf '%s\0' stack "$@" "${extra[@]}" > "$tmp/expected"
  expected_calls=call
  if [ "${open_pr:-no}" = yes ]; then
    printf '%s\0' pr view --web >> "$tmp/expected"
    expected_calls=$'call\ncall'
  fi
  : > "$tmp/calls"
  : > "$tmp/args"
  "$wrapper" "$input" "${extra[@]}" > "$tmp/stdout" 2> "$tmp/stderr"
  cmp "$tmp/expected" "$tmp/args" || fail "arguments for $input"
  [ "$(cat "$tmp/calls")" = "$expected_calls" ] || fail "gh invocation count for $input"
  if [ -s "$tmp/stdout" ] || [ -s "$tmp/stderr" ]; then
    fail "extra output for $input"
  fi
}

# Test each mapping with no arguments, tricky arguments, and upstream help.
for mode in bare arguments help; do
  # shellcheck disable=SC2016
  case "$mode" in
    bare) extra=() ;;
    arguments) extra=('two words' '"double" and '\''single'\''' '' '--flag=value' '*' '; touch SENTINEL' '$(touch SENTINEL)' '`touch SENTINEL`' '$HOME' $'line\nbreak' '--' '-x') ;;
    help) extra=(--help) ;;
  esac
  check create add
  check c add
  check ls view --short
  check checkout checkout
  check co checkout
  check restack rebase --no-trunk
  check r rebase --no-trunk
  if [ "$mode" = help ]; then
    check submit submit --auto
    check s submit --auto
  else
    open_pr=yes check submit submit --auto
    open_pr=yes check s submit --auto
  fi
  check reshape modify
  for native in init add view switch up down top bottom trunk rebase sync push merge link modify unstack unknown update --unknown ''; do
    check "$native" "$native"
  done
done
[ ! -e SENTINEL ] || fail 'shell metacharacters were evaluated'

# Both help spellings skip the browser; arguments after -- are literal.
extra=(-h)
check submit submit --auto
check s submit --auto
extra=(-- --help)
open_pr=yes check submit submit --auto

for command in submit s; do
  : > "$tmp/calls"
  status=0
  GHS_TEST_EXIT=42 "$wrapper" "$command" || status=$?
  [ "$status" -eq 42 ] || fail 'submit exit status not preserved'
  [ "$(cat "$tmp/calls")" = call ] || fail 'browser opened after failed submit'

  : > "$tmp/calls"
  status=0
  GHS_TEST_BROWSER_EXIT=43 "$wrapper" "$command" || status=$?
  [ "$status" -eq 43 ] || fail 'browser exit status not preserved'
  [ "$(cat "$tmp/calls")" = $'call\ncall' ] || fail 'browser not invoked after submit'
done

# exec must preserve the process ID, cwd, environment and standard streams.
printf 'stdin with spaces and \\ backslash\n' > "$tmp/input"
GHS_TEST_IO=yes "$wrapper" view < "$tmp/input" > "$tmp/stdout" 2> "$tmp/stderr" &
child=$!
wait "$child"
printf '%s\n' "$PWD" "$GHS_TEST_ENV" "$child" > "$tmp/expected-context"
cmp "$tmp/context" "$tmp/expected-context"
cmp "$tmp/input" "$tmp/stdout"
[ "$(cat "$tmp/stderr")" = 'upstream stderr' ] || fail 'stderr not preserved'

# Submit leaves upstream streams connected while waiting to open the browser.
GHS_TEST_IO=yes "$wrapper" submit < "$tmp/input" > "$tmp/stdout" 2> "$tmp/stderr"
cmp "$tmp/input" "$tmp/stdout"
[ "$(cat "$tmp/stderr")" = 'upstream stderr' ] || fail 'submit stderr not preserved'

PATH="$tmp/empty" "$wrapper" > "$tmp/help"
PATH="$tmp/empty" "$wrapper" --help > "$tmp/help-flag"
cmp "$tmp/help" "$tmp/help-flag"
grep -q 'Usage: ghs' "$tmp/help"
grep -q 'rebase --no-trunk' "$tmp/help"
PATH="$tmp/empty" "$wrapper" --version > "$tmp/version"
grep -Eq '^ghs [0-9]+\.[0-9]+\.[0-9]+$' "$tmp/version"
status=0
PATH="$tmp/empty" "$wrapper" create > "$tmp/stdout" 2> "$tmp/stderr" || status=$?
[ "$status" -eq 127 ] || fail 'missing gh status'
[ ! -s "$tmp/stdout" ] || fail 'missing gh error went to stdout'
grep -q 'GitHub CLI (gh) is required' "$tmp/stderr"
grep -q 'brew install gh' "$tmp/stderr"
printf 'Wrapper tests passed.\n'
