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
        XCTAssertEqual(teams.map(\.label), ["First team", "Reserves (U18 League)"], "older scans: no age limits")
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

    func testTeamsUseAgeLimits() {
        var t = Factory()
        func p(_ name: String, team: UInt32, rep: Int, age: Int) -> Person {
            var x = t.make(name, club: "Chelsea", pos: ["MC"], level: 10)
            x.tm = team; x.trep = rep; x.tage = age
            return x
        }
        let r = rows([p("U18 kid", team: 3, rep: 1600, age: 18), p("U21 lad", team: 2, rep: 2800, age: 21),
                      p("First teamer", team: 1, rep: 8100, age: 100), p("Reserve", team: 4, rep: 3000, age: 100)])
        XCTAssertEqual(SquadBuilder.teams(club: "Chelsea", rows: r).map(\.label),
                       ["First team", "Reserves", "U21", "U18"])
    }

    func testTeamsFallBackToAgesWithoutTeamData() {
        var t = Factory()
        var people: [Person] = []
        for i in 0..<36 { people.append(t.make("Senior \(i)", club: "Old Scan FC", pos: ["MC"], level: 14, age: 26)) }
        for i in 0..<10 { people.append(t.make("Kid \(i)", club: "Old Scan FC", pos: ["MC"], level: 8, age: 17)) }
        for i in 0..<6 { people.append(t.make("Lad \(i)", club: "Old Scan FC", pos: ["MC"], level: 9, age: 20)) }
        let r = rows(people)
        let teams = SquadBuilder.teams(club: "Old Scan FC", rows: r)
        XCTAssertEqual(teams.map(\.label), ["First team (best 30)", "Under 21 by age", "Under 18 by age"])
        XCTAssertTrue(teams.allSatisfy(\.approximate))
        let first = SquadBuilder.members(of: teams[0], club: "Old Scan FC", rows: r)
        XCTAssertEqual(first.count, 30)
        XCTAssertTrue(first.allSatisfy { $0.name.hasPrefix("Senior") })
        XCTAssertEqual(SquadBuilder.members(of: teams[2], club: "Old Scan FC", rows: r).count, 10)
        XCTAssertEqual(SquadBuilder.members(of: teams[1], club: "Old Scan FC", rows: r).count, 16)
    }

    func testLeagueMap() {
        var t = Factory()
        var people: [Person] = []
        func add(_ club: String, _ div: String, _ nat: String, _ level: UInt8, rep: Int, n: Int) {
            for i in 0..<n {
                var p = t.make("\(club) \(div) \(i)", club: club, pos: ["MC"], level: level, age: 25)
                p.div = div; p.nat = nat; p.trep = rep
                people.append(p)
            }
        }
        add("Big FC", "Top League", "England", 15, rep: 8000, n: 20)
        add("Big FC", "U18 League", "England", 7, rep: 1000, n: 30)     // more youth players than seniors
        add("Small FC", "Second League", "England", 11, rep: 4000, n: 20)
        add("Other FC", "Top League", "England", 14, rep: 7000, n: 20)
        add("Paris FC", "French League", "France", 13, rep: 6000, n: 20)
        let m = TeamCompare.leagueMap(rows(people))
        XCTAssertEqual(m.clubLeague["Big FC"], "Top League", "senior team decides, not the biggest group")
        XCTAssertEqual(m.countries, ["England", "France"])
        XCTAssertEqual(m.leagues(in: "England"), ["Top League", "Second League"], "strongest first")
        XCTAssertEqual(m.clubs(in: "Top League"), ["Big FC", "Other FC"])
    }

    func testStaffAdvice() {
        func person(_ id: UInt32, _ name: String, club: String?, _ s: [UInt8], wage: Int?, job: String,
                    trep: Int? = nil) -> Person {
            var p = Person(id: id, n: name, ca: 100, pa: 100); p.club = club; p.s = s; p.wage = wage; p.dob = "1980-01-01"
            p.job = job; p.trep = trep
            return p
        }
        let staff = RowBuilder.staff([
            person(1, "Our Coach", club: "Home FC", [8, 14, 9, 9], wage: 2000, job: "Coach", trep: 5000),
            person(5, "Our Chairman", club: "Home FC", [18, 18, 18, 18], wage: 0, job: "Chairman", trep: 5000),
            person(2, "Great Attacker", club: "Other", [17, 10, 5, 5], wage: 9000, job: "First-Team Coach", trep: 5000),
            person(3, "Cheap Attacker", club: "Other", [13, 10, 5, 5], wage: 1000, job: "Assistant Manager", trep: 4000),
            person(4, "Scout", club: "Other", [5, 5, 16, 15], wage: 1500, job: "Chief Scout", trep: 3000),
            person(6, "Their President", club: "Big", [20, 20, 20, 20], wage: 0, job: "President", trep: 9000),
            person(7, "Star Coach", club: "Big", [19, 10, 5, 5], wage: 20000, job: "Coach", trep: 9000),
            person(8, "Unpaid Coach", club: "Other", [18, 10, 5, 5], wage: nil, job: "Coach", trep: 4000),
            person(9, "Free Coach", club: nil, [16, 10, 5, 5], wage: nil, job: "", trep: nil),
            person(10, "Set Piece Guy", club: "Other", [5, 5, 5, 5], wage: 1000, job: "Media Analyst", trep: 4000),
        ], reference: Ages.date("2026-07-13")!)
        let advice = StaffAdvisor.advise(club: "Home FC", staff: staff, meta: meta, clubRep: 5000)
        let attacking = advice.first { $0.area.title == "Attacking coaching" }!
        // Your chairman doesn't count as your coach; the board, unpaid people and bigger clubs' staff aren't suggested.
        XCTAssertEqual(attacking.best?.name, "Our Coach")
        XCTAssertEqual(attacking.candidates.map(\.row.name), ["Great Attacker", "Free Coach", "Cheap Attacker"])
        let dreaming = StaffAdvisor.advise(club: "Home FC", staff: staff, meta: meta, clubRep: 5000, realistic: false)
        let all = dreaming.first { $0.area.title == "Attacking coaching" }!
        XCTAssertEqual(all.candidates.first?.row.name, "Star Coach")
        XCTAssertEqual(all.candidates.first?.doubt, "works for a bigger club")
        let capped = StaffAdvisor.advise(club: "Home FC", staff: staff, meta: meta, maxWageGbp: 5000, clubRep: 5000)
        XCTAssertFalse(capped.first { $0.area.title == "Attacking coaching" }!.candidates.contains { $0.row.name == "Great Attacker" })
        XCTAssertEqual(advice.first { $0.area.title == "Scouting" }?.candidates.first?.row.name, "Scout")
        XCTAssertEqual(StaffAdvisor.jobTitle("Media Analyst"), "Set Piece Coach")
        XCTAssertTrue(StaffAdvisor.fits("Media Analyst", .setPieces))
        XCTAssertFalse(StaffAdvisor.fits("Media Analyst", .coaching))
    }
}
