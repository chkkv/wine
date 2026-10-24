# cpuz165 stub

Compatibility driver for **CPU-Z 3.x** under Wine.

## Why

CPU-Z uses its own kernel driver (`cpuz165.sys`, service `cpuz165`) to read
MSRs, PCI configuration space, SMBus/SPD and chipset registers.  It extracts
the driver to
`C:\ProgramData\CPUID Software\cpu-z\<random>` and calls `NtLoadDriver`.

Wine cannot load the real driver:

```
err:ntoskrnl:ZwLoadDriver failed to create driver
  L"\\Registry\\Machine\\System\\CurrentControlSet\\Services\\cpuz165": c0000142
```

`c0000142` is `STATUS_DLL_INIT_FAILED`; the native driver imports kernel and
HAL routines (`MmMapIoSpace`, `HalGetBusDataByOffset`, `SeSinglePrivilegeCheck`,
...) that Wine does not provide.  CPU-Z then shows:

```
CPU-Z Errors
  CPUID int driver error 1114 (0x45A)
```

After dismissing that dialog CPU-Z dereferences a NULL pointer
(`cpuz_x64.exe+0x413E0`, `mov rcx,[rcx+0x8268]`) and crashes.

## What the stub does

The stub is a PE driver loaded by Wine's `ntoskrnl` through the normal
service path.  It is registered as **`cpuz165_stub`**, not `cpuz165`:
CPU-Z creates and deletes a service named `cpuz165` for its own driver, and
reusing that name let CPU-Z remove or replace the stub between runs.  The
device name is still the one CPU-Z expects.

It provides:

- service `cpuz165_stub` (`start= system`, loads with every Wine session)
- device `\Device\cpuz165` and symlink `\DosDevices\cpuz165`
- the three handshake IOCTLs used by the real 1.65 driver:

| IOCTL | Output | Stub answer |
|---|---|---|
| `0x9c402400` | `ULONG` driver version | `0x165` (1.65) |
| `0x9c402404` | `ULONG` major, minor, build | `PsGetVersion()` result |
| `0x9c402408` | `ULONG` open handle count | current count |

- every other IOCTL succeeds and returns a zeroed output buffer

The version answer is what makes CPU-Z accept the driver: with a zero
version it still crashes after the error dialog; with `0x165` it starts and
runs normally.

## 32-bit CPU-Z

`cpuz_x32.exe` uses the same stub service and device; no separate 32-bit
driver is needed in a WoW64 prefix.  However, before touching the driver it
enumerates
display adapters through `DXCore.dll`, and Wine's 32-bit DXCore path faults
inside `wow64cpu.dll`:

```
wine: Unhandled page fault on read access to 0x00005DC9
  at address 7BC5123D (wow64cpu.dll)
```

Disabling DXCore for `cpuz_x32.exe` makes CPU-Z fall back to its other display
path, after which it reaches the stub driver and runs normally.  `install.sh`
applies a per-application override:

```sh
wine reg add 'HKCU\Software\Wine\AppDefaults\cpuz_x32.exe\DllOverrides' \
    /v dxcore /t REG_SZ /d disabled /f
```

This affects only `cpuz_x32.exe` in that prefix, not other applications or
the 64-bit executable.

## Limitations

This is an **empty-data** shim, not real hardware support.  CPU-Z's
driver-backed pages (SPD, chipset, sensors, some clocks/voltages) show zero
or meaningless values.  Data that CPU-Z obtains through CPUID/Windows APIs
still works.  The real driver cannot be used under Wine without implementing
its MSR/PCI/SMBus IOCTLs and the underlying privileged hardware access.

## Build and install

```sh
third_party/app-support/cpuz165/build.sh
third_party/app-support/cpuz165/install.sh --prefix "$HOME/.wine"
```

`install.sh` copies `cpuz165_stub.sys` to
`drive_c/windows/system32/drivers/`, then runs:

```sh
# remove the service name used by older versions of this adapter
wine sc stop   cpuz165
wine sc delete cpuz165

wine sc stop   cpuz165_stub
wine sc delete cpuz165_stub
wine sc create cpuz165_stub type= kernel start= system \
    binPath= 'C:\windows\system32\drivers\cpuz165_stub.sys'
wine sc start  cpuz165_stub

wine reg add 'HKCU\Software\Wine\AppDefaults\cpuz_x32.exe\DllOverrides' \
    /v dxcore /t REG_SZ /d disabled /f
```

Because `\\.\cpuz165` already exists when CPU-Z starts, it uses that device
and never installs its own driver, so there is no per-run reinstall step.
The service survives a wineserver restart (`start= system`) and is loaded
before CPU-Z runs.

## Verified

With the stub installed:

- `cpuz_x64.exe` starts, shows its main window and no longer crashes.
- `cpuz_x32.exe` starts and no longer crashes once the per-app DXCore
  override is in place.
- A probe of `\\.\cpuz165` (IOCTL `0x9c402400`) returns version `0x165` after
  a fresh Wine session, before CPU-Z starts.
- When the driver is loaded on demand by CPU-Z, 433 device opens / 777 IOCTLs
  are logged.  When the driver was already loaded by the service manager, the
  IRP dispatch runs in the service process and those lines appear in a
  different log; the device probe is the reliable check.
- CPU-Z does not create its own `cpuz165` service or try to load its native
  driver once the stub device exists.
- The UI reports the CPUID-visible CPU (`VirtualApple @ 2.50GHz`, 1 thread)
  while driver-backed fields are empty.
