{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  buildDotnetModule,
  dotnetCorePackages,
  nodejs_24,
  electron_40,
  runCommand,
  unzip,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
}: let
  # package.json engines wants node >= 24, the csproj targets net9.0,
  # electron is pinned to ^40 in devDependencies
  node = nodejs_24;
  electron = electron_40;
  dotnet = dotnetCorePackages.dotnet_9;
in
  buildNpmPackage (finalAttrs: let
    # upstream nightlies stamp Version as "<date>-<short hash>", main.js
    # treats the trailing 7 char hash as the nightly marker
    versionStamp = "${lib.replaceStrings ["-"] ["."] (lib.last (lib.splitString "-unstable-" finalAttrs.version))}-${lib.substring 0 7 finalAttrs.src.rev}";

    backend = buildDotnetModule {
      inherit (finalAttrs) version src;
      pname = "${finalAttrs.pname}-backend";

      dotnet-sdk = dotnet.sdk;
      dotnet-runtime = dotnet.runtime;
      projectFile = "Dotnet/VRCX-Electron.csproj";

      nugetDeps = ./deps.json;

      installPhase = ''
        runHook preInstall

        mkdir -p $out/build/Electron
        cp -r build/Electron/* $out/build/Electron/

        runHook postInstall
      '';
    };

    # generate-third-party-licenses.js looks up nuspec and license files in
    # an extracted ~/.nuget/packages style cache, fetchNupkg only gives us
    # the unextracted .nupkg archives
    nugetLicenseCache =
      runCommand "vrcx-nightly-nuget-license-cache" {
        nativeBuildInputs = [unzip];
        nupkgs = backend.nugetDeps;
      } ''
        mkdir -p $out
        for pkg in $nupkgs; do
          for nupkg in "$pkg"/share/nuget/source/*/*/*.nupkg; do
            dir=$out/$(basename "$(dirname "$(dirname "$nupkg")")")/$(basename "$(dirname "$nupkg")")
            mkdir -p "$dir"
            unzip -q -o "$nupkg" -d "$dir"
          done
        done
      '';
  in {
    pname = "vrcx-nightly";
    version = "2026.05.03-unstable-2026-06-25";

    src = fetchFromGitHub {
      owner = "vrcx-team";
      repo = "VRCX";
      rev = "5d27c3de79308e5c5d1309ae323cc944476e45fb";
      hash = "sha256-s/+Dxa2hYptXWJvLfT1NTvlbs17UteHMosMaf74mBmA=";
    };

    nodejs = node;
    makeCacheWritable = true;
    npmFlags = ["--ignore-scripts"];
    npmDepsHash = "sha256-YwhRYpPcGwswf3OC3n1zFoSADOPkI5sTlaQN+fDe8sI=";

    nativeBuildInputs = [
      makeWrapper
      copyDesktopItems
    ];

    postPatch = ''
      # upstream's lockfile is missing resolved/integrity fields for many
      # entries (npm omits them when installing from a warm cache), which
      # breaks offline fetching. the vendored copy is the same lockfile
      # with those fields restored, see update.sh
      cp ${./package-lock.json} package-lock.json

      echo -n "${versionStamp}" > Version
    '';

    # mirrors the linux path of upstream's own scripts: prod-linux (vite
    # build plus license manifest), then build-electron minus the dotnet
    # runtime download (nix provides the runtime via DOTNET_ROOT), then
    # the postbuild asar path fixup. rename-builds.js is skipped, it only
    # renames release artifacts for upload
    buildPhase = ''
      runHook preBuild

      env PLATFORM=linux npm exec vite build src
      NUGET_PACKAGES=${nugetLicenseCache} node ./build-scripts/generate-third-party-licenses.js
      node ./src-electron/patch-package-version.js
      npm exec electron-builder -- --dir \
        -c.electronDist=${electron.dist} \
        -c.electronVersion=${electron.version}
      node ./src-electron/patch-node-api-dotnet.js

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/share/vrcx"
      cp -r build/*-unpacked/resources "$out/share/vrcx/"
      mkdir -p "$out/share/vrcx/resources/app.asar.unpacked/build/Electron"
      cp -r ${backend}/build/Electron/* "$out/share/vrcx/resources/app.asar.unpacked/build/Electron/"

      makeWrapper '${electron}/bin/electron' "$out/bin/vrcx"  \
        --add-flags "--ozone-platform-hint=auto --no-updater" \
        --add-flags "$out/share/vrcx/resources/app.asar"      \
        --set NODE_ENV production                             \
        --set DOTNET_ROOT ${dotnet.runtime}/share/dotnet      \
        --prefix PATH : ${lib.makeBinPath [dotnet.runtime]}

      install -Dm644 images/VRCX.png "$out/share/icons/hicolor/256x256/apps/vrcx.png"

      runHook postInstall
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "vrcx";
        icon = "vrcx";
        exec = "vrcx %u";
        terminal = false;
        desktopName = "VRCX";
        comment = "Friendship management tool for VRChat";
        categories = ["Utility" "Application"];
        # main.js registers vrcx:// for invite and registration links
        mimeTypes = ["x-scheme-handler/vrcx"];
      })
    ];

    passthru = {
      inherit backend;
      # exposed at the top level so nix-update regenerates deps.json by
      # running the fetch-deps script
      inherit (backend) nugetDeps fetch-deps;
      updateScript = ./update.sh;
    };

    meta = {
      description = "Friendship management tool for VRChat";
      homepage = "https://github.com/vrcx-team/VRCX";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      broken = !stdenv.hostPlatform.isx86_64;
      mainProgram = "vrcx";
    };
  })
