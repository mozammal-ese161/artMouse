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
    /// ONE handle kept open across records. The former per-line
    /// open/seek/write/close cost 4-6 syscalls per observation on the main
    /// run loop (at 1000 Hz that is every motion axis) and risked saturating
    /// it (Final Review Issue 3). Closed — and reopened lazily by the next
    /// record — on toggle-off, clear(), and deinit.
    private var fileHandle: FileHandle?

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

    public func setPersistToFile(_ on: Bool) {
        persistToFile = on
        if !on { closeFileHandle() }
    }

    public func clear() {
        buffer.removeAll()
        closeFileHandle()
    }

    private func appendToDisk(_ line: String, url: URL) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if fileHandle == nil {
            // File-create path (first write when the file is absent): this
            // line is the create write — open the handle after it so the
            // records that follow reuse it instead of writing the line twice.
            if !FileManager.default.fileExists(atPath: url.path) {
                try? data.write(to: url)
                fileHandle = try? FileHandle(forWritingTo: url)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            fileHandle = handle
        }
        guard let handle = fileHandle else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func closeFileHandle() {
        if let handle = fileHandle {
            try? handle.close()
        }
        fileHandle = nil
    }

    deinit { closeFileHandle() }
}
