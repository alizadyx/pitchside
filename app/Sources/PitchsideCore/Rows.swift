import Foundation

/// A player with everything the table sorts on precomputed (sorting 100k+ rows must not
/// recompute role scores or ages on every comparison).
public struct PlayerRow: Identifiable, Sendable, Hashable {
    public var id: UInt32 { person.id }
    public let person: Person
    public var name: String { person.n }
    public var club: String { person.club ?? "" }
    public var division: String { person.div ?? "" }
    public var nation: String { person.nat ?? "" }
    public var ca: Int { person.ca }
    public var pa: Int { person.pa }
    public var value: Int { person.val ?? -1 }
    public var wage: Int { person.wage ?? -1 }
    public var expires: String { person.exp ?? "" }
    public var age: Int
    public let positions: String
    public let positionSet: Set<Int>       // indices with familiarity ≥ 15
    public let bestRole: String
    public let bestRoleScore: Double
    public let roleScores: [Double]        // aligned with Roles.all
    public var shortlisted: Bool = false
    public var shortlistKey: Int { shortlisted ? 1 : 0 }
    /// Score for the role chosen in the filter (or the best role when none is chosen).
    public var selectedRoleScore: Double = 0
    /// Match-engine "meta" score (see Meta), 1–20.
    public var meta: Double = 0
    /// CA gained since the reference scan; `PlayerRow.noGrowth` when unknown.
    public var growth: Int = PlayerRow.noGrowth
    public static let noGrowth = -999
    /// Not present in the previous scan (new regen / newly loaded player).
    public var isNew = false
    public var isGoalkeeper: Bool { positionSet.contains(0) }
    /// Transfer value per CA point (lower = better value); huge when value unknown.
    public var pricePerCA: Double { value >= 0 && ca > 0 ? Double(value) / Double(ca) : 1e12 }
    /// Sort key/text for the configurable extra column.
    /// Sort keys for user-added columns, keyed by StatColumn.id (see `PlayerRow[extra:]`).
    public var extras: [String: Double] = [:]

    public static func == (a: PlayerRow, b: PlayerRow) -> Bool {
        a.id == b.id && a.age == b.age && a.shortlisted == b.shortlisted && a.selectedRoleScore == b.selectedRoleScore
    }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public struct StaffRow: Identifiable, Sendable, Hashable {
    public var id: UInt32 { person.id }
    public let person: Person
    public var name: String { person.n }
    public var club: String { person.club ?? "" }
    public var job: String { person.job ?? "" }
    public var nation: String { person.nat ?? "" }
    public var ca: Int { person.ca }
    public var pa: Int { person.pa }
    public var wage: Int { person.wage ?? -1 }
    public var expires: String { person.exp ?? "" }
    public var age: Int
    /// Value of the attribute chosen for the extra column.
    public var selectedAttr: Int = 0

    public static func == (a: StaffRow, b: StaffRow) -> Bool { a.id == b.id && a.age == b.age && a.selectedAttr == b.selectedAttr }
    public func hash(into h: inout Hasher) { h.combine(id) }
}

public enum Ages {
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) } }
    public static func string(_ d: Date) -> String { iso.string(from: d) }

    public static func age(dob: String?, at ref: Date) -> Int {
        guard let d = date(dob) else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.dateComponents([.year], from: d, to: ref).year ?? 0
    }
}

public enum RowBuilder {
    public static func players(_ people: [Person], meta: ExportMeta, reference: Date, shortlist: Set<UInt32>,
                               growth: [UInt32: Int] = [:], previousIds: Set<UInt32>? = nil) -> [PlayerRow] {
        let resolved = Roles.resolve(attrKeys: meta.playerAttrKeys, positionKeys: meta.positionKeys)
        let metaWeights = Meta.resolve(meta)
        let posKeys = meta.positionKeys
        return people.map { p in
            let fam = p.pos ?? []
            let natural = Set(fam.indices.filter { fam[$0] >= 15 })
            let posText = fam.indices.filter { fam[$0] >= 15 }
                .sorted { fam[$0] > fam[$1] }
                .map { $0 < posKeys.count ? posKeys[$0] : "?" }
                .joined(separator: ", ")
            let attrs = p.a ?? []
            let scores = resolved.map { Roles.score($0, attrs: attrs) }
            // Best role among roles the player can actually play (natural/accomplished).
            var best = -1
            for (i, r) in resolved.enumerated() where !natural.isDisjoint(with: r.positionIdx) {
                if best < 0 || scores[i] > scores[best] { best = i }
            }
            if best < 0, let m = scores.indices.max(by: { scores[$0] < scores[$1] }) { best = m }
            var row = PlayerRow(person: p,
                             age: Ages.age(dob: p.dob, at: reference),
                             positions: posText,
                             positionSet: natural,
                             bestRole: best >= 0 ? resolved[best].role.code : "",
                             bestRoleScore: best >= 0 ? scores[best] : 0,
                             roleScores: scores,
                             shortlisted: shortlist.contains(p.id),
                             selectedRoleScore: best >= 0 ? scores[best] : 0)
            let gk = !fam.isEmpty && fam[0] >= 15 && (fam.max() ?? 0) == fam[0]
            row.meta = Meta.score(metaWeights, attrs: attrs, personality: p.p, isGoalkeeper: gk)
            if let g = growth[p.id] { row.growth = g }
            if let prev = previousIds { row.isNew = !prev.contains(p.id) }
            return row
        }
    }

    public static func staff(_ people: [Person], reference: Date) -> [StaffRow] {
        people.map { StaffRow(person: $0, age: Ages.age(dob: $0.dob, at: reference)) }
    }
}

// MARK: - Filters

public struct AttributeRule: Codable, Sendable, Hashable, Identifiable {
    public var id = UUID()
    public var key: String
    public var min: Int
    public init(key: String, min: Int) { self.key = key; self.min = min }
}

public struct PlayerFilter: Codable, Sendable, Equatable {
    public var text = ""                 // name, club or nationality
    public var nation = ""
    public var division = ""
    public var minAge = 15, maxAge = 45
    public var minCA = 0, minPA = 0
    public var maxValue = 0              // 0 = no limit (in display currency units, converted by caller)
    public var maxWage = 0
    public var positions: Set<String> = []
    public var expiringBy = 0            // year; 0 = any
    public var listedOnly = false
    public var hideNotForSale = false
    public var shortlistOnly = false
    public var roleCode = ""             // when set, sort/filter by this role
    public var minRoleScore = 0.0
    public var minMeta = 0.0
    public var minGrowth = 0             // 0 = any; needs a reference scan
    public var onlyNew = false           // only players not in the previous scan
    public var freeAgentsOnly = false
    public var gender = 0                // 0 = all, 1 = men, 2 = women
    public var rules: [AttributeRule] = []
    /// With a role chosen, also list players who aren't natural in any of its positions.
    public var roleAnyPosition = false
    public init() {}

    /// Tolerates searches saved by older versions that lack newer fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? d }
        let base = PlayerFilter()
        text = v(.text, base.text); nation = v(.nation, base.nation); division = v(.division, base.division)
        minAge = v(.minAge, base.minAge); maxAge = v(.maxAge, base.maxAge)
        minCA = v(.minCA, base.minCA); minPA = v(.minPA, base.minPA)
        maxValue = v(.maxValue, base.maxValue); maxWage = v(.maxWage, base.maxWage)
        positions = v(.positions, base.positions); expiringBy = v(.expiringBy, base.expiringBy)
        listedOnly = v(.listedOnly, base.listedOnly); hideNotForSale = v(.hideNotForSale, base.hideNotForSale)
        shortlistOnly = v(.shortlistOnly, base.shortlistOnly)
        roleCode = v(.roleCode, base.roleCode); minRoleScore = v(.minRoleScore, base.minRoleScore)
        minMeta = v(.minMeta, base.minMeta); minGrowth = v(.minGrowth, base.minGrowth)
        onlyNew = v(.onlyNew, base.onlyNew); freeAgentsOnly = v(.freeAgentsOnly, base.freeAgentsOnly)
        gender = v(.gender, base.gender); rules = v(.rules, base.rules)
        roleAnyPosition = v(.roleAnyPosition, base.roleAnyPosition)
    }
}

public struct StaffFilter: Codable, Sendable, Equatable {
    public var text = ""
    public var job = ""
    public var minAge = 15, maxAge = 90
    public var minCA = 0
    public var gender = 0                // 0 = all, 1 = men, 2 = women
    public var rules: [AttributeRule] = []
    public init() {}
}

public enum Filtering {
    /// `valueScale` converts the filter's money limits back to GBP (what the game stores).
    public static func apply(_ f: PlayerFilter, to rows: [PlayerRow], meta: ExportMeta, gbpPerUnit: Double) -> [PlayerRow] {
        let text = f.text.trimmingCharacters(in: .whitespaces).lowercased()
        let nation = f.nation.trimmingCharacters(in: .whitespaces).lowercased()
        let division = f.division.trimmingCharacters(in: .whitespaces).lowercased()
        let posIdx = Set(f.positions.compactMap { meta.positionKeys.firstIndex(of: $0) })
        let attrIdx = Dictionary(uniqueKeysWithValues: meta.playerAttrKeys.enumerated().map { ($1, $0) })
        let hidIdx = Dictionary(uniqueKeysWithValues: meta.hiddenKeys.enumerated().map { ($1, $0) })
        let perIdx = Dictionary(uniqueKeysWithValues: meta.personalityKeys.enumerated().map { ($1, $0) })
        let roleIdx = Roles.all.firstIndex { $0.code == f.roleCode }
        // A role only makes sense for players who play one of its positions (unless positions are picked).
        let rolePositions: Set<Int>? = roleIdx.flatMap { ri in
            guard posIdx.isEmpty && !f.roleAnyPosition else { return nil }
            return Set(Roles.all[ri].positions.compactMap { meta.positionKeys.firstIndex(of: $0) })
        }
        let maxValueGbp = f.maxValue > 0 ? Double(f.maxValue) * gbpPerUnit : 0
        let maxWageGbp = f.maxWage > 0 ? Double(f.maxWage) * gbpPerUnit : 0
        let expiry = f.expiringBy > 0 ? "\(f.expiringBy)-12-31" : ""

        return rows.filter { r in
            let p = r.person
            if f.shortlistOnly && !r.shortlisted { return false }
            if f.gender == 1 && p.f == 1 { return false }
            if f.gender == 2 && p.f != 1 { return false }
            if r.age < f.minAge || r.age > f.maxAge { return false }
            if p.ca < f.minCA || p.pa < f.minPA { return false }
            if !text.isEmpty {
                let hay = (p.n + " " + (p.club ?? "")).lowercased()
                if !hay.contains(text) { return false }
            }
            if !nation.isEmpty && !(p.nat ?? "").lowercased().contains(nation) { return false }
            if !division.isEmpty && !(p.div ?? "").lowercased().contains(division) { return false }
            if !posIdx.isEmpty && r.positionSet.isDisjoint(with: posIdx) { return false }
            if let rp = rolePositions, !rp.isEmpty, r.positionSet.isDisjoint(with: rp) { return false }
            if maxValueGbp > 0 { guard let v = p.val, Double(v) <= maxValueGbp else { return false } }
            if maxWageGbp > 0 { guard let w = p.wage, Double(w) <= maxWageGbp else { return false } }
            if !expiry.isEmpty { guard let e = p.exp, e <= expiry else { return false } }
            if f.listedOnly && p.lst != true { return false }
            if f.hideNotForSale && p.nfs == true { return false }
            if let ri = roleIdx, f.minRoleScore > 0, r.roleScores[ri] < f.minRoleScore { return false }
            if f.minMeta > 0 && r.meta < f.minMeta { return false }
            if f.minGrowth > 0 && (r.growth == PlayerRow.noGrowth || r.growth < f.minGrowth) { return false }
            if f.onlyNew && !r.isNew { return false }
            if f.freeAgentsOnly && !(p.club ?? "").isEmpty { return false }
            for rule in f.rules {
                // A known attribute with no data for this player fails the rule.
                let v: Int
                if let i = attrIdx[rule.key] { v = p.a.flatMap { i < $0.count ? Int($0[i]) : nil } ?? 0 }
                else if let i = hidIdx[rule.key] { v = p.h.flatMap { i < $0.count ? Int($0[i]) : nil } ?? 0 }
                else if let i = perIdx[rule.key] { v = p.p.flatMap { i < $0.count ? Int($0[i]) : nil } ?? 0 }
                else { continue }   // attribute this export doesn't know at all
                if v < rule.min { return false }
            }
            return true
        }
    }

    public static func apply(_ f: StaffFilter, to rows: [StaffRow], meta: ExportMeta) -> [StaffRow] {
        let text = f.text.trimmingCharacters(in: .whitespaces).lowercased()
        let job = f.job.trimmingCharacters(in: .whitespaces).lowercased()
        let idx = Dictionary(uniqueKeysWithValues: meta.staffAttrKeys.enumerated().map { ($1, $0) })
        return rows.filter { r in
            let p = r.person
            if r.age < f.minAge || r.age > f.maxAge || p.ca < f.minCA { return false }
            if f.gender == 1 && p.f == 1 { return false }
            if f.gender == 2 && p.f != 1 { return false }
            if !text.isEmpty && !(p.n + " " + (p.club ?? "")).lowercased().contains(text) { return false }
            if !job.isEmpty && !(p.job ?? "").lowercased().contains(job) { return false }
            for rule in f.rules {
                guard let i = idx[rule.key] else { continue }
                let v = p.s.flatMap { i < $0.count ? Int($0[i]) : nil } ?? 0
                if v < rule.min { return false }
            }
            return true
        }
    }
}

// MARK: - Display helpers

public enum AttributeGroups {
    public static let technical = ["Corners", "Crossing", "Dribbling", "Finishing", "FirstTouch", "FreeKicks", "Heading",
                                   "LongShots", "LongThrows", "Marking", "Passing", "PenaltyTaking", "Tackling", "Technique"]
    public static let mental = ["Aggression", "Anticipation", "Bravery", "Composure", "Concentration", "Decisions",
                                "Determination", "Flair", "Leadership", "OffTheBall", "Positioning", "Teamwork", "Vision", "WorkRate"]
    public static let physical = ["Acceleration", "Agility", "Balance", "JumpingReach", "NaturalFitness", "Pace", "Stamina", "Strength"]
    public static let goalkeeping = ["AerialReach", "CommandOfArea", "Communication", "Eccentricity", "Handling", "Kicking",
                                     "OneOnOnes", "Punching", "Reflexes", "RushingOut", "Throwing"]
    /// Attributes you can read off a player's profile in game (used by Calibration).
    public static let visibleOutfield = technical + mental + physical

    // FM27 staff attributes (Coaching / Mental / Knowledge / Medical & data).
    public static let staffCoaching = ["Attacking", "Defending", "Fitness", "Goalkeeping", "Possession", "SetPieces",
                                       "Tactical", "Technical", "WorkingWithYoungsters"]
    public static let staffMental = ["Determination", "Motivating", "PeopleManagement"]
    public static let staffKnowledge = ["JudgingAbility", "JudgingPotential", "JudgingStaff", "Negotiating", "TacticalKnowledge",
                                        "DataAnalysis", "Physiotherapy", "SportsScience"]

    /// FM27 shows staff attributes as words; bands measured against the game.
    public static func staffWord(_ v: Int) -> String {
        switch v {
        case ..<1: "–"
        case 1...4: "Poor"
        case 5...6: "Reasonable"
        case 7...9: "Competent"
        case 10...11: "Average"
        case 12...14: "Good"
        case 15...16: "Very Good"
        default: "Outstanding"
        }
    }

    private static let special: [String: String] = [
        "OneOnOnes": "One on Ones", "FirstTouch": "First Touch", "OffTheBall": "Off the Ball",
        "GkDistribution": "GK Distribution", "GkHandling": "GK Handling", "GkShotStopping": "GK Shot Stopping",
        "ImportantMatches": "Important Matches", "InjuryProneness": "Injury Proneness",
        "WorkingWithYoungsters": "Working with Youngsters", "JudgingAbility": "Judging Player Ability",
        "JudgingPotential": "Judging Player Potential", "JudgingStaff": "Judging Staff Ability",
        "ManManagement": "Man Management", "DataAnalysis": "Data Analysis", "SportsScience": "Sports Science",
    ]

    public static func label(_ key: String) -> String {
        if let s = special[key] { return s }
        var out = ""
        for ch in key {
            if ch.isUppercase && !out.isEmpty { out.append(" ") }
            out.append(ch)
        }
        return out
    }
}

public enum Money {
    public static func format(_ gbp: Int?, symbol: String, perGbp: Double) -> String {
        guard let gbp, gbp >= 0 else { return "—" }
        let v = Double(gbp) * perGbp
        switch v {
        case 1_000_000...: return "\(symbol)\(String(format: v >= 100_000_000 ? "%.0f" : "%.1f", v / 1_000_000))M"
        case 1_000...: return "\(symbol)\(Int((v / 1_000).rounded()))K"
        default: return "\(symbol)\(Int(v))"
        }
    }
}
