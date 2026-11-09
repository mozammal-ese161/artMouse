import AppKit
import ApplicationServices

enum PermissionState: Equatable {
    case granted, denied
}

/// Main-thread confined: observed directly by the Settings UI, so the
/// main-thread discipline the engine already follows is compiler-enforced.
@MainActor
final class PermissionsController: ObservableObject {
    @Published var accessibility: PermissionState = .denied
    @Published var inputMonitoring: PermissionState = .denied

    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        // Input Monitoring cannot be queried directly; the tap creation
        // result reported through reportTapCreation drives `inputMonitoring`.
    }

    func reportTapCreation(_ succeeded: Bool) {
        inputMonitoring = succeeded ? .granted : .denied
    }

    func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func deepLinkToInputMonitoring() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_InputMonitoring") {
            NSWorkspace.shared.open(url)
        }
    }
}
