import SwiftUI
import ArtMouseCore

struct BindingRowView: View {
    let model: AppModel
    let button: ButtonID

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.body.weight(.medium))
                // Device-profile part name ("Thumb 1") for extended buttons;
                // absent for standard buttons and unnamed numbers, keeping
                // those rows exactly as before.
                if let partName = model.partName(for: button) {
                    Text(partName).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 90, alignment: .leading)
            ActionEditorView(action: currentAction) { newAction in
                model.setBinding(button, action: newAction)
            }
        }
        .padding(.vertical, 4)
    }

    private var currentAction: Action? {
        model.binding(for: button)?.actions.first
    }

    private var label: String {
        switch button {
        case .left: return "Left"
        case .right: return "Right"
        case .middle: return "Middle"
        case .fourth: return "4th"
        case .fifth: return "5th"
        case .extended(let n): return "Button \(n + 1)"
        }
    }
}
