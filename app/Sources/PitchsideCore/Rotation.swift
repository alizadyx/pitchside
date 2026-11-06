import Foundation

/// Rotation planner: two or three XIs for the same tactic that share out the starts, for packed fixture lists.
///
/// Rules (agreed with the user):
/// - outfield players start at most `matches - 1` of the planned matches (2 of 3, 1 of 2) where the squad allows;
/// - the goalkeeper is exempt (keepers barely tire in FM) and so are players you lock ("always starts");
/// - players marked unavailable are left out;
/// - a player may cover a position he's only accomplished at (familiarity 12–14) when that keeps the rotation
///   going; he's scored lower there and the pick is flagged.
public enum Rotation {
    public struct Settings: Sendable, Equatable {
        public var matches = 3
        public var unavailable: Set<UInt32> = []
        public var locked: Set<UInt32> = []
        public init() {}
        public init(matches: Int, unavailable: Set<UInt32> = [], locked: Set<UInt32> = []) {
            self.matches = matches; self.unavailable = unavailable; self.locked = locked
        }
        /// Most starts for a non-exempt player.
        public var cap: Int { max(1, matches - 1) }
    }

    public struct Pick: Sendable, Identifiable {
        public var id: String { slot.label }
        public let slot: Slot
        public let player: PlayerRow?
        public let score: Double
        /// Natural in the position (familiarity 15+); false = accomplished cover.
        public let natural: Bool
        /// Starts more than the cap allows (the squad had no one else).
        public let overCap: Bool
    }

    public struct XI: Sendable, Identifiable {
        public let id: Int
        public let picks: [Pick]
        /// Average score of the filled slots.
        public let level: Double
        public var empty: Int { picks.filter { $0.player == nil }.count }
        public var cover: Int { picks.filter { $0.player != nil && !$0.natural }.count }
    }

    public struct Load: Sendable, Identifiable {
        public var id: UInt32 { row.id }
        public let row: PlayerRow
        public let starts: Int
        /// Which XIs (0-based) he starts.
        public let inXIs: [Int]
        public let locked: Bool
        public let unavailable: Bool
        public let overCap: Bool
    }

    public struct Plan: Sendable {
        public let xis: [XI]
        /// Level of the best XI with no rotation, for comparison.
        public let bestLevel: Double
        public let loads: [Load]
        public let cap: Int
    }

    /// Big enough to outweigh any score difference, so the cap is kept whenever someone else can play.
    static let overCapPenalty = 6.0

    public static func plan(formation: Formation, squad: [PlayerRow], meta: ExportMeta, settings: Settings) -> Plan {
        let slots = orderedSlots(formation.slots)
        let posIndex = Dictionary(uniqueKeysWithValues: meta.positionKeys.enumerated().map { ($1, $0) })
        let n = slots.count, m = squad.count
        let matches = max(1, settings.matches)

        // Raw score of each player in each slot (nil = can't play there), and whether he's a natural.
        var raw = Array(repeating: [Double?](repeating: nil, count: m), count: n)
        var natural = Array(repeating: [Bool](repeating: false, count: m), count: n)
        for (si, slot) in slots.enumerated() {
            let ri = SquadBuilder.roleIndex(slot.role), oi = SquadBuilder.roleIndex(slot.oop)
            guard ri != nil || oi != nil else { continue }
            for (pi, r) in squad.enumerated() where !settings.unavailable.contains(r.id) {
                let f = SquadBuilder.familiarity(r, posIndex[slot.position])
                guard f >= 12, let pen = TacticsAdvisor.familiarityPenalty(f) else { continue }
                raw[si][pi] = SquadBuilder.slotScore(r, ip: ri, oop: oi) - pen - SquadBuilder.oopCost(r, slot, posIndex)
                natural[si][pi] = f >= SquadBuilder.naturalFamiliarity
            }
        }
        func exempt(_ si: Int, _ pi: Int) -> Bool { slots[si].position == "GK" || settings.locked.contains(squad[pi].id) }

        // Reference: the best XI with everyone available and no rotation.
        let bestXI = TacticsAdvisor.optimalAssignment(slots: n, players: m) { raw[$0][$1] }
        let bestLevel = level(bestXI.enumerated().compactMap { si, p in p.flatMap { raw[si][$0] } })

        // Solve one match given how often each player starts the *other* matches.
        func solve(otherStarts: [Int]) -> [Int?] {
            TacticsAdvisor.optimalAssignment(slots: n, players: m) { si, pi in
                guard let v = raw[si][pi] else { return nil }
                if settings.locked.contains(squad[pi].id) { return v + 50 }       // locked: always in his best slot
                if exempt(si, pi) { return v }
                let k = otherStarts[pi]
                // Spread starts: a small cost per start elsewhere, a large one past the cap.
                return v - 0.15 * Double(k) - (k >= settings.cap ? overCapPenalty : 0)
            }
        }
        var assignment: [[Int?]] = []
        var starts = [Int](repeating: 0, count: m)
        for _ in 0..<matches {
            let a = solve(otherStarts: starts)
            for p in a.compactMap({ $0 }) { starts[p] += 1 }
            assignment.append(a)
        }
        // Re-plan each match against the others a few times, so match 1 doesn't take all the best players.
        for _ in 0..<4 {
            for k in 0..<matches {
                for p in assignment[k].compactMap({ $0 }) { starts[p] -= 1 }
                let a = solve(otherStarts: starts)
                for p in a.compactMap({ $0 }) { starts[p] += 1 }
                assignment[k] = a
            }
        }

        // Even the XIs out: swapping who plays a slot between two XIs keeps everyone's number of starts,
        // so it costs nothing in rotation. Keep swapping while the levels move closer together.
        func xiLevel(_ a: [Int?]) -> Double {
            let v = a.enumerated().compactMap { si, p in p.flatMap { raw[si][$0] } }
            return v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
        }
        func spread(_ all: [[Int?]]) -> Double {
            let l = all.map(xiLevel), mean = l.reduce(0, +) / Double(max(1, l.count))
            return l.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        }
        if matches > 1 {
            var improved = true, rounds = 0
            while improved && rounds < 50 {
                improved = false; rounds += 1
                for si in 0..<n {
                    for i in 0..<matches {
                        for j in (i + 1)..<matches {
                            guard let pi = assignment[i][si], let pj = assignment[j][si], pi != pj,
                                  !assignment[j].contains(pi), !assignment[i].contains(pj) else { continue }
                            let before = spread(assignment)
                            assignment[i][si] = pj; assignment[j][si] = pi
                            if spread(assignment) < before - 1e-9 { improved = true }
                            else { assignment[i][si] = pi; assignment[j][si] = pj }
                        }
                    }
                }
            }
        }

        // Count starts that count towards the cap (not in goal, not locked).
        var capped = [Int](repeating: 0, count: m)
        for a in assignment { for (si, p) in a.enumerated() { if let p, !exempt(si, p) { capped[p] += 1 } } }

        var xis: [XI] = assignment.enumerated().map { k, a in
            let picks: [Pick] = slots.enumerated().map { si, slot in
                guard let p = a[si], let v = raw[si][p] else {
                    return Pick(slot: slot, player: nil, score: 0, natural: false, overCap: false)
                }
                return Pick(slot: slot, player: squad[p], score: (v * 10).rounded() / 10, natural: natural[si][p],
                            overCap: !exempt(si, p) && capped[p] > settings.cap)
            }
            return XI(id: k, picks: picks, level: level(picks.filter { $0.player != nil }.map(\.score)))
        }
        // Strongest first: use it for the toughest fixture.
        xis.sort { $0.level > $1.level }
        xis = xis.enumerated().map { XI(id: $0.offset, picks: $0.element.picks, level: $0.element.level) }

        var inXIs = [UInt32: [Int]]()
        for xi in xis { for p in xi.picks { if let r = p.player { inXIs[r.id, default: []].append(xi.id) } } }
        let loads: [Load] = squad.map { r in
            let i = squad.firstIndex { $0.id == r.id }!
            return Load(row: r, starts: inXIs[r.id]?.count ?? 0, inXIs: inXIs[r.id] ?? [],
                        locked: settings.locked.contains(r.id), unavailable: settings.unavailable.contains(r.id),
                        overCap: capped[i] > settings.cap)
        }
        .sorted { a, b in a.starts != b.starts ? a.starts > b.starts : a.row.name < b.row.name }
        return Plan(xis: xis, bestLevel: bestLevel, loads: loads, cap: settings.cap)
    }

    /// Goalkeeper first, then defence to attack, left to right: the order of an FM team sheet.
    public static func orderedSlots(_ slots: [Slot]) -> [Slot] {
        let pts = PitchLayout.points(for: slots)
        return slots.sorted { a, b in
            let pa = pts[a.label], pb = pts[b.label]
            let ya = pa?.y ?? 0, yb = pb?.y ?? 0
            if abs(ya - yb) > 0.01 { return ya > yb }
            return (pa?.x ?? 0.5) < (pb?.x ?? 0.5)
        }
    }

    static func level(_ scores: [Double]) -> Double {
        scores.isEmpty ? 0 : ((scores.reduce(0, +) / Double(scores.count)) * 10).rounded() / 10
    }
}
