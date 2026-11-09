import AppKit
import ArtMouseCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissions: PermissionsController?
    private var bootstrap: EngineBootstrap?
    private var store: SettingsStore?           // shared with AppModel in Task 16
    private var devices: DeviceManager?

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
        if BootstrapDecision.shouldRunEngine(arguments: CommandLine.arguments,
                                             flagsAtLaunch: BootstrapDecision.currentFlags()) {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let directory = appSupport.appendingPathComponent("artMouse", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = SettingsStore(directory: directory)
            let devices = DeviceManager(enumerator: IOKitDeviceEnumerator())
            self.store = store
            self.devices = devices
            let bootstrap = EngineBootstrap(devices: devices, permissions: permissions)
            bootstrap.start(store: store)
            self.bootstrap = bootstrap
        }
    }

    @objc func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Settings window arrives in Task 16; placeholder opens an empty window.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "artMouse Settings"
        window.makeKeyAndOrderFront(nil)
    }

    @objc func quit() { NSApp.terminate(nil) }
}
