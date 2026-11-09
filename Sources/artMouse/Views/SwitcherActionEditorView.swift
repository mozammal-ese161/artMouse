import SwiftUI
import ArtMouseCore

struct SwitcherActionEditorView: View {
    let op: SwitcherOp
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { op },
                set: { onChange(.switcher($0)) })) {
                Text("Next Application").tag(SwitcherOp.nextApp)
                Text("Previous Application").tag(SwitcherOp.previousApp)
                Text("Application Windows").tag(SwitcherOp.applicationWindows)
                Text("Show Switcher Window").tag(SwitcherOp.showSwitcher).disabled(true)   // phase 4
                Text("Switch to App…").tag(SwitcherOp.app(.bundleID("")))
            }
            .labelsHidden()
            .frame(width: 180)

            if case .app(let target) = op {
                switch target {
                case .bundleID(let id):
                    TextField("Bundle ID", text: Binding(
                        get: { id },
                        set: { onChange(.switcher(.app(.bundleID($0)))) }))
                        .frame(width: 180)
                case .url(let u):
                    TextField("URL", text: Binding(
                        get: { u },
                        set: { onChange(.switcher(.app(.url($0)))) }))
                        .frame(width: 180)
                case .bookmark:
                    EmptyView()   // created via URL/bookmark picker in a later phase
                }
            }
        }
    }
}
