/*
 * cpuz165_stub -- CPU-Z hardware driver shim for Wine.
 *
 * CPU-Z installs a kernel driver named cpuz165 to read MSRs, PCI config
 * space, SMBus and chipset registers.  Wine cannot load that native driver
 * (NtLoadDriver fails with STATUS_DLL_INIT_FAILED) and CPU-Z then crashes
 * with a NULL dereference after showing "CPUID int driver error 1114".
 *
 * This shim provides the same device name and the small handshake protocol
 * CPU-Z needs to accept the driver.  Every other IOCTL succeeds and returns
 * zeroed data, so CPU-Z starts and stays usable, but hardware readings that
 * normally come from the driver are empty/nonsense.
 *
 * Build with scripts/build.sh, install with scripts/install.sh.
 */

#include <ntddk.h>

#define CPUZ_DEVICE_NAME    L"\\Device\\cpuz165"
#define CPUZ_SYMLINK_NAME   L"\\DosDevices\\cpuz165"

/* IOCTL codes used by the CPU-Z 1.65 driver (decoded from cpuz165_x64.sys). */
#define IOCTL_CPUZ_VERSION  0x9c402400  /* out: ULONG driver version, 0x165 */
#define IOCTL_CPUZ_OSVER    0x9c402404  /* out: ULONG major, minor, build */
#define IOCTL_CPUZ_OPENCNT  0x9c402408  /* out: ULONG open handle count */

static ULONG open_count;

static NTSTATUS WINAPI dispatch_create(DEVICE_OBJECT *device, IRP *irp)
{
    UNREFERENCED_PARAMETER(device);

    DbgPrint("cpuz165_stub: create\n");
    open_count++;
    irp->IoStatus.Status = STATUS_SUCCESS;
    irp->IoStatus.Information = 0;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return STATUS_SUCCESS;
}

static NTSTATUS WINAPI dispatch_close(DEVICE_OBJECT *device, IRP *irp)
{
    UNREFERENCED_PARAMETER(device);

    DbgPrint("cpuz165_stub: close\n");
    if (open_count) open_count--;
    irp->IoStatus.Status = STATUS_SUCCESS;
    irp->IoStatus.Information = 0;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return STATUS_SUCCESS;
}

static NTSTATUS WINAPI dispatch_ioctl(DEVICE_OBJECT *device, IRP *irp)
{
    IO_STACK_LOCATION *sp = IoGetCurrentIrpStackLocation(irp);
    ULONG code = sp->Parameters.DeviceIoControl.IoControlCode;
    ULONG in_len = sp->Parameters.DeviceIoControl.InputBufferLength;
    ULONG out_len = sp->Parameters.DeviceIoControl.OutputBufferLength;
    void *buf = irp->AssociatedIrp.SystemBuffer;
    ULONG i, info = 0;
    NTSTATUS status = STATUS_SUCCESS;

    UNREFERENCED_PARAMETER(device);

    DbgPrint("cpuz165_stub: ioctl code=%08lx in=%lu out=%lu\n", code, in_len, out_len);

    switch (code)
    {
    case IOCTL_CPUZ_VERSION:
        if (!buf || out_len < sizeof(ULONG)) { status = STATUS_BUFFER_TOO_SMALL; break; }
        *(ULONG *)buf = 0x165;  /* driver 1.65, the version CPU-Z 3.01 expects */
        info = sizeof(ULONG);
        break;

    case IOCTL_CPUZ_OSVER:
    {
        ULONG major = 0, minor = 0, build = 0;

        if (!buf || out_len < 3 * sizeof(ULONG)) { status = STATUS_BUFFER_TOO_SMALL; break; }
        PsGetVersion(&major, &minor, &build, NULL);
        ((ULONG *)buf)[0] = major;
        ((ULONG *)buf)[1] = minor;
        ((ULONG *)buf)[2] = build;
        info = 3 * sizeof(ULONG);
        break;
    }

    case IOCTL_CPUZ_OPENCNT:
        if (!buf || out_len < sizeof(ULONG)) { status = STATUS_BUFFER_TOO_SMALL; break; }
        *(ULONG *)buf = open_count;
        info = sizeof(ULONG);
        break;

    default:
        /* Empty answer: succeed, and zero the output buffer. */
        if (buf)
        {
            DbgPrint("cpuz165_stub: input:");
            for (i = 0; i < in_len && i < 64; i++)
                DbgPrint(" %02x", ((unsigned char *)buf)[i]);
            DbgPrint("\n");
            if (out_len) RtlZeroMemory(buf, out_len);
        }
        info = out_len;
        break;
    }

    irp->IoStatus.Status = status;
    irp->IoStatus.Information = info;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return status;
}

static void WINAPI driver_unload(DRIVER_OBJECT *driver)
{
    UNICODE_STRING symlink;

    DbgPrint("cpuz165_stub: unload\n");

    RtlInitUnicodeString(&symlink, CPUZ_SYMLINK_NAME);
    IoDeleteSymbolicLink(&symlink);
    if (driver->DeviceObject) IoDeleteDevice(driver->DeviceObject);
}

NTSTATUS WINAPI DriverEntry(DRIVER_OBJECT *driver, UNICODE_STRING *path)
{
    UNICODE_STRING device_name, symlink_name;
    DEVICE_OBJECT *device;
    NTSTATUS status;

    UNREFERENCED_PARAMETER(path);

    DbgPrint("cpuz165_stub: DriverEntry\n");

    RtlInitUnicodeString(&device_name, CPUZ_DEVICE_NAME);
    RtlInitUnicodeString(&symlink_name, CPUZ_SYMLINK_NAME);

    status = IoCreateDevice(driver, 0, &device_name, FILE_DEVICE_UNKNOWN,
                            0, FALSE, &device);
    if (status != STATUS_SUCCESS)
    {
        DbgPrint("cpuz165_stub: IoCreateDevice failed %08lx\n", status);
        return status;
    }

    status = IoCreateSymbolicLink(&symlink_name, &device_name);
    if (status != STATUS_SUCCESS)
    {
        DbgPrint("cpuz165_stub: IoCreateSymbolicLink failed %08lx\n", status);
        IoDeleteDevice(device);
        return status;
    }

    driver->MajorFunction[IRP_MJ_CREATE] = dispatch_create;
    driver->MajorFunction[IRP_MJ_CLOSE] = dispatch_close;
    driver->MajorFunction[IRP_MJ_CLEANUP] = dispatch_close;
    driver->MajorFunction[IRP_MJ_DEVICE_CONTROL] = dispatch_ioctl;
    driver->DriverUnload = driver_unload;

    return STATUS_SUCCESS;
}
