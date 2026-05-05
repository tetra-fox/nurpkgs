# grafana-dashboards

nix-packaged community dashboards from [grafana.com](https://grafana.com/grafana/dashboards/), with deterministic slug-derived uids and overridable datasource. pinned set lives in [`dashboards.json`](./dashboards.json). Each entry is exposed at `pkgs.grafana-dashboards.<slug>` as a single JSON file ready for grafana provisioning.

## adding a dashboard

append a `"<slug>": { "id": N }` entry to `dashboards.json`, then run the updater from repo root:

```sh
nix run .#update-grafana-dashboards
# or directly:
./pkgs/grafana-dashboards/update.sh
```

it queries `grafana.com/api/dashboards/{id}`, fills in `revision` + `hash`, writes them back. idempotent when everything is already at upstream latest.

## slug naming

the JSON key is the user-facing slug: nix attribute name, store filename, grafana provider name. default to grafana.com's URL slug. on collision with one already shipped, suffix with the grafana.com id (e.g. `node-exporter-1860`) to match grafana.com's URL convention (`/grafana/dashboards/1860-node-exporter-full/`).

## datasource

each dashboard has its `${DS_PROMETHEUS}` placeholder substituted to `"prometheus"` by default. override per-package via `.override`:

```nix
pkgs.grafana-dashboards.cadvisor.override { datasource = "Mimir"; }
```

`passthru.raw` exposes the unrewritten upstream JSON if you need to inspect what the original author shipped.

## uid rewriting

each dashboard's top-level `uid` is rewritten to a 14-char prefix of `sha256(slug)`. stable across revision bumps (slug stays, uid stays, grafana treats new revisions as updates not duplicates), insulates from upstream uid churn or same-uid collisions between authors, and avoids collisions among ours.

## lib helpers (`pkgs.grafana-dashboards.lib.*`)

| function | description |
| --- | --- |
| `mkDir packages` | bundle a list of dashboard packages into one directory, naming each file after its `passthru.grafanaSlug` |
| `mkProvider {name, path, ...}` | wrap a path into a grafana provisioning provider attrset. only `name` + `path` required. conventional defaults (`type = "file"`, `updateIntervalSeconds = 60`, `allowUiUpdates = true`, `foldersFromFilesStructure = true`) any caller can override. extra args (`folder`, `disableDeletion`, `editable`, ...) pass through to the result. nested provisioning options go in `options = {...}`, `path` always wins |
| `mkProviders specs` | map a list of provider specs to provider attrsets. each spec needs `name` + either `packages = [...]` (bundled via `mkDir`, used as path) or `path = "..."` (used directly). extra fields pass through to `mkProvider`. returns a list ready to assign to `services.grafana.provision.dashboards.settings.providers`. example: `[ { name = "metrics"; packages = [...]; } { name = "alerts"; path = ./alerts; folder = "Alerting"; } ]` |

## passthru

| field | description |
| --- | --- |
| `id` | grafana.com dashboard id |
| `revision` | pinned revision |
| `uid` | rewritten (`sha256(slug)[:14]`) |
| `raw` | unrewritten fetchurl derivation |
| `datasource` | the substituted datasource value |
| `grafanaSlug` | the JSON key |
| `updateScript` | path to `update.sh` (also exposed as the flake app `update-grafana-dashboards`) |
