import Foundation

/// Dumps everything Pitchside computes for one club, so it can be checked independently.
/// Run: swift run -c release PitchsideAudit <export.json> <out.json> ["Club name"]
public enum Audit {
    @discardableResult
    public static func dump(exportPath path: String, club: String, outPath: String) throws -> Int {
        var file = try JSONDecoder().decode(ExportFile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        // Whole scan (meta is calibrated across it) unless asked to keep only the club, which is faster.
        if ProcessInfo.processInfo.environment["AUDIT_CLUB_ONLY"] != nil {
            file.players = file.players.filter { $0.club == club || $0.own == club }
        }
        let meta = file.meta
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withFullDate]
        let ref = file.meta.gameDate.flatMap { fmt.date(from: String($0.prefix(10))) } ?? Date()
        let all = RowBuilder.players(file.players, meta: meta, reference: ref, shortlist: [])
        let side = SquadBuilder.team(all, women: false)
        let teams = SquadBuilder.teams(club: club, rows: side)
        var rows = side
        if let first = teams.first { rows = side.filter { $0.person.club != club } + SquadBuilder.members(of: first, club: club, rows: side) }
        let report = SquadBuilder.analyse(club: club, formation: Formations.all[0], rows: rows, meta: meta, season: 2026)
        guard !report.squad.isEmpty else {
            throw NSError(domain: "Audit", code: 1, userInfo: [NSLocalizedDescriptionKey: "No players found for \(club)"])
        }
        let squad = report.squad
        var out: [String: Any] = ["club": club, "gameDate": meta.gameDate ?? "", "attrKeys": meta.playerAttrKeys, "persKeys": meta.personalityKeys, "posKeys": meta.positionKeys,
                                  "teams": teams.map { "\($0.label) \($0.count)" }]
        out["roles"] = Roles.all.map { ["code": $0.code, "ip": $0.isIP, "pos": $0.positions, "key": $0.key, "support": $0.support] }
        out["pools"] = ["outfield": Roles.outfieldAttrs, "keeper": Roles.keeperAttrs]
        out["weights"] = [Roles.keyWeight, Roles.preferableWeight, Roles.otherWeight]
        out["squad"] = squad.map { r -> [String: Any] in
            ["id": r.id, "name": r.name, "a": (r.person.a ?? []).map(Int.init), "pos": (r.person.pos ?? []).map(Int.init),
             "rs": r.roleScores.indices.map { r.roleScores[$0] }, "best": r.bestRoleScore, "meta": r.meta, "metaRating": r.metaRating, "metaRatingAll": r.metaRatingAll, "div": r.person.div ?? "", "p": (r.person.p ?? []).map(Int.init), "ca": r.person.ca, "positions": r.positions]
        }
        out["report"] = ["level": report.level, "slots": report.slots.map { ["label": $0.slot.label, "pos": $0.slot.position, "role": $0.slot.role,
            "oop": $0.slot.oop, "starter": $0.starter?.id ?? 0, "score": $0.starterScore, "backup": $0.backup?.id ?? 0, "bscore": $0.backupScore] }]
        func picks(_ f: TacticsAdvisor.FormationFit) -> [[String: Any]] {
            f.picks.map { ["label": $0.slot.label, "pos": $0.slot.position, "role": $0.slot.role, "oop": $0.slot.oop,
                           "player": $0.player?.id ?? 0, "ip": $0.ipScore, "oopS": $0.oopScore, "score": $0.score, "fam": Int($0.familiarity)] }
        }
        let fits = TacticsAdvisor.rankFormations(Formations.presets, squad: squad, meta: meta)
        out["formations"] = fits.map { ["name": $0.formation.name, "level": $0.level, "depth": $0.depth, "oop": $0.outOfPosition,
                                        "rating": $0.rating, "picks": picks($0)] }
        let presets = TacticsAdvisor.rankPresets(squad: squad, meta: meta)
        out["presets"] = presets.map { p -> [String: Any] in
            ["id": p.preset.id, "style": p.preset.style, "name": p.preset.name, "level": p.fit.level, "depth": p.fit.depth,
             "oop": p.fit.outOfPosition, "rating": p.rating, "styleScore": p.styleScore, "combined": p.combined,
             "slots": p.preset.slots.map { [$0.ipPosition, $0.ipRole, $0.oopPosition, $0.oopRole] },
             "oopFam": p.oopFamiliarity.map(Int.init), "picks": picks(p.fit),
             "demands": (p.style?.demands ?? []).map { ["label": $0.label, "group": $0.group, "score": $0.score, "weight": $0.weight, "attrs": $0.attributes] },
             "instructions": p.preset.formation.instructions ?? [:]]
        }
        out["styleRules"] = PresetStyle.rules.map { ["phase": $0.phase, "setting": $0.setting, "values": $0.values, "group": $0.group.rawValue,
                                                     "attrs": $0.attrs.map { [$0.0, $0.1] as [Any] }, "weight": $0.weight] }
        out["styles"] = FMPresets.styles.map { ["name": $0.name, "mentality": $0.mentality, "instructions": $0.instructions] }
        let best = fits[0]
        let sp = TacticsAdvisor.setPieces(xi: best.picks.compactMap(\.player), bench: best.bench, meta: meta)
        func t(_ x: [TacticsAdvisor.Taker]) -> [String] { x.map { "\($0.player.name) \($0.score)" } }
        out["setPieces"] = ["corners L": t(sp.leftCorners), "corners R": t(sp.rightCorners), "FK direct": t(sp.directFreeKicks),
                            "penalties": t(sp.penalties), "captains": t(sp.captains), "aerial": t(sp.aerialTargets)]
        let ins = TacticsAdvisor.instructions(best, meta: meta, stance: .even)
        out["instructions"] = ["mentality": ins.mentality, "items": ins.items.map { "\($0.name): \($0.setting)" }]
        let depth = SquadBuilder.depthChart(report, meta: meta)
        out["depth"] = depth.joined().map { ["slot": $0.slot.label, "n": $0.options.count] }
        let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath))
        return squad.count
        }
}
