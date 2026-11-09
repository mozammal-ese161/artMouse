import AppKit
import CoreGraphics

public protocol WorkspaceOpening: AnyObject {
    func launchApp(bundleID: String)
    func openURL(_ url: URL)
    func openFile(path: String)
}

public final class NSWorkspaceOpener: WorkspaceOpening {
    public init() {}
    public func launchApp(bundleID: String) {
        NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleID, options: [.withoutActivation], additionalEventParamDescriptor: nil, launchIdentifier: nil)
    }
    public func openURL(_ url: URL) { NSWorkspace.shared.open(url) }
    public func openFile(path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
}

public final class ActionExecutor: ActionExecuting {
    private let poster: EventPosting
    private let workspace: WorkspaceOpening

    public init(poster: EventPosting, workspace: WorkspaceOpening = NSWorkspaceOpener()) {
        self.poster = poster
        self.workspace = workspace
    }

    public func perform(_ action: Action) {
        switch action {
        case .none:
            break
        case .click(let op, let mods):
            performClick(op, mods: mods)
        case .mission, .music, .zoom, .switcher, .open, .device:
            performAction(action)   // Task 10 replaces this stub dispatch
        }
    }

    public func beganHold(_ action: Action) { performAction(action) }   // precision-mode begin, Task 13
    public func endedHold(_ action: Action) {}                          // precision-mode end, Task 13

    /// Used by ClickLockCoordinator to post lock-phase button events.
    public func postButton(_ id: ButtonID, down: Bool, mods: ModKeys) {
        postButtonEvent(id, down: down, mods: mods, clickState: 1)
    }

    private func performClick(_ op: ClickOp, mods: ModKeys) {
        switch op {
        case .clickLock:
            break   // engine-level; EventRouter + ClickLockCoordinator own it
        case .doubleLeft:
            postStandardClick(.left, clickState: 1, mods: mods)
            postStandardClick(.left, clickState: 2, mods: mods)
        case .left:
            postStandardClick(.left, clickState: 1, mods: mods)
        case .middle:
            postButtonEvent(.middle, down: true, mods: mods, clickState: 1)
            postButtonEvent(.middle, down: false, mods: mods, clickState: 1)
        case .right:
            postButtonEvent(.right, down: true, mods: mods, clickState: 1)
            postButtonEvent(.right, down: false, mods: mods, clickState: 1)
        case .fourth:
            postButtonEvent(.fourth, down: true, mods: mods, clickState: 1)
            postButtonEvent(.fourth, down: false, mods: mods, clickState: 1)
        case .fifth:
            postButtonEvent(.fifth, down: true, mods: mods, clickState: 1)
            postButtonEvent(.fifth, down: false, mods: mods, clickState: 1)
        }
    }

    private func postStandardClick(_ button: ButtonID, clickState: Int64, mods: ModKeys) {
        postButtonEvent(button, down: true, mods: mods, clickState: clickState)
        postButtonEvent(button, down: false, mods: mods, clickState: clickState)
    }

    private func postButtonEvent(_ id: ButtonID, down: Bool, mods: ModKeys, clickState: Int64) {
        let number = id.cgButtonNumber
        let type: CGEventType
        switch (id, down) {
        case (.left, true): type = .leftMouseDown
        case (.left, false): type = .leftMouseUp
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        case (_, true): type = .otherMouseDown
        case (_, false): type = .otherMouseUp
        }
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: UInt32(clamping: number)) ?? .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.flags = CGFlagConversion.cgFlags(mods)
        poster.post(event)
    }

    private func performAction(_ action: Action) {
        // Task 10 fills mission/music/zoom/switcher/open dispatch.
    }
}
