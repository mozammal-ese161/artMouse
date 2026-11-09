import Foundation
import Combine

/// Loads/saves settings.json in the given directory. A malformed or missing
/// file yields defaults plus a warning (spec §7) — never a crash.
public final class SettingsStore: ObservableObject {
    static let settingsFileName = "settings.json"

    @Published public private(set) var lastLoadWarnings: [String] = []
    @Published public var settings: GlobalSettings {
        didSet { objectWillChange.send() }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(Self.settingsFileName)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.settings = .default
        reload()
    }

    public func reload() {
        guard let data = try? Data(contentsOf: fileURL) else {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                lastLoadWarnings = ["Could not read \(Self.settingsFileName); using defaults."]
            }
            return
        }
        do {
            settings = try Self.decode(data)
            lastLoadWarnings = []
        } catch {
            settings = .default
            lastLoadWarnings = ["\(Self.settingsFileName) could not be read (\(error.localizedDescription)); using defaults."]
        }
    }

    public func save() throws {
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Strict decode used by tests and import; falls back happen in reload().
    public static func decode(_ data: Data) throws -> GlobalSettings {
        try JSONDecoder().decode(GlobalSettings.self, from: data)
    }
}
