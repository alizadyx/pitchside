import XCTest
@testable import PitchsideCore

final class InsightTests: XCTestCase {
    let meta = ExportMeta(scannedAt: nil, gameDate: nil, offsetsVersion: nil, offsetsVerified: nil, plugin: nil,
                          scanMs: nil, playerAttrKeys: SquadTests.attrKeys,
                          hiddenKeys: ["Dirtiness", "Consistency", "ImportantMatches", "InjuryProneness", "Versatility"],
                          personalityKeys: ["Adaptability", "Ambition", "Loyalty", "Pressure", "Professionalism",
                                            "Sportsmanship", "Temperament", "Controversy"],
                          positionKeys: SquadTests.posKeys,
                          staffAttrKeys: ["Attacking", "Defending", "JudgingAbility", "JudgingPotential"], warnings: nil)

    func rows(_ people: [Person]) -> [PlayerRow] {
        RowBuilder.players(people, meta: meta, reference: Ages.date("2026-07-13")!, shortlist: [],
                           growth: [:], previousIds: nil)
    }

    func testFlags() {
        var p = Person(id: 1, n: "X", ca: 100, pa: 120)
        p.h = [16, 6, 17, 18, 10]            // dirty, inconsistent, big-match, injury prone
        p.p = [10, 10, 10, 10, 18, 10, 4, 10] // model professional, hot-headed
        let f = Flags.of(p, meta: meta)
        let names = Set(f.map(\.text))
        XCTAssertTrue(names.isSuperset(of: ["Dirty player", "Inconsistent", "Big-match player", "Injury prone",
                                            "Model professional", "Hot-headed"]))
        XCTAssertFalse(f.first!.good, "red flags come first")
        XCTAssertTrue(Flags.of(p, meta: meta, includeHidden: false).isEmpty, "hidden-only flags respect the setting")
    }

    func testDevelopmentOutlook() {
        var t = Factory()
        var keen = t.make("Keen", club: nil, pos: ["MC"], level: 10, age: 17)
        keen.pa = 160; keen.p = [10, 15, 10, 10, 18, 10, 10, 10]
        var lazy = t.make("Lazy", club: nil, pos: ["MC"], level: 10, age: 17)
        lazy.pa = 160; lazy.p = [10, 5, 10, 10, 4, 10, 10, 10]
        var a = lazy.a!; a[SquadTests.attrKeys.firstIndex(of: "Determination")!] = 5; lazy.a = a
        let old = t.make("Old", club: nil, pos: ["MC"], level: 10, age: 29)
        let r = rows([keen, lazy, old])
        let k = Development.outlook(r[0], meta: meta)!, l = Development.outlook(r[1], meta: meta)!
        XCTAssertGreaterThan(k.likelyPeak, l.likelyPeak + 15)
        XCTAssertLessThanOrEqual(k.likelyPeak, 160)
        XCTAssertNil(Development.outlook(r[2], meta: meta))
    }

    func testTeamsAndTimeline() {
        var t = Factory()
        var people = t.homeSquad()
        for i in people.indices { people[i].tm = 1; people[i].trep = 6000; people[i].exp = "2028-06-30" }
        // The striker's contract ends this season; a youth keeper sits in another team.
        people[people.count - 1].exp = "2027-06-30"
        var kid = t.make("Youth Keeper", club: "Home FC", pos: ["GK"], level: 8, age: 17)
        kid.tm = 2; kid.trep = 1200; kid.div = "U18 League"
        people.append(kid)
        let r = rows(people)
        let teams = SquadBuilder.teams(club: "Home FC", rows: r)
        XCTAssertEqual(teams.map(\.label), ["First team", "U18 League"])
        XCTAssertEqual(teams[0].count, 21)

        let first = r.filter { $0.person.tm == teams[0].id }
        let f = Formations.all.first { $0.name == "4-3-3" }!
        let plan = SquadBuilder.timeline(club: "Home FC", formation: f, squad: first, meta: meta, season: 2026)
        XCTAssertEqual(plan.map(\.label), ["2026/27", "2027/28", "2028/29"])
        XCTAssertEqual(plan[0].leaving.map(\.name), ["Weak Striker"])
        XCTAssertNotNil(plan[0].report.slots.first { $0.slot.label == "ST" }?.starter)
        XCTAssertNil(plan[1].report.slots.first { $0.slot.label == "ST" }?.starter, "gone after his contract ends")
        XCTAssertTrue(plan[2].report.squad.isEmpty, "everyone's 2028 contracts have ended")
    }

    func testStaffAdvice() {
        func person(_ id: UInt32, _ name: String, club: String?, _ s: [UInt8], wage: Int) -> Person {
            var p = Person(id: id, n: name, ca: 100, pa: 100); p.club = club; p.s = s; p.wage = wage; p.dob = "1980-01-01"
            return p
        }
        let staff = RowBuilder.staff([
            person(1, "Our Coach", club: "Home FC", [8, 14, 9, 9], wage: 2000),
            person(2, "Great Attacker", club: "Other", [17, 10, 5, 5], wage: 9000),
            person(3, "Cheap Attacker", club: "Other", [13, 10, 5, 5], wage: 1000),
            person(4, "Scout", club: "Other", [5, 5, 16, 15], wage: 1500),
        ], reference: Ages.date("2026-07-13")!)
        let advice = StaffAdvisor.advise(club: "Home FC", staff: staff, meta: meta)
        XCTAssertEqual(advice.first?.area.title, "Attacking coaching", "weakest area first")
        XCTAssertEqual(advice.first?.candidates.map(\.row.name), ["Great Attacker", "Cheap Attacker"])
        let capped = StaffAdvisor.advise(club: "Home FC", staff: staff, meta: meta, maxWageGbp: 5000)
        XCTAssertEqual(capped.first?.candidates.map(\.row.name), ["Cheap Attacker"])
        XCTAssertEqual(advice.first { $0.area.title == "Scouting" }?.candidates.first?.row.name, "Scout")
    }
}
