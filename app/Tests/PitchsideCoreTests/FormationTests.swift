import XCTest
@testable import PitchsideCore

final class FormationTests: XCTestCase {
    func testRelabelGivesUniqueReadableLabels() {
        let f = Formations.all.first { $0.name == "3-5-2" }!
        let labels = Formations.relabel(f.slots).map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertTrue(labels.contains("LCB") && labels.contains("CB") && labels.contains("RCB"))
        XCTAssertTrue(labels.contains("LST") && labels.contains("RST"))
    }

    func testMovingKeepsOrFixesRole() {
        let f = Formations.all.first { $0.name == "4-3-3" }!
        let st = f.slots.firstIndex { $0.position == "ST" }!
        // Advanced Forward is not a winger role, so it is replaced.
        let moved = Formations.moving(st, to: "AMR", in: f)
        XCTAssertEqual(moved.slots[st].position, "AMR")
        XCTAssertTrue(Formations.roles(for: "AMR").contains { $0.code == moved.slots[st].role })
        XCTAssertEqual(Set(moved.slots.map(\.label)).count, moved.slots.count)
        XCTAssertTrue(Formations.oopRoles(for: "AMR").contains { $0.code == moved.slots[st].oop })
        // Advanced Playmaker is offered in MC and AMC, so it survives the move; the OOP role is reset.
        var g = f
        let mc = g.slots.firstIndex { $0.position == "MC" }!
        g.slots[mc].role = "AP"
        let h = Formations.moving(mc, to: "AMC", in: g)
        XCTAssertEqual(h.slots[mc].role, "AP")
        XCTAssertEqual(h.slots[mc].oop, "oAM")
    }

    func testAddingSlot() {
        let f = Formations.all.first { $0.name == "4-4-2" }!
        let (g, i) = Formations.adding("DC", to: f)
        XCTAssertEqual(g.slots.count, 12)
        XCTAssertEqual(g.slots[i].role, "CB")
        XCTAssertEqual(g.slots[i].oop, "oCB")
        XCTAssertEqual(g.slots.filter { $0.position == "DC" }.map(\.label), ["LCB", "CB", "RCB"])
    }

    func testFormationRoundTripsThroughJSON() throws {
        let f = Formations.all[0]
        let back = try JSONDecoder().decode(Formation.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
    }

    func testTeamSplitsMenAndWomenOfSameClub() {
        var t = Factory()
        var people = t.homeSquad()
        people.append(t.make("Women Striker", club: "Home FC", pos: ["ST"], level: 18, female: true))
        people.append(t.make("Women Keeper", club: "Home FC", pos: ["GK"], level: 15, female: true))
        let meta = ExportMeta(scannedAt: nil, gameDate: nil, offsetsVersion: nil, offsetsVerified: nil, plugin: nil,
                              scanMs: nil, playerAttrKeys: SquadTests.attrKeys, hiddenKeys: [],
                              personalityKeys: ["Adaptability", "Ambition", "Loyalty", "Pressure"],
                              positionKeys: SquadTests.posKeys, staffAttrKeys: [], warnings: nil)
        let rows = RowBuilder.players(people, meta: meta, reference: Ages.date("2026-07-13")!, shortlist: [],
                                      growth: [:], previousIds: nil)
        let counts = SquadBuilder.genderCounts(club: "Home FC", rows: rows)
        XCTAssertEqual(counts.men, 21)
        XCTAssertEqual(counts.women, 2)
        let f = Formations.all.first { $0.name == "4-3-3" }!
        let men = SquadBuilder.analyse(club: "Home FC", formation: f, rows: SquadBuilder.team(rows, women: false),
                                       meta: meta, season: 2026)
        XCTAssertFalse(men.squad.contains { $0.person.f == 1 })
        XCTAssertEqual(men.slots.first { $0.slot.label == "ST" }?.starter?.name, "Weak Striker")
        let women = SquadBuilder.analyse(club: "Home FC", formation: f, rows: SquadBuilder.team(rows, women: true),
                                         meta: meta, season: 2026)
        XCTAssertEqual(women.squad.count, 2)
    }
}
