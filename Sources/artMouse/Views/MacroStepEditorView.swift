import SwiftUI
import ArtMouseCore

struct MacroStepEditorView: View {
    let step: MacroStep
    let onChange: (MacroStep) -> Void

    var body: some View {
        switch step {
        case .enterKey(let keyCode, let mods):
            HStack {
                Text("Key").frame(width: 70, alignment: .leading)
                LabeledContent("Code") {
                    TextField("", value: Binding(
                        get: { Double(keyCode) },
                        set: { onChange(.enterKey(keyCode: UInt64(max(0, $0)), mods: mods)) }),
                        format: .number)
                        .frame(width: 60)
                }
                .frame(width: 110)
                modChecks("⌘⌃⌥⇧", current: mods) { onChange(.enterKey(keyCode: keyCode, mods: $0)) }
            }
        case .click(let op, let mods):
            HStack {
                Text("Click").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { op },
                    set: { onChange(.click(op: $0, mods: mods)) })) {
                    Text("Left").tag(ClickOp.left)
                    Text("Right").tag(ClickOp.right)
                    Text("Middle").tag(ClickOp.middle)
                }
                .labelsHidden()
                .frame(width: 90)
                modChecks("⌘⌃⌥⇧", current: mods) { onChange(.click(op: op, mods: $0)) }
            }
        case .wait(let ms):
            HStack {
                Text("Wait").frame(width: 70, alignment: .leading)
                LabeledContent("ms") {
                    TextField("", value: Binding(
                        get: { Double(ms) },
                        set: { onChange(.wait(milliseconds: Int(max(1, $0))) ) }), format: .number)
                        .frame(width: 60)
                }
                .frame(width: 110)
            }
        }
    }

    private let modRows: [(String, ModKeys)] = [("⌘", .command), ("⌃", .control), ("⌥", .option), ("⇧", .shift)]

    private func modChecks(_ title: String, current: ModKeys,
                           onChange: @escaping (ModKeys) -> Void) -> some View {
        HStack {
            ForEach(modRows, id: \.1) { item in
                Toggle(item.0, isOn: Binding(
                    get: { current.contains(item.1) },
                    set: { on in
                        var next = current
                        if on { next.insert(item.1) } else { next.remove(item.1) }
                        onChange(next)
                    }))
                    .toggleStyle(.checkbox)
            }
        }
    }
}
