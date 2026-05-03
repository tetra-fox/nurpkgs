{
  description = "tetra's NUR repository";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
  in {
    legacyPackages = forAllSystems (system:
      import ./default.nix {
        pkgs = import nixpkgs {inherit system;};
      });
    packages =
      forAllSystems (system:
        nixpkgs.lib.filterAttrs (_: v: nixpkgs.lib.isDerivation v) self.legacyPackages.${system});
    overlays.default = import ./overlay.nix;

    apps = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      update-grafana-dashboards = {
        type = "app";
        program = toString (pkgs.writeShellScript "update-grafana-dashboards" ''
          script="$PWD/pkgs/grafana-dashboards/update.sh"
          if [[ ! -x "$script" ]]; then
            echo "must be run from nurpkgs repo root (looked for $script)" >&2
            exit 1
          fi
          exec "$script" "$@"
        '');
      };
    });
  };
}
