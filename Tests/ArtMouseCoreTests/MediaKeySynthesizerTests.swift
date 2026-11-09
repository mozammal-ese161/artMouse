import XCTest
import CoreGraphics
import AppKit
@testable import ArtMouseCore

// SDK adaptation: this SDK omits the deprecated CGEvent.integerValueField(_:) accessor;
// the read-only getIntegerValueField(_:) form is used for every field read below, and
// CGEventField(rawValue:) is failable, so the constant lookups are force-unwrapped.

final class MediaKeySynthesizerTests: XCTestCase {
    func testPlayKeyDownEncoding() {
        let event = MediaKeySynthesizer.makeEvent(keyCode: NXMediaKey.play, keyDown: true)
        XCTAssertEqual(event.type, CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue)))
        let data1 = event.getIntegerValueField(CGEventField(rawValue: 41)!)
        XCTAssertEqual(data1, (8 << 16) | (NXMediaKey.play << 8) | 0x0A)
        XCTAssertEqual(event.getIntegerValueField(CGEventField(rawValue: 42)!), -1)
    }

    func testKeyUpEncoding() {
        let event = MediaKeySynthesizer.makeEvent(keyCode: NXMediaKey.fast, keyDown: false)
        let data1 = event.getIntegerValueField(CGEventField(rawValue: 41)!)
        XCTAssertEqual(data1, (8 << 16) | (NXMediaKey.fast << 8) | 0x0B)
        XCTAssertEqual(event.getIntegerValueField(CGEventField(rawValue: 42)!), 0)
    }

    func testMusicOpsPostPressAndRelease() {
        let poster = RecordingPoster()
        let executor = ActionExecutor(poster: poster)
        executor.perform(.music(.playPause, fineTune: false))
        XCTAssertEqual(poster.events.count, 2)   // press + release of system-defined event
        // SDK adaptation: CGEventType.rawValue (UInt32) and NSEvent.EventType.rawValue (UInt)
        // differ in width, so the type is compared via CGEventType(rawValue:) instead.
        XCTAssertEqual(poster.events[0].type, CGEventType(rawValue: UInt32(NSEvent.EventType.systemDefined.rawValue)))
    }
}
