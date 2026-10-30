import Foundation

/// A tactical role scored from attributes. Key attributes count three times as much as
/// supporting ones; the result stays on FM's 1–20 scale.
public struct Role: Sendable, Hashable, Identifiable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let positions: [String]       // FM position codes where the role is played
    public let key: [String]
    public let support: [String]

    public init(_ code: String, _ name: String, _ positions: [String], key: [String], support: [String]) {
        self.code = code; self.name = name; self.positions = positions; self.key = key; self.support = support
    }
}

public enum Roles {
    public static let all: [Role] = [
        Role("GK", "Goalkeeper", ["GK"],
             key: ["AerialReach", "CommandOfArea", "Communication", "Handling", "Kicking", "Reflexes", "Concentration", "Positioning"],
             support: ["OneOnOnes", "Throwing", "Anticipation", "Decisions", "Agility"]),
        Role("SK", "Sweeper Keeper", ["GK"],
             key: ["CommandOfArea", "Kicking", "OneOnOnes", "Reflexes", "RushingOut", "Anticipation", "Composure", "Concentration", "Positioning"],
             support: ["AerialReach", "Handling", "Passing", "Throwing", "Decisions", "Vision", "Acceleration", "FirstTouch"]),
        Role("CD", "Central Defender", ["DC"],
             key: ["Heading", "Marking", "Tackling", "Positioning", "JumpingReach", "Strength"],
             support: ["Aggression", "Anticipation", "Bravery", "Composure", "Concentration", "Decisions", "Pace"]),
        Role("BPD", "Ball-Playing Defender", ["DC"],
             key: ["Heading", "Marking", "Passing", "Tackling", "Composure", "Positioning", "JumpingReach", "Strength"],
             support: ["FirstTouch", "Technique", "Aggression", "Anticipation", "Bravery", "Concentration", "Decisions", "Vision", "Pace"]),
        Role("FB", "Full-Back", ["DL", "DR"],
             key: ["Marking", "Tackling", "Anticipation", "Concentration", "Positioning", "Teamwork"],
             support: ["Crossing", "Passing", "Decisions", "WorkRate", "Pace", "Stamina"]),
        Role("WB", "Wing-Back", ["DL", "DR", "WBL", "WBR"],
             key: ["Crossing", "Dribbling", "Tackling", "OffTheBall", "Teamwork", "WorkRate", "Acceleration", "Stamina"],
             support: ["FirstTouch", "Marking", "Passing", "Technique", "Anticipation", "Concentration", "Decisions", "Flair", "Positioning", "Agility", "Balance", "Pace"]),
        Role("IWB", "Inverted Wing-Back", ["DL", "DR", "WBL", "WBR"],
             key: ["Passing", "Tackling", "Composure", "Decisions", "Teamwork"],
             support: ["FirstTouch", "Marking", "Technique", "Anticipation", "Concentration", "OffTheBall", "Positioning", "Vision", "WorkRate", "Acceleration", "Agility", "Stamina"]),
        Role("DM", "Defensive Midfielder", ["DM"],
             key: ["Tackling", "Anticipation", "Concentration", "Positioning", "Teamwork"],
             support: ["Marking", "Passing", "Aggression", "Composure", "Decisions", "WorkRate", "Stamina", "Strength"]),
        Role("DLP", "Deep-Lying Playmaker", ["DM", "MC"],
             key: ["FirstTouch", "Passing", "Technique", "Composure", "Decisions", "Teamwork", "Vision"],
             support: ["Anticipation", "OffTheBall", "Positioning", "Balance"]),
        Role("BWM", "Ball-Winning Midfielder", ["DM", "MC"],
             key: ["Tackling", "Aggression", "Anticipation", "Teamwork", "WorkRate", "Stamina"],
             support: ["Marking", "Bravery", "Concentration", "Positioning", "Agility", "Pace", "Strength"]),
        Role("B2B", "Box-to-Box Midfielder", ["MC"],
             key: ["Passing", "Tackling", "OffTheBall", "Teamwork", "WorkRate", "Stamina"],
             support: ["Dribbling", "FirstTouch", "LongShots", "Technique", "Aggression", "Anticipation", "Composure", "Decisions", "Positioning", "Acceleration", "Balance", "Pace", "Strength"]),
        Role("CM", "Central Midfielder", ["MC"],
             key: ["FirstTouch", "Passing", "Tackling", "Decisions", "Teamwork"],
             support: ["Technique", "Anticipation", "Composure", "Concentration", "OffTheBall", "Vision", "WorkRate", "Stamina"]),
        Role("MEZ", "Mezzala", ["MC"],
             key: ["Passing", "Technique", "Decisions", "OffTheBall", "WorkRate", "Acceleration"],
             support: ["Dribbling", "FirstTouch", "LongShots", "Anticipation", "Composure", "Vision", "Balance", "Stamina"]),
        Role("AP", "Advanced Playmaker", ["MC", "AMC", "AML", "AMR"],
             key: ["FirstTouch", "Passing", "Technique", "Composure", "Decisions", "OffTheBall", "Teamwork", "Vision"],
             support: ["Dribbling", "Anticipation", "Flair", "Agility"]),
        Role("AM", "Attacking Midfielder", ["AMC"],
             key: ["FirstTouch", "LongShots", "Passing", "Technique", "Anticipation", "Decisions", "Flair", "OffTheBall"],
             support: ["Dribbling", "Composure", "Vision", "Agility"]),
        Role("W", "Winger", ["ML", "MR", "AML", "AMR"],
             key: ["Crossing", "Dribbling", "Technique", "Acceleration", "Agility"],
             support: ["FirstTouch", "Passing", "OffTheBall", "WorkRate", "Balance", "Pace", "Stamina"]),
        Role("IF", "Inside Forward", ["AML", "AMR"],
             key: ["Dribbling", "Finishing", "FirstTouch", "Technique", "OffTheBall", "Acceleration", "Agility"],
             support: ["LongShots", "Passing", "Anticipation", "Composure", "Flair", "WorkRate", "Balance", "Pace", "Stamina"]),
        Role("IW", "Inverted Winger", ["ML", "MR", "AML", "AMR"],
             key: ["Crossing", "Dribbling", "Passing", "Technique", "Acceleration", "Agility"],
             support: ["FirstTouch", "LongShots", "Composure", "Decisions", "OffTheBall", "Vision", "WorkRate", "Balance", "Pace", "Stamina"]),
        Role("AF", "Advanced Forward", ["ST"],
             key: ["Dribbling", "Finishing", "FirstTouch", "Technique", "Composure", "OffTheBall", "Acceleration"],
             support: ["Passing", "Anticipation", "Decisions", "WorkRate", "Agility", "Balance", "Pace", "Stamina"]),
        Role("P", "Poacher", ["ST"],
             key: ["Finishing", "Anticipation", "Composure", "OffTheBall"],
             support: ["FirstTouch", "Heading", "Technique", "Decisions", "Acceleration"]),
        Role("TM", "Target Forward", ["ST"],
             key: ["Heading", "Bravery", "Teamwork", "Balance", "JumpingReach", "Strength"],
             support: ["Finishing", "FirstTouch", "Aggression", "Anticipation", "Composure", "Decisions", "OffTheBall"]),
        Role("PF", "Pressing Forward", ["ST"],
             key: ["Aggression", "Anticipation", "Bravery", "Teamwork", "WorkRate", "Acceleration", "Stamina"],
             support: ["Finishing", "FirstTouch", "Composure", "Concentration", "Decisions", "OffTheBall", "Agility", "Balance", "Pace", "Strength"]),
        Role("DLF", "Deep-Lying Forward", ["ST"],
             key: ["FirstTouch", "Passing", "Technique", "Composure", "Decisions", "OffTheBall", "Teamwork"],
             support: ["Finishing", "Anticipation", "Flair", "Vision", "Balance", "Strength"]),
    ]

    /// Pre-resolved attribute indices for fast scoring of many players.
    public struct Resolved: Sendable {
        public let role: Role
        let key: [Int]
        let support: [Int]
        public let positionIdx: [Int]
    }

    public static func resolve(attrKeys: [String], positionKeys: [String]) -> [Resolved] {
        let ai = Dictionary(uniqueKeysWithValues: attrKeys.enumerated().map { ($1, $0) })
        let pi = Dictionary(uniqueKeysWithValues: positionKeys.enumerated().map { ($1, $0) })
        return all.map { r in
            Resolved(role: r,
                     key: r.key.compactMap { ai[$0] },
                     support: r.support.compactMap { ai[$0] },
                     positionIdx: r.positions.compactMap { pi[$0] })
        }
    }

    /// 1–20 score, one decimal.
    public static func score(_ r: Resolved, attrs: [UInt8]) -> Double {
        var sum = 0.0, w = 0.0
        for i in r.key where i < attrs.count { sum += 3 * Double(attrs[i]); w += 3 }
        for i in r.support where i < attrs.count { sum += Double(attrs[i]); w += 1 }
        guard w > 0 else { return 0 }
        return (sum / w * 10).rounded() / 10
    }
}
