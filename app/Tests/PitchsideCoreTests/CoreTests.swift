import XCTest
@testable import PitchsideCore

final class CoreTests: XCTestCase {
    // A tiny export in exactly the format the plugin writes.
    let sample = """
    {"meta":{"scannedAt":"2026-10-29T20:00:00","gameDate":"2026-08-01","offsetsVersion":"t","offsetsVerified":false,
      "plugin":"0.1.0","scanMs":1000,
      "playerAttrKeys":["Crossing","Dribbling","Finishing","Heading","Pace","Acceleration","Technique","FirstTouch","Composure","OffTheBall","Agility","Passing","Decisions","Anticipation","Balance","WorkRate","Stamina","Teamwork","Flair","LongShots","Vision"],
      "hiddenKeys":["Consistency","ImportantMatches"],
      "personalityKeys":["Ambition","Professionalism"],
      "positionKeys":["GK","SW","DL","DC","DR","DM","ML","MC","MR","AML","AMC","AMR","ST","WBL","WBR"],
      "staffAttrKeys":["Attacking","Defending"],
      "warnings":["x"]},
     "players":[
      {"id":1,"n":"Fast Winger","dob":"2005-09-05","nat":"England","club":"Arsenal","div":"Premier League","ca":150,"pa":175,
       "rep":5000,"wrep":4000,"wage":120000,"exp":"2027-06-30","p":[15,20],
       "a":[16,17,14,10,18,18,16,16,13,15,16,14,13,14,15,15,15,14,16,13,14],"h":[15,16],
       "pos":[1,1,1,1,1,1,1,1,12,15,10,20,10,1,1],"ht":178,"ft":"L","val":95000000,"lst":true},
      {"id":2,"n":"Old Keeper","dob":"1990-01-15","club":"Nowhere FC","ca":90,"pa":95,
       "a":[1,1,1,1,8,8,5,5,10,1,9,6,9,9,8,7,9,10,3,1,5],"pos":[20,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}
     ],
     "staff":[{"id":3,"n":"Coach Person","dob":"1975-03-03","ca":120,"pa":130,"s":[16,9],"job":"Assistant Manager"}]}
    """

    func load() throws -> ExportFile {
        try JSONDecoder().decode(ExportFile.self, from: Data(sample.utf8))
    }

    func testDecodeAndRows() throws {
        let e = try load()
        XCTAssertEqual(e.players.count, 2)
        XCTAssertEqual(e.staff.first?.job, "Assistant Manager")
        let ref = Ages.date(e.meta.gameDate)!
        let rows = RowBuilder.players(e.players, meta: e.meta, reference: ref, shortlist: [2])
        let w = rows.first { $0.id == 1 }!
        XCTAssertEqual(w.age, 20)                          // born 2005-09-05, date 2026-08-01
        XCTAssertEqual(w.positions, "AMR, AML")            // ≥15 familiarity, best first
        XCTAssertTrue(["W", "IF", "IW", "AP"].contains(w.bestRole), "best role was \(w.bestRole)")
        XCTAssertGreaterThan(w.bestRoleScore, 13)
        let k = rows.first { $0.id == 2 }!
        XCTAssertEqual(k.positions, "GK")
        XCTAssertTrue(k.shortlisted)
        XCTAssertEqual(k.age, 36)
    }

    func testFilters() throws {
        let e = try load()
        let rows = RowBuilder.players(e.players, meta: e.meta, reference: Ages.date("2026-08-01")!, shortlist: [])
        var f = PlayerFilter()
        f.positions = ["AML"]
        XCTAssertEqual(Filtering.apply(f, to: rows, meta: e.meta, gbpPerUnit: 1).map(\.id), [1])
        f = PlayerFilter(); f.maxAge = 25
        XCTAssertEqual(Filtering.apply(f, to: rows, meta: e.meta, gbpPerUnit: 1).map(\.id), [1])
        f = PlayerFilter(); f.rules = [AttributeRule(key: "Pace", min: 17)]
        XCTAssertEqual(Filtering.apply(f, to: rows, meta: e.meta, gbpPerUnit: 1).map(\.id), [1])
        f = PlayerFilter(); f.rules = [AttributeRule(key: "Consistency", min: 16)]       // hidden attribute
        XCTAssertEqual(Filtering.apply(f, to: rows, meta: e.meta, gbpPerUnit: 1).count, 0)
        f = PlayerFilter(); f.rules = [AttributeRule(key: "Professionalism", min: 18)]   // personality
        XCTAssertEqual(Filtering.apply(f, to: rows, meta: e.meta, gbpPerUnit: 1).map(\.id), [1])
        f = PlayerFilter(); f.maxValue = 50_000_000
        XCTAssertEqual(Filtering.apply(f, to: rows, meta: e.meta, gbpPerUnit: 1).count, 0)  // unknown value excluded too
        f = PlayerFilter(); f.expiringBy = 2027; f.listedOnly = true
        XCTAssertEqual(Filtering.apply(f, to: rows, meta: e.meta, gbpPerUnit: 1).map(\.id), [1])
        f = PlayerFilter(); f.text = "arsenal"
        XCTAssertEqual(Filtering.apply(f, to: rows, meta: e.meta, gbpPerUnit: 1).map(\.id), [1])

        let staff = RowBuilder.staff(e.staff, reference: Ages.date("2026-08-01")!)
        var sf = StaffFilter(); sf.rules = [AttributeRule(key: "Attacking", min: 15)]
        XCTAssertEqual(Filtering.apply(sf, to: staff, meta: e.meta).count, 1)
        sf.rules = [AttributeRule(key: "Defending", min: 15)]
        XCTAssertEqual(Filtering.apply(sf, to: staff, meta: e.meta).count, 0)
    }

    func testRequestEncodingMatchesPlugin() throws {
        var t = CalibrationTarget()
        t.name = "Bukayo Saka"; t.attributes = ["Pace": 16]; t.birthDate = "2001-09-05"; t.heightCm = 178
        let r = PluginRequest(mode: "discover", database: "men", targets: [t])
        let json = String(decoding: try JSONEncoder().encode(r), as: UTF8.self)
        XCTAssertTrue(json.contains("\"mode\":\"discover\""))
        XCTAssertTrue(json.contains("\"heightCm\":178"))
        XCTAssertFalse(json.contains("\"id\":\"") && json.contains("targets\":[{\"id\""), "target UUID must not be sent")
    }

    func testMoneyAndLabels() {
        XCTAssertEqual(Money.format(95_000_000, symbol: "£", perGbp: 1), "£95.0M")
        XCTAssertEqual(Money.format(120_000, symbol: "£", perGbp: 1), "£120K")
        XCTAssertEqual(Money.format(nil, symbol: "£", perGbp: 1), "—")
        XCTAssertEqual(AttributeGroups.label("JumpingReach"), "Jumping Reach")
        XCTAssertEqual(AttributeGroups.label("OneOnOnes"), "One on Ones")
    }
}
