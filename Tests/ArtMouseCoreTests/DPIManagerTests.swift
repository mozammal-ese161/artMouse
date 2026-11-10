import XCTest
import ArtMouseCore

final class DPIManagerTests: XCTestCase {
    final class Recorder {
        var calls: [(profile: DeviceProfile, level: Int, index: Int)] = []
        var succeed = true
        func apply(_ profile: DeviceProfile, _ level: Int, _ index: Int) -> Bool {
            calls.append((profile, level, index))
            return succeed
        }
    }

    private func profile(levels: [Int], active: Int = 0) -> DeviceProfile {
        DeviceProfile(name: "m", vendorID: 1, productID: 2,
                      dpi: DeviceDPIConfig(levels: levels, activeLevelIndex: active))
    }

    func testApplyUpAndDownClampAtBounds() {
        let recorder = Recorder()
        let device = profile(levels: [800, 1600, 3200], active: 2)
        let manager = DPIManager(profileProvider: { device },
                                 applyLevel: { recorder.apply($0, $1, $2) })
        XCTAssertTrue(manager.apply(.up))     // already last → stays at index 2
        XCTAssertEqual(recorder.calls.last?.index, 2)
        XCTAssertTrue(manager.apply(.down))
        XCTAssertEqual(recorder.calls.last?.level, 1600)
    }

    func testApplyCycleAndRestoreDefault() {
        let recorder = Recorder()
        let device = profile(levels: [800, 1600, 3200], active: 2)
        let manager = DPIManager(profileProvider: { device },
                                 applyLevel: { recorder.apply($0, $1, $2) })
        XCTAssertTrue(manager.apply(.cycle))   // 2 → 0
        XCTAssertEqual(recorder.calls.last?.index, 0)
        XCTAssertTrue(manager.apply(.restoreDefault))
        XCTAssertEqual(recorder.calls.last?.index, 0)
        XCTAssertEqual(recorder.calls.last?.level, 800)
    }

    func testApplyWithoutConfigReturnsFalse() {
        let manager = DPIManager(profileProvider: { DeviceProfile(name: "m", vendorID: 1, productID: 2) },
                                 applyLevel: { _, _, _ in true })
        XCTAssertFalse(manager.apply(.cycle))
        let empty = profile(levels: [])
        let emptyManager = DPIManager(profileProvider: { empty }, applyLevel: { _, _, _ in true })
        XCTAssertFalse(emptyManager.apply(.cycle))
    }

    func testShiftRaisesThenRestores() {
        let recorder = Recorder()
        let device = profile(levels: [800, 1600, 3200], active: 0)
        let manager = DPIManager(profileProvider: { device },
                                 applyLevel: { recorder.apply($0, $1, $2) })
        XCTAssertTrue(manager.beginShift())
        XCTAssertEqual(recorder.calls.last?.level, 1600)
        manager.endShift()
        XCTAssertEqual(recorder.calls.last?.level, 800)
        XCTAssertEqual(recorder.calls.last?.index, 0)
    }

    func testShiftOnLastLevelReturnsFalseAndNeverSends() {
        let recorder = Recorder()
        let device = profile(levels: [800, 1600], active: 1)
        let manager = DPIManager(profileProvider: { device },
                                 applyLevel: { recorder.apply($0, $1, $2) })
        XCTAssertFalse(manager.beginShift())
        XCTAssertTrue(recorder.calls.isEmpty)
        manager.endShift()   // no origin: must not send
        XCTAssertTrue(recorder.calls.isEmpty)
    }
}
