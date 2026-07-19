# nurpkgs

## Packages

- `surge-dm` — [Surge](https://github.com/SurgeDM/Surge), a TUI download manager
- `vrcx-nightly` — [VRCX](https://github.com/vrcx-team/VRCX) built from the latest master commit
- `apple-color-emoji` — Apple Color Emoji repacked for Linux (via [samuelngs/apple-emoji-ttf](https://github.com/samuelngs/apple-emoji-ttf))
- `pony-hyprcursors` — vectorized hyprcursor builds of [Sullindir's MLP pony cursor packs](https://www.deviantart.com/sullindir/gallery); the original `.ani` files are bundled and converted to svg pixel grids at build time. Each pony installs to `share/icons/<Name>` (Rainbow-Dash, Rainbow-Dash-Alternate, Applejack, Fluttershy, Pinkie-Pie, Rarity, Twilight-Sparkle, Princess-Luna, Octavia, Derpy-Hooves, Vinyl-Scratch, Discord, Queen-Chrysalis); pick one with `hyprctl setcursor <Name> <size>`
- `grafana-dashboards.*` — community dashboards from [grafana.com](https://grafana.com/grafana/dashboards/), uid-rewritten for stable provisioning, `.override`-able datasource. Bundling helpers live in `pkgs.grafana-dashboards.lib.*`. See [`pkgs/grafana-dashboards/README.md`](./pkgs/grafana-dashboards/README.md).
- `ableton-wine` — Wine 11.11 (giang17 d2d1-dcomp fork) with the [shibco/ableton-linux](https://github.com/shibco/ableton-linux) patch series and PipeASIO, built from source with the upstream build gates ported as assertions
- `ableton-live` — launcher and prefix setup for Ableton Live on `ableton-wine`. See [`pkgs/ableton-live/README.md`](./pkgs/ableton-live/README.md).

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
> `apple-color-emoji` and `pony-hyprcursors` are `unfreeRedistributable` (the latter is built on Hasbro IP). You'll need `allowUnfree` (or a predicate) on your nixpkgs config.
