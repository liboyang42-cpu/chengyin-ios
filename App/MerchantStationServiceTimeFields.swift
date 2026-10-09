import SwiftUI

@MainActor struct MerchantStationServiceTimeFields: View {
    struct Context: Hashable {
        let scope: UUID
        let activityID: Int
        let nodeID: Int
        let revision: Int
        let observedAt: Date
    }
    let context: Context
    let start: String
    let end: String
    let canEdit: Bool
    let apply: (MerchantStationServiceWindow, String, String) -> Bool
    @State private var editor: EditSession?
    private struct EditSession: Identifiable {
        let id = UUID()
        let context: Context
        let start: String, end: String
        let initial: MerchantStationServiceWindow
        let replacesUnrecognizedValue: Bool
    }
    var body: some View {
        Button("merchant.stationTime.choose", systemImage: "calendar.badge.clock") {
            guard canEdit else { return }
            let existing = MerchantStationServiceWindow(start: start, end: end)
            editor = .init(context: context, start: start, end: end,
                initial: existing ?? .init(day: MerchantStationServiceWindow.proposedDay(now: Date(), phoneTimeZone: .current)),
                replacesUnrecognizedValue: existing == nil && (!start.isEmpty || !end.isEmpty))
        }
        .disabled(!canEdit)
        .accessibilityIdentifier("merchant.stationTime.open")
        .sheet(item: $editor) { captured in
            MerchantStationServiceTimeSheet(initial: captured.initial,
                replacesUnrecognizedValue: captured.replacesUnrecognizedValue, cancel: { editor = nil }) { value in
                guard canEdit, context == captured.context, start == captured.start, end == captured.end,
                      apply(value, captured.start, captured.end) else { return false }
                editor = nil; return true
            }
        }
        .onChange(of: context) { _, _ in editor = nil }
        .onChange(of: canEdit) { _, current in if !current { editor = nil } }
        .onDisappear { editor = nil }
    }
}

@MainActor private struct MerchantStationServiceTimeSheet: View {
    @State private var draft: MerchantStationServiceWindow
    @State private var stale = false
    let replacesUnrecognizedValue: Bool
    let cancel: () -> Void
    let apply: (MerchantStationServiceWindow) -> Bool
    init(initial: MerchantStationServiceWindow, replacesUnrecognizedValue: Bool,
         cancel: @escaping () -> Void, apply: @escaping (MerchantStationServiceWindow) -> Bool) {
        _draft = State(initialValue: initial); self.replacesUnrecognizedValue = replacesUnrecognizedValue
        self.cancel = cancel; self.apply = apply
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("merchant.stationTime.draftOnly").font(.footnote).foregroundStyle(.secondary)
                if replacesUnrecognizedValue {
                    Text("merchant.stationTime.originalPreserved").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let date = draft.pickerDate {
                    DatePicker("merchant.stationTime.date", selection: Binding(get: { draft.pickerDate ?? date }, set: {
                        draft.selectPickerDate($0); stale = false
                    }), displayedComponents: .date)
                    .environment(\.calendar, MerchantStationServiceWindow.pickerCalendar)
                    .environment(\.timeZone, MerchantStationServiceWindow.pickerCalendar.timeZone)
                    .accessibilityIdentifier("merchant.stationTime.date")
                }
                timeSection("merchant.stationTime.start", start: true)
                timeSection("merchant.stationTime.end", start: false)
                if !draft.isValid { Text("merchant.stationTime.invalidOrder").foregroundStyle(.red) }
                if stale { Text("merchant.stationTime.changed").foregroundStyle(.secondary) }
                Text("merchant.content.civilTime").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("merchant.stationTime.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel", action: cancel).accessibilityIdentifier("merchant.stationTime.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("merchant.stationTime.apply") {
                        guard draft.isValid else { return }
                        stale = !apply(draft)
                    }.disabled(!draft.isValid).accessibilityIdentifier("merchant.stationTime.apply")
                }
            }
        }
    }
    private func timeSection(_ title: LocalizedStringKey, start: Bool) -> some View {
        Section(title) {
            component(start: start, hour: true)
            component(start: start, hour: false)
        }
    }
    private func component(start: Bool, hour: Bool) -> some View {
        let minutes = start ? draft.startMinutes : draft.endMinutes
        return Picker(LocalizedStringKey(hour ? "merchant.operations.hoursHour" : "merchant.operations.hoursMinute"), selection: Binding(get: {
            let value = start ? draft.startMinutes : draft.endMinutes
            return hour ? value / 60 : value % 60
        }, set: { value in
            let old = start ? draft.startMinutes : draft.endMinutes
            let updated = hour ? value * 60 + old % 60 : old / 60 * 60 + value
            if start { draft.startMinutes = updated } else { draft.endMinutes = updated }
            stale = false
        })) {
            ForEach(hour ? Array(0..<24) : MerchantStationServiceWindow.minuteChoices(preserving: minutes % 60), id: \.self) {
                Text(verbatim: String(format: "%02d", $0)).tag($0)
            }
        }.accessibilityIdentifier("merchant.stationTime." + (start ? "start." : "end.") + (hour ? "hour" : "minute"))
    }
}
