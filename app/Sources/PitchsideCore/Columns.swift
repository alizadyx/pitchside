import Foundation

/// A column the user can add to a player table: a general stat, an attribute, a hidden attribute or a
/// personality trait. Identified by a stable string so the choice can be saved.
public struct StatColumn: Hashable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case general = "gen", attribute = "attr", hidden = "hid", personality = "per" }

    public let kind: Kind
    public let key: String
    public var id: String { "\(kind.rawValue).\(key)" }

    public init(_ kind: Kind, _ key: String) { self.kind = kind; self.key = key }

    public init?(id: String) {
        let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let k = Kind(rawValue: parts[0]) else { return nil }
        self.init(k, parts[1])
    }

    public var title: String {
        guard kind == .general else { return AttributeGroups.label(key) }
        return StatColumns.general.first { $0.key == key }?.title ?? key
    }

    /// Short header so attribute columns stay narrow, using FM's own abbreviations ("Fin", "Dec").
    public var shortTitle: String {
        guard kind != .general else { return title }
        return StatColumns.abbreviation[key] ?? String(title.prefix(3))
    }

    public var isAttribute: Bool { kind != .general }
}

public enum StatColumns {
    public struct General: Sendable { public let key: String; public let title: String }

    /// General stats that can be added as columns.
    public static let general: [General] = [
        General(key: "value", title: "Value"),
        General(key: "ask", title: "Asking price"),
        General(key: "wage", title: "Wage/wk"),
        General(key: "contract", title: "Contract"),
        General(key: "interest", title: "Interest"),
        General(key: "growth", title: "Growth"),
        General(key: "pricePerCA", title: "£ per CA"),
        General(key: "meta", title: "Meta"),
        General(key: "metaRating", title: "Meta %"),
        General(key: "bestRole", title: "Best role"),
        General(key: "ca", title: "CA"),
        General(key: "pa", title: "PA"),
        General(key: "height", title: "Height"),
        General(key: "rep", title: "Reputation"),
        General(key: "wrep", title: "World rep."),
        General(key: "likelyPeak", title: "Likely peak"),
        General(key: "redFlags", title: "Red flags"),
        General(key: "nation", title: "Nationality"),
        General(key: "division", title: "Division"),
    ]

    /// Columns grouped for the column menu. Hidden and personality groups only when the scan has them.
    public static func catalog(meta: ExportMeta?, includeHidden: Bool) -> [(String, [StatColumn])] {
        var out: [(String, [StatColumn])] = [("General", general.map { StatColumn(.general, $0.key) })]
        let attrs = Set(meta?.playerAttrKeys ?? [])
        func group(_ name: String, _ keys: [String]) {
            let present = keys.filter { attrs.isEmpty || attrs.contains($0) }
            if !present.isEmpty { out.append((name, present.map { StatColumn(.attribute, $0) })) }
        }
        group("Technical", AttributeGroups.technical)
        group("Mental", AttributeGroups.mental)
        group("Physical", AttributeGroups.physical)
        group("Goalkeeping", AttributeGroups.goalkeeping)
        if includeHidden, let m = meta {
            if !m.hiddenKeys.isEmpty { out.append(("Hidden", m.hiddenKeys.map { StatColumn(.hidden, $0) })) }
            if !m.personalityKeys.isEmpty { out.append(("Personality", m.personalityKeys.map { StatColumn(.personality, $0) })) }
        }
        return out
    }

    /// FM's attribute abbreviations.
    public static let abbreviation: [String: String] = [
        "Corners": "Cor", "Crossing": "Cro", "Dribbling": "Dri", "Finishing": "Fin", "FirstTouch": "Fir",
        "FreeKicks": "Fre", "Heading": "Hea", "LongShots": "Lon", "LongThrows": "L Th", "Marking": "Mar",
        "Passing": "Pas", "PenaltyTaking": "Pen", "Tackling": "Tck", "Technique": "Tec",
        "Aggression": "Agg", "Anticipation": "Ant", "Bravery": "Bra", "Composure": "Cmp", "Concentration": "Cnt",
        "Decisions": "Dec", "Determination": "Det", "Flair": "Fla", "Leadership": "Ldr", "OffTheBall": "OtB",
        "Positioning": "Pos", "Teamwork": "Tea", "Vision": "Vis", "WorkRate": "Wor",
        "Acceleration": "Acc", "Agility": "Agi", "Balance": "Bal", "JumpingReach": "Jum", "NaturalFitness": "Nat",
        "Pace": "Pac", "Stamina": "Sta", "Strength": "Str",
        "AerialReach": "Aer", "CommandOfArea": "Cmd", "Communication": "Com", "Eccentricity": "Ecc",
        "Handling": "Han", "Kicking": "Kic", "OneOnOnes": "1v1", "Punching": "Pun", "Reflexes": "Ref",
        "RushingOut": "TRO", "Throwing": "Thr",
        "Consistency": "Con", "Dirtiness": "Dir", "ImportantMatches": "Imp", "InjuryProneness": "Inj",
        "Versatility": "Vers", "Adaptability": "Adap", "Ambition": "Amb", "Loyalty": "Loy", "Pressure": "Pres",
        "Professionalism": "Prof", "Sportsmanship": "Spor", "Temperament": "Temp", "Controversy": "Cont",
    ]

    public static let defaults: [String: [String]] = [
        "players": ["gen.value"],
        "squad": ["gen.wage"],
        "signings": ["gen.contract"],
        "growth": ["gen.value"],
    ]
}

/// Reads a column's value from a row. Build once per scan (it caches attribute positions).
public struct StatReader: Sendable {
    let attr: [String: Int]
    let hidden: [String: Int]
    let personality: [String: Int]
    let meta: ExportMeta

    public init(meta: ExportMeta) {
        self.meta = meta
        attr = Dictionary(meta.playerAttrKeys.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        hidden = Dictionary(meta.hiddenKeys.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        personality = Dictionary(meta.personalityKeys.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A number for sorting and display; nil when the scan has no value. Money is in GBP, contract as
    /// yyyymmdd. Interest is not handled here (it depends on your club).
    public func value(_ c: StatColumn, _ r: PlayerRow) -> Double? {
        let p = r.person
        func pick(_ idx: [String: Int], _ arr: [UInt8]?) -> Double? {
            guard let i = idx[c.key], let a = arr, i < a.count, a[i] > 0 else { return nil }
            return Double(a[i])
        }
        switch c.kind {
        case .attribute: return pick(attr, p.a)
        case .hidden: return pick(hidden, p.h)
        case .personality: return pick(personality, p.p)
        case .general:
            switch c.key {
            case "value": return p.val.map(Double.init)
            case "ask": return p.ask.flatMap { $0 > 0 ? Double($0) : nil }
            case "wage": return p.wage.map(Double.init)
            case "contract":
                guard let e = p.exp, !e.isEmpty else { return nil }
                return Double(e.replacingOccurrences(of: "-", with: ""))
            case "growth": return r.growth == PlayerRow.noGrowth ? nil : Double(r.growth)
            case "pricePerCA": return r.value >= 0 && r.ca > 0 ? r.pricePerCA : nil
            case "meta": return r.meta
            case "metaRating": return Double(r.metaRating)
            case "bestRole": return r.bestRoleScore
            case "ca": return Double(r.ca)
            case "pa": return Double(r.pa)
            case "height": return p.ht.flatMap { $0 > 0 ? Double($0) : nil }
            case "rep": return p.rep.map(Double.init)
            case "wrep": return p.wrep.map(Double.init)
            case "likelyPeak": return Development.outlook(r, meta: meta).map { Double($0.likelyPeak) }
            case "redFlags": return Double(Flags.of(p, meta: meta).filter { !$0.good }.count)
            default: return nil
            }
        }
    }

    /// Text columns (nationality, division) have no number; they sort alphabetically by this key.
    public static func text(_ c: StatColumn, _ r: PlayerRow) -> String? {
        guard c.kind == .general else { return nil }
        switch c.key {
        case "nation": return r.nation
        case "division": return r.division
        default: return nil
        }
    }
}

extension StatReader {
    /// Fills each row's sort keys for `columns`. Text columns sort alphabetically; `interest` supplies
    /// the interest score, which depends on the user's club.
    public func fill(_ rows: inout [PlayerRow], _ columns: [StatColumn],
                     interest: (PlayerRow) -> Double? = { _ in nil }) {
        guard !columns.isEmpty, !rows.isEmpty else { return }
        var ranks: [String: [String: Double]] = [:]
        for c in columns where c.kind == .general && (c.key == "nation" || c.key == "division") {
            let sorted = Set(rows.compactMap { StatReader.text(c, $0) }.filter { !$0.isEmpty }).sorted()
            ranks[c.id] = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1, Double($0)) })
        }
        for i in rows.indices {
            for c in columns {
                let v: Double?
                if let r = ranks[c.id] { v = StatReader.text(c, rows[i]).flatMap { r[$0] } }
                else if c.kind == .general && c.key == "interest" { v = interest(rows[i]) }
                else { v = value(c, rows[i]) }
                rows[i].extras[c.id] = v ?? -.infinity
            }
        }
    }
}

extension PlayerRow {
    /// Sort key for a user-added column, filled in by the app for the columns on screen.
    public subscript(extra key: String) -> Double { extras[key] ?? -.infinity }
}

extension Person {
    /// The surname as FM stores it, for pasting into the game's search. Falls back to everything
    /// after the first word of the display name ("Kevin De Bruyne" → "De Bruyne").
    public var lastName: String {
        if let s = sn, !s.isEmpty { return s }
        let words = n.split(separator: " ")
        return words.count > 1 ? words.dropFirst().joined(separator: " ") : n
    }
}
