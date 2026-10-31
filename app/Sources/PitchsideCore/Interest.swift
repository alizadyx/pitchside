import Foundation

/// How keen a player would be to join a club, on FM's scale. FM works this out live when you search
/// and does not store it, so this is an estimate built from the same ingredients the game uses:
/// how big your club and league are compared with his, how famous he is, his ambition and loyalty,
/// age, transfer status and contract.
public enum InterestLevel: Int, Comparable, Sendable, CaseIterable, Identifiable {
    case unlikely = 0, doubtful, persuadable, interested

    public var id: Int { rawValue }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var name: String {
        switch self {
        case .interested: "Interested"
        case .persuadable: "Persuadable"
        case .doubtful: "Doubtful"
        case .unlikely: "Unlikely"
        }
    }
}

public struct InterestAssessment: Sendable {
    public let level: InterestLevel
    /// Your club's pull divided by what the player needs; ≥ 1 means a step up for him. Used for sorting.
    public let score: Double
    public let reasons: [String]
}

public struct InterestModel: Sendable {
    /// Club → typical reputation of its 16 most famous players (0–10,000).
    public let clubLevel: [String: Double]
    /// Division → typical level of its clubs.
    public let leagueLevel: [String: Double]
    let clubLeague: [String: String]
    let ambitionIdx: Int?
    let loyaltyIdx: Int?

    // Thresholds on the adjusted score.
    static let interested = 0.95, persuadable = 0.89, doubtful = 0.82

    /// Build from one side (men's or women's) of the database.
    public init(rows: [PlayerRow], meta: ExportMeta) {
        var reps: [String: [Int]] = [:]
        var league: [String: [String: Int]] = [:]
        for r in rows {
            guard let c = r.person.club, !c.isEmpty else { continue }
            reps[c, default: []].append(r.person.rep ?? 0)
            if let d = r.person.div, !d.isEmpty { league[c, default: [:]][d, default: 0] += 1 }
        }
        var clubLevel: [String: Double] = [:]
        for (c, list) in reps {
            let top = list.sorted(by: >).prefix(16)
            clubLevel[c] = Double(top[top.count / 2])
        }
        var clubLeague: [String: String] = [:]
        for (c, counts) in league { clubLeague[c] = counts.max { $0.value < $1.value }?.key }
        var byLeague: [String: [Double]] = [:]
        for (c, d) in clubLeague { if let l = clubLevel[c] { byLeague[d, default: []].append(l) } }
        // A league is as attractive as its upper half.
        var leagueLevel: [String: Double] = [:]
        for (d, levels) in byLeague {
            let s = levels.sorted(by: >)
            let upper = s.prefix(max(1, s.count / 2))
            leagueLevel[d] = upper.reduce(0, +) / Double(upper.count)
        }
        self.clubLevel = clubLevel
        self.leagueLevel = leagueLevel
        self.clubLeague = clubLeague
        ambitionIdx = meta.personalityKeys.firstIndex(of: "Ambition")
        loyaltyIdx = meta.personalityKeys.firstIndex(of: "Loyalty")
    }

    /// How attractive a club is: mostly the club itself, partly its league.
    public func pull(_ club: String) -> Double {
        let c = clubLevel[club] ?? 0
        guard let d = clubLeague[club], let l = leagueLevel[d] else { return c }
        return 0.7 * c + 0.3 * l
    }

    public func assess(_ r: PlayerRow, joining club: String, season: Int) -> InterestAssessment? {
        let dest = pull(club)
        guard dest > 0 else { return nil }
        if r.person.club == club || r.person.own == club { return nil }
        let owner = r.person.own ?? r.person.club ?? ""      // a loanee is bought from his owner
        let freeAgent = owner.isEmpty
        let src = freeAgent ? 0 : pull(owner)
        let own = Double(r.person.rep ?? 0) * 0.92
        let need = max(src, own, 1)
        var score = dest / need
        var reasons: [String] = []

        if src > dest * 1.03 { reasons.append("Plays for a bigger club") }
        else if src > 0 && src < dest * 0.9 { reasons.append("Your club is a step up") }
        if own > src && own > dest * 1.03 { reasons.append("He is more famous than your club") }

        let p = r.person.p
        func trait(_ i: Int?) -> Int? { i.flatMap { j in p.flatMap { j < $0.count ? Int($0[j]) : nil } } }
        if let a = trait(ambitionIdx), a > 0 {
            score += Double(10 - a) * 0.01
            if a >= 16 && score < 1 { reasons.append("Very ambitious") }
            else if a <= 7 { reasons.append("Not very ambitious") }
        }
        if let l = trait(loyaltyIdx), l >= 15, src >= dest {
            score -= 0.04
            reasons.append("Loyal to his club")
        }
        if r.age >= 33 { score += 0.10; reasons.append("Veteran, open to a move") }
        else if r.age >= 30 { score += 0.05 }
        if r.person.lst == true { score += 0.12; reasons.append("Transfer-listed") }
        if freeAgent { score += 0.10; reasons.append("Free agent") }
        else if let e = r.person.exp, !e.isEmpty, e <= "\(season + 1)-06-30" {
            score += 0.04; reasons.append("Contract running down")
        }

        let level: InterestLevel = score >= Self.interested ? .interested
            : score >= Self.persuadable ? .persuadable
            : score >= Self.doubtful ? .doubtful : .unlikely
        return InterestAssessment(level: level, score: score, reasons: reasons)
    }
}
