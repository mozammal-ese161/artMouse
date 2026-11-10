import XCTest
import ArtMouseCore

final class DPIReportBuilderTests: XCTestCase {
    func testPayloadWritesLittleEndianLevelAtValueByte() {
        let config = DeviceDPIConfig(levels: [800, 1600, 3200], reportID: 5,
                                     valueByte: 1, valueMask: 0xFFFF, reportLength: 4)
        XCTAssertEqual(Array(DPIReportBuilder.payload(config: config, level: 1600)),
                       [0x00, 0x40, 0x06, 0x00])   // 1600 = 0x0640 little-endian at byte 1
    }

    func testPayloadMaskLimitsValue() {
        let config = DeviceDPIConfig(levels: [800], valueByte: 0, valueMask: 0x00FF, reportLength: 2)
        XCTAssertEqual(Array(DPIReportBuilder.payload(config: config, level: 1600)),
                       [0x40, 0x00])   // 1600 & 0xFF = 0x40
    }

    func testPayloadClampsOutOfBoundsLayout() {
        // Absurd declared layouts must produce a bounded payload, never crash
        // (Review Focus 3).
        let config = DeviceDPIConfig(levels: [800], valueByte: 9, valueMask: 0xFFFF, reportLength: 0)
        XCTAssertEqual(DPIReportBuilder.payload(config: config, level: 800).count, 1)
        let beyond = DeviceDPIConfig(levels: [800], valueByte: 3, valueMask: 0xFFFF, reportLength: 2)
        XCTAssertEqual(DPIReportBuilder.payload(config: beyond, level: 800).count, 2)
    }

    func testClampedLevelIndex() {
        XCTAssertEqual(DPIReportBuilder.clampedLevelIndex(-5, levelCount: 3), 0)
        XCTAssertEqual(DPIReportBuilder.clampedLevelIndex(2, levelCount: 3), 2)
        XCTAssertEqual(DPIReportBuilder.clampedLevelIndex(9, levelCount: 3), 2)
        XCTAssertEqual(DPIReportBuilder.clampedLevelIndex(0, levelCount: 0), 0)
    }
}
