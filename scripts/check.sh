#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

[ -z "$(gofmt -l ./*.go)" ] || { printf 'Run gofmt on the Go sources.\n' >&2; exit 1; }
go vet ./...
go test -race ./...
go build -trimpath -buildvcs=false -o build/ghs .
for script in scripts/*.sh tests/*.sh; do
  bash -n "$script"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh tests/*.sh
else
  printf 'ShellCheck unavailable; skipped locally (required in CI).\n'
fi
bash tests/ghs.sh
bash tests/add.sh
bash tests/signals.sh
bash tests/release.sh
bash scripts/package.sh
IFS= read -r version < VERSION
[ "$(build/ghs --version)" = "ghs $version" ]
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for platform in darwin-arm64 darwin-amd64 linux-arm64 linux-amd64; do
  cp "dist/ghs-$version-$platform.tar.gz" "$tmp/"
done
cp dist/ghs.rb "$tmp/ghs.rb"
bash scripts/package.sh
cmp "$tmp/ghs.rb" dist/ghs.rb
for platform in darwin-arm64 darwin-amd64 linux-arm64 linux-amd64; do
  name="ghs-$version-$platform"
  archive="$name.tar.gz"
  cmp "$tmp/$archive" "dist/$archive"
  (cd dist && shasum -a 256 -c "$archive.sha256")
  tar -tzf "dist/$archive" > "$tmp/files"
  printf '%s\n' "$name/bin/ghs" "$name/README.md" "$name/LICENSE" > "$tmp/expected"
  cmp "$tmp/expected" "$tmp/files"
  tar -xzf "dist/$archive" -C "$tmp"
  go version -m "$tmp/$name/bin/ghs" > "$tmp/build-info"
  grep -Fq "GOOS=${platform%-*}" "$tmp/build-info"
  grep -Fq "GOARCH=${platform#*-}" "$tmp/build-info"
  grep -Fq 'CGO_ENABLED=0' "$tmp/build-info"
  read -r checksum _ < "dist/$archive.sha256"
  grep -Fq "sha256 \"$checksum\"" dist/ghs.rb
  grep -Fq "releases/download/v$version/$archive" dist/ghs.rb
done
host="$(go env GOHOSTOS)-$(go env GOHOSTARCH)"
GHS_UNDER_TEST="$tmp/ghs-$version-$host/bin/ghs" bash tests/ghs.sh
GHS_UNDER_TEST="$tmp/ghs-$version-$host/bin/ghs" bash tests/add.sh
GHS_UNDER_TEST="$tmp/ghs-$version-$host/bin/ghs" bash tests/signals.sh
ruby -c dist/ghs.rb
if command -v brew >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_DEVELOPER=1 \
    brew ruby tests/formula.rb
else
  printf 'Homebrew unavailable; formula execution skipped.\n'
fi
printf 'Packaging checks passed.\n'
