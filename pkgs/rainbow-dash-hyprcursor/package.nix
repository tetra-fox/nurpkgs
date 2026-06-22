{
  lib,
  stdenvNoCC,
  python3,
  imagemagick,
  hyprcursor,
}: let
  themeName = "Rainbow-Dash";
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "rainbow-dash-hyprcursor";
    version = "1.0";

    src = ./src;

    nativeBuildInputs = [python3 imagemagick hyprcursor];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      mkdir -p theme out
      python3 ${./ani2hypr.py} \
        --src "$src" \
        --mapping ${./mapping.json} \
        --out theme \
        --name ${themeName} \
        --description "Rainbow Dash animated cursor theme (originally a Windows .ani set by Damien Allen / kirigakurenohaku)" \
        --version ${finalAttrs.version}

      hyprcursor-util --create theme --output ./out

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -d $out/share/icons
      mv "out/theme_${themeName}" "$out/share/icons/${themeName}"
      install -Dm644 $src/Disclaimer.txt $out/share/doc/${themeName}/Disclaimer.txt

      runHook postInstall
    '';

    meta = {
      description = "Rainbow Dash animated hyprcursor theme";
      longDescription = ''
        Hyprcursor build of the Rainbow Dash cursor set originally drawn as a
        Windows .ani pack by Damien Allen ("kirigakurenohaku" on DeviantArt).
        Rainbow Dash and My Little Pony: Friendship is Magic are properties of
        Lauren Faust and Hasbro; this is fan-made redistribution. Install the
        theme into ~/.local/share/icons/ or /run/current-system/sw/share/icons
        and select it via hyprcursor's HYPRCURSOR_THEME / hyprctl setcursor.
      '';
      homepage = "https://www.deviantart.com/kirigakurenohaku/art/Rainbow-Dash-Cursor-Set-Standard-Orientation-282922779";
      license = lib.licenses.unfreeRedistributable;
      platforms = lib.platforms.linux;
    };
  })
