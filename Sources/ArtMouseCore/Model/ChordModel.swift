import Foundation

/// Multi-button combination: buttons[0] initiates capture; the chord fires
/// when every button in `buttons` is held within `timeout` seconds.
public struct Chord: Codable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var buttons: [ButtonID]
    public var actions: [Action]
    public var timeout: Double

    public init(id: UUID = UUID(), buttons: [ButtonID], actions: [Action], timeout: Double = 0.3) {
        self.id = id
        self.buttons = buttons
        self.actions = actions
        self.timeout = timeout
    }
}
