import XCTest
@testable import PitchsideCore

final class DisplayTests: XCTestCase {
    func testChipsListOnlyActiveFiltersAndClearIndividually() {
        var f = PlayerFilter()
        f.gender = 1
        XCTAssertTrue(f.chips().isEmpty, "defaults and gender make no chips")

        f.positions = ["DR", "DC"]
        f.minAge = 18; f.maxAge = 23
        f.maxValue = 15_000_000
        f.roleCode = "BPD"; f.minRoleScore = 14
        let rule = AttributeRule(key: "JumpingReach", min: 15)
        f.rules = [rule]
        f.onlyNew = true
        let chips = f.chips(currency: "€", roleName: { $0 == "BPD" ? "Ball-Playing Defender" : $0 })
        XCTAssertEqual(chips.map(\.label), [
            "Age 18–23", "New regens", "Positions: DC, DR", "Ball-Playing Defender ≥ 14.0",
            "Value ≤ €15M", "Jumping Reach ≥ 15",
        ])
        XCTAssertEqual(f.activeGroups, ["ability", "meta", "positions", "role", "money", "attributes"])

        f.clear("positions")
        XCTAssertTrue(f.positions.isEmpty)
        f.clear("rule:\(rule.id.uuidString)")
        XCTAssertTrue(f.rules.isEmpty)
        f.clear("age")
        XCTAssertEqual(f.minAge, 15); XCTAssertEqual(f.maxAge, 45)
        f.clear("role")
        XCTAssertEqual(f.roleCode, ""); XCTAssertEqual(f.minRoleScore, 0)
        XCTAssertEqual(f.chips().map(\.id), ["onlyNew", "maxValue"])

        f.shortlistOnly = true
        f.clearAll()
        XCTAssertTrue(f.chips().isEmpty)
        XCTAssertEqual(f.gender, 1)
        XCTAssertTrue(f.shortlistOnly)
    }

    func testStars() {
        XCTAssertEqual(Stars.value(200), 5)
        XCTAssertEqual(Stars.value(142), 3.5)
        XCTAssertEqual(Stars.value(168), 4.0)
        XCTAssertEqual(Stars.value(10), 0.5)
        XCTAssertEqual(Stars.value(0), 0)
    }

    func testPitchSpreadsSharedPositions() {
        let f = Formations.all.first { $0.name == "3-5-2" }!
        let pts = PitchLayout.points(for: f.slots)
        XCTAssertEqual(pts.count, 11)
        XCTAssertEqual(Set(pts.values).count, 11, "no two slots on the same spot")
        XCTAssertEqual(pts["CB"]?.x, 0.5)
        XCTAssertLessThan(pts["LCB"]!.x, pts["CB"]!.x)
        XCTAssertLessThan(pts["LST"]!.x, pts["RST"]!.x)
        XCTAssertGreaterThan(pts["GK"]!.y, pts["LST"]!.y, "goalkeeper at the bottom")
        for name in Formations.all.map(\.name) {
            let s = Formations.all.first { $0.name == name }!.slots
            XCTAssertEqual(PitchLayout.points(for: s).count, s.count, name)
        }
    }

    func testRadarAxes() {
        let keys = ["Pace", "Acceleration", "Strength", "Reflexes"]
        let meta = ExportMeta(scannedAt: nil, gameDate: nil, offsetsVersion: nil, offsetsVerified: nil, plugin: nil,
                              scanMs: nil, playerAttrKeys: keys, hiddenKeys: [], personalityKeys: [],
                              positionKeys: [], staffAttrKeys: [], warnings: nil)
        var p = Person(id: 1, n: "X", ca: 100, pa: 120)
        p.a = [18, 16, 10, 5]
        let v = RadarAxes.values(p, meta: meta, axes: RadarAxes.outfield)
        XCTAssertEqual(v.count, RadarAxes.outfield.count)
        XCTAssertEqual(v[0], 17)          // speed = (18+16)/2
        XCTAssertEqual(v[1], 10)          // only Strength known
        XCTAssertEqual(v[2], 0)           // nothing known
    }
}
