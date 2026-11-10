import XCTest
import CoreGraphics
@testable import ArtMouseCore

final class ScrollEmitterTests: XCTestCase {
    private var now = 0.0
    private let poster = RecordingPoster()

    private func makeEmitter() -> ScrollEmitter {
        ScrollEmitter(poster: poster)
    }

    func testEmitOncePostsLineDeltaOnAxis() {
        let emitter = makeEmitter()
        emitter.emitOnce(direction: .down, lines: 5)
        XCTAssertEqual(poster.events.count, 1)
        let event = poster.events[0]
        XCTAssertEqual(event.type, .scrollWheel)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventDeltaAxis1), -5, accuracy: 1e-9)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventDeltaAxis2), 0, accuracy: 1e-9)
    }

    func testEmitOnceHorizontalRight() {
        let emitter = makeEmitter()
        emitter.emitOnce(direction: .right, lines: 2)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis2), 2, accuracy: 1e-9)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis1), 0, accuracy: 1e-9)
    }

    // SDK ruling: chunk lines must be integral on this SDK — the scroll delta
    // fields are int-backed (setDoubleValueField truncates and
    // getDoubleValueField reads the int back; the 16.16 fixed-point field
    // quantizes at 1/65536), so the plan's fractional 6/5 = 1.2 chunk is not
    // representable in a real CGEvent here. lines 5 / emissions 5 keeps every
    // behavioral assertion (counts, cadence, idle) while staying representable.
    func testSmoothSpreadsLinesAcrossEmissions() {
        let emitter = makeEmitter()
        emitter.beginSmooth(direction: .up, lines: 5, intervalMS: 16, now: now)   // emissions = 80/16 = 5 → 1.0 each
        emitter.tick(now: now)                                                     // first chunk immediately
        XCTAssertEqual(poster.events.count, 1)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis1), 5.0 / 5.0, accuracy: 1e-9)
        for _ in 0..<4 { now += 0.016; emitter.tick(now: now) }
        XCTAssertEqual(poster.events.count, 5)
        XCTAssertFalse(emitter.isActive)                                           // all chunks emitted → idle
    }

    func testAutoEmitsThenStopsWithoutInput() {
        let emitter = makeEmitter()
        emitter.beginAuto(direction: .up, lines: 3, intervalMS: 50, stopAfterTicks: 3, now: now)
        // Plan ruling: beginAuto ARMS the emitter, so isActive is true here.
        // Pinned behavior ("isActive false only in idle") and Task 4's
        // testAutoModeStartsAndIntercepts (XCTAssertTrue after the controller
        // calls beginAuto) both require true; the plan's XCTAssertFalse
        // contradicts them. The "first emission after interval" intent is
        // verified by the per-tick event-count assertions below (a begin-time
        // emission would make count exceed i on the first tick).
        XCTAssertTrue(emitter.isActive)
        for i in 1...3 {
            now += 0.05
            emitter.tick(now: now)
            XCTAssertEqual(poster.events.count, i)
        }
        now += 0.05
        emitter.tick(now: now)                                                     // stopAfterTicks reached → stop
        XCTAssertEqual(poster.events.count, 3)
        XCTAssertFalse(emitter.isActive)
    }

    func testAutoCounterResetsOnInput() {
        let emitter = makeEmitter()
        emitter.beginAuto(direction: .up, lines: 3, intervalMS: 50, stopAfterTicks: 2, now: now)
        now += 0.05; emitter.tick(now: now)                        // emission 1
        emitter.noteInput(now: now)                                // refresh gap anchor (counter preserved)
        now += 0.05; emitter.tick(now: now)                        // emission 2
        now += 0.05; emitter.tick(now: now)                        // emission 3 (counter reached stopAfter)
        now += 0.05; emitter.tick(now: now)                        // stop, no emission
        XCTAssertEqual(poster.events.count, 3)
        XCTAssertFalse(emitter.isActive)
    }

    func testKeysDownThenRepeatThenReleaseAfterGap() {
        let emitter = makeEmitter()
        emitter.beginKeys(WheelKeyEmulation(keyCode: KeyCodes.f), direction: .up, now: now)
        XCTAssertEqual(poster.events.count, 1)                     // down
        XCTAssertEqual(poster.events[0].type, .keyDown)
        now += 0.10; emitter.tick(now: now)                        // repeat pair (down+up)
        XCTAssertEqual(poster.events.count, 3)
        now += 0.30; emitter.tick(now: now)                        // gap exceeded → key up → idle
        XCTAssertEqual(poster.events.count, 4)
        XCTAssertEqual(poster.events[3].type, .keyUp)
        XCTAssertFalse(emitter.isActive)
    }

    func testKeysWithoutRepeatPostsSingleDownAndUp() {
        let emitter = makeEmitter()
        emitter.beginKeys(WheelKeyEmulation(keyCode: KeyCodes.f, repeatWhileRolling: false), direction: .up, now: now)
        XCTAssertEqual(poster.events.count, 1)
        now += 0.30; emitter.tick(now: now)
        XCTAssertEqual(poster.events.count, 2)
        XCTAssertEqual(poster.events[1].type, .keyUp)
    }

    // Fix round 1 (review finding): begin* replaces `mode` unconditionally, so
    // starting smooth/auto/keys while a key is held would strand it with no UP
    // ever posted. The emitter owns keysDown, so it releases first.
    func testBeginOverKeysReleasesHeldKey() {
        let emitter = makeEmitter()
        emitter.beginKeys(WheelKeyEmulation(keyCode: KeyCodes.f), direction: .up, now: now)
        XCTAssertEqual(poster.events.count, 1)                     // down
        now = 0.05
        emitter.beginAuto(direction: .up, lines: 3, intervalMS: 50, stopAfterTicks: 2, now: now)
        let up = poster.events.first(where: { $0.type == .keyUp })
        XCTAssertNotNil(up)                                        // held F released
        XCTAssertEqual(up.map { UInt64($0.getIntegerValueField(.keyboardEventKeycode)) }, KeyCodes.f)
        XCTAssertTrue(emitter.isActive)                            // auto running
    }

    func testBeginKeysReleasesPreviousKey() {
        let emitter = makeEmitter()
        emitter.beginKeys(WheelKeyEmulation(keyCode: KeyCodes.f), direction: .up, now: now)
        XCTAssertEqual(poster.events.count, 1)
        now = 0.05
        emitter.beginKeys(WheelKeyEmulation(keyCode: 40), direction: .up, now: now)
        XCTAssertEqual(poster.events.count, 3)                     // down F, up F, down 40
        XCTAssertEqual(poster.events[1].type, .keyUp)
        XCTAssertEqual(UInt64(poster.events[1].getIntegerValueField(.keyboardEventKeycode)), KeyCodes.f)
        XCTAssertEqual(UInt64(poster.events[2].getIntegerValueField(.keyboardEventKeycode)), 40)
    }
}
