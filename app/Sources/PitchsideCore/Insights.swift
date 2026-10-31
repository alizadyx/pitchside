import Foundation

// MARK: - Red and green flags

/// A quick verdict drawn from hidden attributes and personality ("Injury prone", "Model professional").
public struct PlayerFlag: Hashable, Sendable, Identifiable {
    public let text: String
    public let good: Bool
    public let detail: String
    public var id: String { text }
}

public enum Flags {
    /// `includeHidden: false` keeps to attributes FM shows openly (for users who hide hidden attributes).
    public static func of(_ p: Person, meta: ExportMeta, includeHidden: Bool = true) -> [PlayerFlag] {
        func val(_ keys: [String], _ arr: [UInt8]?, _ key: String) -> Int? {
            guard let i = keys.firstIndex(of: key), let a = arr, i < a.count, a[i] > 0 else { return nil }
            return Int(a[i])
        }
        func attr(_ k: String) -> Int? { val(meta.playerAttrKeys, p.a, k) }
        func hid(_ k: String) -> Int? { includeHidden ? val(meta.hiddenKeys, p.h, k) : nil }
        func per(_ k: String) -> Int? { includeHidden ? val(meta.personalityKeys, p.p, k) : nil }

        var out: [PlayerFlag] = []
        func add(_ v: Int?, high: Int? = nil, highText: String = "", highGood: Bool = true,
                 low: Int? = nil, lowText: String = "", lowGood: Bool = false, _ name: String) {
            guard let v else { return }
            if let h = high, v >= h { out.append(PlayerFlag(text: highText, good: highGood, detail: "\(name) \(v)")) }
            else if let l = low, v <= l { out.append(PlayerFlag(text: lowText, good: lowGood, detail: "\(name) \(v)")) }
        }
        add(hid("InjuryProneness"), high: 15, highText: "Injury prone", highGood: false,
            low: 5, lowText: "Rarely injured", lowGood: true, "Injury proneness")
        add(hid("Consistency"), high: 16, highText: "Consistent", low: 8, lowText: "Inconsistent", "Consistency")
        add(hid("ImportantMatches"), high: 16, highText: "Big-match player", low: 6, lowText: "Nervous in big games", "Important matches")
        add(hid("Dirtiness"), high: 15, highText: "Dirty player", highGood: false, "Dirtiness")
        add(hid("Versatility"), high: 16, highText: "Versatile", "Versatility")
        add(per("Professionalism"), high: 17, highText: "Model professional", low: 7, lowText: "Low professionalism", "Professionalism")
        add(per("Pressure"), high: 16, highText: "Handles pressure", low: 6, lowText: "Struggles under pressure", "Pressure")
        add(per("Temperament"), low: 6, lowText: "Hot-headed", "Temperament")
        add(per("Controversy"), high: 15, highText: "Controversial", highGood: false, "Controversy")
        add(per("Adaptability"), high: 16, highText: "Settles quickly abroad", low: 5, lowText: "Slow to settle abroad", "Adaptability")
        add(per("Loyalty"), high: 17, highText: "Loyal", "Loyalty")
        add(attr("NaturalFitness"), low: 7, lowText: "Poor natural fitness", "Natural fitness")
        add(attr("Determination"), high: 17, highText: "Driven", low: 6, lowText: "Lacks drive", "Determination")
        return out.sorted { a, b in a.good != b.good ? !a.good : a.text < b.text }   // red flags first
    }
}

// MARK: - Development outlook

public struct DevelopmentOutlook: Sendable, Hashable {
    /// Ability he is likely to reach (FM's 1–200 scale).
    public let likelyPeak: Int
    /// 0–1: how much of the gap to his potential he is likely to close.
    public let realisation: Double
    public var label: String {
        realisation >= 0.75 ? "Strong" : realisation >= 0.55 ? "Good" : realisation >= 0.4 ? "Average" : "Doubtful"
    }
    public let reasons: [String]
}

public enum Development {
    /// For players 23 and under with room to grow: how much of their potential they're likely to
    /// reach, from years left to develop, mentality (Professionalism, Determination, Ambition) and
    /// injury proneness. Older or fully developed players return nil.
    public static func outlook(_ r: PlayerRow, meta: ExportMeta) -> DevelopmentOutlook? {
        let p = r.person
        let gap = r.pa - r.ca
        guard r.age <= 23, gap >= 5, r.pa > 0 else { return nil }
        func v(_ keys: [String], _ arr: [UInt8]?, _ k: String) -> Double? {
            guard let i = keys.firstIndex(of: k), let a = arr, i < a.count, a[i] > 0 else { return nil }
            return Double(a[i])
        }
        let prof = v(meta.personalityKeys, p.p, "Professionalism") ?? 10
        let det = v(meta.playerAttrKeys, p.a, "Determination") ?? 10
        let amb = v(meta.personalityKeys, p.p, "Ambition") ?? 10
        let inj = v(meta.hiddenKeys, p.h, "InjuryProneness") ?? 8
        let mentality = (prof * 0.45 + det * 0.35 + amb * 0.2) / 20
        let window = min(1.0, Double(max(0, 24 - r.age)) / 6)
        var real = (0.35 + 0.65 * mentality) * (0.4 + 0.6 * window) - max(0, inj - 12) * 0.02
        real = min(1, max(0.1, real))
        var reasons: [String] = []
        if prof >= 16 { reasons.append("Professional") } else if prof <= 8 { reasons.append("Unprofessional") }
        if det >= 16 { reasons.append("Determined") } else if det <= 8 { reasons.append("Low determination") }
        if r.age <= 19 { reasons.append("Years to develop") } else if r.age >= 22 { reasons.append("Little time left") }
        if inj >= 15 { reasons.append("Injury prone") }
        return DevelopmentOutlook(likelyPeak: r.ca + Int((Double(gap) * real).rounded()), realisation: real, reasons: reasons)
    }
}

// MARK: - Club teams (first team, U21, U18…)

public struct ClubTeam: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let division: String
    public let reputation: Int
    public let count: Int
    /// Age limit from the game: 100 (or nil with older scans) for senior teams, 21 for U21…
    public let ageLimit: Int?
    /// 0 = first team, then other senior teams, then youth teams from oldest to youngest.
    public let rank: Int
    /// True for the stand-in teams built from ages when the scan has no team data.
    public var approximate = false
    public var isYouth: Bool { (ageLimit ?? 100) < 100 }
    public var label: String {
        if approximate { return rank == 0 ? "First team (best 30)" : "Under \(ageLimit ?? 21) by age" }
        if let a = ageLimit, a < 100 { return "U\(a)" }
        if rank == 0 { return "First team" }
        return division.isEmpty ? "Reserves" : "Reserves (\(division))"
    }
}

extension SquadBuilder {
    /// The club's teams as seen through contracts: the senior team with the highest reputation is
    /// the first team, then other senior teams, then youth teams by age group.
    public static func teams(club: String, rows: [PlayerRow]) -> [ClubTeam] {
        var groups: [UInt32: (div: [String: Int], rep: Int, count: Int, age: Int?)] = [:]
        for r in rows where r.person.club == club {
            guard let t = r.person.tm else { continue }
            var g = groups[t] ?? ([:], 0, 0, r.person.tage)
            if let d = r.person.div { g.div[d, default: 0] += 1 }
            g.rep = max(g.rep, r.person.trep ?? 0)
            g.count += 1
            groups[t] = g
        }
        let sorted = groups.sorted { a, b in
            let ya = (a.value.age ?? 100) < 100, yb = (b.value.age ?? 100) < 100
            if ya != yb { return !ya }                                        // senior teams first
            if ya, let x = a.value.age, let y = b.value.age, x != y { return x > y }   // U23, U21, U18…
            return a.value.rep != b.value.rep ? a.value.rep > b.value.rep : a.value.count > b.value.count
        }
        let real = sorted.enumerated().map { i, kv in
            ClubTeam(id: kv.key, division: kv.value.div.max { $0.value < $1.value }?.key ?? "",
                     reputation: kv.value.rep, count: kv.value.count, ageLimit: kv.value.age, rank: i)
        }
        if !real.isEmpty { return real }
        // Older scans have no team data: approximate the first team by ability and youth teams by age.
        let squad = rows.filter { $0.person.club == club }
        guard squad.count > 30 else { return [] }
        let div = Dictionary(grouping: squad.compactMap(\.person.div), by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? ""
        let rep = squad.compactMap(\.person.trep).max() ?? 0
        var out = [ClubTeam(id: 0, division: div, reputation: rep, count: min(30, squad.count), ageLimit: nil, rank: 0, approximate: true)]
        for (k, limit) in [21, 18].enumerated() {
            let n = squad.filter { $0.age > 0 && $0.age < limit }.count
            if n > 0 { out.append(ClubTeam(id: UInt32(k + 1), division: div, reputation: 0, count: n, ageLimit: limit, rank: k + 1, approximate: true)) }
        }
        return out
    }

    /// The club's players out on loan elsewhere, best first.
    public static func loanedOut(club: String, rows: [PlayerRow]) -> [PlayerRow] {
        rows.filter { $0.person.own == club && $0.person.club != club }.sorted { $0.person.ca > $1.person.ca }
    }

    /// The club's players in `team` (all of them when `team` is nil).
    public static func members(of team: ClubTeam?, club: String, rows: [PlayerRow]) -> [PlayerRow] {
        let squad = rows.filter { $0.person.club == club }
        guard let team else { return squad }
        guard team.approximate else { return squad.filter { $0.person.tm == team.id } }
        if team.rank == 0 {
            return Array(squad.sorted { $0.person.ca > $1.person.ca }.prefix(30))
        }
        return squad.filter { $0.age > 0 && $0.age < (team.ageLimit ?? 21) }
    }

    // MARK: Timeline

    public struct SeasonPlan: Sendable, Identifiable {
        public var id: Int { season }
        public let season: Int              // 2026 = the 2026/27 season
        public let report: SquadReport
        public let leaving: [PlayerRow]     // contracts ending at the end of this season
        public var label: String { "\(season)/\(String(season + 1).suffix(2))" }
    }

    /// The squad over the next `seasons` seasons: who is still under contract, a year older each
    /// season, analysed in the same formation.
    public static func timeline(club: String, formation: Formation, squad: [PlayerRow], meta: ExportMeta,
                                season: Int, seasons: Int = 3) -> [SeasonPlan] {
        (0..<seasons).map { k in
            let s = season + k
            var rows = squad.filter { r in
                guard let e = r.person.exp, !e.isEmpty else { return true }   // unknown contract: assume staying
                return e >= "\(s)-07-01"
            }
            for i in rows.indices { rows[i].age += k }
            let report = analyse(club: club, formation: formation, rows: rows, meta: meta, season: s)
            let leaving = rows.filter { r in
                guard let e = r.person.exp, !e.isEmpty else { return false }
                return e < "\(s + 1)-07-01"
            }.sorted { $0.ca > $1.ca }
            return SeasonPlan(season: s, report: report, leaving: leaving)
        }
    }
}

// MARK: - Staff advice

public enum StaffAdvisor {
    /// Which jobs can do the work of an area. Matched against the job title, lowercased.
    public enum JobGroup: Sendable, Hashable {
        case coaching, setPieces, goalkeeping, fitness, youth, scouting, physio, sportsScience, analysis
    }

    public struct Area: Sendable, Identifiable, Hashable {
        public var id: String { title }
        public let title: String
        public let keys: [String]
        public let group: JobGroup
    }

    public static let areas: [Area] = [
        Area(title: "Attacking coaching", keys: ["Attacking"], group: .coaching),
        Area(title: "Defending coaching", keys: ["Defending"], group: .coaching),
        Area(title: "Fitness coaching", keys: ["Fitness"], group: .fitness),
        Area(title: "Goalkeeping coaching", keys: ["Goalkeeping"], group: .goalkeeping),
        Area(title: "Possession coaching", keys: ["Possession"], group: .coaching),
        Area(title: "Set pieces", keys: ["SetPieces"], group: .setPieces),
        Area(title: "Tactical coaching", keys: ["Tactical"], group: .coaching),
        Area(title: "Technical coaching", keys: ["Technical"], group: .coaching),
        Area(title: "Youth development", keys: ["WorkingWithYoungsters"], group: .youth),
        Area(title: "Scouting", keys: ["JudgingAbility", "JudgingPotential"], group: .scouting),
        Area(title: "Physio", keys: ["Physiotherapy"], group: .physio),
        Area(title: "Sports science", keys: ["SportsScience"], group: .sportsScience),
        Area(title: "Data analysis", keys: ["DataAnalysis"], group: .analysis),
    ]

    /// Job title as FM27 shows it. Scans from 0.5 and earlier labelled set-piece coaches "Media Analyst".
    public static func jobTitle(_ raw: String) -> String { raw == "Media Analyst" ? "Set Piece Coach" : raw }

    /// Board members and executives: never suggested as staff and never counted as your coaches.
    public static func isBoard(_ job: String) -> Bool {
        let j = job.lowercased()
        return ["chairman", "president", "owner", "director", "general manager", "chief executive", "ceo", "loan manager"]
            .contains { j.contains($0) }
    }

    public static func fits(_ rawJob: String, _ g: JobGroup) -> Bool {
        let j = jobTitle(rawJob).lowercased()
        guard !j.isEmpty, !isBoard(j) else { return false }
        let coach = (j.contains("coach") || j.contains("manager")) && !j.contains("goalkeeping") && !j.contains("gk coach")
            && !j.contains("fitness")
        switch g {
        case .coaching: return coach && !j.contains("set piece")
        case .setPieces: return coach
        case .goalkeeping: return j.contains("goalkeeping") || j.contains("gk coach")
        case .fitness: return j.contains("fitness")
        case .youth: return coach || j.contains("youth")
        case .scouting: return j.contains("scout") || j.contains("recruitment")
        case .physio: return j.contains("physio") || j.contains("doctor")
        case .sportsScience: return j.contains("sports scien") || j.contains("doctor") || j.contains("performance")
        case .analysis: return j.contains("analys")
        }
    }

    public struct Candidate: Sendable, Identifiable {
        public let row: StaffRow
        public let score: Double
        public var id: UInt32 { row.id }
        /// Why this person might say no ("works for a bigger club"), nil when realistic.
        public let doubt: String?
    }

    public struct Advice: Sendable, Identifiable {
        public var id: String { area.id }
        public let area: Area
        public let best: StaffRow?          // your best staff member doing this job
        public let bestScore: Double
        public let candidates: [Candidate]
    }

    static func score(_ r: StaffRow, _ keys: [String], _ meta: ExportMeta) -> Double? {
        guard let s = r.person.s else { return nil }
        let vals = keys.compactMap { k -> Double? in
            guard let i = meta.staffAttrKeys.firstIndex(of: k), i < s.count, s[i] > 0 else { return nil }
            return Double(s[i])
        }
        return vals.count == keys.count ? vals.reduce(0, +) / Double(vals.count) : nil
    }

    /// Would this person consider moving to a club of `clubRep` (team reputation, 0–10000)?
    /// Free agents always would; staff at clearly bigger clubs, or far more famous than your club, wouldn't.
    static func doubt(_ r: StaffRow, clubRep: Int?) -> String? {
        guard let mine = clubRep, mine > 0 else { return nil }
        if r.club.isEmpty { return nil }
        if let theirs = r.person.trep, theirs > mine + 400 { return "works for a bigger club" }
        if let rep = r.person.rep, rep > mine + 2500 { return "too big a name for your club" }
        return nil
    }

    /// Areas from weakest to strongest at your club, each with up to `limit` clear upgrades
    /// (at least 2 points better) whose job fits the area. People with no paid contract at a club
    /// (board members, volunteers) are left out; free agents are kept. With `realistic`, people
    /// unlikely to join a club of `clubRep` are left out too.
    public static func advise(club: String, staff: [StaffRow], meta: ExportMeta, maxWageGbp: Int = 0,
                              clubRep: Int? = nil, realistic: Bool = true, limit: Int = 6) -> [Advice] {
        let mine = staff.filter { $0.person.club == club }
        let others = staff.filter { r in
            guard r.person.club != club else { return false }
            if r.club.isEmpty { return true }                     // free agent
            return (r.person.wage ?? 0) > 0                       // employed with a real contract
        }
        let advice: [Advice] = areas.compactMap { area in
            guard area.keys.allSatisfy({ meta.staffAttrKeys.contains($0) }) else { return nil }
            let scored = mine.filter { fits($0.job, area.group) }.compactMap { r in score(r, area.keys, meta).map { (r, $0) } }
            let best = scored.max { $0.1 < $1.1 }
            let floor = (best?.1 ?? 0) + 2
            var cands: [Candidate] = []
            for r in others where fits(r.job, area.group) || (r.club.isEmpty && !isBoard(r.job)) {
                guard let sc = score(r, area.keys, meta), sc >= floor else { continue }
                if maxWageGbp > 0, let w = r.person.wage, w > maxWageGbp { continue }
                let d = doubt(r, clubRep: clubRep)
                if realistic && d != nil { continue }
                cands.append(Candidate(row: r, score: sc, doubt: d))
            }
            cands.sort { a, b in a.score != b.score ? a.score > b.score : (a.row.wage < 0 ? Int.max : a.row.wage) < (b.row.wage < 0 ? Int.max : b.row.wage) }
            return Advice(area: area, best: best?.0, bestScore: best?.1 ?? 0, candidates: Array(cands.prefix(limit)))
        }
        return advice.sorted { $0.bestScore < $1.bestScore }
    }
}
