import AppKit
import SwiftUI
import ArtMouseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissions: PermissionsController?
    private var bootstrap: EngineBootstrap?
    private var store: SettingsStore?
    private var devices: DeviceManager?
    private var appWatcher: AppWatcher?
    private var appModel: AppModel?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit artMouse", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🖱"   // placeholder glyph; replaced by template icon later
        item.menu = menu
        statusItem = item

        let permissions = PermissionsController()
        self.permissions = permissions

        // Store and devices exist in safe mode too, so the Settings UI (Task 16)
        // shares the same instances on both paths. The bootstrap block below
        // gates only the engine itself.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("artMouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SettingsStore(directory: directory)
        let devices = DeviceManager(enumerator: IOKitDeviceEnumerator())
        // One AppWatcher shared by the engine stack AND the Settings UI (Task 8):
        // the router and controllers must read the same activation state the
        // Apps tab's "Add Frontmost App" reports. Retained here so the weak
        // reference in AppModel stays alive in safe mode too; the bootstrap
        // starts it (engine path only — activation tracking is an engine
        // concern, and AppModel's frontmostBundleID stays nil without it).
        let appWatcher = AppWatcher()
        self.appWatcher = appWatcher
        appModel = AppModel(store: store, permissions: permissions, devices: devices,
                            watcher: appWatcher)

        if BootstrapDecision.shouldRunEngine(arguments: CommandLine.arguments,
                                             flagsAtLaunch: BootstrapDecision.currentFlags()) {
            let bootstrap = EngineBootstrap(devices: devices, permissions: permissions,
                                            appWatcher: appWatcher)
            bootstrap.start(store: store)
            self.bootstrap = bootstrap
        }
    }

    @objc func openSettings() {
        guard let appModel else { return }
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "artMouse Settings"
            window.contentView = NSHostingView(rootView: SettingsWindow(model: appModel, safetyBootstrap: bootstrap))
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quit() { NSApp.terminate(nil) }
}
