import Foundation

/// Device Log (spec §6 group 6): a bounded in-memory ring of formatted
/// observation lines with optional append-to-file persistence. Written from
/// the pump's main-queue sink only, so the buffer needs no lock.
public final class HIDEventLog {
    private var buffer: [String] = []
    private let maxEntries: Int
    private let fileURL: URL?
    public private(set) var persistToFile: Bool
    private let now: () -> Date
    private let formatter = ISO8601DateFormatter()

    public init(maxEntries: Int = 500, fileURL: URL? = nil,
                persistToFile: Bool = false, now: @escaping () -> Date = Date.init) {
        self.maxEntries = maxEntries
        self.fileURL = fileURL
        self.persistToFile = persistToFile
        self.now = now
    }

    public func record(_ observation: RawHIDObservation) {
        let hex: (Int) -> String = { String($0, radix: 16) }
        let line = "\(formatter.string(from: now())) vid=\(observation.vendorID) pid=\(observation.productID) "
            + "page=0x\(hex(observation.usagePage)) usage=0x\(hex(observation.usage)) value=\(observation.value)"
        buffer.append(line)
        if buffer.count > maxEntries {
            buffer.removeFirst(buffer.count - maxEntries)
        }
        if persistToFile, let fileURL {
            appendToDisk(line, url: fileURL)
        }
    }

    public var entries: [String] { buffer }

    public func setPersistToFile(_ on: Bool) { persistToFile = on }

    public func clear() { buffer.removeAll() }

    private func appendToDisk(_ line: String, url: URL) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
