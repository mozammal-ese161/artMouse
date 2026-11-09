import SwiftUI

/// Yellow banner surfacing the cursor safety-restore warning (spec §7):
/// a button switched the cursor speed and it restores in 5 s. Renders
/// nothing while the warning is nil; reading it through the @Observable
/// bootstrap tracks the tick timer's mirror, so the banner appears and
/// clears with the restore itself.
struct SafetyWarningBannerView: View {
    let bootstrap: EngineBootstrap?

    var body: some View {
        if let warning = bootstrap?.safetyRestoreWarning {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(warning)
            }
            .padding(8)
            .background(.yellow.opacity(0.25))
        }
    }
}
