using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;

namespace Pitchside;

internal sealed class Segment
{
    public string Name;
    public ulong Start, End;
}

internal sealed class ImageInfo
{
    public string Path;
    public bool IsSystem;
    public ulong Lo, Hi;
    public List<Segment> Segments = new();
    public string FileName => System.IO.Path.GetFileName(Path ?? "");
}

/// <summary>
/// C++ class info for a vtable pointer, read from the Itanium C++ ABI layout clang uses on
/// macOS: [vtable-16] = offset-to-top (how far this sub-object sits from the start of the
/// complete object, negated), [vtable-8] = typeinfo pointer, typeinfo+8 = mangled class name.
/// (On Windows MSVC stores the equivalent in the "complete object locator" — that is what the
/// Windows tools read; the meaning of the offset is the same.)
/// </summary>
internal sealed class ClassInfo
{
    public bool Valid;
    public long OffsetToTop;          // <= 0
    public int SubObjectOffset => (int)(-OffsetToTop);
    public string TypeName;           // mangled name, may be null if RTTI is stripped
}

internal sealed unsafe class Memory
{
    public readonly List<ImageInfo> Images = new();
    public readonly List<(ulong start, ulong size)> Regions = new();
    public ulong TotalRegionBytes;

    // Address ranges where vtables can live (data segments of non-system images).
    private ulong[] _vtLo = Array.Empty<ulong>(), _vtHi = Array.Empty<ulong>();
    // Any image range (for typeinfo validation).
    private ulong[] _imLo = Array.Empty<ulong>(), _imHi = Array.Empty<ulong>();
    public ulong VtMin, VtMax;

    private readonly ConcurrentDictionary<ulong, ClassInfo> _classCache = new();

    [ThreadStatic] private static byte[] _small;

    public Memory(string engineImageFilter = null)
    {
        LoadImages();
        BuildVtRanges(engineImageFilter);
        LoadRegions();
    }

    // ---------------------------------------------------------------- images

    private void LoadImages()
    {
        uint n = Native._dyld_image_count();
        for (uint i = 0; i < n; i++)
        {
            IntPtr hdr = Native._dyld_get_image_header(i);
            if (hdr == IntPtr.Zero) continue;
            string path = Marshal.PtrToStringUTF8(Native._dyld_get_image_name(i)) ?? "";
            long slide = (long)Native._dyld_get_image_vmaddr_slide(i);
            var img = new ImageInfo
            {
                Path = path,
                IsSystem = path.StartsWith("/usr/lib/") || path.StartsWith("/System/") || path.StartsWith("/Library/Apple/"),
                Lo = ulong.MaxValue, Hi = 0,
            };
            byte* h = (byte*)hdr;
            uint magic = *(uint*)h;
            if (magic != 0xFEEDFACF) continue;              // 64-bit Mach-O only
            uint ncmds = *(uint*)(h + 16);
            byte* cmd = h + 32;
            for (uint c = 0; c < ncmds; c++)
            {
                uint type = *(uint*)cmd, size = *(uint*)(cmd + 4);
                if (type == 0x19)                             // LC_SEGMENT_64
                {
                    string seg = Encoding.ASCII.GetString(cmd + 8, 16).TrimEnd('\0');
                    ulong vmaddr = *(ulong*)(cmd + 24), vmsize = *(ulong*)(cmd + 32);
                    if (seg != "__PAGEZERO" && vmsize > 0)
                    {
                        ulong s = (ulong)((long)vmaddr + slide);
                        img.Segments.Add(new Segment { Name = seg, Start = s, End = s + vmsize });
                        if (seg != "__LINKEDIT")
                        {
                            img.Lo = Math.Min(img.Lo, s);
                            img.Hi = Math.Max(img.Hi, s + vmsize);
                        }
                    }
                }
                if (size == 0) break;
                cmd += size;
            }
            if (img.Hi > img.Lo) Images.Add(img);
        }
    }

    private void BuildVtRanges(string filter)
    {
        var vt = new List<(ulong, ulong)>();
        var all = new List<(ulong, ulong)>();
        foreach (var img in Images)
        {
            all.Add((img.Lo, img.Hi));
            if (img.IsSystem) continue;
            if (!string.IsNullOrEmpty(filter) && img.Path.IndexOf(filter, StringComparison.OrdinalIgnoreCase) < 0) continue;
            foreach (var s in img.Segments)
                if (s.Name.StartsWith("__DATA") || s.Name.StartsWith("__AUTH") || s.Name == "__CONST")
                    vt.Add((s.Start, s.End));
        }
        vt.Sort(); all.Sort();
        _vtLo = vt.Select(x => x.Item1).ToArray(); _vtHi = vt.Select(x => x.Item2).ToArray();
        _imLo = all.Select(x => x.Item1).ToArray(); _imHi = all.Select(x => x.Item2).ToArray();
        VtMin = _vtLo.Length > 0 ? _vtLo[0] : 0;
        VtMax = _vtHi.Length > 0 ? _vtHi.Max() : 0;
    }

    private static bool InRanges(ulong a, ulong[] lo, ulong[] hi)
    {
        int l = 0, r = lo.Length - 1;
        while (l <= r)
        {
            int m = (l + r) >> 1;
            if (a < lo[m]) r = m - 1;
            else if (a >= hi[m]) l = m + 1;
            else return true;
        }
        return false;
    }

    public bool InVtRange(ulong a) => a >= VtMin && a < VtMax && InRanges(a, _vtLo, _vtHi);
    public bool InAnyImage(ulong a) => InRanges(a, _imLo, _imHi);

    public ImageInfo ImageOf(ulong a) =>
        Images.FirstOrDefault(i => i.Segments.Any(s => a >= s.Start && a < s.End));

    // ---------------------------------------------------------------- regions

    private void LoadRegions()
    {
        int* info = stackalloc int[16];
        ulong addr = 0;
        for (int guard = 0; guard < 2_000_000; guard++)
        {
            ulong size = 0;
            uint count = 9, obj;
            int kr = Native.mach_vm_region(Native.TaskSelf, ref addr, ref size, Native.VM_REGION_BASIC_INFO_64, info, ref count, out obj);
            if (kr != Native.KERN_SUCCESS) break;
            if (obj != 0) Native.mach_port_deallocate(Native.TaskSelf, obj);
            int prot = info[0];
            bool rw = (prot & (Native.VM_PROT_READ | Native.VM_PROT_WRITE)) == (Native.VM_PROT_READ | Native.VM_PROT_WRITE);
            bool exec = (prot & Native.VM_PROT_EXECUTE) != 0;
            if (rw && !exec && size >= 0x1000 && !InAnyImage(addr) && !IsOwnBuffer(addr, size))
            {
                Regions.Add((addr, size));
                TotalRegionBytes += size;
            }
            ulong next = addr + size;
            if (next <= addr) break;
            addr = next;
        }
    }

    // ---------------------------------------------------------------- reads

    public bool Read(ulong addr, byte[] buf, int offset, int len)
    {
        if (len <= 0) return true;
        fixed (byte* p = &buf[offset])
        {
            int kr = Native.mach_vm_read_overwrite(Native.TaskSelf, addr, (ulong)len, (ulong)p, out ulong got);
            return kr == Native.KERN_SUCCESS && got == (ulong)len;
        }
    }

    private byte[] Small => _small ??= new byte[256];

    public ulong U64(ulong a) { var b = Small; return Read(a, b, 0, 8) ? BinaryPrimitives.ReadUInt64LittleEndian(b) : 0; }
    public long I64(ulong a) { var b = Small; return Read(a, b, 0, 8) ? BinaryPrimitives.ReadInt64LittleEndian(b) : 0; }
    public uint U32(ulong a) { var b = Small; return Read(a, b, 0, 4) ? BinaryPrimitives.ReadUInt32LittleEndian(b) : 0; }
    public ushort U16(ulong a) { var b = Small; return Read(a, b, 0, 2) ? BinaryPrimitives.ReadUInt16LittleEndian(b) : (ushort)0; }
    public byte U8(ulong a) { var b = Small; return Read(a, b, 0, 1) ? b[0] : (byte)0; }

    /// <summary>Pointer read; returns 0 for anything that can't be a user-space pointer.</summary>
    public ulong Ptr(ulong a)
    {
        ulong v = U64(a);
        return v >= 0x1000 && v < 0x0000_8000_0000_0000UL ? v : 0;
    }

    public byte[] ReadBytes(ulong a, int len)
    {
        var b = new byte[len];
        if (Read(a, b, 0, len)) return b;
        // Fall back page-by-page so a partially mapped window still returns what it can.
        for (int off = 0; off < len; off += 0x100)
            if (!Read(a + (ulong)off, b, off, Math.Min(0x100, len - off)))
                Array.Clear(b, off, Math.Min(0x100, len - off));
        return b;
    }

    public string CStr(ulong addr, int max = 160)
    {
        if (addr == 0) return null;
        var b = Small;
        int len = Math.Min(max, b.Length);
        if (!Read(addr, b, 0, len))
        {
            len = 32;
            if (!Read(addr, b, 0, len)) return null;
        }
        int n = Array.IndexOf(b, (byte)0, 0, len);
        if (n < 0) n = len;
        if (n == 0) return null;
        try
        {
            string s = new UTF8Encoding(false, true).GetString(b, 0, n).Trim();
            return s.Length == 0 ? null : s;
        }
        catch { return null; }   // not valid UTF-8 → not a string
    }

    /// <summary>
    /// FM string field. Nested: [field] → outer, [outer] → inner, text at inner+textOffset.
    /// Indirect: [field] → p, text at p+textOffset.
    /// </summary>
    public string FmString(ulong field, bool nested, int textOffset)
    {
        ulong p = Ptr(field);
        if (p == 0) return null;
        if (nested) { p = Ptr(p); if (p == 0) return null; }
        return CStr(p + (ulong)textOffset);
    }

    // ---------------------------------------------------------------- C++ class info

    public ClassInfo Class(ulong vtable)
    {
        if (_classCache.TryGetValue(vtable, out var ci)) return ci;
        ci = new ClassInfo();
        long ott = I64(vtable - 16);
        ulong ti = U64(vtable - 8);
        if (ott <= 0 && ott > -0x10000 && ti != 0 && InAnyImage(ti))
        {
            ci.Valid = true;
            ci.OffsetToTop = ott;
            ulong namePtr = U64(ti + 8);
            if (namePtr != 0 && InAnyImage(namePtr)) ci.TypeName = CStr(namePtr, 120);
        }
        _classCache[vtable] = ci;
        return ci;
    }

    // ---------------------------------------------------------------- parallel scanning

    public delegate void ChunkVisitor(ulong chunkBase, ReadOnlySpan<byte> data, int worker);

    public const int Workers = 4;
    public const int ChunkSize = 16 << 20;
    // Scan buffers live in native memory allocated BEFORE the region list is taken, and the
    // regions holding them are excluded — otherwise the scan would find copies of game
    // objects inside its own buffers and report them at bogus addresses.
    private static readonly IntPtr[] _bufs = AllocBuffers();
    private static IntPtr[] AllocBuffers()
    {
        var b = new IntPtr[Workers];
        for (int i = 0; i < Workers; i++) b[i] = (IntPtr)NativeMemory.Alloc((nuint)ChunkSize);
        return b;
    }

    private bool IsOwnBuffer(ulong regionStart, ulong regionSize)
    {
        if (regionSize > 64UL << 20) return false;
        foreach (var p in _bufs)
        {
            ulong a = (ulong)p;
            if (a >= regionStart && a < regionStart + regionSize) return true;
        }
        return false;
    }

    private bool ReadInto(ulong addr, IntPtr dst, int len)
    {
        int kr = Native.mach_vm_read_overwrite(Native.TaskSelf, addr, (ulong)len, (ulong)dst, out ulong got);
        return kr == Native.KERN_SUCCESS && got == (ulong)len;
    }

    /// <summary>
    /// Walk all writable heap regions in chunks across worker threads. Chunks overlap by
    /// 64 bytes so patterns straddling a boundary are still seen (callers dedupe).
    /// Returns the number of bytes that could not be read.
    /// </summary>
    public long ScanHeap(ChunkVisitor visit, Action<double> progress = null)
    {
        int workers = Workers, chunk = ChunkSize;
        var regions = Regions.ToList();
        long done = 0, unread = 0;
        var tasks = new Task[workers];
        long lastTick = Environment.TickCount64;
        for (int w = 0; w < workers; w++)
        {
            int worker = w;
            tasks[w] = Task.Run(() =>
            {
                IntPtr buf = _bufs[worker];
                for (int ri = worker; ri < regions.Count; ri += workers)
                {
                    var (start, size) = regions[ri];
                    ulong pos = 0;
                    while (pos < size)
                    {
                        int want = (int)Math.Min((ulong)chunk, size - pos);
                        ulong at = start + pos;
                        if (!ReadInto(at, buf, want))
                        {
                            // Retry at 1 MB granularity so one bad page doesn't lose 16 MB.
                            int fine = Math.Min(1 << 20, want);
                            if (fine == want || !ReadInto(at, buf, fine))
                            {
                                pos += (ulong)fine;
                                Interlocked.Add(ref unread, fine);
                                Interlocked.Add(ref done, fine);
                                continue;
                            }
                            want = fine;
                        }
                        try { visit(at, new ReadOnlySpan<byte>((void*)buf, want), worker); }
                        catch (Exception e) { Log.Warn($"chunk @{at:X}: {e.Message}"); }
                        int step = (ulong)want < size - pos ? Math.Max(want - 64, 64) : want;
                        pos += (ulong)step;
                        long d = Interlocked.Add(ref done, step);
                        long now = Environment.TickCount64;
                        if (progress != null && now - Interlocked.Read(ref lastTick) > 500)
                        {
                            Interlocked.Exchange(ref lastTick, now);
                            progress(TotalRegionBytes == 0 ? 0 : (double)d / TotalRegionBytes);
                        }
                    }
                }
            });
        }
        Task.WaitAll(tasks);
        return unread;
    }
}
