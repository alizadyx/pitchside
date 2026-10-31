import Foundation

// MARK: - Formations

/// One position in a formation: where it is played and the FM27 In Possession and
/// Out of Possession roles asked of it.
public struct Slot: Sendable, Hashable, Identifiable, Codable {
    public var id: String { label }
    public var label: String      // "LB", "LCB", … (unique within a formation)
    public var position: String   // FM position code used for familiarity
    public var role: String       // IP role code (Roles.all)
    public var oop: String        // OOP role code (Roles.all); "" = judge on the IP role only

    public init(_ label: String, _ position: String, _ role: String, _ oop: String? = nil) {
        self.label = label; self.position = position; self.role = role
        self.oop = oop ?? Formations.defaultOOP(for: position)
    }

    enum CodingKeys: String, CodingKey { case label, position, role, oop }

    /// Formations saved by 0.4 and earlier have FM24-style role codes and no OOP role.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        position = try c.decode(String.self, forKey: .position)
        let old = try c.decode(String.self, forKey: .role)
        role = Roles.migrate(old)
        if Roles.role(role)?.isIP != true { role = Formations.defaultRole(for: position) }
        oop = try c.decodeIfPresent(String.self, forKey: .oop)
            ?? Roles.legacyOOP(old) ?? Formations.defaultOOP(for: position)
    }
}

public struct Formation: Sendable, Hashable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var slots: [Slot]
    /// Your chosen mentality, tactical style and team instructions (FM27 names); nil/empty = not set.
    public var mentality: String?
    public var style: String?
    public var instructions: [String: String]?
    public init(name: String, slots: [Slot]) { self.name = name; self.slots = slots }
}

public enum Formations {
    /// Positions a slot can be set to, roughly from goal to attack.
    public static let positions = ["GK", "DL", "DC", "DR", "WBL", "DM", "WBR", "ML", "MC", "MR", "AML", "AMC", "AMR", "ST"]

    public static func positionName(_ p: String) -> String {
        switch p {
        case "GK": "Goalkeeper"
        case "DL": "Left back"
        case "DC": "Centre back"
        case "DR": "Right back"
        case "WBL": "Left wing-back"
        case "DM": "Defensive midfield"
        case "WBR": "Right wing-back"
        case "ML": "Left midfield"
        case "MC": "Central midfield"
        case "MR": "Right midfield"
        case "AML": "Left winger"
        case "AMC": "Attacking midfield"
        case "AMR": "Right winger"
        case "ST": "Striker"
        default: p
        }
    }

    static let defaultRole: [String: String] = [
        "GK": "GK", "DL": "FB", "DR": "FB", "DC": "CB", "WBL": "WB", "WBR": "WB", "DM": "DM",
        "ML": "WM", "MR": "WM", "MC": "CM", "AML": "W", "AMR": "W", "AMC": "AM", "ST": "CF",
    ]
    static let defaultOOP: [String: String] = [
        "GK": "oGK", "DL": "oFB", "DR": "oFB", "DC": "oCB", "WBL": "oWB", "WBR": "oWB", "DM": "oDM",
        "ML": "oWM", "MR": "oWM", "MC": "oCM", "AML": "oW", "AMR": "oW", "AMC": "oAM", "ST": "oCF",
    ]

    /// In Possession roles FM offers at a position.
    public static func roles(for position: String) -> [Role] { Roles.offered(at: position, .inPossession) }
    /// Out of Possession roles FM offers at a position.
    public static func oopRoles(for position: String) -> [Role] { Roles.offered(at: position, .outOfPossession) }

    public static func defaultRole(for position: String) -> String {
        defaultRole[position] ?? roles(for: position).first?.code ?? "CM"
    }
    public static func defaultOOP(for position: String) -> String {
        defaultOOP[position] ?? oopRoles(for: position).first?.code ?? ""
    }

    static let shortLabel: [String: String] = [
        "GK": "GK", "DL": "LB", "DR": "RB", "DC": "CB", "WBL": "LWB", "WBR": "RWB", "DM": "DM",
        "ML": "LM", "MR": "RM", "MC": "CM", "AML": "LW", "AMR": "RW", "AMC": "AM", "ST": "ST",
    ]

    /// Gives every slot a readable, unique label ("LCB", "CB", "RCB", …), keeping the order of the slots.
    public static func relabel(_ slots: [Slot]) -> [Slot] {
        var out = slots
        let groups = Dictionary(grouping: slots.indices, by: { slots[$0].position })
        for (pos, idx) in groups {
            let base = shortLabel[pos] ?? pos
            let names: [String]
            switch idx.count {
            case 1: names = [base]
            case 2: names = ["L" + base, "R" + base]
            case 3: names = ["L" + base, base, "R" + base]
            default: names = (1...idx.count).map { "\(base)\($0)" }
            }
            for (k, i) in idx.enumerated() { out[i].label = names[k] }
        }
        return out
    }

    /// Adds a slot at `position` with its usual role; returns the new formation and the new slot's index.
    public static func adding(_ position: String, to f: Formation) -> (Formation, Int) {
        var f = f
        f.slots.append(Slot("", position, defaultRole(for: position)))
        f.slots = relabel(f.slots)
        return (f, f.slots.count - 1)
    }

    /// Moves a slot to another position, keeping its role when it is still a natural fit there.
    public static func moving(_ index: Int, to position: String, in f: Formation) -> Formation {
        var f = f
        guard f.slots.indices.contains(index) else { return f }
        f.slots[index].position = position
        if !roles(for: position).contains(where: { $0.code == f.slots[index].role }) {
            f.slots[index].role = defaultRole(for: position)
        }
        if !oopRoles(for: position).contains(where: { $0.code == f.slots[index].oop }) {
            f.slots[index].oop = defaultOOP(for: position)
        }
        f.slots = relabel(f.slots)
        return f
    }

    /// Common FM27 shapes with sensible starting roles (IP, OOP). Every slot can be changed.
    public static let all: [Formation] = [
        Formation(name: "4-3-3", slots: back4 + [
            Slot("DM", "DM", "DM", "oSDM"), Slot("LCM", "MC", "CHM", "oPCM"), Slot("RCM", "MC", "MP", "oCM"),
            Slot("LW", "AML", "IF", "oW"), Slot("RW", "AMR", "IF", "oW"), Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "4-2-3-1", slots: back4 + [
            Slot("LDM", "DM", "DLP", "oDM"), Slot("RDM", "DM", "B2B", "oPDM"),
            Slot("LW", "AML", "W", "oTW"), Slot("AM", "AMC", "AP", "oAM"), Slot("RW", "AMR", "IF", "oW"),
            Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "4-2-3-1 Wide", slots: back4 + [
            Slot("LCM", "MC", "CM", "oCM"), Slot("RCM", "MC", "MP", "oSCM"),
            Slot("LW", "AML", "W", "oTW"), Slot("AM", "AMC", "AP", "oAM"), Slot("RW", "AMR", "IF", "oW"),
            Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "4-4-2", slots: back4 + [
            Slot("LM", "ML", "W", "oWM"), Slot("LCM", "MC", "CM", "oPCM"), Slot("RCM", "MC", "MP", "oCM"),
            Slot("RM", "MR", "WM", "oTWM"), Slot("LST", "ST", "CHF", "oCF"), Slot("RST", "ST", "TF", "oCOCF"),
        ]),
        Formation(name: "4-4-1-1", slots: back4 + [
            Slot("LM", "ML", "W", "oWM"), Slot("LCM", "MC", "CM", "oPCM"), Slot("RCM", "MC", "MP", "oCM"),
            Slot("RM", "MR", "WM", "oTWM"), Slot("AM", "AMC", "SS", "oTAM"), Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "4-1-4-1", slots: back4 + [
            Slot("DM", "DM", "DM", "oSDM"), Slot("LM", "ML", "W", "oTWM"), Slot("LCM", "MC", "CHM", "oPCM"),
            Slot("RCM", "MC", "MP", "oCM"), Slot("RM", "MR", "IW", "oWM"), Slot("ST", "ST", "CF", "oTCF"),
        ]),
        Formation(name: "4-4-2 Diamond", slots: back4 + [
            Slot("DM", "DM", "DM", "oSDM"), Slot("LCM", "MC", "CHM", "oPCM"), Slot("RCM", "MC", "CM", "oCM"),
            Slot("AM", "AMC", "AP", "oAM"), Slot("LST", "ST", "CF", "oCF"), Slot("RST", "ST", "P", "oCOCF"),
        ]),
        Formation(name: "4-3-1-2", slots: back4 + [
            Slot("LCM", "MC", "CHM", "oPCM"), Slot("CM", "MC", "CM", "oSCM"), Slot("RCM", "MC", "MP", "oCM"),
            Slot("AM", "AMC", "AP", "oAM"), Slot("LST", "ST", "CF", "oCF"), Slot("RST", "ST", "CHF", "oCOCF"),
        ]),
        Formation(name: "3-5-2", slots: back3 + [
            Slot("LWB", "WBL", "WB", "oWB"), Slot("RWB", "WBR", "WB", "oWB"), Slot("DM", "DM", "DLP", "oSDM"),
            Slot("LCM", "MC", "CHM", "oPCM"), Slot("RCM", "MC", "AP", "oCM"),
            Slot("LST", "ST", "CF", "oCF"), Slot("RST", "ST", "CHF", "oTCF"),
        ]),
        Formation(name: "3-4-3", slots: back3 + [
            Slot("LM", "ML", "WM", "oWM"), Slot("LCM", "MC", "CM", "oPCM"), Slot("RCM", "MC", "MP", "oCM"),
            Slot("RM", "MR", "WM", "oWM"), Slot("LW", "AML", "IF", "oW"), Slot("RW", "AMR", "IF", "oW"),
            Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "5-3-2", slots: back3 + [
            Slot("LWB", "WBL", "WB", "oHWB"), Slot("RWB", "WBR", "WB", "oHWB"),
            Slot("LCM", "MC", "CM", "oSCM"), Slot("CM", "MC", "MP", "oCM"), Slot("RCM", "MC", "CHM", "oPCM"),
            Slot("LST", "ST", "CF", "oCF"), Slot("RST", "ST", "CHF", "oCOCF"),
        ]),
    ]

    /// More FM27 shapes, kept separate so the common ones stay at the top of the list.
    public static let more: [Formation] = [
        Formation(name: "4-5-1", slots: back4 + [
            Slot("LM", "ML", "WM", "oTWM"), Slot("LCM", "MC", "CM", "oSCM"), Slot("CM", "MC", "MP", "oCM"),
            Slot("RCM", "MC", "CHM", "oPCM"), Slot("RM", "MR", "WM", "oTWM"), Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "4-2-4", slots: back4 + [
            Slot("LCM", "MC", "CM", "oCM"), Slot("RCM", "MC", "MP", "oSCM"), Slot("LW", "AML", "W", "oW"),
            Slot("RW", "AMR", "IF", "oW"), Slot("LST", "ST", "CF", "oCF"), Slot("RST", "ST", "P", "oCOCF"),
        ]),
        Formation(name: "4-2-2-2", slots: back4 + [
            Slot("LDM", "DM", "DLP", "oDM"), Slot("RDM", "DM", "B2B", "oPDM"), Slot("LAM", "AMC", "AP", "oAM"),
            Slot("RAM", "AMC", "SS", "oTAM"), Slot("LST", "ST", "CF", "oCF"), Slot("RST", "ST", "CHF", "oCOCF"),
        ]),
        Formation(name: "4-4-2 DM", slots: back4 + [
            Slot("LDM", "DM", "DLP", "oDM"), Slot("RDM", "DM", "B2B", "oPDM"), Slot("LM", "ML", "W", "oWM"),
            Slot("RM", "MR", "WM", "oTWM"), Slot("LST", "ST", "CF", "oCF"), Slot("RST", "ST", "TF", "oCOCF"),
        ]),
        Formation(name: "4-3-2-1", slots: back4 + [
            Slot("LCM", "MC", "CHM", "oPCM"), Slot("CM", "MC", "CM", "oSCM"), Slot("RCM", "MC", "MP", "oCM"),
            Slot("LAM", "AMC", "AP", "oAM"), Slot("RAM", "AMC", "SS", "oTAM"), Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "4-1-2-3", slots: back4 + [
            Slot("DM", "DM", "HB", "oDDM"), Slot("LCM", "MC", "CHM", "oPCM"), Slot("RCM", "MC", "AP", "oCM"),
            Slot("LW", "AML", "IF", "oTW"), Slot("RW", "AMR", "IF", "oW"), Slot("ST", "ST", "F9", "oCF"),
        ]),
        Formation(name: "4-2-1-3", slots: back4 + [
            Slot("LDM", "DM", "DLP", "oDM"), Slot("RDM", "DM", "B2B", "oPDM"), Slot("AM", "AMC", "AP", "oAM"),
            Slot("LW", "AML", "IF", "oW"), Slot("RW", "AMR", "WF", "oW"), Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "3-4-2-1", slots: back3 + [
            Slot("LWB", "WBL", "WB", "oWB"), Slot("LCM", "MC", "CM", "oPCM"), Slot("RCM", "MC", "MP", "oSCM"),
            Slot("RWB", "WBR", "AWB", "oWB"), Slot("LAM", "AMC", "AP", "oAM"), Slot("RAM", "AMC", "SS", "oTAM"),
            Slot("ST", "ST", "CF", "oCF"),
        ]),
        Formation(name: "3-4-1-2", slots: back3 + [
            Slot("LWB", "WBL", "WB", "oWB"), Slot("LCM", "MC", "CM", "oPCM"), Slot("RCM", "MC", "MP", "oSCM"),
            Slot("RWB", "WBR", "WB", "oWB"), Slot("AM", "AMC", "AP", "oAM"), Slot("LST", "ST", "CF", "oCF"),
            Slot("RST", "ST", "CHF", "oCOCF"),
        ]),
        Formation(name: "3-1-4-2", slots: back3 + [
            Slot("DM", "DM", "DM", "oSDM"), Slot("LM", "ML", "WM", "oWM"), Slot("LCM", "MC", "CHM", "oPCM"),
            Slot("RCM", "MC", "AP", "oCM"), Slot("RM", "MR", "WM", "oWM"), Slot("LST", "ST", "CF", "oCF"),
            Slot("RST", "ST", "CHF", "oTCF"),
        ]),
        Formation(name: "5-2-1-2", slots: back3 + [
            Slot("LWB", "WBL", "WB", "oHWB"), Slot("RWB", "WBR", "WB", "oHWB"), Slot("LCM", "MC", "CM", "oSCM"),
            Slot("RCM", "MC", "CHM", "oPCM"), Slot("AM", "AMC", "AP", "oTAM"), Slot("LST", "ST", "CF", "oCF"),
            Slot("RST", "ST", "CHF", "oCOCF"),
        ]),
        Formation(name: "5-4-1", slots: back3 + [
            Slot("LWB", "WBL", "WB", "oHWB"), Slot("RWB", "WBR", "WB", "oHWB"), Slot("LM", "ML", "WM", "oTWM"),
            Slot("LCM", "MC", "CM", "oSCM"), Slot("RCM", "MC", "MP", "oCM"), Slot("RM", "MR", "WM", "oTWM"),
            Slot("ST", "ST", "TF", "oCOCF"),
        ]),
        Formation(name: "5-2-3", slots: back3 + [
            Slot("LWB", "WBL", "WB", "oHWB"), Slot("RWB", "WBR", "WB", "oHWB"), Slot("LCM", "MC", "CM", "oSCM"),
            Slot("RCM", "MC", "CHM", "oPCM"), Slot("LW", "AML", "IF", "oIOW"), Slot("RW", "AMR", "IF", "oIOW"),
            Slot("ST", "ST", "CF", "oCF"),
        ]),
    ]

    /// Every preset: the common shapes, then the rest.
    public static var presets: [Formation] { all + more }

    /// A blank pitch with just a goalkeeper, for building a shape from scratch.
    public static let blank = Formation(name: "Blank", slots: [Slot("GK", "GK", "GK", "oGK")])

    static let back4: [Slot] = [
        Slot("GK", "GK", "GK", "oGK"), Slot("LB", "DL", "FB", "oFB"), Slot("LCB", "DC", "BPCB", "oCB"),
        Slot("RCB", "DC", "CB", "oCCB"), Slot("RB", "DR", "FB", "oFB"),
    ]
    static let back3: [Slot] = [
        Slot("GK", "GK", "GK", "oGK"), Slot("LCB", "DC", "WCB", "oWCB"), Slot("CB", "DC", "CB", "oCB"),
        Slot("RCB", "DC", "WCB", "oWCB"),
    ]
}

// MARK: - Squad analysis

public struct SlotAnalysis: Sendable, Identifiable {
    public var id: String { slot.label }
    public let slot: Slot
    public let starter: PlayerRow?
    public let starterScore: Double
    public let backup: PlayerRow?
    public let backupScore: Double
    public let issues: [String]
    /// How far this slot is below the squad's typical starter level (bigger = weaker).
    public let weakness: Double
}

public struct SquadReport: Sendable {
    public let club: String
    public let squad: [PlayerRow]
    public let slots: [SlotAnalysis]
    public let level: Double          // average starter role score
    public let reputation: Int        // typical reputation of the squad's best players
    public let averageAge: Double
}

public struct SigningCriteria: Sendable, Equatable {
    public var maxValueGbp: Int = 0       // 0 = no limit
    public var maxWageGbp: Int = 0        // 0 = no limit
    public var minAge = 16
    public var maxAge = 34
    public var minInterest: InterestLevel? = nil   // only players at least this keen to join (needs a model)
    public var minGain = 0.5              // must beat the current starter by this much
    public var forDepth = false           // compare against the backup instead of the starter
    /// Only these nationalities (matched loosely: "ireland" finds Republic of Ireland); empty = any.
    public var nationalities: [String] = []
    public init() {}

    /// Splits "England, Wales" into its names.
    public static func nationalities(from text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func nationalityMatches(_ nat: String?) -> Bool {
        guard !nationalities.isEmpty else { return true }
        guard let nat, !nat.isEmpty else { return false }
        return nationalities.contains { nat.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

public enum SquadBuilder {
    public static let minFamiliarity: UInt8 = 15

    static func roleIndex(_ code: String) -> Int? { Roles.index(code) }

    /// How much of a slot's score comes from the In Possession role; the rest from the OOP role.
    public static let ipShare = 0.6

    /// A player's score in a slot: IP and OOP role scores blended.
    public static func slotScore(_ r: PlayerRow, ip: Int?, oop: Int?) -> Double {
        switch (ip, oop) {
        case let (i?, o?): return ((ipShare * r.roleScores[i] + (1 - ipShare) * r.roleScores[o]) * 10).rounded() / 10
        case let (i?, nil): return r.roleScores[i]
        case let (nil, o?): return r.roleScores[o]
        default: return 0
        }
    }
    public static func slotScore(_ r: PlayerRow, _ slot: Slot) -> Double {
        slotScore(r, ip: roleIndex(slot.role), oop: roleIndex(slot.oop))
    }

    static func familiarity(_ r: PlayerRow, _ posIdx: Int?) -> UInt8 {
        guard let i = posIdx, let f = r.person.pos, i < f.count else { return 0 }
        return f[i]
    }

    public static func clubs(_ rows: [PlayerRow]) -> [String] {
        Array(Set(rows.compactMap { $0.person.club })).sorted()
    }

    /// Men's or women's players only. Men's and women's sides of a club share its name in the database,
    /// so the squad builder must always pick one.
    public static func team(_ rows: [PlayerRow], women: Bool) -> [PlayerRow] {
        rows.filter { ($0.person.f == 1) == women }
    }

    /// (men, women) registered at the club.
    public static func genderCounts(club: String, rows: [PlayerRow]) -> (men: Int, women: Int) {
        var m = 0, w = 0
        for r in rows where r.person.club == club { if r.person.f == 1 { w += 1 } else { m += 1 } }
        return (m, w)
    }

    public static func analyse(club: String, formation: Formation, rows: [PlayerRow], meta: ExportMeta,
                               season: Int) -> SquadReport {
        let squad = rows.filter { $0.person.club == club }
        let posIndex = Dictionary(uniqueKeysWithValues: meta.positionKeys.enumerated().map { ($1, $0) })

        // Best possible XI (optimal assignment, not first-come), then the best backups from who's left.
        struct Pair { let slot: Int; let row: Int; let score: Double }
        var value = Array(repeating: [Double?](repeating: nil, count: squad.count), count: formation.slots.count)
        for (si, slot) in formation.slots.enumerated() {
            let ri = roleIndex(slot.role), oi = roleIndex(slot.oop)
            guard ri != nil || oi != nil else { continue }
            for (pi, r) in squad.enumerated() where familiarity(r, posIndex[slot.position]) >= minFamiliarity {
                value[si][pi] = slotScore(r, ip: ri, oop: oi)
            }
        }
        var starter = [Int: Pair]()
        let xi = TacticsAdvisor.optimalAssignment(slots: formation.slots.count, players: squad.count) { value[$0][$1] }
        for (si, p) in xi.enumerated() { if let p, let v = value[si][p] { starter[si] = Pair(slot: si, row: p, score: v) } }
        let usedStarters = Set(starter.values.map(\.row))
        var backup = [Int: Pair]()
        let bench = TacticsAdvisor.optimalAssignment(slots: formation.slots.count, players: squad.count) { si, p in
            usedStarters.contains(p) ? nil : value[si][p]
        }
        for (si, p) in bench.enumerated() { if let p, let v = value[si][p] { backup[si] = Pair(slot: si, row: p, score: v) } }

        let starterScores = starter.values.map(\.score)
        let level = starterScores.isEmpty ? 0 : starterScores.reduce(0, +) / Double(starterScores.count)
        let reps = squad.map { $0.person.rep ?? 0 }.sorted(by: >).prefix(16)
        let reputation = reps.isEmpty ? 0 : reps[reps.count / 2]
        let ages = squad.map(\.age).filter { $0 > 0 }
        let avgAge = ages.isEmpty ? 0 : Double(ages.reduce(0, +)) / Double(ages.count)
        let soon = "\(season + 1)-12-31"

        var analyses: [SlotAnalysis] = []
        for (si, slot) in formation.slots.enumerated() {
            let s = starter[si].map { squad[$0.row] }
            let b = backup[si].map { squad[$0.row] }
            let ss = starter[si]?.score ?? 0, bs = backup[si]?.score ?? 0
            var issues: [String] = []
            if s == nil { issues.append("No natural \(slot.position)") }
            else {
                if ss < level - 1 { issues.append(String(format: "Starter %.1f below squad level %.1f", ss, level)) }
                if let a = s?.age, a >= 31 { issues.append("Starter is \(a)") }
                if let e = s?.person.exp, !e.isEmpty, e <= soon { issues.append("Starter's contract ends \(DateText.monthYear(e))") }
            }
            if b == nil { issues.append("No backup") }
            else if bs < level - 2.5 { issues.append(String(format: "Weak backup (%.1f)", bs)) }
            let weakness = (s == nil ? 6 : max(0, level - ss)) + (b == nil ? 1.5 : max(0, level - bs) / 3)
            analyses.append(SlotAnalysis(slot: slot, starter: s, starterScore: ss, backup: b, backupScore: bs,
                                         issues: issues, weakness: weakness))
        }
        return SquadReport(club: club, squad: squad, slots: analyses, level: level, reputation: reputation, averageAge: avgAge)
    }

    public struct Suggestion: Sendable, Identifiable {
        public var id: UInt32 { row.id }
        public var row: PlayerRow
        public let score: Double
        public let gain: Double
        public var interest: InterestAssessment? = nil

        // Sort keys for the signings table.
        public var name: String { row.name }
        public var age: Int { row.age }
        public var club: String { row.club }
        public var nat: String { row.person.nat ?? "" }
        public var ca: Int { row.ca }
        public var interestRank: Int { interest?.level.rawValue ?? -1 }
        /// Free agents cost nothing; unknown values sort last.
        public var valueSort: Int { row.club.isEmpty ? 0 : (row.person.val ?? Int.max) }
        public subscript(extra key: String) -> Double { row[extra: key] }
    }

    /// Players who would improve this slot, affordable and (optionally) keen enough to join.
    public static func suggestions(for a: SlotAnalysis, report: SquadReport, rows: [PlayerRow], meta: ExportMeta,
                                   criteria c: SigningCriteria, interest model: InterestModel? = nil, season: Int = 0,
                                   limit: Int = 40) -> [Suggestion] {
        let ri = roleIndex(a.slot.role), oi = roleIndex(a.slot.oop)
        guard ri != nil || oi != nil else { return [] }
        let posIdx = meta.positionKeys.firstIndex(of: a.slot.position)
        let baseline = c.forDepth ? (a.backup == nil ? 0 : a.backupScore) : (a.starter == nil ? 0 : a.starterScore)
        var out: [Suggestion] = []
        for r in rows where r.person.club != report.club && r.person.own != report.club {
            guard familiarity(r, posIdx) >= minFamiliarity, r.age >= c.minAge, r.age <= c.maxAge,
                  c.nationalityMatches(r.person.nat) else { continue }
            let score = slotScore(r, ip: ri, oop: oi)
            let gain = score - baseline
            guard gain >= c.minGain else { continue }
            if c.maxValueGbp > 0 { guard let v = r.person.val, v <= c.maxValueGbp else { continue } }
            if c.maxWageGbp > 0, let w = r.person.wage, w > c.maxWageGbp { continue }
            let interest = model?.assess(r, joining: report.club, season: season)
            if let min = c.minInterest, let i = interest, i.level < min { continue }
            out.append(Suggestion(row: r, score: score, gain: gain, interest: interest))
        }
        // Best improvement first; among similar gains, younger and cheaper.
        out.sort { x, y in
            let bx = (x.gain * 2).rounded(.down), by = (y.gain * 2).rounded(.down)   // half-point buckets
            if bx != by { return bx > by }
            if x.row.age != y.row.age { return x.row.age < y.row.age }
            return (x.row.person.val ?? Int.max) < (y.row.person.val ?? Int.max)
        }
        return Array(out.prefix(limit))
    }

    // MARK: My tactic helpers

    public struct Option: Sendable, Identifiable {
        public var id: UInt32 { row.id }
        public let row: PlayerRow
        public let score: Double
        public let familiarity: UInt8
    }

    /// Everyone at the club who could play a slot (natural or accomplished there), best first, in its roles.
    public static func options(for slot: Slot, squad: [PlayerRow], meta: ExportMeta, limit: Int = 8) -> [Option] {
        let pi = meta.positionKeys.firstIndex(of: slot.position)
        return squad.compactMap { r -> Option? in
            let f = familiarity(r, pi)
            guard f >= 12 else { return nil }
            return Option(row: r, score: slotScore(r, slot), familiarity: f)
        }
        .sorted { a, b in a.score != b.score ? a.score > b.score : a.familiarity > b.familiarity }
        .prefix(limit).map { $0 }
    }

    /// One position of the depth chart: everyone in the squad who can play there, best first.
    public struct DepthSlot: Sendable, Identifiable {
        public var id: String { slot.label }
        public let slot: Slot
        public let options: [Option]
        /// Where the position sits across the pitch: 0 = left touchline, 1 = right.
        public var x: Double = 0.5
    }

    /// Familiarity from which a player counts as a natural in a position (below: accomplished).
    public static let naturalFamiliarity: UInt8 = 15

    /// The formation as a depth chart, one row per line from attack down to the keeper, left to
    /// right within a line. Each position lists the squad's players who can play there, scored
    /// for that position's IP and OOP roles.
    public static func depthChart(_ report: SquadReport, meta: ExportMeta, naturalOnly: Bool = false,
                                  limit: Int = 5) -> [[DepthSlot]] {
        let points = PitchLayout.points(for: report.slots.map(\.slot))
        let lines: [Set<String>] = [["ST"], ["AML", "AMC", "AMR"], ["ML", "MC", "MR"], ["WBL", "DM", "WBR"],
                                    ["DL", "DC", "DR", "SW"], ["GK"]]
        return lines.compactMap { line in
            let row = report.slots
                .filter { line.contains($0.slot.position) }
                .sorted { (points[$0.slot.label]?.x ?? 0.5) < (points[$1.slot.label]?.x ?? 0.5) }
                .map { a in
                    DepthSlot(slot: a.slot, options: Array(
                        options(for: a.slot, squad: report.squad, meta: meta, limit: .max)
                            .filter { !naturalOnly || $0.familiarity >= naturalFamiliarity }
                            .prefix(limit)),
                              x: points[a.slot.label]?.x ?? 0.5)
                }
            return row.isEmpty ? nil : row
        }
    }

    /// A player's clearly better roles at a slot (0.5 or more above the roles set there), if any.
    public static func betterRoles(for r: PlayerRow, at slot: Slot) -> (ip: (code: String, score: Double)?, oop: (code: String, score: Double)?) {
        func best(_ roles: [Role], current: String) -> (code: String, score: Double)? {
            let now = Roles.index(current).map { r.roleScores[$0] } ?? 0
            guard let top = roles.compactMap({ role in Roles.index(role.code).map { (role.code, r.roleScores[$0]) } })
                    .max(by: { $0.1 < $1.1 }), top.0 != current, top.1 >= now + 0.5 else { return nil }
            return (top.0, top.1)
        }
        return (best(Formations.roles(for: slot.position), current: slot.role),
                best(Formations.oopRoles(for: slot.position), current: slot.oop))
    }

    public struct Upgrade: Sendable, Identifiable {
        public var id: String { slot.label + "-\(suggestion.row.id)" }
        public let slot: Slot
        public let current: Double
        public let suggestion: Suggestion
    }

    /// The best signing for every position of your tactic, biggest improvement first.
    public static func biggestUpgrades(report: SquadReport, rows: [PlayerRow], meta: ExportMeta, criteria: SigningCriteria,
                                       interest: InterestModel? = nil, season: Int = 0) -> [Upgrade] {
        report.slots.compactMap { a -> Upgrade? in
            guard let best = suggestions(for: a, report: report, rows: rows, meta: meta, criteria: criteria,
                                         interest: interest, season: season, limit: 1).first else { return nil }
            return Upgrade(slot: a.slot, current: criteria.forDepth ? a.backupScore : a.starterScore, suggestion: best)
        }
        .sorted { $0.suggestion.gain > $1.suggestion.gain }
    }
}
