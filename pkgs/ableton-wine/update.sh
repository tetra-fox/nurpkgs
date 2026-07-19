#!/usr/bin/env bash
set -euo pipefail

# bumps the shibco/ableton-linux pin, and with it the giang17 wine base and
# pipeasio version when the kit moves them. run by hand and build locally
# before pushing: ableton-wine is excluded from CI builds (preferLocalBuild),
# so an automated bump would land uncompiled

PKG_DIR="pkgs/ableton-wine"
PKG="$PKG_DIR/package.nix"
if [[ ! -f "$PKG" ]]; then
  echo "must be run from nurpkgs repo root (looked for $PKG)" >&2
  exit 1
fi

# track main, not release tags: kit content the packages ship (launcher,
# detection libs, setsyscolors.exe) can land after the release commit that
# stamps VERSION
rev=$(git ls-remote https://github.com/shibco/ableton-linux refs/heads/main | cut -f1)
cur_rev=$(sed -n 's/^    rev = "\(.*\)";$/\1/p' "$PKG")
if [[ "$rev" == "$cur_rev" ]]; then
  echo "already at shibco/ableton-linux ${rev:0:8}"
  exit 0
fi

old_version=$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$PKG")
version=$(curl -fsSL "https://raw.githubusercontent.com/shibco/ableton-linux/$rev/VERSION")
hash=$(nix-prefetch-git --quiet --url https://github.com/shibco/ableton-linux --rev "$rev" \
  | jq -er '.hash')

# the kit names its vendored artifacts by version; read both from the tree
# so the pins move together with the series
vendor=$(curl -fsSL "https://api.github.com/repos/shibco/ableton-linux/contents/vendor?ref=$rev" \
  | jq -er '.[].name')
base_short=$(sed -n 's/^wine-base-\([0-9a-f]*\)\.tar\.zst$/\1/p' <<<"$vendor")
pipeasio=$(sed -n 's/^pipeasio-\([0-9.]*\)\.tar\.gz$/\1/p' <<<"$vendor")
[[ -n "$base_short" && -n "$pipeasio" ]] || {
  echo "cannot read wine-base/pipeasio versions from the kit's vendor/ listing" >&2
  exit 1
}

# the wine base only moves on a series rebase; skip the heavy prefetch otherwise.
# indentation disambiguates the two fetchFromGitHub blocks: the kit pins at
# 4 spaces, the wine src at 6
base_rev=$(curl -fsSL "https://api.github.com/repos/giang17/wine/commits/$base_short" \
  | jq -er '.sha')
cur_base=$(sed -n 's/^      rev = "\(.*\)";$/\1/p' "$PKG")
if [[ "$base_rev" != "$cur_base" ]]; then
  echo "wine base moved: ${cur_base:0:8} -> ${base_rev:0:8} (series rebase; check patches/BASE.txt and the comments here)"
  base_hash=$(nix-prefetch-git --quiet --url https://github.com/giang17/wine --rev "$base_rev" \
    | jq -er '.hash')
  sed -i \
    -e "s|^      rev = \".*\";|      rev = \"$base_rev\";|" \
    -e "s|^      hash = \".*\";|      hash = \"$base_hash\";|" \
    "$PKG"
fi

sed -i \
  -e "s|^  version = \".*\";|  version = \"$version\";|" \
  -e "s|^  pipeasioVersion = \".*\";|  pipeasioVersion = \"$pipeasio\";|" \
  -e "s|^    rev = \".*\";|    rev = \"$rev\";|" \
  -e "s|^    hash = \".*\";|    hash = \"$hash\";|" \
  "$PKG"

echo "ableton-wine: $old_version -> $version (now build it locally before pushing)"
