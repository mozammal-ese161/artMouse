import SwiftUI

struct DevicesTabView: View {
    let model: AppModel
    var body: some View {
        List(model.devices.devices, id: \.settingsKey) { device in
            VStack(alignment: .leading) {
                Text(device.name).font(.body)
                Text("\(device.transport) — VID \(device.vendorID) PID \(device.productID)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
