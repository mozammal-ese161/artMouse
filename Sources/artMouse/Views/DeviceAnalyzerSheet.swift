import SwiftUI
import ArtMouseCore

struct DeviceAnalyzerSheet: View {
    let device: HIDDeviceIdentity
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Local mirror of `deviceLog.persistToFile`: HIDEventLog is not
    /// @Observable, so a binding reading it directly has no invalidation
    /// source and the toggle would never re-render after its own set. The
    /// sheet owns the mirror while open (the log's state cannot change
    /// behind it — the pump only appends entries) and writes through the
    /// model mutator.
    @State private var persistToFile: Bool

    init(device: HIDDeviceIdentity, model: AppModel) {
        self.device = device
        self.model = model
        _persistToFile = State(initialValue: model.deviceLog?.persistToFile ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Analyzing \(device.name)").font(.headline)
                Spacer()
                // Device Log persistence (spec §6 group 6). Switch style to
                // match the Devices row's Enabled switch.
                Toggle("Save to log file", isOn: Binding(
                    get: { persistToFile },
                    set: {
                        persistToFile = $0
                        model.setDeviceLogPersist($0)
                    }))
                    .toggleStyle(.switch)
                Button("Clear") { model.hidAnalyzer?.clear() }
                Button("Done") { dismiss() }
            }
            .padding(8)
            Divider()
            // Offset identity: identical consecutive observations would
            // collide under \.self.
            List(Array(observerEntries.reversed().enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(.caption, design: .monospaced))
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }

    private var observerEntries: [String] {
        guard let analyzer = model.hidAnalyzer else { return [] }
        return analyzer.recent
            .filter { $0.vendorID == device.vendorID && $0.productID == device.productID }
            .map { o in
                "page 0x\(String(o.usagePage, radix: 16)) usage 0x\(String(o.usage, radix: 16)) value \(o.value)"
            }
    }
}
