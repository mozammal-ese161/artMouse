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
    public var wheelModeProfiles: [WheelModeProfile]
    public var activeWheelModeProfileID: UUID?
    public var scrollBindings: [ScrollBinding]
    public var chords: [Chord]

    public static let `default` = GlobalSettings(
        schemaVersion: 1,
        cursorSpeedProfiles: [
            CursorSpeedProfile(name: "Slow", sensitivity: 800, acceleration: 0.0),
            CursorSpeedProfile(name: "Default", sensitivity: 1600, acceleration: 1.0),
            CursorSpeedProfile(name: "Fast", sensitivity: 3200, acceleration: 2.0),
        ],
        activeCursorSpeedProfileID: nil,   // resolved to "Default" by name on first run
        precisionProfileID: nil,
        buttonBindings: [],
        // Phase 2 wheel fields start empty: fresh defaults must resolve to no active
        // wheel profile (pass-through), pinned by testWheelModeProfileFallbackChain.
        // Profiles are user-created (Settings UI, Task 10).
        wheelModeProfiles: [],
        activeWheelModeProfileID: nil,
        scrollBindings: [],
        chords: []
    )
}

/// Backward-compatible decoding: a Phase 1 settings.json lacks every Phase 2
/// field, so absent keys default (empty) instead of failing the whole decode —
/// the user's existing bindings and cursor profiles must survive the upgrade.
/// Lives in an extension so the memberwise initializer stays synthesized for
/// `static let default`.
extension GlobalSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        cursorSpeedProfiles = try c.decode([CursorSpeedProfile].self, forKey: .cursorSpeedProfiles)
        activeCursorSpeedProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeCursorSpeedProfileID)
        precisionProfileID = try c.decodeIfPresent(UUID.self, forKey: .precisionProfileID)
        buttonBindings = try c.decode([ButtonBinding].self, forKey: .buttonBindings)
        // Phase 2 fields: absent in Phase 1 files → empty defaults (backward compat).
        wheelModeProfiles = try c.decodeIfPresent([WheelModeProfile].self, forKey: .wheelModeProfiles) ?? []
        activeWheelModeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeWheelModeProfileID)
        scrollBindings = try c.decodeIfPresent([ScrollBinding].self, forKey: .scrollBindings) ?? []
        chords = try c.decodeIfPresent([Chord].self, forKey: .chords) ?? []
    }
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

    /// The wheel profile used for scroll transforms (same fallback chain as
    /// activeProfile): explicit ID → profile named "Default" → first.
    var activeWheelProfile: WheelModeProfile? {
        if let id = activeWheelModeProfileID,
           let match = wheelModeProfiles.first(where: { $0.id == id }) { return match }
        if let named = wheelModeProfiles.first(where: { $0.name == "Default" }) { return named }
        return wheelModeProfiles.first
    }
}
