import SwiftUI
import ArtMouseCore

struct DeviceActionEditorView: View {
    let op: DeviceOp
    let onChange: (Action?) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { op },
            set: { onChange(.device($0)) })) {
            Text("Activate Next Cursor Speed").tag(DeviceOp.activateCursorSpeed(nil))
            Text("Switch Precision Mode").tag(DeviceOp.switchPrecisionMode)
            Text("DPI Cycle").tag(DeviceOp.dpiCycle)
            Text("DPI Up").tag(DeviceOp.dpiUp)
            Text("DPI Down").tag(DeviceOp.dpiDown)
            Text("DPI Shift").tag(DeviceOp.dpiShift)
            Text("Default DPI").tag(DeviceOp.defaultDPI)
            Text("Switch Wheel Mode").tag(DeviceOp.switchWheelMode)
        }
        .labelsHidden()
        .frame(width: 230)
    }
}
