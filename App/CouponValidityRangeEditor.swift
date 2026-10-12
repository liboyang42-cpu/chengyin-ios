import SwiftUI

struct CouponValidityRangeContext: Equatable {
    let coordinatorID: ObjectIdentifier
    let session: CouponManagementSession
    let draft: CouponManagementDraft
    let sourceRevision: Int
    init(coordinatorID: ObjectIdentifier, session: CouponManagementSession, draft: CouponManagementDraft, sourceRevision: Int = 0) {
        self.coordinatorID = coordinatorID; self.session = session; self.draft = draft; self.sourceRevision = sourceRevision
    }
    func matches(_ other: Self) -> Bool {
        self == other && session.namespace.utf8.elementsEqual(other.session.namespace.utf8)
            && session.authorizationRevision.utf8.elementsEqual(other.session.authorizationRevision.utf8)
    }
}

@MainActor final class CouponValidityRangeEditorModel: ObservableObject, Identifiable {
    let id = UUID()
    let pickerFallback: Date
    private let baseline: CouponValidityRangeContext
    private let current: () -> CouponValidityRangeContext?
    private let apply: (CouponValidityRangeContext, CouponManagementDraft) -> Bool
    @Published private(set) var selection: CouponValidityRangeDraft
    @Published private(set) var active = true
    @Published private(set) var issue: String?
    init?(now: Date = Date(), current: @escaping () -> CouponValidityRangeContext?,
          apply: @escaping (CouponValidityRangeContext, CouponManagementDraft) -> Bool) {
        guard let baseline = current() else { return nil }
        self.baseline = baseline; self.current = current; self.apply = apply
        selection = .init(baseline.draft); pickerFallback = now
    }
    private var currentSnapshot: CouponValidityRangeContext? {
        guard active, let value = current(), baseline.matches(value) else { return nil }
        return value
    }
    var canApply: Bool { currentSnapshot != nil && selection.blocker == nil }
    func setStart(_ value: Date?) { guard currentSnapshot != nil else { invalidate(); return }; selection.startTime = value; issue = nil }
    func setEnd(_ value: Date?) { guard currentSnapshot != nil else { invalidate(); return }; selection.endTime = value; issue = nil }
    func cancel() { active = false }
    private func invalidate() { active = false; issue = "couponManagement.changed" }
    @discardableResult func confirm() -> Bool {
        guard let snapshot = currentSnapshot else { invalidate(); return false }
        guard let value = try? selection.applying(to: snapshot.draft) else { issue = selection.blocker; return false }
        active = false // Consume this exact local sheet before handing changes back to the source form.
        guard apply(snapshot, value) else { issue = "couponManagement.changed"; return false }
        return true
    }
    static func make(screen: CouponManagementScreenModel) -> CouponValidityRangeEditorModel? {
        let current: () -> CouponValidityRangeContext? = { [weak screen] in
            guard let screen, !screen.working else { return nil }
            // The current principal may change before the parent task synchronizes its draft.
            screen.core.synchronize()
            guard !screen.core.busy, let session = screen.core.session else { return nil }
            return .init(coordinatorID: ObjectIdentifier(screen.core), session: session, draft: screen.core.draft,
                         sourceRevision: screen.revision)
        }
        return .init(current: current, apply: { [weak screen] expected, value in
            guard let screen, let actual = current(), expected.matches(actual) else { return false }
            screen.update(value) // Existing local change() invalidates any prior publish review.
            return screen.core.draft == value && screen.core.session == expected.session
        })
    }
}

@MainActor struct CouponValidityRangeEditor: View {
    @ObservedObject var model: CouponValidityRangeEditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private func date(_ start: Bool) -> Binding<Date> {
        Binding(get: { (start ? model.selection.startTime : model.selection.endTime) ?? model.pickerFallback },
                set: { if start { model.setStart($0) } else { model.setEnd($0) } })
    }
    var body: some View {
        Form {
            Section {
                Text("couponManagement.chinaTime").font(.footnote)
                Text("couponManagement.range.localHint").font(.footnote).foregroundStyle(.secondary)
            }
            Section("couponManagement.dates") {
                Toggle("couponManagement.setStart", isOn: Binding(get: { model.selection.startTime != nil },
                    set: { model.setStart($0 ? Date() : nil) })).accessibilityIdentifier("couponManagement.range.setStart")
                if model.selection.startTime != nil {
                    DatePicker("couponManagement.start", selection: date(true), displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("couponManagement.range.start")
                }
                Toggle("couponManagement.setEnd", isOn: Binding(get: { model.selection.endTime != nil },
                    set: { model.setEnd($0 ? Date() : nil) })).accessibilityIdentifier("couponManagement.range.setEnd")
                if model.selection.endTime != nil {
                    DatePicker("couponManagement.end", selection: date(false), displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("couponManagement.range.end")
                }
            }.disabled(!model.active)
            if let issue = model.issue ?? model.selection.blocker {
                Text(LocalizedStringKey(issue)).foregroundStyle(.secondary).accessibilityIdentifier("couponManagement.range.issue")
            }
        }
        .environment(\.timeZone, CouponValidityTime.timeZone)
        .environment(\.calendar, CouponValidityTime.calendar)
        .navigationTitle("couponManagement.range.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("couponManagement.cancel") { model.cancel(); dismiss() }.accessibilityIdentifier("couponManagement.range.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("couponManagement.range.apply") { if model.confirm() { dismiss() } }
                    .disabled(!model.canApply).accessibilityIdentifier("couponManagement.range.apply")
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.cancel(); dismiss() } }
        .onDisappear { model.cancel() }
    }
}
