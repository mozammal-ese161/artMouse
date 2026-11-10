import SwiftUI

/// Finiteness-guarded numeric field helpers (Review-class fix from Phase 3:
/// NaN/inf from force-typing must never trap). Shared with Task 9's sweep.
func safeInt(_ text: String, in range: ClosedRange<Int>, fallback: Int) -> Int {
    guard let value = Double(text), value.isFinite else { return fallback }
    return Int(Swift.min(Swift.max(value, Double(range.lowerBound)), Double(range.upperBound)))
}

/// Range-less guard for `Int(Double)` conversions of user-typed `.number`
/// field values (the Phase 3 trap class): NaN, ±inf, and doubles beyond the
/// Int range all land on `fallback` instead of trapping. Used by editors that
/// deliberately carry no field range (the wheel profile fields —
/// ScrollController clamps every value at consumption).
func safeInt(_ value: Double, fallback: Int) -> Int {
    guard value.isFinite, value >= Double(Int.min), value < Double(Int.max) else { return fallback }
    return Int(value)
}

/// Numeric-field bounds for the keycode conversion below. `format: .number`
/// hands the setter any Double (e.g. a pasted 25-digit number), and
/// UInt64(...)/Int(...) TRAP out of range — values are clamped in Double
/// space BEFORE converting. The keycode ceiling cannot be Double(UInt64.max):
/// that literal rounds UP to exactly 2^64, which is itself out of UInt64
/// range and would trap, so it steps back one representable double (2048 at
/// that magnitude).
let maxKeyCodeDouble = Double(UInt64.max) - 2048

/// Clamp in Double space so an out-of-range integer conversion can never run.
/// NaN compares false against everything, so it is routed to the range's
/// lower bound explicitly: `Swift.max(nan, 0)` propagates NaN in this helper's
/// argument order and the conversion would trap again ("cannot be converted…
/// infinite or NaN") — the pre-fix `max(0, value)` form absorbed NaN only by
/// accident of its argument order. ±inf lands on the lower bound too; either
/// extreme is an acceptable landing spot for a pasted "inf".
extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        isFinite ? Swift.min(Swift.max(self, range.lowerBound), range.upperBound) : range.lowerBound
    }
}

/// True when `text` could still grow into a number inside `range` — the
/// prefix pass-through SafeIntField uses to keep "1" (or "") on screen in a
/// 100...30000 field instead of clamping it to 100 on the first keystroke.
/// Conservative on narrow ranges (any partial below `upperBound` counts as a
/// prefix even when every digit-extension would overshoot `lowerBound` too);
/// the only cost of over-counting is that the raw text lingers until the next
/// in-range keystroke or an external sync — no such ranges exist in this app.
func isPrefixOfInRange(_ text: String, in range: ClosedRange<Int>) -> Bool {
    guard let value = Double(text), value.isFinite else { return text.isEmpty }
    guard value >= 0 else { return range.lowerBound < 0 }
    return value < Double(range.upperBound)
}

/// Text-backed integer field: parses through `safeInt` on every edit, so a
/// blank or non-numeric entry keeps the previous value (`fallback`) instead of
/// trapping, and out-of-range entries clamp into `range`. Prefix-aware
/// (Task 9 polish): a partial number that could still grow into range ("1"
/// in a 100...30000 field) passes through unclamped so typing works naturally;
/// the previous value stays bound until the text lands in range or an
/// external change resyncs the field.
struct SafeIntField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 64
    @State private var text: String = ""

    init(_ label: String, value: Binding<Int>, in range: ClosedRange<Int>, width: CGFloat = 64) {
        self.label = label
        _value = value
        self.range = range
        self.width = width
    }

    var body: some View {
        LabeledContent(label) {
            TextField("", text: $text)
                .frame(width: width)
                .onAppear { text = String(value) }
                .onChange(of: text) { raw in
                    if let parsed = Double(raw), parsed.isFinite,
                       parsed >= Double(range.lowerBound), parsed <= Double(range.upperBound) {
                        value = Int(parsed)
                    } else if isPrefixOfInRange(raw, in: range) {
                        return   // keep the raw text; value holds its previous number
                    } else {
                        value = safeInt(raw, in: range, fallback: value)   // clamp as before
                        text = String(value)   // snap garbage back, like the old derived text
                    }
                }
                .onChange(of: value) { text = String($0) }   // external changes resync the field
        }
    }
}
