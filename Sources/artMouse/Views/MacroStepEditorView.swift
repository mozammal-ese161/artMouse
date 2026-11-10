import SwiftUI
import ArtMouseCore

/// Numeric-field bounds for the conversion below. `format: .number` hands the
/// setter any Double (e.g. a pasted 25-digit number), and UInt64(...)/Int(...)
/// TRAP out of range — values are clamped in Double space BEFORE converting.
/// The keycode ceiling cannot be Double(UInt64.max): that literal rounds UP to
/// exactly 2^64, which is itself out of UInt64 range and would trap, so it
/// steps back one representable double (2048 at that magnitude).
private let maxKeyCodeDouble = Double(UInt64.max) - 2048

struct MacroStepEditorView: View {
    let step: MacroStep
    let onChange: (MacroStep) -> Void

    var body: some View {
        switch step {
        case .enterKey(let keyCode, let mods):
            HStack {
                Text("Key").frame(width: 70, alignment: .leading)
                LabeledContent("Code") {
                    TextField("", value: Binding(
                        get: { Double(keyCode) },
                        set: { onChange(.enterKey(keyCode: UInt64($0.clamped(0...maxKeyCodeDouble)),
                                                  mods: mods)) }),
                        format: .number)
                        .frame(width: 60)
                }
                .frame(width: 110)
                modChecks("⌘⌃⌥⇧", current: mods) { onChange(.enterKey(keyCode: keyCode, mods: $0)) }
            }
        case .click(let op, let mods):
            HStack {
                Text("Click").frame(width: 70, alignment: .leading)
                Picker("", selection: Binding(
                    get: { op },
                    set: { onChange(.click(op: $0, mods: mods)) })) {
                    Text("Left").tag(ClickOp.left)
                    Text("Right").tag(ClickOp.right)
                    Text("Middle").tag(ClickOp.middle)
                }
                .labelsHidden()
                .frame(width: 90)
                modChecks("⌘⌃⌥⇧", current: mods) { onChange(.click(op: op, mods: $0)) }
            }
        case .wait(let ms):
            HStack {
                Text("Wait").frame(width: 70, alignment: .leading)
                LabeledContent("ms") {
                    TextField("", value: Binding(
                        get: { Double(ms) },
                        set: { onChange(.wait(milliseconds: Int($0.clamped(1...60_000))) ) }),
                        format: .number)
                        .frame(width: 60)
                }
                .frame(width: 110)
            }
        }
    }

    private let modRows: [(String, ModKeys)] = [("⌘", .command), ("⌃", .control), ("⌥", .option), ("⇧", .shift)]

    private func modChecks(_ title: String, current: ModKeys,
                           onChange: @escaping (ModKeys) -> Void) -> some View {
        HStack {
            ForEach(modRows, id: \.1) { item in
                Toggle(item.0, isOn: Binding(
                    get: { current.contains(item.1) },
                    set: { on in
                        var next = current
                        if on { next.insert(item.1) } else { next.remove(item.1) }
                        onChange(next)
                    }))
                    .toggleStyle(.checkbox)
            }
        }
    }
}

/// Clamp in Double space so an out-of-range integer conversion can never run.
/// NaN compares false against everything, so it is routed to the range's
/// lower bound explicitly: `Swift.max(nan, 0)` propagates NaN in this helper's
/// argument order and the conversion would trap again ("cannot be converted…
/// infinite or NaN") — the pre-fix `max(0, value)` form absorbed NaN only by
/// accident of its argument order. ±inf lands on the lower bound too; either
/// extreme is an acceptable landing spot for a pasted "inf".
private extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        isFinite ? Swift.min(Swift.max(self, range.lowerBound), range.upperBound) : range.lowerBound
    }
}
