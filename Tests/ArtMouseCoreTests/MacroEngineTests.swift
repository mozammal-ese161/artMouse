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
        // Real-time settle: a straggler pair can straddle yield windows when
        // the OS preempts the task between its own down and up posts.
        try? await Task.sleep(nanoseconds: 30_000_000)
        for _ in 0..<20 { await Task.yield() }
        let count1 = poster.events.count
        XCTAssertTrue(count1 - countAtStop <= 2)   // ≤ one in-flight pair (straggle)
        for _ in 0..<20 { await Task.yield() }
        let count2 = poster.events.count
        XCTAssertEqual(count2, count1)             // stable: loop halted
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
        let countAtStop = poster.events.count
        // Real-time settle: a straggler pair can straddle yield windows when
        // the OS preempts the task between its own down and up posts.
        try? await Task.sleep(nanoseconds: 30_000_000)
        for _ in 0..<20 { await Task.yield() }
        let count1 = poster.events.count
        XCTAssertTrue(count1 - countAtStop <= 4)          // ≤ one in-flight pair per task
        for _ in 0..<20 { await Task.yield() }
        let count2 = poster.events.count
        XCTAssertEqual(count2, count1)                    // stable: loops halted
        XCTAssertFalse(engine.isRunning(for: .middle))
        XCTAssertFalse(engine.isRunning(for: .fourth))
    }

    // Same-button rapid re-trigger: run A, then run B (different keycode)
    // immediately. The OLD task's hopped finishTask must never clobber the
    // NEW run's registration — when it does, the new loop keeps running but
    // unregistered, so stop(for:) no-ops on it and events keep flowing.
    func testRapidRerunKeepsNewRegistration() async {
        let engine = makeEngine()
        engine.run(program: MacroProgram(
            steps: [.enterKey(keyCode: 5, mods: [])], repeatMode: .hold,
            repeatIntervalMS: 10, modifierProxy: false), for: .middle)
        engine.run(program: MacroProgram(
            steps: [.enterKey(keyCode: 6, mods: [])], repeatMode: .hold,
            repeatIntervalMS: 10, modifierProxy: false), for: .middle)
        // Real-time settle while the NEW program is registered: the OLD task's
        // hopped finishTask needs a window to land here. Without one, the hop
        // lands after the stop below (dict already empty) and the clobber is
        // never exercised — the suite's standard settle idiom makes this test
        // deterministic.
        try? await Task.sleep(nanoseconds: 30_000_000)
        engine.stop(for: .middle)
        let countAtStop = poster.events.count
        // Real-time settle: a straggler pair can straddle yield windows when
        // the OS preempts the task between its own down and up posts.
        try? await Task.sleep(nanoseconds: 30_000_000)
        for _ in 0..<20 { await Task.yield() }
        let count1 = poster.events.count
        XCTAssertTrue(count1 - countAtStop <= 2)   // ≤ one in-flight pair
        for _ in 0..<20 { await Task.yield() }
        let count2 = poster.events.count
        XCTAssertEqual(count2, count1)             // stable: loop halted
        XCTAssertFalse(engine.isRunning(for: .middle))
    }
}

/// Synchronous single-pass execution without the Task wrapper, so tests
/// await the engine's internal sequence directly and assert deterministically.
private extension MacroEngine {
    func runAndWait(program: MacroProgram, for button: ButtonID) async {
        await execute(program: program)
    }
}
