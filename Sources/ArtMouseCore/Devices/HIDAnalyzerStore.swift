import Foundation
import Observation

/// Device Analyzer backing store (spec §6 group 6): the newest raw
/// observations for the live view. @Observable so the analyzer sheet tracks
/// additions; written from the pump's main-queue sink only.
@Observable
public final class HIDAnalyzerStore {
    public private(set) var recent: [RawHIDObservation] = []
    private let maxEntries: Int

    public init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
    }

    public func record(_ observation: RawHIDObservation) {
        recent.append(observation)
        if recent.count > maxEntries {
            recent.removeFirst(recent.count - maxEntries)
        }
    }

    public func clear() { recent.removeAll() }
}
