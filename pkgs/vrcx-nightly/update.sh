#!/usr/bin/env bash
set -euo pipefail

# nix-update --use-update-script runs this with cwd at the repo root
PKG_DIR="pkgs/vrcx-nightly"
if [[ ! -f "$PKG_DIR/package.nix" ]]; then
  echo "must be run from nurpkgs repo root (looked for $PKG_DIR/package.nix)" >&2
  exit 1
fi

# bump version, rev and src hash to the latest master commit
nix run nixpkgs#nix-update -- --flake --version=branch --src-only vrcx-nightly

# upstream's lockfile is missing resolved/integrity fields for entries npm
# installed from a warm cache, which the nix npm fetcher cannot work with.
# vendor a copy with those fields restored from the registry
src=$(nix-build default.nix -A vrcx-nightly.src --no-out-link)
install -m644 "$src/package-lock.json" "$PKG_DIR/package-lock.json"
nix run nixpkgs#npm-lockfile-fix -- "$PKG_DIR/package-lock.json"

# untracked files are invisible to flake eval, relevant on a fresh bootstrap
git add --intent-to-add "$PKG_DIR/package-lock.json"

# recompute npmDepsHash and regenerate deps.json against the new source
nix run nixpkgs#nix-update -- --flake --version=skip --no-src vrcx-nightly
