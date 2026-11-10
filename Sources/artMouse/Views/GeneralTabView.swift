import SwiftUI

struct GeneralTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Export Settings…") { model.exportSettings() }
                Button("Import Settings…") { model.importSettings() }
            }
            if let error = model.lastImportError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}
