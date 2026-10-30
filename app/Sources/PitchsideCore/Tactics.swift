import Foundation

/// Smart tactics for your squad, built on FM27's In Possession / Out of Possession roles:
/// the best formation and roles, set-piece takers and captains, and team instructions.
/// Everything is worked out from attributes only, so it explains itself with the numbers it used.
public enum TacticsAdvisor {

    // MARK: Best XI and formation

    /// One position of a suggested XI.
    public struct Pick: Sendable, Identifiable {
        public var id: String { slot.label }
        public let slot: Slot            // position with the suggested IP and OOP roles filled in
        public let player: PlayerRow?
        public let ipScore: Double
        public let oopScore: Double
        public let score: Double         // blended, as in the squad builder
        public let familiarity: UInt8
        /// Next-best IP roles for this player here, for a quick alternative.
        public let alternatives: [(code: String, score: Double)]
    }

    public struct FormationFit: Sendable, Identifiable {
        public var id: String { formation.name }
        public let formation: Formation  // with the suggested roles
        public let picks: [Pick]
        public let bench: [PlayerRow]    // best of the rest, for depth
        public let level: Double         // average XI score
        public let depth: Double         // average score of the best backup per position
        public let outOfPosition: Int    // picks below natural familiarity
        public var rating: Double { level - 0.4 * Double(outOfPosition) + 0.1 * depth }
    }

    /// Below natural (15) a player can still be used, at a cost: accomplished (12–14) −0.8,
    /// unconvincing (9–11) −2. Lower than that is not considered.
    static func familiarityPenalty(_ f: UInt8) -> Double? {
        switch f {
        case 15...: 0
        case 12...14: 0.8
        case 9...11: 2
        default: nil
        }
    }

    /// "Creator" roles: two is plenty in one XI.
    static let playmakers: Set<String> = ["DLP", "B2BP", "MP", "AP", "PWB", "PW", "F9", "FR", "ACB", "BPGK"]
    /// Roles that are fine to repeat (two centre-backs, two full-backs…).
    static let repeatable: Set<String> = ["GK", "CB", "BPCB", "NNCB", "WCB", "FB", "WB", "IWB", "DM", "CM", "WM", "W", "IF", "CF"]

    struct Choice { let ip: Int?; let oop: Int?; let ipScore: Double; let oopScore: Double; let blended: Double }

    static func bestRoles(_ r: PlayerRow, at position: String, excludingIP: Set<String> = []) -> Choice {
        var ip: Int? = nil, ipS = -1.0
        for role in Formations.roles(for: position) where !excludingIP.contains(role.code) {
            guard let i = Roles.index(role.code) else { continue }
            if r.roleScores[i] > ipS { ip = i; ipS = r.roleScores[i] }
        }
        var oop: Int? = nil, oopS = -1.0
        for role in Formations.oopRoles(for: position) {
            guard let i = Roles.index(role.code) else { continue }
            if r.roleScores[i] > oopS { oop = i; oopS = r.roleScores[i] }
        }
        return Choice(ip: ip, oop: oop, ipScore: max(ipS, 0), oopScore: max(oopS, 0),
                      blended: SquadBuilder.slotScore(r, ip: ip, oop: oop))
    }

    /// Picks the XI for a formation: every player in his best IP/OOP roles, the best possible combination.
    public static func fit(_ formation: Formation, squad: [PlayerRow], meta: ExportMeta) -> FormationFit {
        let posIndex = Dictionary(uniqueKeysWithValues: meta.positionKeys.enumerated().map { ($1, $0) })
        let slots = formation.slots
        let n = slots.count
        // value[s][p]: blended score minus familiarity penalty, nil when the player can't play there.
        var value = Array(repeating: [Double?](repeating: nil, count: squad.count), count: n)
        var fam = Array(repeating: [UInt8](repeating: 0, count: squad.count), count: n)
        for (s, slot) in slots.enumerated() {
            for (p, r) in squad.enumerated() {
                let f = SquadBuilder.familiarity(r, posIndex[slot.position])
                fam[s][p] = f
                guard let pen = familiarityPenalty(f) else { continue }
                value[s][p] = bestRoles(r, at: slot.position).blended - pen
            }
        }
        // Best possible XI: maximum-weight assignment of players to slots (Hungarian method).
        func v(_ s: Int, _ p: Int?) -> Double { p.flatMap { value[s][$0] } ?? -8 }
        let assign = optimalAssignment(slots: n, players: squad.count) { value[$0][$1] }
        let used = Set(assign.compactMap { $0 })

        // Roles, keeping the XI balanced: at most two playmakers, no duplicate specialist roles.
        var picks: [Pick] = []
        var playmakerCount = 0
        var takenSpecial = Set<String>()
        var newSlots = slots
        // Fill strongest players first so they keep their favourite role.
        let order = (0..<n).sorted { v($0, assign[$0]) > v($1, assign[$1]) }
        var bySlot = [Int: Pick]()
        for s in order {
            let slot = slots[s]
            guard let p = assign[s] else {
                bySlot[s] = Pick(slot: slot, player: nil, ipScore: 0, oopScore: 0, score: 0, familiarity: 0, alternatives: [])
                continue
            }
            let r = squad[p]
            var excluded = takenSpecial
            if playmakerCount >= 2 { excluded.formUnion(playmakers) }
            var c = bestRoles(r, at: slot.position, excludingIP: excluded)
            let unrestricted = bestRoles(r, at: slot.position)
            if c.ip == nil || unrestricted.ipScore - c.ipScore > 0.8 { c = unrestricted }   // not worth the sacrifice
            let ipCode = c.ip.map { Roles.all[$0].code } ?? slot.role
            let oopCode = c.oop.map { Roles.all[$0].code } ?? slot.oop
            if playmakers.contains(ipCode) { playmakerCount += 1 }
            if !repeatable.contains(ipCode) { takenSpecial.insert(ipCode) }
            newSlots[s].role = ipCode; newSlots[s].oop = oopCode
            let alts = Formations.roles(for: slot.position)
                .compactMap { role -> (String, Double)? in
                    guard role.code != ipCode, let i = Roles.index(role.code) else { return nil }
                    return (role.code, r.roleScores[i])
                }
                .sorted { $0.1 > $1.1 }.prefix(2)
            let pen = familiarityPenalty(fam[s][p]) ?? 0
            bySlot[s] = Pick(slot: newSlots[s], player: r, ipScore: c.ipScore, oopScore: c.oopScore,
                             score: c.blended - pen, familiarity: fam[s][p], alternatives: alts.map { (code: $0.0, score: $0.1) })
        }
        picks = (0..<n).compactMap { bySlot[$0] }

        // Depth: best unused player per position.
        var depthScores: [Double] = []
        for (s, _) in slots.enumerated() {
            let best = squad.indices.filter { !used.contains($0) }.compactMap { value[s][$0] }.max()
            depthScores.append(best ?? 0)
        }
        let bench = squad.indices.filter { !used.contains($0) }
            .map { squad[$0] }.sorted { $0.bestRoleScore > $1.bestRoleScore }.prefix(9)
        let filled = picks.filter { $0.player != nil }
        let level = filled.isEmpty ? 0 : filled.map(\.score).reduce(0, +) / Double(n)
        let depth = depthScores.isEmpty ? 0 : depthScores.reduce(0, +) / Double(depthScores.count)
        let oop = picks.filter { $0.player != nil && $0.familiarity < 15 }.count
        return FormationFit(formation: Formation(name: formation.name, slots: newSlots), picks: picks,
                            bench: Array(bench), level: level, depth: depth, outOfPosition: oop)
    }

    /// Assigns each slot at most one player, maximising the total value; nil where nobody can play.
    /// Hungarian algorithm on an n × m cost matrix (n slots ≤ m columns, padded with dummies).
    static func optimalAssignment(slots n: Int, players: Int, value: (Int, Int) -> Double?) -> [Int?] {
        guard n > 0 else { return [] }
        let m = max(players, n)
        let blocked = 1000.0
        func cost(_ i: Int, _ j: Int) -> Double {
            guard j < players, let v = value(i, j) else { return blocked }
            return -v
        }
        // e-maxx formulation, 1-based.
        var u = [Double](repeating: 0, count: n + 1), w = [Double](repeating: 0, count: m + 1)
        var p = [Int](repeating: 0, count: m + 1), way = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            p[0] = i
            var j0 = 0
            var minv = [Double](repeating: .infinity, count: m + 1)
            var usedCol = [Bool](repeating: false, count: m + 1)
            repeat {
                usedCol[j0] = true
                let i0 = p[j0]
                var delta = Double.infinity, j1 = 0
                for j in 1...m where !usedCol[j] {
                    let cur = cost(i0 - 1, j - 1) - u[i0] - w[j]
                    if cur < minv[j] { minv[j] = cur; way[j] = j0 }
                    if minv[j] < delta { delta = minv[j]; j1 = j }
                }
                for j in 0...m {
                    if usedCol[j] { u[p[j]] += delta; w[j] -= delta } else { minv[j] -= delta }
                }
                j0 = j1
            } while p[j0] != 0
            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }
        var out = [Int?](repeating: nil, count: n)
        for j in 1...m where p[j] != 0 {
            let slot = p[j] - 1, player = j - 1
            if player < players, value(slot, player) != nil { out[slot] = player }
        }
        return out
    }

    /// Every formation fitted to the squad, best first.
    public static func rankFormations(_ formations: [Formation], squad: [PlayerRow], meta: ExportMeta) -> [FormationFit] {
        formations.map { fit($0, squad: squad, meta: meta) }.sorted { $0.rating > $1.rating }
    }

    // MARK: Set pieces and captain

    public struct Taker: Sendable, Identifiable {
        public var id: UInt32 { player.id }
        public let player: PlayerRow
        public let score: Double
        public let note: String
    }

    public struct SetPieces: Sendable {
        public let leftCorners: [Taker]
        public let rightCorners: [Taker]
        public let directFreeKicks: [Taker]
        public let crossedFreeKicks: [Taker]
        public let penalties: [Taker]
        public let longThrows: [Taker]
        public let aerialTargets: [Taker]
        public let stayBack: [Taker]
        public let captains: [Taker]
    }

    struct Reader {
        let a: [String: Int]
        let p: [String: Int]
        init(_ meta: ExportMeta) {
            a = Dictionary(uniqueKeysWithValues: meta.playerAttrKeys.enumerated().map { ($1, $0) })
            p = Dictionary(uniqueKeysWithValues: meta.personalityKeys.enumerated().map { ($1, $0) })
        }
        func attr(_ r: PlayerRow, _ k: String) -> Double {
            guard let i = a[k], let v = r.person.a, i < v.count else { return 10 }
            return Double(v[i])
        }
        func pers(_ r: PlayerRow, _ k: String) -> Double? {
            guard let i = p[k], let v = r.person.p, i < v.count, v[i] > 0 else { return nil }
            return Double(v[i])
        }
        func mix(_ r: PlayerRow, _ w: [(String, Double)]) -> Double {
            let t = w.reduce(0) { $0 + $1.1 }
            return w.reduce(0) { $0 + attr(r, $1.0) * $1.1 } / t
        }
    }

    static func top(_ rows: [PlayerRow], _ n: Int, score: (PlayerRow) -> Double, note: (PlayerRow) -> String) -> [Taker] {
        rows.map { (r: $0, s: score($0)) }.sorted { $0.s > $1.s }.prefix(n)
            .map { Taker(player: $0.r, score: ($0.s * 10).rounded() / 10, note: note($0.r)) }
    }

    /// Takers come from the XI; penalties also look at the bench (subs take them late on).
    public static func setPieces(xi: [PlayerRow], bench: [PlayerRow], meta: ExportMeta) -> SetPieces {
        let R = Reader(meta)
        let outfield = xi.filter { !isKeeper($0) }
        func i(_ r: PlayerRow, _ k: String) -> Int { Int(R.attr(r, k)) }
        let cornerW: [(String, Double)] = [("Corners", 6), ("Crossing", 2.5), ("Technique", 1.5)]
        func foot(_ r: PlayerRow) -> String {
            let l = R.attr(r, "LeftFoot"), rt = R.attr(r, "RightFoot")
            return l >= 15 && rt >= 15 ? "two-footed" : l > rt ? "left-footed" : "right-footed"
        }
        // Inswingers: right-footed takers from the left, left-footed from the right.
        func corner(_ fromLeft: Bool) -> [Taker] {
            top(outfield, 3, score: { r in
                let f = fromLeft ? R.attr(r, "RightFoot") : R.attr(r, "LeftFoot")
                return R.mix(r, cornerW) + (f >= 15 ? 0.6 : f >= 11 ? 0 : -1.5)
            }, note: { r in "Corners \(i(r, "Corners")), Crossing \(i(r, "Crossing")), \(foot(r)) — \(fromLeft ? "inswinging from the left needs the right foot" : "inswinging from the right needs the left foot")" })
        }
        let direct = top(outfield, 3, score: { R.mix($0, [("FreeKicks", 6), ("LongShots", 2), ("Technique", 2)]) },
                         note: { "Free kicks \(i($0, "FreeKicks")), Long shots \(i($0, "LongShots")), Technique \(i($0, "Technique"))" })
        let crossed = top(outfield, 3, score: { R.mix($0, [("FreeKicks", 4), ("Crossing", 4), ("Technique", 2)]) },
                          note: { "Free kicks \(i($0, "FreeKicks")), Crossing \(i($0, "Crossing"))" })
        let penPool = outfield + bench.filter { !isKeeper($0) }
        let pens = top(penPool, 5, score: { r in
            R.mix(r, [("PenaltyTaking", 6), ("Composure", 3), ("Finishing", 1)]) + ((R.pers(r, "Pressure") ?? 10) - 10) * 0.05
        }, note: { r in
            var s = "Penalties \(i(r, "PenaltyTaking")), Composure \(i(r, "Composure"))"
            if let p = R.pers(r, "Pressure") { s += p >= 15 ? ", handles pressure well" : p <= 8 ? ", wilts under pressure" : "" }
            if !xi.contains(where: { $0.id == r.id }) { s += " (bench)" }
            return s
        })
        let throws_ = top(outfield.filter { R.attr($0, "LongThrows") >= 14 }, 2, score: { R.mix($0, [("LongThrows", 8), ("Strength", 2)]) },
                          note: { "Long throws \(i($0, "LongThrows"))" })
        let aerial = top(outfield, 4, score: { r in
            R.mix(r, [("Heading", 3.5), ("JumpingReach", 3.5), ("Strength", 1.5), ("Bravery", 1.5)])
                + Double(max(0, (r.person.ht ?? 180) - 180)) * 0.05
        }, note: { r in
            var s = "Heading \(i(r, "Heading")), Jumping reach \(i(r, "JumpingReach")), Strength \(i(r, "Strength"))"
            if let h = r.person.ht { s += ", \(h) cm" }
            return s
        })
        let targets = Set(aerial.prefix(3).map(\.player.id))
        let back = top(outfield.filter { !targets.contains($0.id) }, 2,
                       score: { R.mix($0, [("Pace", 3), ("Acceleration", 2), ("Anticipation", 2), ("Positioning", 2), ("Tackling", 1)]) },
                       note: { "Pace \(i($0, "Pace")), Anticipation \(i($0, "Anticipation")) — covers the counter" })
        // Captain: leadership first, then the personality that keeps a dressing room steady.
        let caps = top(xi, 3, score: { r in
            var s = R.attr(r, "Leadership") * 0.5 + R.attr(r, "Determination") * 0.15
            s += (R.pers(r, "Professionalism") ?? 10) * 0.12 + (R.pers(r, "Pressure") ?? 10) * 0.08
            s += (R.pers(r, "Temperament") ?? 10) * 0.05 + (R.pers(r, "Loyalty") ?? 10) * 0.05
            s += min(Double(max(r.age - 20, 0)), 10) * 0.05 + Double(min(r.person.rep ?? 0, 10000)) / 10000 * 0.5
            return s * 20 / 19.5
        }, note: { r in
            var s = "Leadership \(i(r, "Leadership")), Determination \(i(r, "Determination"))"
            if let p = R.pers(r, "Professionalism") { s += ", Professionalism \(Int(p))" }
            s += ", age \(r.age)"
            return s
        })
        return SetPieces(leftCorners: corner(true), rightCorners: corner(false), directFreeKicks: direct,
                         crossedFreeKicks: crossed, penalties: pens, longThrows: throws_, aerialTargets: aerial,
                         stayBack: back, captains: caps)
    }

    static func isKeeper(_ r: PlayerRow) -> Bool {
        guard let f = r.person.pos, !f.isEmpty else { return false }
        return f[0] >= 15 && (f.max() ?? 0) == f[0]
    }

    // MARK: Team instructions

    /// How the side usually goes into games; sets the mentality and which styles make sense.
    public enum Stance: Int, Sendable, CaseIterable, Identifiable {
        case favourites, even, underdogs
        public var id: Int { rawValue }
        public var title: String {
            switch self { case .favourites: "Usually favourites"; case .even: "Evenly matched"; case .underdogs: "Usually underdogs" }
        }
    }

    public struct Instruction: Sendable, Identifiable {
        public var id: String { phase + name }
        public let phase: String       // "In possession", "Out of possession", "Goalkeeper", "Set pieces"
        public let name: String        // FM27 instruction
        public let setting: String     // FM27 option
        public let reason: String
        public let strength: Double    // how clear-cut (0–1), for sorting and emphasis
    }

    public struct StyleFit: Sendable, Identifiable {
        public var id: String { name }
        public let name: String        // FM27 tactical style
        public let fit: Double         // 0–100
        public let why: String
    }

    public struct Profile: Sendable {
        public var base = 10.0        // average outfield attribute of the XI
        public var technique = 10.0, speed = 10.0, frontSpeed = 10.0, frontWork = 10.0, work = 10.0
        public var lineSpeed = 10.0, cbAerial = 10.0, cbPlaying = 10.0, fullbackAttack = 10.0, fullbackDefence = 10.0
        public var wideAttack = 10.0, flair = 10.0, longShots = 10.0, strikerAerial = 10.0, tackling = 10.0
        public var dribbling = 10.0, decisions = 10.0, gkDistribution = 10.0, setPieceThreat = 10.0, midDefence = 10.0
        public var leftSide = 0.0, rightSide = 0.0, centre = 0.0, temperament: Double? = nil
        public var hasWideAttackers = false, hasTargetForward = false, hasDeepPlaymaker = false, insideWide = false, insideFullbacks = false
    }

    public struct Instructions: Sendable {
        public let profile: Profile
        public let mentality: String
        public let mentalityReason: String
        public let styles: [StyleFit]
        public let items: [Instruction]
    }

    static func group(_ picks: [Pick], _ positions: Set<String>) -> [PlayerRow] {
        picks.filter { positions.contains($0.slot.position) }.compactMap(\.player)
    }

    public static func profile(_ fit: FormationFit, meta: ExportMeta) -> Profile {
        let R = Reader(meta)
        var P = Profile()
        let picks = fit.picks
        let outfield = picks.filter { $0.slot.position != "GK" }.compactMap(\.player)
        guard !outfield.isEmpty else { return P }
        func avg(_ rows: [PlayerRow], _ keys: [String]) -> Double {
            guard !rows.isEmpty else { return P.base }
            return rows.map { r in keys.map { R.attr(r, $0) }.reduce(0, +) / Double(keys.count) }.reduce(0, +) / Double(rows.count)
        }
        let all = ["Crossing", "Dribbling", "Finishing", "FirstTouch", "Heading", "LongShots", "Marking", "Passing", "Tackling",
                   "Technique", "Aggression", "Anticipation", "Bravery", "Composure", "Concentration", "Decisions", "Determination",
                   "Flair", "Leadership", "OffTheBall", "Positioning", "Teamwork", "Vision", "WorkRate", "Acceleration", "Agility",
                   "Balance", "JumpingReach", "NaturalFitness", "Pace", "Stamina", "Strength"]
        P.base = avg(outfield, all)
        let front = group(picks, ["ST", "AML", "AMR", "AMC"])
        let cbs = group(picks, ["DC"])
        let fbs = group(picks, ["DL", "DR", "WBL", "WBR"])
        let wide = group(picks, ["ML", "MR", "AML", "AMR", "WBL", "WBR"])
        let mids = group(picks, ["DM", "MC", "AMC"])
        let sts = group(picks, ["ST"])
        P.technique = avg(outfield, ["Passing", "FirstTouch", "Technique", "Composure", "Vision", "Decisions"])
        P.speed = avg(outfield, ["Pace", "Acceleration"])
        P.frontSpeed = avg(front.isEmpty ? outfield : front, ["Pace", "Acceleration", "OffTheBall"])
        P.frontWork = avg(front.isEmpty ? outfield : front, ["WorkRate", "Stamina", "Aggression", "Teamwork"])
        P.work = avg(outfield, ["WorkRate", "Stamina", "Teamwork", "NaturalFitness"])
        P.lineSpeed = avg(cbs, ["Pace", "Acceleration", "Anticipation"])
        P.cbAerial = avg(cbs, ["Heading", "JumpingReach", "Strength"])
        P.cbPlaying = avg(cbs, ["Passing", "Composure", "FirstTouch", "Technique"])
        P.fullbackAttack = avg(fbs, ["Crossing", "Stamina", "WorkRate", "Dribbling", "OffTheBall"])
        P.fullbackDefence = avg(fbs, ["Tackling", "Marking", "Positioning", "Pace"])
        P.wideAttack = avg(wide, ["Crossing", "Dribbling", "Pace", "Acceleration"])
        P.flair = avg(outfield, ["Flair", "Vision"])
        P.longShots = avg(mids + front, ["LongShots"])
        P.strikerAerial = avg(sts, ["Heading", "JumpingReach", "Strength"])
        P.tackling = avg(outfield, ["Tackling", "Aggression", "Bravery"])
        P.dribbling = avg(front + wide, ["Dribbling", "Flair"])
        P.decisions = avg(outfield, ["Decisions", "Anticipation", "FirstTouch", "Technique"])
        P.midDefence = avg(mids, ["Tackling", "Marking", "Positioning", "Anticipation"])
        if let gk = picks.first(where: { $0.slot.position == "GK" })?.player {
            P.gkDistribution = ["Kicking", "Passing", "FirstTouch", "Composure"].map { R.attr(gk, $0) }.reduce(0, +) / 4
        }
        let heads = outfield.map { R.mix($0, [("Heading", 1), ("JumpingReach", 1)]) }.sorted(by: >).prefix(3)
        P.setPieceThreat = heads.isEmpty ? 10 : heads.reduce(0, +) / Double(heads.count)
        func side(_ pos: Set<String>) -> Double {
            let s = picks.filter { pos.contains($0.slot.position) && $0.player != nil }.map(\.score)
            return s.isEmpty ? 0 : s.reduce(0, +) / Double(s.count)
        }
        P.leftSide = side(["DL", "WBL", "ML", "AML"])
        P.rightSide = side(["DR", "WBR", "MR", "AMR"])
        P.centre = side(["MC", "AMC", "DM"])
        let temps = outfield.compactMap { R.pers($0, "Temperament") }
        P.temperament = temps.isEmpty ? nil : temps.reduce(0, +) / Double(temps.count)
        let codes = Set(picks.map(\.slot.role))
        P.hasWideAttackers = picks.contains { ["ML", "MR", "AML", "AMR", "WBL", "WBR"].contains($0.slot.position) }
        P.hasTargetForward = codes.contains("TF")
        P.hasDeepPlaymaker = !codes.isDisjoint(with: ["DLP", "B2BP", "MP"])
        P.insideWide = !codes.isDisjoint(with: ["IF", "IW", "PW", "WF"])
        P.insideFullbacks = !codes.isDisjoint(with: ["IFB", "IWB", "PWB"])
        return P
    }

    public static func instructions(_ fit: FormationFit, meta: ExportMeta, stance: Stance) -> Instructions {
        let P = profile(fit, meta: meta)
        let b = P.base
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        func vs(_ label: String, _ x: Double) -> String { "\(label) \(f(x)) vs squad average \(f(b))" }
        var out: [Instruction] = []
        func add(_ phase: String, _ name: String, _ setting: String, _ reason: String, _ d: Double) {
            out.append(Instruction(phase: phase, name: name, setting: setting, reason: reason, strength: min(1, abs(d) / 3)))
        }
        let ip = "In possession", op = "Out of possession", gk = "Goalkeeper", sp = "Set pieces"

        // In possession
        let tech = P.technique - b
        let fast = P.frontSpeed - b
        if tech >= 2 { add(ip, "Passing Directness", "Much Shorter", vs("Passing, first touch, technique & composure", P.technique), tech) }
        else if tech >= 0.8 { add(ip, "Passing Directness", "Shorter", vs("Passing, first touch, technique & composure", P.technique), tech) }
        else if fast >= 1.2 && tech < 0.3 { add(ip, "Passing Directness", "More Direct", "Fast forwards (\(f(P.frontSpeed))) but technique only \(f(P.technique)) — get the ball to them early", fast) }
        let dec = P.decisions - b
        if dec >= 1 { add(ip, "Tempo", "Higher", vs("Decisions, anticipation, first touch & technique", P.decisions), dec) }
        else if dec <= -1 { add(ip, "Tempo", "Lower", vs("Decisions, anticipation, first touch & technique", P.decisions) + " — give them time", dec) }
        if !P.hasWideAttackers { add(ip, "Team Width", "Narrower", "No wide players in this shape", 2) }
        else if P.wideAttack - b >= 1 { add(ip, "Team Width", "Wider", vs("Wide players' crossing, dribbling & pace", P.wideAttack), P.wideAttack - b) }
        if fast >= 1.5 { add(ip, "Attacking Transition", "Counter", vs("Forwards' pace, acceleration & movement", P.frontSpeed), fast) }
        else if tech >= 1 && fast < 0.5 { add(ip, "Attacking Transition", "Hold Shape", "Technical side without quick forwards — keep the ball and build", tech) }
        let fl = P.flair - b
        if fl >= 1.5 { add(ip, "Creative Freedom", "Be More Expressive", vs("Flair & vision", P.flair), fl) }
        else if fl <= -1.5 { add(ip, "Creative Freedom", "Be More Disciplined", vs("Flair & vision", P.flair), fl) }
        if fast >= 1.2 { add(ip, "Pass Reception", "Into Space", "Forwards are quick (\(f(P.frontSpeed))) — play balls in behind", fast) }
        else if tech >= 1 && fast < 0 { add(ip, "Pass Reception", "Into Feet", "Good on the ball (\(f(P.technique))) but not quick up front (\(f(P.frontSpeed)))", tech) }
        if P.dribbling - b >= 1.5 { add(ip, "Dribbling", "Run At Defence", vs("Attackers' dribbling & flair", P.dribbling), P.dribbling - b) }
        let lr = P.leftSide - P.rightSide
        if P.hasWideAttackers && lr >= 0.8 { add(ip, "Progress Through", "Focus Play Down The Left", "Left side \(f(P.leftSide)) vs right \(f(P.rightSide))", lr) }
        else if P.hasWideAttackers && lr <= -0.8 { add(ip, "Progress Through", "Focus Play Down The Right", "Right side \(f(P.rightSide)) vs left \(f(P.leftSide))", -lr) }
        else if P.centre - max(P.leftSide, P.rightSide) >= 0.8 { add(ip, "Progress Through", "Focus Play Down The Middle", "Central players \(f(P.centre)) are your strongest line", P.centre - max(P.leftSide, P.rightSide)) }
        let air = P.strikerAerial - b
        if P.hasWideAttackers {
            if air >= 1.5 { add(ip, "Crossing Style", "Floated Crosses", vs("Strikers' heading, jumping & strength", P.strikerAerial), air) }
            else if air <= -1 { add(ip, "Crossing Style", "Low Crosses", "Strikers are not aerial threats (\(f(P.strikerAerial)))", air) }
            else if P.wideAttack - b >= 1 { add(ip, "Crossing Style", "Whipped Crosses", "Good crossers out wide (\(f(P.wideAttack)))", P.wideAttack - b) }
        }
        let ls = P.longShots - b
        if ls >= 1.5 { add(ip, "Shots From Distance", "Shoot On Sight", vs("Midfield & attack long shots", P.longShots), ls) }
        else if ls <= -1 { add(ip, "Shots From Distance", "Work Ball Into Box", vs("Long shots", P.longShots), ls) }
        let cbp = P.cbPlaying - b
        if cbp >= 0.5 && P.gkDistribution >= max(11, b - 1) { add(ip, "Build-Up Strategy", "Play Through Press", "Centre-backs on the ball \(f(P.cbPlaying)), keeper distribution \(f(P.gkDistribution))", cbp + 1) }
        else if cbp <= -1 { add(ip, "Build-Up Strategy", "Bypass Press", "Centre-backs are uncomfortable on the ball (\(f(P.cbPlaying)))", cbp) }
        if P.fullbackAttack - b >= 1 && P.insideWide && !P.insideFullbacks {
            add(ip, "Supporting Runs", "Look For Overlap", "Wide forwards come inside and full-backs can get forward (\(f(P.fullbackAttack)))", P.fullbackAttack - b)
        } else if P.insideFullbacks && !P.insideWide && P.hasWideAttackers {
            add(ip, "Supporting Runs", "Look For Underlap", "Full-backs move inside while wingers hold the width", 1.5)
        }

        // Goalkeeper
        if cbp >= 0.5 && P.gkDistribution >= max(11, b - 1) {
            add(gk, "Goal Kicks", "Short", "Keeper (\(f(P.gkDistribution))) and centre-backs (\(f(P.cbPlaying))) can play out", cbp + 1)
            add(gk, "Distribute To", P.hasDeepPlaymaker ? "Playmaker" : "Centre-Backs",
                P.hasDeepPlaymaker ? "You have a deep playmaker to receive it" : "Centre-backs are your best passers at the back", 1)
        } else if P.hasTargetForward || air >= 1.5 {
            add(gk, "Goal Kicks", "Long", "Aerial strikers (\(f(P.strikerAerial))) can win long balls", max(air, 1))
            add(gk, "Distribute To", "Target Forward",
                P.hasTargetForward ? "Aim for your Target Forward" : "Your strikers win headers (\(f(P.strikerAerial)))", max(air, 1))
        }

        // Out of possession
        let fw = P.frontWork - b
        if fw >= 1 { add(op, "Line Of Engagement", "High", vs("Forwards' work rate, stamina, aggression & teamwork", P.frontWork), fw) }
        else if fw <= -1 { add(op, "Line Of Engagement", "Low", vs("Forwards' work rate & stamina", P.frontWork) + " — they won't press well", fw) }
        let ln = P.lineSpeed - b
        if ln >= 1 { add(op, "Defensive Line", "Higher", vs("Centre-backs' pace, acceleration & anticipation", P.lineSpeed), ln) }
        else if ln <= -1 { add(op, "Defensive Line", "Deeper", vs("Centre-backs' pace & anticipation", P.lineSpeed) + " — avoid balls in behind", ln) }
        if ln >= 1.5 { add(op, "Defensive Line Behaviour", "Hold Line", "Quick, alert centre-backs can step up together", ln) }
        else if ln <= -1.5 { add(op, "Defensive Line Behaviour", "Drop Off", "Slow centre-backs (\(f(P.lineSpeed))) need a head start", ln) }
        let wk = P.work - b
        if wk >= 1 { add(op, "Pressing Intensity", "Higher", vs("Work rate, stamina, teamwork & fitness", P.work), wk) }
        else if wk <= -1 { add(op, "Pressing Intensity", "Lower", vs("Work rate & stamina", P.work), wk) }
        if wk >= 1 && P.speed - b >= 0 { add(op, "Defensive Transition", "Counter-Press", "Hard-working (\(f(P.work))) and quick enough (\(f(P.speed))) to win it back straight away", wk) }
        else if wk <= -0.8 { add(op, "Defensive Transition", "Regroup", "Not built to press after losing it (\(f(P.work)))", wk) }
        let tk = P.tackling - b
        let calm = (P.temperament ?? 12) >= 11
        if tk >= 1 && calm { add(op, "Tackling", "Get Stuck In", vs("Tackling, aggression & bravery", P.tackling), tk) }
        else if tk <= -1 || !calm { add(op, "Tackling", "Stay On Feet", calm ? vs("Tackling", P.tackling) : "Hot-headed side — avoid cards", max(abs(tk), 1)) }
        let fbd = P.fullbackDefence - b, md = P.midDefence - b
        if P.hasWideAttackers && fbd >= 1 && fbd > md { add(op, "Pressing Trap", "Trap Outside", "Full-backs defend well (\(f(P.fullbackDefence))) — force play wide", fbd) }
        else if md >= 1 && md > fbd { add(op, "Pressing Trap", "Trap Inside", "Strong central midfield defending (\(f(P.midDefence)))", md) }
        let cba = P.cbAerial - b
        if cba >= 1.5 { add(op, "Cross Engagement", "Invite Crosses", vs("Centre-backs' heading, jumping & strength", P.cbAerial), cba) }
        else if fbd >= 0.5 && cba <= 0 { add(op, "Cross Engagement", "Stop Crosses", "Centre-backs not dominant in the air (\(f(P.cbAerial)))", max(fbd, 1)) }
        if fw >= 1 { add(op, "Prevent Short GK Distribution", "On", "You press high anyway — make their keeper kick long", fw) }

        // Set pieces
        if P.setPieceThreat >= 15 { add(sp, "Play For Set Pieces", "On", "Three strong headers in the XI (\(f(P.setPieceThreat)))", P.setPieceThreat - 13) }

        // Mentality from the stance; nudged by how solid or attack-minded the XI is.
        let mentality: String, mReason: String
        switch stance {
        case .favourites:
            mentality = "Positive"
            mReason = "Favourites should take the game to opponents; Attacking if you need goals."
        case .even:
            mentality = "Balanced"
            mReason = "Evenly matched — adjust in-game to the score."
        case .underdogs:
            mentality = fast >= 1 ? "Cautious" : "Defensive"
            mReason = fast >= 1 ? "Sit deeper and use your quick forwards on the break." : "Stay compact and keep the score down."
        }

        // Tactical style fit.
        func pct(_ x: Double) -> Double { max(0, min(100, 50 + x * 12)) }
        var styles: [StyleFit] = [
            StyleFit(name: "Gegenpress", fit: pct((fw + wk + (P.speed - b)) / 2),
                     why: "Pressing needs work rate (\(f(P.work))), forwards who chase (\(f(P.frontWork))) and pace (\(f(P.speed)))"),
            StyleFit(name: "Control Possession", fit: pct(tech + dec * 0.5),
                     why: "Keeping the ball needs technique (\(f(P.technique))) and decisions (\(f(P.decisions)))"),
            StyleFit(name: "Tiki-Taka", fit: pct(tech + fl * 0.5 + wk * 0.3 - 0.3),
                     why: "Short passing and movement: technique \(f(P.technique)), flair \(f(P.flair))"),
            StyleFit(name: "Vertical Tiki-Taka", fit: pct((tech + fast) * 0.8),
                     why: "Quick forward passing: technique \(f(P.technique)) and fast forwards \(f(P.frontSpeed))"),
            StyleFit(name: "Wing Play", fit: P.hasWideAttackers ? pct(((P.wideAttack - b) + air) * 0.8) : 0,
                     why: "Wide players \(f(P.wideAttack)) crossing for strikers in the air \(f(P.strikerAerial))"),
            StyleFit(name: "Route One", fit: pct(air - tech * 0.7),
                     why: "Long balls to strikers who win headers (\(f(P.strikerAerial)))"),
            StyleFit(name: "Fluid Counter-Attack", fit: pct((fast + tech * 0.6) * 0.8),
                     why: "Break quickly with pace (\(f(P.frontSpeed))) and good passing (\(f(P.technique)))"),
            StyleFit(name: "Direct Counter-Attack", fit: pct(fast - tech * 0.4 + wk * 0.3),
                     why: "Fast forwards (\(f(P.frontSpeed))) and simple, early balls"),
        ]
        if stance == .underdogs {
            styles.append(StyleFit(name: "Catenaccio", fit: pct((P.cbAerial - b) * 0.5 + md * 0.6 + 0.8),
                                   why: "Deep and compact; strong centre-backs (\(f(P.cbAerial))) and defensive midfield (\(f(P.midDefence)))"))
            styles.append(StyleFit(name: "Park the Bus", fit: pct(-tech * 0.6 + (P.cbAerial - b) * 0.4 + 0.5),
                                   why: "Pure damage limitation when you are clearly the weaker side"))
        }
        styles.sort { $0.fit > $1.fit }
        out.sort { ($0.phase, -$0.strength) < ($1.phase, -$1.strength) }
        return Instructions(profile: P, mentality: mentality, mentalityReason: mReason, styles: styles, items: out)
    }
}
