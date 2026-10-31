using System.Text;

namespace Pitchside;

/// <summary>
/// clubprobe.txt: everything needed to map team types (first team / U21 / U18 / loans), the
/// in-game date and unmapped staff attributes, without the user typing any values in.
/// </summary>
internal static partial class Dumper
{
    private static void WriteClubProbe(Memory mem, Offsets cfg, string club, ICollection<Rec> players, ICollection<Rec> staff,
                                       List<ulong> teamObjs = null, string squadSummary = null)
    {
        try
        {
            var sb = new StringBuilder();
            int to = cfg.Strings.TextOffset;
            sb.AppendLine($"Pitchside club probe — {club} — {DateTime.Now:s}");

            string ClubOfTeam(ulong team)
            {
                if (team == 0) return null;
                ulong c = mem.Ptr(team + (ulong)cfg.Club.TeamClub);
                if (c == 0) return null;
                return mem.FmString(c + (ulong)cfg.Club.ClubName, false, to) ?? mem.FmString(c + (ulong)cfg.Club.ClubShortName, false, to);
            }
            string CompOfTeam(ulong team)
            {
                ulong comp = team == 0 ? 0 : mem.Ptr(team + (ulong)cfg.Club.TeamCompetition);
                return comp == 0 ? null : (mem.FmString(comp + (ulong)cfg.Club.CompName, false, to) ?? mem.FmString(comp + (ulong)cfg.Club.CompShortName, false, to));
            }
            string ClassOf(ulong obj)
            {
                if (obj < 0x1000 || obj >= 0x0000_8000_0000_0000UL || mem.InAnyImage(obj)) return null;
                ulong vt = mem.U64(obj);
                if (!mem.InVtRange(vt)) return null;
                var ci = mem.Class(vt);
                return ci.Valid ? ci.TypeName : null;
            }
            void Pointers(ulong obj, int len, string label)
            {
                for (int o = 0; o < len; o += 8)
                {
                    ulong q = mem.Ptr(obj + (ulong)o);
                    string cls = ClassOf(q);
                    if (cls == null) continue;
                    string extra = "";
                    if (cls.Contains("TEAM")) extra = $" club={ClubOfTeam(q)} comp={CompOfTeam(q)} rep={mem.U16(q + (ulong)cfg.Club.TeamReputation)}";
                    else if (cls.Contains("CLUB")) extra = $" name={mem.FmString(q + (ulong)cfg.Club.ClubName, false, to)}";
                    sb.AppendLine($"   {label}+0x{o:X} -> {cls} @ {q:X}{extra}");
                }
            }
            void Dates(ulong obj, int len, string label)
            {
                var b = mem.ReadBytes(obj, len);
                if (b == null) return;
                var hits = new List<string>();
                for (int o = 0; o + 4 <= b.Length; o += 2)
                {
                    uint v = BitConverter.ToUInt32(b, o);
                    var (y, _) = FmDate.Decode(v);
                    if (y is >= 2020 and <= 2045) hits.Add($"+0x{o:X}={FmDate.Iso(v)}");
                }
                if (hits.Count > 0) sb.AppendLine($"   dates in {label}: {string.Join("  ", hits)}");
            }

            var mine = players.Where(r => r.Club == club).ToList();
            var myStaff = staff.Where(r => r.Club == club).ToList();
            sb.AppendLine($"{mine.Count} players and {myStaff.Count} staff at this club (players placed by squad lists where found).");

            // 0. Squad lists: who each of the club's teams really holds (this is what placed players)
            sb.AppendLine("\n#### SQUAD LISTS");
            sb.AppendLine($"Whole database: {squadSummary ?? "not read"}; {teamObjs?.Count ?? 0:N0} team objects found.");
            if (teamObjs != null)
            {
                var byObj = new Dictionary<ulong, Rec>();
                foreach (var r in players) { byObj[r.PersonAddr - (ulong)r.Sub] = r; byObj.TryAdd(r.PersonAddr, r); }
                foreach (ulong t in teamObjs.Where(t => ClubOfTeam(t) == club).OrderByDescending(t => mem.U16(t + (ulong)cfg.Club.TeamReputation)))
                {
                    var list = SquadList(mem, cfg, t);
                    int age = cfg.Club.TeamAgeLimit > 0 ? mem.U8(t + (ulong)cfg.Club.TeamAgeLimit) : 0;
                    sb.AppendLine($"\n== {CompOfTeam(t)} (age limit {age}, rep {mem.U16(t + (ulong)cfg.Club.TeamReputation)}) team @ {t:X}: {list.Length} entries");
                    int shown = 0;
                    foreach (ulong p in list)
                    {
                        if (byObj.TryGetValue(p, out var r))
                            sb.AppendLine($"   {r.Name} (CA {r.Ca}, born {r.Dob})" + (r.OwnerClub != null ? $"  ON LOAN from {r.OwnerClub}" : ""));
                        else if (shown++ < 10)
                            sb.AppendLine($"   ? {p:X} -> {ClassOf(p) ?? "not an object"}");
                    }
                }
            }
            var loanedOut = players.Where(r => r.OwnerClub == club).OrderByDescending(r => r.Ca).ToList();
            sb.AppendLine($"\nOut on loan ({loanedOut.Count}):");
            foreach (var r in loanedOut) sb.AppendLine($"   {r.Name} (CA {r.Ca}) at {r.Club} ({r.Division})");

            // 1. Teams of the club
            sb.AppendLine("\n#### TEAMS");
            foreach (var g in mine.Concat(myStaff).GroupBy(r => r.TeamAddr).OrderByDescending(g => g.Count()))
            {
                ulong t = g.Key;
                sb.AppendLine($"\n== team @ {t:X} class={ClassOf(t)} members={g.Count()} comp={CompOfTeam(t)} rep={mem.U16(t + (ulong)cfg.Club.TeamReputation)}");
                sb.AppendLine("   e.g. " + string.Join(", ", g.Take(6).Select(r => r.Name)));
                sb.AppendLine(Hex("team", mem.ReadBytes(t, 0x200) ?? Array.Empty<byte>()));
                Pointers(t, 0x200, "team");
                Dates(t, 0x200, "team");
            }

            // 2. Players: contracts (a loaned-out player may carry a second contract record)
            sb.AppendLine("\n#### PLAYERS");
            foreach (var r in mine.OrderByDescending(r => r.Ca))
            {
                sb.AppendLine($"\n-- {r.Name} (CA {r.Ca}, born {r.Dob}) team @ {r.TeamAddr:X} contract @ {r.ContractAddr:X} expires {r.Expires}");
                ulong otherClub = mem.Ptr(r.PersonAddr + 0xD8);
                if (ClassOf(otherClub) is string oc) sb.AppendLine($"   person+0xD8 -> {oc} name={mem.FmString(otherClub + (ulong)cfg.Club.ClubName, false, to)}");
                if (r.ContractAddr == 0) continue;
                sb.AppendLine(Hex("contract", mem.ReadBytes(r.ContractAddr, 0x140) ?? Array.Empty<byte>()));
                Pointers(r.ContractAddr, 0x140, "contract");
                Dates(r.ContractAddr, 0x140, "contract");
            }

            // 3. Staff attribute blocks (scaled ×5) with the mapped positions marked
            sb.AppendLine("\n#### STAFF");
            var mapped = cfg.Staff.AttributeMap.ToDictionary(kv => kv.Value, kv => kv.Key);
            foreach (var r in myStaff.OrderByDescending(r => r.Ca))
            {
                ulong obj = r.PersonAddr - (ulong)r.Sub;
                var b = mem.ReadBytes(obj + (ulong)cfg.Staff.Attributes, 0x60);
                if (b == null) continue;
                var cells = new List<string>();
                for (int i = 0; i < b.Length; i++)
                {
                    string key = mapped.TryGetValue(i, out var k) ? k : "?";
                    cells.Add($"{i:X2}:{b[i]}{(key == "?" ? "?" : "=" + key)}");
                }
                sb.AppendLine($"-- {r.Name} (CA {r.Ca})  {string.Join(" ", cells)}");
            }

            // 4. In-game date: a date (nearly) every team agrees on, directly or one pointer away
            sb.AppendLine("\n#### DATE CONSENSUS ACROSS TEAMS");
            var teams = players.Select(r => r.TeamAddr).Where(t => t != 0).Distinct().Take(400).ToList();
            var votes = new Dictionary<string, Dictionary<uint, int>>();
            void Vote(string where, uint v)
            {
                if (!votes.TryGetValue(where, out var d)) votes[where] = d = new();
                d[v] = d.GetValueOrDefault(v) + 1;
            }
            foreach (var t in teams)
            {
                var tb = mem.ReadBytes(t, 0x200);
                if (tb == null) continue;
                for (int o = 0; o + 4 <= tb.Length; o += 2)
                {
                    uint v = BitConverter.ToUInt32(tb, o);
                    if (FmDate.Decode(v).year is >= 2024 and <= 2045) Vote($"team+0x{o:X}", v);
                }
                for (int o = 0; o + 8 <= tb.Length; o += 8)
                {
                    ulong q = BitConverter.ToUInt64(tb, o);
                    if (ClassOf(q) == null) continue;
                    var qb = mem.ReadBytes(q, 0x200);
                    if (qb == null) continue;
                    for (int i = 0; i + 4 <= qb.Length; i += 2)
                    {
                        uint v = BitConverter.ToUInt32(qb, i);
                        if (FmDate.Decode(v).year is >= 2024 and <= 2045) Vote($"team+0x{o:X}->+0x{i:X}", v);
                    }
                }
            }
            foreach (var (where, d) in votes.Select(kv => (kv.Key, kv.Value))
                         .Select(x => (x.Key, x.Value, top: x.Value.OrderByDescending(kv => kv.Value).First()))
                         .Where(x => x.top.Value >= teams.Count / 3)
                         .OrderByDescending(x => x.top.Value).Take(40).Select(x => (x.Key, x.Value)))
            {
                var top = d.OrderByDescending(kv => kv.Value).Take(3).Select(kv => $"{FmDate.Iso(kv.Key)}×{kv.Value}");
                sb.AppendLine($"   {where}: {string.Join(", ", top)} (of {teams.Count} teams)");
            }

            Paths.WriteAtomic(System.IO.Path.Combine(Paths.Dir, "clubprobe.txt"), sb.ToString());
            Log.Info($"clubprobe.txt written for {club}: {mine.Count} players, {myStaff.Count} staff");
        }
        catch (Exception e) { Log.Warn("club probe: " + e.Message); }
    }
}
