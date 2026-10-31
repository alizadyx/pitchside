using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;

namespace Pitchside;

/// <summary>
/// tacticprobe.txt — looks for where FM keeps your tactic, so it can be read later.
/// Started by creating tactics.flag in the Pitchside folder; the file's text is the tactic's
/// name as saved in FM (default "PSPROBE"). Read-only, like everything else in the plugin.
///
/// Three leads:
///  1. the tactic's name text, and the objects that point to it;
///  2. clusters of team-instruction codes (FM's four-letter option ids);
///  3. clusters of the larger in/out-of-possession role flags;
/// plus a census of every class whose name mentions tactics, formations, roles or instructions.
/// </summary>
internal static class TacticProbe
{
    private static readonly string[] ClassWords =
        { "TACT", "FORMAT", "INSTRUCT", "ROLE", "PRESET", "STYLE", "SELECTION", "SHAPE", "MENTAL" };
    private const int MaxMarkerHits = 2_000_000;
    private const int Window = 0x400;
    private const ulong RoleFloor = 1UL << 33;

    public static void Run(Request req)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var cfg = Offsets.Load();
        var mem = new Memory(cfg.EngineImage);
        var sb = new StringBuilder();
        void Line(string s = "") => sb.AppendLine(s);
        string name = string.IsNullOrWhiteSpace(req.Club) ? "PSPROBE" : req.Club.Trim();
        byte[] needle = Encoding.UTF8.GetBytes(name);

        Line($"Pitchside tactic probe — plugin {Plugin.Version} — {DateTime.Now:s}");
        Line($"Looking for tactic name \"{name}\". Heap: {mem.TotalRegionBytes / (1 << 20):N0} MB in {mem.Regions.Count:N0} regions.");

        var census = new ConcurrentDictionary<string, (long count, ulong sample)>();
        var textHits = new ConcurrentBag<ulong>();
        var insHits = new ConcurrentBag<(ulong at, ulong v)>();
        var roleHits = new ConcurrentBag<(ulong at, ulong v)>();
        long insCount = 0, roleCount = 0;

        Status.Write("scanning", 0, "Tactic probe 1/2: searching memory…", mode: "tactics");
        mem.ScanHeap((at, data, w) =>
        {
            // name text (must end the string)
            int from = 0;
            while (from < data.Length)
            {
                int i = data.Slice(from).IndexOf(needle);
                if (i < 0) break;
                int pos = from + i;
                from = pos + 1;
                int end = pos + needle.Length;
                if (end < data.Length && data[end] == 0 && textHits.Count < 5000) textHits.Add(at + (ulong)pos);
            }
            // instruction codes (4-byte aligned)
            var d = MemoryMarshal.Cast<byte, uint>(data.Slice(0, data.Length & ~3));
            for (int i = 0; i < d.Length; i++)
            {
                if (TacticCodes.Instructions.ContainsKey(d[i]) && Interlocked.Increment(ref insCount) < MaxMarkerHits)
                    insHits.Add((at + (ulong)i * 4, d[i]));
            }
            // role flags and class census (8-byte aligned)
            var q = MemoryMarshal.Cast<byte, ulong>(data.Slice(0, data.Length & ~7));
            for (int i = 0; i < q.Length; i++)
            {
                ulong v = q[i];
                // Only flags from bit 33 up: lower single bits (16 MB, 1 GB…) are everyday sizes and masks.
                if (v >= RoleFloor && (TacticCodes.InPossession.ContainsKey(v) || TacticCodes.OutOfPossession.ContainsKey(v))
                    && Interlocked.Increment(ref roleCount) < MaxMarkerHits)
                    roleHits.Add((at + (ulong)i * 8, v));
                if (v < mem.VtMin || v >= mem.VtMax || !mem.InVtRange(v)) continue;
                var ci = mem.Class(v);
                if (!ci.Valid || ci.TypeName == null) continue;
                string up = ci.TypeName.ToUpperInvariant();
                if (!ClassWords.Any(up.Contains)) continue;
                ulong here = at + (ulong)i * 8;
                census.AddOrUpdate(ci.TypeName, (1, here), (_, o) => (o.count + 1, o.sample));
            }
        }, p => Status.Write("scanning", 0.6 * p, "Tactic probe 1/2: searching memory…", mode: "tactics"));

        // ---------------------------------------------------------------- census
        Line();
        Line("== Classes mentioning tactics / formations / roles / instructions ==");
        foreach (var kv in census.OrderByDescending(kv => kv.Value.count).Take(80))
            Line($"  {kv.Value.count,8:N0}  {kv.Key}   e.g. @ {kv.Value.sample:X}");
        if (census.IsEmpty) Line("  (none)");

        // ---------------------------------------------------------------- name text → owners
        Line();
        Line($"== Tactic name \"{name}\": {textHits.Count} text hits ==");
        var hits = textHits.Distinct().Take(40).ToList();
        var candidates = new Dictionary<ulong, ulong>();      // possible string-object address → text address
        foreach (var h in hits)
            foreach (int delta in new[] { 0, 4, 8, 16, 24 })
                candidates.TryAdd(h - (ulong)delta, h);
        var refs = new ConcurrentBag<(ulong at, ulong target)>();
        if (candidates.Count > 0)
        {
            Status.Write("scanning", 0.62, "Tactic probe 2/2: following pointers to the name…", mode: "tactics");
            mem.ScanHeap((at, data, w) =>
            {
                var q = MemoryMarshal.Cast<byte, ulong>(data.Slice(0, data.Length & ~7));
                for (int i = 0; i < q.Length; i++)
                    if (candidates.ContainsKey(q[i]) && refs.Count < 400) refs.Add((at + (ulong)i * 8, q[i]));
            }, p => Status.Write("scanning", 0.62 + 0.3 * p, "Tactic probe 2/2: following pointers to the name…", mode: "tactics"));
        }
        foreach (var h in hits.Take(10))
        {
            Line($"  text @ {h:X}");
            Line(Hex("    text-32", mem.ReadBytes(h - 32, 32 + Math.Min(needle.Length + 16, 96))));
        }
        Line();
        Line($"== Objects pointing at the name: {refs.Count} ==");
        int shown = 0;
        foreach (var (at, target) in refs.Distinct().OrderBy(r => r.at))
        {
            if (shown++ >= 12) break;
            var (owner, cls) = Owner(mem, at, 0x1000);
            Line($"\n-- pointer @ {at:X} → {target:X} (text @ {candidates[target]:X}); owner {cls ?? "?"} @ {owner:X} (field +0x{at - owner:X})");
            if (owner != 0) DumpObject(mem, sb, owner, 0x600, depth: 1);
        }

        // ---------------------------------------------------------------- clusters
        ClusterReport(mem, sb, "Team-instruction code clusters", insHits.ToList(), 4,
            v => TacticCodes.Instructions.TryGetValue((uint)v, out var n) ? n : "?");
        ClusterReport(mem, sb, "Role flag clusters", roleHits.ToList(), 4,
            v => string.Join("|", new[] {
                TacticCodes.InPossession.TryGetValue(v, out var a) ? "IP:" + a : null,
                TacticCodes.OutOfPossession.TryGetValue(v, out var b) ? "OOP:" + b : null }.Where(x => x != null)));

        Line();
        Line($"Done in {sw.ElapsedMilliseconds:N0} ms. Instruction-code hits {insHits.Count:N0}, role-flag hits {roleHits.Count:N0}.");
        Paths.WriteAtomic(System.IO.Path.Combine(Paths.Dir, "tacticprobe.txt"), sb.ToString());
        Status.Write("done", 1, "Tactic probe written (tacticprobe.txt in the Pitchside folder).", mode: "tactics");
        Log.Info($"Tactic probe done in {sw.ElapsedMilliseconds} ms");
    }

    /// <summary>Windows of memory where several different known codes sit close together.</summary>
    private static void ClusterReport(Memory mem, StringBuilder sb, string title, List<(ulong at, ulong v)> hits, int minDistinct,
                                      Func<ulong, string> decode)
    {
        sb.AppendLine();
        sb.AppendLine($"== {title} (≥{minDistinct} different codes within 0x{Window:X} bytes) — {hits.Count:N0} raw hits ==");
        hits.Sort((a, b) => a.at.CompareTo(b.at));
        var clusters = new List<(ulong start, ulong end, int distinct, List<(ulong at, ulong v)> items)>();
        int lo = 0;
        for (int hi = 0; hi < hits.Count; hi++)
        {
            while (hits[hi].at - hits[lo].at > Window) lo++;
            int distinct = hits.Skip(lo).Take(hi - lo + 1).Select(h => h.v).Distinct().Count();
            if (distinct < minDistinct) continue;
            var items = hits.Skip(lo).Take(hi - lo + 1).ToList();
            if (clusters.Count > 0 && items[0].at <= clusters[^1].end)
            {
                var c = clusters[^1];
                var merged = c.items.Concat(items).Distinct().OrderBy(x => x.at).ToList();
                clusters[^1] = (c.start, items[^1].at, merged.Select(m => m.v).Distinct().Count(), merged);
            }
            else clusters.Add((items[0].at, items[^1].at, distinct, items));
        }
        sb.AppendLine($"  {clusters.Count:N0} clusters");
        foreach (var c in clusters.OrderByDescending(c => c.distinct).Take(15))
        {
            var (owner, cls) = Owner(mem, c.start, 0x1000);
            sb.AppendLine($"\n-- {c.distinct} codes, {c.start:X}–{c.end:X}; owner {cls ?? "?"} @ {owner:X} (+0x{(owner == 0 ? 0 : c.start - owner):X})");
            foreach (var (at, v) in c.items.Take(40))
                sb.AppendLine($"   +0x{at - c.start:X3} @ {at:X}  {decode(v)}");
            sb.AppendLine(Hex("   region", mem.ReadBytes(c.start - 0x40, (int)Math.Min(0x300, c.end - c.start + 0x80))));
        }
    }

    /// <summary>The object containing <paramref name="addr"/>: nearest vtable at or before it.</summary>
    private static (ulong owner, string cls) Owner(Memory mem, ulong addr, int maxBack)
    {
        for (ulong a = addr & ~7UL; a + (ulong)maxBack > addr && a > 0x1000; a -= 8)
        {
            ulong vt = mem.U64(a);
            if (!mem.InVtRange(vt)) continue;
            var ci = mem.Class(vt);
            if (ci.Valid) return (a - (ulong)ci.SubObjectOffset, ci.TypeName);
        }
        return (0, null);
    }

    private static void DumpObject(Memory mem, StringBuilder sb, ulong obj, int len, int depth)
    {
        sb.AppendLine(Hex("   obj", mem.ReadBytes(obj, len)));
        for (int off = 0; off < len; off += 8)
        {
            ulong q = mem.U64(obj + (ulong)off);
            string what = Describe(mem, q);
            if (what != null) sb.AppendLine($"   +0x{off:X3} → {what}");
            if (depth > 0 && what != null && what.StartsWith("object"))
            {
                var (o2, _) = Owner(mem, q, 8);
                if (o2 != 0)
                    for (int o = 0; o < 0x100; o += 8)
                    {
                        string w2 = Describe(mem, mem.U64(o2 + (ulong)o));
                        if (w2 != null) sb.AppendLine($"        +0x{o:X3} → {w2}");
                    }
            }
        }
    }

    /// <summary>What a pointer-sized value points at: an object (class name), a string, or a known code.</summary>
    private static string Describe(Memory mem, ulong v)
    {
        if (TacticCodes.InPossession.TryGetValue(v, out var ip)) return "role IP:" + ip;
        if (TacticCodes.OutOfPossession.TryGetValue(v, out var oop)) return "role OOP:" + oop;
        if ((v >> 32) == 0 && TacticCodes.Instructions.TryGetValue((uint)v, out var ins)) return "instruction " + ins;
        if (v < 0x1000 || v >= 0x0000_8000_0000_0000UL || mem.InAnyImage(v)) return null;
        ulong vt = mem.U64(v);
        if (mem.InVtRange(vt))
        {
            var ci = mem.Class(vt);
            if (ci.Valid) return $"object {ci.TypeName} @ {v:X}";
        }
        foreach (var (nested, to) in new[] { (false, 4), (true, 4), (false, 0) })
        {
            string s = mem.FmString(v, nested, to);
            if (s != null && s.Length >= 3 && s.Count(char.IsLetter) >= 3 && s.All(c => !char.IsControl(c)))
                return $"string \"{s}\"";
        }
        string c = mem.CStr(v, 80);
        if (c != null && c.Length >= 4 && c.Count(char.IsLetter) >= 3 && c.All(ch => !char.IsControl(ch))) return $"text \"{c}\"";
        return null;
    }

    private static string Hex(string label, byte[] b)
    {
        if (b == null) return $"{label}: (unreadable)";
        var sb = new StringBuilder();
        for (int i = 0; i < b.Length; i += 16)
        {
            sb.Append($"{label}+{i:X3} ");
            for (int j = 0; j < 16 && i + j < b.Length; j++) sb.Append(b[i + j].ToString("X2")).Append(' ');
            sb.Append(' ');
            for (int j = 0; j < 16 && i + j < b.Length; j++) { byte c = b[i + j]; sb.Append(c is >= 32 and < 127 ? (char)c : '.'); }
            sb.AppendLine();
        }
        return sb.ToString().TrimEnd();
    }
}
