{
  lib,
  stdenv,
  buildNpmPackage,
  fetchFromGitHub,
  buildDotnetModule,
  dotnetCorePackages,
  nodejs_24,
  electron_42,
  runCommand,
  unzip,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
}: let
  # package.json engines wants node >= 24, the csproj targets net10.0.
  # upstream pins electron ^40 as a devDependency (type defs + electron-builder),
  # but the runtime electron is passed explicitly to electron-builder below, so we
  # run a supported line instead. 40 is EOL; 42 ships the same node 24.17 / N-API 10
  # as 41 so the precompiled node-api-dotnet addon loads unchanged, just newer chromium
  node = nodejs_24;
  electron = electron_42;
  dotnet = dotnetCorePackages.dotnet_10;
  rid = dotnetCorePackages.systemToDotnetRid stdenv.hostPlatform.system;
in
  buildNpmPackage (finalAttrs: let
    backend = buildDotnetModule {
      inherit (finalAttrs) version src;
      pname = "${finalAttrs.pname}-backend";

      dotnet-sdk = dotnet.sdk;
      dotnet-runtime = dotnet.runtime;
      projectFile = "Dotnet/VRCX-Electron.csproj";
      # Dotnet/Directory.Build.props errors out when Platform is left at the
      # AnyCPU default, upstream passes the arch half of the rid
      dotnetBuildFlags = ["-p:Platform=${lib.last (lib.splitString "-" rid)}"];

      nugetDeps = ./deps.json;

      # keeps the csproj's build/Electron/<rid>/ layout. main.js only loads the
      # flat path when app.isPackaged, which is false under the stock electron
      # binary
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
    # upstream's nightly channel tags each build "<date>T<HH.MM>-<short hash>"
    # (from api0.vrcx.app/releases/nightly/latest). that exact string is what
    # the app writes to its Version file and shows as the running version, and
    # main.js keys nightly detection off the trailing 7 char hash, so we pin the
    # tagged nightly commit and reuse the tag verbatim. see update.sh
    version = "2026-09-30T21.59-c6a4d8b";

    src = fetchFromGitHub {
      owner = "vrcx-team";
      repo = "VRCX";
      rev = "c6a4d8b594a596e78152f1d833785c759d104a49";
      hash = "sha256-vLrAgInm4u3r2X+A3w53QeSAAh8WKK/cY1rJCV1q/sc=";
    };

    nodejs = node;
    makeCacheWritable = true;
    npmFlags = ["--ignore-scripts"];
    npmDepsHash = "sha256-fFuqtISueODEFzuqWWL3aG4DWbrq2G4dHsXi3RWByjY=";

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

      echo -n "${finalAttrs.version}" > Version
    '';

    # mirrors upstream's own scripts: prod (vite build plus license
    # manifest), then build-electron minus the dotnet runtime download (nix
    # provides the runtime via DOTNET_ROOT), then the postbuild asar path
    # fixup. rename-builds.js is skipped, it only renames release artifacts
    # for upload
    buildPhase = ''
      runHook preBuild

      npm exec vite build src
      NUGET_PACKAGES=${nugetLicenseCache} node ./build-scripts/generate-third-party-licenses.js
      node ./build-scripts/patch-package-version.js
      npm exec electron-builder -- --dir \
        --config electron-builder.config.js \
        -c.electronDist=${electron.dist} \
        -c.electronVersion=${electron.version}
      node ./build-scripts/patch-node-api-dotnet.js

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
