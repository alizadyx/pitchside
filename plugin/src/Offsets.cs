using System.Text.Json;

namespace Pitchside;

/// <summary>
/// Where each field lives in FM's native objects. Loaded from offsets.json so a game patch
/// only needs a new JSON file, not a new plugin build. Defaults are the FM 26.3 (Windows)
/// layout documented by the FMSuperScout project and the Cheat Engine tables it credits;
/// they are a STARTING POINT for FM27 on Mac and must be confirmed with Discovery.
/// </summary>
internal sealed class Offsets
{
    public string Version { get; set; } = "fm26.3-windows-defaults (unverified on FM27/Mac)";
    public bool Verified { get; set; } = false;

    /// <summary>Substring of the native engine image path; empty = all non-system images.</summary>
    public string EngineImage { get; set; } = "";

    /// <summary>Unique-ID u32 inside the person sub-object.</summary>
    public int ObjUid { get; set; } = 0x0C;

    // Distance from the person sub-object back to the start of the complete C++ object.
    // Itanium "offset-to-top" (negated) of the person vtable — identifies the class.
    public List<int> PlayerOffsets { get; set; } = new() { 0x288, 0x380 };
    public List<int> StaffOffsets { get; set; } = new() { 0x100, 0x450 };
    /// <summary>Optional C++ class names (from RTTI) that must match too; empty = offset only.</summary>
    public List<string> PlayerTypes { get; set; } = new();
    public List<string> StaffTypes { get; set; } = new();

    public StringLayout Strings { get; set; } = new();
    public PersonLayout Person { get; set; } = new();
    public PlayerLayout Player { get; set; } = new();
    public StaffLayout Staff { get; set; } = new();
    public ContractLayout Contract { get; set; } = new();
    public ClubLayout Club { get; set; } = new();

    public sealed class StringLayout
    {
        public bool Nested { get; set; } = true;   // [field]→outer→inner
        public int TextOffset { get; set; } = 4;   // UTF-8 text after a 4-byte header
    }

    /// <summary>Relative to the person sub-object.</summary>
    public sealed class PersonLayout
    {
        public int FirstName { get; set; } = 0x50;
        public int SecondName { get; set; } = 0x58;
        public int CommonName { get; set; } = 0x60;
        public int Nation { get; set; } = 0x68;
        public int NationName { get; set; } = 0x30;       // inside nation object (indirect string)
        public int NationShortName { get; set; } = 0x20;
        public int Dob { get; set; } = 0x88;
        public int Contract { get; set; } = 0xA8;
        /// <summary>Direct pointer to the club object (FM27); 0 = go via contract → team.</summary>
        public int Club { get; set; } = 0;
        public int Gender { get; set; } = 0x19;
        public int GenderFemaleBit { get; set; } = 0x10;
        /// <summary>Hidden personality, raw 1..20 bytes.</summary>
        public Dictionary<string, int> Personality { get; set; } = new()
        {
            ["Adaptability"] = 0x70, ["Ambition"] = 0x71, ["Loyalty"] = 0x72, ["Pressure"] = 0x73,
            ["Professionalism"] = 0x74, ["Sportsmanship"] = 0x75, ["Temperament"] = 0x76, ["Controversy"] = 0x77,
        };
    }

    /// <summary>Relative to the START of the complete player object (person - playerOffset).</summary>
    public sealed class PlayerLayout
    {
        public int Ca { get; set; } = 0x264;
        public int Pa { get; set; } = 0x266;
        public int HomeRep { get; set; } = 0x25E;
        public int CurrentRep { get; set; } = 0x260;
        public int WorldRep { get; set; } = 0x262;
        public int Height { get; set; } = 0x22E;
        public int Positions { get; set; } = 0x150;       // 15 bytes, 1..20 familiarity
        public int Attributes { get; set; } = 0x15F;      // block base for the maps below
        public int AttributeScale { get; set; } = 5;      // stored ×5 (0..100)
        public int Value { get; set; } = 0x234;           // u32, GBP
        public int AskingPrice { get; set; } = 0x238;     // u32, GBP

        public Dictionary<string, int> AttributeMap { get; set; } = new()
        {
            ["Crossing"] = 0x00, ["Dribbling"] = 0x01, ["Finishing"] = 0x02, ["Heading"] = 0x03,
            ["LongShots"] = 0x04, ["Marking"] = 0x05, ["OffTheBall"] = 0x06, ["Passing"] = 0x07,
            ["PenaltyTaking"] = 0x08, ["Tackling"] = 0x09, ["Vision"] = 0x0A, ["Handling"] = 0x0B,
            ["AerialReach"] = 0x0C, ["CommandOfArea"] = 0x0D, ["Communication"] = 0x0E, ["Kicking"] = 0x0F,
            ["Throwing"] = 0x10, ["Anticipation"] = 0x11, ["Decisions"] = 0x12, ["OneOnOnes"] = 0x13,
            ["Positioning"] = 0x14, ["Reflexes"] = 0x15, ["FirstTouch"] = 0x16, ["Technique"] = 0x17,
            ["LeftFoot"] = 0x18, ["RightFoot"] = 0x19,
            ["Flair"] = 0x1A, ["Corners"] = 0x1B, ["Teamwork"] = 0x1C, ["WorkRate"] = 0x1D,
            ["LongThrows"] = 0x1E, ["Eccentricity"] = 0x1F, ["RushingOut"] = 0x20, ["Punching"] = 0x21,
            ["Acceleration"] = 0x22, ["FreeKicks"] = 0x23, ["Strength"] = 0x24, ["Stamina"] = 0x25,
            ["Pace"] = 0x26, ["JumpingReach"] = 0x27, ["Leadership"] = 0x28, ["Balance"] = 0x2A,
            ["Bravery"] = 0x2B, ["Aggression"] = 0x2D, ["Agility"] = 0x2E, ["NaturalFitness"] = 0x32,
            ["Determination"] = 0x33, ["Composure"] = 0x34, ["Concentration"] = 0x35,
        };

        public Dictionary<string, int> HiddenMap { get; set; } = new()
        {
            ["Dirtiness"] = 0x29, ["Consistency"] = 0x2C, ["ImportantMatches"] = 0x2F,
            ["InjuryProneness"] = 0x30, ["Versatility"] = 0x31,
        };

        public List<string> PositionKeys { get; set; } = new()
        { "GK", "SW", "DL", "DC", "DR", "DM", "ML", "MC", "MR", "AML", "AMC", "AMR", "ST", "WBL", "WBR" };
    }

    /// <summary>Relative to the START of the complete staff object (person - staffOffset).</summary>
    public sealed class StaffLayout
    {
        public int Ca { get; set; } = 0xDA;
        public int Pa { get; set; } = 0xDC;
        public int CurrentRep { get; set; } = 0xD6;
        public int WorldRep { get; set; } = 0xD8;
        public int Attributes { get; set; } = 0x10;
        public int AttributeScale { get; set; } = 5;
        /// <summary>Attributes stored as plain 1..20 instead of ×AttributeScale.</summary>
        public List<string> RawKeys { get; set; } = new();

        public Dictionary<string, int> AttributeMap { get; set; } = new()
        {
            ["Attacking"] = 0x22, ["Defending"] = 0x23, ["Fitness"] = 0x24, ["Mental"] = 0x25,
            ["Technical"] = 0x26, ["Tactical"] = 0x27, ["SetPieces"] = 0x33,
            ["Determination"] = 0x0D, ["ManManagement"] = 0x1E, ["Motivating"] = 0x1F,
            ["JudgingAbility"] = 0x1C, ["JudgingPotential"] = 0x1D, ["JudgingStaff"] = 0x32,
            ["Negotiating"] = 0x31, ["TacticalKnowledge"] = 0x21, ["Physiotherapy"] = 0x20,
            ["SportsScience"] = 0x2F, ["DataAnalysis"] = 0x2C, ["WorkingWithYoungsters"] = 0x0C,
            ["GkDistribution"] = 0x2A, ["GkHandling"] = 0x29, ["GkShotStopping"] = 0x1B,
        };
    }

    /// <summary>Inside the contract object ([person + Person.Contract]).</summary>
    public sealed class ContractLayout
    {
        public int Team { get; set; } = 0x10;
        public int WeeklyWage { get; set; } = 0x20;     // u32 GBP
        public int Expiry { get; set; } = 0x48;         // FM date
        public int Job { get; set; } = 0x26;            // byte
        public int StatusFlags { get; set; } = 0x57;    // bit0 listed, bit3 listed by request, bit4 NFS, bit5 release
    }

    public sealed class ClubLayout
    {
        public int TeamClub { get; set; } = 0x30;       // team → club
        public int TeamReputation { get; set; } = 0xA8; // u16
        public int TeamCompetition { get; set; } = 0x50;
        public int TeamSchedule { get; set; } = 0xA0;   // → schedule object (0 = off)
        public int TeamDate { get; set; } = 0;          // FM date stored directly in the team (0 = off)
        public int ScheduleNextMatch { get; set; } = 0x94; // FM date ≈ today
        public int ClubName { get; set; } = 0xC0;       // indirect string
        public int ClubShortName { get; set; } = 0xC8;
        public int CompName { get; set; } = 0x40;
        public int CompShortName { get; set; } = 0x48;
    }

    // ------------------------------------------------------------------ load/save

    public static Offsets Load()
    {
        try
        {
            if (File.Exists(Paths.Offsets))
                return JsonSerializer.Deserialize<Offsets>(File.ReadAllText(Paths.Offsets), Json.Opts) ?? new Offsets();
        }
        catch (Exception e)
        {
            Log.Error($"offsets.json unreadable ({e.Message}) — using built-in defaults.");
            return new Offsets();
        }
        var d = new Offsets();
        try { Paths.WriteAtomic(Paths.Offsets, JsonSerializer.Serialize(d, Json.Opts)); } catch { }
        return d;
    }

    public string ToJson() => JsonSerializer.Serialize(this, Json.Opts);

    public Offsets Clone() => JsonSerializer.Deserialize<Offsets>(ToJson(), Json.Opts);
}
