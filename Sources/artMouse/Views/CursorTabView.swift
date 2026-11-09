import SwiftUI
import ArtMouseCore

struct CursorTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Speed profiles").font(.headline)
                Spacer()
                Button("Add Profile") { model.addProfile() }
            }
            List(model.settings.cursorSpeedProfiles) { profile in
                ProfileEditorView(
                    profile: profile,
                    isActive: profile.id == effectiveActiveID,
                    isPrecision: profile.id == model.settings.precisionProfileID,
                    onUpdate: { model.updateProfile($0) },
                    onDelete: { model.removeProfile($0.id) },
                    onActivate: { model.setActiveProfile($0.id) },
                    onTogglePrecision: { model.setPrecisionProfile(profile.id == model.settings.precisionProfileID ? nil : profile.id) })
            }
            Text("Sensitivity scales all cursor movement (1600 ≈ system default). Acceleration adds extra distance on fast movements; 0 disables it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var effectiveActiveID: UUID? {
        model.settings.activeProfile?.id
    }
}
