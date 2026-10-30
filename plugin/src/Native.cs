using System.Runtime.InteropServices;

namespace Pitchside;

/// <summary>
/// Thin P/Invoke layer over the macOS kernel and dyld APIs we need.
/// Everything here reads our OWN process (the plugin runs inside FM), so no special
/// permissions or SIP changes are needed. mach_vm_read_overwrite is used instead of
/// raw pointer dereferences so that reading a page FM just freed returns an error
/// instead of crashing the game.
/// </summary>
internal static unsafe class Native
{
    private const string LibSystem = "/usr/lib/libSystem.B.dylib";

    public const int KERN_SUCCESS = 0;
    public const int VM_REGION_BASIC_INFO_64 = 9;
    public const int VM_PROT_READ = 1, VM_PROT_WRITE = 2, VM_PROT_EXECUTE = 4;

    [DllImport(LibSystem)]
    public static extern int mach_vm_read_overwrite(uint task, ulong address, ulong size, ulong data, out ulong outSize);

    [DllImport(LibSystem)]
    public static extern int mach_vm_region(uint task, ref ulong address, ref ulong size, int flavor,
                                            int* info, ref uint infoCount, out uint objectName);

    [DllImport(LibSystem)]
    public static extern int mach_port_deallocate(uint task, uint name);

    [DllImport(LibSystem)]
    public static extern uint _dyld_image_count();

    [DllImport(LibSystem)]
    public static extern IntPtr _dyld_get_image_name(uint index);

    [DllImport(LibSystem)]
    public static extern IntPtr _dyld_get_image_header(uint index);

    [DllImport(LibSystem)]
    public static extern IntPtr _dyld_get_image_vmaddr_slide(uint index);

    /// <summary>mach_task_self() is a macro over the exported global mach_task_self_.</summary>
    public static readonly uint TaskSelf = LoadTaskSelf();

    private static uint LoadTaskSelf()
    {
        IntPtr h = NativeLibrary.Load(LibSystem);
        IntPtr p = NativeLibrary.GetExport(h, "mach_task_self_");
        return (uint)Marshal.ReadInt32(p);
    }
}
