# ableton-live / ableton-wine

Native NixOS packaging of [shibco/ableton-linux](https://github.com/shibco/ableton-linux):
Ableton Live 12 under a patched Wine, no steam-run, no FHS wrapper.

- `ableton-wine` — Wine 11.11 (giang17 d2d1-dcomp fork) with the ableton-linux
  patch series applied and PipeASIO baked in, built from source against
  nixpkgs pipewire and `/run/opengl-driver` like any other nixpkgs wine. The
  upstream build gates (winealsa, ntsync in both halves, xdg file portal,
  Push 2 bridge exports, PipeASIO linkage) are ported as build assertions.
- `ableton-live` — the upstream launcher and prefix tooling wrapped for the
  store: `ableton-live` (launcher), `ableton-live-setup` (prefix creation +
  Ableton installer), desktop entries.

## Usage

1. Install `ableton-live` (it pulls in `ableton-wine`); with this repo as a
   flake input (see the [top-level README](../../README.md)):

   ```nix
   environment.systemPackages = [
     inputs.tetra-nurpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.ableton-live
   ];
   ```

   This puts `ableton-live` and `ableton-live-setup` on PATH and the desktop
   entry in the menu. Live itself is proprietary and never enters the store,
   so no `allowUnfree` is involved. There is no binary cache for this repo:
   expect the wine build to take a while.
2. Download Live from [ableton.com](https://www.ableton.com/) — any edition,
   the zip straight from the download page.
3. `ableton-live-setup ~/Downloads/ableton_live*.zip` — creates
   `~/.wine-ableton`, runs the vendored winetricks verbs (Live 12: corefonts
   vcrun2022 mfc42; mfc42 downloads at setup time), then the Ableton
   installer. Mid-install, a crash dialog for `tlsetupfx.exe` is expected:
   that is Ableton's USB audio kernel-driver installer, which cannot run
   under Wine and is not needed on Linux (PipeWire owns the hardware). Close
   it and the installer continues.
4. `ableton-live`. On first launch, per the upstream README: untick
   Options → Auto-Scale Plugin Window, and set Preferences → Audio →
   Driver Type: ASIO, Device: PipeASIO.

`ableton-live-desktop-entries` writes one menu entry per installed edition
(icon extracted from the exe, install pinned via `ABLETON_LIVE_EXE`); setup
runs it automatically after the Ableton installer, rerun it after adding or
removing editions.

Live, your settings, and the license live in `~/.wine-ableton` and survive
package updates. After an update that changes `ableton-wine`, run
`ableton-live-setup --refresh` once: it re-applies registry policy and heals
runtime DLLs without touching Live or the license (the upstream .run's update
mode does the same). `ableton-live-setup --post-first-run` is the Max for
Live preferences fixup (Live 11).

## Host configuration (not packaged)

These sit in NixOS config territory, deliberately outside the packages:

- realtime audio: [musnix](https://github.com/musnix/musnix), or
  `security.pam.loginLimits` with an rtprio entry plus `security.rtkit.enable`.
  The launcher probes `chrt -r 10` and runs Live under SCHED_RR wherever
  rtprio rights exist; `ABLETON_RT=off` opts out.
- ntsync fast path needs a runtime kernel >= 6.14 (the build-time header is
  not enough); older kernels silently fall back to wineserver round trips at
  a large cpu cost.
- Push 2 display access may need a udev rule
  (`services.udev.extraRules`):

  ```text
  SUBSYSTEM=="usb", ATTR{idVendor}=="2982", ATTR{idProduct}=="1967", TAG+="uaccess"
  ```

  See `notes/ABLETON-WINE-PUSH2-DISPLAY.md` upstream.
- Ableton Link needs its multicast/UDP traffic allowed; upstream's
  `setup-link.sh` documents what it expects.
