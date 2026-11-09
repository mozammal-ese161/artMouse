import SwiftUI
import ArtMouseCore

struct MusicActionEditorView: View {
    @State var op: MusicOp
    @State var fineTune: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(get: { op }, set: { op = $0; emit() })) {
                Text("Play / Pause").tag(MusicOp.playPause)
                Text("Next").tag(MusicOp.next)
                Text("Previous").tag(MusicOp.previous)
                Text("Mute").tag(MusicOp.mute)
                Text("Volume Up").tag(MusicOp.volumeUp)
                Text("Volume Down").tag(MusicOp.volumeDown)
                Text("Eject").tag(MusicOp.eject)
            }
            .labelsHidden()
            .frame(width: 150)

            Toggle("Fine-tune Volume", isOn: Binding(get: { fineTune }, set: { fineTune = $0; emit() }))
                .toggleStyle(.checkbox)
        }
    }

    private func emit() {
        onChange(.music(op, fineTune: fineTune))
    }
}
