import SwiftUI
import ArtMouseCore

struct MacroStepsEditorView: View {
    let steps: [MacroStep]
    let onChange: ([MacroStep]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Offset identity is deliberate: steps are plain values without stable
            // IDs, and duplicate steps would collide under \.self. The transient
            // focus quirk on remove is the accepted trade (the editor is
            // derive-from-props — no @State to key identity from).
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack {
                    Text("\(index + 1).").frame(width: 24, alignment: .trailing)
                        .font(.caption).foregroundStyle(.secondary)
                    MacroStepEditorView(step: step) { newStep in
                        var next = steps
                        next[index] = newStep
                        onChange(next)
                    }
                    Spacer()
                    moveButtons(index: index)
                    Button(role: .destructive) { remove(at: index) } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            Menu("Add step…") {
                Button("Key") { onChange(steps + [.enterKey(keyCode: 40, mods: [])]) }
                Button("Click") { onChange(steps + [.click(op: .left, mods: [])]) }
                Button("Wait 250ms") { onChange(steps + [.wait(milliseconds: 250)]) }
            }
        }
    }

    private func moveButtons(index: Int) -> some View {
        HStack(spacing: 2) {
            Button { move(index, -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
            Button { move(index, 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index == steps.count - 1)
        }
        .buttonStyle(.borderless)
    }

    private func move(_ index: Int, _ delta: Int) {
        var next = steps
        let target = index + delta
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        next.swapAt(index, target)
        onChange(next)
    }

    private func remove(at index: Int) {
        var next = steps
        next.remove(at: index)
        onChange(next)
    }
}
