import SwiftUI
import ArtMouseCore

struct AppsTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Per-application profiles").font(.headline)
                Spacer()
                Button("Add Frontmost App") { model.addFrontmostAppProfile() }
            }
            List(model.settings.appProfiles) { profile in
                AppProfileEditorView(
                    profile: profile,
                    cursorProfiles: model.settings.cursorSpeedProfiles,
                    wheelProfiles: model.settings.wheelModeProfiles,
                    onUpdate: { model.updateAppProfile($0) },
                    onDelete: { model.removeAppProfile($0.id) })
            }
            Text("While the matching app is frontmost, its overrides replace the global cursor speed and wheel mode. Add the app you are using right now with “Add Frontmost App”. Button-binding overrides are edited in settings.json (advanced).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
