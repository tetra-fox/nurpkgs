#!/usr/bin/env bash
set -euo pipefail

DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
JSON="$DIR/dashboards.json"

[[ -f "$JSON" ]] || { echo "missing $JSON" >&2; exit 1; }

bumps=()

while IFS= read -r slug; do
  id="$(jq -r --arg s "$slug" '.[$s].id' "$JSON")"
  current_rev="$(jq -r --arg s "$slug" '.[$s].revision // 0' "$JSON")"

  if [[ -z "$id" || "$id" == "null" ]]; then
    echo "${slug}: missing id, skipping" >&2
    continue
  fi

  meta="$(curl -fsSL "https://grafana.com/api/dashboards/${id}")"
  latest_rev="$(jq -r '.revision' <<<"$meta")"

  if [[ "$current_rev" == "$latest_rev" ]]; then
    echo "${slug}: already at revision ${latest_rev}"
    continue
  fi

  url="https://grafana.com/api/dashboards/${id}/revisions/${latest_rev}/download"
  hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r '.hash')"

  tmp="$(mktemp)"
  jq --arg s "$slug" --argjson r "$latest_rev" --arg h "$hash" \
     '.[$s].revision = $r | .[$s].hash = $h' \
     "$JSON" > "$tmp"
  mv "$tmp" "$JSON"

  bumps+=("${slug}: ${current_rev} -> ${latest_rev}")
  echo "${slug}: ${current_rev} -> ${latest_rev}"
done < <(jq -r 'keys[]' "$JSON")

# CI consumes these to build the commit message without inspecting the diff.
if [[ -n "${GITHUB_OUTPUT:-}" && ${#bumps[@]} -gt 0 ]]; then
  {
    echo "commit_subject=bumped ${#bumps[@]} dashboard(s)"
    echo "commit_body<<COMMIT_BODY_EOF"
    printf '%s\n' "${bumps[@]}"
    echo "COMMIT_BODY_EOF"
  } >> "$GITHUB_OUTPUT"
fi
