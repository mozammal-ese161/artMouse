import SwiftUI
import ArtMouseCore

@Observable
final class AppModel {
    private let store: SettingsStore
    let permissions: PermissionsController
    let devices: DeviceManager

    init(store: SettingsStore, permissions: PermissionsController, devices: DeviceManager) {
        self.store = store
        self.permissions = permissions
        self.devices = devices
        devices.refresh()
    }

    var settings: GlobalSettings { store.settings }

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
}
