import SwiftUI
import ArtMouseCore

struct SnapActionEditorView: View {
    let op: SnappingOp
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Text("Snap to default button").frame(width: 170, alignment: .leading)
            if case .snap(let click, let bounce) = op {
                Toggle("Click it", isOn: Binding(
                    get: { click },
                    set: { onChange(.snapping(.snap(click: $0, bounce: bounce))) }))
                    .toggleStyle(.checkbox)
                Toggle("Return to origin", isOn: Binding(
                    get: { bounce },
                    set: { onChange(.snapping(.snap(click: click, bounce: $0))) }))
                    .toggleStyle(.checkbox)
            }
        }
    }
}
