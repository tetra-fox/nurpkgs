{
  lib,
  stdenvNoCC,
  ableton-wine,
  makeWrapper,
  cabextract,
  coreutils,
  desktop-file-utils,
  diffutils,
  findutils,
  gawk,
  gnugrep,
  gnused,
  icoutils,
  procps,
  unzip,
  util-linux,
  wget,
}: let
  # tools the launcher shells out to on every start. desktop probes (hyprctl,
  # gsettings, xrdb) stay ambient on purpose, the scripts treat them as optional
  launcherPath = lib.makeBinPath [
    coreutils
    gawk
    gnugrep
    gnused
    procps
    util-linux
  ];
  # setup-prefix.sh + winetricks host tools; wget covers verbs whose payload
  # is not in the vendored cache (mfc42 for live 12)
  setupPath = lib.makeBinPath [
    cabextract
    coreutils
    desktop-file-utils
    diffutils
    findutils
    gawk
    gnugrep
    gnused
    unzip
    util-linux
    wget
  ];
  # icon extraction plus the shell tools the entry generator uses
  desktopEntriesPath = lib.makeBinPath [
    coreutils
    desktop-file-utils
    gnugrep
    gnused
    icoutils
  ];
in
  stdenvNoCC.mkDerivation {
    pname = "ableton-live";
    inherit (ableton-wine) version;

    src = ableton-wine.passthru.abletonLinux;

    patches = [./nixos-setup-prefix.patch];

    # the kit's root Makefile drives the upstream container build; nothing to
    # compile here
    dontBuild = true;

    # trivial itself, but depends on ableton-wine; keep the wine build off CI
    preferLocalBuild = true;

    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      share=$out/share/ableton-wine
      mkdir -p $share/scripts $share/vendor $out/bin $out/share/applications

      install -m755 scripts/ableton-live scripts/setup-prefix.sh $share/scripts/
      install -m644 scripts/detect-scale.sh scripts/detect-theme.sh $share/scripts/
      # prebuilt PE helper, runs under wine: repaints live's top bar mid-session
      # on theme change. shipped as-is like upstream's kit does
      install -m644 tools/setsyscolors.exe $share/scripts/
      # only the pieces setup-prefix.sh resolves from the kit root; the rest of
      # vendor/ (wine base tarball, pipeasio, sdk debs) is build input for
      # ableton-wine, not runtime material
      install -m755 vendor/winetricks $share/vendor/
      cp -r vendor/winetricks-cache $share/vendor/

      # the launcher and setup script default to the ~/.local layout of
      # upstream's install.sh; point them at the store instead. an explicit
      # ABLETON_WINE_ROOT still overrides
      for f in $share/scripts/ableton-live $share/scripts/setup-prefix.sh; do
        substituteInPlace $f --replace-fail \
          'WINE_ROOT="''${ABLETON_WINE_ROOT:-$HOME/.local/opt/wine-d2d1-nspa-11.11}"' \
          'WINE_ROOT="''${ABLETON_WINE_ROOT:-${ableton-wine}}"'
      done
      substituteInPlace $share/scripts/ableton-live \
        --replace-fail '"$HOME/.local/share/ableton-wine/detect-scale.sh"' "\"$share/scripts/detect-scale.sh\"" \
        --replace-fail '"$HOME/.local/share/ableton-wine/detect-theme.sh"' "\"$share/scripts/detect-theme.sh\"" \
        --replace-fail '"$HOME/.local/share/ableton-wine/setsyscolors.exe"' "\"$share/scripts/setsyscolors.exe\""

      makeWrapper $share/scripts/ableton-live $out/bin/ableton-live \
        --prefix PATH : ${launcherPath}

      install -m755 ${./ableton-live-desktop-entries.sh} $out/bin/ableton-live-desktop-entries
      substituteInPlace $out/bin/ableton-live-desktop-entries \
        --subst-var-by toolPath ${desktopEntriesPath} \
        --subst-var-by launcher "$out/bin/ableton-live"

      install -m755 ${./ableton-live-setup.sh} $out/bin/ableton-live-setup
      substituteInPlace $out/bin/ableton-live-setup \
        --subst-var-by shareDir "$share" \
        --subst-var-by setupPath ${setupPath} \
        --subst-var-by abletonWine ${ableton-wine} \
        --subst-var-by desktopEntries "$out/bin/ableton-live-desktop-entries"

      # Path= would hardcode a home directory the store cannot know; the
      # launcher does not depend on its cwd
      for d in ableton-live wine-protocol-ableton; do
        sed -e "s#@HOME@/.local/bin/ableton-live#$out/bin/ableton-live#" \
            -e '/^Path=/d' \
            desktop/$d.desktop.in > $out/share/applications/$d.desktop
      done

      runHook postInstall
    '';

    meta = {
      description = "Launcher and prefix setup for Ableton Live on the patched ableton-wine runtime";
      homepage = "https://github.com/shibco/ableton-linux";
      license = lib.licenses.lgpl21Plus;
      sourceProvenance = with lib.sourceTypes; [
        fromSource
        binaryNativeCode # setsyscolors.exe
      ];
      platforms = ["x86_64-linux"];
      mainProgram = "ableton-live";
    };
  }
