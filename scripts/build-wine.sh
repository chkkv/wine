#!/bin/bash
# Build the portable x86_64 Wine tree (x86_64 unixlibs + x86_64/i386 PE DLLs).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

PREFIX="$DEFAULT_BUILD_ROOT/wine"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$DEFAULT_BUILD_ROOT/toolchain}"
MOLTENVK_DIR="${MOLTENVK_DIR:-}"
WINE_BUILD_DIR="${WINE_BUILD_DIR:-$DEFAULT_BUILD_ROOT/wine-build}"
JOBS_ARG=""
LDFLAGS_EXTRA="${LDFLAGS:-}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build Wine for macOS x86_64 (with i386 PE support).

Options:
  --prefix=DIR     Wine installation directory (default: $PREFIX)
  --toolchain=DIR  toolchain directory from prepare-tools.sh
                   (default: $TOOLCHAIN_DIR)
  --moltenvk=DIR   directory containing libMoltenVK.dylib (optional)
  --jobs=N         parallel build jobs (default: $JOBS)
  -h, --help       show this help

Environment:
  WINE_BUILD_DIR   out-of-tree build directory
  FREETYPE_DIR     FreeType installation directory
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix=*)    PREFIX=${1#*=}; shift ;;
        --prefix)      require_value "$@"; PREFIX=$2; shift 2 ;;
        --toolchain=*) TOOLCHAIN_DIR=${1#*=}; shift ;;
        --toolchain)   require_value "$@"; TOOLCHAIN_DIR=$2; shift 2 ;;
        --moltenvk=*)  MOLTENVK_DIR=${1#*=}; shift ;;
        --moltenvk)    require_value "$@"; MOLTENVK_DIR=$2; shift 2 ;;
        --jobs=*)      JOBS_ARG=${1#*=}; shift ;;
        --jobs)        require_value "$@"; JOBS_ARG=$2; shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "unknown option: $1 (use --help)" ;;
    esac
done

[ -n "$JOBS_ARG" ] && JOBS=$JOBS_ARG
PREFIX=$(normalize_dir "$PREFIX")
TOOLCHAIN_DIR=$(normalize_dir "$TOOLCHAIN_DIR")

if [ -f "$TOOLCHAIN_DIR/toolchain.env" ]; then
    # shellcheck disable=SC1091
    source "$TOOLCHAIN_DIR/toolchain.env"
fi

WINE_TOOLS_DIR=${WINE_TOOLS_DIR:-$TOOLCHAIN_DIR/wine-tools}
FREETYPE_DIR=${FREETYPE_DIR:-$TOOLCHAIN_DIR/freetype-x64}

require_cmd clang
require_cmd make
[ -x "$WINE_TOOLS_DIR/tools/winebuild/winebuild" ] || \
    die "Wine tools not found in $WINE_TOOLS_DIR; run scripts/prepare-tools.sh first"
[ -f "$FREETYPE_DIR/lib/libfreetype.6.dylib" ] || \
    die "FreeType not found in $FREETYPE_DIR; run scripts/prepare-tools.sh first"
[ -x "$ROOT_DIR/configure" ] || die "Wine configure not found in $ROOT_DIR"

BREW_PREFIX=$(brew --prefix 2>/dev/null || true)
if [ -n "$BREW_PREFIX" ]; then
    export PATH="$BREW_PREFIX/opt/bison/bin:$BREW_PREFIX/bin:$PATH"
fi

MVK_LDFLAGS=""
MVK_DYLIB=""
if [ -n "$MOLTENVK_DIR" ]; then
    MVK_DYLIB=$(find "$MOLTENVK_DIR" -name libMoltenVK.dylib | head -n 1 || true)
    [ -n "$MVK_DYLIB" ] || die "libMoltenVK.dylib not found under $MOLTENVK_DIR"
    MVK_LDFLAGS="-L$(dirname "$MVK_DYLIB")"
fi

BUILD_ARCH="$(uname -m)"
[ "$BUILD_ARCH" = "arm64" ] && BUILD_ARCH="aarch64"

mkdir -p "$WINE_BUILD_DIR"
log "configuring Wine (x86_64 + i386 PE)"
(
    cd "$WINE_BUILD_DIR"
    "$ROOT_DIR/configure" \
        --build="$BUILD_ARCH-apple-darwin" \
        --host=x86_64-apple-darwin \
        --with-wine-tools="$WINE_TOOLS_DIR" \
        --enable-archs=i386,x86_64 \
        --prefix="$PREFIX" \
        CC="clang -arch x86_64" \
        CXX="clang++ -arch x86_64" \
        LDFLAGS="$LDFLAGS_EXTRA $MVK_LDFLAGS" \
        FREETYPE_CFLAGS="-I$FREETYPE_DIR/include/freetype2" \
        FREETYPE_LIBS="-L$FREETYPE_DIR/lib -lfreetype" \
        MACOSX_DEPLOYMENT_TARGET=11.0

    log "building Wine"
    make -j "$JOBS"

    log "installing Wine to $PREFIX"
    make install
)

UNIXLIB_DIR="$PREFIX/lib/wine/x86_64-unix"
mkdir -p "$UNIXLIB_DIR"

cp -f "$FREETYPE_DIR/lib/libfreetype.6.dylib" "$UNIXLIB_DIR/"
ln -sfn wine/x86_64-unix/libfreetype.6.dylib "$PREFIX/lib/libfreetype.6.dylib"
ln -sfn libfreetype.6.dylib "$PREFIX/lib/libfreetype.dylib"

if [ -n "$MVK_DYLIB" ]; then
    cp -f "$MVK_DYLIB" "$UNIXLIB_DIR/"
    ln -sfn wine/x86_64-unix/libMoltenVK.dylib "$PREFIX/lib/libMoltenVK.dylib"
fi

log "Wine installed: $PREFIX"
