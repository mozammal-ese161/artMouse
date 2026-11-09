import XCTest
@testable import ArtMouseCore

final class ActionModelTests: XCTestCase {
    func testButtonIDCodableRoundTrip() throws {
        let original: [ButtonID] = [.left, .right, .middle, .fourth, .fifth, .extended(7)]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([ButtonID].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testActionCodableRoundTripAllCases() throws {
        let actions: [Action] = [
            .none,
            .click(.doubleLeft, [.command, .shift]),
            .mission(.desktop(3), reverse: false),
            .mission(.moveSpaceRight, reverse: true),
            .music(.volumeUp, fineTune: true),
            .zoom(.appZoomIn, reverse: false),
            .switcher(.app(.bundleID("com.apple.Safari"))),
            .open(.path("/Applications")),
            .device(.activateCursorSpeed(nil)),
            .device(.switchPrecisionMode),
        ]
        let data = try JSONEncoder().encode(actions)
        let decoded = try JSONDecoder().decode([Action].self, from: data)
        XCTAssertEqual(decoded, actions)
    }

    func testIsHoldAction() {
        XCTAssertTrue(Action.device(.switchPrecisionMode).isHoldAction)
        XCTAssertFalse(Action.click(.left, []).isHoldAction)
        XCTAssertFalse(Action.device(.activateCursorSpeed(nil)).isHoldAction)
    }
}
