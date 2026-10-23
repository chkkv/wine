#!/bin/bash
# Build DXMT from the commit referenced in ref.sh.
set -euo pipefail

: "${DEP_SRC:?DEP_SRC is required}"
: "${LLVM_DIR:?LLVM_DIR is required}"
: "${DXMT_WINE_DIR:?DXMT_WINE_DIR is required}"

cd "$DEP_SRC"

meson setup --cross-file build-win64.txt \
    -Dnative_llvm_path="$LLVM_DIR" \
    -Dwine_install_path="$DXMT_WINE_DIR" \
    -Dwine_builtin_dll=true \
    build --buildtype release --prefix="$DEP_SRC/install" --strip

meson compile -C build -j "${JOBS:-4}"
meson install -C build
