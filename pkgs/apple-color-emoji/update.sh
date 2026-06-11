#!/usr/bin/env bash
set -euo pipefail

REPO="samuelngs/apple-emoji-ttf"
ASSET="AppleColorEmoji-Linux.ttf"

# resolving via BASH_SOURCE breaks under nix-update --use-update-script,
# which runs a store copy of this script. it does set cwd to the repo root
NIX_FILE="pkgs/apple-color-emoji/package.nix"
if [[ ! -f "$NIX_FILE" ]]; then
  echo "must be run from nurpkgs repo root (looked for $NIX_FILE)" >&2
  exit 1
fi

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
