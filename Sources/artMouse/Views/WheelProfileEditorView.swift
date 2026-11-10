import SwiftUI
import ArtMouseCore

struct WheelProfileEditorView: View {
    let profile: WheelModeProfile
    let isActive: Bool
    let onUpdate: (WheelModeProfile) -> Void
    let onDelete: (WheelModeProfile) -> Void
    let onActivate: (WheelModeProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                TextField("Name", text: Binding(
                    get: { profile.name },
                    set: { onUpdate(copy(name: $0)) }))
                    .frame(width: 110)

                Picker("", selection: Binding(
                    get: { profile.mode },
                    set: { onUpdate(copy(mode: $0)) })) {
                    Text("Acceleration").tag(ScrollMode.acceleration)
                    Text("Constant").tag(ScrollMode.constant)
                    Text("Auto").tag(ScrollMode.auto)
                }
                .labelsHidden()
                .frame(width: 130)

                numericField("Sens", value: profile.sensFactor) { onUpdate(copy(sensFactor: $0)) }
                numericField("Accel", value: profile.acceleration) { onUpdate(copy(acceleration: $0)) }
                numericField("Lines", value: profile.lines) { onUpdate(copy(lines: $0)) }

                Button(isActive ? "Active" : "Use") { onActivate(profile) }
                    .disabled(isActive)
                Toggle("Reverse V", isOn: Binding(
                    get: { profile.reverseVertical },
                    set: { onUpdate(copy(reverseVertical: $0)) }))
                    .toggleStyle(.checkbox)
                Toggle("Reverse H", isOn: Binding(
                    get: { profile.reverseHorizontal },
                    set: { onUpdate(copy(reverseHorizontal: $0)) }))
                    .toggleStyle(.checkbox)
                Spacer()
                Button(role: .destructive) { onDelete(profile) } label: { Image(systemName: "trash") }
                    .disabled(isActive)
            }
            HStack(spacing: 12) {
                Toggle("Smooth Scroll", isOn: Binding(
                    get: { profile.smoothScroll },
                    set: { onUpdate(copy(smoothScroll: $0)) }))
                    .toggleStyle(.checkbox)
                if profile.smoothScroll {
                    numericField("Smooth step (ms)", value: Double(profile.smoothIntervalMS)) {
                        onUpdate(copy(smoothIntervalMS: Int($0)))
                    }
                }
                if profile.mode == .constant || profile.mode == .auto {
                    numericField("Interval (ms)", value: Double(profile.intervalMS)) {
                        onUpdate(copy(intervalMS: Int($0)))
                    }
                }
                // Free-spin momentum is a constant-mode feature only: it is
                // the one mode that eats the OS's own momentum ticks.
                if profile.mode == .constant {
                    Toggle("Free-spin momentum", isOn: Binding(
                        get: { profile.freeSpinMomentum },
                        set: { onUpdate(copy(freeSpinMomentum: $0)) }))
                        .toggleStyle(.checkbox)
                    if profile.freeSpinMomentum {
                        numericField("Coast decay (%)", value: Double(profile.momentumDecayPercent)) {
                            onUpdate(copy(momentumDecayPercent: Int($0)))
                        }
                        numericField("Coast max (notches)", value: Double(profile.momentumMaxTicks)) {
                            onUpdate(copy(momentumMaxTicks: Int($0)))
                        }
                    }
                }
                if profile.mode == .auto {
                    numericField("Auto interval (ms)", value: Double(profile.autoIntervalMS)) {
                        onUpdate(copy(autoIntervalMS: Int($0)))
                    }
                    numericField("Auto stop (notches)", value: Double(profile.autoStopTicks)) {
                        onUpdate(copy(autoStopTicks: Int($0)))
                    }
                }
                WheelKeysEditorView(emulation: profile.keyEmulation) {
                    onUpdate(copy(keyEmulation: $0))
                }
            }
        }
        .padding(.vertical, 2)
    }

    // Identity bindings (Phase 1 lesson): the field shows exactly what is typed;
    // ScrollController clamps every value at consumption, so the editor never needs a range.
    private func numericField(_ title: String, value: Double,
                              onChange: @escaping (Double) -> Void) -> some View {
        LabeledContent(title) {
            TextField("", value: Binding(
                get: { value },
                set: { onChange($0) }), format: .number)
                .frame(width: 60)
        }
        .frame(width: fieldWidth(title))
    }

    private func fieldWidth(_ title: String) -> CGFloat {
        switch title {
        case "Sens", "Accel", "Lines": return 120
        default: return 170
        }
    }

    // copy() helpers — one per mutated field, mirroring Phase 1's profileWithName pattern:
    private func copy(name: String) -> WheelModeProfile { var c = profile; c.name = name; return c }
    private func copy(mode: ScrollMode) -> WheelModeProfile { var c = profile; c.mode = mode; return c }
    private func copy(sensFactor: Double) -> WheelModeProfile { var c = profile; c.sensFactor = sensFactor; return c }
    private func copy(acceleration: Double) -> WheelModeProfile { var c = profile; c.acceleration = acceleration; return c }
    private func copy(lines: Double) -> WheelModeProfile { var c = profile; c.lines = lines; return c }
    private func copy(intervalMS: Int) -> WheelModeProfile { var c = profile; c.intervalMS = intervalMS; return c }
    private func copy(reverseVertical: Bool) -> WheelModeProfile { var c = profile; c.reverseVertical = reverseVertical; return c }
    private func copy(reverseHorizontal: Bool) -> WheelModeProfile { var c = profile; c.reverseHorizontal = reverseHorizontal; return c }
    private func copy(smoothScroll: Bool) -> WheelModeProfile { var c = profile; c.smoothScroll = smoothScroll; return c }
    private func copy(smoothIntervalMS: Int) -> WheelModeProfile { var c = profile; c.smoothIntervalMS = smoothIntervalMS; return c }
    private func copy(autoIntervalMS: Int) -> WheelModeProfile { var c = profile; c.autoIntervalMS = autoIntervalMS; return c }
    private func copy(autoStopTicks: Int) -> WheelModeProfile { var c = profile; c.autoStopTicks = autoStopTicks; return c }
    private func copy(freeSpinMomentum: Bool) -> WheelModeProfile { var c = profile; c.freeSpinMomentum = freeSpinMomentum; return c }
    private func copy(momentumDecayPercent: Int) -> WheelModeProfile { var c = profile; c.momentumDecayPercent = momentumDecayPercent; return c }
    private func copy(momentumMaxTicks: Int) -> WheelModeProfile { var c = profile; c.momentumMaxTicks = momentumMaxTicks; return c }
    private func copy(keyEmulation: WheelKeyEmulation?) -> WheelModeProfile { var c = profile; c.keyEmulation = keyEmulation; return c }
}
