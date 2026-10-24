# app-support

Application-specific compatibility shims for the portable Wine build.

`third_party/` normally pins upstream dependencies (MoltenVK, DXMT) through
`ref.sh` / `build.sh`.  This directory is different: it contains small
adapters written for this tree that make a particular Windows application
work around a Wine limitation.  They are not Wine patches and not upstream
projects; they are loaded by the application or by Wine's service manager
inside the prefix.

## Layout

```
app-support/
  <app>/
    README.md        what the app needs and why
    *.c              adapter sources
    build.sh         build the adapter into build/
    install.sh       install into a Wine prefix and register it
```

## Current adapters

| Adapter | Application | What it does |
|---|---|---|
| `cpuz165/` | CPU-Z 3.x (x64 + x32) | Provides `\Device\cpuz165`, answers the driver handshake and returns empty data for hardware queries. Also disables DXCore for `cpuz_x32.exe` to work around a WoW64 crash. |

## Adding an adapter

1. Find out which OS facility the application needs (kernel driver, service,
   named pipe, device, registry layout, ...).
2. Implement the smallest shim that satisfies the application's startup and
   handshake paths.  Returning empty/zero data is preferable to guessing
   hardware values.
3. Add `build.sh` and `install.sh` following `cpuz165/` as an example.
4. Document the limitation in the adapter's `README.md` so nobody mistakes
   the shim for real hardware support.

These adapters are installed per Wine prefix, so keep `install.sh` free of
global side effects and print the exact commands it runs.
