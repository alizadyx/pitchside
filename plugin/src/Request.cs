namespace Pitchside;

/// <summary>request.json written by the viewer app (or by hand) to start a job.</summary>
internal sealed class Request
{
    public string Mode { get; set; } = "dump";        // "dump" | "discover"
    public string Id { get; set; } = "";
    public long At { get; set; }                       // ms since epoch; stale requests are ignored
    public string Database { get; set; } = "men";     // men | women | both
    public List<Target> Targets { get; set; } = new();
    /// <summary>Optional: also write clubprobe.txt for this club (teams, contracts, staff, date candidates).</summary>
    public string Club { get; set; }
}

/// <summary>A person you can see in-game, used to locate fields in memory.</summary>
internal sealed class Target
{
    public string Name { get; set; } = "";
    public string Kind { get; set; } = "player";       // player | staff
    /// <summary>Attribute values as shown in game (1..20), keys as in offsets.json maps.</summary>
    public Dictionary<string, int> Attributes { get; set; } = new();
    public string BirthDate { get; set; }              // yyyy-MM-dd, optional
    public int HeightCm { get; set; }                  // optional
}
