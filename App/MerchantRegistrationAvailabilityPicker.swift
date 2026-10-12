import SwiftUI

@MainActor struct MerchantRegistrationAvailabilityPicker: View {
    struct Context: Equatable {
        let scope: UUID
        let registrationID: Int
        let observedAt: Date
    }
    let context: Context
    let source: MerchantRegistrationAvailabilitySource
    let replacement: MerchantRegistrationAvailability?
    let canEdit: Bool
    @Binding var editor: Session?
    let apply: (MerchantRegistrationAvailability?) -> Bool
    @Environment(\.scenePhase) private var scenePhase
    struct Session: Identifiable {
        let id = UUID()
        let context: Context
        let source: MerchantRegistrationAvailabilitySource
        let replacement: MerchantRegistrationAvailability?
        let initial: MerchantRegistrationAvailability
    }
    var body: some View {
        Section("merchant.registrationAvailability.title") {
            MerchantRegistrationAvailabilitySourceRows(source: source)
            if let replacement {
                MerchantRegistrationAvailabilityValues(value: replacement)
                Text("merchant.registrationAvailability.pending").font(.footnote)
                Button("merchant.registrationAvailability.restore") { guard canEdit else { return }; _ = apply(nil) }
                    .disabled(!canEdit).accessibilityIdentifier("merchant.registrationAvailability.restore")
            }
            Button("merchant.registrationAvailability.choose", systemImage: "calendar.badge.clock") {
                guard canEdit, scenePhase == .active else { return }
                let today = MerchantStationServiceWindow.proposedDay(now: Date(), phoneTimeZone: .current)
                editor = .init(context: context, source: source, replacement: replacement,
                    initial: replacement ?? MerchantRegistrationAvailability(source: source)
                        ?? .init(startDay: today, endDay: today))
            }.disabled(!canEdit).accessibilityIdentifier("merchant.registrationAvailability.open")
            Text("merchant.registrationAvailability.preserve").font(.footnote).foregroundStyle(.secondary)
        }

    }
}

/// The sheet belongs to the stable editor page, never a virtualized Form section.
@MainActor struct MerchantRegistrationAvailabilityPresentation: ViewModifier {
    @Binding var editor: MerchantRegistrationAvailabilityPicker.Session?
    let context: MerchantRegistrationAvailabilityPicker.Context?
    let source: MerchantRegistrationAvailabilitySource?
    let replacement: MerchantRegistrationAvailability?
    let canEdit: Bool
    let apply: (MerchantRegistrationAvailability?) -> Bool
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
        .sheet(item: $editor) { captured in
            MerchantRegistrationAvailabilitySheet(initial: captured.initial,
                unrecognized: MerchantRegistrationAvailability(source: captured.source) == nil,
                cancel: { editor = nil }) { value in
                guard let source, canEdit, scenePhase == .active, context == captured.context,
                      source == captured.source, replacement == captured.replacement, value.isValid else { return false }
                // An unchanged representable source is an omission, not normalization.
                let next = value == MerchantRegistrationAvailability(source: source) ? nil : value
                guard next == replacement || apply(next) else { return false }
                editor = nil; return true
            }
        }
        .onChange(of: context) { _, _ in editor = nil }
        .onChange(of: source) { _, _ in editor = nil }
        .onChange(of: replacement) { _, _ in editor = nil }
        .onChange(of: canEdit) { _, value in if !value { editor = nil } }
        .onChange(of: scenePhase) { _, value in if value != .active { editor = nil } }

    }
}

private struct MerchantRegistrationAvailabilitySourceRows: View {
    let source: MerchantRegistrationAvailabilitySource
    var body: some View {
        row("merchant.registrationAvailability.sourceStart", source.start)
        row("merchant.registrationAvailability.sourceEnd", source.end)
        row("merchant.registrationAvailability.sourceDaily", source.daily)
    }
    private func row(_ key: String, _ value: MerchantContentValue) -> some View {
        LabeledContent(LocalizedStringKey(key)) {
            if let text = value.display, !text.isEmpty {
                Text(verbatim: text).textSelection(.enabled)
                    .accessibilityIdentifier(key + ".value")
            }
            else if value == .null || value.text == "" { Text("merchant.registrationAvailability.notProvided") }
            else { Text("merchant.registrationAvailability.unrecognized") }
        }.accessibilityElement(children: .contain)
    }
}
private struct MerchantRegistrationAvailabilityValues: View {
    let value: MerchantRegistrationAvailability
    var body: some View {
        LabeledContent("merchant.registrationAvailability.newStart", value: value.startDay)
            .accessibilityIdentifier("merchant.registrationAvailability.newStart")
        LabeledContent("merchant.registrationAvailability.newEnd", value: value.endDay)
        LabeledContent("merchant.registrationAvailability.newDaily", value: value.dailyTime)
            .accessibilityIdentifier("merchant.registrationAvailability.newDaily")
    }
}
struct MerchantRegistrationAvailabilityReview: View {
    let source: MerchantRegistrationAvailabilitySource
    let replacement: MerchantRegistrationAvailability
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("merchant.registrationAvailability.reviewTitle").font(.headline)
            MerchantRegistrationAvailabilitySourceRows(source: source)
            MerchantRegistrationAvailabilityValues(value: replacement)
            Text("merchant.registrationAvailability.reviewHint").font(.footnote)
        }.accessibilityIdentifier("merchant.registrationAvailability.review")
    }
}

@MainActor private struct MerchantRegistrationAvailabilitySheet: View {
    @State private var draft: MerchantRegistrationAvailability
    @State private var stale = false
    let unrecognized: Bool
    let cancel: () -> Void
    let apply: (MerchantRegistrationAvailability) -> Bool
    init(initial: MerchantRegistrationAvailability, unrecognized: Bool, cancel: @escaping () -> Void,
         apply: @escaping (MerchantRegistrationAvailability) -> Bool) {
        _draft = State(initialValue: initial); self.unrecognized = unrecognized; self.cancel = cancel; self.apply = apply
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("merchant.registrationAvailability.localDraft").font(.footnote)
                if unrecognized { Text("merchant.registrationAvailability.proposal").font(.footnote).foregroundStyle(.secondary) }
                Section("merchant.registrationAvailability.dateRange") { day(start: true); day(start: false) }
                Section("merchant.registrationAvailability.dailyStart") { clock(start: true, hour: true); clock(start: true, hour: false) }
                Section("merchant.registrationAvailability.dailyEnd") { clock(start: false, hour: true); clock(start: false, hour: false) }
                Text("merchant.registrationAvailability.civilHint").font(.footnote)
                if !draft.isValid { Text("merchant.registrationAvailability.invalid").foregroundStyle(.red) }
                if stale { Text("merchant.registrationAvailability.stale").foregroundStyle(.secondary) }
            }
            .appNavigationTitle("merchant.registrationAvailability.choose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel", action: cancel).accessibilityIdentifier("merchant.registrationAvailability.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("merchant.registrationAvailability.apply") { guard draft.isValid else { return }; stale = !apply(draft) }
                        .disabled(!draft.isValid).accessibilityIdentifier("merchant.registrationAvailability.apply")
                }
            }
        }
    }
    @ViewBuilder private func day(start: Bool) -> some View {
        if let original = draft.pickerDate(start: start) {
            DatePicker(LocalizedStringKey(start ? "merchant.registrationAvailability.newStart" : "merchant.registrationAvailability.newEnd"),
                selection: Binding(get: { draft.pickerDate(start: start) ?? original }, set: { draft.selectDay($0, start: start); stale = false }), displayedComponents: .date)
                .environment(\.calendar, MerchantStationServiceWindow.pickerCalendar)
                .environment(\.timeZone, MerchantStationServiceWindow.pickerCalendar.timeZone)
                .accessibilityIdentifier("merchant.registrationAvailability." + (start ? "startDay" : "endDay"))
        }
    }
    private func clock(start: Bool, hour: Bool) -> some View {
        let total = start ? draft.startMinutes : draft.endMinutes
        return Picker(LocalizedStringKey(hour ? "merchant.operations.hoursHour" : "merchant.operations.hoursMinute"), selection: Binding(get: {
            let value = start ? draft.startMinutes : draft.endMinutes; return hour ? value / 60 : value % 60
        }, set: { value in
            let old = start ? draft.startMinutes : draft.endMinutes
            let next = hour ? value * 60 + old % 60 : old / 60 * 60 + value
            if start { draft.startMinutes = next } else { draft.endMinutes = next }; stale = false
        })) {
            ForEach(hour ? Array(0..<24) : MerchantStationServiceWindow.minuteChoices(preserving: total % 60), id: \.self) { value in
                Text(verbatim: String(format: "%02d", value)).tag(value)
            }
        }.accessibilityIdentifier("merchant.registrationAvailability." + (start ? "start" : "end") + (hour ? "Hour" : "Minute"))
    }
}
