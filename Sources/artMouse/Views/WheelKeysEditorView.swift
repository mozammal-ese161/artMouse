import SwiftUI
import ArtMouseCore

struct WheelKeysEditorView: View {
    let emulation: WheelKeyEmulation?
    let onChange: (WheelKeyEmulation?) -> Void

    var body: some View {
        Toggle("Wheel sends keys", isOn: Binding(
            get: { emulation != nil },
            set: { on -> Void in
                onChange(on ? WheelKeyEmulation(keyCode: 40) : nil)   // 40 = "k" placeholder; field below edits it
            }))
            .toggleStyle(.checkbox)
        if let emulation {
            TextField("Key code", value: Binding(
                get: { Double(emulation.keyCode) },
                set: { onChange(WheelKeyEmulation(keyCode: UInt64($0.clamped(0...maxKeyCodeDouble)),
                                                  mods: emulation.mods,
                                                  repeatWhileRolling: emulation.repeatWhileRolling)) }),
                format: .number)
                .frame(width: 70)
            Toggle("Repeat", isOn: Binding(
                get: { emulation.repeatWhileRolling },
                set: { onChange(WheelKeyEmulation(keyCode: emulation.keyCode, mods: emulation.mods,
                                                  repeatWhileRolling: $0)) }))
                .toggleStyle(.checkbox)
            Text("Each notch presses and releases the key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
