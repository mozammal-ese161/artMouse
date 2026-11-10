import SwiftUI
import ArtMouseCore

struct ChordsTabView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Button chords").font(.headline)
                Spacer()
                Button("Add Chord") { model.addChord() }
            }
            List(model.settings.chords) { chord in
                ChordEditorView(chord: chord,
                                onUpdate: { model.updateChord($0) },
                                onDelete: { model.removeChord($0.id) })
            }
            Text("Press the first button, then the rest within the timeout. While a chord is possible, the first button's own binding is deferred; releasing it alone fires its normal binding. A chord held past its timeout flushes at your next input — the initiator's own binding fires then.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
