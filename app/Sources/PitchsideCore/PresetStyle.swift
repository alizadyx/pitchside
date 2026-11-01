import Foundation

/// How well an XI's attribute profile suits a tactical style: each non-neutral team instruction asks
/// something of some players (a high press needs running, a high line needs quick defenders, short
/// passing needs touch and composure…). Each player is measured against his own average, so this is
/// about what the squad leans towards, not how good it is (the role scores cover that).
/// 0 = neutral, +2 = those attributes are two points above the players' usual level.
public enum PresetStyle {
    public struct Demand: Sendable, Identifiable {
        public var id: String { label + group }
        public let label: String        // "Line of Engagement: High Press"
        public let group: String        // who it applies to, e.g. "Outfield", "Defenders"
        public let attributes: [String]
        public let weight: Double
        public let score: Double        // XI average of (weighted attributes − player's own average)
    }
    public struct Result: Sendable {
        public let score: Double        // weighted average of the demands
        public let demands: [Demand]    // heaviest first
    }

    enum Group: String {
        case gk = "Goalkeeper", def = "Defenders", cb = "Centre-backs", fb = "Full-backs", mid = "Midfielders",
             wide = "Wide players", att = "Attackers", st = "Strikers", out = "Outfield", cmid = "Central midfield & attack"
        func contains(_ pos: String) -> Bool {
            switch self {
            case .gk: pos == "GK"
            case .cb: pos == "DC"
            case .fb: ["DL", "DR", "WBL", "WBR"].contains(pos)
            case .def: pos == "DC" || ["DL", "DR", "WBL", "WBR"].contains(pos)
            case .mid: pos == "DM" || pos == "MC"
            case .wide: ["ML", "MR", "AML", "AMR", "WBL", "WBR"].contains(pos)
            case .att: ["ML", "MR", "AML", "AMR", "AMC", "ST"].contains(pos)
            case .st: pos == "ST"
            case .out: pos != "GK"
            case .cmid: ["DM", "MC", "AMC", "ST"].contains(pos)
            }
        }
    }

    struct Rule {
        let phase: String, setting: String, values: [String]
        let group: Group, attrs: [(String, Double)], weight: Double
    }

    /// Instruction → what it asks of whom. Values match by prefix-free containment ("More Often" also
    /// matches "Much More Often", which weighs 1.5×).
    static let rules: [Rule] = [
        // In possession
        Rule(phase: "IP", setting: "Passing Directness", values: ["Shorter"], group: .out,
             attrs: [("Passing", 2), ("FirstTouch", 1.5), ("Composure", 1.5), ("Technique", 1), ("Decisions", 1)], weight: 1),
        Rule(phase: "IP", setting: "Passing Directness", values: ["Direct"], group: .mid,
             attrs: [("Passing", 1.5), ("Vision", 1.5), ("Decisions", 1)], weight: 0.7),
        Rule(phase: "IP", setting: "Passing Directness", values: ["Direct"], group: .att,
             attrs: [("OffTheBall", 1.5), ("Pace", 1.5), ("Acceleration", 1)], weight: 0.7),
        Rule(phase: "IP", setting: "Tempo", values: ["Higher"], group: .out,
             attrs: [("Decisions", 1.5), ("Passing", 1), ("FirstTouch", 1), ("Anticipation", 1), ("Technique", 1)], weight: 0.8),
        Rule(phase: "IP", setting: "Tempo", values: ["Lower"], group: .out,
             attrs: [("Composure", 1.5), ("Decisions", 1), ("Passing", 1), ("Concentration", 0.5)], weight: 0.7),
        Rule(phase: "IP", setting: "Attacking Width", values: ["Wider"], group: .wide,
             attrs: [("Crossing", 2), ("Pace", 1.5), ("Acceleration", 1), ("Dribbling", 1), ("Stamina", 1)], weight: 1),
        Rule(phase: "IP", setting: "Attacking Width", values: ["Narrower"], group: .cmid,
             attrs: [("Passing", 1), ("FirstTouch", 1), ("Technique", 1), ("Agility", 1), ("Balance", 0.5)], weight: 0.7),
        Rule(phase: "IP", setting: "Attacking Transition", values: ["Counter"], group: .att,
             attrs: [("Pace", 2), ("Acceleration", 2), ("OffTheBall", 1.5), ("Dribbling", 1)], weight: 1),
        Rule(phase: "IP", setting: "Attacking Transition", values: ["Hold Shape"], group: .out,
             attrs: [("Composure", 1.5), ("Teamwork", 1), ("Decisions", 1)], weight: 0.6),
        Rule(phase: "IP", setting: "Creative Freedom", values: ["Expressive"], group: .att,
             attrs: [("Flair", 2), ("Vision", 1.5), ("Technique", 1)], weight: 0.8),
        Rule(phase: "IP", setting: "Creative Freedom", values: ["Disciplined"], group: .out,
             attrs: [("Teamwork", 1.5), ("Decisions", 1), ("Concentration", 1)], weight: 0.6),
        Rule(phase: "IP", setting: "Patience", values: ["Work Ball Into Box"], group: .att,
             attrs: [("Passing", 1), ("FirstTouch", 1), ("Technique", 1), ("Composure", 1)], weight: 0.6),
        Rule(phase: "IP", setting: "Patience", values: ["Early Crosses"], group: .wide, attrs: [("Crossing", 2)], weight: 0.7),
        Rule(phase: "IP", setting: "Crossing Style", values: ["Floated", "Whipped"], group: .st,
             attrs: [("Heading", 2), ("JumpingReach", 1.5), ("Strength", 1)], weight: 0.6),
        Rule(phase: "IP", setting: "Crossing Style", values: ["Low"], group: .st,
             attrs: [("Finishing", 1.5), ("OffTheBall", 1.5), ("Anticipation", 1)], weight: 0.6),
        Rule(phase: "IP", setting: "Shots from Distance", values: ["Shoot On Sight"], group: .cmid, attrs: [("LongShots", 2)], weight: 0.6),
        Rule(phase: "IP", setting: "Dribbling", values: ["Run At", "Encourage"], group: .att,
             attrs: [("Dribbling", 2), ("Agility", 1), ("Balance", 1), ("Flair", 0.5)], weight: 0.6),
        Rule(phase: "IP", setting: "Pass Reception", values: ["Into Space"], group: .att,
             attrs: [("Pace", 1.5), ("Acceleration", 1.5), ("OffTheBall", 1.5)], weight: 0.6),
        Rule(phase: "IP", setting: "Pass Reception", values: ["Into Feet"], group: .att,
             attrs: [("FirstTouch", 1.5), ("Technique", 1), ("Strength", 1)], weight: 0.6),
        Rule(phase: "IP", setting: "Play for Set Pieces", values: ["Play For Set Pieces"], group: .def,
             attrs: [("Heading", 1.5), ("JumpingReach", 1.5), ("Strength", 1)], weight: 0.5),
        Rule(phase: "IP", setting: "Time Wasting", values: ["More Often"], group: .out,
             attrs: [("Composure", 1), ("Concentration", 1)], weight: 0.3),
        Rule(phase: "IP", setting: "Supporting Runs", values: ["Overlap"], group: .fb,
             attrs: [("Stamina", 1.5), ("Crossing", 1.5), ("OffTheBall", 1)], weight: 0.6),
        Rule(phase: "IP", setting: "Build-Up Strategy", values: ["Play Through Press"], group: .def,
             attrs: [("Composure", 2), ("Passing", 1.5), ("FirstTouch", 1), ("Technique", 1)], weight: 0.9),
        Rule(phase: "IP", setting: "Build-Up Strategy", values: ["Bypass"], group: .st,
             attrs: [("Heading", 1.5), ("Strength", 1.5), ("JumpingReach", 1)], weight: 0.7),
        Rule(phase: "IP", setting: "Goal Kicks", values: ["Short"], group: .gk,
             attrs: [("Passing", 1.5), ("Composure", 1.5), ("FirstTouch", 1)], weight: 0.5),
        Rule(phase: "IP", setting: "Goal Kicks", values: ["Long"], group: .st,
             attrs: [("Heading", 1.5), ("JumpingReach", 1.5), ("Strength", 1.5)], weight: 0.6),
        // Out of possession
        Rule(phase: "OOP", setting: "Line of Engagement", values: ["High"], group: .out,
             attrs: [("WorkRate", 2), ("Stamina", 1.5), ("Aggression", 1), ("Acceleration", 1), ("Teamwork", 1)], weight: 1.2),
        Rule(phase: "OOP", setting: "Line of Engagement", values: ["Mid"], group: .out,
             attrs: [("Teamwork", 1), ("Positioning", 1), ("WorkRate", 1)], weight: 0.5),
        Rule(phase: "OOP", setting: "Line of Engagement", values: ["Low"], group: .def,
             attrs: [("Positioning", 2), ("Marking", 1.5), ("Concentration", 1.5), ("Heading", 1), ("Strength", 1)], weight: 1.2),
        Rule(phase: "OOP", setting: "Defensive Line", values: ["Higher"], group: .def,
             attrs: [("Pace", 2), ("Acceleration", 1.5), ("Anticipation", 1.5), ("Positioning", 1)], weight: 1),
        Rule(phase: "OOP", setting: "Defensive Line", values: ["Deeper", "Lower"], group: .cb,
             attrs: [("Heading", 1.5), ("JumpingReach", 1.5), ("Positioning", 1.5), ("Strength", 1), ("Marking", 1)], weight: 1),
        Rule(phase: "OOP", setting: "Defensive Line Behaviour", values: ["Step Up"], group: .def,
             attrs: [("Anticipation", 1.5), ("Concentration", 1), ("Teamwork", 1), ("Decisions", 1)], weight: 0.6),
        Rule(phase: "OOP", setting: "Defensive Line Behaviour", values: ["Drop Off"], group: .def,
             attrs: [("Positioning", 1.5), ("Concentration", 1)], weight: 0.6),
        Rule(phase: "OOP", setting: "Trigger Press", values: ["More Often"], group: .out,
             attrs: [("WorkRate", 2), ("Stamina", 1.5), ("Aggression", 1.5), ("Acceleration", 1), ("Anticipation", 1)], weight: 1),
        Rule(phase: "OOP", setting: "Trigger Press", values: ["Less Often"], group: .out,
             attrs: [("Positioning", 1.5), ("Concentration", 1), ("Teamwork", 1)], weight: 0.7),
        Rule(phase: "OOP", setting: "Defensive Transition", values: ["Counter-Press"], group: .out,
             attrs: [("WorkRate", 1.5), ("Stamina", 1), ("Aggression", 1), ("Acceleration", 1), ("Teamwork", 1)], weight: 0.8),
        Rule(phase: "OOP", setting: "Defensive Transition", values: ["Regroup"], group: .out,
             attrs: [("Teamwork", 1.5), ("Positioning", 1), ("Concentration", 1)], weight: 0.6),
        Rule(phase: "OOP", setting: "Tackling", values: ["Get Stuck In"], group: .out,
             attrs: [("Tackling", 2), ("Aggression", 1), ("Bravery", 1)], weight: 0.6),
        Rule(phase: "OOP", setting: "Tackling", values: ["Stay On Feet"], group: .def,
             attrs: [("Tackling", 1), ("Positioning", 1), ("Concentration", 1)], weight: 0.5),
        Rule(phase: "OOP", setting: "Cross Engagement", values: ["Stop"], group: .wide,
             attrs: [("WorkRate", 1), ("Marking", 1), ("Tackling", 1)], weight: 0.5),
        Rule(phase: "OOP", setting: "Cross Engagement", values: ["Invite"], group: .cb,
             attrs: [("Heading", 1.5), ("JumpingReach", 1.5), ("Positioning", 1)], weight: 0.5),
        Rule(phase: "OOP", setting: "Short Goalkeeper Distribution", values: ["Yes"], group: .att,
             attrs: [("WorkRate", 1.5), ("Stamina", 1), ("Acceleration", 1)], weight: 0.4),
    ]

    static func strength(_ value: String) -> Double { value.hasPrefix("Much") ? 1.5 : 1 }

    static let goalkeeping: Set<String> = ["Handling", "AerialReach", "CommandOfArea", "Communication", "Kicking", "Throwing",
                                           "OneOnOnes", "Reflexes", "RushingOut", "Punching", "Eccentricity"]
    static let notAbility: Set<String> = ["LeftFoot", "RightFoot"]

    /// A player's usual attribute level: outfield attributes for outfielders, everything but feet for keepers.
    static func baseline(_ r: PlayerRow, keeper: Bool, meta: ExportMeta, reader R: TacticsAdvisor.Reader) -> Double {
        let keys = meta.playerAttrKeys.filter { !notAbility.contains($0) && (keeper || !goalkeeping.contains($0)) }
        guard !keys.isEmpty else { return 10 }
        return keys.reduce(0) { $0 + R.attr(r, $1) } / Double(keys.count)
    }

    /// `xi`: each player with the position he plays in possession.
    public static func evaluate(_ style: FMStyle, xi: [(PlayerRow, String)], meta: ExportMeta) -> Result {
        let R = TacticsAdvisor.Reader(meta)
        var base = [UInt32: Double]()
        for (r, pos) in xi { base[r.id] = baseline(r, keeper: pos == "GK", meta: meta, reader: R) }
        var demands: [Demand] = []
        var seen = Set<String>()
        for row in style.instructions {
            let (phase, setting, value) = (row[0], row[2], row[3])
            for rule in rules where rule.phase == phase && rule.setting == setting && rule.values.contains(where: value.contains) {
                let key = "\(setting)|\(rule.group.rawValue)"
                guard seen.insert(key).inserted else { continue }      // settings repeated under sub-phases
                let players = xi.filter { rule.group.contains($0.1) }.map(\.0)
                guard !players.isEmpty else { continue }
                let score = players.map { R.mix($0, rule.attrs) - (base[$0.id] ?? 10) }.reduce(0, +) / Double(players.count)
                demands.append(Demand(label: "\(setting): \(value)", group: rule.group.rawValue,
                                      attributes: rule.attrs.map(\.0), weight: rule.weight * strength(value), score: score))
            }
        }
        let total = demands.reduce(0) { $0 + $1.weight }
        let score = total > 0 ? demands.reduce(0) { $0 + $1.score * $1.weight } / total : 0
        return Result(score: score, demands: demands.sorted { $0.weight > $1.weight })
    }
}
