import Foundation

/// One step of a key macro. Wait steps pause the sequence; enterKey posts a
/// full press+release; click posts a full click pair at the current cursor.
public enum MacroStep: Codable, Equatable, Hashable {
    case enterKey(keyCode: UInt64, mods: ModKeys)
    case click(op: ClickOp, mods: ModKeys)
    case wait(milliseconds: Int)
}

public enum RepeatMode: String, Codable, CaseIterable, Equatable {
    case none   // run once per press
    case hold   // repeat the whole sequence while the button is held
}

/// Cursor snapping: move to the focused window's default button, optionally
/// click it, optionally return to the original position.
public enum SnappingOp: Codable, Equatable, Hashable {
    case snap(click: Bool, bounce: Bool)
}
