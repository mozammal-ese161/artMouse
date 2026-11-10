import XCTest
@testable import ArtMouseCore

final class ChordEngineTests: XCTestCase {
    private let executor = RecordingExecutor()   // present only to prove ChordEngine never performs

    private func makeEngine(_ chords: [Chord]) -> ChordEngine {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(directory: dir)
        store.settings.chords = chords
        return ChordEngine(settings: store)
    }

    func testChordStartButtonCapturesAndCompletes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none])])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .fire([.none]))
        XCTAssertTrue(executor.performed.isEmpty)   // router executes, not the engine
    }

    func testNonChordButtonRoutes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none])])
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0), .route)
    }

    func testSoloReleaseFlushes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.click(.left, [])])])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonUp(.middle), now: 0.05), .flush([.middle]))
    }

    func testReleasingInitiatorFlushesAllHeld() {
        // 4-button chord so every down below EXTENDS (none set-equals) and the
        // capture is still alive with three held buttons when the initiator lifts.
        let engine = makeEngine([Chord(buttons: [.middle, .fourth, .fifth, .left], actions: [.none], timeout: 1.0)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.10), .consume)
        // Initiator released mid-chord: the chord is abandoned — everything held flushes.
        XCTAssertEqual(engine.intercept(.buttonUp(.middle), now: 0.15), .flush([.middle, .fourth, .fifth]))
    }

    func testNonInitiatorReleaseThenInitiatorReleaseFlushes() {
        // 3-button chord so the fourth press extends instead of completing.
        let engine = makeEngine([Chord(buttons: [.middle, .fourth, .fifth], actions: [.none])])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .consume)
        XCTAssertEqual(engine.intercept(.buttonUp(.fourth), now: 0.10), .consume)   // capture continues
        XCTAssertEqual(engine.intercept(.buttonUp(.middle), now: 0.15), .flush([.middle]))  // held is [middle] — fourth already left
    }

    func testTimeoutFlushesOnNextEvent() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth],
                                       actions: [.click(.left, [])], timeout: 0.3)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.35), .flush([.middle]))
        // Router re-sends after flushing; fresh capture works again:
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0.36), .consume)
    }

    func testSubsetExtendsThenCompletes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth, .fifth], actions: [.none])])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .consume)   // subset extends
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.10), .fire([.none]))  // completes
    }

    func testLongestCandidateChordTimeoutGoverns() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none], timeout: 0.2),
                                 Chord(buttons: [.middle, .fourth, .fifth], actions: [.none], timeout: 0.6)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .consume)
        // The 3-button candidate's 0.6 timeout governs while it remains completable.
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.5), .fire([.none]))
    }

    func testUpsAfterFiredChordRoute() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none])])
        _ = engine.intercept(.buttonDown(.middle), now: 0)
        _ = engine.intercept(.buttonDown(.fourth), now: 0.05)
        XCTAssertEqual(engine.intercept(.buttonUp(.middle), now: 0.1), .route)
        XCTAssertEqual(engine.intercept(.buttonUp(.fourth), now: 0.12), .route)
    }

    func testPartialReleaseOfThreeButtonChord() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth, .fifth], actions: [.none], timeout: 1.0)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.05), .consume)
        XCTAssertEqual(engine.intercept(.buttonUp(.fourth), now: 0.10), .consume)   // release one: capture continues
        XCTAssertEqual(engine.intercept(.buttonDown(.fourth), now: 0.15), .consume) // re-press re-extends
        XCTAssertEqual(engine.intercept(.buttonDown(.fifth), now: 0.20), .fire([.none]))
    }

    func testRePressOfHeldButtonConsumes() {
        let engine = makeEngine([Chord(buttons: [.middle, .fourth], actions: [.none], timeout: 1.0)])
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0), .consume)
        XCTAssertEqual(engine.intercept(.buttonDown(.middle), now: 0.05), .consume)  // already held
    }
}
