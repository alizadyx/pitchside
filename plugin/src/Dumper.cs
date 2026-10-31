using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace Pitchside;

/// <summary>
/// Full scan: walks FM's heap once, recognises person objects by their C++ class
/// (vtable offset-to-top in offsets.json), reads every player and staff member and
/// writes export.json for the viewer app.
/// </summary>
internal static partial class Dumper
{
    private sealed class Rec
    {
        public uint Uid;
        public bool IsPlayer;
        public string Name, Surname, Nation, Club, Division, Dob, Expires, Foot;
        public int Ca, Pa, Height, Job, Gender, CurRep, WorldRep, StatusFlags, TeamRep, TeamAge;
        /// <summary>The club that holds his contract, when he plays somewhere else (on loan).</summary>
        public string OwnerClub;
        public long Value = -1, Asking = -1, Wage = -1;
        public ulong PersonAddr, ContractAddr, TeamAddr;
        public int Sub;
        public byte[] Attrs, Hidden, Personality, Positions, StaffAttrs;
    }

    [ThreadStatic] private static byte[] _block;

    public static void Run(Request req)
    {
        var sw = System.Diagnostics.Stopwatch.StartNew();
        var cfg = Offsets.Load();
        int db = req.Database switch { "women" => 1, "both" => 2, _ => 0 };
        Status.Write("scanning", 0, "Mapping memory…", mode: "dump");

        var mem = new Memory(cfg.EngineImage);
        if (mem.VtMin == 0)
        {
            Status.Write("error", -1, $"Engine image '{cfg.EngineImage}' not found — run Calibration first.", mode: "dump");
            return;
        }

        var playerSet = cfg.PlayerOffsets.ToHashSet();
        var staffSet = cfg.StaffOffsets.ToHashSet();
        var playerTypes = cfg.PlayerTypes.Where(x => !string.IsNullOrEmpty(x)).ToHashSet();
        var staffTypes = cfg.StaffTypes.Where(x => !string.IsNullOrEmpty(x)).ToHashSet();
        // A class at offset 0 can't be told apart by offset alone — require its name then.
        if (playerTypes.Count == 0 && playerSet.Contains(0)) playerSet.Remove(0);
        if (staffTypes.Count == 0 && staffSet.Contains(0)) staffSet.Remove(0);
        var players = new ConcurrentDictionary<uint, Rec>();
        var staff = new ConcurrentDictionary<uint, Rec>();
        var nationCache = new ConcurrentDictionary<ulong, string>();
        var teamCache = new ConcurrentDictionary<ulong, (string club, string div, int rep, int age)>();
        var dateVotes = new ConcurrentDictionary<uint, int>();
        var signedVotes = new ConcurrentDictionary<uint, int>();
        var teamObjs = new ConcurrentDictionary<ulong, byte>();
        string teamType = cfg.Club.TeamType;
        var vtCounts = new Dictionary<ulong, long>[Memory.Workers];
        for (int i = 0; i < vtCounts.Length; i++) vtCounts[i] = new();
        long skippedGender = 0, rejected = 0;

        // How many bytes of each object we need in one read.
        int personSpan = new[] { cfg.Person.FirstName, cfg.Person.SecondName, cfg.Person.CommonName, cfg.Person.Nation,
                                 cfg.Person.Dob, cfg.Person.Contract, cfg.Person.Club, cfg.Person.Gender, cfg.ObjUid }
                         .Concat(cfg.Person.Personality.Values).Max() + 16;
        int playerSpan = new[] { cfg.Player.Ca, cfg.Player.Pa, cfg.Player.CurrentRep, cfg.Player.WorldRep, cfg.Player.Height,
                                 cfg.Player.Positions + cfg.Player.PositionKeys.Count, cfg.Player.Value, cfg.Player.AskingPrice,
                                 cfg.Player.Attributes + cfg.Player.AttributeMap.Values.Concat(cfg.Player.HiddenMap.Values).Max() }.Max() + 16;
        int staffSpan = new[] { cfg.Staff.Ca, cfg.Staff.Pa, cfg.Staff.CurrentRep, cfg.Staff.WorldRep,
                                cfg.Staff.Attributes + cfg.Staff.AttributeMap.Values.Max() }.Max() + 16;

        long unread = mem.ScanHeap((at, data, w) =>
        {
            var q = MemoryMarshal.Cast<byte, ulong>(data.Slice(0, data.Length & ~7));
            var counts = vtCounts[w];
            for (int i = 0; i < q.Length; i++)
            {
                ulong v = q[i];
                if (v < mem.VtMin || v >= mem.VtMax || !mem.InVtRange(v)) continue;
                counts[v] = counts.GetValueOrDefault(v) + 1;
                var ci = mem.Class(v);
                if (!ci.Valid) continue;
                int sub = ci.SubObjectOffset;
                if (sub == 0 && teamType != null && ci.TypeName == teamType)
                {
                    teamObjs.TryAdd(at + (ulong)i * 8, 0);
                    continue;
                }
                bool isPlayer = playerSet.Contains(sub) && (playerTypes.Count == 0 || (ci.TypeName != null && playerTypes.Contains(ci.TypeName)));
                bool isStaff = !isPlayer && staffSet.Contains(sub) && (staffTypes.Count == 0 || (ci.TypeName != null && staffTypes.Contains(ci.TypeName)));
                if (!isPlayer && !isStaff) continue;

                ulong person = at + (ulong)i * 8;
                ulong objStart = person - (ulong)sub;
                int len = Math.Max(sub + personSpan, isPlayer ? playerSpan : staffSpan);
                var blk = _block ??= new byte[0x4000];
                if (len > blk.Length || !mem.Read(objStart, blk, 0, len)) continue;

                uint uid = BinaryPrimitives.ReadUInt32LittleEndian(blk.AsSpan(sub + cfg.ObjUid));
                if (uid == 0 || uid == uint.MaxValue) continue;
                if ((isPlayer ? players : staff).ContainsKey(uid)) continue;

                bool female = (blk[sub + cfg.Person.Gender] & cfg.Person.GenderFemaleBit) != 0;
                if (female ? db == 0 : db == 1) { Interlocked.Increment(ref skippedGender); continue; }

                var r = isPlayer ? ReadPlayer(mem, cfg, blk, objStart, sub) : ReadStaff(mem, cfg, blk, objStart, sub);
                if (r == null) { Interlocked.Increment(ref rejected); continue; }
                r.Uid = uid;
                r.PersonAddr = person;
                r.Sub = sub;
                r.Gender = female ? 1 : 0;
                ReadPersonCommon(mem, cfg, r, blk, person, sub, nationCache, teamCache, dateVotes, signedVotes);
                if (string.IsNullOrEmpty(r.Name)) { Interlocked.Increment(ref rejected); continue; }
                (isPlayer ? players : staff).TryAdd(uid, r);
            }
        }, p => Status.Write("scanning", 0.9 * p, "Reading players and staff…", mode: "dump",
                             players: players.Count, staff: staff.Count));

        foreach (var uid in players.Keys) staff.TryRemove(uid, out _);   // player-coaches: keep as player

        // Where each player actually plays: the squad lists kept on every team (first team, U21,
        // U18, or another club's team while on loan). Contracts only say who owns him.
        Status.Write("scanning", 0.91, "Reading squads…", mode: "dump", players: players.Count, staff: staff.Count);
        string squadSummary = AssignSquads(mem, cfg, teamObjs.Keys.ToList(), players.Values.ToList(), teamCache, dateVotes);
        Log.Info("Squads: " + squadSummary);

        // In-game date: the most recent contract signing (several players sign or renew every day
        // somewhere in the world). Needs at least two signings that day so one odd value can't skew it.
        string gameDate = null;
        var signed = signedVotes.Where(kv => kv.Value >= 2).Select(kv => kv.Key).DefaultIfEmpty(0u).Max();
        if (signed != 0) gameDate = FmDate.Iso(signed);
        if (gameDate == null && !dateVotes.IsEmpty)
        {
            var top = dateVotes.OrderByDescending(kv => kv.Value).First();
            if (top.Value >= 3) gameDate = FmDate.Iso(top.Key);
        }

        Status.Write("scanning", 0.93, "Writing export…", mode: "dump", players: players.Count, staff: staff.Count);
        var warnings = new List<string>();
        double unreadFrac = mem.TotalRegionBytes == 0 ? 0 : (double)unread / mem.TotalRegionBytes;
        if (unreadFrac > 0.05) warnings.Add($"{unreadFrac:P0} of memory could not be read during the scan.");
        if (!cfg.Verified) warnings.Add("Offsets are not verified for this game version — compare a few players with the game.");
        if (players.Count < 100) warnings.Add("Very few players found — offsets are probably wrong. Run Calibration.");
        if (gameDate == null) warnings.Add("In-game date not found — set the season year in the app's settings for correct ages.");

        WriteExport(cfg, players.Values, staff.Values, gameDate, warnings, sw.ElapsedMilliseconds);
        WriteProbe(mem, cfg, req, players.Values.Concat(staff.Values));
        if (!string.IsNullOrWhiteSpace(req.Club))
            WriteClubProbe(mem, cfg, req.Club.Trim(), players.Values, staff.Values, teamObjs.Keys.ToList(), squadSummary);
        WriteDiagnostics(mem, cfg, vtCounts, players.Count, staff.Count, skippedGender, rejected, unread, sw.ElapsedMilliseconds);

        Log.Info($"Scan done: {players.Count:N0} players, {staff.Count:N0} staff in {sw.ElapsedMilliseconds} ms");
        Status.Write("done", 1, players.Count < 100 ? "Scan finished, but very few players were found — calibration needed."
                                                    : $"Scan finished in {sw.ElapsedMilliseconds / 1000.0:N0} s.",
                     players: players.Count, staff: staff.Count, mode: "dump");
    }

    // ------------------------------------------------------------------ readers

    private static int U16(byte[] b, int o) => o >= 0 && o + 2 <= b.Length ? BinaryPrimitives.ReadUInt16LittleEndian(b.AsSpan(o)) : 0;
    private static uint U32(byte[] b, int o) => o >= 0 && o + 4 <= b.Length ? BinaryPrimitives.ReadUInt32LittleEndian(b.AsSpan(o)) : 0;
    private static ulong U64(byte[] b, int o) => o >= 0 && o + 8 <= b.Length ? BinaryPrimitives.ReadUInt64LittleEndian(b.AsSpan(o)) : 0;
    private static long Money(uint v) => v == uint.MaxValue || v == 300_000_000u ? -1 : v;

    private static byte Scaled(byte raw, int scale)
    {
        int v = scale <= 1 ? raw : (int)Math.Floor(raw / (double)scale + 0.5);
        return (byte)Math.Clamp(v, 0, 20);
    }

    private static Rec ReadPlayer(Memory mem, Offsets cfg, byte[] b, ulong objStart, int sub)
    {
        var p = cfg.Player;
        int ca = U16(b, p.Ca), pa = U16(b, p.Pa);
        if (ca is < 1 or > 200) return null;
        if (pa is < 1 or > 200) pa = 0;
        var r = new Rec { IsPlayer = true, Ca = ca, Pa = pa };
        r.Attrs = p.AttributeMap.Values.Select(o => Scaled(b[p.Attributes + o], p.AttributeScale)).ToArray();
        r.Hidden = p.HiddenMap.Values.Select(o => Scaled(b[p.Attributes + o], p.AttributeScale)).ToArray();
        r.Positions = Enumerable.Range(0, p.PositionKeys.Count).Select(i => (byte)Math.Min((int)b[p.Positions + i], 20)).ToArray();
        int h = U16(b, p.Height);
        r.Height = h is >= 140 and <= 220 ? h : 0;
        r.Value = Money(U32(b, p.Value));
        r.Asking = Money(U32(b, p.AskingPrice));
        r.CurRep = U16(b, p.CurrentRep);
        r.WorldRep = U16(b, p.WorldRep);
        if (p.AttributeMap.TryGetValue("LeftFoot", out var lfo) && p.AttributeMap.TryGetValue("RightFoot", out var rfo))
        {
            int lf = Scaled(b[p.Attributes + lfo], p.AttributeScale), rf = Scaled(b[p.Attributes + rfo], p.AttributeScale);
            r.Foot = lf >= 14 && rf >= 14 ? "B" : rf >= lf ? "R" : "L";
        }
        return r;
    }

    private static Rec ReadStaff(Memory mem, Offsets cfg, byte[] b, ulong objStart, int sub)
    {
        var s = cfg.Staff;
        int ca = U16(b, s.Ca), pa = U16(b, s.Pa);
        // Staff are recognised by class; CA/PA position may still be uncalibrated.
        if (ca is < 1 or > 200) ca = 0;
        if (pa is < 1 or > 200) pa = 0;
        return new Rec
        {
            IsPlayer = false, Ca = ca, Pa = pa,
            CurRep = U16(b, s.CurrentRep), WorldRep = U16(b, s.WorldRep),
            StaffAttrs = s.AttributeMap.Select(kv => Scaled(b[s.Attributes + kv.Value],
                                     s.RawKeys.Contains(kv.Key) ? 1 : s.AttributeScale)).ToArray(),
        };
    }

    private static void ReadPersonCommon(Memory mem, Offsets cfg, Rec r, byte[] b, ulong person, int sub,
        ConcurrentDictionary<ulong, string> nations,
        ConcurrentDictionary<ulong, (string club, string div, int rep, int age)> teams,
        ConcurrentDictionary<uint, int> dateVotes, ConcurrentDictionary<uint, int> signedVotes)
    {
        var pe = cfg.Person;
        bool nested = cfg.Strings.Nested;
        int to = cfg.Strings.TextOffset;
        string common = mem.FmString(person + (ulong)pe.CommonName, nested, to);
        if (!Plausible(common))
        {
            string first = mem.FmString(person + (ulong)pe.FirstName, nested, to);
            string second = mem.FmString(person + (ulong)pe.SecondName, nested, to);
            common = string.Join(" ", new[] { first, second }.Where(Plausible));
            // Surname for pasting into FM's search ("De Bruyne"); players known by a common name use that.
            if (Plausible(first) && Plausible(second)) r.Surname = second;
        }
        r.Name = Plausible(common) ? common : null;
        if (r.Name == null) return;

        r.Dob = FmDate.Iso(U32(b, sub + pe.Dob));
        r.Personality = pe.Personality.Values.Select(o => { byte x = b[sub + o]; return x is >= 1 and <= 20 ? x : (byte)0; }).ToArray();

        ulong nat = U64(b, sub + pe.Nation);
        if (nat >= 0x1000 && nat < 0x0000_8000_0000_0000UL)
            r.Nation = nations.GetOrAdd(nat, n => mem.FmString(n + (ulong)pe.NationShortName, false, to)
                                                  ?? mem.FmString(n + (ulong)pe.NationName, false, to));

        ulong con = U64(b, sub + pe.Contract);
        if (con >= 0x1000 && con < 0x0000_8000_0000_0000UL)
        {
            var c = cfg.Contract;
            r.Wage = Money(mem.U32(con + (ulong)c.WeeklyWage));
            r.Expires = FmDate.Iso(mem.U32(con + (ulong)c.Expiry));
            if (r.Expires != null && string.CompareOrdinal(r.Expires, "2000") < 0) r.Expires = null;
            r.StatusFlags = mem.U8(con + (ulong)c.StatusFlags);
            if (c.Signed > 0)
            {
                uint sd = mem.U32(con + (ulong)c.Signed);
                if (FmDate.Decode(sd).year is >= 2020 and <= 2080) signedVotes.AddOrUpdate(sd, 1, (_, n) => n + 1);
            }
            if (!r.IsPlayer) r.Job = mem.U8(con + (ulong)c.Job);
            ulong team = mem.Ptr(con + (ulong)c.Team);
            r.ContractAddr = con;
            r.TeamAddr = team;
            if (team != 0)
            {
                var t = teams.GetOrAdd(team, tm => ResolveTeam(mem, cfg, tm, dateVotes));
                r.Club = t.club; r.Division = t.div; r.TeamRep = t.rep; r.TeamAge = t.age;
            }
        }
        if (pe.Club > 0)
        {
            ulong club = U64(b, sub + pe.Club);
            if (club >= 0x1000 && club < 0x0000_8000_0000_0000UL)
            {
                var k = cfg.Club;
                string n = mem.FmString(club + (ulong)k.ClubName, cfg.Strings.Nested, to)
                        ?? mem.FmString(club + (ulong)k.ClubName, false, to)
                        ?? mem.FmString(club + (ulong)k.ClubShortName, false, to);
                if (Plausible(n)) r.Club = n;
            }
        }
    }

    private static (string, string, int, int) ResolveTeam(Memory mem, Offsets cfg, ulong team, ConcurrentDictionary<uint, int> votes)
    {
        var k = cfg.Club;
        int to = cfg.Strings.TextOffset;
        int rep = mem.U16(team + (ulong)k.TeamReputation);
        ulong club = mem.Ptr(team + (ulong)k.TeamClub);
        string name = club == 0 ? null : (mem.FmString(club + (ulong)k.ClubName, false, to) ?? mem.FmString(club + (ulong)k.ClubShortName, false, to));
        ulong comp = mem.Ptr(team + (ulong)k.TeamCompetition);
        string div = comp == 0 ? null : (mem.FmString(comp + (ulong)k.CompName, false, to) ?? mem.FmString(comp + (ulong)k.CompShortName, false, to));
        if (k.TeamDate > 0)
        {
            uint td = mem.U32(team + (ulong)k.TeamDate);
            if (FmDate.Decode(td).year is >= 2025 and <= 2080) votes.AddOrUpdate(td, 1, (_, n) => n + 1);
        }
        ulong sched = k.TeamSchedule > 0 ? mem.Ptr(team + (ulong)k.TeamSchedule) : 0;
        if (sched != 0)
        {
            uint d = mem.U32(sched + (ulong)k.ScheduleNextMatch);
            var (y, _) = FmDate.Decode(d);
            if (y is >= 2025 and <= 2080) votes.AddOrUpdate(d, 1, (_, n) => n + 1);
        }
        int age = k.TeamAgeLimit > 0 ? mem.U8(team + (ulong)k.TeamAgeLimit) : 0;
        return (Plausible(name) ? name : null, Plausible(div) ? div : null, rep is >= 0 and <= 12000 ? rep : 0,
                age is >= 14 and <= 100 ? age : 0);
    }

    /// <summary>The class name of the object at <paramref name="obj"/>, or null.</summary>
    private static string ClassName(Memory mem, ulong obj)
    {
        if (obj < 0x1000 || obj >= 0x0000_8000_0000_0000UL || mem.InAnyImage(obj)) return null;
        ulong vt = mem.U64(obj);
        if (!mem.InVtRange(vt)) return null;
        var ci = mem.Class(vt);
        return ci.Valid ? ci.TypeName : null;
    }

    /// <summary>A team's squad list as raw pointers (empty when it can't be read).</summary>
    internal static ulong[] SquadList(Memory mem, Offsets cfg, ulong team)
    {
        int off = cfg.Club.TeamSquad;
        if (off <= 0) return Array.Empty<ulong>();
        ulong b = mem.Ptr(team + (ulong)off), e = mem.Ptr(team + (ulong)off + 8);
        if (b == 0 || e <= b || (e - b) % 8 != 0 || e - b > 8 * 400) return Array.Empty<ulong>();
        var raw = mem.ReadBytes(b, (int)(e - b));
        if (raw == null) return Array.Empty<ulong>();
        var list = new ulong[raw.Length / 8];
        for (int i = 0; i < list.Length; i++) list[i] = BitConverter.ToUInt64(raw, i * 8);
        return list;
    }

    /// <summary>
    /// Moves every player listed in a club team's squad to that team: youth players to the U21/U18,
    /// loanees to the club they're playing for (remembering the owner). National teams are skipped.
    /// Players found in no list keep what their contract says.
    /// </summary>
    private static string AssignSquads(Memory mem, Offsets cfg, List<ulong> teamAddrs, List<Rec> players,
        ConcurrentDictionary<ulong, (string club, string div, int rep, int age)> teams, ConcurrentDictionary<uint, int> votes)
    {
        try
        {
            if (cfg.Club.TeamSquad <= 0) return "squad lists off";
            var byObj = new Dictionary<ulong, Rec>();
            foreach (var r in players)
            {
                byObj[r.PersonAddr - (ulong)r.Sub] = r;
                byObj.TryAdd(r.PersonAddr, r);
            }
            var placed = new Dictionary<Rec, List<ulong>>(ReferenceEqualityComparer.Instance);
            int lists = 0, entries = 0, matched = 0, national = 0;
            foreach (ulong t in teamAddrs)
            {
                var list = SquadList(mem, cfg, t);
                if (list.Length == 0) continue;
                if (cfg.Club.ClubType != null && ClassName(mem, mem.Ptr(t + (ulong)cfg.Club.TeamClub)) != cfg.Club.ClubType)
                {
                    national++;
                    continue;
                }
                lists++;
                foreach (ulong p in list)
                {
                    entries++;
                    if (!byObj.TryGetValue(p, out var r)) continue;
                    matched++;
                    if (!placed.TryGetValue(r, out var l)) placed[r] = l = new List<ulong>();
                    l.Add(t);
                }
            }
            int loans = 0;
            foreach (var (r, ts) in placed)
            {
                var options = ts.Distinct()
                    .Select(t => (t, info: teams.GetOrAdd(t, x => ResolveTeam(mem, cfg, x, votes))))
                    .Where(x => x.info.club != null)
                    .ToList();
                if (options.Count == 0) continue;
                // Playing for another club beats the owner's lists; otherwise his club's top team.
                var pick = options
                    .OrderByDescending(x => r.Club != null && x.info.club != r.Club ? 1 : 0)
                    .ThenByDescending(x => x.info.rep)
                    .First();
                if (r.Club != null && pick.info.club != r.Club) { r.OwnerClub = r.Club; loans++; }
                r.Club = pick.info.club;
                r.Division = pick.info.div ?? r.Division;
                r.TeamRep = pick.info.rep;
                r.TeamAge = pick.info.age;
                r.TeamAddr = pick.t;
            }
            return $"{lists:N0} club squad lists ({national:N0} other lists skipped), {matched:N0} of {entries:N0} entries matched, " +
                   $"{placed.Count:N0} players placed, {loans:N0} on loan";
        }
        catch (Exception e)
        {
            Log.Warn("squads: " + e.Message);
            return "squad lists failed: " + e.Message;
        }
    }

    private static bool Plausible(string s)
    {
        if (string.IsNullOrWhiteSpace(s) || s.Length > 60) return false;
        int letters = s.Count(char.IsLetter);
        return letters >= 1 && letters >= s.Length / 2 && !s.Any(c => char.IsControl(c));
    }

    // ------------------------------------------------------------------ output

    private static readonly Dictionary<int, string> Jobs = new()
    {
        [1] = "Player", [2] = "Coach", [3] = "Player/Coach", [4] = "Chairman", [6] = "Director",
        [8] = "Managing Director", [10] = "Director of Football", [12] = "Physio", [14] = "Scout",
        [16] = "Manager", [17] = "Player/Manager", [20] = "Assistant Manager", [21] = "Player/Assistant Manager",
        [22] = "Set Piece Coach", [24] = "General Manager", [26] = "Fitness Coach", [27] = "Player/Fitness Coach",
        [34] = "Goalkeeping Coach", [35] = "Player/GK Coach", [36] = "Head of Performance Analysis",
        [38] = "Club Doctor", [40] = "Head of Sports Science", [42] = "Data Analyst", [44] = "Chief Scout",
        [45] = "Player/Chief Scout", [46] = "Doctor", [48] = "Sports Scientist", [49] = "Player/Youth Coach",
        [50] = "Head Physio", [52] = "U19 Manager", [54] = "First-Team Coach", [64] = "Head of Youth Development",
        [65] = "Player/Head of Youth", [66] = "Owner", [70] = "President", [86] = "Loan Manager",
        [88] = "Technical Director", [144] = "Caretaker Manager",
    };

    private static void WriteExport(Offsets cfg, ICollection<Rec> players, ICollection<Rec> staff,
                                    string gameDate, List<string> warnings, long ms)
    {
        Directory.CreateDirectory(Paths.Dir);
        string tmp = Paths.Export + ".tmp";
        using (var fs = File.Create(tmp))
        using (var w = new Utf8JsonWriter(fs))
        {
            w.WriteStartObject();
            w.WriteStartObject("meta");
            w.WriteString("scannedAt", DateTime.Now.ToString("s"));
            if (gameDate != null) w.WriteString("gameDate", gameDate); else w.WriteNull("gameDate");
            w.WriteString("offsetsVersion", cfg.Version);
            w.WriteBoolean("offsetsVerified", cfg.Verified);
            w.WriteString("plugin", Plugin.Version);
            w.WriteNumber("scanMs", ms);
            WriteStrings(w, "playerAttrKeys", cfg.Player.AttributeMap.Keys);
            WriteStrings(w, "hiddenKeys", cfg.Player.HiddenMap.Keys);
            WriteStrings(w, "personalityKeys", cfg.Person.Personality.Keys);
            WriteStrings(w, "positionKeys", cfg.Player.PositionKeys);
            WriteStrings(w, "staffAttrKeys", cfg.Staff.AttributeMap.Keys);
            WriteStrings(w, "warnings", warnings);
            w.WriteEndObject();

            w.WriteStartArray("players");
            foreach (var r in players) WriteRec(w, r);
            w.WriteEndArray();
            w.WriteStartArray("staff");
            foreach (var r in staff) WriteRec(w, r);
            w.WriteEndArray();
            w.WriteEndObject();
        }
        File.Move(tmp, Paths.Export, true);
    }

    private static void WriteStrings(Utf8JsonWriter w, string name, IEnumerable<string> xs)
    {
        w.WriteStartArray(name);
        foreach (var x in xs) w.WriteStringValue(x);
        w.WriteEndArray();
    }

    private static void WriteBytes(Utf8JsonWriter w, string name, byte[] b)
    {
        if (b == null) return;
        w.WriteStartArray(name);
        foreach (var x in b) w.WriteNumberValue(x);
        w.WriteEndArray();
    }

    private static void WriteRec(Utf8JsonWriter w, Rec r)
    {
        w.WriteStartObject();
        w.WriteNumber("id", r.Uid);
        w.WriteString("n", r.Name);
        if (r.Surname != null) w.WriteString("sn", r.Surname);
        if (r.Dob != null) w.WriteString("dob", r.Dob);
        if (r.Nation != null) w.WriteString("nat", r.Nation);
        if (r.Club != null) w.WriteString("club", r.Club);
        if (r.Division != null) w.WriteString("div", r.Division);
        if (r.TeamAddr != 0)
        {
            // Which of the club's teams (first team, U21, U18…) the contract is with.
            w.WriteNumber("tm", (uint)((r.TeamAddr >> 3) ^ (r.TeamAddr >> 35)));
            w.WriteNumber("trep", r.TeamRep);
            if (r.TeamAge > 0) w.WriteNumber("tage", r.TeamAge);   // 100 senior, 21 = U21…
        }
        if (r.OwnerClub != null) w.WriteString("own", r.OwnerClub);   // on loan from
        w.WriteNumber("ca", r.Ca);
        w.WriteNumber("pa", r.Pa);
        w.WriteNumber("rep", r.CurRep);
        w.WriteNumber("wrep", r.WorldRep);
        if (r.Gender == 1) w.WriteNumber("f", 1);
        if (r.Wage >= 0) w.WriteNumber("wage", r.Wage);
        if (r.Expires != null) w.WriteString("exp", r.Expires);
        WriteBytes(w, "p", r.Personality);
        if (r.IsPlayer)
        {
            WriteBytes(w, "a", r.Attrs);
            WriteBytes(w, "h", r.Hidden);
            WriteBytes(w, "pos", r.Positions);
            if (r.Height > 0) w.WriteNumber("ht", r.Height);
            if (r.Foot != null) w.WriteString("ft", r.Foot);
            if (r.Value >= 0) w.WriteNumber("val", r.Value);
            if (r.Asking >= 0) w.WriteNumber("ask", r.Asking);
            int f = r.StatusFlags;
            if ((f & 0b1001) != 0) w.WriteBoolean("lst", true);
            if ((f & 0b10000) != 0) w.WriteBoolean("nfs", true);
            if ((f & 0b100000) != 0) w.WriteBoolean("rel", true);
        }
        else
        {
            WriteBytes(w, "s", r.StaffAttrs);
            w.WriteString("job", Jobs.TryGetValue(r.Job, out var j) ? j : "Staff");
        }
        w.WriteEndObject();
    }

    /// <summary>
    /// probe.txt — for the people named in the request (or the first few found), dumps the
    /// person block and the contract, club and nation objects it points to, plus every
    /// string reachable from them. This is how the contract/club layout gets mapped.
    /// </summary>
    private static void WriteProbe(Memory mem, Offsets cfg, Request req, IEnumerable<Rec> all)
    {
        try
        {
            var names = req.Targets.Select(t => t.Name?.Trim()).Where(n => !string.IsNullOrEmpty(n)).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var pick = all.Where(r => names.Contains(r.Name)).ToList();
            if (pick.Count == 0) pick = all.Where(r => r.IsPlayer).OrderByDescending(r => r.Ca).Take(3).ToList();
            var sb = new StringBuilder();
            sb.AppendLine($"Pitchside probe — {DateTime.Now:s}");
            foreach (var r in pick.Take(6))
            {
                ulong p = r.PersonAddr;
                sb.AppendLine($"\n######## {r.Name} (uid {r.Uid}, CA {r.Ca}) person @ {p:X}");
                sb.AppendLine(Hex("person", mem.ReadBytes(p, 0x140)));
                sb.AppendLine($"-- complete object (person at +0x{r.Sub:X})");
                sb.AppendLine(Hex("full", mem.ReadBytes(p - (ulong)r.Sub, r.Sub + 0x140)));
                for (int off = 0; off < 0x140; off += 8)
                {
                    ulong q = mem.Ptr(p + (ulong)off);
                    if (q == 0 || mem.InAnyImage(q)) continue;
                    ulong vt = mem.U64(q);
                    if (!mem.InVtRange(vt)) continue;
                    var ci = mem.Class(vt);
                    if (!ci.Valid) continue;
                    sb.AppendLine($"\n-- person+0x{off:X} -> {ci.TypeName} @ {q:X}");
                    sb.AppendLine(Hex("obj", mem.ReadBytes(q, 0x140)));
                    for (int so = 0; so < 0x140; so += 8)
                        foreach (var (nested, to) in new[] { (false, 4), (true, 4), (false, 0), (true, 0), (false, 0x10) })
                        {
                            string s = mem.FmString(q + (ulong)so, nested, to);
                            if (s != null && s.Length >= 2 && s.Count(char.IsLetter) >= 2)
                                sb.AppendLine($"   string @+0x{so:X} ({(nested ? "nested" : "indirect")}, text+{to}): {s}");
                        }
                }
            }
            Paths.WriteAtomic(System.IO.Path.Combine(Paths.Dir, "probe.txt"), sb.ToString());
        }
        catch (Exception e) { Log.Warn("probe: " + e.Message); }
    }

    private static string Hex(string label, byte[] b)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < b.Length; i += 16)
        {
            sb.Append($"  {label}+{i:X3} ");
            for (int j = 0; j < 16 && i + j < b.Length; j++) sb.Append(b[i + j].ToString("X2")).Append(' ');
            sb.AppendLine();
        }
        return sb.ToString().TrimEnd();
    }

    /// <summary>
    /// diagnostics.txt — the most common C++ classes on the heap. If a scan finds nothing,
    /// this list shows which classes exist, so the player/staff offsets can be corrected.
    /// </summary>
    private static void WriteDiagnostics(Memory mem, Offsets cfg, Dictionary<ulong, long>[] counts,
                                         int players, int staff, long skippedGender, long rejected, long unread, long ms)
    {
        try
        {
            var merged = new Dictionary<ulong, long>();
            foreach (var d in counts) foreach (var kv in d) merged[kv.Key] = merged.GetValueOrDefault(kv.Key) + kv.Value;
            var sb = new StringBuilder();
            sb.AppendLine($"Pitchside scan diagnostics — plugin {Plugin.Version} — {DateTime.Now:s}");
            sb.AppendLine($"offsets: {cfg.Version} (verified: {cfg.Verified}), engine image filter '{cfg.EngineImage}'");
            sb.AppendLine($"players {players:N0} · staff {staff:N0} · other-gender skipped {skippedGender:N0} · rejected {rejected:N0}");
            sb.AppendLine($"heap {mem.TotalRegionBytes / (1 << 20):N0} MB in {mem.Regions.Count:N0} regions, unreadable {unread / (1 << 20):N0} MB, {ms} ms");
            sb.AppendLine($"player sub-object offsets: {string.Join(", ", cfg.PlayerOffsets.Select(x => $"0x{x:X}"))}; staff: {string.Join(", ", cfg.StaffOffsets.Select(x => $"0x{x:X}"))}");
            sb.AppendLine();
            sb.AppendLine("Top C++ classes by instance count (count · sub-object offset · type · image):");
            foreach (var kv in merged.OrderByDescending(k => k.Value).Take(80))
            {
                var ci = mem.Class(kv.Key);
                var img = mem.ImageOf(kv.Key);
                sb.AppendLine($"  {kv.Value,9:N0}  0x{ci.SubObjectOffset,-5:X}  {ci.TypeName ?? "?",-50}  {img?.FileName}");
            }
            Paths.WriteAtomic(System.IO.Path.Combine(Paths.Dir, "diagnostics.txt"), sb.ToString());
        }
        catch (Exception e) { Log.Warn("diagnostics: " + e.Message); }
    }
}
