# DXMT dependency reference.
# Consumed by scripts/build-deps.sh.

DEP_NAME=dxmt
DEP_REPO=https://github.com/3Shain/dxmt.git
DEP_COMMIT=a148782d431249405acdb1531dbb0c7e737bbece
DEP_RECURSIVE=1

# from (relative to the dependency source tree) | to (relative to Wine install)
DEP_ARTIFACTS=(
    "install/x86_64-unix/winemetal.so|lib/wine/x86_64-unix/winemetal.so"
    "install/x86_64-windows/*.dll|lib/wine/x86_64-windows/"
)
