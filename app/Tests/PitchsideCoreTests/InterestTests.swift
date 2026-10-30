import XCTest
@testable import PitchsideCore

final class InterestTests: XCTestCase {
    let meta = ExportMeta(scannedAt: nil, gameDate: nil, offsetsVersion: nil, offsetsVerified: nil, plugin: nil,
                          scanMs: nil, playerAttrKeys: SquadTests.attrKeys, hiddenKeys: [],
                          personalityKeys: ["Adaptability", "Ambition", "Loyalty", "Pressure"],
                          positionKeys: SquadTests.posKeys, staffAttrKeys: [], warnings: nil)

    func world() -> [PlayerRow] {
        var t = Factory()
        var people: [Person] = []
        for i in 0..<16 { people.append(t.make("Home \(i)", club: "Home FC", pos: ["MC"], level: 12, rep: 5000)) }
        for i in 0..<16 { people.append(t.make("Giant \(i)", club: "Giant FC", pos: ["MC"], level: 16, rep: 8500)) }
        for i in 0..<16 { people.append(t.make("Small \(i)", club: "Small FC", pos: ["MC"], level: 9, rep: 2000)) }
        people.append(t.make("Peer", club: "Peer FC", pos: ["MC"], level: 12, rep: 5500))
        people.append(t.make("Star", club: nil, pos: ["MC"], level: 18, rep: 9500))
        var listed = t.make("Listed Giant", club: "Giant FC", pos: ["MC"], level: 15, age: 33, rep: 8000)
        listed.lst = true
        people.append(listed)
        return RowBuilder.players(people, meta: meta, reference: Ages.date("2026-07-13")!, shortlist: [],
                                  growth: [:], previousIds: nil)
    }

    func level(_ name: String, _ rows: [PlayerRow], _ m: InterestModel) -> InterestLevel? {
        m.assess(rows.first { $0.name == name }!, joining: "Home FC", season: 2026)?.level
    }

    func testBiggerClubsAndStarsRefuseSmallerOnesAccept() {
        let rows = world()
        let m = InterestModel(rows: rows, meta: meta)
        XCTAssertEqual(m.clubLevel["Home FC"], 5000)
        XCTAssertEqual(level("Small 3", rows, m), .interested)
        XCTAssertEqual(level("Giant 3", rows, m), .unlikely)
        XCTAssertEqual(level("Star", rows, m), .unlikely, "free, but far too famous")
        // An ageing, transfer-listed player from the big club is much more willing than his teammates.
        func score(_ n: String) -> Double { m.assess(rows.first { $0.name == n }!, joining: "Home FC", season: 2026)!.score }
        XCTAssertGreaterThan(score("Listed Giant"), score("Giant 3") + 0.2)
        XCTAssertEqual(level("Peer", rows, m), .persuadable, "a slightly bigger peer club needs persuading")
        XCTAssertNil(level("Home 1", rows, m), "already at the club")
    }

    func testSuggestionsRespectMinimumInterest() {
        let rows = world()
        let m = InterestModel(rows: rows, meta: meta)
        let f = Formation(name: "one", slots: [Slot("CM", "MC", "CM")])
        let report = SquadBuilder.analyse(club: "Home FC", formation: f, rows: rows, meta: meta, season: 2026)
        var c = SigningCriteria()
        c.minGain = 0.1
        c.maxAge = 40
        let all = SquadBuilder.suggestions(for: report.slots[0], report: report, rows: rows, meta: meta, criteria: c,
                                           interest: m, season: 2026)
        XCTAssertTrue(all.contains { $0.row.name == "Giant 1" })
        c.minInterest = .persuadable
        let keen = SquadBuilder.suggestions(for: report.slots[0], report: report, rows: rows, meta: meta, criteria: c,
                                            interest: m, season: 2026)
        XCTAssertFalse(keen.contains { $0.row.name.hasPrefix("Giant ") })
        XCTAssertTrue(keen.allSatisfy { ($0.interest?.level ?? .unlikely) >= .persuadable })
    }
}
