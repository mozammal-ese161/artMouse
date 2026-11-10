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
}
