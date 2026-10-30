using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace Pitchside;

/// <summary>
/// Calibration: finds where FM keeps a person's fields by starting from things you can see
/// in game (a name, some attribute values, a birth date) and working backwards through memory:
///   1. find the name text  →  2. find pointers to it  →  3. find pointers to those
///   4. walk back to the C++ object that owns the name field (its vtable tells us the class)
///   5. inside that object, find the byte pattern matching your attribute values
/// The result is a report (for a human to check) and an offsets.suggested.json.
/// </summary>
internal static class Discovery
{
    private sealed class Needle
    {
        public int Target;
        public string Text;
        public string Role;          // full | first | last | token
        public byte[] Bytes;
        public ConcurrentBag<ulong> Hits = new();
        public int HitCount;
    }

    private sealed class FieldHit
    {
        public int Needle;
        public ulong Field;          // address of the pointer field inside the person object
        public bool Nested;
        public int TextOffset;
    }

    private sealed class Candidate
    {
        public int Target;
        public ulong Person;         // address of the vtable pointer of the person sub-object
        public ulong Vtable;
        public ClassInfo Class;
        public List<(int needle, int off, bool nested, int textOff)> Fields = new();
        public int Score;
    }

    private const int MaxHitsPerNeedle = 20000;
    private const int BackScan = 0x400;

    public static void Run(Request req)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var cfg = Offsets.Load();
        var sb = new StringBuilder();
        var report = new Dictionary<string, object>();
        void Line(string s = "") => sb.AppendLine(s);

        Status.Write("scanning", 0, "Discovery: mapping memory…", mode: "discover");
        var mem = new Memory(cfg.EngineImage);

        Line($"Pitchside discovery report — plugin {Plugin.Version} — {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        Line($"Heap regions: {mem.Regions.Count:N0} · {mem.TotalRegionBytes / (1 << 20):N0} MB");
        Line();
        Line("== Loaded non-system images ==");
        foreach (var img in mem.Images.Where(i => !i.IsSystem))
            Line($"  {img.Lo:X12}-{img.Hi:X12}  {(img.Hi - img.Lo) / 1024,8:N0} KB  {img.Path}");
        Line();
        report["images"] = mem.Images.Where(i => !i.IsSystem)
            .Select(i => new { path = i.Path, lo = $"0x{i.Lo:X}", hi = $"0x{i.Hi:X}",
                               segments = i.Segments.Select(s => $"{s.Name} 0x{s.Start:X}-0x{s.End:X}") }).ToList();

        // ---------------------------------------------------------------- needles
        var needles = new List<Needle>();
        for (int t = 0; t < req.Targets.Count; t++)
        {
            string name = (req.Targets[t].Name ?? "").Trim();
            if (name.Length < 2) continue;
            var tokens = name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            void Add(string text, string role)
            {
                if (text.Length < 2 || needles.Any(n => n.Target == t && n.Text == text)) return;
                needles.Add(new Needle { Target = t, Text = text, Role = role, Bytes = Encoding.UTF8.GetBytes(text) });
            }
            Add(name, "full");
            if (tokens.Length > 1)
            {
                Add(tokens[0], "first");
                Add(string.Join(" ", tokens.Skip(1)), "last");
                Add(tokens[^1], "token");
            }
        }
        if (needles.Count == 0) { Fail("Discovery needs at least one target name."); return; }

        // ---------------------------------------------------------------- pass 1: text
        Status.Write("scanning", 0.02, "Discovery 1/3: finding names in memory…", mode: "discover");
        mem.ScanHeap((at, data, w) =>
        {
            foreach (var n in needles)
            {
                if (n.HitCount >= MaxHitsPerNeedle) continue;
                var nb = n.Bytes;
                int from = 0;
                while (from < data.Length)
                {
                    int i = data.Slice(from).IndexOf(nb);
                    if (i < 0) break;
                    int pos = from + i;
                    from = pos + 1;
                    int end = pos + nb.Length;
                    if (end >= data.Length || data[end] != 0) continue;              // must end the string
                    if (pos > 0 && data[pos - 1] is (byte)' ' or (byte)'-' or (byte)'\'' ) continue; // tail of a longer name
                    if (Interlocked.Increment(ref n.HitCount) > MaxHitsPerNeedle) break;
                    n.Hits.Add(at + (ulong)pos);
                }
            }
        }, p => Status.Write("scanning", 0.02 + 0.3 * p, "Discovery 1/3: finding names in memory…", mode: "discover"));

        Line("== Name text hits ==");
        foreach (var n in needles)
            Line($"  [{req.Targets[n.Target].Name}] \"{n.Text}\" ({n.Role}): {n.Hits.Distinct().Count():N0} hits");
        Line();

        // ---------------------------------------------------------------- pass 2: pointers to text
        // FM strings: pointer → (header + text). Try several header sizes.
        int[] deltas = { 4, 0, 8, 16 };
        var textPtr = new Dictionary<ulong, (int needle, int delta)>();
        for (int ni = 0; ni < needles.Count; ni++)
            foreach (var h in needles[ni].Hits.Distinct())
                foreach (int d in deltas)
                    textPtr.TryAdd(h - (ulong)d, (ni, d));
        Status.Write("scanning", 0.33, "Discovery 2/3: following pointers…", mode: "discover");
        var lvl1 = ScanPointers(mem, textPtr.Keys.ToHashSet(),
            p => Status.Write("scanning", 0.33 + 0.3 * p, "Discovery 2/3: following pointers…", mode: "discover"));

        // ---------------------------------------------------------------- pass 3: pointers to pointers
        var lvl1Set = lvl1.Select(x => x.loc).ToHashSet();
        Status.Write("scanning", 0.64, "Discovery 3/3: following pointers…", mode: "discover");
        var lvl2 = ScanPointers(mem, lvl1Set,
            p => Status.Write("scanning", 0.64 + 0.3 * p, "Discovery 3/3: following pointers…", mode: "discover"));
        Line($"Pointer chains: {lvl1.Count:N0} direct (text←ptr), {lvl2.Count:N0} nested (text←ptr←ptr)");
        Line();

        var fields = new List<FieldHit>();
        var lvl1ByLoc = new Dictionary<ulong, ulong>();
        foreach (var (loc, val) in lvl1)
        {
            lvl1ByLoc.TryAdd(loc, val);
            var (ni, d) = textPtr[val];
            fields.Add(new FieldHit { Needle = ni, Field = loc, Nested = false, TextOffset = d });
        }
        foreach (var (loc, val) in lvl2)
        {
            if (!lvl1ByLoc.TryGetValue(val, out var inner)) continue;
            var (ni, d) = textPtr[inner];
            fields.Add(new FieldHit { Needle = ni, Field = loc, Nested = true, TextOffset = d });
        }

        // ---------------------------------------------------------------- owning objects
        Status.Write("scanning", 0.95, "Discovery: identifying objects…", mode: "discover");
        var cands = new Dictionary<(int target, ulong person), Candidate>();
        var back = new byte[BackScan];
        foreach (var f in fields.Take(200_000))
        {
            int t = needles[f.Needle].Target;
            ulong lo = f.Field - BackScan;
            if (!mem.Read(lo, back, 0, BackScan)) continue;
            int found = 0;
            for (int i = BackScan - 8; i >= 0 && found < 3; i -= 8)
            {
                ulong v = BitConverter.ToUInt64(back, i);
                if (!mem.InVtRange(v)) continue;
                var ci = mem.Class(v);
                if (!ci.Valid) continue;
                found++;
                ulong person = lo + (ulong)i;
                if (!cands.TryGetValue((t, person), out var c))
                    cands[(t, person)] = c = new Candidate { Target = t, Person = person, Vtable = v, Class = ci };
                int off = (int)(f.Field - person);
                if (!c.Fields.Any(x => x.needle == f.Needle && x.off == off))
                    c.Fields.Add((f.Needle, off, f.Nested, f.TextOffset));
            }
        }
        foreach (var c in cands.Values)
        {
            var distinct = c.Fields.Select(x => needles[x.needle].Role).Distinct().ToList();
            bool adjacent = c.Fields.Any(f => needles[f.needle].Role == "first" &&
                                c.Fields.Any(l => needles[l.needle].Role is "last" or "token" && l.off == f.off + 8));
            c.Score = distinct.Count * 10
                    + (distinct.Contains("first") && distinct.Contains("last") ? 25 : 0)
                    + (adjacent ? 40 : 0)                                          // real person: first, then surname
                    - (c.Fields.Count > 6 ? 60 : 0)                                // string caches repeat names
                    - c.Fields.Min(x => x.off) / 64;                               // nearer = likelier
        }

        // ---------------------------------------------------------------- per-target analysis
        var suggestion = cfg.Clone();
        var targetsOut = new List<object>();
        bool suggestedPlayer = false, suggestedStaff = false, suggestedPerson = false;
        var playerOffs = new HashSet<int>();
        var staffOffs = new HashSet<int>();
        var playerTypes = new HashSet<string>();
        var staffTypes = new HashSet<string>();

        for (int t = 0; t < req.Targets.Count; t++)
        {
            var tg = req.Targets[t];
            bool isStaff = string.Equals(tg.Kind, "staff", StringComparison.OrdinalIgnoreCase);
            Line($"################ TARGET {t + 1}: {tg.Name} ({(isStaff ? "staff" : "player")}) ################");
            var top = cands.Values.Where(c => c.Target == t).OrderByDescending(c => c.Score).Take(6).ToList();
            if (top.Count == 0) { Line("  No owning object found. Check the spelling (exactly as FM shows it)."); Line(); continue; }

            var candOut = new List<object>();
            int rank = 0;
            foreach (var c in top)
            {
                rank++;
                int sub = c.Class.SubObjectOffset;
                ulong objStart = c.Person - (ulong)sub;
                int window = Math.Clamp(sub + 0x400, 0x800, 0x2000);
                byte[] obj = mem.ReadBytes(objStart, window);
                var img = mem.ImageOf(c.Vtable);

                Line($"-- candidate #{rank}  score {c.Score}");
                Line($"   person sub-object @ {c.Person:X}  vtable {c.Vtable:X} ({img?.FileName}+0x{c.Vtable - (img?.Lo ?? 0):X})");
                Line($"   class '{c.Class.TypeName ?? "?"}'  offset-to-top {c.Class.OffsetToTop} → complete object @ {objStart:X} (person at +0x{sub:X})");
                foreach (var fx in c.Fields.OrderBy(x => x.off))
                    Line($"   name field +0x{fx.off:X}: \"{needles[fx.needle].Text}\" ({needles[fx.needle].Role}, {(fx.nested ? "nested" : "indirect")}, text+{fx.textOff})");
                Line($"   uid u32 @+0x{cfg.ObjUid:X}: {mem.U32(c.Person + (ulong)cfg.ObjUid)}");

                // Sub-objects (other vtables inside the complete object).
                var subs = new List<string>();
                for (int i = 0; i + 8 <= obj.Length; i += 8)
                {
                    ulong v = BitConverter.ToUInt64(obj, i);
                    if (!mem.InVtRange(v)) continue;
                    var ci = mem.Class(v);
                    if (ci.Valid) subs.Add($"+0x{i:X} '{ci.TypeName ?? "?"}' ott {ci.OffsetToTop}");
                }
                Line($"   vtables inside object: {string.Join(" | ", subs)}");

                // Attributes.
                var attrHits = new List<object>();
                int bestAttrRel = -1, bestScaleMode = 0;
                var map = isStaff ? cfg.Staff.AttributeMap
                                  : cfg.Player.AttributeMap.Concat(cfg.Player.HiddenMap).ToDictionary(k => k.Key, k => k.Value);
                var given = tg.Attributes.Where(kv => map.ContainsKey(kv.Key) && kv.Value is >= 1 and <= 20).ToList();
                var unknownKeys = tg.Attributes.Keys.Where(k => !map.ContainsKey(k)).ToList();
                if (unknownKeys.Count > 0) Line($"   (ignored unknown attribute names: {string.Join(", ", unknownKeys)})");
                if (given.Count >= 3)
                {
                    int maxRel = given.Max(g => map[g.Key]);
                    var partial = new List<(int x, int hits, int mode)>();
                    foreach (int mode in new[] { 5, 1 })
                        for (int x = 0; x + maxRel < obj.Length; x++)
                        {
                            int ok = 0;
                            foreach (var g in given)
                            {
                                int b = obj[x + map[g.Key]];
                                int v = mode == 5 ? (int)Math.Floor(b / 5.0 + 0.5) : b;
                                if (b <= 100 && v == g.Value) ok++;
                            }
                            if (ok >= Math.Max(3, (int)(given.Count * 0.7))) partial.Add((x, ok, mode));
                        }
                    foreach (var p in partial.OrderByDescending(p => p.hits).Take(6))
                    {
                        Line($"   attribute block candidate: object+0x{p.x:X} (person{(p.x - sub >= 0 ? "+" : "-")}0x{Math.Abs(p.x - sub):X}) " +
                             $"matches {p.hits}/{given.Count} (stored ×{p.mode})");
                        attrHits.Add(new { objOffset = $"0x{p.x:X}", matched = p.hits, of = given.Count, scale = p.mode });
                    }
                    var best = partial.OrderByDescending(p => p.hits).FirstOrDefault();
                    if (best.hits == given.Count) { bestAttrRel = best.x; bestScaleMode = best.mode; }
                    if (partial.Count == 0) Line($"   no attribute pattern match in the first 0x{obj.Length:X} bytes of this object");
                }
                else Line("   (fewer than 3 known attributes given — attribute search skipped)");

                // Birth date / height.
                var dobHits = new List<string>();
                var dobRel = new List<int>();
                if (DateTime.TryParse(tg.BirthDate, System.Globalization.CultureInfo.InvariantCulture,
                                      System.Globalization.DateTimeStyles.None, out var dob))
                {
                    uint enc = FmDate.Encode(dob);
                    for (int i = 0; i + 4 <= obj.Length; i += 2)
                        if (BitConverter.ToUInt32(obj, i) == enc)
                        {
                            dobRel.Add(i - sub);
                            dobHits.Add($"object+0x{i:X} (person{(i - sub >= 0 ? "+" : "-")}0x{Math.Abs(i - sub):X})");
                        }
                    Line($"   birth date {tg.BirthDate} found at: {(dobHits.Count > 0 ? string.Join(", ", dobHits) : "nowhere in object")}");
                }
                Line($"   current DOB guess (person+0x{cfg.Person.Dob:X}): {FmDate.Iso(mem.U32(c.Person + (ulong)cfg.Person.Dob)) ?? "—"}");
                var heightHits = new List<string>();
                var heightRel = new List<int>();
                if (tg.HeightCm is >= 140 and <= 220)
                {
                    for (int i = 0; i + 2 <= obj.Length; i += 2)
                        if (BitConverter.ToUInt16(obj, i) == tg.HeightCm) { heightRel.Add(i); heightHits.Add($"object+0x{i:X}"); }
                    Line($"   height {tg.HeightCm} (u16) at: {(heightHits.Count > 0 ? string.Join(", ", heightHits.Take(12)) : "nowhere")}");
                }

                // CA/PA candidates near the attribute block.
                var caPa = new List<string>();
                if (bestAttrRel >= 0)
                {
                    int lo = Math.Max(0, bestAttrRel - 0x200), hi = Math.Min(obj.Length - 4, bestAttrRel + 0x300);
                    for (int i = lo; i <= hi; i += 2)
                    {
                        int a = BitConverter.ToUInt16(obj, i), b = BitConverter.ToUInt16(obj, i + 2);
                        if (a is >= 20 and <= 200 && b is >= 40 and <= 200 && b >= a && b - a <= 150)
                            caPa.Add($"+0x{i:X}:{a}/{b}");
                    }
                    int fmCaRel = cfg.Player.Ca - cfg.Player.Attributes;
                    if (!isStaff)
                        Line($"   CA/PA at FM26 distance from attributes (object+0x{bestAttrRel + fmCaRel:X}): " +
                             $"{BitConverter.ToUInt16(obj, Math.Min(obj.Length - 4, bestAttrRel + fmCaRel))}/" +
                             $"{BitConverter.ToUInt16(obj, Math.Min(obj.Length - 2, bestAttrRel + fmCaRel + 2))}");
                    Line($"   other plausible CA/PA u16 pairs: {string.Join("  ", caPa.Take(40))}");
                }

                // Pointer fields of the person sub-object (contract, nation, club live behind these).
                var ptrs = new List<string>();
                for (int i = 0; i < 0x200; i += 8)
                {
                    ulong p = mem.Ptr(c.Person + (ulong)i);
                    if (p == 0 || mem.InAnyImage(p)) continue;
                    ulong pv = mem.U64(p);
                    if (mem.InVtRange(pv) && mem.Class(pv) is { Valid: true } pc)
                        ptrs.Add($"+0x{i:X}→'{pc.TypeName ?? "?"}'");
                }
                Line($"   object pointers in person: {string.Join("  ", ptrs)}");

                // Personality window and hex dump.
                Line($"   person+0x60..0x90: {Hex(mem.ReadBytes(c.Person + 0x60, 0x30))}");
                Line("   hexdump of complete object:");
                Line(HexDump(obj, objStart));

                candOut.Add(new
                {
                    rank, score = c.Score, person = $"0x{c.Person:X}", vtable = $"0x{c.Vtable:X}",
                    image = img?.FileName, typeName = c.Class.TypeName, offsetToTop = c.Class.OffsetToTop,
                    objectStart = $"0x{objStart:X}",
                    fields = c.Fields.Select(fx => new { text = needles[fx.needle].Text, role = needles[fx.needle].Role,
                                                         offset = $"0x{fx.off:X}", fx.nested, textOffset = fx.textOff }),
                    attributeBlocks = attrHits, birthDate = dobHits, height = heightHits, caPaPairs = caPa, pointers = ptrs,
                    vtables = subs,
                });

                // ------------------------------------------------ suggestion from the best candidate
                if (rank == 1)
                {
                    var first = c.Fields.Where(x => needles[x.needle].Role == "first").OrderBy(x => x.off).FirstOrDefault();
                    var last = c.Fields.Where(x => needles[x.needle].Role is "last" or "token").OrderBy(x => x.off).FirstOrDefault();
                    var full = c.Fields.Where(x => needles[x.needle].Role == "full").OrderBy(x => x.off).FirstOrDefault();
                    if (!suggestedPerson && first.off > 0)
                    {
                        int shift = first.off - cfg.Person.FirstName;
                        ShiftPerson(suggestion.Person, shift);
                        suggestion.Person.FirstName = first.off;
                        if (last.off > 0) suggestion.Person.SecondName = last.off;
                        if (full.off > 0 && full.off != first.off) suggestion.Person.CommonName = full.off;
                        suggestion.Strings.Nested = first.nested;
                        suggestion.Strings.TextOffset = first.textOff;
                        var dobInPerson = dobRel.Where(r => r >= 0).ToList();
                        if (dobInPerson.Count > 0) suggestion.Person.Dob = dobInPerson[0];
                        suggestedPerson = true;
                    }
                    if (isStaff) staffOffs.Add(sub); else playerOffs.Add(sub);
                    if (c.Class.TypeName != null) (isStaff ? staffTypes : playerTypes).Add(c.Class.TypeName);
                    if (bestAttrRel >= 0)
                    {
                        if (!isStaff && !suggestedPlayer)
                        {
                            ShiftPlayer(suggestion.Player, bestAttrRel - cfg.Player.Attributes);
                            suggestion.Player.AttributeScale = bestScaleMode;
                            if (heightRel.Count == 1) suggestion.Player.Height = heightRel[0];
                            suggestedPlayer = true;
                        }
                        if (isStaff && !suggestedStaff)
                        {
                            ShiftStaff(suggestion.Staff, bestAttrRel - cfg.Staff.Attributes);
                            suggestion.Staff.AttributeScale = bestScaleMode;
                            suggestedStaff = true;
                        }
                    }
                }
                Line();
            }
            targetsOut.Add(new { name = tg.Name, kind = tg.Kind, candidates = candOut });
        }

        // When we found the real classes, keep only what we saw (old Windows values just add noise).
        if (playerOffs.Count > 0) suggestion.PlayerOffsets = playerOffs.ToList();
        if (staffOffs.Count > 0) suggestion.StaffOffsets = staffOffs.ToList();
        // Class names are only required when one of the classes sits at offset 0.
        suggestion.PlayerTypes = playerOffs.Contains(0) ? playerTypes.ToList() : new();
        suggestion.StaffTypes = staffOffs.Contains(0) ? staffTypes.ToList() : new();
        suggestion.Version = $"discovered {DateTime.Now:yyyy-MM-dd HH:mm} (person:{suggestedPerson} player:{suggestedPlayer} staff:{suggestedStaff})";
        suggestion.Verified = false;
        var engine = cands.Values.OrderByDescending(c => c.Score).Select(c => mem.ImageOf(c.Vtable)?.FileName).FirstOrDefault();
        if (!string.IsNullOrEmpty(engine)) suggestion.EngineImage = engine;

        Line("== Suggested offsets (offsets.suggested.json) ==");
        Line($"   engine image: {suggestion.EngineImage}");
        Line($"   person found: {suggestedPerson} · player attributes found: {suggestedPlayer} · staff attributes found: {suggestedStaff}");
        Line($"   player classes (person sub-object offsets): {string.Join(", ", suggestion.PlayerOffsets.Select(x => $"0x{x:X}"))}");
        Line($"   staff classes: {string.Join(", ", suggestion.StaffOffsets.Select(x => $"0x{x:X}"))}");
        Line($"   class names seen — players: {string.Join(", ", playerTypes)} · staff: {string.Join(", ", staffTypes)}");
        Line("   Fields other than names/attributes/birth date are SHIFTED GUESSES from the FM26 layout.");
        Line("   Apply them in the app (Calibration → Apply), run a scan, and compare a few players with the game.");
        Line();
        Line($"Finished in {sw.ElapsedMilliseconds / 1000.0:N1} s");

        report["targets"] = targetsOut;
        report["suggestedOffsets"] = JsonSerializer.Deserialize<object>(suggestion.ToJson());
        try
        {
            Paths.WriteAtomic(Paths.SuggestedOffsets, suggestion.ToJson());
            Paths.WriteAtomic(Paths.DiscoveryTxt, sb.ToString());
            Paths.WriteAtomic(Paths.DiscoveryJson, JsonSerializer.Serialize(report, Json.Plain));
        }
        catch (Exception e) { Log.Error("writing discovery report: " + e); }

        Log.Info($"Discovery done in {sw.ElapsedMilliseconds} ms → {Paths.DiscoveryTxt}");
        Status.Write("done", 1, suggestedPlayer || suggestedStaff
            ? "Discovery finished — suggested offsets ready."
            : "Discovery finished — see the report (no full attribute match yet).", mode: "discover");
    }

    private static void Fail(string msg)
    {
        Log.Error(msg);
        Status.Write("error", -1, msg, mode: "discover");
    }

    /// <summary>All 8-byte-aligned locations in the heap holding one of the given values.</summary>
    private static List<(ulong loc, ulong val)> ScanPointers(Memory mem, HashSet<ulong> targets, Action<double> progress)
    {
        var result = new ConcurrentBag<(ulong, ulong)>();
        if (targets.Count == 0) return new();
        ulong min = targets.Min(), max = targets.Max();
        int count = 0;
        mem.ScanHeap((at, data, w) =>
        {
            var q = MemoryMarshal.Cast<byte, ulong>(data.Slice(0, data.Length & ~7));
            for (int i = 0; i < q.Length; i++)
            {
                ulong v = q[i];
                if (v < min || v > max || !targets.Contains(v)) continue;
                if (Interlocked.Increment(ref count) > 2_000_000) return;
                result.Add((at + (ulong)i * 8, v));
            }
        }, progress);
        return result.Distinct().ToList();
    }

    // FM26-relative shifts: keep the known internal spacing, move the whole block.
    private static void ShiftPerson(Offsets.PersonLayout p, int d)
    {
        p.SecondName += d; p.CommonName += d; p.Nation += d; p.Dob += d; p.Contract += d; p.Gender += d;
        foreach (var k in p.Personality.Keys.ToList()) p.Personality[k] += d;
    }

    private static void ShiftPlayer(Offsets.PlayerLayout p, int d)
    {
        p.Ca += d; p.Pa += d; p.HomeRep += d; p.CurrentRep += d; p.WorldRep += d; p.Height += d;
        p.Positions += d; p.Attributes += d; p.Value += d; p.AskingPrice += d;
    }

    private static void ShiftStaff(Offsets.StaffLayout s, int d)
    {
        s.Ca += d; s.Pa += d; s.CurrentRep += d; s.WorldRep += d; s.Attributes += d;
    }

    private static string Hex(byte[] b) => string.Join(" ", b.Select(x => x.ToString("X2")));

    private static string HexDump(byte[] b, ulong baseAddr)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < b.Length; i += 16)
        {
            int n = Math.Min(16, b.Length - i);
            sb.Append($"   +{i:X4} ");
            for (int j = 0; j < 16; j++) sb.Append(j < n ? b[i + j].ToString("X2") + " " : "   ");
            sb.Append(' ');
            for (int j = 0; j < n; j++) { byte c = b[i + j]; sb.Append(c is >= 32 and < 127 ? (char)c : '.'); }
            sb.AppendLine();
        }
        return sb.ToString().TrimEnd();
    }
}
