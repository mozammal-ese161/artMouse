import SwiftUI
import ArtMouseCore

struct DevicesTabView: View {
    let model: AppModel
    @State private var analyzerDevice: HIDDeviceIdentity?
    @State private var editingProfile: DeviceProfile?

    var body: some View {
        List(model.devices.devices, id: \.settingsKey) { device in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name).font(.body)
                    Spacer()
                    Toggle("Enabled", isOn: Binding(
                        get: { !model.settings.isDeviceDisabled(vendorID: device.vendorID,
                                                                productID: device.productID) },
                        set: { _ in model.toggleDeviceDisabled(device) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                Text("\(device.transport) — VID \(device.vendorID) PID \(device.productID)")
                    .font(.caption).foregroundStyle(.secondary)
                if let profile = model.deviceProfile(for: device) {
                    Text("Profile: \(profile.name) — \(profile.parts.count) part(s)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Edit Profile…") {
                        editingProfile = model.deviceProfile(for: device)
                            ?? model.addDeviceProfile(for: device)
                    }
                    Button("Analyze…") { analyzerDevice = device }
                }
                .buttonStyle(.link)
                DeviceDetailsDisclosure(device: device, model: model)
            }
        }
        .sheet(item: $analyzerDevice) { device in
            DeviceAnalyzerSheet(device: device, model: model)
        }
        .sheet(item: $editingProfile) { profile in
            DeviceProfileEditorSheet(
                initial: profile,
                onSave: { model.updateDeviceProfile($0) },
                onDelete: { model.removeDeviceProfile($0.id) })
        }
    }
}

/// On-demand IORegistry disclosure (state keeps it collapsed by default).
struct DeviceDetailsDisclosure: View {
    let device: HIDDeviceIdentity
    let model: AppModel
    @State private var expanded = false
    @State private var details: [String: String] = [:]

    var body: some View {
        DisclosureGroup("Details", isExpanded: $expanded) {
            ForEach(details.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).font(.caption)
                }
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded && details.isEmpty {
                details = model.registryDetails(for: device)
            }
        }
    }
}
