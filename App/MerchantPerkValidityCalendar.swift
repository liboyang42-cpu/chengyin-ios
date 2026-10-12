import SwiftUI

struct MerchantPerkValidityContext: Equatable {
    let session: CoopFlowSession
    let value: String
    let siblingFields: [String]
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session == rhs.session && Data(lhs.value.utf8) == Data(rhs.value.utf8) &&
        lhs.siblingFields.map { Data($0.utf8) } == rhs.siblingFields.map { Data($0.utf8) }
    }
}
@MainActor final class MerchantPerkValiditySession: ObservableObject, Identifiable {
    let id = UUID()
    let context: MerchantPerkValidityContext
    private let current: () -> MerchantPerkValidityContext?
    @Published private(set) var draft: MerchantPerkValidityDraft
    @Published private(set) var asksDiscard = false
    @Published private(set) var invalid = false
    private(set) var active = true
    init?(current: @escaping () -> MerchantPerkValidityContext?, now: Date = Date()) {
        guard let context = current() else { return nil }
        self.context = context; self.current = current; draft = .init(value: context.value, now: now)
    }
    var isCurrent: Bool { active && current() == context }
    func setEnabled(_ enabled: Bool, now: Date = Date()) {
        guard isCurrent, !asksDiscard else { return }; draft.setEnabled(enabled, now: now); invalid = false
    }
    func choose(_ date: Date) { guard isCurrent, !asksDiscard else { return }; draft.choose(date); invalid = false }
    func apply(now: Date = Date()) -> String? {
        guard isCurrent, !asksDiscard else { return nil }
        do { let value = try draft.value(now: now); cancel(); return value }
        catch { invalid = true; return nil }
    }
    func requestClose() -> Bool {
        guard isCurrent else { cancel(); return true }
        if draft.isDirty { asksDiscard = true; return false }
        cancel(); return true
    }
    func keepEditing() { guard isCurrent else { return }; asksDiscard = false }
    func cancel() { active = false; asksDiscard = false }
}

@MainActor struct MerchantPerkValidityEntry: View {
    @Binding var value: String
    let context: () -> MerchantPerkValidityContext?
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: MerchantPerkValiditySession?
    @State private var appliedValue: String?
    @State private var appliedContext: MerchantPerkValidityContext?
    private var presentation: Binding<MerchantPerkValiditySession?> {
        let shownID = session?.id
        return Binding(get: { session }, set: { next in
            guard session?.id == shownID else { return }
            if next == nil { session?.cancel() }; session = next
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard session == nil else { return }
                session = MerchantPerkValiditySession(current: context)
            } label: {
                HStack {
                    Text("coopflow.field.validEnd"); Spacer()
                    if value.isEmpty { Text("merchant.perkCalendar.none").foregroundStyle(.secondary) }
                    else { Text(verbatim: value) }
                    Image(systemName: "calendar")
                }
            }.disabled(context() == nil).accessibilityIdentifier("merchant.perkCalendar.open")
            if appliedValue == value, appliedContext == context(), appliedContext != nil {
                Text(LocalizedStringKey(value.isEmpty ? "merchant.perkCalendar.cleared" : "merchant.perkCalendar.applied")).font(.footnote)
                    .accessibilityIdentifier("merchant.perkCalendar.result")
            }
        }
        .sheet(item: presentation) { shown in
            MerchantPerkValiditySheet(session: shown, close: { if session?.id == shown.id { session = nil } }, apply: {
                guard session?.id == shown.id, let next = shown.apply() else { return }
                value = next; appliedValue = next; appliedContext = context(); session = nil
            })
        }
        .onChange(of: context()) { _, new in
            if let session, session.context != new { session.cancel(); self.session = nil; appliedValue = nil }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session?.cancel(); session = nil } }
        .onDisappear { if session == nil { appliedValue = nil; appliedContext = nil } }
    }
}
@MainActor private struct MerchantPerkValiditySheet: View {
    @ObservedObject var session: MerchantPerkValiditySession
    let close: () -> Void
    let apply: () -> Void
    @State private var now = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("merchant.perkCalendar.chinaTime").font(.footnote)
                    if session.draft.preservesExistingValue(now: now) {
                        Text("merchant.perkCalendar.existing").font(.footnote)
                        Text(verbatim: session.draft.original)
                    }
                    Toggle("merchant.perkCalendar.enabled", isOn: Binding(get: { session.draft.enabled }, set: { session.setEnabled($0) }))
                        .accessibilityIdentifier("merchant.perkCalendar.enabled")
                    if session.draft.enabled {
                        DatePicker("merchant.perkCalendar.day", selection: Binding(get: { max(session.draft.day, MerchantPerkValidityDraft.minimum(now: now)) }, set: session.choose),
                            in: MerchantPerkValidityDraft.minimum(now: now)..., displayedComponents: [.date])
                            .datePickerStyle(.graphical).accessibilityIdentifier("merchant.perkCalendar.day")
                    }
                    if session.invalid { Text("merchant.perkCalendar.invalid").foregroundStyle(.red) }
                    Text("merchant.perkCalendar.localOnly").font(.footnote)
                }.disabled(!session.isCurrent || session.asksDiscard)
            }
            .navigationTitle("merchant.perkCalendar.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { if session.requestClose() { close() } } }
                ToolbarItem(placement: .confirmationAction) { Button("merchant.perkCalendar.apply", action: apply).disabled(!session.isCurrent || session.asksDiscard) }
            }
        }
        .environment(\.timeZone, MerchantPerkValidityDraft.timeZone)
        .environment(\.calendar, MerchantPerkValidityDraft.calendar)
        .interactiveDismissDisabled(session.draft.isDirty)
        .confirmationDialog("merchant.perkCalendar.discardTitle", isPresented: Binding(get: { session.asksDiscard }, set: { if !$0 { session.keepEditing() } }), titleVisibility: .visible) {
            Button("merchant.perkCalendar.discard", role: .destructive) { session.cancel(); close() }
            Button("merchant.perkCalendar.keep", role: .cancel) { session.keepEditing() }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .accessibilityIdentifier("merchant.perkCalendar.sheet")
    }
}
