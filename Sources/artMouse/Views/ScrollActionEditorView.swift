import SwiftUI
import ArtMouseCore

struct ScrollActionEditorView: View {
    let spec: ScrollSpec
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { spec.direction },
                set: { onChange(.scroll(ScrollSpec(direction: $0, mods: spec.mods,
                                                   lines: spec.lines, intervalMS: spec.intervalMS,
                                                   continuous: spec.continuous))) })) {
                ForEach(ScrollDirection.allCases, id: \.self) { d in
                    Text(label(d)).tag(d)
                }
            }
            .labelsHidden()
            .frame(width: 110)
            LabeledContent("Lines") {
                TextField("", value: Binding(
                    get: { spec.lines },
                    set: { onChange(.scroll(ScrollSpec(direction: spec.direction, mods: spec.mods,
                                                       lines: $0, intervalMS: spec.intervalMS,
                                                       continuous: spec.continuous))) }), format: .number)
                    .frame(width: 60)
            }
            .frame(width: 110)
            Text("Hold-to-repeat arrives in Phase 3")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ d: ScrollDirection) -> String {
        switch d {
        case .up: return "Scroll Up"
        case .down: return "Scroll Down"
        case .left: return "Scroll Left"
        case .right: return "Scroll Right"
        }
    }
}
