#!/bin/bash
# Install the cpuz165 compatibility driver into a Wine prefix and start it.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
PREFIX=${WINEPREFIX:-$HOME/.wine}
WINE=${WINE:-}
SYSTEM_DRIVER_PATH='C:\windows\system32\drivers\cpuz165_stub.sys'

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build the cpuz165 stub, copy it into a Wine prefix, register the kernel
service and start it.

Options:
  --prefix=DIR   Wine prefix (default: $PREFIX)
  --wine=PATH    wine binary (default: \$WINE, then PATH, then
                 \$HOME/.local/opt/wine/bin/wine)
  --rebuild      force a rebuild of the driver
  -h, --help     show this help
EOF
}

REBUILD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --prefix=*)  PREFIX=${1#*=}; shift ;;
        --prefix)    [ $# -ge 2 ] || { echo "error: --prefix needs a value" >&2; exit 1; }
                     PREFIX=$2; shift 2 ;;
        --wine=*)    WINE=${1#*=}; shift ;;
        --wine)      [ $# -ge 2 ] || { echo "error: --wine needs a value" >&2; exit 1; }
                     WINE=$2; shift 2 ;;
        --rebuild)   REBUILD=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [ -z "$WINE" ]; then
    if command -v wine >/dev/null 2>&1; then
        WINE=$(command -v wine)
    elif [ -x "$HOME/.local/opt/wine/bin/wine" ]; then
        WINE="$HOME/.local/opt/wine/bin/wine"
    else
        echo "error: wine not found; pass --wine=PATH" >&2
        exit 1
    fi
fi

PREFIX=$(cd "$PREFIX" 2>/dev/null && pwd -P) || {
    echo "error: Wine prefix not found: $PREFIX" >&2
    exit 1
}
DRIVERS_DIR="$PREFIX/drive_c/windows/system32/drivers"
[ -d "$DRIVERS_DIR" ] || {
    echo "error: not a Wine prefix (missing $DRIVERS_DIR)" >&2
    exit 1
}

if [ "$REBUILD" -eq 1 ] || [ ! -f "$HERE/build/cpuz165_stub.sys" ]; then
    "$HERE/build.sh"
fi

cp -f "$HERE/build/cpuz165_stub.sys" "$DRIVERS_DIR/cpuz165_stub.sys"

export WINEPREFIX=$PREFIX

# CPU-Z creates and deletes a service named "cpuz165" for its own driver.
# Use a different service name so CPU-Z cannot replace the stub; the device
# it creates is still named \Device\cpuz165.  Clean up the old name used by
# earlier versions of this adapter.
"$WINE" sc stop cpuz165 >/dev/null 2>&1 || true
"$WINE" sc delete cpuz165 >/dev/null 2>&1 || true
"$WINE" sc stop cpuz165_stub >/dev/null 2>&1 || true
"$WINE" sc delete cpuz165_stub >/dev/null 2>&1 || true
"$WINE" sc create cpuz165_stub type= kernel start= system binPath= "$SYSTEM_DRIVER_PATH"
"$WINE" sc start cpuz165_stub

# 32-bit CPU-Z enumerates display adapters through DXCore and crashes inside
# Wine's WoW64 DXCore path before it ever reaches the driver.  Disable DXCore
# for this executable only so CPU-Z falls back to its other display path.
"$WINE" reg add "HKCU\\Software\\Wine\\AppDefaults\\cpuz_x32.exe\\DllOverrides" \
    /v dxcore /t REG_SZ /d disabled /f >/dev/null

echo "==> cpuz165 stub installed in $PREFIX"
echo "    run: WINEPREFIX=$PREFIX $WINE /path/to/cpuz_x64.exe"
echo "    run: WINEPREFIX=$PREFIX $WINE /path/to/cpuz_x32.exe"
echo "    note: the cpuz_x32.exe DXCore override is applied automatically."
echo "    note: service cpuz165_stub is independent of CPU-Z's own cpuz165 service."
