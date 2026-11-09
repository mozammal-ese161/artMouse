import SwiftUI
import ArtMouseCore

struct ProfileEditorView: View {
    let profile: CursorSpeedProfile
    let isActive: Bool
    let isPrecision: Bool
    let onUpdate: (CursorSpeedProfile) -> Void
    let onDelete: (CursorSpeedProfile) -> Void
    let onActivate: (CursorSpeedProfile) -> Void
    let onTogglePrecision: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: Binding(
                get: { profile.name },
                set: { onUpdate(profileWithName($0)) }))
                .frame(width: 110)

            LabeledContent("Sensitivity") {
                TextField("", value: Binding(
                    get: { profile.sensitivity },
                    set: { onUpdate(profileWithSensitivity($0)) }), format: .number)
                    .frame(width: 70)
            }
            .frame(width: 190)

            LabeledContent("Acceleration") {
                TextField("", value: Binding(
                    get: { profile.acceleration },
                    set: { onUpdate(profileWithAcceleration($0)) }), format: .number)
                    .frame(width: 70)
            }
            .frame(width: 180)

            Button(isActive ? "Active" : "Use") { onActivate(profile) }
                .disabled(isActive)

            Toggle("Precision", isOn: Binding(get: { isPrecision }, set: { _ in onTogglePrecision() }))
                .toggleStyle(.checkbox)

            Spacer()

            Button(role: .destructive) { onDelete(profile) } label: { Image(systemName: "trash") }
                .disabled(isActive)
        }
    }

    private func profileWithName(_ name: String) -> CursorSpeedProfile {
        var copy = profile; copy.name = name; return copy
    }
    private func profileWithSensitivity(_ value: Double) -> CursorSpeedProfile {
        var copy = profile; copy.sensitivity = value; return copy
    }
    private func profileWithAcceleration(_ value: Double) -> CursorSpeedProfile {
        var copy = profile; copy.acceleration = value; return copy
    }
}
