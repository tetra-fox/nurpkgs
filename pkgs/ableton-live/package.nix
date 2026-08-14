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
  xdg-user-dirs,
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
    xdg-user-dirs # xdg-user-dir DESKTOP, for the .desktop refresh
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
    xdg-user-dirs
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
      # the launcher and setup source these helper libs. both resolve them
      # relative to their own dir first ($here/lib), so installing beside the
      # scripts is enough; config.sh drives the ABLETON_* env contract
      install -m644 scripts/lib/*.sh -Dt $share/scripts/lib
      # prebuilt PE helpers that run under wine: setsyscolors repaints live's
      # top bar on theme change, learnheal reloads a wedged learn view. plus the
      # gnome shortcut-hold helper (has a launcher-dir fallback, so shipping it
      # beside the launcher is enough) and ableton-linkctl (opt-in link control).
      # all runtime-optional; shipped for parity with upstream's install
      install -m644 tools/setsyscolors.exe tools/learnheal.exe $share/scripts/
      install -m755 scripts/shortcut-hold.sh scripts/ableton-linkctl $share/scripts/
      # setup-prefix installs these into the prefix to repair max for live's font
      # fallback (M4L devices name macOS fonts; max's last resort is bitstream
      # vera, which no modern distro ships), fixing an M4L load hang
      mkdir -p $share/vendor/fonts
      cp -r vendor/fonts/bitstream-vera $share/vendor/fonts/
      # the pieces setup-prefix.sh resolves from the kit root; the rest of
      # vendor/ (wine base tarball, pipeasio, sdk debs) is build input for
      # ableton-wine, not runtime material
      install -m755 vendor/winetricks $share/vendor/
      cp -r vendor/winetricks-cache $share/vendor/

      # setup-prefix.sh finds its libs and detect scripts relative to $here
      # (the store), so it needs no rewriting. the launcher, though, reads the
      # detect scripts and setsyscolors from $ABLETON_DATA_HOME (a writable user
      # dir in the upstream install.sh model); point those at the store copies
      substituteInPlace $share/scripts/ableton-live \
        --replace-fail '"$ABLETON_DATA_HOME/detect-scale.sh"' "\"$share/scripts/detect-scale.sh\"" \
        --replace-fail '"$ABLETON_DATA_HOME/detect-theme.sh"' "\"$share/scripts/detect-theme.sh\"" \
        --replace-fail '"$ABLETON_DATA_HOME/setsyscolors.exe"' "\"$share/scripts/setsyscolors.exe\"" \
        --replace-fail '"$ABLETON_DATA_HOME/learnheal.exe"' "\"$share/scripts/learnheal.exe\"" \
        --replace-fail '"$ABLETON_DATA_HOME/ableton-linkctl"' "\"$share/scripts/ableton-linkctl\""

      # config.sh only defaults ABLETON_WINE_ROOT when unset, so the wrapper's
      # value wins; an explicit ABLETON_WINE_ROOT in the environment still
      # overrides. ABLETON_DATA_HOME stays the user default (writable: link
      # state, ableton-linkd), since the store copies are wired in above
      makeWrapper $share/scripts/ableton-live $out/bin/ableton-live \
        --set-default ABLETON_WINE_ROOT ${ableton-wine} \
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

      # static menu entry + the ableton:// and .auz handlers. @BIN@ -> our bin;
      # drop Path=@PREFIX@ (the store cannot know the wine prefix, and the
      # launcher does not depend on its cwd). generic name/icon/wmclass here;
      # ableton-live-desktop-entries overwrites with real per-edition icons
      # after Live installs
      for d in ableton-live ableton-linux-protocol ableton-linux-auz; do
        sed -e "s#@BIN@#$out/bin#g" \
            -e 's#@NAME@#Ableton Live#g' \
            -e 's#@ICON@#ableton-live#g' \
            -e 's#@WMCLASS@#ableton live 12 suite.exe#g' \
            -e '/^Path=@PREFIX@/d' \
            desktop/$d.desktop.in > $out/share/applications/$d.desktop
      done

      # file-type integration: the .auz MIME definition and the scalable icons
      # for the edition entries and the live document types (.als/.adg/.adv...),
      # so file managers show the right icons and .auz opens through the handler
      install -Dm644 desktop/x-wine-extension-auz.xml -t $out/share/mime/packages
      mkdir -p $out/share/icons/hicolor
      cp -r desktop/icons/scalable $out/share/icons/hicolor/

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
