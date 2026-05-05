{
  lib,
  fetchurl,
  jq,
  gnused,
  runCommand,
}: let
  dashboards = lib.importJSON ./dashboards.json;

  mkDashboard = slug: {
    id,
    revision,
    hash,
  }:
    lib.makeOverridable ({datasource ? "prometheus"}: let
      raw = fetchurl {
        name = "grafana-dashboard-${slug}.raw.json";
        url = "https://grafana.com/api/dashboards/${toString id}/revisions/${toString revision}/download";
        inherit hash;
      };

      uid = builtins.substring 0 14 (builtins.hashString "sha256" slug);
    in
      runCommand "grafana-dashboard-${slug}.json" {
        nativeBuildInputs = [jq gnused];

        passthru = {
          inherit id revision uid raw datasource;
          grafanaSlug = slug;
          updateScript = ./update.sh;
        };

        meta = {
          description = "Grafana community dashboard: ${slug}";
          homepage = "https://grafana.com/grafana/dashboards/${toString id}/";
        };
      } ''
        jq --arg uid '${uid}' '.uid = $uid' ${raw} \
          | sed 's|''${DS_PROMETHEUS}|${datasource}|g' \
          > $out
      '') {};

  mkDir = packages:
    runCommand "grafana-community-dashboards" {} (''
        mkdir -p $out
      ''
      + lib.concatMapStringsSep "\n" (p: ''
        cp ${p} $out/${p.passthru.grafanaSlug}.json
      '')
      packages);

  mkProvider = {
    name,
    path,
    options ? {},
    ...
  } @ args:
    {
      type = "file";
      updateIntervalSeconds = 60;
      allowUiUpdates = true;
    }
    // (removeAttrs args ["path" "options"])
    // {
      inherit name;
      options =
        {
          foldersFromFilesStructure = true;
        }
        // options
        // {inherit path;};
    };

  mkProviders = specs:
    map (spec:
      if spec ? packages
      then mkProvider (removeAttrs spec ["packages"] // {path = mkDir spec.packages;})
      else mkProvider spec)
    specs;
in
  lib.recurseIntoAttrs (
    lib.mapAttrs mkDashboard dashboards
    // {
      lib = {inherit mkDir mkProvider mkProviders;};
    }
  )
