import SwiftUI
import ArtMouseCore

struct ChordEditorView: View {
    let chord: Chord
    let onUpdate: (Chord) -> Void
    let onDelete: (Chord) -> Void

    private let standardButtons: [ButtonID] = [.left, .right, .middle, .fourth, .fifth]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(standardButtons, id: \.self) { button in
                    Toggle(label(button), isOn: Binding(
                        get: { chord.buttons.contains(button) },
                        set: { on in updateButtons { $0.toggle(button, isOn: on) } }))
                        .toggleStyle(.checkbox)
                }
                TextField("Timeout (s)", value: Binding(
                    get: { chord.timeout },
                    set: { onUpdate(chord(timeout: max(0.05, min(2.0, $0)))) }), format: .number)
                    .frame(width: 90)
                Spacer()
                Button(role: .destructive) { onDelete(chord) } label: { Image(systemName: "trash") }
            }
            Text("First checked button initiates.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Action:").font(.caption)
                // Chord actions fire via executor.perform, whose .macro arm is
                // a no-op — macros are button-only, so the picker omits them.
                ActionEditorView(action: chord.actions.first, allowsMacro: false) { newAction in
                    onUpdate(chord(actions: newAction.map { [$0] } ?? []))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func label(_ button: ButtonID) -> String {
        switch button {
        case .left: return "L"
        case .right: return "R"
        case .middle: return "M"
        case .fourth: return "4"
        case .fifth: return "5"
        case .extended(let n): return "+\(n + 1)"
        }
    }

    private func updateButtons(_ mutate: (inout [ButtonID]) -> Void) {
        var buttons = chord.buttons
        // buttons[0] stays the initiator unless it was toggled off: promote the next.
        mutate(&buttons)
        if buttons.isEmpty { buttons = chord.buttons }   // never empty
        onUpdate(chord(buttons: buttons))
    }

    // copy() helpers — one per mutated field, mirroring Phase 1's profileWithName pattern:
    private func chord(buttons: [ButtonID]) -> Chord { var c = chord; c.buttons = buttons; return c }
    private func chord(actions: [Action]) -> Chord { var c = chord; c.actions = actions; return c }
    private func chord(timeout: Double) -> Chord { var c = chord; c.timeout = timeout; return c }
}

private extension Array where Element == ButtonID {
    mutating func toggle(_ button: ButtonID, isOn: Bool) {
        if isOn {
            if !contains(button) { append(button) }
        } else {
            removeAll { $0 == button }
        }
    }
}
