import SwiftUI
import ArtMouseCore

struct ZoomActionEditorView: View {
    let op: ZoomOp
    let reverse: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { op },
                set: { onChange(.zoom($0, reverse: reverse)) })) {
                Text("Screen Zoom In").tag(ZoomOp.screenZoomIn)
                Text("Screen Zoom Out").tag(ZoomOp.screenZoomOut)
                Text("App Zoom In").tag(ZoomOp.appZoomIn)
                Text("App Zoom Out").tag(ZoomOp.appZoomOut)
                Text("Pinch Zoom In").tag(ZoomOp.pinchIn).disabled(true)    // phase 4
                Text("Pinch Zoom Out").tag(ZoomOp.pinchOut).disabled(true)  // phase 4
                Text("Smart Zoom").tag(ZoomOp.smartZoom).disabled(true)     // phase 4
            }
            .labelsHidden()
            .frame(width: 160)

            Toggle("Reverse", isOn: Binding(
                get: { reverse },
                set: { onChange(.zoom(op, reverse: $0)) }))
                .toggleStyle(.checkbox)
        }
    }
}
