# MoltenVK dependency reference.
# Consumed by scripts/build-deps.sh.

DEP_NAME=moltenvk
DEP_REPO=https://github.com/KhronosGroup/MoltenVK.git
DEP_COMMIT=db66022459ffb663aa2b50f6b018bc2e124f5edf
DEP_RECURSIVE=0

# from (relative to the dependency source tree) | to (relative to Wine install)
DEP_ARTIFACTS=(
    "Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib|lib/wine/x86_64-unix/libMoltenVK.dylib"
)
