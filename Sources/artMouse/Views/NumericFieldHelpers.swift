import SwiftUI

/// Finiteness-guarded numeric field helpers (Review-class fix from Phase 3:
/// NaN/inf from force-typing must never trap). Shared with Task 9's sweep.
func safeInt(_ text: String, in range: ClosedRange<Int>, fallback: Int) -> Int {
    guard let value = Double(text), value.isFinite else { return fallback }
    return Int(Swift.min(Swift.max(value, Double(range.lowerBound)), Double(range.upperBound)))
}

/// Text-backed integer field: parses through `safeInt` on every edit, so a
/// blank or non-numeric entry keeps the previous value (`fallback`) instead of
/// trapping, and out-of-range entries clamp into `range`.
struct SafeIntField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 64

    init(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>, width: CGFloat = 64) {
        self.label = label
        _value = value
        self.range = range
        self.width = width
    }

    var body: some View {
        LabeledContent(label) {
            TextField("", text: Binding(
                get: { String(value) },
                set: { value = safeInt($0, in: range, fallback: value) }))
                .frame(width: width)
        }
    }
}
