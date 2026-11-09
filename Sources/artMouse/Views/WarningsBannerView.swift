import SwiftUI

/// Yellow banner listing settings-load warnings (e.g. a malformed
/// settings.json fell back to defaults). Renders nothing when empty.
struct WarningsBannerView: View {
    let warnings: [String]

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(warnings, id: \.self) { warning in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(warning)
                    }
                }
            }
            .padding(8)
            .background(.yellow.opacity(0.25))
        }
    }
}
