import Foundation

/// One slot of an FM27 preset: where the player stands and his role, in and out of possession.
public struct PresetSlot: Sendable, Hashable {
    public let ipPosition: String
    public let ipRole: String
    public let oopPosition: String
    public let oopRole: String
}

/// A tactic preset the game offers under Create Tactic → Presets: a tactical style plus an
/// In Possession shape and an Out of Possession shape, eleven players each with both roles.
public struct FMPreset: Sendable, Identifiable, Hashable {
    public let id: String
    public let style: String
    public let ip: String           // In Possession formation, FM's name
    public let oop: String          // Out of Possession formation
    public let slots: [PresetSlot]  // goalkeeper first, then right to left within each line, as the game lists them

    /// `slots` is "POS ROLE OOPPOS OOPROLE|…" (compact generated data).
    public init(id: String, style: String, ip: String, oop: String, slots: String) {
        self.id = id; self.style = style; self.ip = ip; self.oop = oop
        self.slots = slots.split(separator: "|").map {
            let p = $0.split(separator: " ").map(String.init)
            return PresetSlot(ipPosition: p[0], ipRole: p[1], oopPosition: p[2], oopRole: p[3])
        }
    }

    public var name: String { ip == oop ? ip : "\(ip) → \(oop)" }
    public var title: String { "\(style): \(name)" }

    /// The preset as a Pitchside formation (IP positions, IP + OOP roles, labelled left to right).
    public var formation: Formation {
        // The game lists each line right to left; relabel works left to right.
        let raw = slots.reversed().map { Slot("", $0.ipPosition, $0.ipRole, $0.oopRole) }
        var f = Formation(name: "\(ip) \(style)", slots: Array(Formations.relabel(raw).reversed()))
        f.style = style
        let st = FMPresets.style(style)
        f.mentality = st?.mentality
        f.instructions = st?.catalogueInstructions() ?? [:]
        return f
    }
}

/// A tactical style's default mentality and team instructions.
public struct FMStyle: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let mentality: String
    /// [phase ("IP"/"OOP"), section ("Overview", "Buildup"…), setting, value]
    public let instructions: [[String]]

    public func settings(_ phase: String, _ section: String? = nil) -> [(String, String)] {
        instructions.filter { $0[0] == phase && (section == nil || $0[1] == section) }.map { ($0[2], $0[3]) }
    }
    /// Settings that differ from the neutral "Standard"/"Balanced".
    public func highlights(_ phase: String) -> [(String, String)] {
        settings(phase).filter { !["Standard", "Balanced", "Keep Ball in Play", "No"].contains($0.1) }
    }
}

extension FMStyle {
    /// The style's instructions in the names and options of Pitchside's instruction list
    /// (TacticsAdvisor.catalogue). Neutral settings are left at Default.
    public func catalogueInstructions() -> [String: String] {
        let names = ["Attacking Width": "Team Width", "Line of Engagement": "Line Of Engagement",
                     "Shots from Distance": "Shots From Distance", "Trigger Press": "Pressing Intensity",
                     "GK Distribution": "Distribute To", "GK Distribution (Speed)": "Distribution Speed",
                     "Short Goalkeeper Distribution": "Prevent Short GK Distribution", "Play for Set Pieces": "Play For Set Pieces"]
        let values = ["Counter-Attack": "Counter", "More Expressive": "Be More Expressive", "More Disciplined": "Be More Disciplined",
                      "High Press": "High", "Mid Block": "Mid", "Low Block": "Low", "Lower": "Deeper", "Much Lower": "Much Deeper",
                      "More Often": "Higher", "Much More Often": "Much Higher", "Less Often": "Lower", "Much Less Often": "Much Lower",
                      "Step Up More": "Hold Line", "Drop Off More": "Drop Off", "Encourage": "Run At Defence", "Discourage": "Dribble Less",
                      "Pass Into Space": "Into Space", "Pass Into Feet": "Into Feet", "Distribute Quickly": "Quick",
                      "Slow Pace Down": "Slow", "Yes": "On", "Play For Set Pieces": "On"]
        var out = [String: String]()
        for row in instructions {
            let (setting, value) = (row[2], row[3])
            if ["Standard", "Balanced", "No", "Mixed", "Keep Ball in Play"].contains(value) { continue }
            let name = names[setting] ?? setting
            guard let spec = TacticsAdvisor.catalogue.first(where: { $0.name.lowercased() == name.lowercased() }) else { continue }
            // Pressing Intensity comes from Trigger Press; Time Wasting's own Less/More Often stay as they are.
            let v = (setting == "Time Wasting") ? value : (values[value] ?? value)
            if let o = spec.options.first(where: { $0.lowercased() == v.lowercased() }) { out[spec.name] = o }
        }
        return out
    }
}

public enum FMPresets {
    public static func style(_ name: String) -> FMStyle? { styles.first { $0.name == name } }
    public static var styleNames: [String] { styles.map(\.name) }
}

extension TacticsAdvisor {
    /// How well a squad fits one FM preset: the best XI with every player judged in the preset's roles,
    /// at the IP position and at the OOP position.
    public struct PresetFit: Sendable, Identifiable {
        public var id: String { preset.id }
        public let preset: FMPreset
        public let fit: FormationFit
        /// Per pick (same order as fit.picks): OOP position and the player's familiarity there.
        public let oopPositions: [String]
        public let oopFamiliarity: [UInt8]
        /// How the XI suits the style's team instructions (separate from the role scores).
        public let style: PresetStyle.Result?
        /// Your squad's average style fit over all presets: style fit is shown relative to it.
        public var styleOffset: Double = 0
        public var rating: Double { fit.rating }
        /// + this style suits your players' strengths better than your average style, − worse.
        public var styleScore: Double { (style?.score ?? 0) - styleOffset }
        /// XI level nudged by the squad's lean: half a level per point of style fit.
        public var combined: Double { fit.level + 0.5 * styleScore }
    }

    /// Cost of an unfamiliar OOP position. The player only spends part of the game there,
    /// so it never rules him out, but it counts.
    static func oopPenalty(_ f: UInt8) -> Double { familiarityPenalty(f) ?? 3 }

    public static func fit(_ preset: FMPreset, squad: [PlayerRow], meta: ExportMeta) -> PresetFit {
        let posIndex = Dictionary(uniqueKeysWithValues: meta.positionKeys.enumerated().map { ($1, $0) })
        let formation = preset.formation
        let slots = formation.slots
        let n = slots.count
        let ipShare = SquadBuilder.ipShare
        var value = Array(repeating: [Double?](repeating: nil, count: squad.count), count: n)
        var famIP = Array(repeating: [UInt8](repeating: 0, count: squad.count), count: n)
        var famOOP = famIP
        for s in 0..<n {
            let ps = preset.slots[s]
            for (p, r) in squad.enumerated() {
                let fi = SquadBuilder.familiarity(r, posIndex[ps.ipPosition])
                let fo = ps.oopPosition == ps.ipPosition ? fi : SquadBuilder.familiarity(r, posIndex[ps.oopPosition])
                famIP[s][p] = fi; famOOP[s][p] = fo
                guard let pen = familiarityPenalty(fi) else { continue }
                let penalty = ipShare * pen + (1 - ipShare) * (ps.oopPosition == ps.ipPosition ? pen : oopPenalty(fo))
                value[s][p] = SquadBuilder.slotScore(r, slots[s]) - penalty
            }
        }
        let assign = optimalAssignment(slots: n, players: squad.count) { value[$0][$1] }
        let used = Set(assign.compactMap { $0 })
        var picks: [Pick] = [], oopFam: [UInt8] = []
        for s in 0..<n {
            let slot = slots[s]
            guard let p = assign[s], let v = value[s][p] else {
                picks.append(Pick(slot: slot, player: nil, ipScore: 0, oopScore: 0, score: 0, familiarity: 0, alternatives: []))
                oopFam.append(0)
                continue
            }
            let r = squad[p]
            let ipS = Roles.index(slot.role).map { r.roleScores[$0] } ?? 0
            let oopS = Roles.index(slot.oop).map { r.roleScores[$0] } ?? 0
            picks.append(Pick(slot: slot, player: r, ipScore: ipS, oopScore: oopS, score: v,
                              familiarity: famIP[s][p], alternatives: []))
            oopFam.append(famOOP[s][p])
        }
        let depthScores = (0..<n).map { s in squad.indices.filter { !used.contains($0) }.compactMap { value[s][$0] }.max() ?? 0 }
        let bench = squad.indices.filter { !used.contains($0) }.map { squad[$0] }
            .sorted { $0.bestRoleScore > $1.bestRoleScore }.prefix(9)
        let filled = picks.filter { $0.player != nil }
        let level = filled.isEmpty ? 0 : filled.map(\.score).reduce(0, +) / Double(n)
        let depth = depthScores.reduce(0, +) / Double(max(1, n))
        let out = filled.filter { $0.familiarity < 15 }.count
        let fit = FormationFit(formation: formation, picks: picks, bench: Array(bench),
                               level: level, depth: depth, outOfPosition: out)
        let xi = picks.compactMap { p in p.player.map { ($0, p.slot.position) } }
        let style = FMPresets.style(preset.style).map { PresetStyle.evaluate($0, xi: xi, meta: meta) }
        return PresetFit(preset: preset, fit: fit, oopPositions: preset.slots.map(\.oopPosition),
                         oopFamiliarity: oopFam, style: style)
    }

    /// Every FM preset fitted to the squad, best first.
    public static func rankPresets(squad: [PlayerRow], meta: ExportMeta, presets: [FMPreset] = FMPresets.all) -> [PresetFit] {
        var fits = presets.map { fit($0, squad: squad, meta: meta) }
        let raw = fits.compactMap { $0.style?.score }
        let mean = raw.isEmpty ? 0 : raw.reduce(0, +) / Double(raw.count)
        for i in fits.indices { fits[i].styleOffset = mean }
        return fits.sorted { $0.rating > $1.rating }
    }
}
