{
  lib,
  fetchurl,
  jq,
  runCommand,
}: let
  dashboards = lib.importJSON ./dashboards.json;

  mkDashboard = slug: {
    id,
    revision,
    hash,
  }: let
    raw = fetchurl {
      name = "grafana-dashboard-${slug}.raw.json";
      url = "https://grafana.com/api/dashboards/${toString id}/revisions/${toString revision}/download";
      inherit hash;
    };

    # deterministic uids: upstream dashboard `uid`s may collide with other dashboards.
    # to solve this, derive a stable, slug-keyed uid so grafana provisioning is
    # idempotent across revision bumps and authors
    uid = builtins.substring 0 14 (builtins.hashString "sha256" slug);
  in
    runCommand "grafana-dashboard-${slug}.json" {
      nativeBuildInputs = [jq];

      passthru = {
        inherit id revision uid raw;
        grafanaSlug = slug;
        updateScript = ./update.sh;
      };

      meta = {
        description = "Grafana community dashboard: ${slug}";
        homepage = "https://grafana.com/grafana/dashboards/${toString id}/";
      };
    } ''
      jq --arg uid '${uid}' '.uid = $uid' ${raw} > $out
    '';
in
  lib.recurseIntoAttrs (lib.mapAttrs mkDashboard dashboards)
