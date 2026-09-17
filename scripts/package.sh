#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

IFS= read -r version < VERSION
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid version\n' >&2; exit 1; }
mkdir -p dist
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
case "$(tar --version)" in
  *bsdtar*) owners=(--uid 0 --gid 0 --uname root --gname root) ;;
  *) owners=(--owner=root --group=root) ;;
esac
sed "s/@VERSION@/$version/g" Formula/ghs.rb.in > "$stage/formula"
for platform in darwin-arm64 darwin-amd64 linux-arm64 linux-amd64; do
  name="ghs-$version-$platform"
  mkdir -p "$stage/$name/bin"
  CGO_ENABLED=0 GOOS="${platform%-*}" GOARCH="${platform#*-}" \
    go build -trimpath -buildvcs=false -ldflags='-s -w -buildid=' -o "$stage/$name/bin/ghs" .
  cp README.md LICENSE "$stage/$name/"
  chmod 755 "$stage/$name/bin/ghs"
  chmod 644 "$stage/$name/README.md" "$stage/$name/LICENSE"
  TZ=UTC touch -t 200001010000 "$stage/$name/bin/ghs" "$stage/$name/README.md" "$stage/$name/LICENSE"
  COPYFILE_DISABLE=1 tar --format=ustar "${owners[@]}" -cf - -C "$stage" \
    "$name/bin/ghs" "$name/README.md" "$name/LICENSE" | gzip -n > "dist/$name.tar.gz"
  (cd dist && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")
  read -r checksum _ < "dist/$name.tar.gz.sha256"
  sed "s/@SHA256-$platform@/$checksum/g" "$stage/formula" > "$stage/next-formula"
  mv "$stage/next-formula" "$stage/formula"
  printf 'Built dist/%s.tar.gz and checksum\n' "$name"
done
cp "$stage/formula" dist/ghs.rb
printf 'Generated dist/ghs.rb\n'
