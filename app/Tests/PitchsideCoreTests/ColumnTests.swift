import XCTest
@testable import PitchsideCore

final class ColumnTests: XCTestCase {
    let meta = ExportMeta(scannedAt: nil, gameDate: nil, offsetsVersion: nil, offsetsVerified: nil, plugin: nil,
                          scanMs: nil, playerAttrKeys: SquadTests.attrKeys, hiddenKeys: ["Consistency"],
                          personalityKeys: ["Adaptability", "Ambition", "Loyalty", "Pressure"],
                          positionKeys: SquadTests.posKeys, staffAttrKeys: [], warnings: nil)

    func rows(_ people: [Person]) -> [PlayerRow] {
        RowBuilder.players(people, meta: meta, reference: Ages.date("2026-07-13")!, shortlist: [],
                           growth: [:], previousIds: nil)
    }

    func testIdsRoundTripAndTitles() {
        let c = StatColumn(.attribute, "Finishing")
        XCTAssertEqual(c.id, "attr.Finishing")
        XCTAssertEqual(StatColumn(id: c.id), c)
        XCTAssertNil(StatColumn(id: "nonsense"))
        XCTAssertEqual(StatColumn(.general, "wage").title, "Wage/wk")
        XCTAssertEqual(StatColumn(.attribute, "FirstTouch").shortTitle, "Fir")
        XCTAssertEqual(StatColumn(.attribute, "Pace").shortTitle, "Pac")
        XCTAssertEqual(StatColumn(.general, "value").shortTitle, "Value")
    }

    func testReaderAndFill() {
        var t = Factory()
        var a = t.make("Kevin De Bruyne", club: "Home FC", pos: ["MC"], level: 15, pace: 9)
        a.nat = "Belgium"; a.h = [17]; a.exp = "2027-06-30"
        var b = t.make("Vitinha", club: "PSG", pos: ["MC"], level: 14, pace: 16)
        b.nat = "Portugal"; b.sn = "Ferreira"
        var r = rows([a, b])
        let reader = StatReader(meta: meta)
        let pace = StatColumn(.attribute, "Pace"), cons = StatColumn(.hidden, "Consistency")
        let nat = StatColumn(.general, "nation"), con = StatColumn(.general, "contract")
        XCTAssertEqual(reader.value(pace, r[0]), 9)
        XCTAssertEqual(reader.value(cons, r[0]), 17)
        XCTAssertNil(reader.value(cons, r[1]), "no hidden data")
        XCTAssertEqual(reader.value(con, r[0]), 20270630)
        reader.fill(&r, [pace, nat, cons, StatColumn(.general, "interest")], interest: { $0.name == "Vitinha" ? 0.9 : nil })
        XCTAssertEqual(r[1][extra: pace.id], 16)
        XCTAssertLessThan(r[0][extra: nat.id], r[1][extra: nat.id], "Belgium sorts before Portugal")
        XCTAssertEqual(r[1][extra: cons.id], -.infinity)
        XCTAssertEqual(r[1][extra: "gen.interest"], 0.9)
    }

    func testCatalogAndLastName() {
        let cat = StatColumns.catalog(meta: meta, includeHidden: false)
        XCTAssertEqual(cat.first?.0, "General")
        XCTAssertFalse(cat.contains { $0.0 == "Hidden" })
        XCTAssertTrue(StatColumns.catalog(meta: meta, includeHidden: true).contains { $0.0 == "Personality" })
        var p = Person(id: 1, n: "Kevin De Bruyne", ca: 1, pa: 1)
        XCTAssertEqual(p.lastName, "De Bruyne")
        p.sn = "De Bruyne"; XCTAssertEqual(p.lastName, "De Bruyne")
        XCTAssertEqual(Person(id: 2, n: "Vitinha", ca: 1, pa: 1).lastName, "Vitinha")
    }
}
