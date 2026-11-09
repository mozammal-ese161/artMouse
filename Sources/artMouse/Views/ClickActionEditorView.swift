import SwiftUI
import ArtMouseCore

struct ClickActionEditorView: View {
    let op: ClickOp
    let mods: ModKeys
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            opPicker
            modifierCheck("⌘", .command)
            modifierCheck("⌃", .control)
            modifierCheck("⌥", .option)
            modifierCheck("⇧", .shift)
        }
    }

    private var opPicker: some View {
        Picker("", selection: Binding(
            get: { op },
            set: { onChange(.click($0, mods)) })) {
            ForEach(ClickOp.allCases, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .labelsHidden()
    }

    private func modifierCheck(_ title: String, _ key: ModKeys) -> some View {
        Toggle(title, isOn: Binding(
            get: { mods.contains(key) },
            set: { on in
                var next = mods
                if on { next.insert(key) } else { next.remove(key) }
                onChange(.click(op, next))
            }))
        .toggleStyle(.checkbox)
    }

    private func label(_ op: ClickOp) -> String {
        switch op {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        case .doubleLeft: return "Double Click"
        case .fourth: return "4th Click"
        case .fifth: return "5th Click"
        case .clickLock: return "Click Lock"
        }
    }
}
