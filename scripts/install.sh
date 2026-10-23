#!/bin/bash
# Install a built portable Wine tree into a destination directory.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd -P)
DEST=""
SRC=""
FORCE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] <destination>

Install a portable Wine tree into <destination>.

The source defaults to <repo>/build/wine.

Options:
  --source=DIR   Wine tree to install (default: $ROOT_DIR/build/wine)
  --force        replace <destination> if it already contains files
  -h, --help     show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --source=*) SRC=${1#*=}; shift ;;
        --source)   [ $# -ge 2 ] || { echo "error: --source requires a value" >&2; exit 1; }
                    SRC=$2; shift 2 ;;
        --force)    FORCE=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*)         echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)
            [ -z "$DEST" ] || { echo "error: destination specified more than once" >&2; exit 1; }
            DEST=$1
            shift
            ;;
    esac
done

[ -n "$DEST" ] || { usage >&2; exit 1; }

if [ -z "$SRC" ]; then
    SRC="$ROOT_DIR/build/wine"
fi

[ -d "$SRC" ] || { echo "error: Wine source directory not found: $SRC" >&2; exit 1; }
SRC=$(cd "$SRC" && pwd -P)
[ -x "$SRC/bin/wine" ] || { echo "error: not a Wine installation tree: $SRC" >&2; exit 1; }

mkdir -p "$DEST"
DEST=$(cd "$DEST" && pwd -P)

[ "$SRC" != "$DEST" ] || { echo "error: source and destination are the same: $DEST" >&2; exit 1; }
case "$DEST" in
    /|"$HOME")
        echo "error: refusing to install into $DEST" >&2
        exit 1
        ;;
esac
case "$DEST/" in
    "$SRC"/*)
        echo "error: destination must not be inside the source tree: $DEST" >&2
        exit 1
        ;;
esac

if [ -n "$(ls -A "$DEST" 2>/dev/null || true)" ] && [ "$FORCE" -ne 1 ]; then
    echo "error: destination is not empty: $DEST" >&2
    echo "       use --force to replace it" >&2
    exit 1
fi

TMP_DEST="${DEST}.installing.$$"
trap 'rm -rf "$TMP_DEST"' EXIT
rm -rf "$TMP_DEST"
mkdir -p "$TMP_DEST"

# ditto preserves symlinks and permissions, which the Wine tree relies on.
ditto "$SRC/" "$TMP_DEST/"

# Do not keep a top-level launcher: the real binary is bin/wine.
rm -f "$TMP_DEST/wine"

rm -rf "$DEST"
mv "$TMP_DEST" "$DEST"
trap - EXIT

echo "==> Wine installed to $DEST"
echo "    run: $DEST/bin/wine"
