/// Button-press actions (phase-1 subset of spec §5). Cases are extended in
/// later phases (scroll, macro, snapping); decoding of phase-1 JSON is
/// unaffected because Codable synthesis is per-case.
public enum Action: Hashable, Codable {
    case none
    case click(ClickOp, ModKeys)
    case mission(MissionOp, reverse: Bool)
    case music(MusicOp, fineTune: Bool)
    case zoom(ZoomOp, reverse: Bool)
    case switcher(SwitcherOp)
    case open(OpenTarget)
    case device(DeviceOp)
    case scroll(ScrollSpec)

    /// Hold actions activate on button-down and revert on button-up.
    public var isHoldAction: Bool {
        if case .device(.switchPrecisionMode) = self { return true }
        return false
    }

    /// Click-lock bindings match regardless of the modifier set.
    public var isClickLock: Bool {
        if case .click(.clickLock, _) = self { return true }
        return false
    }
}

public enum ClickOp: String, Codable, CaseIterable {
    case left, middle, right, doubleLeft, fourth, fifth, clickLock
}

public enum MissionOp: Hashable, Codable {
    case missionControl, appWindows, launchpad, showDesktop
    case notificationCenter   // deferred: executor reports unavailable (phase 4)
    case spotlight, siri      // siri deferred
    case fullscreenButton
    case desktop(Int)         // 1...9 → ctrl+<n>
    case moveSpaceLeft, moveSpaceRight
}

public enum MusicOp: String, Codable, CaseIterable {
    case playPause, next, previous, mute, volumeUp, volumeDown, eject
}

public enum ZoomOp: String, Codable, CaseIterable {
    case screenZoomIn, screenZoomOut
    case appZoomIn, appZoomOut
    case pinchIn, pinchOut, smartZoom   // deferred: gesture emulation (phase 4)
}

public enum AppTarget: Hashable, Codable {
    case bundleID(String), url(String), bookmark(String)
}

public enum SwitcherOp: Hashable, Codable {
    case app(AppTarget)
    case nextApp, previousApp
    case applicationWindows
    case showSwitcher   // deferred: custom overlay (phase 4)
}

public enum OpenTarget: Hashable, Codable {
    case path(String), url(String)
}

public enum DeviceOp: Hashable, Codable {
    case activateCursorSpeed(String?)   // nil = next profile in order
    case switchPrecisionMode            // hold: precision profile while held
    // DPI + wheel-mode ops declared for parity; implemented in phases 2/4.
    case dpiCycle, dpiUp, dpiDown, dpiShift, defaultDPI, switchWheelMode
}
