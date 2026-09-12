#!/usr/bin/env bash
set -euo pipefail

# Also usable independently to package an already signed release archive.
if [[ $# != 3 || ! -d "$1" || "$2" != *.dmg ]]; then
  echo "Usage: scripts/package-dmg.sh APP_PATH OUTPUT.dmg VOLUME_NAME" >&2
  exit 1
fi
app_path="$1"
output_path="$2"
volume_name="$3"
stage="$(mktemp -d -t codexbar-dmg)"
trap 'rm -rf "$stage"' EXIT

codesign --verify --deep --strict "$app_path"
mkdir -p "$stage/root" "$(dirname "$output_path")"
ditto --norsrc "$app_path" "$stage/root/$(basename "$app_path")"
ln -s /Applications "$stage/root/Applications"
# Build in staging so a failed attempt cannot replace a valid existing image.
hdiutil create -volname "$volume_name" -srcfolder "$stage/root" \
  -format UDZO -fs HFS+ "$stage/package.dmg"
hdiutil verify "$stage/package.dmg"
mv -f "$stage/package.dmg" "$output_path"
