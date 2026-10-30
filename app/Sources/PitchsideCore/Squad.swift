import Foundation

// MARK: - Formations

/// One position in a formation: where it is played and which role is asked of it.
public struct Slot: Sendable, Hashable, Identifiable, Codable {
    public var id: String { label }
    public var label: String      // "LB", "LCB", … (unique within a formation)
    public var position: String   // FM position code used for familiarity
    public var role: String       // Roles.all code

    public init(_ label: String, _ position: String, _ role: String) {
        self.label = label; self.position = position; self.role = role
    }
}

public struct Formation: Sendable, Hashable, Identifiable, Codable {
    public var id: String { name }
    public var name: String
    public var slots: [Slot]
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
        "GK": "GK", "DL": "FB", "DR": "FB", "DC": "CD", "WBL": "WB", "WBR": "WB", "DM": "DM",
        "ML": "W", "MR": "W", "MC": "CM", "AML": "IF", "AMR": "IF", "AMC": "AM", "ST": "AF",
    ]

    /// Roles FM offers at a position (the rest can still be chosen, but are unusual there).
    public static func roles(for position: String) -> [Role] { Roles.all.filter { $0.positions.contains(position) } }

    public static func defaultRole(for position: String) -> String {
        defaultRole[position] ?? roles(for: position).first?.code ?? "CM"
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
        f.slots = relabel(f.slots)
        return f
    }

    public static let all: [Formation] = [
        Formation(name: "4-3-3", slots: [
            Slot("GK", "GK", "SK"), Slot("LB", "DL", "FB"), Slot("LCB", "DC", "BPD"), Slot("RCB", "DC", "CD"),
            Slot("RB", "DR", "FB"), Slot("DM", "DM", "DM"), Slot("LCM", "MC", "B2B"), Slot("RCM", "MC", "MEZ"),
            Slot("LW", "AML", "IF"), Slot("RW", "AMR", "IF"), Slot("ST", "ST", "AF"),
        ]),
        Formation(name: "4-2-3-1", slots: [
            Slot("GK", "GK", "GK"), Slot("LB", "DL", "FB"), Slot("LCB", "DC", "BPD"), Slot("RCB", "DC", "CD"),
            Slot("RB", "DR", "FB"), Slot("LDM", "DM", "DLP"), Slot("RDM", "DM", "BWM"),
            Slot("LW", "AML", "W"), Slot("AM", "AMC", "AM"), Slot("RW", "AMR", "IF"), Slot("ST", "ST", "AF"),
        ]),
        Formation(name: "4-4-2", slots: [
            Slot("GK", "GK", "GK"), Slot("LB", "DL", "FB"), Slot("LCB", "DC", "CD"), Slot("RCB", "DC", "CD"),
            Slot("RB", "DR", "FB"), Slot("LM", "ML", "W"), Slot("LCM", "MC", "B2B"), Slot("RCM", "MC", "CM"),
            Slot("RM", "MR", "W"), Slot("LST", "ST", "AF"), Slot("RST", "ST", "TM"),
        ]),
        Formation(name: "3-5-2", slots: [
            Slot("GK", "GK", "GK"), Slot("LCB", "DC", "BPD"), Slot("CB", "DC", "CD"), Slot("RCB", "DC", "BPD"),
            Slot("LWB", "WBL", "WB"), Slot("RWB", "WBR", "WB"), Slot("DM", "DM", "DM"),
            Slot("LCM", "MC", "B2B"), Slot("RCM", "MC", "AP"), Slot("LST", "ST", "AF"), Slot("RST", "ST", "PF"),
        ]),
        Formation(name: "4-1-4-1", slots: [
            Slot("GK", "GK", "SK"), Slot("LB", "DL", "WB"), Slot("LCB", "DC", "BPD"), Slot("RCB", "DC", "CD"),
            Slot("RB", "DR", "WB"), Slot("DM", "DM", "DM"), Slot("LM", "ML", "W"), Slot("LCM", "MC", "B2B"),
            Slot("RCM", "MC", "AP"), Slot("RM", "MR", "IW"), Slot("ST", "ST", "PF"),
        ]),
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
    public init() {}
}

public enum SquadBuilder {
    public static let minFamiliarity: UInt8 = 15

    static func roleIndex(_ code: String) -> Int? { Roles.all.firstIndex { $0.code == code } }

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

        // Every (slot, player) pair a player can play, best first; fill greedily.
        struct Pair { let slot: Int; let row: Int; let score: Double }
        var pairs: [Pair] = []
        for (si, slot) in formation.slots.enumerated() {
            guard let ri = roleIndex(slot.role) else { continue }
            for (pi, r) in squad.enumerated() where familiarity(r, posIndex[slot.position]) >= minFamiliarity {
                pairs.append(Pair(slot: si, row: pi, score: r.roleScores[ri]))
            }
        }
        pairs.sort { $0.score > $1.score }
        var starter = [Int: Pair](), usedStarters = Set<Int>()
        for p in pairs where starter[p.slot] == nil && !usedStarters.contains(p.row) {
            starter[p.slot] = p; usedStarters.insert(p.row)
        }
        var backup = [Int: Pair](), usedBackups = Set<Int>()
        for p in pairs where backup[p.slot] == nil && !usedStarters.contains(p.row) && !usedBackups.contains(p.row) {
            backup[p.slot] = p; usedBackups.insert(p.row)
        }

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
                if let e = s?.person.exp, !e.isEmpty, e <= soon { issues.append("Starter's contract ends \(e.prefix(7))") }
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
        public let row: PlayerRow
        public let score: Double
        public let gain: Double
        public var interest: InterestAssessment? = nil
    }

    /// Players who would improve this slot, affordable and (optionally) keen enough to join.
    public static func suggestions(for a: SlotAnalysis, report: SquadReport, rows: [PlayerRow], meta: ExportMeta,
                                   criteria c: SigningCriteria, interest model: InterestModel? = nil, season: Int = 0,
                                   limit: Int = 40) -> [Suggestion] {
        guard let ri = roleIndex(a.slot.role) else { return [] }
        let posIdx = meta.positionKeys.firstIndex(of: a.slot.position)
        let baseline = c.forDepth ? (a.backup == nil ? 0 : a.backupScore) : (a.starter == nil ? 0 : a.starterScore)
        var out: [Suggestion] = []
        for r in rows where r.person.club != report.club {
            guard familiarity(r, posIdx) >= minFamiliarity, r.age >= c.minAge, r.age <= c.maxAge else { continue }
            let score = r.roleScores[ri]
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
}
