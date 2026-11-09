import SwiftUI

struct PermissionBannerView: View {
    @ObservedObject var permissions: PermissionsController

    var body: some View {
        if permissions.accessibility == .denied || permissions.inputMonitoring == .denied {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("artMouse needs Accessibility and Input Monitoring permissions.")
                Spacer()
                Button("Grant") {
                    permissions.promptAccessibility()
                    PermissionsController.deepLinkToInputMonitoring()
                }
            }
            .padding(8)
            .background(.yellow.opacity(0.25))
        }
    }
}
