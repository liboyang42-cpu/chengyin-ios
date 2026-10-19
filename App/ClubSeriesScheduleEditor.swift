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
                    if session.operation == .updateSeries {
                        Text("club.schedule.editTime", tableName: "ClubSeriesSchedule")
                        Text("club.schedule.futureOnly", tableName: "ClubSeriesSchedule")
                    }
                }
                Section("club.gov.field.recurrenceType") {
                    Picker("club.gov.field.recurrenceType", selection: $schedule.recurrence) {
                        ForEach(ClubSeriesScheduleDraft.Recurrence.allCases, id: \.rawValue) { kind in
                            Text(LocalizedStringKey("club.gov.choice." + kind.rawValue)).tag(kind.rawValue)
                        }
                    }.accessibilityIdentifier("club.schedule.recurrence")
                    if schedule.recurrence != ClubSeriesScheduleDraft.Recurrence.custom.rawValue {
                        DatePicker(selection: dayBinding(now: clock.date), in: minimumDay(clock.date)..., displayedComponents: .date) {
                            Text("clubOpsEvent.field.firstDate", tableName: "ClubOpsEvent")
                        }
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
                                DatePicker(selection: customBinding(item.id, now: clock.date), in: minimumDay(clock.date)..., displayedComponents: .date) {
                                    Text("clubOpsEvent.field.date", tableName: "ClubOpsEvent")
                                }
                                    .accessibilityIdentifier("club.schedule.customDate." + item.id.uuidString)
                                Button(role: .destructive) { schedule.removeDate(id: item.id) } label: { Image(systemName: "minus.circle"); Text("club.schedule.remove") }
                                    .disabled(schedule.customDates.count <= 1).buttonStyle(.borderless)
                            }
                        }
                        Button("club.schedule.add") { schedule.addDate(now: clock.date) }
                            .disabled(schedule.customDates.count >= 64).accessibilityIdentifier("club.schedule.add")
                    }
                    if ClubSeriesScheduleDraft.parseTime(schedule.startTime) == nil {
                        // No saved common time: require explicit input, including an intentional 09:00.
                        VStack(alignment: .leading) {
                            Text("club.gov.field.startTime")
                            TextField("HH:mm", text: $schedule.startTime)
                                .keyboardType(.numbersAndPunctuation)
                                .accessibilityLabel(Text("club.gov.field.startTime"))
                                .accessibilityIdentifier("club.schedule.startTime.unknown")
                        }
                    } else {
                        DatePicker("club.gov.field.startTime", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("club.schedule.startTime")
                    }
                }
                Section("club.schedule.preview") {
                    Text("club.schedule.previewNote")
                    if session.initial.preservesReadbackAsCustomDates && schedule.recurrence == ClubSeriesScheduleDraft.Recurrence.custom.rawValue {
                        Text("club.schedule.preserveRemaining", tableName: "ClubSeriesSchedule")
                            .accessibilityIdentifier("club.schedule.preserveRemaining")
                    }
                    if session.operation == .updateSeries && schedule.recurrence == ClubSeriesScheduleDraft.Recurrence.custom.rawValue {
                        Text("club.schedule.customConversion", tableName: "ClubSeriesSchedule")
                            .accessibilityIdentifier("club.schedule.customConversion")
                    }
                    ForEach(Array(schedule.requestedDates.enumerated()), id: \.offset) { _, day in
                        Text(verbatim: day + " " + schedule.startTime).accessibilityIdentifier("club.schedule.requestedDate")
                    }
                }
                if let issue = schedule.issue(now: clock.date) {
                    Section { ClubSeriesScheduleIssueLabel(issue: issue).accessibilityIdentifier("club.schedule.error") }
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
    private func minimumDay(_ now: Date) -> Date { schedule.minimumDate(now: now) }
    private func dayBinding(now: Date) -> Binding<Date> {
        .init(get: { ClubSeriesScheduleDraft.parseDay(schedule.startDate) ?? minimumDay(now) }, set: { schedule.startDate = ClubSeriesScheduleDraft.day($0) })
    }
    private func customBinding(_ id: UUID, now: Date) -> Binding<Date> {
        .init(get: { ClubSeriesScheduleDraft.parseDay(schedule.customDates.first(where: { $0.id == id })?.day ?? "") ?? minimumDay(now) }, set: { value in
            guard let index = schedule.customDates.firstIndex(where: { $0.id == id }) else { return }
            schedule.customDates[index].day = ClubSeriesScheduleDraft.day(value)
        })
    }
    private var timeBinding: Binding<Date> {
        .init(get: { ClubSeriesScheduleDraft.parseTime(schedule.startTime) ?? ClubSeriesScheduleDraft.parseTime("09:00")! }, set: { schedule.startTime = ClubSeriesScheduleDraft.time($0) })
    }
}

struct ClubSeriesScheduleIssueLabel: View {
    let issue: ClubSeriesScheduleDraft.Issue
    var body: some View {
        if issue == .futureOnly { Text("club.schedule.futureOnly", tableName: "ClubSeriesSchedule") }
        else { Text(LocalizedStringKey(issue.localizationKey)) }
    }
}

/// An acknowledged cancellation permits a readback, never a repeated command.
@MainActor final class ClubOccurrenceCancellationReturn: ObservableObject {
    struct Source: Equatable {
        let context: ClubGovernanceReadContext
        let snapshot: ClubGovernanceSnapshot
        let generation: UInt64
        let namespace: String
        let realm: String
        @MainActor init?(context: ClubGovernanceReadContext, snapshot: ClubGovernanceSnapshot,
                         generation: UInt64, access: any ClubGovernanceAccess) {
            guard context.operation == .occurrenceStatus, context.accepts(snapshot),
                  context.identity?.isSignedIn == true, context.identity == access.identity,
                  context.authorizationGeneration == access.authorizationGeneration,
                  context.accessIdentity == ObjectIdentifier(access), access.isConfigured,
                  (context.scope.clubID ?? 0) > 0, (context.scope.activityID ?? 0) > 0,
                  snapshot.value["activityId"].int == context.scope.activityID,
                  snapshot.value["occurrenceStatus"] == .string("ACTIVE"),
                  snapshot.value["activityCancelled"] == .bool(false), snapshot.value["publishStatus"] == .integer(1),
                  snapshot.permissions?.allows(ClubGovernanceRead.occurrenceStatus.permission, scope: context.scope) == true else { return nil }
            self.context = context; self.snapshot = snapshot; self.generation = generation
            namespace = access.storageNamespace; realm = access.journalRealm
        }
        @MainActor func live(context: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> Bool {
            self.context == context && access.isConfigured && context.identity == access.identity &&
            context.authorizationGeneration == access.authorizationGeneration && context.accessIdentity == ObjectIdentifier(access) &&
            namespace == access.storageNamespace && realm == access.journalRealm
        }
    }
    struct Item: Identifiable {
        let route: ClubGovernanceFormRoute
        let source: Source
        var id: UUID { route.id }
    }
    struct Readback: Identifiable {
        let id = UUID()
        let source: Source
        let reviewID: UUID
        let receipt: ClubGovernanceValue
    }
    struct Callbacks {
        let begin: (ClubGovernanceReview) -> Bool
        let acknowledged: (ClubGovernanceReview, ClubGovernanceValue) -> Void
    }
    struct ReadTrigger: Equatable {
        let context: ClubGovernanceReadContext
        let visible: Bool
        let active: Bool
    }
    @Published private(set) var item: Item?
    @Published private(set) var isPresented = false
    @Published private(set) var readback: Readback?
    @Published private(set) var confirmed = false
    private var submissionID: UUID?
    private var acknowledged: Readback?
    private var didDismiss = false
    func open(_ source: Source?, visible: Bool, active: Bool) {
        guard item == nil, readback == nil, visible, active, let source else { return }
        item = .init(route: .init(operation: .cancelOccurrence, scope: source.context.scope), source: source)
        isPresented = true; submissionID = nil; acknowledged = nil; didDismiss = false
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
    func begin(_ review: ClubGovernanceReview, state: ClubGovernanceWriteState,
               item expected: Item, source: Source?, active: Bool) -> Bool {
        guard isPresented, current(expected, source: source, active: active), state == .reviewing,
              acknowledged == nil, review.command.operation == .cancelOccurrence,
              review.command.scope == expected.source.context.scope,
              review.identity == expected.source.context.identity,
              review.authorizationGeneration == expected.source.context.authorizationGeneration,
              review.storageNamespace == expected.source.namespace, review.journalRealm == expected.source.realm,
              review.snapshot == expected.source.snapshot else { return false }
        submissionID = review.id; return true
    }
    func acknowledge(_ review: ClubGovernanceReview, value: ClubGovernanceValue, state: ClubGovernanceWriteState,
                     item expected: Item, source: Source?, active: Bool) {
        guard isPresented, current(expected, source: source, active: active), state == .acknowledged,
              submissionID == review.id, acknowledged == nil,
              value["activityId"].int == expected.source.context.scope.activityID,
              value["refundStatus"].string != nil else { return }
        acknowledged = .init(source: expected.source, reviewID: review.id, receipt: value)
        isPresented = false
    }
    @discardableResult func dismissed(_ expected: Item, source: Source?, active: Bool) -> Bool {
        guard current(expected, source: source, active: active), !isPresented else { return false }
        if acknowledged != nil { didDismiss = true } else { retireForm() }
        return true
    }
    func consume(source: Source?, visible: Bool, active: Bool) -> Readback? {
        guard visible, active, !isPresented, didDismiss, readback == nil, let acknowledged, let item,
              current(item, source: source, active: active) else { return nil }
        readback = acknowledged; confirmed = false; retireForm(); return acknowledged
    }
    func readIsCurrent(_ expected: Readback, context: ClubGovernanceReadContext, access: any ClubGovernanceAccess,
                       visible: Bool, active: Bool) -> Bool {
        visible && active && readback?.id == expected.id && readback?.reviewID == expected.reviewID &&
        expected.source.live(context: context, access: access)
    }
    @discardableResult func observe(_ result: ClubGovernanceSnapshot, for expected: Readback,
                                   context: ClubGovernanceReadContext, access: any ClubGovernanceAccess,
                                   visible: Bool, active: Bool) -> Bool {
        guard readIsCurrent(expected, context: context, access: access, visible: visible, active: active) else { return false }
        confirmed = false
        guard result.operation == .occurrenceStatus, result.scope == expected.source.context.scope,
              result.value["activityId"].int == expected.source.context.scope.activityID else { return false }
        confirmed = result.value["occurrenceStatus"] == .string("CANCELLED") &&
            result.value["activityCancelled"] == .bool(true) && result.value["publishStatus"] == .integer(0)
        return confirmed
    }
    func invalidateForm(source: Source?, active: Bool) {
        if let item, !current(item, source: source, active: active) { retireForm() }
    }
    func retire() { retireForm(); readback = nil; confirmed = false }
    private func retireForm() {
        isPresented = false; item = nil; submissionID = nil; acknowledged = nil; didDismiss = false
    }
}

@MainActor struct ClubOccurrenceCancellationPresentationOwner: View {
    let item: ClubOccurrenceCancellationReturn.Item
    @ObservedObject var owner: ClubOccurrenceCancellationReturn
    let source: () -> ClubOccurrenceCancellationReturn.Source?
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
                        }, occurrenceCancellationReturn: .init(begin: { review in
                            owner.begin(review, state: coordinator.state, item: item, source: source(), active: active())
                        }, acknowledged: { review, value in
                            owner.acknowledge(review, value: value, state: coordinator.state,
                                item: item, source: source(), active: active())
                        }))
                }
            }
    }
}

/// A navigation proof, separate from the acknowledged write and its retained lock.
struct ClubCreatedSeriesReceipt: Equatable {
    let seriesID: Int
    let scope: ClubGovernanceScope
    let identity: ClubReadIdentity
    let requestID: String
    init?(review: ClubGovernanceReview, value: ClubGovernanceValue) {
        guard review.command.operation == .createSeries,
              let principal = review.identity.accountID, principal > 0,
              let clubID = review.command.scope.clubID, clubID > 0,
              let topicID = review.command.scope.topicID, topicID > 0,
              let seriesID = value["id"].int, (1...9_007_199_254_740_991).contains(seriesID),
              value["clubId"].int == clubID, value["topicId"].int == topicID,
              value["createdByMemberId"].int == principal,
              let submitted = review.command.fields["requestId"]?.string, !submitted.isEmpty,
              let returned = value["requestId"].string, submitted.utf8.elementsEqual(returned.utf8) else { return nil }
        self.seriesID = seriesID; scope = .init(clubID: clubID, topicID: topicID, seriesID: seriesID)
        identity = review.identity; requestID = submitted
    }
    func accepts(_ snapshot: ClubGovernanceSnapshot) -> Bool {
        snapshot.operation == .seriesDetail && snapshot.scope == scope &&
        snapshot.value["id"].int == seriesID && snapshot.value["clubId"].int == scope.clubID &&
        snapshot.value["topicId"].int == scope.topicID
    }
}

@MainActor final class ClubSeriesCreationReturn: ObservableObject {
    struct Source: Equatable {
        enum Proof: Equatable {
            case topics(ClubGovernanceSnapshot, UInt64)
            case quickStart(ClubSessionQuickStartTarget)
        }
        let context: ClubGovernanceReadContext
        let scope: ClubGovernanceScope
        let seed: [String: ClubGovernanceValue]
        let proof: Proof
        let namespace: String
        let realm: String
        @MainActor private init?(context: ClubGovernanceReadContext, scope: ClubGovernanceScope,
                                 seed: [String: ClubGovernanceValue], proof: Proof, access: any ClubGovernanceAccess) {
            guard context.operation == .eventTopics, context.identity?.isSignedIn == true,
                  (scope.clubID ?? 0) > 0, (scope.topicID ?? 0) > 0,
                  scope.clubID == context.scope.clubID, scope.seriesID == nil,
                  access.isConfigured, context.identity == access.identity,
                  context.authorizationGeneration == access.authorizationGeneration,
                  context.accessIdentity == ObjectIdentifier(access) else { return nil }
            self.context = context; self.scope = scope; self.seed = seed; self.proof = proof
            namespace = access.storageNamespace; realm = access.journalRealm
        }
        @MainActor static func topics(context: ClubGovernanceReadContext, snapshot: ClubGovernanceSnapshot,
                                     generation: UInt64, topicID: Int, access: any ClubGovernanceAccess) -> Self? {
            guard context.accepts(snapshot),
                  snapshot.permissions?.allows(ClubGovernanceRead.eventTopics.permission, scope: context.scope) == true,
                  let rows = snapshot.value.array, rows.filter({ $0["id"].int == topicID }).count == 1 else { return nil }
            return .init(context: context, scope: .init(clubID: context.scope.clubID, topicID: topicID),
                         seed: [:], proof: .topics(snapshot, generation), access: access)
        }
        @MainActor static func quickStart(_ target: ClubSessionQuickStartTarget, access: any ClubGovernanceAccess) -> Self? {
            guard target.context.canRead else { return nil }
            return .init(context: target.context.topicsContext, scope: target.scope, seed: target.seed,
                         proof: .quickStart(target), access: access)
        }
        @MainActor func live(context: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> Bool {
            self.context == context && access.isConfigured && context.identity == access.identity &&
            context.authorizationGeneration == access.authorizationGeneration && context.accessIdentity == ObjectIdentifier(access) &&
            namespace == access.storageNamespace && realm == access.journalRealm
        }
    }
    struct Item: Identifiable {
        let route: ClubGovernanceFormRoute
        let source: Source
        var id: UUID { route.id }
    }
    struct Destination: Identifiable {
        let id = UUID()
        let source: Source
        let receipt: ClubCreatedSeriesReceipt
    }
    struct Callbacks {
        let begin: (ClubGovernanceReview) -> Bool
        let acknowledged: (ClubGovernanceReview, ClubGovernanceValue) -> Void
    }
    @Published private(set) var item: Item?
    @Published private(set) var isPresented = false
    @Published private(set) var destination: Destination?
    private var submissionID: UUID?
    private var receipt: ClubCreatedSeriesReceipt?
    private var didDismiss = false
    var holdsSource: Bool { item != nil || destination != nil }

    func open(_ source: Source?, visible: Bool, active: Bool) {
        guard !holdsSource, visible, active, let source else { return }
        item = .init(route: .init(operation: .createSeries, scope: source.scope, seed: source.seed), source: source)
        isPresented = true; submissionID = nil; receipt = nil; didDismiss = false
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
    func begin(_ review: ClubGovernanceReview, state: ClubGovernanceWriteState,
               item expected: Item, source: Source?, active: Bool) -> Bool {
        guard isPresented, current(expected, source: source, active: active), state == .reviewing,
              receipt == nil, review.command.operation == .createSeries, review.command.scope == expected.source.scope,
              review.identity == expected.source.context.identity,
              review.authorizationGeneration == expected.source.context.authorizationGeneration,
              review.storageNamespace == expected.source.namespace, review.journalRealm == expected.source.realm,
              review.snapshot.operation == .eventTopics, review.snapshot.scope == expected.source.scope,
              review.snapshot.permissions?.allows(ClubGovernanceRead.eventTopics.permission, scope: expected.source.scope) == true,
              review.snapshot.value.array?.filter({ $0["id"].int == expected.source.scope.topicID }).count == 1 else { return false }
        submissionID = review.id; return true
    }
    func acknowledge(_ review: ClubGovernanceReview, value: ClubGovernanceValue, state: ClubGovernanceWriteState,
                     item expected: Item, source: Source?, active: Bool) {
        guard isPresented, current(expected, source: source, active: active), state == .acknowledged,
              submissionID == review.id, receipt == nil,
              let matched = ClubCreatedSeriesReceipt(review: review, value: value) else { return }
        receipt = matched; isPresented = false
    }
    @discardableResult func dismissed(_ expected: Item, source: Source?, active: Bool) -> Bool {
        guard current(expected, source: source, active: active), !isPresented else { return false }
        if receipt != nil { didDismiss = true } else { retireForm() }
        return true
    }
    @discardableResult func consume(source: Source?, visible: Bool, active: Bool) -> Destination? {
        guard visible, active, !isPresented, didDismiss, let receipt, let item,
              destination == nil, current(item, source: source, active: active) else { return nil }
        let target = Destination(source: item.source, receipt: receipt)
        destination = target; retireForm(); return target
    }
    func invalidateForm(_ expected: Item, source: Source?, active: Bool) {
        if item?.id == expected.id, !current(expected, source: source, active: active) { retireForm() }
    }
    func isBound(context: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> Bool {
        (item?.source ?? destination?.source)?.live(context: context, access: access) == true
    }
    func destinationIsCurrent(_ target: Destination, context: ClubGovernanceReadContext, access: any ClubGovernanceAccess) -> Bool {
        destination?.id == target.id && target.source.live(context: context, access: access)
    }
    func destinationBinding(_ target: Destination, current: @escaping () -> Bool) -> Binding<Bool> {
        Binding(get: { self.destination?.id == target.id && current() }, set: { shown in
            guard !shown, self.destination?.id == target.id else { return }
            self.destination = nil
        })
    }
    func retireDestination(_ target: Destination) {
        guard destination?.id == target.id else { return }; destination = nil
    }
    func retire() { retireForm(); destination = nil }
    private func retireForm() {
        isPresented = false; item = nil; submissionID = nil; receipt = nil; didDismiss = false
    }
}

@MainActor struct ClubSeriesCreationPresentationOwner: View {
    let item: ClubSeriesCreationReturn.Item
    @ObservedObject var owner: ClubSeriesCreationReturn
    let source: () -> ClubSeriesCreationReturn.Source?
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
                        }, seriesCreationReturn: .init(begin: { review in
                            owner.begin(review, state: coordinator.state, item: item, source: source(), active: active())
                        }, acknowledged: { review, value in
                            owner.acknowledge(review, value: value, state: coordinator.state,
                                item: item, source: source(), active: active())
                        }))
                }
            }
            .onChange(of: source()) { _, source in owner.invalidateForm(item, source: source, active: active()) }
    }
}

@MainActor struct ClubCreatedSeriesDestinationOwner: View {
    let target: ClubSeriesCreationReturn.Destination
    @ObservedObject var owner: ClubSeriesCreationReturn
    let current: () -> Bool
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .navigationDestination(isPresented: owner.destinationBinding(target, current: current)) {
                Group {
                    if current() {
                        ClubGovernanceReadView(operation: .seriesDetail, scope: target.receipt.scope,
                            identity: target.receipt.identity, access: access, coordinator: coordinator,
                            expectedCreatedSeries: target.receipt)
                    } else { Color.clear }
                }
                .onChange(of: current(), initial: true) { _, valid in
                    if !valid { owner.retireDestination(target) }
                }
            }
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

/// Display-only interpretation of the form's existing minute value.
struct ClubSeriesOfferWindowPresentation {
    let minutes: Int?
    init(raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(text), (5...1440).contains(value) { minutes = value }
        else { minutes = nil }
    }
    func duration(locale: Locale) -> String? {
        guard let minutes else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale; calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.collapsesLargestUnit = false
        formatter.allowsFractionalUnits = false
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes * 60))
    }
}

/// Uses the original draft binding; partial input is never normalized or replaced.
struct ClubSeriesOfferWindowField: View {
    @Binding var minutes: String
    @Environment(\.locale) private var locale
    var body: some View {
        let presentation = ClubSeriesOfferWindowPresentation(raw: minutes)
        VStack(alignment: .leading, spacing: 4) {
            TextField("club.gov.field.offerMinutes", text: $minutes)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("club.gov.input.offerMinutes")
            Text(verbatim: "5–1440").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("club.schedule.offer.range")
            if let duration = presentation.duration(locale: locale) {
                Text(verbatim: duration).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("club.schedule.offer.duration")
            } else {
                Text("club.gov.invalid").font(.caption).foregroundStyle(.red)
                    .accessibilityIdentifier("club.schedule.offer.invalid")
            }
        }
    }
}
