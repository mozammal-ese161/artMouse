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
            // Scroll bindings fire per tick via executor.perform; a macro
            // there would replay its whole sequence on every wheel tick —
            // macros are button-only, so the picker omits them.
            ActionEditorView(action: currentAction, allowsMacro: false) { newAction in
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
