import SwiftUI

struct GeneralTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Export Settings…") { model.exportSettings() }
                Button("Import Settings…") { model.importSettings() }
            }
            Toggle("Flip trackball horizontal direction", isOn: Binding(
                get: { model.settings.trackballHorizontalFlip },
                set: { model.setTrackballFlip($0) }))
                .toggleStyle(.checkbox)
            if let error = model.lastImportError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let error = model.lastExportError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}
