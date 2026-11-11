import SwiftUI
import ArtMouseCore

@Observable
final class AppModel {
    private let store: SettingsStore
    let permissions: PermissionsController
    let devices: DeviceManager
    /// Owned by AppDelegate and EngineBootstrap (which starts it); the model
    /// only reads the frontmost bundle ID for "Add Frontmost App".
    private weak var watcher: AppWatcher?
    /// Shared with the engine's HID pump (Device Analyzer sheet, Phase 4):
    /// created ONCE in AppDelegate so UI and engine observe the same stores.
    /// Optional with a nil default because the model is also constructed in
    /// tests and previews without the device pipeline.
    let deviceLog: HIDEventLog?
    let hidAnalyzer: HIDAnalyzerStore?

    init(store: SettingsStore, permissions: PermissionsController, devices: DeviceManager,
         watcher: AppWatcher? = nil, hidLog: HIDEventLog? = nil,
         hidAnalyzer: HIDAnalyzerStore? = nil) {
        self.store = store
        self.permissions = permissions
        self.devices = devices
        devices.refresh()
        self.watcher = watcher
        self.deviceLog = hidLog
        self.hidAnalyzer = hidAnalyzer
    }

    var settings: GlobalSettings { store.settings }

    var frontmostBundleID: String? { watcher?.frontmostBundleID }

    /// Load warnings from the store; surfaced in the Settings UI so a
    /// malformed settings.json is visible to the user (spec §7, Review Focus 2).
    var lastLoadWarnings: [String] { store.lastLoadWarnings }

    func binding(for button: ButtonID) -> ButtonBinding? {
        store.settings.buttonBindings.first { $0.button == button }
    }

    func setBinding(_ button: ButtonID, action: Action?) {
        var settings = store.settings
        if let index = settings.buttonBindings.firstIndex(where: { $0.button == button }) {
            if let action {
                settings.buttonBindings[index].actions = [action]
            } else {
                // Unbind removes the whole binding: an empty binding left
                // behind would match the router forever and swallow both
                // press and release of a button the UI reports as Unbound.
                settings.buttonBindings.remove(at: index)
            }
        } else if let action {
            settings.buttonBindings.append(ButtonBinding(button: button, actions: [action]))
        }
        store.settings = settings
        save()
    }

    /// Creates an empty binding for an extended button so its row appears in
    /// the Buttons tab (idempotent). The empty-actions shape is behaviorally
    /// inert in the engine (bindings with no actions never match), so adding
    /// a row cannot strand the button — the Phase 1 zombie-binding fix holds.
    func ensureBinding(for button: ButtonID) {
        guard binding(for: button) == nil else { return }
        var settings = store.settings
        settings.buttonBindings.append(ButtonBinding(button: button, actions: []))
        store.settings = settings
        save()
    }

    /// Device-profile part name for an extended button ("Thumb 1"), shown as
    /// a caption in the Buttons tab; nil when no profile names this number.
    func partName(for button: ButtonID) -> String? {
        guard case .extended(let number) = button else { return nil }
        for profile in store.settings.deviceProfiles {
            if let part = profile.parts.first(where: { $0.routesAsButton == number }) {
                return part.name
            }
        }
        return nil
    }

    /// Unlike buttons, an existing scroll binding set to nil keeps the
    /// binding with empty actions: the router filters empty scroll bindings,
    /// and the UI keeps the row visible so the user can re-bind or Clear it.
    func setScrollBinding(axis: ScrollAxis, direction: ScrollDirection, action: Action?) {
        var settings = store.settings
        if let index = settings.scrollBindings.firstIndex(where: { $0.axis == axis && $0.direction == direction }) {
            settings.scrollBindings[index].actions = action.map { [$0] } ?? []
        } else if let action {
            settings.scrollBindings.append(ScrollBinding(axis: axis, direction: direction, actions: [action]))
        }
        store.settings = settings
        save()
    }

    func scrollBinding(axis: ScrollAxis, direction: ScrollDirection) -> ScrollBinding? {
        store.settings.scrollBindings.first { $0.axis == axis && $0.direction == direction }
    }

    /// Clear removes the binding entirely, dropping the "bound but none"
    /// marker row so the wheel direction behaves like an unbound default.
    func removeScrollBinding(axis: ScrollAxis, direction: ScrollDirection) {
        var settings = store.settings
        settings.scrollBindings.removeAll { $0.axis == axis && $0.direction == direction }
        store.settings = settings
        save()
    }

    func save() {
        try? store.save()
    }

    func addProfile() {
        var settings = store.settings
        settings.cursorSpeedProfiles.append(
            CursorSpeedProfile(name: "Profile \(settings.cursorSpeedProfiles.count + 1)",
                               sensitivity: 1600, acceleration: 1.0))
        store.settings = settings
        save()
    }

    func removeProfile(_ id: UUID) {
        var settings = store.settings
        guard settings.cursorSpeedProfiles.count > 1 else { return }   // never zero profiles
        settings.cursorSpeedProfiles.removeAll { $0.id == id }
        if settings.activeCursorSpeedProfileID == id { settings.activeCursorSpeedProfileID = nil }
        if settings.precisionProfileID == id { settings.precisionProfileID = nil }
        store.settings = settings
        save()
    }

    func updateProfile(_ profile: CursorSpeedProfile) {
        var settings = store.settings
        if let index = settings.cursorSpeedProfiles.firstIndex(where: { $0.id == profile.id }) {
            settings.cursorSpeedProfiles[index] = profile
        }
        store.settings = settings
        save()
    }

    func setActiveProfile(_ id: UUID) {
        store.settings.activeCursorSpeedProfileID = id
        save()
    }

    func setPrecisionProfile(_ id: UUID?) {
        store.settings.precisionProfileID = id
        save()
    }

    func addWheelProfile() {
        var settings = store.settings
        settings.wheelModeProfiles.append(
            WheelModeProfile(name: "Profile \(settings.wheelModeProfiles.count + 1)"))
        store.settings = settings
        save()
    }

    func removeWheelProfile(_ id: UUID) {
        var settings = store.settings
        guard settings.wheelModeProfiles.count > 1 else { return }   // never zero profiles
        settings.wheelModeProfiles.removeAll { $0.id == id }
        if settings.activeWheelModeProfileID == id { settings.activeWheelModeProfileID = nil }
        store.settings = settings
        save()
    }

    func updateWheelProfile(_ profile: WheelModeProfile) {
        var settings = store.settings
        if let index = settings.wheelModeProfiles.firstIndex(where: { $0.id == profile.id }) {
            settings.wheelModeProfiles[index] = profile
        }
        store.settings = settings
        save()
    }

    func setActiveWheelProfile(_ id: UUID) {
        store.settings.activeWheelModeProfileID = id
        save()
    }

    /// Global trackball convention (spec A.4): thumb-operated trackballs
    /// report horizontal deltas mirrored; this flips the sign at the engine.
    func setTrackballFlip(_ flipped: Bool) {
        store.settings.trackballHorizontalFlip = flipped
        save()
    }

    func addChord() {
        var settings = store.settings
        settings.chords.append(Chord(buttons: [.middle, .fourth], actions: []))
        store.settings = settings
        save()
    }

    func updateChord(_ chord: Chord) {
        var settings = store.settings
        if let index = settings.chords.firstIndex(where: { $0.id == chord.id }) {
            settings.chords[index] = chord
        }
        store.settings = settings
        save()
    }

    func removeChord(_ id: UUID) {
        var settings = store.settings
        settings.chords.removeAll { $0.id == id }
        store.settings = settings
        save()
    }

    // Per-application profiles (Phase 3 Task 8). Matching stays bundle-ID
    // exact, so an empty ID would shadow nothing and a duplicate would create
    // an ambiguous row that can never both apply — both are refused.

    func addAppProfile(bundleID: String, name: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var settings = store.settings
        guard !settings.appProfiles.contains(where: { $0.bundleID == trimmed }) else { return }
        settings.appProfiles.append(AppProfile(bundleID: trimmed, name: name))
        store.settings = settings
        save()
    }

    func addFrontmostAppProfile() {
        guard let bundleID = frontmostBundleID else { return }
        addAppProfile(bundleID: bundleID, name: bundleID)
    }

    func removeAppProfile(_ id: UUID) {
        var settings = store.settings
        settings.appProfiles.removeAll { $0.id == id }
        store.settings = settings
        save()
    }

    func updateAppProfile(_ profile: AppProfile) {
        // Same guards as add: trimmed, non-empty, and no duplicate bundle ID
        // against OTHER profiles (a duplicate would create an inert loser row
        // in first-match resolution).
        var trimmed = profile
        trimmed.bundleID = profile.bundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.bundleID.isEmpty else { return }
        var settings = store.settings
        if let index = settings.appProfiles.firstIndex(where: { $0.id == trimmed.id }) {
            let duplicates = settings.appProfiles.contains {
                $0.bundleID == trimmed.bundleID && $0.id != trimmed.id
            }
            guard !duplicates else { return }
            settings.appProfiles[index] = trimmed
        }
        store.settings = settings
        save()
    }

    // MARK: Devices (Phase 4)

    /// Stores a profile authored in the editor sheet. The sheet builds its
    /// own draft (the stored profile, or a fresh skeleton for the device),
    /// so persistence happens only on Save — opening the editor no longer
    /// stores a skeleton that Cancel could not undo.
    func addDeviceProfile(_ profile: DeviceProfile) {
        var settings = store.settings
        settings.deviceProfiles.append(profile)
        store.settings = settings
        save()
    }

    func updateDeviceProfile(_ profile: DeviceProfile) {
        var settings = store.settings
        if let index = settings.deviceProfiles.firstIndex(where: { $0.id == profile.id }) {
            settings.deviceProfiles[index] = profile
        }
        store.settings = settings
        save()
    }

    func removeDeviceProfile(_ id: UUID) {
        var settings = store.settings
        settings.deviceProfiles.removeAll { $0.id == id }
        store.settings = settings
        save()
    }

    /// Toggle helper over `disabledDeviceKeys` (settings-key based, so it
    /// works for devices without a profile too).
    func toggleDeviceDisabled(_ device: HIDDeviceIdentity) {
        var settings = store.settings
        let key = device.settingsKey
        if let index = settings.disabledDeviceKeys.firstIndex(of: key) {
            settings.disabledDeviceKeys.remove(at: index)
        } else {
            settings.disabledDeviceKeys.append(key)
        }
        store.settings = settings
        save()
    }

    func deviceProfile(for device: HIDDeviceIdentity) -> DeviceProfile? {
        store.settings.deviceProfile(matchingVendor: device.vendorID, productID: device.productID)
    }

    func setDeviceLogPersist(_ on: Bool) {
        deviceLog?.setPersistToFile(on)
    }

    /// IORegistry details for the disclosure row (glue call, on demand —
    /// never on the hot path).
    func registryDetails(for device: HIDDeviceIdentity) -> [String: String] {
        IOKitDeviceEnumerator().registryDetails(vendorID: device.vendorID,
                                                productID: device.productID)
    }

    // Settings import/export (Phase 3 Task 9). Import is all-or-nothing: the
    // store's strict importData throws on malformed data before any assignment,
    // so the user's settings survive a bad file untouched.

    private(set) var lastImportError: String?
    /// Surfaced next to the import error in the General tab: a failed export
    /// (unwritable location, disk full) must not look identical to success.
    private(set) var lastExportError: String?

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "artMouse-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportData()
            // Atomic: a half-written backup file must never be created.
            try data.write(to: url, options: .atomic)
            lastExportError = nil
        } catch {
            lastExportError = "Export failed: \(error.localizedDescription)"
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try store.importData(data)
            save()
            lastImportError = nil
        } catch {
            lastImportError = "Import failed: \(error.localizedDescription)"
        }
    }
}
