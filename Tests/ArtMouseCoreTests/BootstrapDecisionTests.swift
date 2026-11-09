import XCTest
@testable import ArtMouseCore

final class BootstrapDecisionTests: XCTestCase {
    func testNormalLaunchRunsEngine() {
        XCTAssertTrue(BootstrapDecision.shouldRunEngine(arguments: [], flagsAtLaunch: []))
    }

    func testSafeModeFlagDisablesEngine() {
        XCTAssertFalse(BootstrapDecision.shouldRunEngine(arguments: ["--safe-mode"], flagsAtLaunch: []))
    }

    func testCommandOptionHeldAtLaunchDisablesEngine() {
        XCTAssertFalse(BootstrapDecision.shouldRunEngine(arguments: [], flagsAtLaunch: [.command, .option]))
        XCTAssertTrue(BootstrapDecision.shouldRunEngine(arguments: [], flagsAtLaunch: [.command]))
        XCTAssertTrue(BootstrapDecision.shouldRunEngine(arguments: [], flagsAtLaunch: [.option, .shift]))
    }
}
