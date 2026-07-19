#!/usr/bin/env bash
set -euo pipefail

# nix-update --use-update-script runs this with cwd at the repo root
PKG_DIR="pkgs/vrcx-nightly"
PKG="$PKG_DIR/package.nix"
if [[ ! -f "$PKG" ]]; then
  echo "must be run from nurpkgs repo root (looked for $PKG)" >&2
  exit 1
fi

# upstream cuts nightlies on its own channel, not as vrcx-team/VRCX git tags or
# GitHub releases. the proxy hands us the tag string (which the app uses as its
# whole Version file) and the exact commit it was built from. track that instead
# of the tip of main, so the pinned build corresponds to a real published nightly
latest=$(curl -fsSL https://api0.vrcx.app/releases/nightly/latest)
version=$(jq -er '.tag_name' <<<"$latest")
rev=$(jq -er '.target_commitish' <<<"$latest")

# fetchFromGitHub owner/repo stay vrcx-team/VRCX; the nightly commit is reachable
# there (shared history with the fork the release points at)
hash=$(nix-prefetch-git --quiet --url https://github.com/vrcx-team/VRCX --rev "$rev" \
  | jq -er '.hash')

# rewrite the three pinned fields. anchored to the attr names so we don't touch
# npmDepsHash or the backend's own hashes
sed -i \
  -e "s|^    version = \".*\";|    version = \"$version\";|" \
  -e "s|^      rev = \".*\";|      rev = \"$rev\";|" \
  -e "s|^      hash = \".*\";|      hash = \"$hash\";|" \
  "$PKG"

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
