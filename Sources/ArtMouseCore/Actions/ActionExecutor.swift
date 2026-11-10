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
    private let cursorLocation: () -> CGPoint
    /// Weak: the executor lives in the router graph alongside its cursor controller,
    /// so a strong reference here would be a cycle (Task 13).
    private weak var cursor: CursorCoordinating?

    public init(poster: EventPosting,
                workspace: WorkspaceOpening = NSWorkspaceOpener(),
                cursor: CursorCoordinating? = nil,
                cursorLocation: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero }) {
        self.poster = poster
        self.workspace = workspace
        self.cursor = cursor
        self.cursorLocation = cursorLocation
    }

    public func perform(_ action: Action) {
        switch action {
        case .none:
            break
        case .click(let op, let mods):
            performClick(op, mods: mods)
        case .mission, .music, .zoom, .switcher, .open, .device:
            performAction(action)   // Task 10 replaces this stub dispatch
        case .scroll:
            break   // wheel emission wired in Task 8; model introduced in Task 1
        }
    }

    public func beganHold(_ action: Action) {
        if case .device(.switchPrecisionMode) = action { cursor?.beginPrecision() }
    }

    public func endedHold(_ action: Action) {
        if case .device(.switchPrecisionMode) = action { cursor?.endPrecision() }
    }

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
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: cursorLocation(), mouseButton: CGMouseButton(rawValue: UInt32(clamping: number)) ?? .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.flags = CGFlagConversion.cgFlags(mods)
        poster.post(event)
    }

    private func performAction(_ action: Action) {
        switch action {
        case .mission(let op, let reverse):
            performMission(op, reverse: reverse)
        case .music(let op, _):
            performMusic(op)
        case .zoom(let op, let reverse):
            performZoom(op, reverse: reverse)
        case .switcher(let op):
            performSwitcher(op)
        case .open(let target):
            performOpen(target)
        case .device(let op):
            performDevice(op)
        default:
            break   // .none/.click are dispatched in perform(_:); deferred ops no-op
        }
    }

    private func performDevice(_ op: DeviceOp) {
        switch op {
        case .activateCursorSpeed:
            cursor?.activateNext(source: .buttonAction)
        case .switchPrecisionMode:
            break   // hold lifecycle, not a tap action
        case .dpiCycle, .dpiUp, .dpiDown, .dpiShift, .defaultDPI, .switchWheelMode:
            break   // DPI/wheel ops deferred (phases 2/4); UI disables
        }
    }

    /// Down + up pair with the given modifier flags (mission, zoom, app switcher).
    // SDK adaptation: the keyboard CGEvent initializer takes no flags argument;
    // the flags are assigned to each event before it is posted.
    private func keyPress(_ keyCode: UInt64, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)!
        down.flags = flags
        poster.post(down)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)!
        up.flags = flags
        poster.post(up)
    }

    private func performMission(_ op: MissionOp, reverse: Bool) {
        let ctrl: CGEventFlags = [.maskControl]
        switch op {
        case .missionControl: keyPress(KeyCodes.upArrow, flags: ctrl)
        case .appWindows: keyPress(KeyCodes.downArrow, flags: ctrl)
        case .launchpad: keyPress(KeyCodes.f4, flags: [])
        case .showDesktop: keyPress(KeyCodes.f11, flags: [])
        case .desktop(let n): keyPress(KeyCodes.digit(n), flags: ctrl)
        case .moveSpaceLeft: keyPress(reverse ? KeyCodes.rightArrow : KeyCodes.leftArrow, flags: ctrl)
        case .moveSpaceRight: keyPress(reverse ? KeyCodes.leftArrow : KeyCodes.rightArrow, flags: ctrl)
        case .spotlight: keyPress(KeyCodes.space, flags: [.maskCommand])
        case .fullscreenButton: keyPress(KeyCodes.f, flags: [.maskControl, .maskCommand])
        case .notificationCenter, .siri:
            break   // deferred (phase 4); UI disables
        }
    }

    private func performMusic(_ op: MusicOp) {
        let keyCode: Int64
        switch op {
        case .playPause: keyCode = NXMediaKey.play
        case .next: keyCode = NXMediaKey.fast
        case .previous: keyCode = NXMediaKey.rewind
        case .mute: keyCode = NXMediaKey.mute
        case .volumeUp: keyCode = NXMediaKey.soundUp
        case .volumeDown: keyCode = NXMediaKey.soundDown
        case .eject: keyCode = NXMediaKey.eject
        }
        poster.post(MediaKeySynthesizer.makeEvent(keyCode: keyCode, keyDown: true))
        poster.post(MediaKeySynthesizer.makeEvent(keyCode: keyCode, keyDown: false))
    }

    private func performZoom(_ op: ZoomOp, reverse: Bool) {
        switch op {
        case .appZoomIn, .appZoomOut:
            let zoomIn = (op == .appZoomIn) != reverse
            keyPress(zoomIn ? KeyCodes.equals : KeyCodes.minus, flags: [.maskCommand])
        case .screenZoomIn, .screenZoomOut:
            let zoomIn = (op == .screenZoomIn) != reverse
            keyPress(zoomIn ? KeyCodes.equals : KeyCodes.minus, flags: [.maskAlternate, .maskCommand])
        case .pinchIn, .pinchOut, .smartZoom:
            break   // deferred gesture emulation (phase 4); UI disables
        }
    }

    private func performSwitcher(_ op: SwitcherOp) {
        switch op {
        case .nextApp: keyPress(48, flags: [.maskCommand])
        case .previousApp: keyPress(48, flags: [.maskCommand, .maskShift])
        case .applicationWindows: keyPress(KeyCodes.downArrow, flags: [.maskControl])
        case .showSwitcher: break   // deferred custom overlay (phase 4)
        case .app(let target):
            switch target {
            case .bundleID(let id): workspace.launchApp(bundleID: id)
            case .url(let string): openURLIfValid(string)
            case .bookmark(let base64):
                guard let data = Data(base64Encoded: base64) else { return }
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: data, options: [],
                                      relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    workspace.openURL(url)
                }
            }
        }
    }

    private func performOpen(_ target: OpenTarget) {
        switch target {
        case .path(let p): workspace.openFile(path: p)
        case .url(let string): openURLIfValid(string)
        }
    }

    /// Opens a URL target, treating an unparseable string as a no-op rather than a crash.
    // SDK adaptation: macOS 14 Foundation's URL(string:) accepts garbage such as
    // "::::not-a-url" with an empty scheme, so a non-empty scheme is required before opening.
    private func openURLIfValid(_ string: String) {
        guard let url = URL(string: string), let scheme = url.scheme, !scheme.isEmpty else { return }
        workspace.openURL(url)
    }
}
