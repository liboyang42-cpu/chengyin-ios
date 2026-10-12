import SwiftUI

@MainActor struct ClubGovernanceCommandForm: View {
    let route: ClubGovernanceFormRoute
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    let validateTarget: (() async throws -> Void)?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var rolePicker = ClubRoleAssignmentReadModel()
    @StateObject private var seriesLeadPicker = ClubSeriesLeadReadModel()
    @State private var scheduleSession: ClubSeriesScheduleSession?
    @State private var draft: ClubGovernanceFormDraft
    @State private var review: ClubGovernanceReview?
    @State private var failure: ClubGovernanceFailure?
    @State private var receipt: ClubGovernanceValue?
    @State private var groupCode: ClubGovernanceGroupCode?
    @State private var busy = false
    @State private var dirty = false
    @State private var locked = false
    @State private var showDiscard = false
    @State private var generation: UInt64 = 0
    init(route: ClubGovernanceFormRoute, identity: ClubReadIdentity?, access: any ClubGovernanceAccess, coordinator: ClubGovernanceCoordinator, validateTarget: (() async throws -> Void)? = nil) {
        self.route = route; self.identity = identity; self.access = access; self.coordinator = coordinator; self.validateTarget = validateTarget
        var initial = ClubGovernanceFormDraft(operation: route.operation, scope: route.scope, seed: route.seed)
        if route.operation == .assignRole { initial.text["roleCode"] = "" }
        _draft = State(initialValue: initial)
    }
    var body: some View {
        let _ = bindRolePicker()
        let _ = bindSeriesLeadPicker()
        Form {
            Section { Text("club.gov.localDraft"); Text(LocalizedStringKey(gateKey)) }
            Section("club.gov.target") { ClubGovernanceFactRows(value: .object(route.scope.ids), fields: ["clubId", "topicId", "activityId", "seriesId", "memberId", "registrationId", "campaignId", "chapterId"]); ClubGovernanceFactRows(value: .object(draft.anchors), fields: Array(draft.anchors.keys).sorted()) }
            Section {
                if route.operation == .assignRole {
                    ClubRoleAssignmentPicker(scope: route.scope, identity: identity, access: access, model: rolePicker,
                        memberID: textBinding("targetMemberId"), roleCode: textBinding("roleCode"),
                        canEdit: { !busy && !locked && review == nil })
                }
                if route.operation == .createSeries {
                    ClubSeriesLeadPicker(scope: route.scope, identity: identity, access: access, model: seriesLeadPicker,
                        memberID: textBinding("defaultLeadMemberId"), canEdit: { !busy && !locked && review == nil })
                }
                if isSeries {
                    Button("club.schedule.title") {
                        scheduleSession = .init(form: draft, identity: identity, access: access, now: Date())
                    }.disabled(identity == nil || identity != access.identity || !access.isConfigured).accessibilityIdentifier("club.schedule.open")
                    if !(draft.text["startDate"] ?? "").isEmpty {
                        ClubGovernanceFactRows(value: .object(draft.text.filter { ClubSeriesScheduleDraft.fieldKeys.contains($0.key) }.mapValues(ClubGovernanceValue.string)),
                            fields: ["recurrenceType", "startDate", "startTime", "occurrenceCount", "customDates"])
                    } else { Text("club.schedule.choose") }
                }
                ForEach(Array(draft.text.keys).sorted().filter { key in
                    (route.operation != .assignRole || !["targetMemberId", "roleCode"].contains(key)) &&
                    (!isSeries || !ClubSeriesScheduleDraft.fieldKeys.contains(key)) &&
                    (route.operation != .createSeries || key != "defaultLeadMemberId")
                }, id: \.self) { key in
                    if let choices = draft.choices(key) {
                        Picker(LocalizedStringKey("club.gov.field." + key), selection: textBinding(key)) {
                            ForEach(choices, id: \.self) { Text(LocalizedStringKey("club.gov.choice." + $0)).tag($0) }
                        }.accessibilityIdentifier("club.gov.input." + key)
                    } else {
                        TextField(LocalizedStringKey("club.gov.field." + key), text: textBinding(key), axis: ["content", "reason", "remark"].contains(key) ? .vertical : .horizontal)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("club.gov.input." + key)
                    }
                }
                ForEach(Array(draft.flags.keys).sorted(), id: \.self) { key in
                    Toggle(LocalizedStringKey("club.gov.field." + key), isOn: flagBinding(key)).accessibilityIdentifier("club.gov.input." + key)
                }
            }.disabled(busy || locked || review != nil)
            if let failure { Section { Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.gov.formError"); if let message = failure.message { Text(verbatim: message) } } }
            if busy { ProgressView() }
            if let review {
                Section("club.gov.review") {
                    ClubGovernanceFactRows(value: .object(review.command.fields), fields: Array(review.command.fields.keys).sorted(), showUnknown: true)
                    if route.operation == .sendNotification { ClubGovernanceFactRows(value: review.snapshot.value, fields: ["recipientCount", "inApp", "wechatSubscription"]) }
                    Button(access.allowsOfflineWrites ? "club.gov.confirmOffline" : "club.gov.confirmProduction") { Task { await confirm(review) } }
                        .disabled(!access.canDispatch(review.command) || busy || locked).accessibilityIdentifier("club.gov.confirm")
                    Button("club.gov.cancelReview") { self.review = nil; coordinator.cancelReview() }.disabled(busy)
                }
            } else if receipt == nil {
                Button("club.gov.review") { Task { await prepare() } }.disabled(busy || locked || identity == nil || !roleAssignmentReady || !seriesScheduleReady || !seriesLeadReady).accessibilityIdentifier("club.gov.prepare")
            }
            if let groupCode {
                TimelineView(.periodic(from: groupCode.receivedAt, by: 1)) { context in
                    Section {
                        if groupCode.isActive(at: context.date) { Text("club.gov.codeAvailable"); Text(verbatim: groupCode.code).privacySensitive().accessibilityIdentifier("club.gov.groupCode") }
                        else { Text("club.gov.expiredCode").accessibilityIdentifier("club.gov.expiredCode") }
                    }
                }
            }
            if let receipt {
                Section("club.gov.acknowledged") { Text("club.gov.acknowledgedBody"); ClubGovernanceFactRows(value: receipt, fields: ["id", "activityId", "refundStatus", "totalCount", "successCount", "failedCount", "refundedOrders", "manualOrders"])
                    if [.sendNotification, .retryNotification].contains(route.operation), let id = receipt["id"].int {
                        NavigationLink { ClubGovernanceReadView(operation: .notificationStatus, scope: .init(clubID: route.scope.clubID, activityID: route.scope.activityID, campaignID: id), identity: identity, access: access, coordinator: coordinator) } label: { Text("club.gov.notificationStatus") }
                    }
                    ForEach(Array((receipt["failedSessions"].array ?? []).enumerated()), id: \.offset) { _, value in Text(verbatim: value.string ?? "") }
                }
            }
        }
        .navigationTitle(LocalizedStringKey("club.gov.action." + route.operation.rawValue))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { if dirty || busy || locked { showDiscard = true } else { dismiss() } } } }
        .interactiveDismissDisabled(dirty || busy || locked)
        .confirmationDialog("club.gov.discardTitle", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("club.gov.discard", role: .destructive) { generation &+= 1; coordinator.cancelReview(); dismiss() }
            Button("club.gov.keepEditing", role: .cancel) {}
        } message: { Text(locked ? "club.gov.unknown" : "club.gov.discardBody") }
        .sheet(item: $scheduleSession) { session in
            NavigationStack {
                ClubSeriesScheduleEditor(session: session, canApply: { canApplySchedule(session) }, apply: { selection in
                    guard canApplySchedule(session), let next = try? selection.applying(to: draft, now: Date()) else { return false }
                    draft = next; dirty = true; review = nil; failure = nil; coordinator.cancelReview(); scheduleSession = nil
                    return true
                })
            }
        }
        .onChange(of: access.authorizationGeneration) { _, _ in scheduleSession = nil }
        .onChange(of: identity) { _, _ in scheduleSession = nil; generation &+= 1; review = nil; receipt = nil; groupCode = nil; coordinator.cancelReview(); draft = .init(operation: route.operation, scope: route.scope); failure = .staleReview; dismiss() }
        .task(id: rolePickerContext) {
            guard route.operation == .assignRole, let permit = rolePicker.activate(rolePickerContext) else { return }
            await rolePicker.load(permit, access: access)
        }
        .task(id: seriesLeadContext) {
            guard route.operation == .createSeries, let permit = seriesLeadPicker.activate(seriesLeadContext) else { return }
            await seriesLeadPicker.load(permit, access: access)
        }
        .onDisappear { seriesLeadPicker.leave(seriesLeadContext); scheduleSession = nil; generation &+= 1; coordinator.cancelReview(); rolePicker.leave(rolePickerContext) }
    }
    private var rolePickerContext: ClubGovernanceReadContext {
        ClubRoleAssignmentReadModel.context(scope: route.scope, identity: identity, access: access)
    }
    private func bindRolePicker() {
        if route.operation == .assignRole { rolePicker.bind(rolePickerContext) }
    }
    private var roleAssignmentReady: Bool {
        route.operation != .assignRole || rolePicker.canPrepare(scope: route.scope, identity: identity, access: access,
            memberID: draft.text["targetMemberId"] ?? "", roleCode: draft.text["roleCode"] ?? "")
    }
    private var seriesLeadContext: ClubSeriesLeadReadModel.Context {
        ClubSeriesLeadReadModel.context(scope: route.scope, identity: identity, access: access)
    }
    private func bindSeriesLeadPicker() {
        if route.operation == .createSeries { seriesLeadPicker.bind(seriesLeadContext) }
    }
    private var seriesLeadReady: Bool {
        route.operation != .createSeries || seriesLeadPicker.canPrepare(scope: route.scope, identity: identity, access: access,
            memberID: draft.text["defaultLeadMemberId"] ?? "")
    }
    private var isSeries: Bool { [.createSeries, .updateSeries].contains(route.operation) }
    private var seriesScheduleReady: Bool {
        !isSeries || (!(draft.text["startDate"] ?? "").isEmpty && ClubSeriesScheduleDraft(form: draft, now: Date()).issue(now: Date()) == nil)
    }
    private func canApplySchedule(_ session: ClubSeriesScheduleSession) -> Bool {
        !busy && !locked && review == nil && session.isCurrent(activeID: scheduleSession?.id, form: draft, identity: identity, access: access)
    }
    private var gateKey: String {
        switch route.operation.risk { case .administrative: return "club.gov.writeGate"; case .financial: return "club.gov.financialGate"; case .identity: return "club.gov.identityGate"; case .provider: return "club.gov.providerGate" }
    }
    private func textBinding(_ key: String) -> Binding<String> { Binding(get: { draft.text[key] ?? "" }, set: { draft.text[key] = $0; dirty = true; review = nil; coordinator.cancelReview() }) }
    private func flagBinding(_ key: String) -> Binding<Bool> { Binding(get: { draft.flags[key] ?? false }, set: { draft.flags[key] = $0; dirty = true; review = nil; coordinator.cancelReview() }) }
    private func prepare() async {
        guard roleAssignmentReady && seriesScheduleReady && seriesLeadReady else { return }
        let revision = generation, expected = identity; busy = true; failure = nil
        do {
            if let validateTarget {
                try await validateTarget()
                guard revision == generation, expected == identity, expected == access.identity, !Task.isCancelled else { return }
            }
            let pending = try await coordinator.prepare(draft.command())
            guard revision == generation, expected == identity, expected == access.identity else { return }
            review = pending
        } catch { if revision == generation && expected == identity { failure = error as? ClubGovernanceFailure ?? .malformed } }
        if revision == generation { busy = false }
    }
    private func confirm(_ review: ClubGovernanceReview) async {
        let revision = generation, expected = identity; busy = true; failure = nil
        do {
            if let validateTarget {
                try await validateTarget()
                guard revision == generation, expected == identity, expected == access.identity, !Task.isCancelled else { return }
            }
            let value = try await coordinator.confirm(review)
            guard revision == generation, expected == identity, expected == access.identity else { return }
            receipt = value; self.review = nil; locked = true
            if route.operation == .issueGroupCode { groupCode = try ClubGovernanceGroupCode(receipt: value, receivedAt: Date()) }
        } catch {
            if revision == generation && expected == identity {
                failure = error as? ClubGovernanceFailure ?? .unknown(message: nil)
                self.review = nil; locked = coordinator.isLocked(review.command, identity: review.identity)
            }
        }
        if revision == generation { busy = false }
    }
}
