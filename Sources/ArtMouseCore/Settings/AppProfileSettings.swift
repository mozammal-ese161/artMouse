import Foundation

/// Per-application settings overlay. Nil fields inherit the global settings;
/// button/scroll binding overrides are v1-edited via settings.json only
/// (documented in the Apps tab caption).
public struct AppProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var bundleID: String
    public var name: String
    public var buttonBindings: [ButtonBinding]?
    public var scrollBindings: [ScrollBinding]?
    public var cursorSpeedProfileID: UUID?
    public var wheelModeProfileID: UUID?

    public init(id: UUID = UUID(), bundleID: String, name: String,
                buttonBindings: [ButtonBinding]? = nil, scrollBindings: [ScrollBinding]? = nil,
                cursorSpeedProfileID: UUID? = nil, wheelModeProfileID: UUID? = nil) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.buttonBindings = buttonBindings
        self.scrollBindings = scrollBindings
        self.cursorSpeedProfileID = cursorSpeedProfileID
        self.wheelModeProfileID = wheelModeProfileID
    }
}
