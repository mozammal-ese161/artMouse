import Foundation

public struct CursorSpeedProfile: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// Counts per inch; 1600 = system-neutral scale factor 1.0.
    public var sensitivity: Double
    /// 0 disables acceleration entirely (1:1 for the movement component).
    public var acceleration: Double

    public init(id: UUID = UUID(), name: String, sensitivity: Double, acceleration: Double) {
        self.id = id
        self.name = name
        self.sensitivity = sensitivity
        self.acceleration = acceleration
    }
}

public struct ButtonBinding: Codable, Equatable, Identifiable {
    public var id: UUID
    public var button: ButtonID
    public var actions: [Action]

    public init(id: UUID = UUID(), button: ButtonID, actions: [Action]) {
        self.id = id
        self.button = button
        self.actions = actions
    }
}

public struct GlobalSettings: Codable, Equatable {
    public var schemaVersion: Int
    public var cursorSpeedProfiles: [CursorSpeedProfile]
    public var activeCursorSpeedProfileID: UUID?
    public var precisionProfileID: UUID?
    public var buttonBindings: [ButtonBinding]

    public static let `default` = GlobalSettings(
        schemaVersion: 1,
        cursorSpeedProfiles: [
            CursorSpeedProfile(name: "Slow", sensitivity: 800, acceleration: 0.0),
            CursorSpeedProfile(name: "Default", sensitivity: 1600, acceleration: 1.0),
            CursorSpeedProfile(name: "Fast", sensitivity: 3200, acceleration: 2.0),
        ],
        activeCursorSpeedProfileID: nil,   // resolved to "Default" by name on first run
        precisionProfileID: nil,
        buttonBindings: []
    )
}

public extension GlobalSettings {
    /// The profile used for cursor transforms (falls back to first profile).
    var activeProfile: CursorSpeedProfile? {
        let profiles = cursorSpeedProfiles
        if let id = activeCursorSpeedProfileID,
           let match = profiles.first(where: { $0.id == id }) { return match }
        if let named = profiles.first(where: { $0.name == "Default" }) { return named }
        return profiles.first
    }

    var precisionProfile: CursorSpeedProfile? {
        if let id = precisionProfileID,
           let match = cursorSpeedProfiles.first(where: { $0.id == id }) { return match }
        return cursorSpeedProfiles.first
    }
}
