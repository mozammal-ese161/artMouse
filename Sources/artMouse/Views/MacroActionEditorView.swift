import SwiftUI
import ArtMouseCore

struct MacroActionEditorView: View {
    let steps: [MacroStep]
    let repeatMode: RepeatMode
    let repeatIntervalMS: Int
    let modifierProxy: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: Binding(
                    get: { repeatMode },
                    set: { emit(repeatMode: $0) })) {
                    Text("Run once").tag(RepeatMode.none)
                    Text("Repeat while held").tag(RepeatMode.hold)
                }
                .labelsHidden()
                .frame(width: 160)
                if repeatMode == .hold {
                    LabeledContent("Interval (ms)") {
                        TextField("", value: Binding(
                            get: { repeatIntervalMS },
                            set: { emit(repeatIntervalMS: Int($0)) }), format: .number)
                            .frame(width: 60)
                    }
                    .frame(width: 150)
                }
                Toggle("Proxy modifiers", isOn: Binding(
                    get: { modifierProxy },
                    set: { emit(modifierProxy: $0) }))
                    .toggleStyle(.checkbox)
            }
            MacroStepsEditorView(steps: steps) { steps in
                emit(steps: steps)
            }
        }
    }

    private func emit(steps: [MacroStep]? = nil, repeatMode: RepeatMode? = nil,
                      repeatIntervalMS: Int? = nil, modifierProxy: Bool? = nil) {
        onChange(.macro(
            steps: steps ?? self.steps,
            repeatMode: repeatMode ?? self.repeatMode,
            repeatIntervalMS: repeatIntervalMS ?? self.repeatIntervalMS,
            modifierProxy: modifierProxy ?? self.modifierProxy))
    }
}
