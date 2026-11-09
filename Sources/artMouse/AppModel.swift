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

    func binding(for button: ButtonID) -> ButtonBinding? {
        store.settings.buttonBindings.first { $0.button == button }
    }

    func setBinding(_ button: ButtonID, action: Action?) {
        var settings = store.settings
        if let index = settings.buttonBindings.firstIndex(where: { $0.button == button }) {
            settings.buttonBindings[index].actions = action.map { [$0] } ?? []
        } else if let action {
            settings.buttonBindings.append(ButtonBinding(button: button, actions: [action]))
        }
        store.settings = settings
        save()
    }

    func save() {
        try? store.save()
    }
}
