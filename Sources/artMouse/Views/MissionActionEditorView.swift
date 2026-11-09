import SwiftUI
import ArtMouseCore

struct MissionActionEditorView: View {
    @State var op: MissionOp
    @State var reverse: Bool
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            Picker("", selection: Binding(
                get: { op },
                set: { op = $0; emit() })) {
                Text("Mission Control").tag(MissionOp.missionControl)
                Text("Application Windows").tag(MissionOp.appWindows)
                Text("Launchpad").tag(MissionOp.launchpad)
                Text("Show Desktop").tag(MissionOp.showDesktop)
                Text("Notification Center").tag(MissionOp.notificationCenter).disabled(true)   // phase 4
                Text("Spotlight").tag(MissionOp.spotlight)
                Text("Siri").tag(MissionOp.siri).disabled(true)                                // phase 4
                Text("Fullscreen Button").tag(MissionOp.fullscreenButton)
                Text("Move Left a Space").tag(MissionOp.moveSpaceLeft)
                Text("Move Right a Space").tag(MissionOp.moveSpaceRight)
                ForEach(1...5, id: \.self) { n in
                    Text("Desktop \(n)").tag(MissionOp.desktop(n))
                }
            }
            .labelsHidden()
            .frame(width: 190)

            if isSpaceSwitch {
                Toggle("Reverse", isOn: Binding(get: { reverse }, set: { reverse = $0; emit() }))
                    .toggleStyle(.checkbox)
            }
        }
    }

    private var isSpaceSwitch: Bool {
        op == .moveSpaceLeft || op == .moveSpaceRight
    }

    private func emit() {
        onChange(.mission(op, reverse: reverse))
    }
}
