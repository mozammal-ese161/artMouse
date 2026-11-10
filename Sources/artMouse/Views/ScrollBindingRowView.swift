import SwiftUI
import ArtMouseCore

struct ScrollBindingRowView: View {
    let model: AppModel
    let label: String
    let axis: ScrollAxis
    let direction: ScrollDirection

    var body: some View {
        HStack(alignment: .top) {
            Text(label).frame(width: 110, alignment: .leading).font(.body.weight(.medium))
            ActionEditorView(action: currentAction) { newAction in
                model.setScrollBinding(axis: axis, direction: direction, action: newAction)
            }
            Button("Clear") { model.removeScrollBinding(axis: axis, direction: direction) }
                .disabled(model.scrollBinding(axis: axis, direction: direction) == nil)
        }
        .padding(.vertical, 4)
    }

    private var currentAction: Action? {
        model.scrollBinding(axis: axis, direction: direction)?.actions.first
    }
}
