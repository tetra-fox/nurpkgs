{
  lib,
  fetchFromGitHub,
  wineWow64Packages,
  pipewire,
  llvmPackages,
  cmake,
  ninja,
  pkg-config,
}: let
  # shibco/ableton-linux is the kit: the wine patch series, vendored pipeasio
  # and its patches, winetricks plus payload cache, launcher scripts. one pin
  # shared with ableton-live via passthru. in an upstream in-tree flake this
  # becomes ./. with the version read from ./VERSION
  version = "2026.08.14.2";
  abletonLinux = fetchFromGitHub {
    owner = "shibco";
    repo = "ableton-linux";
    # main tip, not a release tag: kit content the packages ship can land
    # after the release commit that stamps VERSION. bump with update.sh and
    # build locally before pushing, CI does not build this package
    rev = "b89f904ba8c7c932b721a864ce2301b93678b4b6";
    hash = "sha256-V+asGCPxBDgi6UN+xsSHhJ9MtY9n7K39f/W0Ri6DJww=";
  };
  pipeasioVersion = "1.5.0";
  pwLib = lib.getLib pipewire;
in
  # nixpkgs base wine (11.12 infra, one point release off the 11.13 fork base)
  # already enables everything upstream's ubuntu container provides: alsa
  # (winealsa midi), pulse, gnutls, dbus, udev, freetype, fontconfig,
  # x11/gl/vulkan, and libusb via usbSupport for the push 2 bridge. wayland is
  # also on, which upstream lacks (xwayland-only container); the driver stays
  # dormant while DISPLAY is set.
  # media: nixpkgs base ships ffmpegSupport, so mp3/video decode through wine's
  # winedmo (ffmpeg) demuxer, wine's own strategic replacement for the
  # winegstreamer backend upstream still uses. the prefix routes mfsrcsnk to it
  # with DisableGstByteStreamHandler=1 (nixos-setup-prefix.patch).
  # pe side: nixpkgs mingw instead of upstream's clang/lld.
  wineWow64Packages.unstable.overrideAttrs (old: {
    pname = "ableton-wine";
    inherit version;

    # giang17's d2d1-dcomp-11.13 branch, the exact base the series applies to
    # (upstream vendors it as vendor/wine-base-5c23dd1c.tar.zst); upstream
    # bumped 11.11 -> 11.13 on 2026-07-21
    src = fetchFromGitHub {
      owner = "giang17";
      repo = "wine";
      rev = "5c23dd1cf66550608df3a0b598269628e917e8e8";
      hash = "sha256-uLxVe0lxHsxHktKeVchjoeOk1FZAU65/0qh7nJXZV1A=";
    };

    # keep nixpkgs' own patches (cert-path); the series applies after, driven
    # by the kit's SERIES.sha256 manifest so this file never restates it and a
    # kit whose patches disagree with the manifest fails instead of building.
    # upstream uses git am --3way, but on the exact base plain patch works:
    # the series carries no renames or binary diffs, and 0032 patches the
    # generated configure alongside configure.ac so no autoreconf is needed
    postPatch =
      (old.postPatch or "")
      + ''
        [ "$(cat ${abletonLinux}/VERSION)" = "$version" ] || {
          echo "kit VERSION $(cat ${abletonLinux}/VERSION) does not match package version $version" >&2
          exit 1
        }
        (cd ${abletonLinux}/patches && sha256sum -c --quiet SERIES.sha256)
        for f in ${abletonLinux}/patches/00*.patch ${abletonLinux}/patches/pipeasio/*.patch; do
          rel=''${f#${abletonLinux}/patches/}
          grep -q "  $rel\$" ${abletonLinux}/patches/SERIES.sha256 || {
            echo "$rel on disk but not in SERIES.sha256" >&2
            exit 1
          }
        done
        n=0
        for p in $(sed -n 's/^[0-9a-f]\{64\}  \(00.*\.patch\)$/\1/p' ${abletonLinux}/patches/SERIES.sha256); do
          patch -p1 --no-backup-if-mismatch < ${abletonLinux}/patches/$p
          n=$((n + 1))
        done
        echo "applied $n patches from the ableton-linux series"
      '';

    # fail two minutes in, not after the full compile: configure silently
    # drops ntsync without a usable linux/ntsync.h
    postConfigure =
      (old.postConfigure or "")
      + ''
        grep -q '^#define HAVE_LINUX_NTSYNC_H 1' include/config.h
      '';

    env =
      old.env
      // {
        # the kit's vendored uapi header, like upstream's container build: the
        # dir holds only linux/ntsync.h, so system headers stay authoritative
        # for everything else and the build stops depending on the consumer's
        # nixpkgs kernel headers being new enough
        CPPFLAGS = "-I${abletonLinux}/vendor/ntsync-uapi";
      };

    configureFlags = old.configureFlags ++ ["--disable-tests"];

    # a source wine build is far too heavy for the github runner; ci.nix
    # excludes preferLocalBuild packages from the cache set
    preferLocalBuild = true;

    # llvm-readobj for the push 2 export gate below
    nativeBuildInputs = old.nativeBuildInputs ++ [llvmPackages.llvm];

    # pipeasio is versioned and shipped as one runtime with this wine upstream.
    # 1.5 moved to a cmake build (its cmake/WineDLL.cmake drives this wine's
    # winebuild/winegcc); build it here mirroring container-build.sh step [4/8].
    # the settings panel (native qt6, not used inside wine) and ctest are off,
    # driver only. then the ported build gates, each catching a regression that
    # shipped silently at least once, see the upstream script and notes/
    postInstall =
      (old.postInstall or "")
      + ''
        echo "== build pipeasio ${pipeasioVersion} against this wine (cmake) =="
        mkdir pipeasio
        tar xzf ${abletonLinux}/vendor/pipeasio-${pipeasioVersion}.tar.gz -C pipeasio --strip-components=1
        pushd pipeasio
        for p in ${abletonLinux}/patches/pipeasio/*.patch; do
          patch -p1 --no-backup-if-mismatch < "$p"
        done
        # this wine's winegcc/winebuild first, then cmake/ninja by path (kept
        # out of nativeBuildInputs so their setup hooks never hijack wine's
        # autotools configurePhase). WineDLL finds wine headers from $out/include
        export PATH="$out/bin:${cmake}/bin:${ninja}/bin:${pkg-config}/bin:$PATH"
        export PKG_CONFIG_PATH="${lib.getDev pipewire}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
        cmake -S . -B build -G Ninja \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$out" \
          -DWINEBUILD="$out/bin/winebuild" \
          -DWINEGCC="$out/bin/winegcc" \
          -DBUILD_SETTINGS_PANEL=OFF \
          -DBUILD_TESTS=OFF \
          -DCMAKE_EXE_LINKER_FLAGS="-Wl,--allow-shlib-undefined"
        cmake --build build -j''${NIX_BUILD_CORES:-4}
        cmake --install build
        popd
        # WineDLL installs pipeasio64.dll(.so) plus the pipeasio.dll(.so) symlink
        # aliases wine resolves the builtin by. cmake links libpipewire by soname
        # (pkg-config) but embeds no rpath; nixos has no ld.so cache, so add the
        # store rpath to the real unix file (the symlink alias follows it)
        patchelf --add-rpath ${pwLib}/lib $out/lib/wine/x86_64-unix/pipeasio64.dll.so

        # pipewire-version-probe: a native linux client the kit's setup-prefix
        # runs from $WINE_ROOT/bin to preflight the host pipewire before
        # registering pipeasio. plain gcc against nixpkgs pipewire, store rpath
        # (nixos has no ld.so cache; upstream's container forbids rpath because
        # it resolves against the host, the opposite constraint)
        echo "== build pipewire-version-probe =="
        cc ${abletonLinux}/tools/pipewire-version-probe.c \
          $(pkg-config --cflags libpipewire-0.3) \
          -lpipewire-0.3 -L${pwLib}/lib -Wl,-rpath,${pwLib}/lib \
          -O2 -o $out/bin/pipewire-version-probe

        # sealed-runtime manifest the kit's setup-prefix requires and validates
        # (lib/pipeasio.sh): the pipeasio/probe sha256s it re-checks at setup,
        # plus the panel state (we build driver-only, panel disabled)
        echo "== stamp ABLETON-WINE-BUILD-INFO.txt =="
        {
          echo "dist-version: ${version}"
          echo "pipeasio-pe: $(sha256sum $out/lib/wine/x86_64-windows/pipeasio64.dll | awk '{print $1}')"
          echo "pipeasio-unix: $(sha256sum $out/lib/wine/x86_64-unix/pipeasio64.dll.so | awk '{print $1}')"
          echo "pipewire-version-probe: $(sha256sum $out/bin/pipewire-version-probe | awk '{print $1}')"
          echo "pipeasio-panel: skipped"
          echo "pipeasio-settings: skipped (disabled)"
        } > $out/ABLETON-WINE-BUILD-INFO.txt

        echo "== build gates (container-build.sh [3/8] + [4/8]) =="
        # configure silently drops winealsa without alsa-lib; that means no
        # hardware midi in live, only "Computer Keyboard"
        test -s $out/lib/wine/x86_64-unix/winealsa.so

        # without ntsync every NT sync wait becomes a wineserver round trip
        # (~1.3 cores with live running). check both halves, one upstream
        # build lost only the wineserver one
        # grep -c, not -q: -q exits on first match and strings dies of SIGPIPE
        ntsync_srv="$(strings $out/bin/wineserver | grep -c ntsync || true)"
        ntsync_ntd="$(strings $out/lib/wine/x86_64-unix/ntdll.so | grep -c ntsync || true)"
        [ "$ntsync_srv" -gt 0 ] || { echo "no ntsync in wineserver" >&2; exit 1; }
        [ "$ntsync_ntd" -gt 0 ] || { echo "no ntsync in ntdll.so" >&2; exit 1; }

        # xdg file portal patch 0031
        strings $out/lib/wine/x86_64-unix/comdlg32.so | grep -qF 'org.freedesktop.portal.FileChooser'

        # push 2 bridge, patch 0032: x64 only, exact export/ordinal list
        bridge_pe=$out/lib/wine/x86_64-windows/libusb-1.0.dll
        bridge_unix=$out/lib/wine/x86_64-unix/libusb-1.0.so
        test -f "$bridge_pe"
        test -f "$bridge_unix"
        test ! -e $out/lib/wine/i386-windows/libusb-1.0.dll
        test ! -e $out/lib/wine/i386-unix/libusb-1.0.so
        expected_exports=$'4 libusb_alloc_transfer\n10 libusb_cancel_transfer\n12 libusb_claim_interface\n16 libusb_close\n26 libusb_error_name\n32 libusb_exit\n40 libusb_free_device_list\n50 libusb_free_transfer\n72 libusb_get_device_descriptor\n74 libusb_get_device_list\n110 libusb_handle_events_timeout\n120 libusb_init\n132 libusb_open\n140 libusb_release_interface\n154 libusb_set_option\n161 libusb_submit_transfer'
        actual_exports="$(llvm-readobj --coff-exports "$bridge_pe" | awk '
          /^Export / { ordinal = ""; name = "" }
          /Ordinal:/ { ordinal = $2 }
          /Name: libusb_/ { name = $2 }
          /^}/ && name != "" { print ordinal, name }
        ')"
        if [ "$actual_exports" != "$expected_exports" ]; then
          echo "push 2 bridge export/ordinal mismatch" >&2
          diff -u <(printf '%s\n' "$expected_exports") <(printf '%s\n' "$actual_exports") >&2 || true
          exit 1
        fi
        readelf -d "$bridge_unix" | grep -qF 'Shared library: [libusb-1.0.so.0]'

        # pipeasio must link the host pipewire by soname
        readelf -d $out/lib/wine/x86_64-unix/pipeasio64.dll.so | grep -qF 'Shared library: [libpipewire-0.3.so.0]'

        $out/bin/wine --version
      '';

    passthru =
      old.passthru
      // {
        inherit abletonLinux;
        updateScript = ./update.sh;
      };

    meta =
      old.meta
      // {
        description = "Wine (giang17 d2d1-dcomp fork) with the shibco/ableton-linux patch series and PipeASIO, for Ableton Live";
        homepage = "https://github.com/shibco/ableton-linux";
        license = with lib.licenses; [lgpl21Plus gpl3Plus];
        platforms = ["x86_64-linux"];
        mainProgram = "wine";
      };
  })
