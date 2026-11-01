using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;

namespace Pitchside;

/// <summary>
/// shortlistprobe.txt — looks for where FM keeps your shortlist, so scans can bring it into Pitchside.
/// Started by creating shortlist.flag in the Pitchside folder with the names of a few players on your
/// FM shortlist, one per line. Read-only, like everything else in the plugin.
///
/// 1. finds every player object (address and unique id) and the named ones;
/// 2. looks for places that hold two or more of the named players, as pointers or as ids, close
///    together (a list), decodes every player in that list and names the object that owns it;
/// 3. a census of classes whose names suggest shortlists, scouting or transfer targets.
/// </summary>
internal static partial class Dumper
{
    private static readonly string[] ShortlistWords = { "SHORT", "SCOUT", "WATCH", "TARGET", "RECRUIT", "INTEREST", "FAVOUR" };

    private static string PersonName(Memory mem, Offsets cfg, ulong person)
    {
        var pe = cfg.Person;
        bool nested = cfg.Strings.Nested;
        int to = cfg.Strings.TextOffset;
        string common = mem.FmString(person + (ulong)pe.CommonName, nested, to);
        if (Plausible(common)) return common;
        string first = mem.FmString(person + (ulong)pe.FirstName, nested, to);
        string second = mem.FmString(person + (ulong)pe.SecondName, nested, to);
        string n = string.Join(" ", new[] { first, second }.Where(Plausible));
        return n.Length > 0 ? n : null;
    }

    public static void RunShortlistProbe(Request req)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var cfg = Offsets.Load();
        var mem = new Memory(cfg.EngineImage);
        var sb = new StringBuilder();
        void Line(string s = "") => sb.AppendLine(s);
        var wanted = (req.Club ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(s => s.ToLowerInvariant()).ToList();
        Line($"Pitchside shortlist probe — plugin {Plugin.Version} — {DateTime.Now:s}");
        Line($"Players named: {string.Join(", ", wanted)}");
        if (mem.VtMin == 0) { Line("Engine image not found."); Finish(sb, sw); return; }

        var playerSet = cfg.PlayerOffsets.ToHashSet();
        var playerTypes = cfg.PlayerTypes.Where(x => !string.IsNullOrEmpty(x)).ToHashSet();
        // address (object start or person sub-object) → uid; uid → person address
        var addrUid = new ConcurrentDictionary<ulong, uint>();
        var uidPerson = new ConcurrentDictionary<uint, ulong>();
        var census = new ConcurrentDictionary<string, (long count, ConcurrentBag<ulong> samples)>();

        Status.Write("scanning", 0, "Shortlist probe 1/3: finding players…", mode: "shortlist");
        mem.ScanHeap((at, data, w) =>
        {
            var q = MemoryMarshal.Cast<byte, ulong>(data.Slice(0, data.Length & ~7));
            var blk = _block ??= new byte[0x4000];
            for (int i = 0; i < q.Length; i++)
            {
                ulong v = q[i];
                if (v < mem.VtMin || v >= mem.VtMax || !mem.InVtRange(v)) continue;
                var ci = mem.Class(v);
                if (!ci.Valid) continue;
                ulong here = at + (ulong)i * 8;
                if (ci.SubObjectOffset == 0 && ci.TypeName != null)
                {
                    string up = ci.TypeName.ToUpperInvariant();
                    if (ShortlistWords.Any(up.Contains))
                    {
                        var e = census.GetOrAdd(ci.TypeName, _ => (0, new ConcurrentBag<ulong>()));
                        if (e.samples.Count < 4) e.samples.Add(here);
                        census[ci.TypeName] = (e.count + 1, e.samples);
                    }
                }
                int sub = ci.SubObjectOffset;
                if (!playerSet.Contains(sub) || (playerTypes.Count > 0 && (ci.TypeName == null || !playerTypes.Contains(ci.TypeName)))) continue;
                ulong objStart = here - (ulong)sub;
                if (!mem.Read(objStart, blk, 0, sub + cfg.ObjUid + 4)) continue;
                uint uid = BinaryPrimitives.ReadUInt32LittleEndian(blk.AsSpan(sub + cfg.ObjUid));
                if (uid == 0 || uid == uint.MaxValue) continue;
                addrUid.TryAdd(objStart, uid);
                addrUid.TryAdd(here, uid);
                uidPerson.TryAdd(uid, here);
            }
        }, p => Status.Write("scanning", 0.35 * p, "Shortlist probe 1/3: finding players…", mode: "shortlist"));
        Line($"{uidPerson.Count:N0} player objects.");

        // Named players
        var targetUids = new HashSet<uint>();
        var names = new ConcurrentDictionary<uint, string>();
        string NameOf(uint uid) => names.GetOrAdd(uid, u => uidPerson.TryGetValue(u, out var a) ? PersonName(mem, cfg, a) ?? "?" : "?");
        if (wanted.Count > 0)
        {
            Status.Write("scanning", 0.36, "Shortlist probe: matching names…", mode: "shortlist");
            foreach (var (uid, addr) in uidPerson)
            {
                string n = PersonName(mem, cfg, addr);
                if (n == null) continue;
                names[uid] = n;
                if (wanted.Contains(n.ToLowerInvariant())) targetUids.Add(uid);
            }
        }
        Line($"Named players found: {string.Join(", ", targetUids.Select(u => $"{NameOf(u)} (id {u}, @ {uidPerson[u]:X})"))}");
        Line();
        Line("== Classes that sound like shortlists / scouting / targets ==");
        foreach (var kv in census.OrderByDescending(kv => kv.Value.count).Take(60))
            Line($"  {kv.Value.count,8:N0}  {kv.Key}   e.g. {string.Join(" ", kv.Value.samples.Select(a => a.ToString("X")))}");

        if (targetUids.Count >= 2)
        {
            // Every place holding a named player: as a pointer (8-byte aligned) or as an id (4-byte aligned).
            var targetAddrs = addrUid.Where(kv => targetUids.Contains(kv.Value)).ToDictionary(kv => kv.Key, kv => kv.Value);
            // Any pointer into a named player's object (FM objects have several sub-objects, each its own address).
            var starts = addrUid.Where(kv => targetUids.Contains(kv.Value)).GroupBy(kv => kv.Value)
                .Select(g => (lo: g.Min(x => x.Key), uid: g.Key)).ToList();
            uint Inside(ulong v)
            {
                foreach (var (lo, uid) in starts) if (v >= lo && v < lo + 0x600) return uid;
                return 0;
            }
            // The plugin's own memory (copies of game data) sits below this; only the game's heap counts.
            const ulong GameHeap = 0x60_0000_0000UL;
            var hits = new ConcurrentBag<(ulong at, uint uid, bool ptr)>();
            Status.Write("scanning", 0.4, "Shortlist probe 2/3: looking for lists of your players…", mode: "shortlist");
            mem.ScanHeap((at, data, w) =>
            {
                var q = MemoryMarshal.Cast<byte, ulong>(data.Slice(0, data.Length & ~7));
                if (at < GameHeap) return;
                for (int i = 0; i < q.Length; i++)
                {
                    ulong v = q[i];
                    if (v < GameHeap || hits.Count >= 200_000) continue;
                    uint u = targetAddrs.TryGetValue(v, out var x) ? x : Inside(v);
                    if (u != 0) hits.Add((at + (ulong)i * 8, u, true));
                }
                var d = MemoryMarshal.Cast<byte, uint>(data.Slice(0, data.Length & ~3));
                for (int i = 0; i < d.Length; i++)
                    if (targetUids.Contains(d[i]) && hits.Count < 200_000) hits.Add((at + (ulong)i * 4, d[i], false));
            }, p => Status.Write("scanning", 0.4 + 0.3 * p, "Shortlist probe 2/3: looking for lists of your players…", mode: "shortlist"));
            Line();
            Line($"== Places holding 2+ of the named players within 0x400 bytes ({hits.Count:N0} raw hits) ==");
            var sorted = hits.OrderBy(h => h.at).ToList();
            var clusters = new List<(ulong start, ulong end, bool ptr, HashSet<uint> uids)>();
            foreach (bool ptr in new[] { true, false })
            {
                var hs = sorted.Where(h => h.ptr == ptr).ToList();
                int lo = 0;
                for (int hi = 0; hi < hs.Count; hi++)
                {
                    while (hs[hi].at - hs[lo].at > 0x400) lo++;
                    var set = hs.Skip(lo).Take(hi - lo + 1).Select(h => h.uid).ToHashSet();
                    if (set.Count < 2) continue;
                    if (clusters.Count > 0 && clusters[^1].ptr == ptr && hs[lo].at <= clusters[^1].end)
                    {
                        var c = clusters[^1]; c.uids.UnionWith(set); clusters[^1] = (c.start, hs[hi].at, ptr, c.uids);
                    }
                    else clusters.Add((hs[lo].at, hs[hi].at, ptr, set));
                }
            }
            var listStarts = new Dictionary<ulong, string>();
            int shown = 0;
            foreach (var c in clusters.OrderByDescending(c => c.uids.Count).ThenBy(c => c.end - c.start))
            {
                if (shown++ >= 25) break;
                var (owner, cls) = TacticProbe.Owner(mem, c.start, 0x2000);
                Line($"\n-- {(c.ptr ? "pointers" : "ids")}: {c.uids.Count} named players, {c.start:X}–{c.end:X}; owner {cls ?? "(none: plain buffer)"}{(owner != 0 ? $" @ {owner:X} (+0x{c.start - owner:X})" : "")}");
                // Decode the whole list around it: walk outwards over consecutive player entries.
                foreach (int stride in c.ptr ? new[] { 8, 16 } : new[] { 4, 8, 12, 16 })
                {
                    ulong a0 = c.start;
                    bool IsEntry(ulong a)
                    {
                        if (c.ptr) { ulong v = mem.U64(a); return addrUid.ContainsKey(v) || Inside(v) != 0; }
                        var b = mem.ReadBytes(a, 4);
                        return b != null && uidPerson.ContainsKey(BinaryPrimitives.ReadUInt32LittleEndian(b));
                    }
                    if (!IsEntry(a0)) continue;
                    while (a0 >= (ulong)stride && IsEntry(a0 - (ulong)stride)) a0 -= (ulong)stride;
                    var list = new List<string>();
                    for (ulong a = a0; IsEntry(a) && list.Count < 400; a += (ulong)stride)
                    {
                        ulong pv = c.ptr ? mem.U64(a) : 0;
                        uint u = c.ptr ? (addrUid.TryGetValue(pv, out var uu) ? uu : Inside(pv)) : BinaryPrimitives.ReadUInt32LittleEndian(mem.ReadBytes(a, 4));
                        list.Add(NameOf(u) + (targetUids.Contains(u) ? "*" : ""));
                    }
                    if (list.Count < 2) continue;
                    Line($"   stride {stride}: {list.Count} players from {a0:X}: {string.Join(", ", list.Take(60))}");
                    listStarts.TryAdd(a0, $"{list.Count} players, stride {stride}");
                }
                Line(TacticProbe.Hex("   memory", mem.ReadBytes(c.start - 0x40, (int)Math.Min(0x200, c.end - c.start + 0x80))));
                if (owner != 0 && cls != null) TacticProbe.DumpObject(mem, sb, owner, 0x200, depth: 0);
            }
            // Vectors: a (begin, end) pointer pair on the heap that spans an id cluster is the list itself.
            var idClusters = clusters.Where(c => c.uids.Count >= 2).OrderByDescending(c => c.uids.Count).Take(8).ToList();
            if (idClusters.Count > 0)
            {
                Status.Write("scanning", 0.72, "Shortlist probe: finding the lists' owners…", mode: "shortlist");
                var spans = new ConcurrentBag<(ulong at, ulong begin, ulong end, int ci)>();
                mem.ScanHeap((at, data, w) =>
                {
                    var q = MemoryMarshal.Cast<byte, ulong>(data.Slice(0, data.Length & ~7));
                    for (int i = 0; i + 1 < q.Length; i++)
                    {
                        ulong b = q[i], e = q[i + 1];
                        if (e <= b || e - b > 0x40000 || b < GameHeap) continue;
                        for (int k = 0; k < idClusters.Count; k++)
                            if (b <= idClusters[k].start && e > idClusters[k].end && spans.Count < 500)
                                spans.Add((at + (ulong)i * 8, b, e, k));
                    }
                }, p => Status.Write("scanning", 0.72 + 0.03 * p, "Shortlist probe: finding the lists' owners…", mode: "shortlist"));
                Line();
                Line("== Containers (begin, end) around the id lists ==");
                foreach (var g in spans.GroupBy(x => (x.begin, x.end)).OrderBy(g => g.Key.end - g.Key.begin).Take(12))
                {
                    var (b, e) = g.Key;
                    int n = (int)((e - b) / 4);
                    var bytes = mem.ReadBytes(b, (int)Math.Min(e - b, 0x4000));
                    if (bytes == null) continue;
                    var parts = new List<string>();
                    int known = 0;
                    for (int o = 0; o + 4 <= bytes.Length; o += 4)
                    {
                        uint u = BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(o));
                        if (uidPerson.ContainsKey(u)) { known++; parts.Add(NameOf(u) + (targetUids.Contains(u) ? "*" : "")); }
                        else parts.Add($"#{u}");
                    }
                    // Or 8-byte pointers to players.
                    var pparts = new List<string>();
                    int pknown = 0;
                    for (int o = 0; o + 8 <= bytes.Length; o += 8)
                    {
                        ulong v = BinaryPrimitives.ReadUInt64LittleEndian(bytes.AsSpan(o));
                        uint u = addrUid.TryGetValue(v, out var uu) ? uu : Inside(v);
                        if (u != 0) { pknown++; pparts.Add(NameOf(u) + (targetUids.Contains(u) ? "*" : "")); } else pparts.Add($"@{v:X}");
                    }
                    if (pknown > known) { parts = pparts; known = pknown; n = pparts.Count; }
                    Line($"\n-- {n} entries at {b:X}–{e:X}, {known} are players");
                    foreach (var (at, _, _, _) in g.Take(4))
                    {
                        var (owner, cls) = TacticProbe.Owner(mem, at, 0x4000);
                        Line($"   held by {cls ?? "(no class)"}{(owner != 0 ? $" @ {owner:X}, field +0x{at - owner:X}" : $" @ {at:X}")}; capacity field {mem.U64(at + 16):X}");
                    }
                    Line("   " + string.Join(", ", parts.Take(300)));
                }
                if (spans.IsEmpty) Line("  (none found)");
            }
            // Who points at the start of each list (the vector's owner)?
            if (listStarts.Count > 0)
            {
                Status.Write("scanning", 0.75, "Shortlist probe 3/3: finding who owns each list…", mode: "shortlist");
                var refs = new ConcurrentBag<(ulong at, ulong target)>();
                mem.ScanHeap((at, data, w) =>
                {
                    var q = MemoryMarshal.Cast<byte, ulong>(data.Slice(0, data.Length & ~7));
                    for (int i = 0; i < q.Length; i++)
                        if (listStarts.ContainsKey(q[i]) && refs.Count < 2000) refs.Add((at + (ulong)i * 8, q[i]));
                }, p => Status.Write("scanning", 0.75 + 0.2 * p, "Shortlist probe 3/3: finding who owns each list…", mode: "shortlist"));
                Line();
                Line("== Objects pointing at the start of a list ==");
                foreach (var (at, target) in refs.Distinct().Take(40))
                {
                    var (owner, cls) = TacticProbe.Owner(mem, at, 0x2000);
                    ulong end = mem.U64(at + 8);
                    Line($"  {cls ?? "(no class)"} @ {owner:X} field +0x{(owner == 0 ? 0 : at - owner):X} → list {target:X} ({listStarts[target]}); next field {end:X} (+{(long)(end - target)} bytes)");
                }
            }
        }
        else Line("\nNeed at least two of the named players found to look for the list. Check the spelling (as FM shows the name).");
        Finish(sb, sw);
    }

    private static void Finish(StringBuilder sb, System.Diagnostics.Stopwatch sw)
    {
        sb.AppendLine();
        sb.AppendLine($"Done in {sw.ElapsedMilliseconds:N0} ms.");
        Paths.WriteAtomic(System.IO.Path.Combine(Paths.Dir, "shortlistprobe.txt"), sb.ToString());
        Status.Write("done", 1, "Shortlist probe written (shortlistprobe.txt in the Pitchside folder).", mode: "shortlist");
        Log.Info($"Shortlist probe done in {sw.ElapsedMilliseconds} ms");
    }
}
