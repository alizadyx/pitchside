import Foundation

// MARK: - Active filter chips

/// One active filter, shown as a removable chip above the players table.
public struct FilterChip: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    /// Which panel group it belongs to, so that group can be highlighted.
    public let group: String
}

extension PlayerFilter {
    public static let defaultMinAge = 15, defaultMaxAge = 45

    /// Every non-default setting, in panel order. Gender and shortlist mode are global
    /// switches elsewhere in the UI, so they are not chips.
    public func chips(currency: String = "£", roleName: (String) -> String = { $0 }) -> [FilterChip] {
        var c: [FilterChip] = []
        func add(_ id: String, _ label: String, _ group: String) { c.append(FilterChip(id: id, label: label, group: group)) }
        let t = text.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { add("text", "“\(t)”", "search") }
        if !nation.trimmingCharacters(in: .whitespaces).isEmpty { add("nation", "Nation: \(nation)", "search") }
        if !division.trimmingCharacters(in: .whitespaces).isEmpty { add("division", "Division: \(division)", "search") }
        if minAge != Self.defaultMinAge || maxAge != Self.defaultMaxAge { add("age", "Age \(minAge)–\(maxAge)", "ability") }
        if minCA > 0 { add("minCA", "CA ≥ \(minCA)", "ability") }
        if minPA > 0 { add("minPA", "PA ≥ \(minPA)", "ability") }
        if minMeta > 0 { add("minMeta", String(format: "Meta ≥ %.1f", minMeta), "meta") }
        if minGrowth > 0 { add("minGrowth", "Growth ≥ +\(minGrowth)", "meta") }
        if onlyNew { add("onlyNew", "New regens", "meta") }
        if freeAgentsOnly { add("free", "Free agents", "meta") }
        if !positions.isEmpty { add("positions", "Positions: " + positions.sorted().joined(separator: ", "), "positions") }
        if !roleCode.isEmpty {
            add("role", minRoleScore > 0 ? String(format: "%@ ≥ %.1f", roleName(roleCode), minRoleScore) : "Role: \(roleName(roleCode))", "role")
        }
        if maxValue > 0 { add("maxValue", "Value ≤ \(currency)\(Self.short(maxValue))", "money") }
        if maxWage > 0 { add("maxWage", "Wage ≤ \(currency)\(Self.short(maxWage))", "money") }
        if expiringBy > 0 { add("expiring", "Contract ends by \(expiringBy)", "money") }
        if listedOnly { add("listed", "Transfer listed", "money") }
        if hideNotForSale { add("nfs", "Hide not for sale", "money") }
        for r in rules { add("rule:\(r.id.uuidString)", "\(AttributeGroups.label(r.key)) ≥ \(r.min)", "attributes") }
        return c
    }

    public var activeGroups: Set<String> { Set(chips().map(\.group)) }

    public mutating func clear(_ id: String) {
        switch id {
        case "text": text = ""
        case "nation": nation = ""
        case "division": division = ""
        case "age": minAge = Self.defaultMinAge; maxAge = Self.defaultMaxAge
        case "minCA": minCA = 0
        case "minPA": minPA = 0
        case "minMeta": minMeta = 0
        case "minGrowth": minGrowth = 0
        case "onlyNew": onlyNew = false
        case "free": freeAgentsOnly = false
        case "positions": positions = []
        case "role": roleCode = ""; minRoleScore = 0
        case "maxValue": maxValue = 0
        case "maxWage": maxWage = 0
        case "expiring": expiringBy = 0
        case "listed": listedOnly = false
        case "nfs": hideNotForSale = false
        default:
            if id.hasPrefix("rule:"), let u = UUID(uuidString: String(id.dropFirst(5))) {
                rules.removeAll { $0.id == u }
            }
        }
    }

    /// Clears everything except the global switches (gender, shortlist mode).
    public mutating func clearAll() {
        let g = gender, s = shortlistOnly
        self = PlayerFilter()
        gender = g
        shortlistOnly = s
    }

    static func short(_ v: Int) -> String {
        switch v {
        case 1_000_000...: return String(format: v % 1_000_000 == 0 ? "%.0fM" : "%.1fM", Double(v) / 1_000_000)
        case 1_000...: return "\(v / 1_000)K"
        default: return "\(v)"
        }
    }
}

// MARK: - Stars

public enum Stars {
    /// FM-style 0.5–5 stars for an ability on the 1–200 scale.
    public static func value(_ ability: Int) -> Double {
        guard ability > 0 else { return 0 }
        return min(5, max(0.5, (Double(ability) / 200 * 10).rounded() / 2))
    }
}

// MARK: - Pitch layout

/// A point on a pitch drawn vertically: x 0 = left touchline, y 0 = opponent's goal line.
public struct PitchPoint: Sendable, Hashable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum PitchLayout {
    static let base: [String: PitchPoint] = [
        "GK": PitchPoint(x: 0.5, y: 0.93),
        "SW": PitchPoint(x: 0.5, y: 0.84),
        "DL": PitchPoint(x: 0.12, y: 0.76), "DC": PitchPoint(x: 0.5, y: 0.78), "DR": PitchPoint(x: 0.88, y: 0.76),
        "WBL": PitchPoint(x: 0.1, y: 0.6), "DM": PitchPoint(x: 0.5, y: 0.63), "WBR": PitchPoint(x: 0.9, y: 0.6),
        "ML": PitchPoint(x: 0.12, y: 0.45), "MC": PitchPoint(x: 0.5, y: 0.47), "MR": PitchPoint(x: 0.88, y: 0.45),
        "AML": PitchPoint(x: 0.15, y: 0.28), "AMC": PitchPoint(x: 0.5, y: 0.3), "AMR": PitchPoint(x: 0.85, y: 0.28),
        "ST": PitchPoint(x: 0.5, y: 0.12),
    ]

    public static func point(_ position: String) -> PitchPoint? { base[position] }

    /// Positions for a formation; slots sharing a position are spread across the pitch.
    public static func points(for slots: [Slot]) -> [String: PitchPoint] {
        var out: [String: PitchPoint] = [:]
        let grouped = Dictionary(grouping: slots, by: \.position)
        for (pos, group) in grouped {
            guard let b = base[pos] else { continue }
            let n = group.count
            let spread: [Double] = n == 1 ? [b.x] : n == 2 ? [0.36, 0.64] : n == 3 ? [0.25, 0.5, 0.75]
                : (0..<n).map { 0.15 + 0.7 * Double($0) / Double(n - 1) }
            for (i, s) in group.enumerated() { out[s.label] = PitchPoint(x: spread[i], y: b.y) }
        }
        return out
    }
}

// MARK: - Radar chart axes

public enum RadarAxes {
    public static let outfield: [(String, [String])] = [
        ("Speed", ["Pace", "Acceleration"]),
        ("Physical", ["Strength", "Stamina", "JumpingReach", "Balance", "NaturalFitness"]),
        ("Technique", ["Dribbling", "FirstTouch", "Technique"]),
        ("Creativity", ["Passing", "Vision", "Flair"]),
        ("Attacking", ["Finishing", "OffTheBall", "LongShots", "Composure"]),
        ("Defending", ["Tackling", "Marking", "Positioning", "Heading"]),
        ("Mental", ["Anticipation", "Decisions", "Concentration", "Determination", "WorkRate", "Teamwork"]),
    ]

    public static let goalkeeper: [(String, [String])] = [
        ("Shot stopping", ["Reflexes", "OneOnOnes", "Handling"]),
        ("Aerial", ["AerialReach", "CommandOfArea", "JumpingReach"]),
        ("Distribution", ["Kicking", "Throwing", "Passing"]),
        ("Organising", ["Communication", "Positioning", "Concentration"]),
        ("Sweeping", ["RushingOut", "Acceleration", "Pace", "Anticipation"]),
        ("Mental", ["Composure", "Decisions", "Determination", "Bravery"]),
    ]

    /// Average 1–20 value per axis.
    public static func values(_ p: Person, meta: ExportMeta, axes: [(String, [String])]) -> [Double] {
        let idx = Dictionary(uniqueKeysWithValues: meta.playerAttrKeys.enumerated().map { ($1, $0) })
        let a = p.a ?? []
        return axes.map { _, keys in
            let vals = keys.compactMap { idx[$0] }.filter { $0 < a.count }.map { Double(a[$0]) }
            return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
        }
    }
}
