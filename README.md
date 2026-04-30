# nurpkgs

## Packages

- `surge-dm` — [Surge](https://github.com/SurgeDM/Surge), a TUI download manager
- `apple-color-emoji` — Apple Color Emoji repacked for Linux (via [samuelngs/apple-emoji-ttf](https://github.com/samuelngs/apple-emoji-ttf))

## Usage

Add as a flake input:

```nix
inputs.nurpkgs.url = "github:tetra-fox/nurpkgs";
```

Then either the overlay or `legacyPackages.<system>` can be used.

**Via overlay** (in a NixOS or home-manager module):

```nix
{ inputs, ... }: {
  nixpkgs.overlays = [ inputs.nurpkgs.overlays.default ];
}
```

**Via direct reference** (skip the overlay):

```nix
environment.systemPackages = [
  inputs.nurpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.surge-dm
];
```

Or build a package directly:

```sh
nix build github:tetra-fox/nurpkgs#surge-dm
```

> [!IMPORTANT]
> `apple-color-emoji` is `unfreeRedistributable`; you'll need `allowUnfree` (or a predicate) on your nixpkgs config.
