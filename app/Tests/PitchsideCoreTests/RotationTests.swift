import XCTest
@testable import PitchsideCore

final class RotationTests: XCTestCase {
    let meta = ExportMeta(scannedAt: nil, gameDate: nil, offsetsVersion: nil, offsetsVerified: nil, plugin: nil,
                          scanMs: nil, playerAttrKeys: SquadTests.attrKeys, hiddenKeys: [],
                          personalityKeys: ["Adaptability", "Ambition", "Loyalty", "Pressure"],
                          positionKeys: SquadTests.posKeys, staffAttrKeys: [], warnings: nil)
    let f433 = Formations.all.first { $0.name == "4-3-3" }!

    func rows(_ people: [Person]) -> [PlayerRow] {
        RowBuilder.players(people, meta: meta, reference: Ages.date("2026-07-13")!, shortlist: [], growth: [:], previousIds: nil)
    }

    /// Two keepers and two naturals for every outfield position: 20 outfielders for 30 starts.
    func deepSquad() -> [PlayerRow] {
        var t = Factory()
        var s = [t.make("Keeper A", club: "Home FC", pos: ["GK"], level: 14),
                 t.make("Keeper B", club: "Home FC", pos: ["GK"], level: 10)]
        for p in ["DL", "DC", "DC", "DR", "DM", "MC", "MC", "AML", "AMR", "ST"] {
            s.append(t.make("\(p) first", club: "Home FC", pos: [p], level: 14))
            s.append(t.make("\(p) second", club: "Home FC", pos: [p], level: 11))
        }
        return rows(s)
    }

    func testThreeXIsShareStartsAndKeepTheKeeper() {
        let squad = deepSquad()
        let plan = Rotation.plan(formation: f433, squad: squad, meta: meta, settings: .init(matches: 3))
        XCTAssertEqual(plan.xis.count, 3)
        XCTAssertEqual(plan.cap, 2)
        XCTAssertTrue(plan.xis.allSatisfy { $0.empty == 0 && $0.picks.count == 11 })
        for xi in plan.xis {
            XCTAssertEqual(xi.picks.first?.slot.position, "GK", "team sheet starts with the keeper")
            XCTAssertEqual(xi.picks.first?.player?.name, "Keeper A", "the best keeper plays every match")
        }
        let outfield = plan.loads.filter { $0.row.person.pos?[0] != 20 }
        XCTAssertTrue(outfield.allSatisfy { $0.starts <= 2 }, "nobody outfield starts all three")
        XCTAssertFalse(plan.loads.contains { $0.overCap })
        XCTAssertEqual(outfield.map(\.starts).reduce(0, +), 30)
        XCTAssertGreaterThanOrEqual(plan.bestLevel, plan.xis[0].level)
        XCTAssertGreaterThanOrEqual(plan.xis[0].level, plan.xis[2].level, "strongest XI first")
    }

    func testUnavailableAndLockedPlayers() {
        let squad = deepSquad()
        let star = squad.first { $0.name == "ST first" }!
        let injured = squad.first { $0.name == "DM first" }!
        let plan = Rotation.plan(formation: f433, squad: squad, meta: meta,
                                 settings: .init(matches: 3, unavailable: [injured.id], locked: [star.id]))
        XCTAssertEqual(plan.loads.first { $0.row.id == star.id }?.starts, 3, "locked players start every match")
        XCTAssertEqual(plan.loads.first { $0.row.id == injured.id }?.starts, 0)
        XCTAssertFalse(plan.xis.flatMap(\.picks).contains { $0.player?.id == injured.id })
    }

    func testThinSquadUsesAccomplishedCoverBeforeBreakingTheCap() {
        var t = Factory()
        var people = [t.make("Keeper", club: "Home FC", pos: ["GK"], level: 14)]
        for p in ["DL", "DC", "DC", "DR", "DM", "MC", "MC", "AML", "AMR"] {
            people.append(t.make("\(p) a", club: "Home FC", pos: [p], level: 14))
            people.append(t.make("\(p) b", club: "Home FC", pos: [p], level: 12))
        }
        people.append(t.make("Striker", club: "Home FC", pos: ["ST"], level: 14))
        var cover = t.make("Spare winger", club: "Home FC", pos: ["AMR"], level: 13)
        cover.pos![Factory.posKeys.firstIndex(of: "ST")!] = 13          // accomplished up front
        people.append(cover)
        let plan = Rotation.plan(formation: f433, squad: rows(people), meta: meta, settings: .init(matches: 3))
        let st = plan.xis.compactMap { xi in xi.picks.first { $0.slot.position == "ST" } }
        XCTAssertTrue(st.contains { $0.player?.name == "Spare winger" && !$0.natural }, "cover flagged as not natural")
        XCTAssertLessThanOrEqual(plan.loads.first { $0.row.name == "Striker" }?.starts ?? 0, 2)
    }

    func testTwoMatchesFlagsDoublesWhenSquadIsTooSmall() {
        var t = Factory()
        var people = [t.make("Keeper", club: "Home FC", pos: ["GK"], level: 14)]
        for p in ["DL", "DC", "DC", "DR", "DM", "MC", "MC", "AML", "AMR", "ST"] {
            people.append(t.make("\(p) only", club: "Home FC", pos: [p], level: 14))
        }
        people.append(t.make("Spare MC", club: "Home FC", pos: ["MC"], level: 12))
        let plan = Rotation.plan(formation: f433, squad: rows(people), meta: meta, settings: .init(matches: 2))
        XCTAssertEqual(plan.cap, 1)
        XCTAssertTrue(plan.loads.contains { $0.overCap }, "11 outfielders can't cover 20 starts at one each")
        XCTAssertTrue(plan.xis.allSatisfy { $0.empty == 0 })
    }
}
