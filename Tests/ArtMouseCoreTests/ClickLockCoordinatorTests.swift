import XCTest
@testable import ArtMouseCore

final class ClickLockCoordinatorTests: XCTestCase {
    private var now = 0.0

    func testNormalClickPostsDownAndUp() {
        let coordinator = makeCoordinator()
        coordinator.noteDown(.left, now: 0.0)
        let swallowed = coordinator.noteUp(.left, now: 0.1)
        XCTAssertFalse(swallowed)
    }

    func testReleaseAfterThresholdLocks() {
        let coordinator = makeCoordinator()
        coordinator.noteDown(.left, now: 0.0)
        let swallowed = coordinator.noteUp(.left, now: 0.6)
        XCTAssertTrue(swallowed)                     // physical release ignored
        XCTAssertTrue(coordinator.isLocked(.left))   // sticky down
    }

    func testNextClickReleasesLock() {
        let coordinator = makeCoordinator()
        coordinator.noteDown(.left, now: 0.0)
        _ = coordinator.noteUp(.left, now: 0.6)      // locks
        XCTAssertTrue(coordinator.shouldSwallowDown(.left))
        XCTAssertFalse(coordinator.isLocked(.left))  // released
    }

    func testButtonsTrackIndependently() {
        let coordinator = makeCoordinator()
        coordinator.noteDown(.left, now: 0.0)
        _ = coordinator.noteUp(.left, now: 0.6)      // left locks
        XCTAssertFalse(coordinator.shouldSwallowDown(.right))
        XCTAssertTrue(coordinator.isLocked(.left))
        XCTAssertFalse(coordinator.isLocked(.right))
    }

    func testLockReleasePostsSyntheticUp() {
        let executor = RecordingExecutor()
        let coordinator = ClickLockCoordinator(executor: executor, clock: { 0 }, threshold: 0.5)
        coordinator.noteDown(.left, now: 0.0)
        _ = coordinator.noteUp(.left, now: 0.6)          // locks
        XCTAssertTrue(coordinator.shouldSwallowDown(.left))
        XCTAssertTrue(executor.postedButtons.contains { $0.0 == .left && $0.1 == false })
    }

    private func makeCoordinator() -> ClickLockCoordinator {
        ClickLockCoordinator(executor: RecordingExecutor(), clock: { [weak self] in self?.now ?? 0 }, threshold: 0.5)
    }
}
