#!/usr/bin/env bash
set -euo pipefail

REPO="samuelngs/apple-emoji-ttf"
ASSET="AppleColorEmoji-Linux.ttf"
NIX_FILE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/package.nix"

release=$(gh release view --repo "$REPO" --json tagName,assets)
tag=$(jq -r '.tagName' <<<"$release")
url=$(jq -r --arg name "$ASSET" '.assets[] | select(.name == $name) | .url' <<<"$release")

current=$(grep -oP 'version = "\K[^"]+' "$NIX_FILE")
if [[ "$current" == "$tag" ]]; then
  echo "already at $tag"
  exit 0
fi

hash=$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r '.hash')

sed -i -E "
  s|version = \".*\";|version = \"$tag\";|
  s|url = \".*\";|url = \"$url\";|
  s|hash = \".*\";|hash = \"$hash\";|
" "$NIX_FILE"

echo "updated $current -> $tag"
