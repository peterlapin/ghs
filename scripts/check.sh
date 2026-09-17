#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in bin/ghs scripts/*.sh tests/*.sh; do
  bash -n "$script"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck bin/ghs scripts/*.sh tests/*.sh
else
  printf 'ShellCheck unavailable; skipped locally (required in CI).\n'
fi
bash tests/ghs.sh
bash tests/release.sh
bash scripts/package.sh
version=$(bin/ghs --version)
archive="ghs-${version#ghs }.tar.gz"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "dist/$archive" "$tmp/first.tar.gz"
bash scripts/package.sh
cmp "$tmp/first.tar.gz" "dist/$archive"
(cd dist && shasum -a 256 -c "$archive.sha256")
tar -tzf "dist/$archive" > "$tmp/files"
printf '%s\n' "${archive%.tar.gz}/bin/ghs" "${archive%.tar.gz}/README.md" "${archive%.tar.gz}/LICENSE" > "$tmp/expected"
cmp "$tmp/expected" "$tmp/files"
tar -xzf "dist/$archive" -C "$tmp"
GHS_UNDER_TEST="$tmp/${archive%.tar.gz}/bin/ghs" bash tests/ghs.sh
read -r checksum _ < "dist/$archive.sha256"
grep -Fq "sha256 \"$checksum\"" dist/ghs.rb
grep -Fq "releases/download/v${version#ghs }/$archive" dist/ghs.rb
ruby -c dist/ghs.rb
if command -v brew >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_DEVELOPER=1 \
    brew ruby tests/formula.rb
else
  printf 'Homebrew unavailable; formula execution skipped.\n'
fi
printf 'Packaging checks passed.\n'
