#!/bin/bash
# Build the cpuz165 compatibility driver for Wine.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
OUT=${OUT:-"$HERE/build"}
CC=${CC:-x86_64-w64-mingw32-gcc}
SRC="$HERE/cpuz165_stub.c"

command -v "$CC" >/dev/null 2>&1 || {
    echo "error: $CC not found (brew install mingw-w64)" >&2
    exit 1
}
[ -f "$SRC" ] || { echo "error: source not found: $SRC" >&2; exit 1; }

SYSROOT=$("$CC" -print-sysroot)
DDK="$SYSROOT/x86_64-w64-mingw32/include/ddk"
if [ ! -d "$DDK" ]; then
    echo "error: mingw-w64 DDK headers not found under $SYSROOT" >&2
    exit 1
fi

mkdir -p "$OUT"
"$CC" -I"$DDK" \
    -shared -nostartfiles -nostdlib \
    -Wl,--entry,DriverEntry -Wl,--subsystem,native \
    -o "$OUT/cpuz165_stub.sys" "$SRC" \
    -lntoskrnl -lhal -lgcc

echo "built $OUT/cpuz165_stub.sys"
