import SwiftUI

/// Canonical workspace tabs for post-create club management routing.
/// Validates `requestedTab` and safely falls back to `.overview` when nil, unknown, or unverified.
public enum ClubWorkspaceTab: String, CaseIterable, Equatable, Sendable {
    case posts
    case events
    case overview
    case manage

    public static let defaultFallback: ClubWorkspaceTab = .overview

    public static func validate(requestedTab: String?) -> ClubWorkspaceTab {
        guard let raw = requestedTab?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty,
              let tab = ClubWorkspaceTab(rawValue: raw) else {
            return .overview
        }
        return tab
    }

    public static func validate(_ requestedTab: ClubWorkspaceTab?) -> ClubWorkspaceTab {
        requestedTab ?? .overview
    }

    public static func resolve(requestedTab: String?, canEnterManagement: Bool = true) -> ClubWorkspaceTab {
        let validated = validate(requestedTab: requestedTab)
        if validated == .manage && !canEnterManagement {
            return .overview
        }
        return validated
    }

    public static func resolve(requestedTab: ClubWorkspaceTab?, canEnterManagement: Bool = true) -> ClubWorkspaceTab {
        let validated = validate(requestedTab)
        if validated == .manage && !canEnterManagement {
            return .overview
        }
        return validated
    }
}

/// Production gate for club creation ("不扩 Club28"): keeps the 28-subview Club feature catalog
/// fixed and defaults to closed (`writeAvailability == .unverified`, `isConfigured == false`)
/// when no live backend or explicit approval is configured.
public struct ClubCreationGate: Equatable, Sendable {
    public static let club28SubviewLimit = 28
    public static let productionDefault = ClubCreationGate(
        isConfigured: false,
        writeAvailability: .unverified,
        catalogSubviewCount: club28SubviewLimit
    )

    public let isConfigured: Bool
    public let writeAvailability: ClubOperationsWriteAvailability
    public let catalogSubviewCount: Int

    public init(
        isConfigured: Bool = false,
        writeAvailability: ClubOperationsWriteAvailability = .unverified,
        catalogSubviewCount: Int = Self.club28SubviewLimit
    ) {
        self.isConfigured = isConfigured
        self.writeAvailability = writeAvailability
        self.catalogSubviewCount = catalogSubviewCount
    }

    @MainActor
    public init(access: any ClubOperationsAccess) {
        self.init(
            isConfigured: access.isConfigured,
            writeAvailability: access.writeAvailability,
            catalogSubviewCount: Self.club28SubviewLimit
        )
    }

    public var withinClub28Scope: Bool {
        catalogSubviewCount == Self.club28SubviewLimit
    }

    public var isCreationAllowed: Bool {
        isConfigured && withinClub28Scope && (writeAvailability == .approved || writeAvailability == .syntheticOnly)
    }

    public var isBlocked: Bool {
        !isCreationAllowed
    }

    public var bilingualGateCopy: String {
        if isCreationAllowed {
            return "俱乐部创建门控已授权（不扩 Club28）/ Club creation gate authorized (within Club28 scope)."
        }
        return "俱乐部创建门控未开启，暂不可进入俱乐部管理 / Club creation gate is closed; entering Club Management is blocked."
    }
}

/// Verified post-create destination for jumping from club creation into club management.
public struct ClubCreateToManageDestination: Equatable, Identifiable, Sendable {
    public let accountId: Int
    public let clubId: Int
    public let tab: ClubWorkspaceTab
    public var id: String { "\(accountId):\(clubId):\(tab.rawValue)" }

    public init(accountId: Int, clubId: Int, tab: ClubWorkspaceTab = .manage) {
        self.accountId = accountId
        self.clubId = clubId
        self.tab = tab
    }
}

public enum ClubCreateToManageBlockReason: String, Equatable, Sendable {
    case gateBlocked
    case awaitingConfirmedReceipt
    case readbackFailed
    case accountMismatch
    case clubIdMismatch
}

/// Post-create closure state machine:
/// Confirmed Receipt -> Same-Account Readback Verification (`accountId` & `clubId` match) -> Explicit "Enter Club Management" action.
public struct ClubCreateToManageFlowState: Equatable, Sendable {
    public static let enterManagementButtonTitle = "进入俱乐部管理 / Enter Club Management"

    public let gate: ClubCreationGate
    public let receiptAccountId: Int?
    public let receiptClubId: Int?
    public let currentAccountId: Int?
    public let readbackAccountId: Int?
    public let readbackOwnedClubIds: [Int]
    public let readbackSucceeded: Bool
    public let requestedTab: String?
    public private(set) var enteredDestination: ClubCreateToManageDestination?

    public init(
        gate: ClubCreationGate = .productionDefault,
        receiptAccountId: Int? = nil,
        receiptClubId: Int? = nil,
        currentAccountId: Int? = nil,
        readbackAccountId: Int? = nil,
        readbackOwnedClubIds: [Int] = [],
        readbackSucceeded: Bool = false,
        requestedTab: String? = ClubWorkspaceTab.manage.rawValue,
        enteredDestination: ClubCreateToManageDestination? = nil
    ) {
        self.gate = gate
        self.receiptAccountId = receiptAccountId
        self.receiptClubId = receiptClubId
        self.currentAccountId = currentAccountId
        self.readbackAccountId = readbackAccountId
        self.readbackOwnedClubIds = readbackOwnedClubIds
        self.readbackSucceeded = readbackSucceeded
        self.requestedTab = requestedTab
        self.enteredDestination = enteredDestination
    }

    public var hasConfirmedReceipt: Bool {
        guard !gate.isBlocked,
              let receiptAccountId, receiptAccountId > 0,
              let receiptClubId, receiptClubId > 0 else {
            return false
        }
        return true
    }

    public var isSameAccountVerified: Bool {
        guard let receiptAccountId, receiptAccountId > 0,
              let currentAccountId, currentAccountId == receiptAccountId,
              let readbackAccountId, readbackAccountId == receiptAccountId else {
            return false
        }
        return true
    }

    public var isClubIdVerified: Bool {
        guard readbackSucceeded,
              let receiptClubId, receiptClubId > 0 else {
            return false
        }
        return readbackOwnedClubIds.contains(receiptClubId)
    }

    public var isSameAccountReadbackVerified: Bool {
        hasConfirmedReceipt && isSameAccountVerified && isClubIdVerified
    }

    public var canEnterManagement: Bool {
        isSameAccountReadbackVerified
    }

    public var blockReason: ClubCreateToManageBlockReason? {
        if gate.isBlocked {
            return .gateBlocked
        }
        guard let receiptAccountId, receiptAccountId > 0,
              let receiptClubId, receiptClubId > 0 else {
            return .awaitingConfirmedReceipt
        }
        if currentAccountId != receiptAccountId || (readbackAccountId != nil && readbackAccountId != receiptAccountId) {
            return .accountMismatch
        }
        if !readbackSucceeded || readbackAccountId == nil {
            return .readbackFailed
        }
        if !readbackOwnedClubIds.contains(receiptClubId) {
            return .clubIdMismatch
        }
        return nil
    }

    public var validatedTab: ClubWorkspaceTab {
        ClubWorkspaceTab.resolve(requestedTab: requestedTab, canEnterManagement: canEnterManagement)
    }

    public var bilingualStatusCopy: String {
        switch blockReason {
        case .gateBlocked:
            return "俱乐部创建门控未开启，暂不可进入俱乐部管理 / Club creation gate is closed; entering Club Management is blocked."
        case .awaitingConfirmedReceipt:
            return "等待俱乐部创建确认回执 / Awaiting confirmed club creation receipt."
        case .accountMismatch:
            return "账号已变更或不匹配，已拦截进入俱乐部管理 / Account mismatch detected; entering Club Management is blocked."
        case .readbackFailed:
            return "同账号回读校验未通过，暂不可进入俱乐部管理 / Same-account readback verification failed; entering Club Management is blocked."
        case .clubIdMismatch:
            return "俱乐部 ID 回读不匹配，已拦截进入俱乐部管理 / Club ID readback mismatch; entering Club Management is blocked."
        case nil:
            let clubId = receiptClubId ?? 0
            return "同账号回读已确认（俱乐部 #\(clubId)），可进入俱乐部管理 / Same-account readback verified (Club #\(clubId)); ready to enter Club Management."
        }
    }

    @discardableResult
    public mutating func enterClubManagement(requestedTab overrideTab: String? = nil) -> ClubCreateToManageDestination? {
        guard canEnterManagement,
              let accountId = receiptAccountId,
              let clubId = receiptClubId else {
            enteredDestination = nil
            return nil
        }
        let resolvedTab = ClubWorkspaceTab.resolve(
            requestedTab: overrideTab ?? requestedTab,
            canEnterManagement: true
        )
        let destination = ClubCreateToManageDestination(accountId: accountId, clubId: clubId, tab: resolvedTab)
        enteredDestination = destination
        return destination
    }
}

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
    var createToManageFlow: ClubCreateToManageFlowState {
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
            currentAccountId: identity?.accountID,
            readbackAccountId: readbackIdentity?.accountID,
            readbackOwnedClubIds: ownedIDs,
            readbackSucceeded: readbackSucceeded,
            requestedTab: requestedTab,
            enteredDestination: enteredManageDestination
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
            Section {
                if value.accountRole != "club", let hostApplication {
                    Text("club.ops.leaderRequired.apply")
                    ClubCreateHostApplicationLink(identity: identity, governance: hostApplication)
                } else {
                    Text(value.accountRole != "club" ? "club.ops.leaderRequired" : "club.ops.clubLimit")
                }
            }
        } else {
            ClubOperationsProfileForm(draft: $draft, isCreate: target == .create, isOwner: value.profile?.club.isOwner == true, joinPolicySupported: value.profile?.club.joinPolicySupported == true,
                choiceContext: profileChoiceContext, choiceIsCurrent: profileChoiceIsCurrent, choiceController: profileChoice)
                .disabled(loading || state.locksForm)
            Section {
                Button("club.ops.reviewProfile") {
                    let command: ClubOperationsCommand
                    if let original = value.profile { command = .update(draft, original: original) }
                    else { command = .create(draft) }
                    Task { await prepare(command) }
                }
                .disabled(loading || state.locksForm || (target != .create && !dirty))
                .accessibilityIdentifier("club.ops.reviewProfile")
                Text("club.ops.mediaUnavailable").font(.footnote).foregroundStyle(.secondary)
            }
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
                Text("club.ops.settingsHint").font(.footnote).foregroundStyle(.secondary)
            }
            Section("club.ops.memberRoles") {
                if value.members.isEmpty { Text("club.ops.membersUnavailable") }
                ForEach(value.members) { member in
                    if !member.isOwner, member.memberId != identity?.accountID, [0, 1].contains(member.role) {
                        Button {
                            Task { await prepare(.memberRole(memberID: member.id, admin: !member.isAdmin, previousRole: member.role)) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: member.trimmedNickname ?? "#\(member.id)")
                                Text(member.isAdmin ? "club.ops.removeAdmin" : "club.ops.makeAdmin").font(.caption)
                            }
                        }
                        .disabled(loading || state.locksForm)
                        .accessibilityIdentifier("club.ops.member.\(member.id)")
                    } else {
                        LabeledContent { Text(member.isOwner ? "club.ops.owner" : "club.ops.unknownRole") } label: { Text(verbatim: member.trimmedNickname ?? "#\(member.id)") }
                    }
                }
                Text("club.ops.adminHint").font(.footnote).foregroundStyle(.secondary)
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
                if let id = receipt.clubID { LabeledContent("club.ops.clubID") { Text(id, format: .number) } }
            case .rejected(let failure):
                Text("club.ops.rejected")
                if let message = failure.message { Text(verbatim: message) }
            case .outcomeUnknown: Text("club.ops.outcomeUnknown").accessibilityIdentifier("club.ops.outcomeUnknown")
            default: EmptyView()
            }
            if readbackUnavailable { Text("club.ops.readbackUnavailable") }
            if case .outcomeUnknown = state {
                Button("club.ops.readBack") { Task { await readBack() } }
                    .disabled(loading).accessibilityIdentifier("club.ops.readBack")
            }
            if snapshot == nil, identity != nil, access.isConfigured, !loading {
                Button("club.ops.retryRead") { Task { await load() } }.accessibilityIdentifier("club.ops.retryRead")
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
        Text(verbatim: flow.bilingualStatusCopy)
            .font(.footnote)
            .foregroundStyle(flow.canEnterManagement ? .primary : .secondary)
            .accessibilityIdentifier("clubCreateManage.status")
        Button {
            var nextFlow = createToManageFlow
            if let destination = nextFlow.enterClubManagement(requestedTab: requestedTab) {
                enteredManageDestination = destination
                onEnterClubManagement?(destination)
            }
        } label: {
            Text(verbatim: ClubCreateToManageFlowState.enterManagementButtonTitle)
        }
        .disabled(loading || !flow.canEnterManagement)
        .accessibilityIdentifier("clubCreateManage.enterManagement")
        if let destination = enteredManageDestination,
           flow.canEnterManagement,
           destination.accountId == identity?.accountID {
            NavigationLink {
                ClubOperationsWorkspaceView(
                    target: .club(destination.clubId),
                    identity: identity,
                    access: access,
                    coordinator: coordinator,
                    hostApplication: hostApplication
                )
            } label: {
                Text(verbatim: "已就绪：俱乐部 #\(destination.clubId) 管理工作台（分栏：\(destination.tab.rawValue)）/ Ready: Club #\(destination.clubId) Management Workspace (Tab: \(destination.tab.rawValue))")
                    .font(.footnote)
            }
            .accessibilityIdentifier("clubCreateManage.destination")
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
        snapshot = nil; readbackUnavailable = false; readbackIdentity = nil; enteredManageDestination = nil
        if target == .create { createReceiptIdentity = pending.identity; createReceiptClubID = nil }
        await coordinator.confirm(pending)
        guard run == generation, access.identity == pending.identity, !Task.isCancelled else { return }
        state = coordinator.state(target: target)
        if target == .create, case .acknowledged(let receipt) = state {
            createReceiptIdentity = pending.identity
            createReceiptClubID = receipt.clubID
        }
        acceptReadback()
    }
    @MainActor private func readBack() async {
        guard let identity, !loading else { return }
        generation &+= 1; let run = generation; loading = true
        await coordinator.readBack(target: target, ownerID: ownerID)
        guard run == generation, access.identity == identity, !Task.isCancelled else { return }
        loading = false; acceptReadback(); state = coordinator.state(target: target)
    }
    private func acceptReadback() {
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
        Section("club.ops.profile") {
            // cy-scene-club-edit admin-note: administrators may only edit display information.
            if !isCreate && !isOwner { Text("club.ops.adminNote").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("club.ops.adminNote") }
            field("name", text: $draft.name)
            field("city", text: $draft.city)
            if isCreate {
            Picker("club.ops.clubType", selection: $draft.clubType) {
                Text("club.ops.chooseType").tag("")
                ForEach(ClubOperationsCatalog.types, id: \.self) { Text(LocalizedStringKey("club.ops.value." + $0)).tag($0) }
                if !draft.clubType.isEmpty, !ClubOperationsCatalog.types.contains(draft.clubType) { Text(verbatim: draft.clubType).tag(draft.clubType) }
            }.accessibilityIdentifier("club.ops.clubType")
            } else {
                ClubProfileChoiceControl(kind: .type, draft: $draft, context: choiceContext, isCurrent: choiceIsCurrent, controller: choiceController)
            }
            field("description", text: $draft.description, axis: .vertical)
            field("keywords", text: $draft.keywords)
            field("style", text: $draft.style)
        }
        Section("club.ops.directions") {
            if isCreate {
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
            Text("club.ops.directionsHint").font(.footnote).foregroundStyle(.secondary)
            } else {
                ClubProfileChoiceControl(kind: .directions, draft: $draft, context: choiceContext, isCurrent: choiceIsCurrent, controller: choiceController)
            }
        }
        if !isCreate && !isOwner {
            // Locked card instead of disabled toggles, echoing the current owner-only values.
            Section("club.ops.signupSettings") {
                Text("club.ops.locked.title").font(.subheadline.bold())
                Text("club.ops.locked.body").font(.footnote).foregroundStyle(.secondary)
                lockedCurrent.font(.footnote).accessibilityIdentifier("club.ops.locked.current")
            }
        }
        if !isCreate && isOwner {
            Section("club.ops.signupSettings") {
                Toggle("club.ops.prioritySignup", isOn: $draft.prioritySignupEnabled).accessibilityIdentifier("club.ops.prioritySignup")
                VStack(alignment: .leading, spacing: 6) {
                    Text("club.ops.quota").font(.subheadline)
                        .accessibilityIdentifier("clubQuota.visibleLabel")
                    field("quota", text: $draft.memberReservedQuota).keyboardType(.numberPad)
                }
                if joinPolicySupported {
                    Picker("club.ops.joinPolicy", selection: $draft.joinPolicy) {
                        Text("club.ops.joinDirect").tag(0); Text("club.ops.joinReview").tag(1)
                    }.accessibilityIdentifier("club.ops.joinPolicy")
                } else { Text("club.ops.joinPolicyUnavailable").font(.footnote) }
            }
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
