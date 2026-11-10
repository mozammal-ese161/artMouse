import XCTest
import ArtMouseCore

final class HIDEventLogTests: XCTestCase {
    private func observation(value: Int = 1) -> RawHIDObservation {
        RawHIDObservation(vendorID: 111, productID: 222, usagePage: 0x09, usage: 0x10, value: value)
    }

    func testRingBufferBounds() {
        let log = HIDEventLog(maxEntries: 3)
        for i in 0..<5 { log.record(observation(value: i)) }
        XCTAssertEqual(log.entries.count, 3)
        XCTAssertTrue(log.entries.allSatisfy { $0.contains("value=") })
    }

    func testFormattedLineContainsIdentityAndHex() {
        var now = Date(timeIntervalSince1970: 0)
        let log = HIDEventLog(now: { now = now.addingTimeInterval(1); return now })
        log.record(observation())
        let line = try! XCTUnwrap(log.entries.first)
        XCTAssertTrue(line.contains("vid=111"))
        XCTAssertTrue(line.contains("pid=222"))
        XCTAssertTrue(line.contains("page=0x9"))
        XCTAssertTrue(line.contains("usage=0x10"))
        XCTAssertTrue(line.contains("value=1"))
    }

    func testPersistenceAppendsToFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("devices.log")
        let log = HIDEventLog(fileURL: fileURL, persistToFile: true)
        log.record(observation())
        log.record(observation(value: 2))
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(contents.split(separator: "\n").count, 2)
        XCTAssertTrue(contents.contains("value=2"))
    }

    func testPersistenceOffWritesNothing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("devices.log")
        let log = HIDEventLog(fileURL: fileURL, persistToFile: false)
        log.record(observation())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        log.setPersistToFile(true)
        log.record(observation(value: 3))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testClearAndAnalyzerBound() {
        let log = HIDEventLog(maxEntries: 2)
        log.record(observation())
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
        let analyzer = HIDAnalyzerStore(maxEntries: 2)
        analyzer.record(observation())
        analyzer.record(observation())
        analyzer.record(observation(value: 9))
        XCTAssertEqual(analyzer.recent.count, 2)
        XCTAssertEqual(analyzer.recent.last?.value, 9)
        analyzer.clear()
        XCTAssertTrue(analyzer.recent.isEmpty)
    }
}
