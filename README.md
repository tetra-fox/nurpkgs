# nurpkgs

## Packages

- `surge-dm` — [Surge](https://github.com/SurgeDM/Surge), a TUI download manager
- `apple-color-emoji` — Apple Color Emoji repacked for Linux (via [samuelngs/apple-emoji-ttf](https://github.com/samuelngs/apple-emoji-ttf))
- `grafana-dashboards.*` — community dashboards from [grafana.com](https://grafana.com/grafana/dashboards/), uid-rewritten for stable provisioning, `.override`-able datasource. Bundling helpers live in `pkgs.grafana-dashboards.lib.*`. See [`pkgs/grafana-dashboards/README.md`](./pkgs/grafana-dashboards/README.md).

## NixOS modules

- `grafana-dashboards` — declares `services.grafana-dashboards.{community, extras}` and wires the bundled provider into `services.grafana.provision.dashboards.settings.providers`. Auto-discovered from `./modules/`.
- `default` — all modules in `./modules/`.

## Apps

- `update-grafana-dashboards` — bumps `pkgs/grafana-dashboards/dashboards.json` against grafana.com. Run via `nix run .#update-grafana-dashboards` from the repo root.

## Usage

First, add as a flake input

```nix
inputs = {
  tetra-nurpkgs = {
    url = "github:tetra-fox/nurpkgs";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### As an overlay

```nix
{ inputs, ... }: {
  nixpkgs.overlays = [ inputs.tetra-nurpkgs.overlays.default ];
}
```

### Directly

```nix
environment.systemPackages = [
  inputs.tetra-nurpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.surge-dm
];
```

### As a NixOS module

```nix
{ inputs, ... }: {
  imports = [ inputs.tetra-nurpkgs.nixosModules.grafana-dashboards ];

  services.grafana-dashboards.community = with pkgs.grafana-dashboards; [
    cadvisor
    node-exporter-full
    (nvidia-gpu.override { datasource = "Mimir"; })
  ];
}
```

### From the CLI

```sh
nix build github:tetra-fox/nurpkgs#surge-dm
```

> [!IMPORTANT]
> `apple-color-emoji` is `unfreeRedistributable`. You'll need `allowUnfree` (or a predicate) on your nixpkgs config.
