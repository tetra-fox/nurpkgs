{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.grafana-dashboards;
  hasOverlay = pkgs ? grafana-dashboards;
in {
  options.services.grafana-dashboards = {
    community = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Grafana community dashboards to provision. Each entry is a
        `pkgs.grafana-dashboards.<slug>` package (or
        `.override { datasource = "..."; }` for non-default datasource).
        All entries are bundled into a single grafana provider named
        "community". Silent no-op on hosts where grafana isn't enabled.
      '';
    };

    extras = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = ''
        Extra directories of one-off local dashboard JSONs. Each becomes
        its own grafana provider alongside the bundled community set.
      '';
    };
  };

  # the bundling helpers live in the overlay-attached package set, so guard
  # both the assertion and the assignment. mkIf keeps the rhs lazy when the
  # overlay isn't applied, so the assertion fires with its own message
  # instead of an opaque "attribute 'grafana-dashboards' missing".
  config = {
    assertions = [
      {
        assertion = hasOverlay;
        message = ''
          services.grafana-dashboards needs the tetra-nurpkgs overlay applied
          for `pkgs.grafana-dashboards.lib.*` to exist. add:

            nixpkgs.overlays = [ inputs.tetra-nurpkgs.overlays.default ];
        '';
      }
    ];

    services.grafana.provision.dashboards.settings.providers = lib.mkIf hasOverlay (
      pkgs.grafana-dashboards.lib.mkProviders (
        lib.optional (cfg.community != []) {
          name = "community";
          packages = cfg.community;
        }
        ++ lib.imap0 (i: path: {
          name = "extra-${toString i}";
          inherit path;
        })
        cfg.extras
      )
    );
  };
}
