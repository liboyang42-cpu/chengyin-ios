import SwiftUI

@MainActor struct ClubGovernanceCommandForm: View {
    let route: ClubGovernanceFormRoute
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    let validateTarget: (() async throws -> Void)?
    let seriesUpdateReturn: ClubSeriesUpdateReturn.Callbacks?
    let seriesCreationReturn: ClubSeriesCreationReturn.Callbacks?
    let occurrenceCancellationReturn: ClubOccurrenceCancellationReturn.Callbacks?
    let caseSubmissionReturn: ClubCaseSubmissionReturn.Callbacks?
    let attendanceReturn: ClubAttendanceCorrectionReturn.Callbacks?
    let roleManagementReturn: ClubRoleManagementReturn.Callbacks?
    let topicSettingsReturn: ClubTopicSettingsReturn.Callbacks?
    let banRemovalReturn: ClubBanRemovalReturn.Callbacks?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hostMaterials = ClubHostApplicationMaterials()
    @StateObject private var rolePicker = ClubRoleAssignmentReadModel()
    @StateObject private var seriesLeadPicker = ClubSeriesLeadReadModel()
    @StateObject private var notificationAudience = ClubNotificationAudienceReadModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var audienceVisible = false
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
    @State private var cancelConfirmReview: ClubGovernanceReview?
    @State private var generation: UInt64 = 0
    init(route: ClubGovernanceFormRoute, identity: ClubReadIdentity?, access: any ClubGovernanceAccess, coordinator: ClubGovernanceCoordinator, validateTarget: (() async throws -> Void)? = nil, caseSubmissionReturn: ClubCaseSubmissionReturn.Callbacks? = nil, attendanceReturn: ClubAttendanceCorrectionReturn.Callbacks? = nil, roleManagementReturn: ClubRoleManagementReturn.Callbacks? = nil, topicSettingsReturn: ClubTopicSettingsReturn.Callbacks? = nil, banRemovalReturn: ClubBanRemovalReturn.Callbacks? = nil, seriesUpdateReturn: ClubSeriesUpdateReturn.Callbacks? = nil, seriesCreationReturn: ClubSeriesCreationReturn.Callbacks? = nil, occurrenceCancellationReturn: ClubOccurrenceCancellationReturn.Callbacks? = nil) {
        self.route = route; self.identity = identity; self.access = access; self.coordinator = coordinator; self.validateTarget = validateTarget
        self.caseSubmissionReturn = caseSubmissionReturn
        self.attendanceReturn = attendanceReturn
        self.roleManagementReturn = roleManagementReturn
        self.topicSettingsReturn = topicSettingsReturn
        self.banRemovalReturn = banRemovalReturn
        self.seriesUpdateReturn = seriesUpdateReturn
        self.seriesCreationReturn = seriesCreationReturn
        self.occurrenceCancellationReturn = occurrenceCancellationReturn
        var initial = ClubGovernanceFormDraft(operation: route.operation, scope: route.scope, seed: route.seed)
        if route.operation == .assignRole { initial.text["roleCode"] = "" }
        _draft = State(initialValue: initial)
    }
    var body: some View {
        let hostMaterialAttachment = hostMaterials.attachment
        let _ = bindRolePicker()
        let _ = bindSeriesLeadPicker()
        let _ = bindNotificationAudience()
        Form {
            Section { Text("club.gov.localDraft"); Text(LocalizedStringKey(gateKey)) }
            if ClubOpsGovernanceFormNotes.applies(route.operation) { Section { ClubOpsGovernanceFormNotes(operation: route.operation, seed: route.seed) } }
            Section("club.gov.target") { ClubGovernanceFactRows(value: .object(route.scope.ids), fields: ["clubId", "topicId", "activityId", "seriesId", "memberId", "registrationId", "campaignId", "chapterId"]); ClubGovernanceFactRows(value: .object(draft.anchors), fields: Array(draft.anchors.keys).sorted()) }
            Section {
                if route.operation == .hostApply {
                    ClubHostApplicationMaterialsRows(model: hostMaterials, context: hostMaterialsContext,
                        allowed: { hostMaterialAttachment != nil && hostMaterials.attachment == hostMaterialAttachment && hostMaterialsAllowed }, changed: { dirty = true })
                }
                if route.operation == .sendNotification {
                    ClubNotificationAudienceView(context: audienceContext, access: access, model: notificationAudience,
                        selection: textBinding("audienceType"), canEdit: { audienceIsCurrent && !busy && !locked && review == nil },
                        isCurrent: { audienceIsCurrent })
                    ClubOpsNotifyContentFields(title: textBinding("title"), content: textBinding("content"))
                }
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
                        if showsCustomDateConversion {
                            Text("club.schedule.customConversion", tableName: "ClubSeriesSchedule")
                                .accessibilityIdentifier("club.schedule.formConversion")
                        }
                        if let issue = ClubSeriesScheduleDraft(form: draft, now: Date()).issue(now: Date()) {
                            ClubSeriesScheduleIssueLabel(issue: issue)
                        }
                    } else { Text("club.schedule.choose") }
                }
                if isSeries {
                    ClubOpsEventSeriesFields(operation: route.operation, capacity: textBinding("capacity"), waitlist: flagBinding("waitlistEnabled"))
                }
                if isSeries {
                    ClubSeriesOfferWindowField(minutes: textBinding("offerMinutes"))
                        .clubOpsEventVisible(showsOfferWindow)
                    ClubOpsEventOfferHelp(minutes: draft.text["offerMinutes"] ?? "", visible: showsOfferWindow)
                }
                if [.cancelOccurrence, .correctAttendance].contains(route.operation) {
                    ClubOpsEventReasonField(operation: route.operation, reason: textBinding("reason"))
                }
                if route.operation == .saveCustomer {
                    ClubOpsCustomerTagRemarkEditor(tagsText: textBinding("tags"), remark: textBinding("remark"))
                }
                if route.operation == .ban { ClubOpsBanDurationPicker(days: textBinding("banDays")) }
                ForEach(Array(draft.text.keys).sorted().filter { key in
                    (route.operation != .ban || key != "banDays") && (route.operation != .revokeRole || key != "reason") &&
                    (route.operation != .hostApply || key != "certImages") &&
                    (route.operation != .assignRole || !["targetMemberId", "roleCode"].contains(key)) &&
                    (!isSeries || (!ClubSeriesScheduleDraft.fieldKeys.contains(key) && key != "offerMinutes")) &&
                    (route.operation != .createSeries || key != "defaultLeadMemberId") &&
                    (!isSeries || key != "capacity") && (route.operation != .updateSeries || key != "defaultLeadMemberId") &&
                    (![.cancelOccurrence, .correctAttendance].contains(route.operation) || key != "reason") &&
                    (route.operation != .sendNotification || key != "audienceType") &&
                    (route.operation != .sendNotification || !["title", "content"].contains(key)) &&
                    (route.operation != .saveCustomer || !["tags", "remark"].contains(key))
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
                ForEach(Array(draft.flags.keys).sorted().filter { !isSeries || $0 != "waitlistEnabled" }, id: \.self) { key in
                    Toggle(LocalizedStringKey("club.gov.field." + key), isOn: flagBinding(key)).accessibilityIdentifier("club.gov.input." + key)
                }
            }.disabled(busy || locked || review != nil)
            if let failure { Section { Text(LocalizedStringKey(failure.localizationKey)).accessibilityIdentifier("club.gov.formError"); if let message = failure.message { Text(verbatim: message) } } }
            if busy { ProgressView() }
            if let review {
                Section("club.gov.review") {
                    ClubGovernanceFactRows(value: .object(review.command.fields), fields: Array(review.command.fields.keys).sorted().filter { $0 != "expiresAtEpochMs" && !(route.operation == .createSeries && $0 == "defaultLeadMemberId" && review.command.fields[$0] == .null) }, showUnknown: true)
                    if route.operation == .createSeries, review.command.fields["defaultLeadMemberId"] == .null {
                        LabeledContent("club.gov.field.defaultLeadMemberId") { Text("clubOpsEvent.lead.ownerDefault", tableName: "ClubOpsEvent") }
                            .accessibilityIdentifier("clubOpsEvent.review.ownerDefault")
                    }
                    ClubOpsBanExpiryReview(fields: review.command.fields)
                    if showsCustomDateConversion {
                        Text("club.schedule.customConversion", tableName: "ClubSeriesSchedule")
                            .accessibilityIdentifier("club.schedule.reviewConversion")
                    }
                    if route.operation == .sendNotification { ClubGovernanceFactRows(value: review.snapshot.value, fields: ["recipientCount", "inApp", "wechatSubscription"]) }
                    if route.operation == .sendNotification { ClubOpsNotifyPreviewSummary(value: review.snapshot.value) }
                    Button(access.allowsOfflineWrites ? "club.gov.confirmOffline" : "club.gov.confirmProduction") {
                        if route.operation == .cancelOccurrence { cancelConfirmReview = review } else { Task { await confirm(review) } }
                    }
                        .disabled(!access.canDispatch(review.command) || busy || locked).accessibilityIdentifier("club.gov.confirm")
                    Button("club.gov.cancelReview") { self.review = nil; coordinator.cancelReview() }.disabled(busy)
                }
            } else if receipt == nil {
                Button("club.gov.review") { Task { await prepare() } }.disabled(busy || locked || identity == nil || !roleAssignmentReady || !seriesScheduleReady || !seriesLeadReady || !hostMaterialsReady || !notificationAudienceReady).accessibilityIdentifier("club.gov.prepare")
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
                Section("club.gov.acknowledged") { Text("club.gov.acknowledgedBody")
                    ClubOpsGovernanceSuccess(operation: route.operation)
                    if route.operation == .correctAttendance { Text("clubOpsEvent.correct.success", tableName: "ClubOpsEvent").accessibilityIdentifier("clubOpsEvent.correct.success") }
                    ClubGovernanceFactRows(value: receipt, fields: ["id", "activityId", "refundStatus", "totalCount", "successCount", "failedCount", "refundedOrders", "manualOrders"])
                    if [.sendNotification, .retryNotification].contains(route.operation), let campaign = try? ClubOpsNotifyCampaign(value: receipt) {
                        ClubOpsNotifyCampaignRows(campaign: campaign, outcome: route.operation)
                    }
                    if [.sendNotification, .retryNotification].contains(route.operation), let id = receipt["id"].int {
                        NavigationLink { ClubGovernanceReadView(operation: .notificationStatus, scope: .init(clubID: route.scope.clubID, activityID: route.scope.activityID, campaignID: id), identity: identity, access: access, coordinator: coordinator) } label: { Text("club.gov.notificationStatus") }
                    }
                    ForEach(Array((receipt["failedSessions"].array ?? []).enumerated()), id: \.offset) { _, value in Text(verbatim: value.string ?? "") }
                }
            }
        }
        .background {
            if route.operation == .hostApply {
                let context = hostMaterialsContext
                if let attachment = hostMaterials.attachment {
                    ClubHostApplicationMaterialsLifetime { hostMaterials.depart(context, attachment: attachment) }
                        .frame(width: 0, height: 0).id(attachment)
                }
                if let value = hostMaterials.presentation {
                    ClubHostApplicationMaterialsOwner(model: hostMaterials, value: value,
                        allowed: { hostMaterialsAllowed }, changed: { dirty = true }).id(value.id)
                }
            }
        }
        .onAppear { activateHostMaterials(appearing: true) }
        .onDisappear { hostMaterials.hide() }
        .onChange(of: hostMaterialsContext) { _, _ in activateHostMaterials() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { activateHostMaterials() } else { hostMaterials.retire() }
        }
        .navigationTitle(ClubOpsEventFormCopy.title(route))
        .alert(Text("clubOpsEvent.cancel.confirmTitle", tableName: "ClubOpsEvent"), isPresented: Binding(get: { cancelConfirmReview != nil }, set: { if !$0 { cancelConfirmReview = nil } })) {
            Button(role: .destructive) {
                guard let pending = cancelConfirmReview, pending.id == review?.id else { cancelConfirmReview = nil; return }
                cancelConfirmReview = nil; Task { await confirm(pending) }
            } label: { Text("clubOpsEvent.cancel.confirmAction", tableName: "ClubOpsEvent") }
            Button(role: .cancel) { cancelConfirmReview = nil } label: { Text("clubOpsEvent.cancel.keep", tableName: "ClubOpsEvent") }
        } message: { Text("clubOpsEvent.cancel.confirmBody", tableName: "ClubOpsEvent") }
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
        .onAppear { audienceVisible = true }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { notificationAudience.leave(audienceContext) }
        }
        .task(id: AudienceTrigger(context: audienceContext, visible: audienceVisible, active: scenePhase == .active)) {
            guard route.operation == .sendNotification, audienceIsCurrent,
                  let permit = notificationAudience.activate(audienceContext) else { return }
            let expected = audienceContext
            await notificationAudience.load(permit, access: access, isCurrent: { audienceIsCurrent && audienceContext == expected })
        }
        .onDisappear { audienceVisible = false; notificationAudience.leave(audienceContext); seriesLeadPicker.leave(seriesLeadContext); scheduleSession = nil; generation &+= 1; coordinator.cancelReview(); rolePicker.leave(rolePickerContext) }
    }
    private var hostMaterialsContext: ClubHostApplicationMaterials.Context {
        ClubHostApplicationMaterials.context(formID: route.id, scope: route.scope, identity: identity, access: access)
    }
    private var hostMaterialsAllowed: Bool {
        route.operation == .hostApply && scenePhase == .active && identity?.isSignedIn == true &&
            identity == access.identity && hostMaterials.context == hostMaterialsContext && !busy && !locked && review == nil
    }
    private var hostMaterialsReady: Bool {
        route.operation != .hostApply || (hostMaterials.isCurrent(hostMaterialsContext, allowed: { hostMaterialsAllowed }) && !hostMaterials.blocksSubmission)
    }
    private func activateHostMaterials(appearing: Bool = false) {
        guard route.operation == .hostApply else { return }
        guard scenePhase == .active, identity?.isSignedIn == true, identity == access.identity else { hostMaterials.retire(); return }
        if appearing { hostMaterials.appear(hostMaterialsContext) } else { hostMaterials.activate(hostMaterialsContext) }
    }
    private struct AudienceTrigger: Hashable {
        let context: ClubNotificationAudienceReadModel.Context
        let visible: Bool
        let active: Bool
    }
    private var audienceContext: ClubNotificationAudienceReadModel.Context {
        ClubNotificationAudienceReadModel.context(scope: route.scope, identity: identity, access: access)
    }
    private var audienceIsCurrent: Bool { audienceVisible && scenePhase == .active && identity == access.identity }
    private func bindNotificationAudience() {
        if route.operation == .sendNotification { notificationAudience.bind(audienceContext) }
    }
    private var notificationAudienceReady: Bool {
        route.operation != .sendNotification || (audienceIsCurrent && notificationAudience.canPrepare(draft.text["audienceType"] ?? "", context: audienceContext, access: access))
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
    private var showsOfferWindow: Bool { route.operation == .createSeries && draft.flags["waitlistEnabled"] == true }
    private var showsCustomDateConversion: Bool {
        route.operation == .updateSeries && draft.text["recurrenceType"] == "CUSTOM_DATES" &&
        route.seed["recurrenceType"]?.string != "CUSTOM_DATES"
    }
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
        guard roleAssignmentReady && seriesScheduleReady && seriesLeadReady && hostMaterialsReady else { return }
        let revision = generation, expected = identity; busy = true; failure = nil
        do {
            if let validateTarget {
                try await validateTarget()
                guard revision == generation, expected == identity, expected == access.identity, !Task.isCancelled else { return }
            }
            let pending = try await coordinator.prepare(draft.command())
            guard revision == generation, expected == identity, expected == access.identity else { return }
            guard seriesScheduleReady else { coordinator.cancelReview(); throw ClubGovernanceFailure.invalidRequest }
            review = pending
        } catch { if revision == generation && expected == identity { failure = error as? ClubGovernanceFailure ?? .malformed } }
        if revision == generation { busy = false }
    }
    private func confirm(_ review: ClubGovernanceReview) async {
        let revision = generation, expected = identity; busy = true; failure = nil
        let submittedRequestID = draft.requestID
        do {
            // A reviewed schedule may have crossed Shanghai midnight while left open.
            guard seriesScheduleReady else { coordinator.cancelReview(); throw ClubGovernanceFailure.invalidRequest }
            if let validateTarget {
                try await validateTarget()
                guard revision == generation, expected == identity, expected == access.identity, !Task.isCancelled else { return }
            }
            guard seriesScheduleReady else { coordinator.cancelReview(); throw ClubGovernanceFailure.invalidRequest }
            if let caseSubmissionReturn, !caseSubmissionReturn.begin(review) { throw ClubGovernanceFailure.staleReview }
            let returnsToRoster = route.operation == .correctAttendance && attendanceReturn?.begin(review) == true
            let returnsToRoles = [ClubGovernanceMutation.assignRole, .revokeRole].contains(route.operation) && roleManagementReturn?.begin(review) == true
            let returnsToTopicSettings = route.operation == .saveTopicSettings && topicSettingsReturn?.begin(review) == true
            let returnsToBans = route.operation == .unban && banRemovalReturn?.begin(review) == true
            if route.operation == .updateSeries, let seriesUpdateReturn {
                guard self.review?.id == review.id, seriesUpdateReturn.begin(review) else { throw ClubGovernanceFailure.staleReview }
            }
            if route.operation == .createSeries, let seriesCreationReturn {
                guard self.review?.id == review.id, seriesCreationReturn.begin(review) else { throw ClubGovernanceFailure.staleReview }
            }
            if route.operation == .cancelOccurrence, let occurrenceCancellationReturn {
                guard self.review?.id == review.id, occurrenceCancellationReturn.begin(review) else { throw ClubGovernanceFailure.staleReview }
            }
            let value = try await coordinator.confirm(review)
            guard revision == generation, expected == identity, expected == access.identity else { return }
            receipt = value; self.review = nil; locked = true
            if returnsToRoster { attendanceReturn?.acknowledged(review, value) }
            caseSubmissionReturn?.acknowledged(review)
            if returnsToRoles { roleManagementReturn?.acknowledged(review, value) }
            if returnsToTopicSettings { topicSettingsReturn?.acknowledged(review, value) }
            if returnsToBans { banRemovalReturn?.acknowledged(review, value) }
            if route.operation == .updateSeries, submittedRequestID == draft.requestID, !Task.isCancelled {
                seriesUpdateReturn?.acknowledged(review, value)
            }
            if route.operation == .createSeries, submittedRequestID == draft.requestID, !Task.isCancelled {
                seriesCreationReturn?.acknowledged(review, value)
            }
            if route.operation == .cancelOccurrence, submittedRequestID == draft.requestID, !Task.isCancelled {
                occurrenceCancellationReturn?.acknowledged(review, value)
            }
            if route.operation == .issueGroupCode { groupCode = try ClubGovernanceGroupCode(receipt: value, receivedAt: Date()) }
        } catch {
            if revision == generation && expected == identity {
                failure = error as? ClubGovernanceFailure ?? .unknown(message: nil)
                self.review = nil; locked = coordinator.isLocked(review.command, identity: review.identity)
                if route.operation == .updateSeries, submittedRequestID == draft.requestID, !locked, let definite = failure {
                    seriesUpdateReturn?.conflicted(review, definite)
                }
            }
        }
        if revision == generation { busy = false }
    }
}
