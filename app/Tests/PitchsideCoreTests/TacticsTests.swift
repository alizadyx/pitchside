import XCTest
@testable import PitchsideCore

final class TacticsTests: XCTestCase {
    let meta = ExportMeta(scannedAt: "2026-10-30T10:00:00", gameDate: "2026-07-13", offsetsVersion: nil, offsetsVerified: nil,
                          plugin: nil, scanMs: nil, playerAttrKeys: SquadTests.attrKeys, hiddenKeys: [],
                          personalityKeys: ["Adaptability", "Ambition", "Loyalty", "Pressure"],
                          positionKeys: SquadTests.posKeys, staffAttrKeys: [], warnings: nil)
    let ref = Ages.date("2026-07-13")!

    func rows(_ people: [Person]) -> [PlayerRow] {
        RowBuilder.players(people, meta: meta, reference: ref, shortlist: [])
    }

    // Attributes as shown in FM27 (Technical, Mental, Physical columns, in screen order).
    static let screenOrder = ["Crossing", "Dribbling", "Finishing", "FirstTouch", "Heading", "LongShots", "Marking", "Passing",
                              "Tackling", "Technique", "Aggression", "Anticipation", "Bravery", "Composure", "Concentration",
                              "Decisions", "Determination", "Flair", "Leadership", "OffTheBall", "Positioning", "Teamwork",
                              "Vision", "WorkRate", "Acceleration", "Agility", "Balance", "JumpingReach", "NaturalFitness",
                              "Pace", "Stamina", "Strength"]

    func player(_ id: UInt32, _ values: String, pos: [String]) -> Person {
        var p = Person(id: id, n: "P\(id)", ca: 140, pa: 150)
        var a = [UInt8](repeating: 10, count: SquadTests.attrKeys.count)
        for (k, v) in zip(Self.screenOrder, values.split(separator: " ").map { UInt8($0)! }) {
            a[SquadTests.attrKeys.firstIndex(of: k)!] = v
        }
        p.a = a
        var fam = [UInt8](repeating: 1, count: SquadTests.posKeys.count)
        for k in pos { fam[SquadTests.posKeys.firstIndex(of: k)!] = 20 }
        p.pos = fam
        return p
    }

    func scores(_ p: Person) -> [String: Double] {
        let r = RowBuilder.players([p], meta: meta, reference: ref, shortlist: [])[0]
        return Dictionary(uniqueKeysWithValues: Roles.all.enumerated().map { ($1.code, r.roleScores[$0]) })
    }

    /// FM27 star ratings from the player screens of one save: higher stars must score higher.
    func testRoleScoresFollowFMStars() {
        let cases: [(String, [String], [String: Double])] = [
            ("18 12 15 17 9 15 3 18 8 18 18 17 15 15 14 13 18 17 17 16 8 15 19 18 13 14 14 9 20 13 20 10", ["MC", "AMC"],   // Fernandes, DM list
             ["B2BP": 3.5, "DLP": 3.5, "B2B": 3, "DM": 2.5, "HB": 2]),
            ("18 12 15 17 9 15 3 18 8 18 18 17 15 15 14 13 18 17 17 16 8 15 19 18 13 14 14 9 20 13 20 10", ["MC", "AMC"],   // Fernandes, MC list
             ["CHM": 4, "AM": 4, "AP": 4, "MP": 4, "CM": 3, "WCM": 3]),
            ("7 13 14 14 14 12 5 12 8 14 13 14 14 13 12 13 15 14 8 15 5 14 11 15 15 14 14 17 16 17 15 15", ["ST"],          // Šeško
             ["TF": 3, "CF": 3, "CHF": 2.5, "DLF": 2.5, "P": 2.5, "F9": 2]),
            ("6 10 8 12 9 7 13 12 18 12 18 16 18 9 14 12 15 12 10 8 13 17 8 17 14 14 15 10 17 13 17 14", ["DM", "MC"],      // Ugarte
             ["DM": 2.5, "B2B": 2.5, "HB": 2.5, "B2BP": 2, "DLP": 2]),
            ("7 10 10 14 18 7 15 13 15 13 14 14 17 13 14 13 11 9 15 9 16 14 12 12 10 8 13 17 17 12 15 17", ["DC"],          // Maguire
             ["BPCB": 3, "NNCB": 3, "ACB": 3, "CB": 3, "WCB": 3, "OCB": 2.5]),
            ("13 15 14 14 12 13 4 14 4 15 10 13 10 11 12 11 13 16 10 16 4 11 13 10 15 15 15 12 14 17 14 15", ["AML", "AMR"], // Rashford at ML
             ["W": 2.5, "IW": 2.5, "PW": 2.5, "WM": 2]),
            ("14 13 7 15 13 3 14 15 14 14 13 15 13 15 13 14 10 10 12 12 16 15 13 13 12 15 15 14 10 14 14 16", ["DL"],        // Shaw at DL
             ["IFB": 3, "IWB": 3, "FB": 3, "PWB": 3, "WB": 2.5]),
        ]
        for (n, (values, pos, stars)) in cases.enumerated() {
            let s = scores(player(UInt32(n + 1), values, pos: pos))
            for (a, sa) in stars { for (b, sb) in stars where sa > sb {
                XCTAssertGreaterThan(s[a]!, s[b]!, "case \(n): \(a) (\(sa)★) should beat \(b) (\(sb)★)")
            } }
        }
    }

    func testCatalogue() {
        XCTAssertEqual(Set(Roles.all.map(\.code)).count, Roles.all.count)
        for pos in Formations.positions {
            XCTAssertFalse(Formations.roles(for: pos).isEmpty, "IP roles at \(pos)")
            XCTAssertFalse(Formations.oopRoles(for: pos).isEmpty, "OOP roles at \(pos)")
        }
        for f in Formations.all {
            XCTAssertEqual(f.slots.count, 11, f.name)
            for s in f.slots {
                XCTAssertTrue(Formations.roles(for: s.position).contains { $0.code == s.role }, "\(f.name) \(s.label) \(s.role)")
                XCTAssertTrue(Formations.oopRoles(for: s.position).contains { $0.code == s.oop }, "\(f.name) \(s.label) \(s.oop)")
            }
        }
    }

    func testOldFormationsMigrate() throws {
        let json = #"{"name":"Mine","slots":[{"label":"GK","position":"GK","role":"SK"},{"label":"LCB","position":"DC","role":"BPD"},{"label":"ST","position":"ST","role":"PF"}]}"#
        let f = try JSONDecoder().decode(Formation.self, from: Data(json.utf8))
        XCTAssertEqual(f.slots.map(\.role), ["GK", "BPCB", "CF"])
        XCTAssertEqual(f.slots.map(\.oop), ["oSK", "oCB", "oTCF"])
        var filter = PlayerFilter(); filter.roleCode = "BPD"
        let back = try JSONDecoder().decode(PlayerFilter.self, from: JSONEncoder().encode(filter))
        XCTAssertEqual(back.roleCode, "BPCB")
    }

    func testBestFormationAndXI() {
        var t = Factory()
        let rows = rows(t.homeSquad()).filter { $0.person.club == "Home FC" }
        let ranked = TacticsAdvisor.rankFormations(Formations.all, squad: rows, meta: meta)
        XCTAssertEqual(ranked.count, Formations.all.count)
        // The squad is built for 4-3-3 (DL DC DC DR DM MC MC AML AMR ST), so a back four with a DM ranks first.
        let best = ranked[0]
        XCTAssertEqual(best.outOfPosition, 0, best.formation.name)
        XCTAssertEqual(Set(best.picks.compactMap { $0.player?.id }).count, 11)
        // Each pick's roles are offered at its position.
        for p in best.picks {
            XCTAssertTrue(Formations.roles(for: p.slot.position).contains { $0.code == p.slot.role })
            XCTAssertTrue(Formations.oopRoles(for: p.slot.position).contains { $0.code == p.slot.oop })
        }
        // Starters (level 14) beat backups (12).
        XCTAssertTrue(best.picks.compactMap(\.player).allSatisfy { !$0.name.hasPrefix("Backup") })
        // A shape that needs three centre-backs is worse for this squad.
        let threeBack = ranked.first { $0.formation.name == "3-5-2" }!
        XCTAssertLessThan(threeBack.rating, best.rating)
    }

    func testSetPiecesAndCaptain() {
        var t = Factory()
        var people = t.homeSquad()
        let ai = { (k: String) in SquadTests.attrKeys.firstIndex(of: k)! }
        // Starter 5 (an MC) is the dead-ball specialist, Starter 1 (a DC) the leader and aerial threat.
        let spec = people.firstIndex { $0.n == "Starter 5" }!
        for k in ["Corners", "FreeKicks", "PenaltyTaking", "Crossing"] { people[spec].a![ai(k)] = 19 }
        people[spec].a![ai("RightFoot")] = 18
        let lead = people.firstIndex { $0.n == "Starter 1" }!
        people[lead].a![ai("Leadership")] = 19
        for k in ["Heading", "JumpingReach"] { people[lead].a![ai(k)] = 19 }
        let rows = rows(people).filter { $0.person.club == "Home FC" }
        let fit = TacticsAdvisor.fit(Formations.all[0], squad: rows, meta: meta)
        let sp = TacticsAdvisor.setPieces(xi: fit.picks.compactMap(\.player), bench: fit.bench, meta: meta)
        XCTAssertEqual(sp.leftCorners.first?.player.name, "Starter 5")
        XCTAssertEqual(sp.penalties.first?.player.name, "Starter 5")
        XCTAssertEqual(sp.directFreeKicks.first?.player.name, "Starter 5")
        XCTAssertEqual(sp.aerialTargets.first?.player.name, "Starter 1")
        XCTAssertEqual(sp.captains.first?.player.name, "Starter 1")
        XCTAssertFalse(sp.stayBack.contains { $0.player.name == "Starter 1" })
    }

    func testInstructionsFollowTheSquad() {
        var t = Factory()
        var people = t.homeSquad()
        let ai = { (k: String) in SquadTests.attrKeys.firstIndex(of: k)! }
        // Very technical, slow side with tireless forwards.
        for i in people.indices where people[i].n.hasPrefix("Starter") || people[i].n == "Weak Striker" {
            for k in ["Passing", "FirstTouch", "Technique", "Composure", "Vision", "Decisions"] { people[i].a![ai(k)] = 18 }
            for k in ["Pace", "Acceleration"] { people[i].a![ai(k)] = 8 }
        }
        let rows = rows(people).filter { $0.person.club == "Home FC" }
        let fit = TacticsAdvisor.fit(Formations.all[0], squad: rows, meta: meta)
        let ins = TacticsAdvisor.instructions(fit, meta: meta, stance: .favourites)
        func setting(_ name: String) -> String? { ins.items.first { $0.name == name }?.setting }
        XCTAssertEqual(setting("Passing Directness"), "Much Shorter")
        XCTAssertEqual(setting("Defensive Line"), "Deeper")
        XCTAssertNotEqual(setting("Attacking Transition"), "Counter")
        XCTAssertEqual(ins.mentality, "Positive")
        XCTAssertEqual(ins.styles.first?.name == "Control Possession" || ins.styles.first?.name == "Tiki-Taka", true,
                       ins.styles.map(\.name).joined(separator: ","))
        XCTAssertTrue(ins.items.allSatisfy { !$0.reason.isEmpty })
    }
}
