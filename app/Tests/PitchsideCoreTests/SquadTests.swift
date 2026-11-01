import XCTest
@testable import PitchsideCore

final class SquadTests: XCTestCase {
    static let attrKeys = ["Crossing", "Dribbling", "Finishing", "Heading", "LongShots", "Marking", "OffTheBall", "Passing",
                           "PenaltyTaking", "Tackling", "Vision", "Handling", "AerialReach", "CommandOfArea", "Communication",
                           "Kicking", "Throwing", "Anticipation", "Decisions", "OneOnOnes", "Positioning", "Reflexes",
                           "FirstTouch", "Technique", "LeftFoot", "RightFoot", "Flair", "Corners", "Teamwork", "WorkRate",
                           "LongThrows", "Eccentricity", "RushingOut", "Punching", "Acceleration", "FreeKicks", "Strength",
                           "Stamina", "Pace", "JumpingReach", "Leadership", "Balance", "Bravery", "Aggression", "Agility",
                           "NaturalFitness", "Determination", "Composure", "Concentration"]
    static let posKeys = ["GK", "SW", "DL", "DC", "DR", "DM", "ML", "MC", "MR", "AML", "AMC", "AMR", "ST", "WBL", "WBR"]

    let meta = ExportMeta(scannedAt: "2026-10-30T10:00:00", gameDate: "2026-07-13", offsetsVersion: nil, offsetsVerified: nil,
                          plugin: nil, scanMs: nil, playerAttrKeys: attrKeys, hiddenKeys: [],
                          personalityKeys: ["Adaptability", "Ambition", "Loyalty", "Pressure"],
                          positionKeys: posKeys, staffAttrKeys: [], warnings: nil)

    func rows(_ people: [Person], previous: Set<UInt32>? = nil, growth: [UInt32: Int] = [:]) -> [PlayerRow] {
        RowBuilder.players(people, meta: meta, reference: Ages.date("2026-07-13")!, shortlist: [],
                           growth: growth, previousIds: previous)
    }

    func testMetaPrefersPace() {
        var t = Factory()
        let slow = t.make("Slow", club: nil, pos: ["MC"], level: 14, pace: 8)
        let fast = t.make("Fast", club: nil, pos: ["MC"], level: 14, pace: 18)
        let r = rows([slow, fast])
        XCTAssertGreaterThan(r[1].meta, r[0].meta + 1)
        // Same CA (equal level) but very different meta: the point of the score.
        XCTAssertEqual(r[0].ca, r[1].ca)
    }

    func testMetaPressurePenaltyAndGoalkeeper() {
        var t = Factory()
        let calm = t.make("Calm", club: nil, pos: ["MC"], level: 14, pressure: 15)
        let nervy = t.make("Nervy", club: nil, pos: ["MC"], level: 14, pressure: 3)
        let gk = t.make("GK", club: nil, pos: ["GK"], level: 14)
        let edgy = t.make("Edgy", club: nil, pos: ["MC"], level: 14, pressure: 7)
        let r = rows([calm, nervy, gk, edgy])
        // A quarter point per point of Pressure below 8: 3 costs 1.25, 7 costs 0.25.
        XCTAssertEqual(r[0].meta - r[1].meta, 1.25, accuracy: 0.06)
        XCTAssertEqual(r[0].meta - r[3].meta, 0.25, accuracy: 0.06)
        XCTAssertGreaterThan(r[0].metaRating, r[1].metaRating)
        XCTAssertTrue(r[2].isGoalkeeper)
        XCTAssertEqual(r[2].meta, 14, accuracy: 0.05)
    }

    func testSquadFindsWeakStrikerAndSuggestsUpgrades() {
        var t = Factory()
        var people = t.homeSquad()
        people.append(t.make("Great Striker", club: "Rich FC", pos: ["ST"], level: 16, value: 60_000_000))
        people.append(t.make("Good Cheap Striker", club: "Small FC", pos: ["ST"], level: 13, age: 22, value: 4_000_000))
        people.append(t.make("Superstar", club: "Giant FC", pos: ["ST"], level: 18, rep: 9500, value: 150_000_000))
        people.append(t.make("Free Striker", club: nil, pos: ["ST"], level: 12, age: 30, value: 0))
        people.append(t.make("Winger", club: "Small FC", pos: ["AML"], level: 13))
        let r = rows(people)
        let f = Formations.all.first { $0.name == "4-3-3" }!
        let report = SquadBuilder.analyse(club: "Home FC", formation: f, rows: r, meta: meta, season: 2026)

        XCTAssertEqual(report.squad.count, 21)
        let byWeakness = report.slots.sorted { $0.weakness > $1.weakness }
        XCTAssertEqual(byWeakness.first?.slot.label, "ST")
        let st = report.slots.first { $0.slot.label == "ST" }!
        XCTAssertEqual(st.starter?.name, "Weak Striker")
        XCTAssertTrue(st.issues.contains("No backup"))
        XCTAssertTrue(st.issues.contains { $0.hasPrefix("Starter") && $0.contains("below squad level") })
        // Every other slot has a starter and a backup.
        XCTAssertTrue(report.slots.filter { $0.slot.label != "ST" }.allSatisfy { $0.starter != nil && $0.backup != nil })
        // Ageing backup is not a starter issue; starters are 25.
        XCTAssertFalse(report.slots.contains { $0.issues.contains { $0.hasPrefix("Starter is") } })

        var c = SigningCriteria()
        c.maxValueGbp = 70_000_000
        let s = SquadBuilder.suggestions(for: st, report: report, rows: r, meta: meta, criteria: c)
        let names = s.map(\.row.name)
        XCTAssertEqual(names.first, "Great Striker")
        XCTAssertTrue(names.contains("Good Cheap Striker"))
        XCTAssertTrue(names.contains("Free Striker"))
        XCTAssertFalse(names.contains("Superstar"), "too expensive and reputation too high")
        XCTAssertFalse(names.contains("Winger"), "not a striker")
        XCTAssertFalse(names.contains("Weak Striker"), "already at the club")

        c.maxValueGbp = 5_000_000
        let cheap = SquadBuilder.suggestions(for: st, report: report, rows: r, meta: meta, criteria: c).map(\.row.name)
        XCTAssertEqual(Set(cheap), ["Good Cheap Striker", "Free Striker"])

        c.maxValueGbp = 0; c.minInterest = nil
        XCTAssertTrue(SquadBuilder.suggestions(for: st, report: report, rows: r, meta: meta, criteria: c)
            .map(\.row.name).contains("Superstar"))
    }

    func testUnknownClubWithNoGoalkeeper() {
        var t = Factory()
        var people = [t.make("Lonely Defender", club: "Tiny FC", pos: ["DC"], level: 8)]
        people.append(t.make("Keeper For Hire", club: "Other FC", pos: ["GK"], level: 10, rep: 300, value: 50_000))
        let r = rows(people)
        let f = Formations.all.first { $0.name == "4-4-2" }!
        let report = SquadBuilder.analyse(club: "Tiny FC", formation: f, rows: r, meta: meta, season: 2026)
        let gk = report.slots.first { $0.slot.label == "GK" }!
        XCTAssertNil(gk.starter)
        XCTAssertTrue(gk.issues.contains("No natural GK"))
        XCTAssertEqual(report.slots.max { $0.weakness < $1.weakness }!.starter == nil, true)
        let s = SquadBuilder.suggestions(for: gk, report: report, rows: r, meta: meta, criteria: SigningCriteria())
        XCTAssertEqual(s.map(\.row.name), ["Keeper For Hire"])
        XCTAssertEqual(SquadBuilder.clubs(r), ["Other FC", "Tiny FC"])
    }

    func testHistoryGrowthAndNewgens() throws {
        var t = Factory()
        let a = t.make("Old Timer", club: "X", pos: ["MC"], level: 14)
        var b = t.make("Improver", club: "X", pos: ["MC"], level: 12)
        let oldExport = ExportFile(meta: meta, players: [a, b], staff: [])
        let snap = Snapshot(export: oldExport)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pitchside-hist-\(UUID().uuidString)")
        XCTAssertTrue(try History.save(snap, in: dir))
        XCTAssertFalse(try History.save(snap, in: dir), "same scan is stored once")
        let list = History.list(in: dir)
        XCTAssertEqual(list.count, 1)
        let loaded = try XCTUnwrap(History.load(list[0]))
        XCTAssertEqual(loaded.ids, [a.id, b.id])

        b.ca += 9
        let regen = t.make("Regen", club: "X", pos: ["ST"], level: 6, age: 15)
        let growth = History.growth(current: [a, b, regen], reference: loaded)
        XCTAssertEqual(growth[b.id], 9)
        XCTAssertEqual(growth[a.id], 0)
        XCTAssertNil(growth[regen.id])

        let r = rows([a, b, regen], previous: Set(loaded.ids), growth: growth)
        var f = PlayerFilter(); f.onlyNew = true
        XCTAssertEqual(Filtering.apply(f, to: r, meta: meta, gbpPerUnit: 1).map(\.name), ["Regen"])
        f = PlayerFilter(); f.minGrowth = 5
        XCTAssertEqual(Filtering.apply(f, to: r, meta: meta, gbpPerUnit: 1).map(\.name), ["Improver"])
        try? FileManager.default.removeItem(at: dir)
    }

    func testGenderAndPresets() {
        var t = Factory()
        let m = t.make("Man", club: "A", pos: ["ST"], level: 12)
        let w = t.make("Woman", club: "B", pos: ["ST"], level: 12, female: true)
        let r = rows([m, w])
        var f = PlayerFilter(); f.gender = 2
        XCTAssertEqual(Filtering.apply(f, to: r, meta: meta, gbpPerUnit: 1).map(\.name), ["Woman"])
        f.gender = 1
        XCTAssertEqual(Filtering.apply(f, to: r, meta: meta, gbpPerUnit: 1).map(\.name), ["Man"])
        f.gender = 0
        XCTAssertEqual(Filtering.apply(f, to: r, meta: meta, gbpPerUnit: 1).count, 2)

        let presets = Presets.builtIn(season: 2026, perUnit: 1.17)
        XCTAssertEqual(presets.count, 8)
        XCTAssertEqual(presets[2].filter.maxValue, 17_550_000)    // £15M shown in €
        XCTAssertEqual(presets[3].filter.expiringBy, 2027)
        // Presets round-trip as saved filters.
        let data = try! JSONEncoder().encode(presets)
        XCTAssertEqual(try! JSONDecoder().decode([NamedFilter].self, from: data), presets)
    }
}

struct Factory {
    static let attrKeys = SquadTests.attrKeys
    static let posKeys = SquadTests.posKeys
    var nextId: UInt32 = 1
    mutating func make(_ name: String, club: String?, pos: [String], level: UInt8, age: Int = 25, rep: Int = 5000,
                       value: Int = 10_000_000, pace: UInt8? = nil, pressure: UInt8 = 12, female: Bool = false) -> Person {
        var p = Person(id: nextId, n: name, ca: Int(level) * 7, pa: Int(level) * 8)
        nextId += 1
        p.club = club
        p.dob = "\(2026 - age)-01-01"
        p.rep = rep
        p.val = value
        p.wage = value / 500
        var a = [UInt8](repeating: level, count: Factory.attrKeys.count)
        if let pace { a[Factory.attrKeys.firstIndex(of: "Pace")!] = pace; a[Factory.attrKeys.firstIndex(of: "Acceleration")!] = pace }
        p.a = a
        var fam = [UInt8](repeating: 1, count: Factory.posKeys.count)
        for k in pos { fam[Factory.posKeys.firstIndex(of: k)!] = 20 }
        p.pos = fam
        p.p = [10, 10, 10, pressure]
        if female { p.f = 1 }
        return p
    }

    // A full 4-3-3 squad for "Home FC" with one weak spot at ST.
    mutating func homeSquad() -> [Person] {
        var s: [Person] = []
        s.append(make("Keeper A", club: "Home FC", pos: ["GK"], level: 14))
        s.append(make("Keeper B", club: "Home FC", pos: ["GK"], level: 11))
        for (i, p) in ["DL", "DC", "DC", "DR", "DM", "MC", "MC", "AML", "AMR"].enumerated() {
            s.append(make("Starter \(i)", club: "Home FC", pos: [p], level: 14))
            s.append(make("Backup \(i)", club: "Home FC", pos: [p], level: 12, age: i == 1 ? 33 : 24))
        }
        s.append(make("Weak Striker", club: "Home FC", pos: ["ST"], level: 9))
        return s
    }

}
