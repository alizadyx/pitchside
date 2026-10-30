import Foundation

/// Compares clubs: a league table of team metrics, head to head, or one team against a group.
/// Every club is measured on its best XI in its best-suited formation (the same method as Tactics),
/// so reserves and youngsters don't drag the numbers down.
public enum TeamCompare {

    /// Which players a club is judged on.
    public enum Basis: Int, Sendable, CaseIterable, Identifiable {
        case firstTeam, wholeClub, top18
        public var id: Int { rawValue }
        public var title: String {
            switch self {
            case .firstTeam: "First-team XI"
            case .wholeClub: "Best XI at the club"
            case .top18: "Squad (top 18)"
            }
        }
        public var help: String {
            switch self {
            case .firstTeam: "The best 11 from the first-team squad"
            case .wholeClub: "The best 11 from all of the club's teams, youth included"
            case .top18: "The 18 best first-team players, so depth counts as well as the XI"
            }
        }
    }

    public struct Metric: Sendable, Identifiable, Hashable {
        public let id: String
        public let title: String
        public let short: String
        public let group: String
        public let higherIsBetter: Bool
        public let decimals: Int
        /// On FM's 1–20 scale (can go on the radar).
        public let attributeScale: Bool
        /// Plain-English explanation, shown when hovering a column.
        public var explanation: String { TeamCompare.explanations[id] ?? title }
    }

    /// XI level on a 0–100 scale: (level − 6) × 10, so one point of level is ten rating points.
    /// About 50 is a lower-league side, 70 a typical top-flight side, 90+ a title contender.
    public static func rating(_ level: Double) -> Double { min(100, max(0, (level - 6) * 10)) }

    static let explanations: [String: String] = [
        "rating": "Rating: XI level stretched to 0–100 so gaps are easier to see — (level − 6) × 10. Roughly: 50 lower league, 70 typical top flight, 90+ title contender. 10 rating points ≈ 15–20 CA.",
        "level": "XI level: average role score (1–20) of the best eleven in their best shape, IP and OOP roles together — the same score as in Tactics. About 1 point is a big gap (roughly 15–20 CA); Rating shows it on 0–100.",
        "depth": "Depth: average role score of the best backup for each of the eleven positions.",
        "ca": "Average Current Ability of the players being compared (0–200).",
        "pa": "Average Potential Ability of the players being compared (0–200).",
        "meta": "Meta score: how strong the players are on the attributes the match engine rewards most (pace, acceleration, anticipation and so on).",
        "gk": "Goalkeeper: role score of the starting keeper.",
        "def": "Defence: average role score of the starting full backs, wing backs and centre backs.",
        "mid": "Midfield: average role score of the starting defensive, central and wide midfielders.",
        "att": "Attack: average role score of the starting attacking midfielders, wingers and strikers.",
        "technique": "Technique: average of Passing, First Touch, Technique, Composure, Vision and Decisions (outfield players).",
        "pace": "Pace: average of Pace and Acceleration (outfield players).",
        "work": "Work: work rate and pressing — average of Work Rate, Stamina, Teamwork and Natural Fitness (outfield players).",
        "physical": "Physical: average of Strength, Jumping Reach and Balance (outfield players).",
        "aerial": "Air: aerial threat — Heading and Jumping Reach of the three best headers in the team.",
        "setpieces": "SP: set pieces — how good the best takers are: corners (Corners + Crossing), free kicks (Free Kicks + Technique) and penalties (Penalty Taking + Composure).",
        "mental": "Mental strength: Determination, Composure, Concentration, Decisions and the Pressure personality trait (outfield players).",
        "age": "Average age of the starting eleven.",
        "old": "Number of starters aged 30 or over.",
        "young": "Number of starters aged 23 or under.",
        "size": "Number of players in the squad being compared.",
        "close": "Near: players within 1.5 of the XI level — how many could step in without a big drop.",
        "expiring": "Exp: starters whose contracts end by next summer.",
        "wages": "Wages: weekly wage bill of the squad.",
        "value": "Value: total transfer value of the squad.",
    ]

    public static let metrics: [Metric] = [
        Metric(id: "rating", title: "Rating (0–100)", short: "Rating", group: "Overall", higherIsBetter: true, decimals: 0, attributeScale: false),
        Metric(id: "level", title: "XI level", short: "Level", group: "Overall", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "depth", title: "Depth (best backups)", short: "Depth", group: "Overall", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "ca", title: "Average CA", short: "CA", group: "Overall", higherIsBetter: true, decimals: 0, attributeScale: false),
        Metric(id: "pa", title: "Average PA", short: "PA", group: "Overall", higherIsBetter: true, decimals: 0, attributeScale: false),
        Metric(id: "meta", title: "Meta score", short: "Meta", group: "Overall", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "gk", title: "Goalkeeper", short: "GK", group: "Lines", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "def", title: "Defence", short: "Def", group: "Lines", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "mid", title: "Midfield", short: "Mid", group: "Lines", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "att", title: "Attack", short: "Att", group: "Lines", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "technique", title: "Technique", short: "Tech", group: "Profile", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "pace", title: "Pace", short: "Pace", group: "Profile", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "work", title: "Work rate & pressing", short: "Work", group: "Profile", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "physical", title: "Physical", short: "Phys", group: "Profile", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "aerial", title: "Aerial threat (top 3)", short: "Air", group: "Profile", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "setpieces", title: "Set-piece takers", short: "SP", group: "Profile", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "mental", title: "Mental strength", short: "Mental", group: "Profile", higherIsBetter: true, decimals: 1, attributeScale: true),
        Metric(id: "age", title: "Average age", short: "Age", group: "Squad", higherIsBetter: false, decimals: 1, attributeScale: false),
        Metric(id: "old", title: "Starters 30+", short: "30+", group: "Squad", higherIsBetter: false, decimals: 0, attributeScale: false),
        Metric(id: "young", title: "Starters 23 and under", short: "≤23", group: "Squad", higherIsBetter: true, decimals: 0, attributeScale: false),
        Metric(id: "size", title: "Squad size", short: "Size", group: "Squad", higherIsBetter: true, decimals: 0, attributeScale: false),
        Metric(id: "close", title: "Players near XI level (±1.5)", short: "Near", group: "Squad", higherIsBetter: true, decimals: 0, attributeScale: false),
        Metric(id: "expiring", title: "Starters' contracts ending by next summer", short: "Exp", group: "Squad", higherIsBetter: false, decimals: 0, attributeScale: false),
        Metric(id: "wages", title: "Wage bill / week", short: "Wages", group: "Money", higherIsBetter: true, decimals: 0, attributeScale: false),
        Metric(id: "value", title: "Squad value", short: "Value", group: "Money", higherIsBetter: true, decimals: 0, attributeScale: false),
    ]

    public static func metric(_ id: String) -> Metric? { metrics.first { $0.id == id } }
    /// Metrics drawn on the radar (all on the 1–20 scale).
    public static let radarIDs = ["level", "gk", "def", "mid", "att", "technique", "pace", "work", "physical", "aerial", "mental"]

    public struct TeamProfile: Sendable, Identifiable {
        public var id: String { club }
        public let club: String
        public let division: String
        public let formation: String
        public let values: [String: Double]
        public let fit: TacticsAdvisor.FormationFit
        /// The players measured (XI, or top 18).
        public let players: [PlayerRow]
        /// Attribute-group profile used by team instructions.
        public let tactical: TacticsAdvisor.Profile
        public subscript(_ id: String) -> Double { values[id] ?? 0 }

        public init(club: String, division: String, formation: String, values: [String: Double],
                    fit: TacticsAdvisor.FormationFit, players: [PlayerRow], tactical: TacticsAdvisor.Profile) {
            self.club = club; self.division = division; self.formation = formation; self.values = values
            self.fit = fit; self.players = players; self.tactical = tactical
        }
    }

    // MARK: Building profiles

    /// Players of `club` that `basis` looks at (the caller passes one gender's rows).
    static func pool(club: String, rows: [PlayerRow], basis: Basis) -> [PlayerRow] {
        let all = rows.filter { $0.person.club == club }
        if basis == .wholeClub { return all }
        let teams = SquadBuilder.teams(club: club, rows: rows)
        guard let first = teams.first(where: { $0.rank == 0 }) else { return all }
        return SquadBuilder.members(of: first, club: club, rows: rows)
    }

    public static func profile(club: String, rows: [PlayerRow], meta: ExportMeta, basis: Basis,
                               season: Int = 0, shapes: [Formation] = Formations.all) -> TeamProfile? {
        let squad = pool(club: club, rows: rows, basis: basis)
        guard squad.count >= 11 else { return nil }
        guard let fit = TacticsAdvisor.rankFormations(shapes, squad: squad, meta: meta).first else { return nil }
        let xi = fit.picks.compactMap(\.player)
        let xiIDs = Set(xi.map(\.id))
        var measured = xi
        if basis == .top18 {
            measured += squad.filter { !xiIDs.contains($0.id) }.sorted { $0.bestRoleScore > $1.bestRoleScore }.prefix(7)
        }
        let R = TacticsAdvisor.Reader(meta)
        func avg(_ rows: [PlayerRow], _ f: (PlayerRow) -> Double) -> Double {
            rows.isEmpty ? 0 : rows.map(f).reduce(0, +) / Double(rows.count)
        }
        func attrs(_ keys: [String]) -> Double {
            avg(measured.filter { !TacticsAdvisor.isKeeper($0) }) { r in keys.map { R.attr(r, $0) }.reduce(0, +) / Double(keys.count) }
        }
        func line(_ pos: Set<String>) -> Double {
            let s = fit.picks.filter { pos.contains($0.slot.position) && $0.player != nil }.map(\.score)
            return s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count)
        }
        var v: [String: Double] = [:]
        v["level"] = basis == .top18 ? (fit.level * 11 + measured.dropFirst(11).map(\.bestRoleScore).reduce(0, +)) / Double(max(measured.count, 1)) : fit.level
        v["rating"] = rating(v["level"] ?? 0)
        v["depth"] = fit.depth
        v["ca"] = avg(measured) { Double($0.ca) }
        v["pa"] = avg(measured) { Double($0.pa) }
        v["meta"] = avg(measured) { $0.meta }
        v["gk"] = line(["GK"])
        v["def"] = line(["DL", "DC", "DR", "WBL", "WBR"])
        v["mid"] = line(["DM", "ML", "MC", "MR"])
        v["att"] = line(["AML", "AMC", "AMR", "ST"])
        v["technique"] = attrs(["Passing", "FirstTouch", "Technique", "Composure", "Vision", "Decisions"])
        v["pace"] = attrs(["Pace", "Acceleration"])
        v["work"] = attrs(["WorkRate", "Stamina", "Teamwork", "NaturalFitness"])
        v["physical"] = attrs(["Strength", "JumpingReach", "Balance"])
        let heads = measured.filter { !TacticsAdvisor.isKeeper($0) }
            .map { R.mix($0, [("Heading", 1), ("JumpingReach", 1)]) }.sorted(by: >).prefix(3)
        v["aerial"] = heads.isEmpty ? 0 : heads.reduce(0, +) / Double(heads.count)
        let outfield = measured.filter { !TacticsAdvisor.isKeeper($0) }
        let takers = [["Corners", "Crossing"], ["FreeKicks", "Technique"], ["PenaltyTaking", "Composure"]].map { keys in
            outfield.map { r in keys.map { R.attr(r, $0) }.reduce(0, +) / Double(keys.count) }.max() ?? 0
        }
        v["setpieces"] = takers.reduce(0, +) / 3
        v["mental"] = avg(outfield) { r in
            let base = ["Determination", "Composure", "Concentration", "Decisions"].map { R.attr(r, $0) }.reduce(0, +) / 4
            return base * 0.85 + (R.pers(r, "Pressure") ?? base) * 0.15
        }
        v["age"] = avg(xi) { Double($0.age) }
        v["old"] = Double(xi.filter { $0.age >= 30 }.count)
        v["young"] = Double(xi.filter { $0.age > 0 && $0.age <= 23 }.count)
        v["size"] = Double(squad.count)
        v["close"] = Double(squad.filter { $0.bestRoleScore >= fit.level - 1.5 }.count)
        let soon = "\(season + 1)-06-30"
        v["expiring"] = Double(xi.filter { ($0.person.exp ?? "9999") <= soon && season > 0 }.count)
        v["wages"] = Double(squad.compactMap(\.person.wage).reduce(0, +))
        v["value"] = Double(squad.compactMap(\.person.val).reduce(0, +))
        let division = Dictionary(grouping: squad.compactMap(\.person.div), by: { $0 })
            .max { $0.value.count < $1.value.count }?.key ?? ""
        return TeamProfile(club: club, division: division, formation: fit.formation.name, values: v, fit: fit,
                           players: measured, tactical: TacticsAdvisor.profile(fit, meta: meta))
    }

    /// Where every club plays and what every league looks like, worked out from the players.
    public struct LeagueMap: Sendable {
        /// club → its senior league: the division of its highest-reputation team.
        public var clubLeague: [String: String] = [:]
        /// league → country (the most common nationality among its players).
        public var country: [String: String] = [:]
        /// league → average CA of its clubs' players, to list top divisions first.
        public var strength: [String: Double] = [:]
        public init() {}

        public var countries: [String] { Array(Set(clubLeague.values.compactMap { country[$0] })).sorted() }
        /// Leagues of a country, strongest first.
        public func leagues(in c: String) -> [String] {
            Array(Set(clubLeague.values.filter { country[$0] == c })).sorted { (strength[$0] ?? 0) > (strength[$1] ?? 0) }
        }
        public func clubs(in league: String) -> [String] { clubLeague.filter { $0.value == league }.map(\.key).sorted() }
    }

    public static func leagueMap(_ rows: [PlayerRow]) -> LeagueMap {
        // Per club and division: highest team reputation and player count.
        var perClub: [String: [String: (rep: Int, n: Int)]] = [:]
        var nats: [String: [String: Int]] = [:]
        var ca: [String: (sum: Int, n: Int)] = [:]
        for r in rows {
            guard let c = r.person.club, let d = r.person.div, !d.isEmpty else { continue }
            var e = perClub[c, default: [:]][d] ?? (0, 0)
            e.rep = max(e.rep, r.person.trep ?? 0); e.n += 1
            perClub[c, default: [:]][d] = e
            if let nat = r.person.nat, !nat.isEmpty { nats[d, default: [:]][nat, default: 0] += 1 }
        }
        var m = LeagueMap()
        for (club, divs) in perClub {
            m.clubLeague[club] = divs.max { a, b in a.value.rep != b.value.rep ? a.value.rep < b.value.rep : a.value.n < b.value.n }?.key
        }
        let senior = Set(m.clubLeague.values)
        for r in rows {
            guard let c = r.person.club, let d = m.clubLeague[c], r.person.div == d else { continue }
            var e = ca[d] ?? (0, 0); e.sum += r.ca; e.n += 1; ca[d] = e
        }
        for d in senior {
            m.country[d] = nats[d]?.max { a, b in a.value < b.value }?.key ?? "Other"
            if let e = ca[d], e.n > 0 { m.strength[d] = Double(e.sum) / Double(e.n) }
        }
        return m
    }

    /// Clubs whose senior team plays in `division` (one gender's rows).
    public static func clubs(in division: String, rows: [PlayerRow]) -> [String] {
        leagueMap(rows).clubs(in: division)
    }

    /// Where a club ranks for a metric in `profiles`, as a share: 0 = best, 1 = worst.
    public static func standing(_ value: Double, metric: Metric, in profiles: [TeamProfile]) -> Double? {
        guard profiles.count >= 3 else { return nil }
        let better = profiles.filter { metric.higherIsBetter ? $0[metric.id] > value : $0[metric.id] < value }.count
        return Double(better) / Double(profiles.count - 1)
    }

    public static func league(_ division: String, rows: [PlayerRow], meta: ExportMeta, basis: Basis,
                              season: Int = 0) -> [TeamProfile] {
        clubs(in: division, rows: rows).compactMap { profile(club: $0, rows: rows, meta: meta, basis: basis, season: season) }
            .sorted { $0["level"] > $1["level"] }
    }

    /// Average of every metric over `profiles`.
    public static func average(_ profiles: [TeamProfile]) -> [String: Double] {
        guard !profiles.isEmpty else { return [:] }
        var out: [String: Double] = [:]
        for m in metrics { out[m.id] = profiles.map { $0[m.id] }.reduce(0, +) / Double(profiles.count) }
        return out
    }

    /// Average tactical profile (for team instructions' league column).
    public static func averageTactical(_ profiles: [TeamProfile]) -> TacticsAdvisor.Profile? {
        guard !profiles.isEmpty else { return nil }
        let n = Double(profiles.count)
        var p = TacticsAdvisor.Profile()
        let ps = profiles.map(\.tactical)
        func m(_ k: KeyPath<TacticsAdvisor.Profile, Double>) -> Double { ps.map { $0[keyPath: k] }.reduce(0, +) / n }
        p.base = m(\.base); p.technique = m(\.technique); p.speed = m(\.speed); p.frontSpeed = m(\.frontSpeed)
        p.frontWork = m(\.frontWork); p.work = m(\.work); p.lineSpeed = m(\.lineSpeed); p.cbAerial = m(\.cbAerial)
        p.cbPlaying = m(\.cbPlaying); p.fullbackAttack = m(\.fullbackAttack); p.fullbackDefence = m(\.fullbackDefence)
        p.wideAttack = m(\.wideAttack); p.flair = m(\.flair); p.longShots = m(\.longShots); p.strikerAerial = m(\.strikerAerial)
        p.tackling = m(\.tackling); p.dribbling = m(\.dribbling); p.decisions = m(\.decisions)
        p.gkDistribution = m(\.gkDistribution); p.setPieceThreat = m(\.setPieceThreat); p.midDefence = m(\.midDefence)
        return p
    }

    /// 1 = best in `profiles` for this metric.
    public static func rank(of club: String, metric: Metric, in profiles: [TeamProfile]) -> Int? {
        let sorted = profiles.sorted { metric.higherIsBetter ? $0[metric.id] > $1[metric.id] : $0[metric.id] < $1[metric.id] }
        return sorted.firstIndex { $0.club == club }.map { $0 + 1 }
    }

    /// How a club usually goes into games, from where its XI ranks in its league.
    public static func stance(for club: String, in league: [TeamProfile]) -> (TacticsAdvisor.Stance, rank: Int, of: Int)? {
        guard let level = metric("level"), let r = rank(of: club, metric: level, in: league), league.count >= 4 else { return nil }
        let share = Double(r - 1) / Double(league.count - 1)
        let s: TacticsAdvisor.Stance = share <= 0.25 ? .favourites : share >= 0.65 ? .underdogs : .even
        return (s, r, league.count)
    }

    // MARK: Notes

    static func ordinal(_ n: Int) -> String {
        let suffix = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(suffix)"
    }

    /// Short plain-English findings for one club against the others ("3rd strongest XI of 20").
    public static func notes(for club: String, in profiles: [TeamProfile]) -> [String] {
        guard profiles.count >= 3, let me = profiles.first(where: { $0.club == club }) else { return [] }
        let n = profiles.count
        var out: [String] = []
        if let m = metric("level"), let r = rank(of: club, metric: m, in: profiles) {
            out.append("\(ordinal(r)) strongest XI of \(n)")
        }
        let lines = ["gk": "goalkeeper", "def": "defence", "mid": "midfield", "att": "attack"]
        let ranked = lines.compactMap { id, name in metric(id).flatMap { m in rank(of: club, metric: m, in: profiles).map { (name, $0) } } }
        if let best = ranked.min(by: { $0.1 < $1.1 }), let worst = ranked.max(by: { $0.1 < $1.1 }), best.1 != worst.1 {
            out.append("Best line: \(best.0) (\(ordinal(best.1))); weakest: \(worst.0) (\(ordinal(worst.1)))")
        }
        for (id, hi, lo) in [("pace", "Among the fastest teams", "One of the slowest teams"),
                             ("technique", "Among the most technical sides", "Less technical than most"),
                             ("work", "Built to press: among the hardest-working", "Below average for pressing"),
                             ("aerial", "Big aerial threat", "Weak in the air"),
                             ("depth", "Deep squad", "Thin squad behind the XI")] {
            guard let m = metric(id), let r = rank(of: club, metric: m, in: profiles) else { continue }
            if Double(r) <= Double(n) * 0.2 { out.append("\(hi) (\(ordinal(r)))") }
            else if Double(r) > Double(n) * 0.8 { out.append("\(lo) (\(ordinal(r)))") }
        }
        if me["old"] >= 5 { out.append("\(Int(me["old"])) starters are 30 or older") }
        if me["expiring"] >= 3 { out.append("\(Int(me["expiring"])) starters' contracts end by next summer") }
        return out
    }

    /// Head to head: who is better on each metric, and a one-line summary.
    public static func summary(_ a: TeamProfile, vs b: TeamProfile) -> String {
        let keys = ["gk": "goal", "def": "defence", "mid": "midfield", "att": "attack", "pace": "pace",
                    "technique": "technique", "work": "work rate", "physical": "physicality", "aerial": "the air", "depth": "depth"]
        var better: [String] = [], worse: [String] = []
        for (id, word) in keys.sorted(by: { $0.key < $1.key }) {
            let d = a[id] - b[id]
            if d >= 0.5 { better.append(word) } else if d <= -0.5 { worse.append(word) }
        }
        var parts: [String] = []
        if !better.isEmpty { parts.append("\(a.club) is stronger in " + better.joined(separator: ", ")) }
        if !worse.isEmpty { parts.append("weaker in " + worse.joined(separator: ", ")) }
        return parts.isEmpty ? "Very evenly matched." : parts.joined(separator: "; ") + "."
    }

    /// Position-by-position: each of `a`'s XI against the other team's player in the same line.
    public struct LineUp: Sendable, Identifiable {
        public var id: String { line }
        public let line: String
        public let mine: Double
        public let theirs: Double
    }

    public static func lines(_ a: TeamProfile, _ b: TeamProfile) -> [LineUp] {
        [("Goalkeeper", "gk"), ("Defence", "def"), ("Midfield", "mid"), ("Attack", "att")].map {
            LineUp(line: $0.0, mine: a[$0.1], theirs: b[$0.1])
        }
    }

    // MARK: First team vs the whole club

    public struct Promotion: Sendable, Identifiable {
        public var id: String { slot }
        public let slot: String
        public let player: PlayerRow
        public let score: Double
        public let replaces: PlayerRow?
        public let replacedScore: Double
    }

    /// Your tactic filled from the whole club (youth teams included) against the first team alone:
    /// the two XI levels, and who from outside the first team would start, and instead of whom.
    public static func promotions(formation: Formation, firstTeam: [PlayerRow], wholeClub: [PlayerRow],
                                  meta: ExportMeta) -> (first: Double, club: Double, promotions: [Promotion]) {
        let a = TacticsAdvisor.fit(formation, squad: firstTeam, meta: meta, keepRoles: true)
        let b = TacticsAdvisor.fit(formation, squad: wholeClub, meta: meta, keepRoles: true)
        let inFirst = Set(firstTeam.map(\.id))
        var out: [Promotion] = []
        for (i, pick) in b.picks.enumerated() {
            guard let p = pick.player, !inFirst.contains(p.id) else { continue }
            let old = i < a.picks.count ? a.picks[i] : nil
            out.append(Promotion(slot: pick.slot.label, player: p, score: pick.score,
                                 replaces: old?.player, replacedScore: old?.score ?? 0))
        }
        return (a.level, b.level, out.sorted { ($0.score - $0.replacedScore) > ($1.score - $1.replacedScore) })
    }
}
