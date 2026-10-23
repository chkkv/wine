#!/bin/bash
# Common helpers for the portable Wine build scripts.
# This file is meant to be sourced.

if [ -n "${WINE_BUILD_COMMON_LOADED:-}" ]; then
    return 0
fi
WINE_BUILD_COMMON_LOADED=1

case "${BASH_SOURCE[0]}" in
    "$0") echo "error: source scripts/common.sh instead of executing it" >&2; exit 1 ;;
esac

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
DEFAULT_BUILD_ROOT="$PWD/build"
JOBS=${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}

die()  { echo "error: $*" >&2; exit 1; }
log()  { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

normalize_dir() {
    local dir=$1
    mkdir -p "$dir"
    (cd "$dir" && pwd -P)
}

require_value() {
    [ $# -ge 2 ] || die "$1 requires a value"
}
