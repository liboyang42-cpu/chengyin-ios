import SwiftUI

/// Session host owns access/coordinator and passes a published identity. This additive
/// entry can be mounted on ClubHome (.create) and ClubDetail (.club(id)).
struct ClubOperationsEntryButton: View {
    let target: ClubOperationsTarget
    let identity: ClubReadIdentity?
    let access: any ClubOperationsAccess
    let coordinator: ClubOperationsCoordinator
    /// Mini-program club/create redirects non-hosts to club/apply; the host supplies the
    /// existing host-status/become-leader governance read when it has one.
    var hostApplication: ClubGovernanceContext? = nil
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { Label(target == .create ? "club.ops.create" : "club.ops.manage", systemImage: target == .create ? "plus.circle" : "slider.horizontal.3") }
            .accessibilityIdentifier("club.ops." + (target == .create ? "openCreate" : "openManage"))
            .sheet(isPresented: $presented) {
                NavigationStack { ClubOperationsWorkspaceView(target: target, identity: identity, access: access, coordinator: coordinator, hostApplication: hostApplication) }
            }
    }
}

struct ClubOperationsWorkspaceView: View {
    let target: ClubOperationsTarget
    let identity: ClubReadIdentity?
    let access: any ClubOperationsAccess
    let coordinator: ClubOperationsCoordinator
    var hostApplication: ClubGovernanceContext? = nil
    var requestedTab: String? = ClubWorkspaceTab.manage.rawValue
    var onEnterClubManagement: ((ClubCreateToManageDestination) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var profileChoice = ClubProfileChoiceController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: ClubOperationsSnapshot?
    @State private var draft = ClubOperationsDraft()
    @State private var baseline = ClubOperationsDraft()
    @State private var state: ClubOperationsState = .idle
    @State private var review: ClubOperationsReview?
    @State private var loading = false
    @State private var errorKey: String?
    @State private var serverMessage: String?
    @State private var generation: UInt64 = 0
    @State private var screenIdentity: ClubReadIdentity?
    @State private var showDiscard = false
    @State private var readbackUnavailable = false
    @State private var ownerID = UUID()
    @State private var artworkRevision = UUID()
    @State private var createReceiptIdentity: ClubReadIdentity?
    @State private var createReceiptClubID: Int?
    @State private var readbackIdentity: ClubReadIdentity?
    @State private var enteredManageDestination: ClubCreateToManageDestination?
    private var dirty: Bool { draft != baseline }
    private var title: LocalizedStringKey { target == .create ? "club.ops.create" : "club.ops.manage" }
    static func makeCreateToManageFlow(
        access: any ClubOperationsAccess,
        snapshot: ClubOperationsSnapshot?,
        readbackUnavailable: Bool,
        createReceiptIdentity: ClubReadIdentity?,
        createReceiptClubID: Int?,
        currentIdentity: ClubReadIdentity?,
        readbackIdentity: ClubReadIdentity?,
        requestedTab: String?,
        enteredManageDestination: ClubCreateToManageDestination?
    ) -> ClubCreateToManageFlowState {
        let gate = ClubCreationGate(access: access)
        var ownedIDs = snapshot?.ownedClubIDs ?? []
        if let profileID = snapshot?.profile?.club.id, !ownedIDs.contains(profileID) {
            ownedIDs.append(profileID)
        }
        let readbackSucceeded = !readbackUnavailable && snapshot != nil && readbackIdentity != nil
        return ClubCreateToManageFlowState(
            gate: gate,
            receiptAccountId: createReceiptIdentity?.accountID,
            receiptClubId: createReceiptClubID,
            currentAccountId: currentIdentity?.accountID,
            readbackAccountId: readbackIdentity?.accountID,
            readbackOwnedClubIds: ownedIDs,
            readbackSucceeded: readbackSucceeded,
            readbackUnavailable: readbackUnavailable,
            requestedTab: requestedTab,
            enteredDestination: enteredManageDestination
        )
    }
    var createToManageFlow: ClubCreateToManageFlowState {
        Self.makeCreateToManageFlow(
            access: access,
            snapshot: snapshot,
            readbackUnavailable: readbackUnavailable,
            createReceiptIdentity: createReceiptIdentity,
            createReceiptClubID: createReceiptClubID,
            currentIdentity: identity,
            readbackIdentity: readbackIdentity,
            requestedTab: requestedTab,
            enteredManageDestination: enteredManageDestination
        )
    }
    var body: some View {
        Form {
            if loading { ProgressView().accessibilityIdentifier("club.ops.loading") }
            if identity == nil { Text("club.ops.signedOut") }
            else if !access.isConfigured { Text("club.ops.unavailable") }
            if let errorKey { Text(LocalizedStringKey(errorKey)).accessibilityIdentifier("club.ops.error") }
            if let serverMessage { Text(verbatim: serverMessage).textSelection(.enabled) }
            if let snapshot { content(snapshot) }
            status
        }
        .navigationTitle(title)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: loading)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("club.ops.close") {
                    if dirty || state.locksForm { showDiscard = true } else { dismiss() }
                }.accessibilityIdentifier("club.ops.close")
            }
        }
        .interactiveDismissDisabled(dirty || state.locksForm)
        .confirmationDialog("club.ops.discardTitle", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("club.ops.discard", role: .destructive) { dismiss() }
            Button("club.ops.keepEditing", role: .cancel) {}
        } message: { Text("club.ops.discardMessage") }
        .sheet(item: $review, onDismiss: cancelReview) { pending in
            NavigationStack {
                ClubOperationsReviewView(review: pending, canSubmit: coordinator.writeAvailability != .unverified, isExample: coordinator.writeAvailability == .syntheticOnly, onCancel: cancelReview) {
                    review = nil; state = .preflighting
                    Task { await confirm(pending) }
                }
            }.interactiveDismissDisabled(state == .preflighting || state == .submitting)
        }
        .background {
            if let session = profileChoice.session {
                ClubProfileChoicePresentationOwner(controller: profileChoice, session: session, draft: $draft,
                    context: profileChoiceContext, isCurrent: profileChoiceIsCurrent)
                    .id(session.id)
            }
        }
        .onChange(of: profileChoiceContext) { _, _ in profileChoice.close() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { profileChoice.close() } }
        .task(id: identity) {
            generation &+= 1; cancelReview(); snapshot = nil; draft = .init(); baseline = .init()
            screenIdentity = identity; errorKey = nil; serverMessage = nil; readbackUnavailable = false
            readbackIdentity = nil; enteredManageDestination = nil
            if createReceiptIdentity == nil || createReceiptIdentity?.accountID == identity?.accountID {
                createReceiptIdentity = nil; createReceiptClubID = nil
            }
            coordinator.synchronizeSession()
            state = coordinator.state(target: target); loading = false
            await load()
        }
        .onDisappear {
            profileChoice.close()
            generation &+= 1
            if let screenIdentity { coordinator.leaveScreen(target: target, expectedIdentity: screenIdentity, ownerID: ownerID) }
        }
    }
    private var profileChoiceContext: ClubProfileChoiceContext? {
        ClubProfileChoiceContext(target: target, identity: identity, access: access, profile: snapshot?.profile, sourceRevision: artworkRevision)
    }
    private func profileChoiceIsCurrent(_ expected: ClubProfileChoiceContext) -> Bool {
        scenePhase == .active && screenIdentity == identity && !loading && !state.locksForm && review == nil &&
            expected.matches(target: target, identity: identity, access: access, profile: snapshot?.profile, sourceRevision: artworkRevision)
    }
    @ViewBuilder private func content(_ value: ClubOperationsSnapshot) -> some View {
        if let profile = value.profile {
            Section {
                QuestifyImageEntityCard(imageSource: profile.club.cover, title: profile.club.name, subtitle: profile.club.city, fallbackSymbol: "person.3.fill", minimumHeight: 230,
                    progressiveBlur: .cover, artworkIdentity: identity != nil && screenIdentity == identity && access.identity == identity && access.isConfigured && !loading
                        ? .init(owner: ownerID.uuidString + ":" + String(identity?.accountID ?? 0) + ":" + String(identity?.epoch ?? 0), content: "club:\(profile.club.id)", version: artworkRevision.uuidString) : nil) {
                    Text(profile.club.isOwner ? "club.ops.owner" : "club.ops.administrator")
                }.questifyCardListRow()
            }
        }
        if target == .create && !value.canCreate {
            // Mini-program club/create no-permission and limit states.
            Section {
                ContentUnavailableView {
                    Label(value.accountRole != "club" ? "club.ops.leaderRequired.title" : "club.ops.clubLimit.title",
                          systemImage: value.accountRole != "club" ? "person.badge.plus" : "person.3")
                } description: {
                    Text(value.accountRole != "club" ? "club.ops.leaderRequired.apply" : "club.ops.clubLimit")
                }
                if value.accountRole != "club", let hostApplication {
                    ClubCreateHostApplicationLink(identity: identity, governance: hostApplication)
                }
            }
        } else {
            ClubOperationsProfileForm(draft: $draft, isCreate: target == .create, isOwner: value.profile?.club.isOwner == true, joinPolicySupported: value.profile?.club.joinPolicySupported == true,
                choiceContext: profileChoiceContext, choiceIsCurrent: profileChoiceIsCurrent, choiceController: profileChoice)
                .disabled(loading || state.locksForm)
            Section {
                Button {
                    let command: ClubOperationsCommand
                    if let original = value.profile { command = .update(draft, original: original) }
                    else { command = .create(draft) }
                    Task { await prepare(command) }
                } label: {
                    Text(target == .create ? "club.ops.create" : "club.ops.reviewProfile").frame(maxWidth: .infinity)
                }
                .buttonStyle(.questifyPrimary)
                .disabled(loading || state.locksForm || (target != .create && !dirty))
                .accessibilityIdentifier("club.ops.reviewProfile")
            }.listRowBackground(Color.clear)
        }
        if let profile = value.profile, profile.club.isOwner {
            Section("club.ops.openSettings") {
                ForEach(ClubOpenSetting.allCases, id: \.rawValue) { setting in
                    if let enabled = profile.value(setting) {
                        Button {
                            Task { await prepare(.openSetting(setting, enabled: !enabled, previous: enabled)) }
                        } label: {
                            LabeledContent(LocalizedStringKey("club.ops." + setting.rawValue)) { Text(enabled ? "club.ops.enabled" : "club.ops.disabled") }
                        }
                        .disabled(loading || state.locksForm)
                        .accessibilityIdentifier("club.ops.setting." + setting.rawValue)
                    } else { LabeledContent(LocalizedStringKey("club.ops." + setting.rawValue)) { Text("club.ops.unknownValue") } }
                }
            }
            Section("club.ops.memberRoles") {
                if value.members.isEmpty { Text("club.ops.membersUnavailable").foregroundStyle(.secondary) }
                ForEach(value.members) { member in
                    if !member.isOwner, member.memberId != identity?.accountID, [0, 1].contains(member.role) {
                        Button {
                            Task { await prepare(.memberRole(memberID: member.id, admin: !member.isAdmin, previousRole: member.role)) }
                        } label: {
                            LabeledContent {
                                Text(member.isAdmin ? "club.ops.removeAdmin" : "club.ops.makeAdmin")
                            } label: { Text(verbatim: member.trimmedNickname ?? "—") }
                        }
                        .disabled(loading || state.locksForm)
                        .accessibilityIdentifier("club.ops.member.\(member.id)")
                    } else {
                        LabeledContent { Text(member.isOwner ? "club.ops.owner" : "club.ops.unknownRole") } label: { Text(verbatim: member.trimmedNickname ?? "—") }
                    }
                }
            }
        }
        if access.writeAvailability == .unverified { Section { Text("club.ops.writeGated").accessibilityIdentifier("club.ops.writeGated") } }
    }
    @ViewBuilder private var status: some View {
        Section {
            switch state {
            case .preparing, .preflighting, .submitting: ProgressView("club.ops.checking")
            case .notSent: Text("club.ops.notSent").accessibilityIdentifier("club.ops.notSent")
            case .acknowledged(let receipt):
                Text("club.ops.acknowledged").accessibilityIdentifier("club.ops.acknowledged")
                if let message = receipt.message { Text(verbatim: message) }
            case .rejected(let failure):
                Text("club.ops.rejected")
                if let message = failure.message { Text(verbatim: message) }
            case .outcomeUnknown: Text("club.ops.outcomeUnknown").accessibilityIdentifier("club.ops.outcomeUnknown")
            default: EmptyView()
            }
            if readbackUnavailable { Text("club.ops.readbackUnavailable") }
            if createToManageFlow.requiresReadbackRecovery(state: state, hasSnapshot: snapshot != nil) {
                Button("club.ops.readBack") { Task { await readBack() } }
                    .disabled(loading).accessibilityIdentifier("club.ops.readBack")
            }
            if snapshot == nil, identity != nil, access.isConfigured, !loading {
                Button("club.ops.retryRead") {
                    Task {
                        if createToManageFlow.requiresReadbackRecovery(state: state, hasSnapshot: snapshot != nil) {
                            await readBack()
                        } else {
                            await load()
                        }
                    }
                }.accessibilityIdentifier("club.ops.retryRead")
            }
            if target == .create, shouldShowPostCreateManagementClosure {
                postCreateManagementClosure
            }
        }
    }
    private var shouldShowPostCreateManagementClosure: Bool {
        if case .acknowledged = state { return true }
        if case .notSent = state { return true }
        return createReceiptClubID != nil || readbackUnavailable
    }
    @ViewBuilder private var postCreateManagementClosure: some View {
        let flow = createToManageFlow
        Text(LocalizedStringKey(Self.createStatusKey(flow.blockReason)))
            .font(flow.canEnterManagement ? .headline : .body)
            .foregroundStyle(flow.canEnterManagement ? .primary : .secondary)
            .accessibilityIdentifier("clubCreateManage.status")
        Button {
            if let destination = Self.performEnterClubManagement(
                access: access,
                snapshot: snapshot,
                readbackUnavailable: readbackUnavailable,
                createReceiptIdentity: createReceiptIdentity,
                createReceiptClubID: createReceiptClubID,
                currentIdentity: identity,
                readbackIdentity: readbackIdentity,
                requestedTab: requestedTab,
                enteredManageDestination: &enteredManageDestination
            ) {
                onEnterClubManagement?(destination)
            }
        } label: {
            Text(flow.validatedTab == .manage || !flow.canEnterManagement ? "club.ops.enterManagement" : "club.ops.enterDetail")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.questifyPrimary)
        .disabled(loading || !flow.canEnterManagement)
        .accessibilityIdentifier("clubCreateManage.enterManagement")
        if let destination = enteredManageDestination,
           flow.canEnterManagement,
           destination.accountId == identity?.accountID {
            if destination.opensManagementWorkspace {
                NavigationLink {
                    ClubOperationsWorkspaceView(
                        target: .club(destination.clubId),
                        identity: identity,
                        access: access,
                        coordinator: coordinator,
                        hostApplication: hostApplication
                    )
                } label: {
                    Text("club.ops.openManagement")
                }
                .accessibilityIdentifier("clubCreateManage.destination")
            } else {
                Text("club.ops.destinationDetail")
                    .accessibilityIdentifier("clubCreateManage.fallbackDestination")
            }
        }
    }
    /// Core's flow copy is bilingual engineering text; the screen shows one localized line per state.
    static func createStatusKey(_ reason: ClubCreateToManageBlockReason?) -> String {
        switch reason {
        case nil: return "club.ops.createdStatus.ready"
        case .gateBlocked: return "club.ops.createdStatus.closed"
        case .awaitingConfirmedReceipt: return "club.ops.createdStatus.confirming"
        case .accountMismatch: return "club.ops.createdStatus.accountChanged"
        case .readbackFailed, .clubIdMismatch: return "club.ops.createdStatus.unread"
        }
    }
    @MainActor private func load() async {
        guard let identity, access.isConfigured, !loading else { return }
        generation &+= 1; let run = generation
        loading = true; errorKey = nil; serverMessage = nil
        do {
            let result = try await access.snapshot(target: target)
            guard generation == run, access.identity == identity, !Task.isCancelled else { return }
            guard result.target == target else { throw ClubOperationsBlock.changed }
            artworkRevision = UUID(); snapshot = result; draft = result.profile.map(ClubOperationsDraft.init(profile:)) ?? .init(); baseline = draft
            loading = false; state = coordinator.state(target: target)
        } catch {
            guard generation == run, access.identity == identity, !Task.isCancelled else { return }
            loading = false; show(error)
        }
    }
    @MainActor private func prepare(_ command: ClubOperationsCommand) async {
        guard let identity, !state.locksForm, !loading else { return }
        generation &+= 1; let run = generation
        state = .preparing; errorKey = nil; serverMessage = nil
        do {
            let pending = try await coordinator.prepare(command, target: target, expectedIdentity: identity, ownerID: ownerID)
            guard run == generation, access.identity == identity, !Task.isCancelled else { coordinator.cancel(pending); return }
            review = pending; state = coordinator.state(target: target)
        } catch {
            guard run == generation, access.identity == identity else { return }
            state = coordinator.state(target: target); show(error)
        }
    }
    private func cancelReview() {
        if let review { coordinator.cancel(review) }; review = nil
        state = coordinator.state(target: target)
    }
    @MainActor private func confirm(_ pending: ClubOperationsReview) async {
        generation &+= 1; let run = generation
        Self.performBeginConfirm(
            pending,
            target: target,
            snapshot: &snapshot,
            readbackUnavailable: &readbackUnavailable,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity,
            enteredManageDestination: &enteredManageDestination
        )
        await coordinator.confirm(pending)
        guard run == generation, !Task.isCancelled else { return }
        Self.performFinishConfirm(
            pending,
            target: target,
            identity: identity,
            access: access,
            coordinator: coordinator,
            snapshot: &snapshot,
            draft: &draft,
            baseline: &baseline,
            state: &state,
            readbackUnavailable: &readbackUnavailable,
            artworkRevision: &artworkRevision,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity
        )
    }
    @MainActor private func readBack() async {
        guard let identity, !loading else { return }
        generation &+= 1; let run = generation; loading = true
        await coordinator.readBack(target: target, ownerID: ownerID)
        guard run == generation, !Task.isCancelled else { return }
        Self.performFinishReadBack(
            target: target,
            identity: identity,
            access: access,
            coordinator: coordinator,
            loading: &loading,
            snapshot: &snapshot,
            draft: &draft,
            baseline: &baseline,
            state: &state,
            readbackUnavailable: &readbackUnavailable,
            artworkRevision: &artworkRevision,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity
        )
    }
    @MainActor static func performBeginConfirm(
        _ pending: ClubOperationsReview,
        target: ClubOperationsTarget,
        snapshot: inout ClubOperationsSnapshot?,
        readbackUnavailable: inout Bool,
        createReceiptIdentity: inout ClubReadIdentity?,
        createReceiptClubID: inout Int?,
        readbackIdentity: inout ClubReadIdentity?,
        enteredManageDestination: inout ClubCreateToManageDestination?
    ) {
        snapshot = nil; readbackUnavailable = false; readbackIdentity = nil; enteredManageDestination = nil
        if target == .create { createReceiptIdentity = pending.identity; createReceiptClubID = nil }
    }
    @MainActor static func performFinishConfirm(
        _ pending: ClubOperationsReview,
        target: ClubOperationsTarget,
        identity: ClubReadIdentity?,
        access: any ClubOperationsAccess,
        coordinator: ClubOperationsCoordinator,
        snapshot: inout ClubOperationsSnapshot?,
        draft: inout ClubOperationsDraft,
        baseline: inout ClubOperationsDraft,
        state: inout ClubOperationsState,
        readbackUnavailable: inout Bool,
        artworkRevision: inout UUID,
        createReceiptIdentity: inout ClubReadIdentity?,
        createReceiptClubID: inout Int?,
        readbackIdentity: inout ClubReadIdentity?
    ) {
        guard access.identity == pending.identity else { return }
        state = coordinator.state(target: target)
        if target == .create, case .acknowledged(let receipt) = state {
            createReceiptIdentity = pending.identity
            createReceiptClubID = receipt.clubID
        }
        performAcceptReadback(
            target: target,
            identity: identity,
            access: access,
            coordinator: coordinator,
            snapshot: &snapshot,
            draft: &draft,
            baseline: &baseline,
            readbackUnavailable: &readbackUnavailable,
            artworkRevision: &artworkRevision,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity
        )
    }
    @MainActor static func performFinishReadBack(
        target: ClubOperationsTarget,
        identity: ClubReadIdentity,
        access: any ClubOperationsAccess,
        coordinator: ClubOperationsCoordinator,
        loading: inout Bool,
        snapshot: inout ClubOperationsSnapshot?,
        draft: inout ClubOperationsDraft,
        baseline: inout ClubOperationsDraft,
        state: inout ClubOperationsState,
        readbackUnavailable: inout Bool,
        artworkRevision: inout UUID,
        createReceiptIdentity: inout ClubReadIdentity?,
        createReceiptClubID: inout Int?,
        readbackIdentity: inout ClubReadIdentity?
    ) {
        guard access.identity == identity else { return }
        loading = false
        performAcceptReadback(
            target: target,
            identity: identity,
            access: access,
            coordinator: coordinator,
            snapshot: &snapshot,
            draft: &draft,
            baseline: &baseline,
            readbackUnavailable: &readbackUnavailable,
            artworkRevision: &artworkRevision,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity
        )
        state = coordinator.state(target: target)
    }
    @MainActor static func performAcceptReadback(
        target: ClubOperationsTarget,
        identity: ClubReadIdentity?,
        access: any ClubOperationsAccess,
        coordinator: ClubOperationsCoordinator,
        snapshot: inout ClubOperationsSnapshot?,
        draft: inout ClubOperationsDraft,
        baseline: inout ClubOperationsDraft,
        readbackUnavailable: inout Bool,
        artworkRevision: inout UUID,
        createReceiptIdentity: inout ClubReadIdentity?,
        createReceiptClubID: inout Int?,
        readbackIdentity: inout ClubReadIdentity?
    ) {
        switch coordinator.readback(target: target) {
        case .received(let value):
            artworkRevision = UUID(); snapshot = value; readbackUnavailable = false
            readbackIdentity = access.identity
            if case .acknowledged(let receipt) = coordinator.state(target: target) {
                if target == .create {
                    if createReceiptIdentity == nil { createReceiptIdentity = identity }
                    createReceiptClubID = receipt.clubID
                }
                draft = value.profile.map(ClubOperationsDraft.init(profile:)) ?? .init(); baseline = draft
            }
        case .unavailable:
            readbackUnavailable = true
            readbackIdentity = nil
        default: break
        }
    }
    @MainActor static func performEnterClubManagement(
        access: any ClubOperationsAccess,
        snapshot: ClubOperationsSnapshot?,
        readbackUnavailable: Bool,
        createReceiptIdentity: ClubReadIdentity?,
        createReceiptClubID: Int?,
        currentIdentity: ClubReadIdentity?,
        readbackIdentity: ClubReadIdentity?,
        requestedTab: String?,
        enteredManageDestination: inout ClubCreateToManageDestination?
    ) -> ClubCreateToManageDestination? {
        var nextFlow = makeCreateToManageFlow(
            access: access,
            snapshot: snapshot,
            readbackUnavailable: readbackUnavailable,
            createReceiptIdentity: createReceiptIdentity,
            createReceiptClubID: createReceiptClubID,
            currentIdentity: currentIdentity,
            readbackIdentity: readbackIdentity,
            requestedTab: requestedTab,
            enteredManageDestination: enteredManageDestination
        )
        guard let destination = nextFlow.enterClubManagement(requestedTab: requestedTab) else { return nil }
        enteredManageDestination = destination
        return destination
    }
    private func show(_ error: Error) {
        serverMessage = (error as? ClubReadFailure)?.message
        if let block = error as? ClubOperationsBlock { errorKey = "club.ops.error." + String(describing: block) }
        else if (error as? ClubReadFailure)?.isForbidden == true { errorKey = "club.ops.error.forbidden" }
        else { errorKey = "club.ops.readFailed" }
    }
}

private struct ClubOperationsProfileForm: View {
    @Binding var draft: ClubOperationsDraft
    let isCreate: Bool
    let isOwner: Bool
    let joinPolicySupported: Bool
    var choiceContext: ClubProfileChoiceContext? = nil
    var choiceIsCurrent: (ClubProfileChoiceContext) -> Bool = { _ in false }
    let choiceController: ClubProfileChoiceController
    var body: some View {
        if isCreate { createSections } else { editSections }
    }
    /// Mini-program club/create steps, in order: 类型 → 活动方向 → 资料 → 城市.
    @ViewBuilder private var createSections: some View {
        Section("club.ops.clubType") {
            Picker("club.ops.clubType", selection: $draft.clubType) {
                ForEach(ClubOperationsCatalog.types, id: \.self) { Text(LocalizedStringKey("club.ops.value." + $0)).tag($0) }
                if !draft.clubType.isEmpty, !ClubOperationsCatalog.types.contains(draft.clubType) { Text(verbatim: draft.clubType).tag(draft.clubType) }
            }.pickerStyle(.inline).labelsHidden().accessibilityIdentifier("club.ops.clubType")
        }
        Section {
            directionToggles
        } header: { Text("club.ops.directions") } footer: { Text("club.ops.directionsCount \(draft.activityPrefs.count)") }
        Section("club.ops.profile") {
            field("name", text: $draft.name)
            field("description", text: $draft.description, axis: .vertical)
        }
        Section("club.ops.city") {
            field("city", text: $draft.city)
            field("keywords", text: $draft.keywords)
            field("style", text: $draft.style)
        }
    }
    /// Mini-program cy-scene-club-edit order: 基础信息 → 俱乐部介绍 → 定位 → 会员经营配置.
    @ViewBuilder private var editSections: some View {
        Section("club.ops.basics") {
            // cy-scene-club-edit admin-note: administrators may only edit display information.
            if !isOwner { Text("club.ops.adminNote").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("club.ops.adminNote") }
            field("name", text: $draft.name)
            field("city", text: $draft.city)
            field("keywords", text: $draft.keywords)
            field("style", text: $draft.style)
        }
        Section("club.ops.introduction") {
            field("description", text: $draft.description, axis: .vertical)
        }
        Section("club.ops.positioning") {
            ClubProfileChoiceControl(kind: .type, draft: $draft, context: choiceContext, isCurrent: choiceIsCurrent, controller: choiceController)
            ClubProfileChoiceControl(kind: .directions, draft: $draft, context: choiceContext, isCurrent: choiceIsCurrent, controller: choiceController)
        }
        if !isOwner {
            // Locked card instead of disabled toggles, echoing the current owner-only values.
            Section("club.ops.signupSettings") {
                Text("club.ops.locked.title").font(.subheadline.bold())
                lockedCurrent.font(.footnote).accessibilityIdentifier("club.ops.locked.current")
            }
        } else {
            Section("club.ops.signupSettings") {
                Toggle("club.ops.prioritySignup", isOn: $draft.prioritySignupEnabled).accessibilityIdentifier("club.ops.prioritySignup")
                if joinPolicySupported {
                    Toggle("club.ops.joinReview", isOn: Binding(get: { draft.joinPolicy == 1 }, set: { draft.joinPolicy = $0 ? 1 : 0 }))
                        .accessibilityIdentifier("club.ops.joinPolicy")
                }
                LabeledContent {
                    field("quota", text: $draft.memberReservedQuota).keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 96)
                } label: {
                    Text("club.ops.quota").accessibilityIdentifier("clubQuota.visibleLabel")
                }
            }
        }
    }
    @ViewBuilder private var directionToggles: some View {
        ForEach(ClubOperationsCatalog.directions, id: \.self) { value in
            Toggle(isOn: Binding(get: { draft.activityPrefs.contains(value) }, set: { enabled in
                if enabled { if draft.activityPrefs.count < 3 { draft.activityPrefs.append(value) } }
                else { draft.activityPrefs.removeAll { $0 == value } }
            })) { Text(LocalizedStringKey("club.ops.value." + value)) }
            .disabled(!draft.activityPrefs.contains(value) && draft.activityPrefs.count >= 3)
        }
        if draft.activityPrefs.contains(where: { !ClubOperationsCatalog.directions.contains($0) }) {
            Text(verbatim: draft.activityPrefs.filter { !ClubOperationsCatalog.directions.contains($0) }.joined(separator: ", "))
        }
    }
    private var lockedCurrent: Text {
        let quota = Int(draft.memberReservedQuota) ?? 0
        var text = Text("club.ops.locked.current") + Text(verbatim: " ")
            + Text(draft.prioritySignupEnabled ? "club.ops.locked.priority.on" : "club.ops.locked.priority.off")
        if joinPolicySupported {
            text = text + Text(verbatim: " · ") + Text(draft.joinPolicy == 1 ? "club.ops.locked.join.on" : "club.ops.locked.join.off")
        }
        return text + Text(verbatim: " · ") + Text("club.ops.locked.quota \(quota)")
    }
    private func field(_ key: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        TextField(LocalizedStringKey("club.ops." + key), text: text, axis: axis)
            .accessibilityLabel(Text(LocalizedStringKey("club.ops." + key)))
            .accessibilityIdentifier("club.ops.field." + key)
    }
}

@MainActor final class ClubCreateWorkspaceDriver {
    let target: ClubOperationsTarget
    let access: any ClubOperationsAccess
    let coordinator: ClubOperationsCoordinator
    var identity: ClubReadIdentity?
    var requestedTab: String?
    private(set) var snapshot: ClubOperationsSnapshot?
    private(set) var draft = ClubOperationsDraft()
    private(set) var baseline = ClubOperationsDraft()
    private(set) var state: ClubOperationsState = .idle
    private(set) var loading = false
    private(set) var readbackUnavailable = false
    private(set) var artworkRevision = UUID()
    private(set) var createReceiptIdentity: ClubReadIdentity?
    private(set) var createReceiptClubID: Int?
    private(set) var readbackIdentity: ClubReadIdentity?
    private(set) var enteredManageDestination: ClubCreateToManageDestination?
    let ownerID = UUID()

    init(
        target: ClubOperationsTarget = .create,
        identity: ClubReadIdentity?,
        access: any ClubOperationsAccess,
        coordinator: ClubOperationsCoordinator,
        requestedTab: String? = ClubWorkspaceTab.manage.rawValue
    ) {
        self.target = target
        self.identity = identity
        self.access = access
        self.coordinator = coordinator
        self.requestedTab = requestedTab
    }

    var createToManageFlow: ClubCreateToManageFlowState {
        ClubOperationsWorkspaceView.makeCreateToManageFlow(
            access: access,
            snapshot: snapshot,
            readbackUnavailable: readbackUnavailable,
            createReceiptIdentity: createReceiptIdentity,
            createReceiptClubID: createReceiptClubID,
            currentIdentity: identity,
            readbackIdentity: readbackIdentity,
            requestedTab: requestedTab,
            enteredManageDestination: enteredManageDestination
        )
    }

    func load() async throws {
        guard let identity, access.isConfigured else { return }
        let result = try await access.snapshot(target: target)
        guard access.identity == identity, result.target == target else { throw ClubOperationsBlock.changed }
        snapshot = result
        state = coordinator.state(target: target)
    }

    func prepare(_ command: ClubOperationsCommand) async throws -> ClubOperationsReview {
        guard let identity else { throw APIError.unauthorized }
        let pending = try await coordinator.prepare(command, target: target, expectedIdentity: identity, ownerID: ownerID)
        state = coordinator.state(target: target)
        return pending
    }

    func confirm(_ pending: ClubOperationsReview) async {
        ClubOperationsWorkspaceView.performBeginConfirm(
            pending,
            target: target,
            snapshot: &snapshot,
            readbackUnavailable: &readbackUnavailable,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity,
            enteredManageDestination: &enteredManageDestination
        )
        await coordinator.confirm(pending)
        guard !Task.isCancelled else { return }
        ClubOperationsWorkspaceView.performFinishConfirm(
            pending,
            target: target,
            identity: identity,
            access: access,
            coordinator: coordinator,
            snapshot: &snapshot,
            draft: &draft,
            baseline: &baseline,
            state: &state,
            readbackUnavailable: &readbackUnavailable,
            artworkRevision: &artworkRevision,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity
        )
    }

    func readBack() async {
        guard let identity else { return }
        loading = true
        await coordinator.readBack(target: target, ownerID: ownerID)
        guard !Task.isCancelled else { return }
        ClubOperationsWorkspaceView.performFinishReadBack(
            target: target,
            identity: identity,
            access: access,
            coordinator: coordinator,
            loading: &loading,
            snapshot: &snapshot,
            draft: &draft,
            baseline: &baseline,
            state: &state,
            readbackUnavailable: &readbackUnavailable,
            artworkRevision: &artworkRevision,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity
        )
    }

    func acceptReadback() {
        ClubOperationsWorkspaceView.performAcceptReadback(
            target: target,
            identity: identity,
            access: access,
            coordinator: coordinator,
            snapshot: &snapshot,
            draft: &draft,
            baseline: &baseline,
            readbackUnavailable: &readbackUnavailable,
            artworkRevision: &artworkRevision,
            createReceiptIdentity: &createReceiptIdentity,
            createReceiptClubID: &createReceiptClubID,
            readbackIdentity: &readbackIdentity
        )
    }

    @discardableResult
    func enterClubManagement(requestedTab overrideTab: String? = nil) -> ClubCreateToManageDestination? {
        ClubOperationsWorkspaceView.performEnterClubManagement(
            access: access,
            snapshot: snapshot,
            readbackUnavailable: readbackUnavailable,
            createReceiptIdentity: createReceiptIdentity,
            createReceiptClubID: createReceiptClubID,
            currentIdentity: identity,
            readbackIdentity: readbackIdentity,
            requestedTab: overrideTab ?? requestedTab,
            enteredManageDestination: &enteredManageDestination
        )
    }
}
