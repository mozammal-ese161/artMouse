import SwiftUI
import ArtMouseCore

struct DeviceAnalyzerSheet: View {
    let device: HIDDeviceIdentity
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Analyzing \(device.name)").font(.headline)
                Spacer()
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
