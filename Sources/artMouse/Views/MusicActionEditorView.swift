import SwiftUI
import ArtMouseCore

struct MusicActionEditorView: View {
    let op: MusicOp
    let fineTune: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { op },
                set: { onChange(.music($0, fineTune: fineTune)) })) {
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

            Toggle("Fine-tune Volume", isOn: Binding(
                get: { fineTune },
                set: { onChange(.music(op, fineTune: $0)) }))
                .toggleStyle(.checkbox)
        }
    }
}
