import XCTest
@testable import ArtMouseCore

final class ActionModelTests: XCTestCase {
    func testButtonIDCodableRoundTrip() throws {
        let original: [ButtonID] = [.left, .right, .middle, .fourth, .fifth, .extended(7)]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([ButtonID].self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
