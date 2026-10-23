# third_party

Dependency references for the portable Wine build.

Each dependency directory contains:

- `ref.sh` — source repository, pinned commit, recursive-submodule flag and
  artifact mappings.
- `build.sh` — dependency-specific build commands. It receives:
  - `DEP_NAME`
  - `DEP_SRC` (checked-out source directory)
  - `DEP_INSTALL`
  - `TOOLCHAIN_DIR`
  - `LLVM_DIR`
  - `DXMT_WINE_DIR`
  - `JOBS`

`scripts/build-deps.sh` clones the repository, checks out the pinned commit,
runs `build.sh`, then copies artifacts according to `DEP_ARTIFACTS`.

Artifact mapping format:

```sh
DEP_ARTIFACTS=(
    "path/inside/source|path/inside/wine/install"
    "path/inside/source/*.dll|lib/wine/x86_64-windows/"
)
```

- The left side is relative to `DEP_SRC`.
- The right side is relative to the Wine installation root.
- A trailing `/` means the destination is a directory.
- A missing artifact aborts the build.

## Updating a dependency

1. Change `DEP_COMMIT` in `ref.sh` to the desired commit.
2. Update `build.sh` if the upstream build system changed.
3. Update `DEP_ARTIFACTS` if output paths changed.
4. Run `scripts/build-deps.sh --ref third_party/<name>` to verify.

## Current dependencies

| Directory | Upstream | Purpose |
|---|---|---|
| `moltenvk/` | KhronosGroup/MoltenVK | Vulkan backend (Metal) |
| `dxmt/` | 3Shain/dxmt | D3D10/D3D11 backend (Metal) |

MoltenVK is built from source at the pinned commit; its external dependency
revisions are controlled by MoltenVK's `fetchDependencies`/`ExternalRevisions`.
DXMT is built with LLVM 15 and Wine 8.16 tools prepared by
`scripts/prepare-tools.sh`.
