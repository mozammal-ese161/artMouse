import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

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

        startEngine()
    }

    /// Engine bootstrap; wired in Task 15.
    func startEngine() {}

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
