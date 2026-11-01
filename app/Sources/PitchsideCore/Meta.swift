import Foundation

/// "Meta score": how much a player's attributes are worth in FM's match engine, as opposed
/// to CA (which only says how much ability the game *charges* for them). The weights follow
/// the community match-engine testing published on FM-Arena (FM24/FM26): pace and
/// acceleration matter far more than anything else, then jumping reach, dribbling,
/// anticipation and work rate; crossing, marking, agility, decisions and technique add
/// very little. Approximate by nature, but it ranks players much closer to how they
/// actually perform than CA does. Result is on the 1–20 scale (keepers calibrated to it), plus a
/// 0–100 percentile within the player's division.
public enum Meta {
    static let outfield: [String: Double] = [
        "Pace": 5, "Acceleration": 5,
        "JumpingReach": 3, "Dribbling": 3, "Anticipation": 3, "WorkRate": 3,
        "Composure": 2, "Vision": 2, "Concentration": 2, "Positioning": 2,
        "Stamina": 1.5, "Determination": 1.5,
        "Finishing": 1, "FirstTouch": 1, "LongShots": 1, "Heading": 1, "Passing": 1, "Tackling": 1,
        "Bravery": 1, "OffTheBall": 1, "Teamwork": 1, "Balance": 1, "Strength": 1, "Leadership": 1,
        "Aggression": 0.5, "Flair": 0.5,
        "Crossing": 0.25, "Marking": 0.25, "Agility": 0.25, "Decisions": 0.25, "Technique": 0.25,
    ]

    static let goalkeeper: [String: Double] = [
        "Reflexes": 5, "AerialReach": 5, "Handling": 3, "OneOnOnes": 2, "CommandOfArea": 1.5,
        "Kicking": 1, "Communication": 1, "Anticipation": 1, "Concentration": 1, "Positioning": 1,
        "Acceleration": 1, "Pace": 1, "Agility": 1,
    ]

    public struct Resolved: Sendable {
        let outfield: [(Int, Double)]
        let goalkeeper: [(Int, Double)]
        let pressure: Int?
    }

    public static func resolve(_ meta: ExportMeta) -> Resolved {
        let idx = Dictionary(uniqueKeysWithValues: meta.playerAttrKeys.enumerated().map { ($1, $0) })
        func r(_ w: [String: Double]) -> [(Int, Double)] { w.compactMap { k, v in idx[k].map { ($0, v) } } }
        return Resolved(outfield: r(outfield), goalkeeper: r(goalkeeper),
                        pressure: meta.personalityKeys.firstIndex(of: "Pressure"))
    }

    public static func score(_ r: Resolved, attrs: [UInt8], personality: [UInt8]?, isGoalkeeper: Bool) -> Double {
        let weights = isGoalkeeper ? r.goalkeeper : r.outfield
        var sum = 0.0, w = 0.0
        for (i, wt) in weights where i < attrs.count {
            sum += Double(attrs[i]) * wt
            w += wt
        }
        guard w > 0 else { return 0 }
        var s = sum / w
        // Testing shows players with very low Pressure perform much worse: a quarter point per point below 8.
        if let pi = r.pressure, let p = personality, pi < p.count, p[pi] > 0, p[pi] < 8 { s -= 0.25 * Double(8 - Int(p[pi])) }
        return (max(0, s) * 10).rounded() / 10
    }

    /// Meta % against a chosen pool of meta values (0–100: share of the pool a player is better than).
    /// Pitchside uses the first-team players of your club's division, so Meta % says where a player
    /// would rank in your league.
    public static func rate(_ rows: inout [PlayerRow], against pool: [Double]) {
        let sorted = pool.sorted()
        guard sorted.count > 1 else { return }
        for i in rows.indices {
            var lo = 0, hi = sorted.count
            while lo < hi { let mid = (lo + hi) / 2; if sorted[mid] < rows[i].meta { lo = mid + 1 } else { hi = mid } }
            rows[i].metaRating = Int((100 * Double(lo) / Double(sorted.count)).rounded())
        }
    }

    /// Puts goalkeepers on the outfield scale (their weights give higher numbers: a keeper's 14 was
    /// worth an outfielder's 13) by matching the two distributions in the scan, then ranks everyone
    /// 0–100 within their division (and across the whole scan). Small scans (under 30 keepers or outfielders) keep the raw keeper numbers.
    /// Divisions with fewer scanned players than this use the whole scan for Meta %.
    static let minDivision = 40

    public static func calibrate(_ rows: inout [PlayerRow], keeper: [Bool]) {
        guard keeper.count == rows.count else { return }
        let gk = rows.indices.filter { keeper[$0] && rows[$0].meta > 0 }
        let of = rows.indices.filter { !keeper[$0] && rows[$0].meta > 0 }
        func stats(_ idx: [Int]) -> (Double, Double) {
            let v = idx.map { rows[$0].meta }
            let m = v.reduce(0, +) / Double(v.count)
            let sd = (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count)).squareRoot()
            return (m, sd)
        }
        if gk.count >= 30 && of.count >= 30 {
            let (mg, sg) = stats(gk), (mo, so) = stats(of)
            if sg > 0 {
                for i in gk { rows[i].meta = (max(0, mo + (rows[i].meta - mg) * so / sg) * 10).rounded() / 10 }
            }
        }
        func percentile(_ v: Double, in sorted: [Double]) -> Int {
            guard sorted.count > 1 else { return 50 }
            var lo = 0, hi = sorted.count                        // players strictly below
            while lo < hi { let mid = (lo + hi) / 2; if sorted[mid] < v { lo = mid + 1 } else { hi = mid } }
            return Int((100 * Double(lo) / Double(sorted.count - 1)).rounded())
        }
        let all = rows.map(\.meta).sorted()
        var byDivision = [String: [Double]]()
        for r in rows { if let d = r.person.div, !d.isEmpty { byDivision[d, default: []].append(r.meta) } }
        for k in byDivision.keys { byDivision[k]!.sort() }
        for i in rows.indices {
            rows[i].metaRatingAll = percentile(rows[i].meta, in: all)
            if let d = rows[i].person.div, let list = byDivision[d], list.count >= minDivision {
                rows[i].metaRating = percentile(rows[i].meta, in: list)
            } else {
                rows[i].metaRating = rows[i].metaRatingAll
            }
        }
    }
}

/// Ready-made searches plus the user's own saved ones.
public struct NamedFilter: Codable, Sendable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var filter: PlayerFilter
    public init(name: String, filter: PlayerFilter) { self.name = name; self.filter = filter }
}

public enum Presets {
    /// `season` = current season's year, `perUnit` = how many display-currency units make £1
    /// (money limits in filters are entered in the display currency).
    public static func builtIn(season: Int, perUnit: Double = 1) -> [NamedFilter] {
        func money(_ gbp: Double) -> Int { Int((gbp * perUnit).rounded()) }
        var wonder = PlayerFilter(); wonder.maxAge = 19; wonder.minPA = 150
        var gems = PlayerFilter(); gems.maxAge = 23; gems.minMeta = 13; gems.maxValue = money(5_000_000)
        var bargain = PlayerFilter(); bargain.minCA = 130; bargain.maxValue = money(15_000_000)
        var ending = PlayerFilter(); ending.expiringBy = season + 1; ending.minCA = 110
        var free = PlayerFilter(); free.freeAgentsOnly = true; free.minCA = 90
        var fast = PlayerFilter(); fast.rules = [AttributeRule(key: "Pace", min: 15), AttributeRule(key: "Acceleration", min: 15)]
        var risers = PlayerFilter(); risers.minGrowth = 5
        var newgens = PlayerFilter(); newgens.onlyNew = true; newgens.maxAge = 18
        return [
            NamedFilter(name: "Wonderkids (≤19, PA 150+)", filter: wonder),
            NamedFilter(name: "Hidden gems (≤23, meta 13+, cheap)", filter: gems),
            NamedFilter(name: "Bargain starters (CA 130+, ≤£15M)", filter: bargain),
            NamedFilter(name: "Contracts ending by \(season + 1)", filter: ending),
            NamedFilter(name: "Free agents", filter: free),
            NamedFilter(name: "Fast (Pace & Acceleration 15+)", filter: fast),
            NamedFilter(name: "Rising (+5 CA since reference scan)", filter: risers),
            NamedFilter(name: "New regens since last scan", filter: newgens),
        ]
    }
}
