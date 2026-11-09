import SwiftUI
import ArtMouseCore

struct DeviceActionEditorView: View {
    @State var op: DeviceOp
    let onChange: (Action?) -> Void

    var body: some View {
        Picker("", selection: Binding(get: { op }, set: { op = $0; onChange(.device($0)) })) {
            Text("Activate Next Cursor Speed").tag(DeviceOp.activateCursorSpeed(nil))
            Text("Switch Precision Mode").tag(DeviceOp.switchPrecisionMode)
            Text("DPI Cycle").tag(DeviceOp.dpiCycle).disabled(true)        // phase 4
            Text("DPI Up").tag(DeviceOp.dpiUp).disabled(true)              // phase 4
            Text("DPI Down").tag(DeviceOp.dpiDown).disabled(true)          // phase 4
            Text("DPI Shift").tag(DeviceOp.dpiShift).disabled(true)        // phase 4
            Text("Default DPI").tag(DeviceOp.defaultDPI).disabled(true)    // phase 4
            Text("Switch Wheel Mode").tag(DeviceOp.switchWheelMode).disabled(true)  // phase 2
        }
        .labelsHidden()
        .frame(width: 230)
    }
}
