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

    func testScrollDirectionAxisAndSign() {
        XCTAssertEqual(ScrollDirection.up.axis, .vertical)
        XCTAssertEqual(ScrollDirection.down.axis, .vertical)
        XCTAssertEqual(ScrollDirection.left.axis, .horizontal)
        XCTAssertEqual(ScrollDirection.right.axis, .horizontal)
        XCTAssertEqual(ScrollDirection.up.sign, 1)
        XCTAssertEqual(ScrollDirection.down.sign, -1)
        XCTAssertEqual(ScrollDirection.right.sign, 1)
        XCTAssertEqual(ScrollDirection.left.sign, -1)
    }

    func testActionScrollCodableRoundTrip() throws {
        let spec = ScrollSpec(direction: .down, mods: [.shift], lines: 5, intervalMS: 50, continuous: true)
        let original: [Action] = [.scroll(spec)]
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode([Action].self, from: data), original)
    }

    func testChordCodableRoundTripAndDefaults() throws {
        var chord = Chord(id: UUID(), buttons: [.middle, .fourth], actions: [.mission(.missionControl, reverse: false)])
        XCTAssertEqual(chord.timeout, 0.3, accuracy: 1e-12)
        chord.timeout = 0.5
        let data = try JSONEncoder().encode(chord)
        XCTAssertEqual(try JSONDecoder().decode(Chord.self, from: data), chord)
    }

    func testMacroAndSnappingCodableRoundTrip() throws {
        let steps: [MacroStep] = [
            .enterKey(keyCode: 40, mods: [.command]),
            .wait(milliseconds: 150),
            .click(op: .left, mods: []),
        ]
        let original: [Action] = [
            .macro(steps: steps, repeatMode: .hold, repeatIntervalMS: 250, modifierProxy: true),
            .snapping(.snap(click: true, bounce: false)),
        ]
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode([Action].self, from: data), original)
    }

    func testMacroAndSnappingAreNotHoldActions() {
        XCTAssertFalse(Action.macro(steps: [], repeatMode: .hold, repeatIntervalMS: 100, modifierProxy: false).isHoldAction)
        XCTAssertFalse(Action.snapping(.snap(click: true, bounce: true)).isHoldAction)
        XCTAssertFalse(Action.macro(steps: [], repeatMode: .hold, repeatIntervalMS: 100, modifierProxy: false).isClickLock)
    }
}
