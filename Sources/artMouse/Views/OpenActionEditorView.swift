import SwiftUI
import AppKit
import ArtMouseCore

struct OpenActionEditorView: View {
    @State var target: OpenTarget
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            switch target {
            case .path(let p):
                TextField("Path", text: Binding(
                    get: { p },
                    set: { target = .path($0); onChange(.open(target)) }))
                    .frame(width: 220)
                Button("Choose…") { chooseFile() }
            case .url(let u):
                TextField("URL", text: Binding(
                    get: { u },
                    set: { target = .url($0); onChange(.open(target)) }))
                    .frame(width: 220)
            }
            Picker("", selection: Binding(
                get: { kind },
                set: { newKind in
                    target = newKind == .pathKind ? .path("") : .url("")
                    onChange(.open(target))
                })) {
                Text("Path").tag(Kind.pathKind)
                Text("URL").tag(Kind.urlKind)
            }
            .frame(width: 70)
        }
    }

    private enum Kind { case pathKind, urlKind }

    private var kind: Kind {
        if case .path = target { return .pathKind }
        return .urlKind
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            target = .path(url.path)
            onChange(.open(target))
        }
    }
}
