import SwiftUI

struct SettingsWindow: View {
    @State private var model: AppModel
    @State private var safetyBootstrap: EngineBootstrap?

    init(model: AppModel, safetyBootstrap: EngineBootstrap? = nil) {
        _model = State(initialValue: model)
        _safetyBootstrap = State(initialValue: safetyBootstrap)
    }

    var body: some View {
        VStack(spacing: 0) {
            PermissionBannerView(permissions: model.permissions)
            WarningsBannerView(warnings: model.lastLoadWarnings)
            SafetyWarningBannerView(bootstrap: safetyBootstrap)
            TabView {
                ButtonsTabView(model: model)
                    .tabItem { Text("Buttons") }
                WheelTabView(model: model)
                    .tabItem { Text("Wheel") }
                ScrollBindingsTabView(model: model)
                    .tabItem { Text("Scroll Bindings") }
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
