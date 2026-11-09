import SwiftUI

struct SettingsWindow: View {
    @State private var model: AppModel

    init(model: AppModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            PermissionBannerView(permissions: model.permissions)
            WarningsBannerView(warnings: model.lastLoadWarnings)
            TabView {
                ButtonsTabView(model: model)
                    .tabItem { Text("Buttons") }
                CursorTabView(model: model)
                    .tabItem { Text("Cursor") }
                DevicesTabView(model: model)
                    .tabItem { Text("Devices") }
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}
