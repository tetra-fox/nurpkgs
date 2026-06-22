{
  lib,
  stdenvNoCC,
  python3,
  imagemagick,
  hyprcursor,
}: let
  version = "1.0";
  ponies = lib.importJSON ./ponies.json;
  # one theme dir per pony under share/icons/<Name>; pick at runtime with
  # `hyprctl setcursor <Name> <size>` or HYPRCURSOR_THEME=<Name>
  buildOne = name: meta: ''
    python3 ${./ani2hypr.py} \
      --src "$src/${meta.src}" \
      --roles ${./roles.json} \
      --out "theme/${name}" \
      --name ${lib.escapeShellArg name} \
      --description ${lib.escapeShellArg meta.description} \
      --version ${lib.escapeShellArg version}
    # closed stdin: hyprcursor-util prompts to delete a pre-existing
    # out/theme_<name>. names are distinct so it never fires, but a future
    # duplicate name should fail the build, not hang waiting on a [Y/n]
    hyprcursor-util --create "theme/${name}" --output ./out </dev/null
    mv "out/theme_${name}" "$out/share/icons/${name}"
    if [ -f "$src/${meta.src}/Disclaimer.txt" ]; then
      install -Dm644 "$src/${meta.src}/Disclaimer.txt" \
        "$out/share/doc/${name}/Disclaimer.txt"
    fi
  '';
in
  stdenvNoCC.mkDerivation {
    pname = "pony-hyprcursors";
    inherit version;

    src = ./src;

    nativeBuildInputs = [python3 imagemagick hyprcursor];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      mkdir -p theme out "$out/share/icons"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList buildOne ponies)}

      runHook postBuild
    '';

    # buildOne installs each theme directly, so there is nothing left to do here
    dontInstall = true;

    meta = {
      description = "Animated MLP pony hyprcursor themes by Damien Allen (Sullindir)";
      longDescription = ''
        Hyprcursor builds of Damien Allen's ("Sullindir" on DeviantArt) pony
        cursor sets, originally drawn as Windows .ani packs. Each pony installs
        to share/icons/<Name>; select one at runtime via hyprcursor's
        HYPRCURSOR_THEME or `hyprctl setcursor <Name> <size>`. Frames are
        emitted as svg pixel grids so they stay crisp at any cursor size.
        My Little Pony: Friendship is Magic is the property of Lauren Faust
        and Hasbro; this is fan-made redistribution.
      '';
      homepage = "https://www.deviantart.com/sullindir/journal/My-Little-Pony-Cursors-267244235";
      license = lib.licenses.unfreeRedistributable;
      platforms = lib.platforms.linux;
    };
  }
