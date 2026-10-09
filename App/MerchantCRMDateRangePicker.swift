import SwiftUI

@MainActor struct MerchantCRMDateRangePicker: View {
    struct Context: Equatable {
        let scope: MerchantBusinessScope
        let authorization: UUID?
        let merchantID: Int
        init?(scope: MerchantBusinessScope?, authorization: UUID?, merchantID: Int?) {
            guard let scope, let merchantID, merchantID > 0 else { return nil }
            self.scope = scope; self.authorization = authorization; self.merchantID = merchantID
        }
    }
    let context: Context?
    let start: String
    let end: String
    let apply: (MerchantCRMDateRange) -> Void
    @State private var editor: Session?
    private struct Session: Identifiable {
        let id = UUID()
        let context: Context
        let original: MerchantCRMDateRange
    }
    var body: some View {
        Button("merchant.crmDate.choose", systemImage: "calendar") {
            guard let context else { return }
            editor = .init(context: context, original: .init(start: start, end: end))
        }.disabled(context == nil).accessibilityIdentifier("merchant.crmDate.open")
        .sheet(item: $editor) { captured in
            MerchantCRMDateRangeSheet(initial: captured.original, cancel: { editor = nil }) { value in
                guard context == captured.context, start == captured.original.start, end == captured.original.end,
                      value.isValid else { return false }
                if value != captured.original { apply(value) }
                editor = nil; return true
            }
        }
        .onChange(of: context) { _, _ in editor = nil }
        .onChange(of: start) { _, _ in editor = nil }
        .onChange(of: end) { _, _ in editor = nil }
        .onDisappear { editor = nil }
    }
}

@MainActor private struct MerchantCRMDateRangeSheet: View {
    @State private var draft: MerchantCRMDateRange
    @State private var stale = false
    let cancel: () -> Void
    let apply: (MerchantCRMDateRange) -> Bool
    init(initial: MerchantCRMDateRange, cancel: @escaping () -> Void, apply: @escaping (MerchantCRMDateRange) -> Bool) {
        _draft = State(initialValue: initial); self.cancel = cancel; self.apply = apply
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("merchant.crmDate.localOnly").font(.footnote); Text("merchant.crmDate.rangeHint").font(.footnote) }
                dateField("merchant.business.sourceStart", .start)
                dateField("merchant.business.sourceEnd", .end)
                if !draft.isValid { Text("merchant.crmDate.invalid").foregroundStyle(.red) }
                if stale { Text("merchant.crmDate.stale").foregroundStyle(.secondary) }
            }
            .navigationTitle("merchant.crmDate.choose")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: cancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("merchant.crmDate.apply") { stale = !apply(draft) }.disabled(!draft.isValid)
                        .accessibilityIdentifier("merchant.crmDate.apply")
                }
            }
        }
    }
    private func dateField(_ key: String, _ field: MerchantCRMDateRange.Field) -> some View {
        Section(LocalizedStringKey(key)) {
            Toggle("merchant.crmDate.enabled", isOn: Binding(get: { draft.hasValue(field) }, set: { enabled in
                if enabled { draft.select(field, day: MerchantStationServiceWindow.proposedDay(now: Date(), phoneTimeZone: .current)) }
                else { draft.clear(field) }
                stale = false
            }))
            if let date = draft.pickerDate(field) {
                DatePicker(LocalizedStringKey(key), selection: Binding(get: { draft.pickerDate(field) ?? date }, set: {
                    draft.select(field, pickerDate: $0); stale = false
                }), displayedComponents: .date)
                .environment(\.calendar, MerchantStationServiceWindow.pickerCalendar)
                .environment(\.timeZone, MerchantStationServiceWindow.pickerCalendar.timeZone)
            } else if draft.hasValue(field) {
                Text(verbatim: draft.text(field))
                Text("merchant.crmDate.unrecognized").font(.footnote).foregroundStyle(.secondary)
                Button("merchant.crmDate.replace") {
                    draft.select(field, day: MerchantStationServiceWindow.proposedDay(now: Date(), phoneTimeZone: .current)); stale = false
                }
            }
            if draft.hasValue(field) {
                Button("merchant.crmDate.clear", role: .destructive) { draft.clear(field); stale = false }
            }
        }
    }
}
