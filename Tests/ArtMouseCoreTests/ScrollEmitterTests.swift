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

    // Carry scheme: smooth emits INTEGRAL line counts with a fractional
    // carry, so integer-line consumers always see a nonzero delta. lines 6
    // over emissions 5 (80/16) gives chunk 1.2 — the carry accumulates
    // 1, 1, 1, 1, 2 for a 6-line total.
    func testSmoothSpreadsLinesAcrossEmissions() {
        let emitter = makeEmitter()
        emitter.beginSmooth(direction: .up, lines: 6, intervalMS: 16, now: now)   // emissions = 80/16 = 5 → 1.2 each
        emitter.tick(now: now)                                                     // first chunk immediately
        XCTAssertEqual(poster.events.count, 1)
        XCTAssertEqual(poster.events[0].getDoubleValueField(.scrollWheelEventDeltaAxis1), 1, accuracy: 1e-9)
        var axis1: [Double] = [1]
        for _ in 0..<4 {
            now += 0.016
            emitter.tick(now: now)
            axis1.append(poster.events.last!.getDoubleValueField(.scrollWheelEventDeltaAxis1))
        }
        let expected: [Double] = [1, 1, 1, 1, 2]
        for (index, value) in axis1.enumerated() {
            XCTAssertEqual(value, expected[index], accuracy: 1e-9, "emission \(index)")   // carry-accumulated
        }
        XCTAssertEqual(axis1.reduce(0, +), 6, accuracy: 1e-9)                      // total distance preserved
        XCTAssertFalse(emitter.isActive)                                           // drained → idle
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

    // Fix round 1 (escalated Task 3 note): tick's .auto case stored `due` but
    // never gated on it, so Task 8's 8 ms pump would emit at ~8 ms regardless
    // of autoIntervalMS.
    func testAutoRespectsIntervalUnderFastPump() {
        let emitter = makeEmitter()
        emitter.beginAuto(direction: .up, lines: 3, intervalMS: 50, stopAfterTicks: 10, now: now)
        for _ in 0..<5 { now += 0.008; emitter.tick(now: now) }    // 8 ms pump → interval not reached
        XCTAssertEqual(poster.events.count, 0)
        now += 0.01                                                // now = 0.05 = due
        emitter.tick(now: now)
        XCTAssertEqual(poster.events.count, 1)
    }

    // Fix round 1 (review finding): a profile switch must end a live auto
    // immediately.
    func testStopHaltsAuto() {
        let emitter = makeEmitter()
        emitter.beginAuto(direction: .up, lines: 3, intervalMS: 50, stopAfterTicks: 10, now: now)
        XCTAssertTrue(emitter.isActive)
        emitter.stop()
        now += 0.05; emitter.tick(now: now)
        XCTAssertEqual(poster.events.count, 0)
        XCTAssertFalse(emitter.isActive)
    }

    // MARK: Free-spin momentum (Phase 4)

    // Coast sequence: after 0.12 s of input silence the primed momentum
    // emits the full linesPerTick, then each 16 ms step decays by
    // decayPercent until the next step falls below the 0.05-line floor —
    // strictly decreasing, then idle, never resurrecting itself.
    func testMomentumCoastStartsAfterInputSilenceAndDecays() {
        let emitter = makeEmitter()
        emitter.primeMomentum(direction: .down, linesPerTick: 3, decayPercent: 50,
                              maxLines: 100, now: now)
        emitter.tick(now: 0.05)                                // inside the gap: nothing
        XCTAssertEqual(poster.events.count, 0)
        emitter.tick(now: 0.13)                                // gap elapsed: first coast step
        XCTAssertEqual(poster.events.count, 1)
        emitter.tick(now: 0.15)                                // step 2: 1.5
        emitter.tick(now: 0.17)                                // step 3: 0.75
        emitter.tick(now: 0.19)                                // step 4: 0.375
        emitter.tick(now: 0.21)                                // step 5: 0.1875
        emitter.tick(now: 0.23)                                // next decay 0.046875 < floor → idle
        let expected: [Double] = [-3, -1.5, -0.75, -0.375, -0.1875, -0.09375]
        let amounts = poster.events.map { fixedPtLines($0) }
        XCTAssertEqual(amounts.count, expected.count)
        for (index, value) in amounts.enumerated() {
            XCTAssertEqual(value, expected[index], accuracy: 1e-9, "coast step \(index)")
        }
        for pair in zip(amounts, amounts.dropFirst()) {
            XCTAssertLessThan(abs(pair.1), abs(pair.0))        // strictly decaying magnitude
        }
        XCTAssertFalse(emitter.isActive)                       // decayed past the floor → idle
        emitter.tick(now: 1.0)                                 // a spent coast must not restart
        XCTAssertEqual(poster.events.count, expected.count)
    }

    // Review Focus 5: momentum is constant-mode-only. While a keys run owns
    // the emitter the primed momentum must never coast over it — not during
    // the run, and not after the release gap drops the emitter back to idle
    // (stop-equivalent idle transitions discard the primed state).
    func testMomentumNeverCoastsUnderAnotherOwner() {
        let emitter = makeEmitter()
        emitter.beginKeys(WheelKeyEmulation(keyCode: KeyCodes.f), direction: .down, now: now)
        emitter.primeMomentum(direction: .down, linesPerTick: 3, decayPercent: 50,
                              maxLines: 100, now: now)
        emitter.tick(now: 0.05)                                // keys run open: coast refused
        XCTAssertEqual(poster.events.filter { $0.type == .scrollWheel }.count, 0)
        emitter.tick(now: 1.0)                                 // release gap exceeded → key up → idle
        XCTAssertEqual(poster.events.filter { $0.type == .scrollWheel }.count, 0)
        emitter.tick(now: 1.5)                                 // idle again, but no primed momentum left
        XCTAssertEqual(poster.events.filter { $0.type == .scrollWheel }.count, 0)
        XCTAssertEqual(poster.events.filter { $0.type == .keyUp }.count, 1)   // keys still behave: F released
    }

    // The coast is capped: total posted lines must never exceed maxLines
    // plus the first step (the step that crosses the cap still posts whole).
    func testMomentumCappedByMaxLines() {
        let emitter = makeEmitter()
        emitter.primeMomentum(direction: .down, linesPerTick: 3, decayPercent: 95,
                              maxLines: 5, now: now)
        for t in stride(from: 0.13, through: 2.0, by: 0.02) { emitter.tick(now: t) }
        let totalFixedPt = poster.events.reduce(Int64(0)) {
            $0 + $1.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
        }
        XCTAssertLessThanOrEqual(abs(totalFixedPt), Int64(8 * 65536))   // ≤ (5 + 3) lines of fixed-pt units
        XCTAssertEqual(poster.events.count, 2)                 // 3 + 2.85 = 5.85 ≥ cap → idle
        XCTAssertFalse(emitter.isActive)
    }

    // noteInput cancels a live coast AND its primed state: only a fresh
    // primeMomentum restarts the sequence.
    func testNewInputCancelsLiveCoast() {
        let emitter = makeEmitter()
        emitter.primeMomentum(direction: .down, linesPerTick: 3, decayPercent: 50,
                              maxLines: 100, now: now)
        emitter.tick(now: 0.13)                                // coast begins, first step posts
        XCTAssertEqual(poster.events.count, 1)
        emitter.noteInput(now: 0.14)                           // real wheel tick lands
        emitter.tick(now: 0.30)                                // silence again, but no fresh prime
        emitter.tick(now: 1.0)
        XCTAssertEqual(poster.events.count, 1, "cancelled coast must not restart without a prime")
        XCTAssertFalse(emitter.isActive)
    }

    /// Line amount of a recorded scroll post read off the 16.16 fixed-point
    /// delta field — the emitter carries fractional coast steps there, and
    /// the line fields truncate.
    private func fixedPtLines(_ event: CGEvent) -> Double {
        Double(event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)) / 65536.0
    }
}
