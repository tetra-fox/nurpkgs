#!/usr/bin/env bash
# end-user step 2 (step 1 is installing the packages): create or refresh the
# wine prefix, then optionally run the ableton installer from a downloaded
# ableton_live*.zip or installer .exe. wraps the upstream setup-prefix.sh;
# the zip handling mirrors the upstream .run installer
set -euo pipefail

usage() {
    cat <<EOF
usage: ableton-live-setup [--refresh | --post-first-run] [ableton_live*.zip | installer.exe]

creates or refreshes the wine prefix at \${ABLETON_WINEPREFIX:-~/.wine-ableton},
then runs the ableton installer if a download from ableton.com is given
(any edition; the zip straight from the download page works).

environment (see the upstream README for details):
  ABLETON_LIVE_VERSION  11|12   winetricks recipe to prepare (default 12)
  ABLETON_DPI_MODE              auto|preserve|100|fractional|dpi<N>
  ABLETON_THEME_MODE            auto|dark|light|preserve

upstream: https://github.com/shibco/ableton-linux
EOF
}

installer=""
setup_args=()
for a in "$@"; do
    case "$a" in
        -h|--help) usage; exit 0 ;;
        *.zip|*.exe) installer="$a" ;;
        *) setup_args+=("$a") ;;
    esac
done
if [ -n "$installer" ] && [ ! -f "$installer" ]; then
    echo "!! no such file: $installer" >&2
    exit 1
fi

export PATH="@setupPath@:$PATH"
bash "@shareDir@/scripts/setup-prefix.sh" ${setup_args[@]+"${setup_args[@]}"}

[ -n "$installer" ] || exit 0

export WINEPREFIX="${ABLETON_WINEPREFIX:-$HOME/.wine-ableton}"
unset WINELOADER WINEDLLPATH WINEDLLOVERRIDES WINEARCH WINEESYNC WINEFSYNC
export WINEDEBUG=-all

live_exe="$installer"
unpack_dir=""
case "$installer" in
    *.zip)
        unpack_dir="${XDG_CACHE_HOME:-$HOME/.cache}/ableton-wine-setup/live-installer"
        rm -rf "$unpack_dir"
        mkdir -p "$unpack_dir"
        echo "== unpacking $(basename "$installer") =="
        unzip -q "$installer" -d "$unpack_dir"
        live_exe="$(find "$unpack_dir" -iname '*.exe' | head -1)"
        [ -n "$live_exe" ] || {
            echo "!! that zip holds no installer (.exe) — is it the right download from ableton.com?" >&2
            exit 1
        }
        ;;
esac

echo "== starting the ableton installer — from here just click through its window =="
# run from the installer's own directory so its relative payload lookups resolve
( cd "$(dirname -- "$live_exe")" && "@abletonWine@/bin/wine" "./$(basename -- "$live_exe")" )
"@abletonWine@/bin/wineserver" -w 2>/dev/null || true
[ -z "$unpack_dir" ] || rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/ableton-wine-setup"

echo "== menu entries for the installed editions =="
"@desktopEntries@" || true

cat <<EOF

================================================================
Done — launch with: ableton-live
Then, inside Live (both matter):
  * Options menu -> untick 'Auto-Scale Plugin Window'
  * Preferences -> Audio -> Driver Type: ASIO -> Device: PipeASIO
================================================================
EOF
