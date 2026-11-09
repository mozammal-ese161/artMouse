import CoreGraphics

public enum BootstrapDecision {
    /// Engine runs unless --safe-mode is passed or ⌥⌘ held at launch.
    public static func shouldRunEngine(arguments: [String], flagsAtLaunch: ModKeys) -> Bool {
        if arguments.contains("--safe-mode") { return false }
        if flagsAtLaunch.contains(.command) && flagsAtLaunch.contains(.option) { return false }
        return true
    }

    /// Modifier state at process start (no posted events exist yet).
    public static func currentFlags() -> ModKeys {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var result: ModKeys = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }
}
