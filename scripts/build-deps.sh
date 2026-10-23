#!/bin/bash
# Clone, build and install one dependency described by third_party/*/ref.sh.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

REF=""
DEST=""
WORK="$DEFAULT_BUILD_ROOT/deps-src"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$DEFAULT_BUILD_ROOT/toolchain}"
JOBS_ARG=""
FORCE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") --ref=DIR [options]

Reuse or build a dependency at the commit pinned in its ref.sh.

Options:
  --ref=DIR        dependency directory containing ref.sh (required)
  --dest=DIR       installation root for artifacts (default: build/deps/NAME)
  --work=DIR       source/clone working directory (default: $WORK)
  --toolchain=DIR  toolchain directory from prepare-tools.sh
  --jobs=N         parallel build jobs (default: $JOBS)
  --force          rebuild even if the cached artifacts are present
  -h, --help       show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --ref=*)       REF=${1#*=}; shift ;;
        --ref)         require_value "$@"; REF=$2; shift 2 ;;
        --dest=*)      DEST=${1#*=}; shift ;;
        --dest)        require_value "$@"; DEST=$2; shift 2 ;;
        --work=*)      WORK=${1#*=}; shift ;;
        --work)        require_value "$@"; WORK=$2; shift 2 ;;
        --toolchain=*) TOOLCHAIN_DIR=${1#*=}; shift ;;
        --toolchain)   require_value "$@"; TOOLCHAIN_DIR=$2; shift 2 ;;
        --jobs=*)      JOBS_ARG=${1#*=}; shift ;;
        --jobs)        require_value "$@"; JOBS_ARG=$2; shift 2 ;;
        --force)       FORCE=1; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "unknown option: $1 (use --help)" ;;
    esac
done

[ -n "$JOBS_ARG" ] && JOBS=$JOBS_ARG
[ -n "$REF" ] || die "--ref=DIR is required"

if [ -d "$REF" ]; then
    REF="$REF/ref.sh"
fi
[ -f "$REF" ] || die "reference file not found: $REF"

REF_DIR=$(cd "$(dirname "$REF")" && pwd -P)
REF="$REF_DIR/$(basename "$REF")"
BUILD_SCRIPT="$REF_DIR/build.sh"
[ -f "$BUILD_SCRIPT" ] || die "build script not found: $BUILD_SCRIPT"

# shellcheck disable=SC1090
source "$REF"

: "${DEP_NAME:?DEP_NAME is required}"
: "${DEP_REPO:?DEP_REPO is required}"
: "${DEP_COMMIT:?DEP_COMMIT is required}"

TOOLCHAIN_DIR=$(normalize_dir "$TOOLCHAIN_DIR")
if [ -f "$TOOLCHAIN_DIR/toolchain.env" ]; then
    # shellcheck disable=SC1091
    source "$TOOLCHAIN_DIR/toolchain.env"
fi

WORK=$(normalize_dir "$WORK")
[ -n "$DEST" ] || DEST="$DEFAULT_BUILD_ROOT/deps/$DEP_NAME"
DEST=$(normalize_dir "$DEST")

shopt -s nullglob

artifacts_present() {
    local mapping to files
    for mapping in "${DEP_ARTIFACTS[@]}"; do
        to=${mapping#*|}
        if [[ "$to" == */ ]]; then
            files=("$DEST/$to"*)
            [ ${#files[@]} -gt 0 ] || return 1
        else
            [ -f "$DEST/$to" ] || return 1
        fi
    done
    return 0
}

STAMP_DIR="$WORK/.stamps"
STAMP="$STAMP_DIR/$DEP_NAME"
BUILD_KEY="$DEP_REPO:$DEP_COMMIT:$(shasum -a 256 "$BUILD_SCRIPT" | awk '{print $1}')"
mkdir -p "$STAMP_DIR"

if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ] && \
   [ "$(cat "$STAMP")" = "$BUILD_KEY" ] && artifacts_present; then
    log "$DEP_NAME already built at $DEP_COMMIT"
    exit 0
fi
rm -f "$STAMP"

SRC="$WORK/$DEP_NAME"
REMOTE_URL=$(git -C "$SRC" remote get-url origin 2>/dev/null || true)
if [ -d "$SRC/.git" ] && [ "$REMOTE_URL" = "$DEP_REPO" ]; then
    log "reusing $DEP_NAME source at $SRC"
else
    log "fetching $DEP_NAME at $DEP_COMMIT"
    rm -rf "$SRC"
    git clone --depth 1 "$DEP_REPO" "$SRC"
fi

if ! git -C "$SRC" cat-file -e "$DEP_COMMIT^{commit}" 2>/dev/null; then
    log "fetching $DEP_NAME commit $DEP_COMMIT"
    if ! git -C "$SRC" fetch --depth 1 origin "$DEP_COMMIT"; then
        warn "shallow fetch failed, fetching full history for $DEP_NAME"
        git -C "$SRC" fetch --unshallow || git -C "$SRC" fetch origin
    fi
fi
git -C "$SRC" checkout --detach "$DEP_COMMIT" 2>/dev/null || \
    git -C "$SRC" checkout --detach --force "$DEP_COMMIT"

if [ "${DEP_RECURSIVE:-0}" = "1" ]; then
    git -C "$SRC" submodule update --init --recursive
fi

log "building $DEP_NAME"
export DEP_NAME DEP_SRC="$SRC" DEP_INSTALL="$SRC/install"
export TOOLCHAIN_DIR JOBS LLVM_DIR DXMT_WINE_DIR
(
    cd "$SRC"
    bash "$BUILD_SCRIPT"
)

shopt -s nullglob
for mapping in "${DEP_ARTIFACTS[@]}"; do
    from=${mapping%%|*}
    to=${mapping#*|}

    matches=("$SRC"/$from)
    [ ${#matches[@]} -gt 0 ] || die "artifact not found: $DEP_NAME/$from"

    if [[ "$to" == */ ]]; then
        mkdir -p "$DEST/$to"
        cp -f "${matches[@]}" "$DEST/$to/"
    else
        [ ${#matches[@]} -eq 1 ] || die "artifact pattern must match one file: $DEP_NAME/$from"
        mkdir -p "$(dirname "$DEST/$to")"
        cp -f "${matches[0]}" "$DEST/$to"
    fi
done

printf '%s\n' "$BUILD_KEY" > "$STAMP"
log "$DEP_NAME installed to $DEST"
