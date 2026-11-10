import Foundation

/// Two-way wheel binding: distinct actions per scroll direction.
public struct ScrollBinding: Codable, Equatable, Identifiable {
    public var id: UUID
    public var axis: ScrollAxis
    public var direction: ScrollDirection
    public var actions: [Action]

    public init(id: UUID = UUID(), axis: ScrollAxis, direction: ScrollDirection, actions: [Action]) {
        self.id = id
        self.axis = axis
        self.direction = direction
        self.actions = actions
    }
}
