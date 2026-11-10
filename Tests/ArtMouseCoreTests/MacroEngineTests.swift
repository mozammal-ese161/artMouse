import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class MacroEngineTests: XCTestCase {
    private let poster = RecordingPoster()
    private var sleptMS: [Int] = []
    private var physicalFlags: ModKeys = []

    private func makeEngine() -> MacroEngine {
        MacroEngine(
            poster: poster,
            cursorLocation: { CGPoint(x: 11, y: 22) },
            sleep: { [weak self] ms in self?.sleptMS.append(ms) },
            flagReader: { [weak self] in self?.physicalFlags ?? [] })
    }

    func testEnterKeyPostsDownUpPair() async {
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.enterKey(keyCode: 40, mods: [.command])], repeatMode: .none,
            repeatIntervalMS: 100, modifierProxy: false), for: .middle)
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .keyDown)
        XCTAssertEqual(UInt64(poster.events[0].getIntegerValueField(.keyboardEventKeycode)), 40)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertEqual(poster.events[1].type, .keyUp)
    }

    func testWaitSleepsAndPostsNothing() async {
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.wait(milliseconds: 250), .enterKey(keyCode: 5, mods: [])],
            repeatMode: .none, repeatIntervalMS: 100, modifierProxy: false), for: .middle)
        XCTAssertEqual(sleptMS, [250])
        XCTAssertEqual(poster.events.count, 2)   // only the key pair
    }

    func testClickStepPostsPairAtCursorLocation() async {
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.click(op: .left, mods: [])], repeatMode: .none,
            repeatIntervalMS: 100, modifierProxy: false), for: .middle)
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[0].type, .leftMouseDown)
        XCTAssertEqual(poster.events[0].location.x, 11, accuracy: 1e-9)
        XCTAssertEqual(poster.events[0].location.y, 22, accuracy: 1e-9)
    }

    func testModifierProxyMergesPhysicalFlags() async {
        physicalFlags = [.shift]
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.enterKey(keyCode: 5, mods: [.command])], repeatMode: .none,
            repeatIntervalMS: 100, modifierProxy: true), for: .middle)
        XCTAssertTrue(poster.events[0].flags.contains(.maskCommand))
        XCTAssertTrue(poster.events[0].flags.contains(.maskShift))
    }

    func testWaitClampedToRange() async {
        let engine = makeEngine()
        await engine.runAndWait(program: MacroProgram(
            steps: [.wait(milliseconds: 99_999)], repeatMode: .none,
            repeatIntervalMS: 100, modifierProxy: false), for: .middle)
        XCTAssertEqual(sleptMS, [60_000])   // clamped 1...60000
    }

    func testHoldRepeatRunsUntilStop() async {
        let engine = makeEngine()
        engine.run(program: MacroProgram(
            steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .hold,
            repeatIntervalMS: 10, modifierProxy: false), for: .middle)
        XCTAssertTrue(engine.isRunning(for: .middle))
        // Deterministic drain: the injected sleep records instead of waiting;
        // poll until at least two sequences have executed.
        while poster.events.count < 4 { await Task.yield() }
        engine.stop(for: .middle)
        let countAtStop = poster.events.count
        XCTAssertTrue(countAtStop >= 4 && countAtStop % 2 == 0)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(poster.events.count, countAtStop)   // stopped
        XCTAssertFalse(engine.isRunning(for: .middle))
    }

    func testStopAllStopsEveryButton() async {
        let engine = makeEngine()
        engine.run(program: MacroProgram(
            steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .hold,
            repeatIntervalMS: 10, modifierProxy: false), for: .middle)
        engine.run(program: MacroProgram(
            steps: [.enterKey(keyCode: 6, mods: [])], repeatMode: .hold,
            repeatIntervalMS: 10, modifierProxy: false), for: .fourth)
        while poster.events.count < 4 { await Task.yield() }
        engine.stopAll()
        for _ in 0..<20 { await Task.yield() }
        let countAtStop = poster.events.count
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(poster.events.count, countAtStop)
        XCTAssertFalse(engine.isRunning(for: .middle))
        XCTAssertFalse(engine.isRunning(for: .fourth))
    }
}

/// Synchronous single-pass execution without the Task wrapper, so tests
/// await the engine's internal sequence directly and assert deterministically.
private extension MacroEngine {
    func runAndWait(program: MacroProgram, for button: ButtonID) async {
        await execute(program: program)
    }
}
