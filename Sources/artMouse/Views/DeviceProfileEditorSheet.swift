import SwiftUI
import ArtMouseCore

/// Modal editor for one device profile (parts + DPI). Unlike the inline row
/// editors (which derive from props and call `onUpdate` per keystroke), a
/// modal sheet owns its draft: the draft is built HERE from the edited
/// device (the stored profile when one exists, otherwise a fresh skeleton —
/// never persisted on open, so Cancel leaves a profile-less device
/// profile-less), edits accumulate in `@State`, and everything is written
/// through `onSave` exactly once on Save; Cancel and Delete never create.
struct DeviceProfileEditorSheet: View {
    let device: HIDDeviceIdentity
    /// The stored profile for `device`, or nil when the sheet authors a new
    /// one (Save then routes through addDeviceProfile; Delete is a harmless
    /// no-op for a draft that was never stored).
    let existing: DeviceProfile?
    let onSave: (DeviceProfile) -> Void
    let onDelete: (DeviceProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DeviceProfile

    init(device: HIDDeviceIdentity,
         existing: DeviceProfile?,
         onSave: @escaping (DeviceProfile) -> Void,
         onDelete: @escaping (DeviceProfile) -> Void) {
        self.device = device
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: existing ?? DeviceProfile(name: device.name,
                                                               vendorID: device.vendorID,
                                                               productID: device.productID))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Device Profile").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
            }
            .padding(8)
            Divider()
            Form {
                Section("Identity") {
                    TextField("Name", text: $draft.name)
                    LabeledContent("Device") {
                        Text("VID \(draft.vendorID) PID \(draft.productID)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Parts") {
                    ForEach($draft.parts) { $part in
                        DevicePartEditorRow(part: $part,
                                            takenRoutingNumbers: Set(draft.parts.compactMap(\.routesAsButton))) {
                            draft.parts.removeAll { $0.id == part.id }
                        }
                    }
                    Button("Add Part") {
                        // New parts are buttons with a concrete routing
                        // target: the row's picker displays "Button 6" for
                        // the `?? 5` fallback, so the model must agree (a nil
                        // routesAsButton is engine-inert but would still be
                        // displayed as Button 6).
                        //
                        // The usage skeleton starts at 3 — the first
                        // non-left/right button usage: usage 1 is the physical
                        // left button, and a saved unedited part must not
                        // claim it (a profile part wins over the
                        // CG-covered-usage drop rule in the translator).
                        draft.parts.append(DevicePart(
                            name: "Part \(draft.parts.count + 1)",
                            kind: .button,
                            usagePage: HIDUsage.buttonPage,
                            usage: min(draft.parts.count + 2, 32),
                            routesAsButton: Self.nextFreeRoutingNumber(
                                avoiding: Set(draft.parts.compactMap(\.routesAsButton)))))
                    }
                }
                Section {
                    Toggle("Capture extra buttons as raw HID", isOn: $draft.rawButtonCapture)
                    Text("Only for mice whose extra buttons never reach macOS. If your buttons already work, enabling this fires each press twice.")
                        .font(.caption).foregroundStyle(.orange)
                } header: {
                    Text("Extra Buttons")
                }
                Section("DPI Feature Reports") {
                    Toggle("Configure DPI feature reports", isOn: Binding(
                        get: { draft.dpi != nil },
                        set: { enabled in
                            draft.dpi = enabled ? DeviceDPIConfig(levels: [800, 1600, 3200]) : nil
                        }))
                    if draft.dpi != nil {
                        DeviceDPIPanel(config: Binding(
                            get: { draft.dpi ?? DeviceDPIConfig(levels: []) },
                            set: { draft.dpi = $0 }))
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Delete Profile", role: .destructive) {
                    onDelete(draft)
                    dismiss()
                }
                Spacer()
            }
            .padding(8)
        }
        .frame(minWidth: 640, minHeight: 560)
    }

    /// First routing number in 5...31 that no other part of this profile
    /// already claims; 5 when every slot is taken (the picker's displayed
    /// fallback). Two fresh parts both seeding Button 6 would route two
    /// physical elements into one binding — collision-free seeding keeps
    /// each part's route distinct.
    fileprivate static func nextFreeRoutingNumber(avoiding taken: Set<Int>) -> Int {
        (5...31).first { !taken.contains($0) } ?? 5
    }
}

/// One parts-list row: name, kind, HID usage coordinates, and — for button
/// and pedal kinds — the CGEvent button number the element routes as
/// ("Button 6"…"Button 32"). Wheel parts never carry a routing number.
private struct DevicePartEditorRow: View {
    @Binding var part: DevicePart
    let takenRoutingNumbers: Set<Int>
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Name", text: $part.name)
                    .frame(width: 100)
                Picker("Kind", selection: Binding(
                    get: { part.kind },
                    set: { newKind in
                        part.kind = newKind
                        // Wheel parts must not route as a button; button/pedal
                        // parts always need a target, so give a skeleton one that
                        // no sibling part already claims.
                        if newKind == .wheel {
                            part.routesAsButton = nil
                        } else if part.routesAsButton == nil {
                            part.routesAsButton = DeviceProfileEditorSheet
                                .nextFreeRoutingNumber(avoiding: takenRoutingNumbers)
                        }
                    })) {
                    Text("Button").tag(DevicePartKind.button)
                    Text("Wheel").tag(DevicePartKind.wheel)
                    Text("Pedal").tag(DevicePartKind.pedal)
                }
                // Wide enough to show "label + selected value" (96 clipped the
                // value to a bare chevron on the grouped-form style).
                .frame(width: 130)
                SafeIntField("Page", value: $part.usagePage, in: 0...65535, width: 70)
                SafeIntField("Usage", value: $part.usage, in: 0...65535, width: 70)
                if part.kind != .wheel {
                    Picker("Routes as", selection: Binding(
                        get: { part.routesAsButton ?? 5 },
                        set: { part.routesAsButton = $0 })) {
                        ForEach(5...31, id: \.self) { number in
                            Text("Button \(number + 1)").tag(number)
                        }
                    }
                    .frame(width: 120)
                }
                Spacer()
                Button(role: .destructive, action: onRemove) { Image(systemName: "trash") }
            }
            if targetsStandardWheelUsage {
                // A profile part wins over the translator's tap-covered-usage
                // drop rule, so claiming the standard wheel/AC Pan usages
                // feeds every roll twice: once as macOS's own scrollWheel
                // event, once as the part's routed tick.
                Text("macOS already delivers this usage as scroll events — the part will double-fire.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    /// Wheel parts targeting the standard wheel (GD_Wheel) or horizontal
    /// tilt (GD_AC_Pan) usages on the generic-desktop page — the usages
    /// macOS already delivers as scrollWheel CGEvents.
    private var targetsStandardWheelUsage: Bool {
        part.kind == .wheel
            && part.usagePage == HIDUsage.genericDesktopPage
            && (part.usage == HIDUsage.gdWheel || part.usage == HIDUsage.gdACPan)
    }
}

/// DPI feature-report layout editor. All declared numbers are clamped here at
/// entry; DPIReportBuilder clamps again at the engine boundary.
private struct DeviceDPIPanel: View {
    @Binding var config: DeviceDPIConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Levels (counts per inch)").font(.subheadline)
                Spacer()
                Button("Add Level") { config.levels.append(config.levels.last ?? 1600) }
            }
            ForEach(config.levels.indices, id: \.self) { index in
                HStack {
                    SafeIntField("Level \(index + 1)", value: levelBinding(index),
                                 in: 100...30000, width: 90)
                    Spacer()
                    Button(role: .destructive) {
                        config.levels.remove(at: index)
                    } label: { Image(systemName: "trash") }
                }
            }
            HStack(spacing: 12) {
                SafeIntField("Report ID", value: $config.reportID, in: 0...255)
                SafeIntField("Value byte", value: $config.valueByte, in: 0...63)
                SafeIntField("Value mask", value: $config.valueMask, in: 0...65535)
                SafeIntField("Report length", value: $config.reportLength, in: 1...64)
            }
            Text("Report layout is vendor-specific: consult your mouse's documentation before entering report values.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Index-safe binding: removing a level while its field is on screen must
    /// not read out of bounds.
    private func levelBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { config.levels.indices.contains(index) ? config.levels[index] : 1600 },
            set: { if config.levels.indices.contains(index) { config.levels[index] = $0 } })
    }
}
