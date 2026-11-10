import AppKit

/// The frontmost-bundle-ID source the router and both controllers consume for
/// per-app profile resolution (Phase 3 Task 5). AppWatcher is the real
/// implementation; tests substitute a bare double.
public protocol FrontmostProviding: AnyObject {
    var frontmostBundleID: String? { get }
}

public final class AppWatcher {
    private let notificationCenter: NotificationCenter
    public private(set) var frontmostBundleID: String?
    private var observer: NSObjectProtocol?

    public init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.notificationCenter = notificationCenter
    }

    public func start() {
        guard observer == nil else { return }
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let bundleID = Self.bundleID(fromActivation: notification.userInfo ?? [:])
            self?.handleActivation(bundleID)
        }
    }

    public func handleActivation(_ bundleID: String?) {
        guard let bundleID else { return }
        frontmostBundleID = bundleID
    }

    public static func bundleID(fromActivation userInfo: [AnyHashable: Any]) -> String? {
        (userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }
}

extension AppWatcher: FrontmostProviding {}
