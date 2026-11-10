import SwiftUI
import ArtMouseCore

struct AppProfileEditorView: View {
    let profile: AppProfile
    let cursorProfiles: [CursorSpeedProfile]
    let wheelProfiles: [WheelModeProfile]
    let onUpdate: (AppProfile) -> Void
    let onDelete: (AppProfile) -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Name", text: Binding(
                get: { profile.name },
                set: { onUpdate(copy(name: $0)) }))
                .frame(width: 110)
            TextField("Bundle ID", text: Binding(
                get: { profile.bundleID },
                set: { onUpdate(copy(bundleID: $0)) }))
                .frame(width: 180)
            Picker("Cursor", selection: Binding(
                get: { profile.cursorSpeedProfileID },
                set: { onUpdate(copy(cursorSpeedProfileID: $0)) })) {
                Text("Global").tag(UUID?.none)
                ForEach(cursorProfiles) { profile in
                    Text(profile.name).tag(UUID?.some(profile.id))
                }
            }
            .frame(width: 150)
            Picker("Wheel", selection: Binding(
                get: { profile.wheelModeProfileID },
                set: { onUpdate(copy(wheelModeProfileID: $0)) })) {
                Text("Global").tag(UUID?.none)
                ForEach(wheelProfiles) { profile in
                    Text(profile.name).tag(UUID?.some(profile.id))
                }
            }
            .frame(width: 150)
            Spacer()
            Button(role: .destructive) { onDelete(profile) } label: { Image(systemName: "trash") }
        }
    }

    private func copy(name: String) -> AppProfile { var c = profile; c.name = name; return c }
    private func copy(bundleID: String) -> AppProfile { var c = profile; c.bundleID = bundleID; return c }
    private func copy(cursorSpeedProfileID: UUID?) -> AppProfile { var c = profile; c.cursorSpeedProfileID = cursorSpeedProfileID; return c }
    private func copy(wheelModeProfileID: UUID?) -> AppProfile { var c = profile; c.wheelModeProfileID = wheelModeProfileID; return c }
}
