#!/bin/bash
# Build MoltenVK from the commit referenced in ref.sh.
set -euo pipefail

: "${DEP_SRC:?DEP_SRC is required}"

cd "$DEP_SRC"

# MoltenVK's build script pulls its external dependency revisions.
./fetchDependencies --macos
make macos
