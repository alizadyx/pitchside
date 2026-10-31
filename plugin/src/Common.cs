using System.Text.Json;
using System.Text.Json.Serialization;
using BepInEx.Logging;

namespace Pitchside;

internal static class Paths
{
    /// <summary>~/Library/Application Support/Pitchside — shared with the Mac viewer app.</summary>
    public static readonly string Dir = Prepare();

    /// Moves the folder used under the project's earlier name (FMScoutMac), keeping calibration and history.
    private static string Prepare()
    {
        string support = System.IO.Path.Combine(
            Environment.GetEnvironmentVariable("HOME") ?? "/tmp", "Library", "Application Support");
        string dir = System.IO.Path.Combine(support, "Pitchside");
        string old = System.IO.Path.Combine(support, "FMScoutMac");
        try { if (!Directory.Exists(dir) && Directory.Exists(old)) Directory.Move(old, dir); } catch { }
        return dir;
    }

    public static string Request => System.IO.Path.Combine(Dir, "request.json");
    public static string DumpFlag => System.IO.Path.Combine(Dir, "dump.flag");
    public static string TacticFlag => System.IO.Path.Combine(Dir, "tactics.flag");
    public static string Status => System.IO.Path.Combine(Dir, "status.json");
    public static string Export => System.IO.Path.Combine(Dir, "export.json");
    public static string Offsets => System.IO.Path.Combine(Dir, "offsets.json");
    public static string SuggestedOffsets => System.IO.Path.Combine(Dir, "offsets.suggested.json");
    public static string DiscoveryJson => System.IO.Path.Combine(Dir, "discovery-report.json");
    public static string DiscoveryTxt => System.IO.Path.Combine(Dir, "discovery-report.txt");
    public static string Log => System.IO.Path.Combine(Dir, "plugin.log");

    public static void WriteAtomic(string path, string content)
    {
        Directory.CreateDirectory(Dir);
        string tmp = path + ".tmp";
        File.WriteAllText(tmp, content);
        File.Move(tmp, path, true);
    }
}

internal static class Log
{
    public static ManualLogSource Source;
    private static readonly object Gate = new();

    private static void File(string level, string msg)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Paths.Dir);
                System.IO.File.AppendAllText(Paths.Log, $"{DateTime.Now:HH:mm:ss} [{level}] {msg}\n");
            }
        }
        catch { }
    }

    public static void Info(string m) { Source?.LogInfo(m); File("info", m); }
    public static void Warn(string m) { Source?.LogWarning(m); File("warn", m); }
    public static void Error(string m) { Source?.LogError(m); File("error", m); }
}

/// <summary>status.json — the viewer app polls this to show progress and results.</summary>
internal static class Status
{
    public static string RequestId = "";

    public static void Write(string state, double progress = -1, string message = null,
                             int players = 0, int staff = 0, string mode = null)
    {
        try
        {
            var o = new Dictionary<string, object>
            {
                ["state"] = state,                        // idle | scanning | done | error
                ["mode"] = mode ?? "",
                ["id"] = RequestId,
                ["progress"] = progress < 0 ? null : Math.Round(Math.Clamp(progress, 0, 1), 3),
                ["message"] = message,
                ["players"] = players,
                ["staff"] = staff,
                ["at"] = DateTime.Now.ToString("s"),
                ["plugin"] = Plugin.Version,
            };
            Paths.WriteAtomic(Paths.Status, JsonSerializer.Serialize(o));
        }
        catch { }
    }
}

/// <summary>Reads ints written either as numbers or as "0x1A" strings; writes hex strings.</summary>
internal sealed class HexIntConverter : JsonConverter<int>
{
    public override int Read(ref Utf8JsonReader r, Type t, JsonSerializerOptions o)
    {
        if (r.TokenType == JsonTokenType.Number) return r.GetInt32();
        string s = r.GetString()?.Trim() ?? "0";
        bool neg = s.StartsWith("-");
        if (neg) s = s.Substring(1);
        int v = s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)
            ? Convert.ToInt32(s.Substring(2), 16)
            : int.Parse(s);
        return neg ? -v : v;
    }

    public override void Write(Utf8JsonWriter w, int v, JsonSerializerOptions o)
        => w.WriteStringValue(v < 0 ? $"-0x{-v:X}" : $"0x{v:X}");
}

internal static class Json
{
    public static readonly JsonSerializerOptions Opts = new()
    {
        WriteIndented = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        PropertyNameCaseInsensitive = true,
        Converters = { new HexIntConverter() },
    };

    public static readonly JsonSerializerOptions Plain = new()
    {
        WriteIndented = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
        PropertyNameCaseInsensitive = true,
    };
}

internal static class FmDate
{
    // FM stores dates as u32: year in the high 16 bits, day-of-year (1..366) in the low 9 bits.
    public static (int year, int doy) Decode(uint raw)
    {
        int y = (int)(raw >> 16), d = (int)(raw & 0x1FF);
        return y is < 1900 or > 2100 || d is < 1 or > 366 ? (0, 0) : (y, d);
    }

    public static uint Encode(DateTime d) => ((uint)d.Year << 16) | (uint)d.DayOfYear;

    public static string Iso(uint raw)
    {
        var (y, d) = Decode(raw);
        if (y == 0 || d > (DateTime.IsLeapYear(y) ? 366 : 365)) return null;
        return new DateTime(y, 1, 1).AddDays(d - 1).ToString("yyyy-MM-dd");
    }
}
