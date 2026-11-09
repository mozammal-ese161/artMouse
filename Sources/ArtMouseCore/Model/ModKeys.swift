/// Modifier buttons held during an action. Raw values match CGEventFlags shifts
/// conceptually but are persisted as-is; conversion to CGEventFlags lives in
/// ActionExecutor (system layer only).
public struct ModKeys: OptionSet, Codable, Hashable, CaseIterable {
    public static let command = ModKeys(rawValue: 1)
    public static let control = ModKeys(rawValue: 2)
    public static let option  = ModKeys(rawValue: 4)
    public static let shift   = ModKeys(rawValue: 8)

    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public var rawValue: UInt8

    /// Manual synthesis is required because CaseIterable is only
    /// auto-synthesized for enums.
    public static var allCases: [ModKeys] {
        [.command, .control, .option, .shift]
    }
}
