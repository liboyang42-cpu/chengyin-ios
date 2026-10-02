import SwiftUI

struct ClubGovernanceCommandForm: View {
    let route: ClubGovernanceFormRoute
    let identity: ClubReadIdentity?
    let access: any ClubGovernanceAccess
    let coordinator: ClubGovernanceCoordinator
    @Environment(\.dismiss) private var dismiss
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
    init(route: ClubGovernanceFormRoute, identity: ClubReadIdentity?, access: any ClubGovernanceAccess, coordinator: ClubGovernanceCoordinator) {
        self.route = route; self.identity = identity; self.access = access; self.coordinator = coordinator
        _draft = State(initialValue: .init(operation: route.operation, scope: route.scope, seed: route.seed))
    }
    var body: some View {
        Form {
            Section { Text("club.gov.localDraft"); Text(LocalizedStringKey(gateKey)) }
            Section("club.gov.target") { ClubGovernanceFactRows(value: .object(route.scope.ids), fields: ["clubId", "topicId", "activityId", "seriesId", "memberId", "registrationId", "campaignId", "chapterId"]); ClubGovernanceFactRows(value: .object(draft.anchors), fields: Array(draft.anchors.keys).sorted()) }
            Section {
                ForEach(Array(draft.text.keys).sorted(), id: \.self) { key in
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
                Button("club.gov.review") { Task { await prepare() } }.disabled(busy || locked || identity == nil).accessibilityIdentifier("club.gov.prepare")
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
        .onChange(of: identity) { _, _ in generation &+= 1; review = nil; receipt = nil; groupCode = nil; coordinator.cancelReview(); draft = .init(operation: route.operation, scope: route.scope); failure = .staleReview; dismiss() }
        .onDisappear { generation &+= 1; coordinator.cancelReview() }
    }
    private var gateKey: String {
        switch route.operation.risk { case .administrative: return "club.gov.writeGate"; case .financial: return "club.gov.financialGate"; case .identity: return "club.gov.identityGate"; case .provider: return "club.gov.providerGate" }
    }
    private func textBinding(_ key: String) -> Binding<String> { Binding(get: { draft.text[key] ?? "" }, set: { draft.text[key] = $0; dirty = true; review = nil; coordinator.cancelReview() }) }
    private func flagBinding(_ key: String) -> Binding<Bool> { Binding(get: { draft.flags[key] ?? false }, set: { draft.flags[key] = $0; dirty = true; review = nil; coordinator.cancelReview() }) }
    private func prepare() async {
        let revision = generation, expected = identity; busy = true; failure = nil
        do {
            let pending = try await coordinator.prepare(draft.command())
            guard revision == generation, expected == identity, expected == access.identity else { return }
            review = pending
        } catch { if revision == generation && expected == identity { failure = error as? ClubGovernanceFailure ?? .malformed } }
        if revision == generation { busy = false }
    }
    private func confirm(_ review: ClubGovernanceReview) async {
        let revision = generation, expected = identity; busy = true; failure = nil
        do {
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
