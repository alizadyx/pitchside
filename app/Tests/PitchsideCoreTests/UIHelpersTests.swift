import XCTest
@testable import PitchsideCore

final class UIHelpersTests: XCTestCase {
    func testAttributeName() {
        XCTAssertEqual(Roles.attributeName("WorkRate"), "Work Rate")
        XCTAssertEqual(Roles.attributeName("OffTheBall"), "Off The Ball")
    }

    func testRoleExplainNamesStrongestAndWeakestKeyAttributes() throws {
        let role = try XCTUnwrap(Roles.all.first { $0.key.count > 4 && $0.positions != ["GK"] })
        let keys = Roles.outfieldAttrs
        var attrs = [UInt8](repeating: 10, count: keys.count)
        let ki = role.key.compactMap { keys.firstIndex(of: $0) }
        attrs[ki[0]] = 19
        attrs[ki[1]] = 3
        let text = Roles.explain(role.code, attrs: attrs, attrKeys: keys)
        XCTAssertTrue(text.hasPrefix(role.label), text)
        XCTAssertTrue(text.contains("Strongest key: \(Roles.attributeName(role.key[0])) 19"), text)
        XCTAssertTrue(text.contains("\(Roles.attributeName(role.key[1])) 3"), text)
        XCTAssertEqual(Roles.explain("nope", attrs: attrs, attrKeys: keys), "")
    }

    func testSameSearchIgnoresGlobalSwitches() {
        var a = PlayerFilter(); a.minAge = 18
        var b = a; b.gender = 2; b.shortlistOnly = true
        XCTAssertTrue(a.sameSearch(as: b))
        b.minAge = 19
        XCTAssertFalse(a.sameSearch(as: b))
    }
}
