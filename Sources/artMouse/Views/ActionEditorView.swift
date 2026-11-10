import SwiftUI
import ArtMouseCore

struct ActionEditorView: View {
    let action: Action?
    let onChange: (Action?) -> Void

    var body: some View {
        HStack {
            categoryPicker
            editor
        }
    }

    @ViewBuilder private var editor: some View {
        switch action {
        case .click(let op, let mods): ClickActionEditorView(op: op, mods: mods, onChange: onChange)
        case .mission(let op, let reverse): MissionActionEditorView(op: op, reverse: reverse, onChange: onChange)
        case .music(let op, let fineTune): MusicActionEditorView(op: op, fineTune: fineTune, onChange: onChange)
        case .zoom(let op, let reverse): ZoomActionEditorView(op: op, reverse: reverse, onChange: onChange)
        case .switcher(let op): SwitcherActionEditorView(op: op, onChange: onChange)
        case .open(let target): OpenActionEditorView(target: target, onChange: onChange)
        case .device(let op): DeviceActionEditorView(op: op, onChange: onChange)
        // Interim placeholder: the Scroll category + editor land in Task 10.
        case .some(.scroll): Text("Scroll").foregroundStyle(.secondary)
        // SDK adaptation: `Action` has its own `.none` case, so a bare `case .none`
        // binds to `Optional.none` (nil) and the wrapped `Action.none` payload
        // needs its own pattern; both mean "no action" and render as Unbound.
        case nil, .some(.none): Text("Unbound").foregroundStyle(.secondary)
        }
    }

    private var categoryPicker: some View {
        Picker("", selection: Binding(
            get: { action.map(ActionCategory.init) ?? .none },
            set: { onChange($0.initialAction) })) {
            ForEach(ActionCategory.allCases, id: \.self) { category in
                Text(category.label).tag(category)
            }
        }
        .labelsHidden()
        .frame(width: 110)
    }
}

enum ActionCategory: CaseIterable {
    case none, click, mission, music, zoom, switcher, open, device

    var label: String {
        switch self {
        case .none: return "None"
        case .click: return "Click"
        case .mission: return "Mission"
        case .music: return "Music"
        case .zoom: return "Zoom"
        case .switcher: return "Switcher"
        case .open: return "Open"
        case .device: return "Device"
        }
    }

    init(_ action: Action) {
        switch action {
        case .none: self = .none
        case .click: self = .click
        case .mission: self = .mission
        case .music: self = .music
        case .zoom: self = .zoom
        case .switcher: self = .switcher
        case .open: self = .open
        case .device: self = .device
        case .scroll: self = .none   // interim: Scroll category lands in Task 10
        }
    }

    var initialAction: Action? {
        switch self {
        case .none: return nil
        case .click: return .click(.left, [])
        case .mission: return .mission(.missionControl, reverse: false)
        case .music: return .music(.playPause, fineTune: false)
        case .zoom: return .zoom(.appZoomIn, reverse: false)
        case .switcher: return .switcher(.nextApp)
        case .open: return .open(.path(""))
        case .device: return .device(.activateCursorSpeed(nil))
        }
    }
}
