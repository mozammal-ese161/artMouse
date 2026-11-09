import XCTest
@testable import ArtMouseCore

final class CursorMathTests: XCTestCase {
    func testSensitivityScalesLinearly() {
        XCTAssertEqual(CursorMath.sensitivityFactor(1600), 1.0, accuracy: 1e-12)
        XCTAssertEqual(CursorMath.sensitivityFactor(800), 0.5, accuracy: 1e-12)
        XCTAssertEqual(CursorMath.sensitivityFactor(3200), 2.0, accuracy: 1e-12)
    }

    func testAccelerationIsOneAtRest() {
        XCTAssertEqual(CursorMath.accelerationFactor(acceleration: 3.0, speed: 0), 1.0, accuracy: 1e-12)
    }

    func testAccelerationGrowsWithSpeed() {
        let slow = CursorMath.accelerationFactor(acceleration: 1.0, speed: 2)
        let fast = CursorMath.accelerationFactor(acceleration: 1.0, speed: 16)
        XCTAssertEqual(slow, 1.25, accuracy: 1e-12)
        XCTAssertEqual(fast, 3.0, accuracy: 1e-12)
        XCTAssertLessThan(slow, fast)
    }

    func testZeroAccelerationIsAlwaysOne() {
        for speed in [0.0, 1.0, 5.0, 20.0, 100.0] {
            XCTAssertEqual(CursorMath.accelerationFactor(acceleration: 0, speed: speed), 1.0, accuracy: 1e-12)
        }
    }

    func testDeltaFactorCombinesBoth() {
        let profile = CursorSpeedProfile(name: "T", sensitivity: 800, acceleration: 1.0)
        let factor = CursorMath.deltaFactor(profile: profile, speed: 8)   // speed = reference
        XCTAssertEqual(factor.dxFactor, 0.5 * 2.0, accuracy: 1e-12)
        XCTAssertEqual(factor.dyFactor, 0.5 * 2.0, accuracy: 1e-12)
    }
}
