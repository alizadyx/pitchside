import Foundation

/// FM27 splits every role into an In Possession (IP) and an Out of Possession (OOP) part, chosen
/// per position. Attribute lists come from the game itself: key and preferable attributes exactly as
/// FM27 highlights them on the player screen, for every IP and OOP role.
public enum Phase: String, Sendable, Hashable, Codable {
    case inPossession, outOfPossession
    public var short: String { self == .inPossession ? "IP" : "OOP" }
}

/// A tactical role scored from attributes: key attributes weigh most, then preferable ones, and every
/// other attribute a little (see `Roles.keyWeight`). The result stays on FM's 1–20 scale.
public struct Role: Sendable, Hashable, Identifiable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let phase: Phase
    public let positions: [String]       // FM position codes where the role is offered
    public let key: [String]
    public let support: [String]         // FM's "preferable" attributes

    public init(_ code: String, _ name: String, _ phase: Phase, _ positions: [String], key: [String], support: [String]) {
        self.code = code; self.name = name; self.phase = phase; self.positions = positions; self.key = key; self.support = support
    }

    /// "Winger" or "Winger (OOP)": IP and OOP lists share some names.
    public var label: String { phase == .inPossession ? name : "\(name) (OOP)" }
    public var isIP: Bool { phase == .inPossession }

    /// Compact name for table cells: "No-Nonsense CB", "Box-To-Box Mid".
    public var short: String {
        var n = name
        for (a, b) in [("Centre-Back", "CB"), ("Full-Back", "FB"), ("Wing-Back", "WB"), ("Goalkeeper", "GK"),
                       ("Defensive Midfielder", "DM"), ("Central Midfielder", "CM"), ("Attacking Midfielder", "AM"),
                       ("Wide Midfielder", "WM"), ("Midfielder", "Mid"), ("Centre Forward", "CF"), ("Forward", "Fwd")] {
            n = n.replacingOccurrences(of: a, with: b)
        }
        return n
    }
}

/// Role scores for one player, aligned with `Roles.all`. Stored as tenths in a byte each, so a
/// 500k-player database stays small (scores are already rounded to one decimal).
public struct RoleScores: Sendable, Hashable {
    let raw: [UInt8]
    public init(_ values: [Double]) { raw = values.map { UInt8(max(0, min(250, ($0 * 10).rounded()))) } }
    public subscript(_ i: Int) -> Double { i >= 0 && i < raw.count ? Double(raw[i]) / 10 : 0 }
    public var count: Int { raw.count }
    public var indices: Range<Int> { raw.indices }
}

public enum Roles {
    public static let all: [Role] = [
        Role("GK", "Goalkeeper", .inPossession, ["GK"],
             key: ["AerialReach", "CommandOfArea", "Communication", "Handling", "Reflexes", "Concentration", "Positioning", "Agility"],
             support: ["Kicking", "OneOnOnes", "Throwing", "Anticipation", "Decisions"]),
        Role("BPGK", "Ball-Playing Goalkeeper", .inPossession, ["GK"],
             key: ["AerialReach", "CommandOfArea", "Communication", "Handling", "Kicking", "Reflexes", "Concentration", "Positioning", "Agility"],
             support: ["Eccentricity", "OneOnOnes", "Passing", "Throwing", "Anticipation", "Composure", "Decisions"]),
        Role("NNGK", "No-Nonsense Goalkeeper", .inPossession, ["GK"],
             key: ["AerialReach", "CommandOfArea", "Communication", "Handling", "Reflexes", "Concentration", "Positioning", "Agility"],
             support: ["OneOnOnes", "Anticipation", "Decisions"]),
        Role("CB", "Centre-Back", .inPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Positioning", "JumpingReach", "Strength"],
             support: ["Aggression", "Bravery", "Composure", "Concentration", "Decisions", "Pace"]),
        Role("BPCB", "Ball-Playing Centre-Back", .inPossession, ["DC"],
             key: ["Heading", "Marking", "Passing", "Tackling", "Anticipation", "Composure", "Positioning", "JumpingReach", "Strength"],
             support: ["FirstTouch", "Technique", "Aggression", "Bravery", "Concentration", "Decisions", "Vision", "Pace"]),
        Role("ACB", "Advanced Centre-Back", .inPossession, ["DC"],
             key: ["Heading", "Marking", "Passing", "Tackling", "Technique", "Anticipation", "Composure", "Decisions", "Positioning", "Teamwork", "JumpingReach", "Strength"],
             support: ["Dribbling", "FirstTouch", "Aggression", "Bravery", "Concentration", "Vision", "Pace", "Stamina"]),
        Role("NNCB", "No-Nonsense Centre-Back", .inPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Positioning", "JumpingReach", "Strength"],
             support: ["Aggression", "Bravery", "Concentration", "Pace"]),
        Role("WCB", "Wide Centre-Back", .inPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Positioning", "JumpingReach", "Strength"],
             support: ["Dribbling", "Aggression", "Bravery", "Composure", "Concentration", "Decisions", "WorkRate", "Acceleration", "Agility", "Pace", "Stamina"]),
        Role("OCB", "Overlapping Centre-Back", .inPossession, ["DC"],
             key: ["Crossing", "Heading", "Marking", "Tackling", "Anticipation", "WorkRate", "JumpingReach", "Pace", "Stamina", "Strength"],
             support: ["Dribbling", "Technique", "Aggression", "Bravery", "Composure", "Concentration", "Decisions", "OffTheBall", "Positioning", "Acceleration", "Agility"]),
        Role("FB", "Full-Back", .inPossession, ["DL", "DR"],
             key: ["Marking", "Tackling", "Anticipation", "Concentration", "Positioning", "Teamwork", "Acceleration"],
             support: ["Crossing", "Dribbling", "Passing", "Technique", "Decisions", "WorkRate", "Agility", "Pace", "Stamina"]),
        Role("IFB", "Inside Full-Back", .inPossession, ["DL", "DR"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Positioning", "Strength"],
             support: ["Dribbling", "Aggression", "Bravery", "Composure", "Concentration", "Decisions", "WorkRate", "Acceleration", "Agility", "JumpingReach", "Pace", "Stamina"]),
        Role("WB", "Wing-Back", .inPossession, ["DL", "DR", "WBL", "WBR"],
             key: ["Crossing", "Marking", "Tackling", "Teamwork", "WorkRate", "Acceleration", "Pace", "Stamina"],
             support: ["Dribbling", "FirstTouch", "Passing", "Technique", "Anticipation", "Concentration", "Decisions", "OffTheBall", "Positioning", "Agility", "Balance"]),
        Role("IWB", "Inside Wing-Back", .inPossession, ["DL", "DR", "WBL", "WBR"],
             key: ["Passing", "Tackling", "Anticipation", "Composure", "Decisions", "Positioning", "Teamwork", "Acceleration"],
             support: ["FirstTouch", "Marking", "Technique", "Concentration", "WorkRate", "Agility", "Pace", "Stamina"]),
        Role("PWB", "Playmaking Wing-Back", .inPossession, ["DL", "DR", "WBL", "WBR"],
             key: ["FirstTouch", "Passing", "Tackling", "Technique", "Composure", "Decisions", "Teamwork", "Vision", "Acceleration"],
             support: ["Crossing", "Dribbling", "Marking", "Anticipation", "Concentration", "OffTheBall", "Positioning", "WorkRate", "Agility", "Pace", "Stamina"]),
        Role("AWB", "Advanced Wing-Back", .inPossession, ["WBL", "WBR"],
             key: ["Crossing", "Dribbling", "Technique", "OffTheBall", "Teamwork", "WorkRate", "Acceleration", "Agility", "Pace", "Stamina"],
             support: ["FirstTouch", "Marking", "Passing", "Tackling", "Anticipation", "Decisions", "Flair", "Positioning", "Balance"]),
        Role("DM", "Defensive Midfielder", .inPossession, ["DM"],
             key: ["Tackling", "Anticipation", "Concentration", "Positioning", "Teamwork"],
             support: ["FirstTouch", "Marking", "Passing", "Aggression", "Composure", "Decisions", "WorkRate", "Stamina", "Strength"]),
        Role("DLP", "Deep-Lying Playmaker", .inPossession, ["DM"],
             key: ["FirstTouch", "Passing", "Technique", "Composure", "Decisions", "Teamwork", "Vision"],
             support: ["Marking", "Tackling", "Anticipation", "Concentration", "OffTheBall", "Positioning", "WorkRate", "Balance", "Stamina"]),
        Role("B2B", "Box-To-Box Midfielder", .inPossession, ["DM"],
             key: ["Passing", "Tackling", "OffTheBall", "Teamwork", "WorkRate", "Stamina"],
             support: ["Dribbling", "Finishing", "FirstTouch", "LongShots", "Technique", "Aggression", "Anticipation", "Composure", "Decisions", "Positioning", "Acceleration", "Balance", "Pace", "Strength"]),
        Role("B2BP", "Box-To-Box Playmaker", .inPossession, ["DM"],
             key: ["FirstTouch", "Passing", "Technique", "Composure", "Decisions", "OffTheBall", "Teamwork", "Vision", "WorkRate", "Stamina"],
             support: ["Dribbling", "LongShots", "Marking", "Tackling", "Anticipation", "Positioning", "Acceleration", "Agility", "Balance", "Pace"]),
        Role("HB", "Half Back", .inPossession, ["DM"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Concentration", "Positioning", "Teamwork", "JumpingReach", "Strength"],
             support: ["FirstTouch", "Passing", "Aggression", "Bravery", "Composure", "Decisions", "WorkRate", "Stamina"]),
        Role("CM", "Central Midfielder", .inPossession, ["MC"],
             key: ["FirstTouch", "Passing", "Tackling", "Decisions", "Teamwork"],
             support: ["Technique", "Anticipation", "Composure", "Concentration", "OffTheBall", "Positioning", "Vision", "WorkRate", "Stamina"]),
        Role("WCM", "Wide Central Midfielder", .inPossession, ["MC"],
             key: ["FirstTouch", "Passing", "Tackling", "Decisions", "Teamwork"],
             support: ["Crossing", "Dribbling", "Technique", "Anticipation", "Composure", "Concentration", "OffTheBall", "Positioning", "Vision", "WorkRate", "Agility", "Stamina"]),
        Role("MP", "Midfield Playmaker", .inPossession, ["MC"],
             key: ["FirstTouch", "Passing", "Technique", "Composure", "Decisions", "OffTheBall", "Teamwork", "Vision"],
             support: ["Dribbling", "Tackling", "Anticipation", "Flair", "Positioning", "WorkRate", "Agility", "Stamina"]),
        Role("CHM", "Channel Midfielder", .inPossession, ["MC", "AMC"],
             key: ["Crossing", "FirstTouch", "Passing", "Technique", "Composure", "OffTheBall", "WorkRate", "Acceleration"],
             support: ["Dribbling", "LongShots", "Anticipation", "Decisions", "Flair", "Vision", "Agility", "Pace", "Stamina"]),
        Role("AP", "Advanced Playmaker", .inPossession, ["MC", "AMC"],
             key: ["FirstTouch", "Passing", "Technique", "Composure", "Decisions", "OffTheBall", "Teamwork", "Vision"],
             support: ["Crossing", "Dribbling", "Anticipation", "Flair", "Acceleration", "Agility"]),
        Role("AM", "Attacking Midfielder", .inPossession, ["MC", "AMC"],
             key: ["FirstTouch", "LongShots", "Passing", "Technique", "Composure", "Flair", "OffTheBall"],
             support: ["Crossing", "Dribbling", "Finishing", "Anticipation", "Decisions", "Vision", "Acceleration", "Agility"]),
        Role("FR", "Free Role", .inPossession, ["AMC"],
             key: ["Dribbling", "FirstTouch", "LongShots", "Passing", "Technique", "Composure", "Flair", "OffTheBall", "Vision"],
             support: ["Crossing", "Finishing", "Anticipation", "Decisions", "Acceleration", "Agility"]),
        Role("SS", "Second Striker", .inPossession, ["AMC"],
             key: ["Finishing", "FirstTouch", "Anticipation", "Composure", "OffTheBall", "Acceleration"],
             support: ["Dribbling", "LongShots", "Passing", "Technique", "Concentration", "Decisions", "WorkRate", "Agility", "Pace", "Stamina"]),
        Role("WM", "Wide Midfielder", .inPossession, ["ML", "MR"],
             key: ["Crossing", "Passing", "Technique", "Decisions", "Teamwork", "WorkRate", "Pace", "Stamina"],
             support: ["Dribbling", "FirstTouch", "Anticipation", "Composure", "OffTheBall", "Vision", "Acceleration", "Agility"]),
        Role("W", "Winger", .inPossession, ["ML", "MR", "AML", "AMR"],
             key: ["Crossing", "Dribbling", "Technique", "Teamwork", "Acceleration", "Agility", "Pace"],
             support: ["FirstTouch", "Passing", "Anticipation", "Flair", "OffTheBall", "WorkRate", "Balance", "Stamina"]),
        Role("IW", "Inside Winger", .inPossession, ["ML", "MR", "AML", "AMR"],
             key: ["Dribbling", "FirstTouch", "Technique", "Composure", "Teamwork", "Acceleration", "Agility"],
             support: ["Crossing", "LongShots", "Passing", "Anticipation", "Flair", "OffTheBall", "Vision", "WorkRate", "Balance", "Pace", "Stamina"]),
        Role("PW", "Playmaking Winger", .inPossession, ["ML", "MR", "AML", "AMR"],
             key: ["Crossing", "Dribbling", "FirstTouch", "Passing", "Technique", "Composure", "Decisions", "OffTheBall", "Teamwork", "Vision", "Acceleration"],
             support: ["Anticipation", "Flair", "WorkRate", "Agility", "Pace", "Stamina"]),
        Role("IF", "Inside Forward", .inPossession, ["AML", "AMR"],
             key: ["Dribbling", "FirstTouch", "Technique", "Anticipation", "Composure", "OffTheBall", "Acceleration", "Agility"],
             support: ["Crossing", "Finishing", "LongShots", "Passing", "Flair", "Vision", "WorkRate", "Balance", "Pace", "Stamina"]),
        Role("WF", "Wide Forward", .inPossession, ["AML", "AMR"],
             key: ["Dribbling", "FirstTouch", "Technique", "Anticipation", "OffTheBall", "Acceleration", "Agility", "Pace"],
             support: ["Crossing", "Finishing", "Passing", "Composure", "Flair", "WorkRate", "Balance", "Stamina"]),
        Role("CF", "Centre Forward", .inPossession, ["ST"],
             key: ["Finishing", "FirstTouch", "Heading", "Technique", "Composure", "OffTheBall", "Acceleration", "Strength"],
             support: ["Dribbling", "Passing", "Anticipation", "Decisions", "Agility", "Balance", "JumpingReach", "Pace"]),
        Role("TF", "Target Forward", .inPossession, ["ST"],
             key: ["Finishing", "Heading", "Aggression", "Bravery", "Composure", "OffTheBall", "Balance", "JumpingReach", "Strength"],
             support: ["FirstTouch", "Anticipation", "Decisions", "Teamwork"]),
        Role("P", "Poacher", .inPossession, ["ST"],
             key: ["Finishing", "Heading", "Anticipation", "Composure", "Concentration", "OffTheBall", "Acceleration"],
             support: ["FirstTouch", "Technique", "Decisions", "Balance"]),
        Role("CHF", "Channel Forward", .inPossession, ["ST"],
             key: ["Dribbling", "Finishing", "FirstTouch", "Technique", "Composure", "OffTheBall", "WorkRate", "Acceleration"],
             support: ["Crossing", "Heading", "Passing", "Anticipation", "Decisions", "Agility", "Balance", "Pace", "Stamina"]),
        Role("DLF", "Deep-Lying Forward", .inPossession, ["ST"],
             key: ["Finishing", "FirstTouch", "Technique", "Composure", "OffTheBall", "Strength"],
             support: ["Dribbling", "Passing", "Anticipation", "Decisions", "Teamwork", "Vision", "Balance"]),
        Role("F9", "False Nine", .inPossession, ["ST"],
             key: ["Dribbling", "FirstTouch", "Passing", "Technique", "Composure", "Decisions", "OffTheBall", "Teamwork", "Vision", "Acceleration"],
             support: ["Finishing", "Anticipation", "Flair", "Agility", "Balance"]),
        Role("oGK", "Goalkeeper", .outOfPossession, ["GK"],
             key: ["AerialReach", "CommandOfArea", "Communication", "Handling", "Reflexes", "Concentration", "Positioning", "Agility"],
             support: ["OneOnOnes", "RushingOut", "Anticipation", "Decisions"]),
        Role("oSK", "Sweeper Keeper", .outOfPossession, ["GK"],
             key: ["AerialReach", "CommandOfArea", "Communication", "Handling", "OneOnOnes", "Reflexes", "RushingOut", "Anticipation", "Decisions", "Agility"],
             support: ["Eccentricity", "Concentration", "Positioning", "Acceleration"]),
        Role("oLK", "Line-Holding Keeper", .outOfPossession, ["GK"],
             key: ["AerialReach", "CommandOfArea", "Communication", "Handling", "Reflexes", "Concentration", "Positioning", "Agility"],
             support: ["OneOnOnes", "Anticipation", "Decisions"]),
        Role("oCB", "Centre-Back", .outOfPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Positioning", "JumpingReach", "Strength"],
             support: ["Aggression", "Bravery", "Composure", "Concentration", "Decisions", "Pace"]),
        Role("oSCB", "Stopping Centre-Back", .outOfPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Aggression", "Anticipation", "Bravery", "Positioning", "JumpingReach", "Strength"],
             support: ["Concentration", "Decisions", "Pace"]),
        Role("oCCB", "Covering Centre-Back", .outOfPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Concentration", "Decisions", "Positioning", "JumpingReach", "Pace", "Strength"],
             support: ["Bravery", "Acceleration"]),
        Role("oWCB", "Wide Centre-Back", .outOfPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Positioning", "JumpingReach", "Strength"],
             support: ["Aggression", "Bravery", "Concentration", "Decisions", "Acceleration", "Agility", "Pace"]),
        Role("oSWCB", "Stopping Wide Centre-Back", .outOfPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Aggression", "Anticipation", "Bravery", "Positioning", "JumpingReach", "Strength"],
             support: ["Concentration", "Decisions", "Acceleration", "Agility", "Pace"]),
        Role("oCWCB", "Covering Wide Centre-Back", .outOfPossession, ["DC"],
             key: ["Heading", "Marking", "Tackling", "Anticipation", "Concentration", "Decisions", "Positioning", "JumpingReach", "Pace", "Strength"],
             support: ["Bravery", "Acceleration", "Agility"]),
        Role("oFB", "Full-Back", .outOfPossession, ["DL", "DR"],
             key: ["Marking", "Tackling", "Anticipation", "Positioning", "Teamwork", "Acceleration"],
             support: ["Aggression", "Concentration", "Decisions", "WorkRate", "Agility", "Pace", "Stamina"]),
        Role("oPFB", "Pressing Full-Back", .outOfPossession, ["DL", "DR"],
             key: ["Marking", "Tackling", "Aggression", "Anticipation", "Positioning", "Teamwork", "WorkRate", "Acceleration"],
             support: ["Bravery", "Concentration", "Decisions", "Agility", "Pace", "Stamina"]),
        Role("oHFB", "Holding Full-Back", .outOfPossession, ["DL", "DR"],
             key: ["Marking", "Tackling", "Anticipation", "Concentration", "Decisions", "Positioning", "Acceleration"],
             support: ["Teamwork", "Agility", "Pace"]),
        Role("oWB", "Wing-Back", .outOfPossession, ["WBL", "WBR"],
             key: ["Marking", "Tackling", "Anticipation", "Positioning", "Teamwork", "Acceleration", "Stamina"],
             support: ["Aggression", "Concentration", "Decisions", "WorkRate", "Agility", "Pace"]),
        Role("oPWB", "Pressing Wing-Back", .outOfPossession, ["WBL", "WBR"],
             key: ["Marking", "Tackling", "Aggression", "Anticipation", "Positioning", "Teamwork", "WorkRate", "Acceleration", "Stamina"],
             support: ["Bravery", "Concentration", "Decisions", "Agility", "Pace"]),
        Role("oHWB", "Holding Wing-Back", .outOfPossession, ["WBL", "WBR"],
             key: ["Marking", "Tackling", "Anticipation", "Concentration", "Decisions", "Positioning", "Acceleration"],
             support: ["Teamwork", "Agility", "Pace", "Stamina"]),
        Role("oDM", "Defensive Midfielder", .outOfPossession, ["DM"],
             key: ["Tackling", "Anticipation", "Decisions", "Positioning", "Teamwork", "WorkRate"],
             support: ["Marking", "Aggression", "Concentration", "Stamina", "Strength"]),
        Role("oDDM", "Dropping Defensive Midfielder", .outOfPossession, ["DM"],
             key: ["Marking", "Tackling", "Anticipation", "Concentration", "Decisions", "Positioning", "Teamwork", "WorkRate", "JumpingReach", "Strength"],
             support: ["Aggression", "Stamina"]),
        Role("oPDM", "Pressing Defensive Midfielder", .outOfPossession, ["DM"],
             key: ["Tackling", "Aggression", "Anticipation", "Decisions", "Positioning", "Teamwork", "WorkRate", "Stamina"],
             support: ["Marking", "Concentration", "Pace", "Strength"]),
        Role("oSDM", "Screening Defensive Midfielder", .outOfPossession, ["DM"],
             key: ["Marking", "Tackling", "Anticipation", "Concentration", "Decisions", "Positioning"],
             support: ["Teamwork", "WorkRate", "Stamina", "Strength"]),
        Role("oWCDM", "Wide Covering Defensive Midfielder", .outOfPossession, ["DM"],
             key: ["Marking", "Tackling", "Anticipation", "Decisions", "Positioning", "Teamwork", "WorkRate", "Agility", "Stamina"],
             support: ["Aggression", "Concentration", "Pace", "Strength"]),
        Role("oCM", "Central Midfielder", .outOfPossession, ["MC"],
             key: ["Tackling", "Decisions", "Teamwork", "WorkRate"],
             support: ["Marking", "Aggression", "Anticipation", "Concentration", "Positioning", "Stamina"]),
        Role("oPCM", "Pressing Central Midfielder", .outOfPossession, ["MC"],
             key: ["Tackling", "Aggression", "Anticipation", "Decisions", "Teamwork", "WorkRate", "Stamina"],
             support: ["Marking", "Concentration", "Positioning", "Pace", "Strength"]),
        Role("oSCM", "Screening Central Midfielder", .outOfPossession, ["MC"],
             key: ["Marking", "Tackling", "Concentration", "Decisions", "Positioning"],
             support: ["Anticipation", "Teamwork", "WorkRate", "Stamina"]),
        Role("oWCCM", "Wide Covering Central Midfielder", .outOfPossession, ["MC"],
             key: ["Marking", "Tackling", "Decisions", "Teamwork", "WorkRate", "Agility", "Stamina"],
             support: ["Aggression", "Anticipation", "Concentration", "Positioning", "Pace"]),
        Role("oWM", "Wide Midfielder", .outOfPossession, ["ML", "MR"],
             key: ["Decisions", "Teamwork", "WorkRate", "Acceleration"],
             support: ["Marking", "Aggression", "Anticipation", "OffTheBall", "Agility", "Pace", "Stamina"]),
        Role("oTWM", "Tracking Wide Midfielder", .outOfPossession, ["ML", "MR"],
             key: ["Aggression", "Anticipation", "Decisions", "Teamwork", "WorkRate", "Acceleration", "Stamina"],
             support: ["Marking", "Tackling", "OffTheBall", "Positioning", "Agility", "Pace"]),
        Role("oWOWM", "Wide Outlet Wide Midfielder", .outOfPossession, ["ML", "MR"],
             key: ["Anticipation", "Concentration", "Decisions", "OffTheBall", "Teamwork", "Pace"],
             support: ["Dribbling", "FirstTouch", "Marking", "Composure", "Acceleration", "Agility"]),
        Role("oW", "Winger", .outOfPossession, ["AML", "AMR"],
             key: ["Anticipation", "Decisions", "Teamwork", "WorkRate", "Acceleration"],
             support: ["Marking", "Aggression", "OffTheBall", "Agility", "Pace", "Stamina"]),
        Role("oTW", "Tracking Winger", .outOfPossession, ["AML", "AMR"],
             key: ["Aggression", "Anticipation", "Decisions", "Teamwork", "WorkRate", "Acceleration", "Stamina"],
             support: ["Marking", "Tackling", "OffTheBall", "Positioning", "Agility", "Pace"]),
        Role("oIOW", "Inside Outlet Winger", .outOfPossession, ["AML", "AMR"],
             key: ["Anticipation", "Concentration", "Decisions", "OffTheBall", "Teamwork", "Balance"],
             support: ["Dribbling", "FirstTouch", "Marking", "Composure", "Acceleration", "Strength"]),
        Role("oWOW", "Wide Outlet Winger", .outOfPossession, ["AML", "AMR"],
             key: ["Anticipation", "Concentration", "Decisions", "OffTheBall", "Teamwork", "Pace"],
             support: ["Dribbling", "FirstTouch", "Marking", "Composure", "Acceleration", "Agility"]),
        Role("oAM", "Attacking Midfielder", .outOfPossession, ["AMC"],
             key: ["Anticipation", "Decisions", "WorkRate"],
             support: ["Marking", "Aggression", "OffTheBall", "Teamwork", "Stamina"]),
        Role("oTAM", "Tracking Attacking Midfielder", .outOfPossession, ["AMC"],
             key: ["Aggression", "Anticipation", "Decisions", "Teamwork", "WorkRate", "Stamina"],
             support: ["Marking", "OffTheBall", "Positioning"]),
        Role("oCOAM", "Central Outlet Attacking Midfielder", .outOfPossession, ["AMC"],
             key: ["Anticipation", "Concentration", "Decisions", "OffTheBall", "Teamwork", "Balance"],
             support: ["FirstTouch", "Marking", "Composure", "Strength"]),
        Role("oSOAM", "Splitting Outlet Attacking Midfielder", .outOfPossession, ["AMC"],
             key: ["Anticipation", "Concentration", "Decisions", "OffTheBall", "Teamwork", "Pace"],
             support: ["FirstTouch", "Marking", "Composure", "Acceleration"]),
        Role("oCF", "Centre Forward", .outOfPossession, ["ST"],
             key: ["Anticipation", "Decisions", "WorkRate"],
             support: ["Marking", "Aggression", "OffTheBall", "Teamwork", "Stamina"]),
        Role("oTCF", "Tracking Centre Forward", .outOfPossession, ["ST"],
             key: ["Aggression", "Anticipation", "Decisions", "Teamwork", "WorkRate", "Stamina"],
             support: ["Marking", "OffTheBall", "Positioning"]),
        Role("oCOCF", "Central Outlet Centre Forward", .outOfPossession, ["ST"],
             key: ["Anticipation", "Concentration", "Decisions", "OffTheBall", "Teamwork", "Balance"],
             support: ["FirstTouch", "Marking", "Composure", "Strength"]),
        Role("oSOCF", "Splitting Outlet Centre Forward", .outOfPossession, ["ST"],
             key: ["Anticipation", "Concentration", "Decisions", "OffTheBall", "Teamwork", "Pace"],
             support: ["FirstTouch", "Marking", "Composure", "Acceleration"]),
    ]

    public static let inPossession: [Role] = all.filter(\.isIP)
    public static let outOfPossession: [Role] = all.filter { !$0.isIP }

    public static func index(_ code: String) -> Int? { indexByCode[code] ?? indexByCode[migrate(code)] }
    static let indexByCode: [String: Int] = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.code, $0) })
    public static func role(_ code: String) -> Role? { index(code).map { all[$0] } }

    /// Roles offered at a position in one phase.
    public static func offered(at position: String, _ phase: Phase) -> [Role] {
        all.filter { $0.phase == phase && $0.positions.contains(position) }
    }

    /// Role codes from Pitchside 0.4 and earlier (FM24-style roles) → the nearest FM27 IP role.
    public static func migrate(_ code: String) -> String {
        switch code {
        case "SK": "GK"
        case "CD": "CB"
        case "BPD": "BPCB"
        case "BWM": "DM"
        case "MEZ": "CHM"
        case "AF": "CHF"
        case "TM": "TF"
        case "PF": "CF"
        default: code
        }
    }

    /// Usual OOP partner for an old single role (0.4 formations only stored one role per slot).
    public static func legacyOOP(_ code: String) -> String? {
        switch code {
        case "SK": "oSK"
        case "BWM": "oPDM"
        case "PF": "oTCF"
        default: nil
        }
    }

    /// Pre-resolved attribute indices for fast scoring of many players.
    public struct Resolved: Sendable {
        public let role: Role
        let key: [Int]
        let support: [Int]
        let other: [Int]
        public let positionIdx: [Int]
    }

    /// Attributes that count a little for every role even when FM doesn't highlight them.
    static let outfieldAttrs = ["Crossing", "Dribbling", "Finishing", "FirstTouch", "Heading", "LongShots", "Marking",
                                "Passing", "Tackling", "Technique", "Aggression", "Anticipation", "Bravery", "Composure",
                                "Concentration", "Decisions", "Determination", "Flair", "Leadership", "OffTheBall",
                                "Positioning", "Teamwork", "Vision", "WorkRate", "Acceleration", "Agility", "Balance",
                                "JumpingReach", "NaturalFitness", "Pace", "Stamina", "Strength"]
    static let keeperAttrs = ["AerialReach", "CommandOfArea", "Communication", "Eccentricity", "FirstTouch", "Handling",
                              "Kicking", "OneOnOnes", "Passing", "Punching", "Reflexes", "RushingOut", "Throwing",
                              "Aggression", "Anticipation", "Bravery", "Composure", "Concentration", "Decisions",
                              "Determination", "Flair", "Leadership", "OffTheBall", "Positioning", "Teamwork", "Vision",
                              "WorkRate", "Acceleration", "Agility", "Balance", "JumpingReach", "NaturalFitness", "Pace",
                              "Stamina", "Strength"]

    public static func resolve(attrKeys: [String], positionKeys: [String]) -> [Resolved] {
        let ai = Dictionary(uniqueKeysWithValues: attrKeys.enumerated().map { ($1, $0) })
        let pi = Dictionary(uniqueKeysWithValues: positionKeys.enumerated().map { ($1, $0) })
        return all.map { r in
            let listed = Set(r.key + r.support)
            let pool = r.positions == ["GK"] ? keeperAttrs : outfieldAttrs
            return Resolved(role: r,
                            key: r.key.compactMap { ai[$0] },
                            support: r.support.compactMap { ai[$0] },
                            other: pool.filter { !listed.contains($0) }.compactMap { ai[$0] },
                            positionIdx: r.positions.compactMap { pi[$0] })
        }
    }

    /// Weights fitted to FM27's role stars: with these, 70 of 73 star comparisons across 9 players
    /// (IP and OOP) come out in FM's order, one more is a tie at one decimal, and the two misses are near-ties.
    public static let keyWeight = 3.5
    public static let preferableWeight = 2.25
    public static let otherWeight = 0.5

    /// 1–20 score, one decimal.
    public static func score(_ r: Resolved, attrs: [UInt8]) -> Double {
        var sum = 0.0, w = 0.0
        for i in r.key where i < attrs.count { sum += keyWeight * Double(attrs[i]); w += keyWeight }
        for i in r.support where i < attrs.count { sum += preferableWeight * Double(attrs[i]); w += preferableWeight }
        for i in r.other where i < attrs.count { sum += otherWeight * Double(attrs[i]); w += otherWeight }
        guard w > 0 else { return 0 }
        return (sum / w * 10).rounded() / 10
    }
}
