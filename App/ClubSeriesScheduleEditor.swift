import SwiftUI

/// Captures the ordinary form's actual reader and identity. A cancelled/replaced sheet cannot apply later.
@MainActor struct ClubSeriesScheduleSession: Identifiable {
    let id = UUID()
    let initial: ClubSeriesScheduleDraft
    let operation: ClubGovernanceMutation
    let context: ClubGovernanceReadContext
    let requestID: String
    let namespace: String
    init?(form: ClubGovernanceFormDraft, identity: ClubReadIdentity?, access: any ClubGovernanceAccess, now: Date) {
        guard [.createSeries, .updateSeries].contains(form.operation), (identity?.accountID ?? 0) > 0,
              access.isConfigured, identity == access.identity else { return nil }
        initial = .init(form: form, now: now); operation = form.operation; requestID = form.requestID
        namespace = access.storageNamespace
        context = Self.context(form: form, identity: identity, access: access)
    }
    func isCurrent(activeID: UUID?, form: ClubGovernanceFormDraft, identity: ClubReadIdentity?, access: any ClubGovernanceAccess) -> Bool {
        activeID == id && operation == form.operation && requestID == form.requestID && access.isConfigured &&
        identity == access.identity && namespace == access.storageNamespace && context == Self.context(form: form, identity: identity, access: access)
    }
    private static func context(form: ClubGovernanceFormDraft, identity: ClubReadIdentity?, access: any ClubGovernanceAccess) -> ClubGovernanceReadContext {
        .init(operation: form.operation.reviewRead, scope: form.scope, identity: identity, viewerRevision: 0,
              authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
    }
}

@MainActor struct ClubSeriesScheduleEditor: View {
    let session: ClubSeriesScheduleSession
    let canApply: () -> Bool
    let apply: (ClubSeriesScheduleDraft) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: ClubSeriesScheduleDraft
    @State private var stale = false
    init(session: ClubSeriesScheduleSession, canApply: @escaping () -> Bool, apply: @escaping (ClubSeriesScheduleDraft) -> Bool) {
        self.session = session; self.canApply = canApply; self.apply = apply
        _schedule = State(initialValue: session.initial)
    }
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { clock in
            Form {
                Section {
                    Text("club.schedule.shanghai")
                    if session.operation == .updateSeries { Text("club.schedule.newDatesOnly") }
                }
                Section("club.gov.field.recurrenceType") {
                    Picker("club.gov.field.recurrenceType", selection: $schedule.recurrence) {
                        ForEach(ClubSeriesScheduleDraft.Recurrence.allCases, id: \.rawValue) { kind in
                            Text(LocalizedStringKey("club.gov.choice." + kind.rawValue)).tag(kind.rawValue)
                        }
                    }.accessibilityIdentifier("club.schedule.recurrence")
                    if schedule.recurrence != ClubSeriesScheduleDraft.Recurrence.custom.rawValue {
                        DatePicker("club.gov.field.startDate", selection: dayBinding(now: clock.date), in: minimumDay(clock.date)..., displayedComponents: .date)
                            .accessibilityIdentifier("club.schedule.startDate")
                    }
                    if schedule.recurrence == ClubSeriesScheduleDraft.Recurrence.weekly.rawValue {
                        Stepper(value: $schedule.occurrenceCount, in: 1...64) {
                            LabeledContent("club.gov.field.occurrenceCount", value: String(schedule.occurrenceCount))
                        }.accessibilityIdentifier("club.schedule.count")
                    }
                    if schedule.recurrence == ClubSeriesScheduleDraft.Recurrence.custom.rawValue {
                        ForEach(schedule.customDates) { item in
                            HStack {
                                DatePicker("club.gov.field.startDate", selection: customBinding(item.id, now: clock.date), in: minimumDay(clock.date)..., displayedComponents: .date)
                                    .accessibilityIdentifier("club.schedule.customDate." + item.id.uuidString)
                                Button(role: .destructive) { schedule.removeDate(id: item.id) } label: { Image(systemName: "minus.circle"); Text("club.schedule.remove") }
                                    .disabled(schedule.customDates.count <= 1).buttonStyle(.borderless)
                            }
                        }
                        Button("club.schedule.add") { schedule.addDate() }
                            .disabled(schedule.customDates.count >= 64).accessibilityIdentifier("club.schedule.add")
                    }
                    DatePicker("club.gov.field.startTime", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("club.schedule.startTime")
                }
                Section("club.schedule.preview") {
                    Text("club.schedule.previewNote")
                    ForEach(Array(schedule.requestedDates.enumerated()), id: \.offset) { _, day in
                        Text(verbatim: day + " " + schedule.startTime).accessibilityIdentifier("club.schedule.requestedDate")
                    }
                }
                if let issue = schedule.issue(now: clock.date) {
                    Section { Text(LocalizedStringKey(issue.localizationKey)).accessibilityIdentifier("club.schedule.error") }
                }
                if stale || !canApply() { Section { Text("club.schedule.expired").accessibilityIdentifier("club.schedule.expired") } }
                Section {
                    Button("club.schedule.reset") { schedule = session.initial; stale = false }
                        .accessibilityIdentifier("club.schedule.reset")
                }
            }
            .environment(\.calendar, ClubSeriesScheduleDraft.calendar)
            .environment(\.timeZone, ClubSeriesScheduleDraft.timeZone)
            .navigationTitle("club.schedule.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { dismiss() }.accessibilityIdentifier("club.schedule.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("club.schedule.apply") {
                        guard canApply(), schedule.issue(now: Date()) == nil else { stale = !canApply(); return }
                        if apply(schedule) { dismiss() } else { stale = true }
                    }.disabled(!canApply() || schedule.issue(now: clock.date) != nil).accessibilityIdentifier("club.schedule.apply")
                }
            }
        }
    }
    private func minimumDay(_ now: Date) -> Date { ClubSeriesScheduleDraft.calendar.startOfDay(for: now) }
    private func dayBinding(now: Date) -> Binding<Date> {
        .init(get: { ClubSeriesScheduleDraft.parseDay(schedule.startDate) ?? now }, set: { schedule.startDate = ClubSeriesScheduleDraft.day($0) })
    }
    private func customBinding(_ id: UUID, now: Date) -> Binding<Date> {
        .init(get: { ClubSeriesScheduleDraft.parseDay(schedule.customDates.first(where: { $0.id == id })?.day ?? "") ?? now }, set: { value in
            guard let index = schedule.customDates.firstIndex(where: { $0.id == id }) else { return }
            schedule.customDates[index].day = ClubSeriesScheduleDraft.day(value)
        })
    }
    private var timeBinding: Binding<Date> {
        .init(get: { ClubSeriesScheduleDraft.parseTime(schedule.startTime) ?? ClubSeriesScheduleDraft.parseTime("09:00")! }, set: { schedule.startTime = ClubSeriesScheduleDraft.time($0) })
    }
}

/// Owns only the return from an acknowledged edit of an existing series.
/// The coordinator retains every write lock; a return ticket authorizes one read.
@MainActor final class ClubSeriesUpdateReturn: ObservableObject {
    struct Source: Equatable {
        let context: ClubGovernanceReadContext
        let snapshot: ClubGovernanceSnapshot
        let generation: UInt64
        let namespace: String
        let realm: String
        @MainActor init?(context: ClubGovernanceReadContext, snapshot: ClubGovernanceSnapshot,
              generation: UInt64, access: any ClubGovernanceAccess) {
            guard context.operation == .seriesDetail, context.accepts(snapshot),
                  context.identity?.isSignedIn == true, context.identity == access.identity,
                  context.authorizationGeneration == access.authorizationGeneration,
                  context.accessIdentity == ObjectIdentifier(access), access.isConfigured,
                  (context.scope.clubID ?? 0) > 0, (context.scope.seriesID ?? 0) > 0,
                  (context.scope.topicID ?? 0) > 0,
                  snapshot.value["id"].int == context.scope.seriesID,
                  snapshot.value["topicId"].int == context.scope.topicID,
                  let version = snapshot.value["version"].int, version >= 0,
                  snapshot.permissions?.allows(ClubGovernanceRead.seriesDetail.permission, scope: context.scope) == true else { return nil }
            self.context = context; self.snapshot = snapshot; self.generation = generation
            namespace = access.storageNamespace; realm = access.journalRealm
        }
    }
    struct Item: Identifiable {
        let route: ClubGovernanceFormRoute
        let source: Source
        var id: UUID { route.id }
    }
    struct Callbacks {
        let begin: (ClubGovernanceReview) -> Bool
        let acknowledged: (ClubGovernanceReview, ClubGovernanceValue) -> Void
    }
    @Published private(set) var item: Item?
    @Published private(set) var isPresented = false
    private var submissionID: UUID?
    private var acknowledgedID: UUID?
    private var didDismiss = false

    func open(_ source: Source?, visible: Bool, active: Bool) {
        guard item == nil, visible, active, let source else { return }
        item = Item(route: .init(operation: .updateSeries, scope: source.context.scope,
                                 seed: source.snapshot.value.object ?? [:]), source: source)
        isPresented = true; submissionID = nil; acknowledgedID = nil; didDismiss = false
    }
    func current(_ expected: Item, source: Source?, active: Bool) -> Bool {
        active && item?.id == expected.id && expected.source == source
    }
    func binding(_ expected: Item, source: @escaping () -> Source?, active: @escaping () -> Bool) -> Binding<Bool> {
        Binding(get: { self.isPresented && self.current(expected, source: source(), active: active()) }, set: { shown in
            guard !shown, self.current(expected, source: source(), active: active()) else { return }
            self.isPresented = false
        })
    }
    func begin(_ review: ClubGovernanceReview, state: ClubGovernanceWriteState, item expected: Item, source: Source?, active: Bool) -> Bool {
        guard isPresented, current(expected, source: source, active: active),
              state == .reviewing, acknowledgedID == nil,
              review.command.operation == .updateSeries, review.command.scope == expected.source.context.scope,
              review.identity == expected.source.context.identity,
              review.authorizationGeneration == expected.source.context.authorizationGeneration,
              review.storageNamespace == expected.source.namespace, review.journalRealm == expected.source.realm,
              review.snapshot == expected.source.snapshot,
              review.command.fields["expectedVersion"] == expected.source.snapshot.value["version"] else { return false }
        submissionID = review.id
        return true
    }
    func acknowledge(_ review: ClubGovernanceReview, receipt: ClubGovernanceValue,
                     state: ClubGovernanceWriteState, item expected: Item, source: Source?, active: Bool) {
        guard isPresented, current(expected, source: source, active: active),
              submissionID == review.id, acknowledgedID == nil, state == .acknowledged,
              receipt["id"].int == expected.source.context.scope.seriesID else { return }
        acknowledgedID = review.id; isPresented = false
    }
    @discardableResult func dismissed(_ expected: Item, source: Source?, active: Bool) -> Bool {
        guard current(expected, source: source, active: active), !isPresented else { return false }
        if acknowledgedID != nil { didDismiss = true }
        else { retire() }
        return true
    }
    func consume(source: Source?, visible: Bool, active: Bool) -> Source? {
        guard visible, active, !isPresented, didDismiss, acknowledgedID != nil,
              let item, current(item, source: source, active: active) else { return nil }
        let result = item.source
        retire()
        return result
    }
    func invalidateUnlessCurrent(source: Source?, active: Bool) {
        if let item, !current(item, source: source, active: active) { retire() }
    }
    func retire() {
        isPresented = false; item = nil; submissionID = nil; acknowledgedID = nil; didDismiss = false
    }
}

/// The concrete route owns presentation outside the lazy detail rows.
@MainActor struct ClubSeriesUpdatePresentationOwner: View {
    let item: ClubSeriesUpdateReturn.Item
    @ObservedObject var owner: ClubSeriesUpdateReturn
    let source: () -> ClubSeriesUpdateReturn.Source?
    let active: () -> Bool
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    let didDismiss: () -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: owner.binding(item, source: source, active: active), onDismiss: {
                if owner.dismissed(item, source: source(), active: active()) { didDismiss() }
            }) {
                NavigationStack {
                    ClubGovernanceCommandForm(route: item.route, identity: item.source.context.identity,
                        access: access, coordinator: coordinator, validateTarget: {
                            guard owner.isPresented, owner.current(item, source: source(), active: active()) else {
                                throw ClubGovernanceFailure.staleReview
                            }
                        }, seriesUpdateReturn: .init(begin: { review in
                            owner.begin(review, state: coordinator.state, item: item, source: source(), active: active())
                        }, acknowledged: { review, receipt in
                            owner.acknowledge(review, receipt: receipt, state: coordinator.state,
                                item: item, source: source(), active: active())
                        }))
                }
            }
    }
}
