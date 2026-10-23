#!/bin/bash
# Prepare the macOS toolchains used to build Wine, DXMT and MoltenVK.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

PREFIX="$DEFAULT_BUILD_ROOT/toolchain"
JOBS_ARG=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Prepare Homebrew packages, Metal Toolchain, LLVM 15 (x86_64),
Wine 8.16 (DXMT build tools), native Wine tools and x86_64 FreeType.

Options:
  --prefix=DIR   toolchain installation directory (default: $PREFIX)
  --jobs=N       parallel build jobs (default: $JOBS)
  -h, --help     show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix=*) PREFIX=${1#*=}; shift ;;
        --prefix)   require_value "$@"; PREFIX=$2; shift 2 ;;
        --jobs=*)   JOBS_ARG=${1#*=}; shift ;;
        --jobs)     require_value "$@"; JOBS_ARG=$2; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "unknown option: $1 (use --help)" ;;
    esac
done

[ -n "$JOBS_ARG" ] && JOBS=$JOBS_ARG
PREFIX=$(normalize_dir "$PREFIX")
TOOLCHAIN_DIR=$PREFIX

require_cmd brew
require_cmd git
require_cmd curl
require_cmd tar
require_cmd xcodebuild
require_cmd xcrun

BREW_PREFIX=$(brew --prefix)
export PATH="$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/bin:$PATH"

log "installing Homebrew build dependencies"
brew install bison pkg-config meson ninja cmake mingw-w64 xz freetype

require_cmd cmake
require_cmd meson
require_cmd ninja
require_cmd x86_64-w64-mingw32-gcc

if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
    log "downloading Metal Toolchain"
    if ! xcodebuild -downloadComponent MetalToolchain; then
        sudo -n xcodebuild -downloadComponent MetalToolchain || \
            die "failed to install Metal Toolchain; run 'sudo xcodebuild -downloadComponent MetalToolchain'"
    fi
    xcrun -sdk macosx metal --version >/dev/null
fi

LLVM_DIR="$TOOLCHAIN_DIR/llvm-darwin"
LLVM_SRC="$TOOLCHAIN_DIR/llvm-project"
LLVM_BUILD="$TOOLCHAIN_DIR/llvm-darwin-build"

if [ ! -f "$LLVM_DIR/lib/libLLVMCore.a" ] || [ ! -x "$LLVM_DIR/bin/llvm-tblgen" ]; then
    log "building LLVM 15 x86_64"
    if [ ! -d "$LLVM_SRC/.git" ]; then
        git clone --depth 1 --branch llvmorg-15.0.7 \
            https://github.com/llvm/llvm-project.git "$LLVM_SRC"
    fi
    rm -rf "$LLVM_BUILD"
    cmake -B "$LLVM_BUILD" -S "$LLVM_SRC/llvm" \
        -DCMAKE_INSTALL_PREFIX="$LLVM_DIR" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
        -DLLVM_ENABLE_ASSERTIONS=Off \
        -DLLVM_ENABLE_ZSTD=Off \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23" \
        -DLLVM_TARGETS_TO_BUILD="" \
        -DLLVM_BUILD_TOOLS=Off \
        -DLLVM_INCLUDE_BENCHMARKS=Off \
        -DBUG_REPORT_URL="https://github.com/3Shain/dxmt" \
        -DPACKAGE_VENDOR="DXMT" \
        -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off \
        -G Ninja
    cmake --build "$LLVM_BUILD" -j "$JOBS"
    cmake --install "$LLVM_BUILD"
else
    log "LLVM 15 already prepared: $LLVM_DIR"
fi

DXMT_WINE_DIR="$TOOLCHAIN_DIR/wine-dxmt"
if [ ! -x "$DXMT_WINE_DIR/bin/winebuild" ]; then
    log "downloading Wine 8.16 for DXMT"
    mkdir -p "$DXMT_WINE_DIR"
    curl -sL --fail -o "$TOOLCHAIN_DIR/wine-8.16.tar.gz" \
        https://github.com/3Shain/wine/releases/download/v8.16-3shain/wine.tar.gz
    tar -xzf "$TOOLCHAIN_DIR/wine-8.16.tar.gz" -C "$DXMT_WINE_DIR"
else
    log "DXMT Wine already prepared: $DXMT_WINE_DIR"
fi

WINE_TOOLS_DIR="$TOOLCHAIN_DIR/wine-tools"
if [ ! -x "$WINE_TOOLS_DIR/tools/winebuild/winebuild" ] || \
   [ ! -x "$WINE_TOOLS_DIR/tools/winegcc/winegcc" ] || \
   ! grep -q '^#define SONAME_LIBFREETYPE' "$WINE_TOOLS_DIR/include/config.h" 2>/dev/null; then
    log "building native Wine tools"
    rm -rf "$WINE_TOOLS_DIR"
    [ -x "$ROOT_DIR/configure" ] || (cd "$ROOT_DIR" && ./autogen.sh)
    mkdir -p "$WINE_TOOLS_DIR"
    FREETYPE_PREFIX=$(brew --prefix freetype)
    (
        cd "$WINE_TOOLS_DIR"
        FREETYPE_CFLAGS="-I$FREETYPE_PREFIX/include/freetype2" \
        FREETYPE_LIBS="-L$FREETYPE_PREFIX/lib -lfreetype" \
        "$ROOT_DIR/configure" \
            --enable-archs=none \
            --without-vulkan \
            --prefix="$WINE_TOOLS_DIR/install"
        make -C tools -j "$JOBS"
        make -C tools/winebuild -j "$JOBS"
        make -C tools/winegcc -j "$JOBS"
        make -C tools/widl -j "$JOBS"
        make -C tools/wrc -j "$JOBS"
        make -C tools/wmc -j "$JOBS"
        make -C tools/sfnt2fon -j "$JOBS"
    )
else
    log "native Wine tools already prepared: $WINE_TOOLS_DIR"
fi

if [ ! -x "$WINE_TOOLS_DIR/tools/sfnt2fon/sfnt2fon" ]; then
    log "building native Wine sfnt2fon"
    make -C "$WINE_TOOLS_DIR/tools/sfnt2fon" -j "$JOBS"
fi

if [ ! -f "$WINE_TOOLS_DIR/nls/locale.nls" ]; then
    log "preparing native Wine nls data"
    make -C "$WINE_TOOLS_DIR" -j "$JOBS" nls/all
fi

FREETYPE_DIR="$TOOLCHAIN_DIR/freetype-x64"
FREETYPE_SRC="$TOOLCHAIN_DIR/freetype-src"
if [ ! -f "$FREETYPE_DIR/lib/libfreetype.6.dylib" ]; then
    log "building x86_64 FreeType"
    rm -rf "$FREETYPE_SRC"
    mkdir -p "$FREETYPE_SRC"
    curl -sL --fail -o "$TOOLCHAIN_DIR/freetype.tar.xz" \
        https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz
    tar -xf "$TOOLCHAIN_DIR/freetype.tar.xz" -C "$FREETYPE_SRC" --strip-components=1
    (
        cd "$FREETYPE_SRC"
        ./configure \
            --prefix="$FREETYPE_DIR" \
            --host=x86_64-apple-darwin \
            --without-harfbuzz --without-png --without-brotli --without-zlib \
            CC="clang -arch x86_64" \
            CFLAGS="-O2 -arch x86_64 -mmacosx-version-min=11.0" \
            LDFLAGS="-mmacosx-version-min=11.0"
        make -j "$JOBS"
        make install
    )
else
    log "FreeType already prepared: $FREETYPE_DIR"
fi

cat > "$TOOLCHAIN_DIR/toolchain.env" <<EOF
TOOLCHAIN_DIR="$TOOLCHAIN_DIR"
LLVM_DIR="$LLVM_DIR"
DXMT_WINE_DIR="$DXMT_WINE_DIR"
WINE_TOOLS_DIR="$WINE_TOOLS_DIR"
FREETYPE_DIR="$FREETYPE_DIR"
EOF

log "toolchains ready"
echo "  $TOOLCHAIN_DIR/toolchain.env"
