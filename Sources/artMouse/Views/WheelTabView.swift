import SwiftUI
import ArtMouseCore

struct WheelTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wheel mode profiles").font(.headline)
                Spacer()
                Button("Add Profile") { model.addWheelProfile() }
            }
            List(model.settings.wheelModeProfiles) { profile in
                WheelProfileEditorView(
                    profile: profile,
                    isActive: profile.id == model.settings.activeWheelProfile?.id,
                    onUpdate: { model.updateWheelProfile($0) },
                    onDelete: { model.removeWheelProfile($0.id) },
                    onActivate: { model.setActiveWheelProfile($0.id) })
            }
            Text("Sens multiplies wheel distance; Acceleration adds distance on fast rolls. Constant mode scrolls a fixed amount per notch; Auto keeps scrolling after a roll and stops after N notches of silence. Smooth spreads each notch into small steps. Keys sends a keystroke instead of scrolling.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
