#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(bin/ghs --version)
version=${version#ghs }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid version\n' >&2; exit 1; }
name="ghs-$version"
mkdir -p dist
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$name/bin"
cp bin/ghs "$stage/$name/bin/ghs"
cp README.md LICENSE "$stage/$name/"
chmod 755 "$stage/$name/bin/ghs"
chmod 644 "$stage/$name/README.md" "$stage/$name/LICENSE"
TZ=UTC touch -t 200001010000 "$stage/$name/bin/ghs" "$stage/$name/README.md" "$stage/$name/LICENSE"

# Fixed ordering, timestamps, ownership and gzip header; no formula in the archive.
case "$(tar --version)" in
  *bsdtar*) owners=(--uid 0 --gid 0 --uname root --gname root) ;;
  *) owners=(--owner=root --group=root) ;;
esac
COPYFILE_DISABLE=1 tar --format=ustar "${owners[@]}" -cf - -C "$stage" \
  "$name/bin/ghs" "$name/README.md" "$name/LICENSE" | gzip -n > "dist/$name.tar.gz"
(cd dist && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")
read -r checksum _ < "dist/$name.tar.gz.sha256"
sed -e "s/@VERSION@/$version/g" -e "s/@SHA256@/$checksum/g" Formula/ghs.rb.in > dist/ghs.rb
printf 'Built dist/%s.tar.gz, checksum and dist/ghs.rb\n' "$name"
