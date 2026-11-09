import SwiftUI
import ArtMouseCore

struct BindingRowView: View {
    let model: AppModel
    let button: ButtonID

    var body: some View {
        HStack(alignment: .top) {
            Text(label).frame(width: 90, alignment: .leading).font(.body.weight(.medium))
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
