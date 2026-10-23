#!/bin/bash
# Build Wine, MoltenVK and DXMT into one installation root.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

PREFIX="$DEFAULT_BUILD_ROOT"
JOBS_ARG=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build toolchains, Wine, MoltenVK and DXMT.

Layout under --prefix:
  toolchain/   prepared toolchains
  wine/        portable Wine installation (+ DXMT)
  deps/        staged MoltenVK
  work/        dependency source trees

Options:
  --prefix=DIR   output/install root (default: $PREFIX)
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
OUT=$(normalize_dir "$PREFIX")
TOOLCHAIN_DIR="$OUT/toolchain"
WINE_DIR="$OUT/wine"
DEPS_DIR="$OUT/deps"
WORK_DIR="$OUT/work"

[ -d "$ROOT_DIR/third_party/moltenvk" ] || die "third_party/moltenvk is missing"
[ -d "$ROOT_DIR/third_party/dxmt" ] || die "third_party/dxmt is missing"

log "preparing toolchains in $TOOLCHAIN_DIR"
"$SCRIPT_DIR/prepare-tools.sh" --prefix="$TOOLCHAIN_DIR" --jobs="$JOBS"

# shellcheck disable=SC1091
source "$TOOLCHAIN_DIR/toolchain.env"

log "building MoltenVK"
"$SCRIPT_DIR/build-deps.sh" \
    --ref "$ROOT_DIR/third_party/moltenvk" \
    --dest "$DEPS_DIR/moltenvk" \
    --work "$WORK_DIR" \
    --toolchain "$TOOLCHAIN_DIR" \
    --jobs "$JOBS"

log "building Wine"
TOOLCHAIN_DIR="$TOOLCHAIN_DIR" \
WINE_BUILD_DIR="$OUT/build-wine" \
"$SCRIPT_DIR/build-wine.sh" \
    --prefix "$WINE_DIR" \
    --toolchain "$TOOLCHAIN_DIR" \
    --moltenvk "$DEPS_DIR/moltenvk" \
    --jobs "$JOBS"

log "building DXMT into Wine"
"$SCRIPT_DIR/build-deps.sh" \
    --ref "$ROOT_DIR/third_party/dxmt" \
    --dest "$WINE_DIR" \
    --work "$WORK_DIR" \
    --toolchain "$TOOLCHAIN_DIR" \
    --jobs "$JOBS"

log "done"
echo "  Wine:      $WINE_DIR"
echo "  toolchain: $TOOLCHAIN_DIR"
echo "  MoltenVK:  $DEPS_DIR/moltenvk"
