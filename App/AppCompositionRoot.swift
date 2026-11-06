import Foundation
import SwiftUI

/// Reviewed in source/composition, never reconstructed from a login response or remote flags.
/// Adding a host is insufficient: native identity, capability evidence and read grants are separate.
struct ReviewedAppDeployment {
    let regional: RegionalConfiguration
    let storageScope: RegionalSessionStorageScope
    let reads: Set<ReadGrant>
    let privateHome: PrivateHomeTransportGrant?
    let contentDetails: SignedInContentDetailReadApproval?
    /// Explicit local endpoint approval. Absence is unavailable, never inferred from login.
    let nativeChannelAppeals: NativeChannelAppealPolicyStore?
    /// Independent original-request source. Nil never authorizes reads, consent or deletion.
    let accountDeregistrationOriginalSource: AccountDeregistrationOriginalConfigurationSource?
    enum ReadGrant: Hashable {
        case homeAndSearch
        case manualMap
        case publicMapLayers
        /// Only the public route-template shelf and its projected detail, not standalone games.
        case publicTopicTemplateCatalogAndDetail
        /// Original public official list/detail only; a selected source is independently required.
        case officialPublicEventCatalogAndDetail
        /// Authenticated progress projection only; runtime approval is independently required.
        case playNodesAndRouteState
    }

    init(market: RegionalMarket, baseURL: String, approvedBaseURLs: [RegionalMarket: Set<String>],
         verifiedCapabilities: Set<RegionalCapability>, bundleIdentifier: String, realm: String,
         reads: Set<ReadGrant> = [], contentDetails: SignedInContentDetailReadApproval? = nil, privateHome: PrivateHomeTransportGrant? = nil,
         nativeChannelAppeals: NativeChannelAppealPolicyStore? = nil,
         accountDeregistrationOriginalSource: AccountDeregistrationOriginalConfigurationSource? = nil) throws {
        regional = try RegionalConfiguration(market: market, baseURL: baseURL,
            approvedBaseURLs: approvedBaseURLs, verifiedCapabilities: verifiedCapabilities)
        storageScope = try RegionalSessionStorageScope(configuration: regional, bundleIdentifier: bundleIdentifier, realm: realm)
        guard privateHome == nil || privateHome?.storageScope == storageScope else { throw APIError.invalidConfiguration }
        self.reads = reads; self.privateHome = privateHome; self.contentDetails = contentDetails
        self.nativeChannelAppeals = nativeChannelAppeals
        self.accountDeregistrationOriginalSource = accountDeregistrationOriginalSource
    }
}

/// Explicit host-owned read grant. No login response or feature flag constructs this value.
struct InvoiceLaunchReadApproval {
    let context: RuntimeDependencyContext
    let revision = UUID()
    let originalReceipts: Bool
    /// Separately reviewed #725 command result reads only. No deployment is inferred.
    let commandReceiptRead: Bool
    init(context: RuntimeDependencyContext, originalReceipts: Bool = false, commandReceiptRead: Bool = false) throws {
        guard context.market == .china, context.role.utf8.elementsEqual(context.session.role.utf8) else {
            throw InvoiceLaunchIssue.invalid
        }
        self.context = context; self.originalReceipts = originalReceipts; self.commandReceiptRead = commandReceiptRead
    }
    func matches(_ current: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(context, current)
            && context.session.role.utf8.elementsEqual(current.session.role.utf8)
    }
}

@MainActor protocol AppTokenStorage {
    func read() throws -> String?
    func write(_ token: String) throws
    func clear() throws
}
extension KeychainTokenStore: AppTokenStorage {}

/// Local factories are injected together, preventing test sessions from touching the real vault
/// or logout tombstones. Unknown operation records are never cleared on session changes.
@MainActor struct AppScopedStorageFactory {
    /// Opt-in original metadata storage only. No default directory or factory is installed.
    var clubWelcomeNoteOriginalJournalDirectory: URL? = nil
    var clubWelcomeNoteOriginalJournalFactory: (@MainActor () -> ClubWelcomeNoteOriginalJournal?)? = nil
    let defaults: UserDefaults
    let tokenStore: (RegionalSessionStorageScope?) -> any AppTokenStorage
    let privateHomeKeychain: (any PrivateHomeKeychainPrimitive)?
    let playRecovery: PlayRecoveryConstruction
    let invoiceJournal: (RegionalSessionStorageScope) -> any InvoiceLaunchStorage
#if DEBUG
    /// Explicit fixture-only override. Ordinary and Release composition keep system storage.
    var syntheticWorkshopCreatorPendingRecoveryStorage: (any TemplateAuthoringStorage)? = nil
#endif
    init(defaults: UserDefaults = .standard,
         tokenStore: @escaping (RegionalSessionStorageScope?) -> any AppTokenStorage = { KeychainTokenStore(scope: $0) },
         privateHomeKeychain: (any PrivateHomeKeychainPrimitive)? = nil,
         playRecovery: PlayRecoveryConstruction = .system,
         invoiceJournal: @escaping (RegionalSessionStorageScope) -> any InvoiceLaunchStorage = { TemplateAuthoringSecureStorage(scope: $0) }) {
        self.defaults = defaults; self.tokenStore = tokenStore; self.privateHomeKeychain = privateHomeKeychain
        self.playRecovery = playRecovery; self.invoiceJournal = invoiceJournal
    }
    /// Existing adapters already use deployment/account-scoped owner keys. Preserve the
    /// persisted key format so an unknown operation can never disappear during migration.
    func operationJournal() -> any OperationPendingJournal {
        OperationDefaultsJournal(defaults: defaults)
    }
}

@MainActor struct AppCompositionRoot {
    /// Default empty. No deployment, login or another read grant issues this source.
    let officialPublicEventReadSelection = OfficialPublicEventReadSelection()
    // Proposed read-only wiring. No grant is issued by shipped composition.
    var freeExploreBundleReadApproval: @MainActor (RuntimeDependencyContext) -> FreeExploreBundleReadApproval? = { _ in nil }
    var freeExploreBundleReadStorage: @MainActor (RegionalSessionStorageScope) -> any TemplateAuthoringStorage = { TemplateAuthoringSecureStorage(scope: $0) }
    func makeFreeExploreBundleReadHost(registrationID: Int64, context: RuntimeDependencyContext,
        scope: RegionalSessionStorageScope, currentContext: @escaping () -> RuntimeDependencyContext?,
        originCurrent: @escaping () -> Bool, unauthorized: @escaping () -> Void) -> FreeExploreBundleReadHost? {
        guard let reviewed, reviewed.storageScope == scope, reviewed.regional.market == context.market,
              reviewed.regional.apiConfiguration?.baseURL == context.baseURL,
              context.session.namespace == scope.service else { return nil }
        return FreeExploreBundleReadHost(registrationID: registrationID, accountID: Int64(context.session.accountID),
            context: context, approval: freeExploreBundleReadApproval(context), currentContext: currentContext,
            currentApproval: { self.freeExploreBundleReadApproval(context) }, originCurrent: originCurrent,
            storage: freeExploreBundleReadStorage(scope), transport: makeTransport(), unauthorized: unauthorized)
    }
    /// Local facts/original-receipt presentation only. No game runtime or read grant is created.
    var merchantGamePlayerDestination: (@MainActor (MerchantGamePlayerCoordinator, AnyView?) -> AnyView)? = {
        AnyView(MerchantGamePlayerView(coordinator: $0, chat: $1))
    }
    var merchantGamePlayerReadGrant: @MainActor (RuntimeDependencyContext) -> MerchantGamePlayerReadGrant? = { _ in nil }
    /// Independently issued original-result GET grant. Never inferred from legacy write approval.
    var merchantOfferWithdrawalOriginalReadApproval: @MainActor (RuntimeDependencyContext) -> MerchantOfferWithdrawalOriginalReadApproval? = { _ in nil }
    func makeMerchantOfferWithdrawalOriginalReadTransport(approval: MerchantOfferWithdrawalOriginalReadApproval,
        current: @escaping () -> Bool) -> (any HTTPTransport)? {
        let context = approval.context
        guard current(), approval.matches(context), let reviewed,
              reviewed.regional.market == context.market,
              reviewed.regional.apiConfiguration?.baseURL == context.baseURL,
              reviewed.storageScope.service == context.session.namespace,
              merchantOfferWithdrawalOriginalReadApproval(context)?.revision == approval.revision,
              let api = try? APIConfiguration(baseURL: context.baseURL) else { return nil }
        return MerchantOfferWithdrawalOriginalReadTransport(api: api, approval: approval, underlying: makeTransport(), current: current)
    }
    enum DeploymentState { case unconfigured, incompatibleBuild, reviewed(ReviewedAppDeployment) }
    enum ReadSurface { case home, contentDetail }
    enum ReadAvailability: Equatable {
        case available, deploymentMissing, buildMismatch, homeReadNotApproved, detailReadNotApproved
        case signInRequired, sessionUnavailable, serviceUnavailable
        var messageKey: String? {
            switch self {
            case .available: return nil
            case .deploymentMissing: return "readConfiguration.deploymentMissing"
            case .buildMismatch: return "readConfiguration.buildMismatch"
            case .homeReadNotApproved: return "readConfiguration.homeReadNotApproved"
            case .detailReadNotApproved: return "readConfiguration.detailReadNotApproved"
            case .signInRequired: return "readConfiguration.signInRequired"
            case .sessionUnavailable: return "readConfiguration.sessionUnavailable"
            case .serviceUnavailable: return "readConfiguration.serviceUnavailable"
            }
        }
    }
    let invoiceLaunchReadApproval: @MainActor (RuntimeDependencyContext) -> InvoiceLaunchReadApproval?
    let clubBadgeManagementApproval: @MainActor (RuntimeDependencyContext) -> ClubBadgeManagementApproval?
    let merchantReviewOriginalReadApproval: @MainActor (RuntimeDependencyContext) -> MerchantReviewOriginalReadApproval?
    let deployment: DeploymentState
    let storage: AppScopedStorageFactory
    private let makeTransport: () -> any HTTPTransport
    /// Distinct endpoint permissions, neither inferred from login nor ordinary club writes.
    var clubWelcomeNoteWriteApproval: @MainActor (RuntimeDependencyContext) -> OperationEndpointApproval? = { _ in nil }
    var clubWelcomeNoteReceiptApproval: @MainActor (RuntimeDependencyContext) -> OperationEndpointApproval? = { _ in nil }
    func makeClubWelcomeNoteRuntime(transport: CompositionHTTPTransport,
                                   current: @escaping @MainActor () -> RuntimeDependencyContext?) -> ClubWelcomeNoteRuntime? {
        let original: ClubWelcomeNoteOriginalJournal
        if let factory = storage.clubWelcomeNoteOriginalJournalFactory {
            // An explicitly supplied unavailable factory must not silently fall back.
            guard let value = factory() else { return nil }; original = value
        } else if let directory = storage.clubWelcomeNoteOriginalJournalDirectory {
            original = ClubWelcomeNoteOriginalJournal(directory: directory)
        } else { return nil }
        let write: () -> OperationEndpointApproval? = {
            guard let context = current() else { return nil }; return clubWelcomeNoteWriteApproval(context)
        }
        let receipt: () -> OperationEndpointApproval? = {
            guard let context = current() else { return nil }; return clubWelcomeNoteReceiptApproval(context)
        }
        // Original journal is mandatory here: this host can never select legacy writes.
        return ClubWelcomeNoteRuntime(
            transport: transport.clubWelcomeNoteDispatchTransport(path: ClubWelcomeNoteService.path, approval: write),
            journal: storage.operationJournal(), approval: write, originalJournal: original,
            receiptTransport: transport.clubWelcomeNoteDispatchTransport(path: ClubWelcomeNoteService.receiptPath, approval: receipt),
            receiptApproval: receipt)
    }
    var clubRoleAssignmentJournalDirectory: URL? = nil
    var clubRoleRevocationJournalDirectory: URL? = nil
    /// Default nil; neither login nor a private-home CRUD grant creates return-home authority.
    var nativeHomeReturnApproval: @MainActor (RuntimeDependencyContext) -> NativeHomeReturnApproval? = { _ in nil }
    func makeNativeHomeReturnTransport(approval: NativeHomeReturnApproval,
        current: @escaping () -> RuntimeDependencyContext?,
        selected: @escaping (RuntimeDependencyContext) -> NativeHomeReturnApproval?) -> (any HTTPTransport)? {
        let context = approval.context
        guard let reviewed, let api = reviewed.regional.apiConfiguration, let home = reviewed.privateHome,
              reviewed.regional.market == context.market, api.baseURL == context.baseURL,
              reviewed.storageScope.service == context.session.namespace,
              home.matches(storageScope: reviewed.storageScope, accountID: context.session.accountID, role: context.role),
              approval.matches(context), current() == context, selected(context)?.revision == approval.revision else { return nil }
        return NativeHomeReturnTransport(approval: approval, underlying: makeTransport(), current: current, selected: selected)
    }
    func makeClubBadgeService(context: RuntimeDependencyContext, clubID: Int, approval: ClubBadgeManagementApproval,
        current: @escaping () -> RuntimeDependencyContext?, unauthorized: @escaping () -> Void) -> ClubBadgeManagementService? {
        guard case .reviewed(let reviewed) = deployment, context.market == .china,
              reviewed.regional.market == context.market,
              reviewed.regional.apiConfiguration?.baseURL == context.baseURL,
              reviewed.storageScope.service == context.session.namespace,
              current() == context, approval.permits(context, clubID: clubID, writing: false),
              clubBadgeManagementApproval(context)?.revision == approval.revision else { return nil }
        let latest = { self.clubBadgeManagementApproval(context) }
        let transport = ClubBadgeScopedTransport(context: context, clubID: clubID, approval: approval,
            underlying: makeTransport(), current: current, currentApproval: latest)
        return ClubBadgeManagementService(context: context, clubID: clubID, transport: transport,
            current: current, approval: { _ in latest() }, unauthorized: unauthorized)
    }
    func makeMerchantReviewOriginalReceiptReader(context: RuntimeDependencyContext,
        approval: MerchantReviewOriginalReadApproval, reader: any MerchantBusinessReading,
        journal: any MerchantBusinessIntentStore, current: @escaping () -> RuntimeDependencyContext?,
        currentSession: @escaping () -> MerchantBusinessSession?,
        unauthorized: @escaping (MerchantBusinessSession) -> Void) -> MerchantReviewOriginalReceiptReader? {
        guard case .reviewed(let reviewed) = deployment,
              context.market == .china, reviewed.regional.market == context.market,
              let api = reviewed.regional.apiConfiguration, api.baseURL == context.baseURL,
              reviewed.storageScope.service == context.session.namespace,
              approval.matches(context) else { return nil }
        let approved: () -> Bool = {
            guard let live = current(), approval.matches(live),
                  let latest = self.merchantReviewOriginalReadApproval(live) else { return false }
            return latest.revision == approval.revision && latest.matches(live)
        }
        return MerchantReviewOriginalReceiptReader(configuration: api,
            transport: makeTransport(), reader: reader, journal: journal, currentSession: currentSession,
            enabled: approved, completionEnabled: { approved() && approval.permitsJournalCompletion },
            onUnauthorized: unauthorized)
    }
    func makeInvoiceLaunchService(context: RuntimeDependencyContext, approval: InvoiceLaunchReadApproval,
                                  current: @escaping () -> RuntimeDependencyContext?,
                                  unauthorized: @escaping () -> Void) -> InvoiceLaunchService? {
        guard case .reviewed(let reviewed) = deployment,
              context.market == .china, reviewed.regional.market == context.market,
              reviewed.regional.apiConfiguration?.baseURL == context.baseURL,
              reviewed.storageScope.service == context.session.namespace,
              context.role.utf8.elementsEqual(context.session.role.utf8), approval.matches(context),
              let session = try? InvoiceLaunchSession(baseURL: context.baseURL, namespace: context.session.namespace,
                  accountID: Int64(context.session.accountID), role: context.role, epoch: context.session.epoch,
                  token: context.session.token) else { return nil }
        let approved: () -> Bool = {
            guard let live = current(), approval.matches(live),
                  let latest = self.invoiceLaunchReadApproval(live) else { return false }
            return latest.revision == approval.revision && latest.matches(live)
        }
        return InvoiceLaunchService(session: session, transport: makeTransport(), enabled: approved,
            mutationsEnabled: { false }, // Read-only first. No write permission is implied.
            originalReceiptsEnabled: { approved() && approval.originalReceipts },
            commandReceiptsEnabled: { approved() && approval.commandReceiptRead }, // Writes remain disabled above.
            current: {
                guard let live = current(), live.market == .china else { return nil }
                return try? InvoiceLaunchSession(baseURL: live.baseURL, namespace: live.session.namespace,
                    accountID: Int64(live.session.accountID), role: live.role, epoch: live.session.epoch,
                    token: live.session.token)
            }, unauthorized: unauthorized)
    }
    /// A dedicated final gate, like the other reviewed transport factories in this root.
    /// Does not widen BusinessRuntimeFactory.additionalRoutes or ordinary composition sends.
    func makeNativeChannelAppealFlow(notice: NativeChannelGovernanceNotice, context: RuntimeDependencyContext,
                                    storage: any ProjectEditDataStorage, locatorStorage: any ProjectEditDataStorage,
                                    current: @escaping () -> Bool, unauthorized: @escaping () -> Void) -> NativeChannelAppealFlow? {
        guard case .reviewed(let reviewed) = deployment, let api = reviewed.regional.apiConfiguration,
              reviewed.regional.market == context.market, api.baseURL == context.baseURL,
              reviewed.storageScope.service == context.session.namespace, let policyStore = reviewed.nativeChannelAppeals else { return nil }
        return NativeChannelAppealRuntime.makeFlow(notice: notice, context: context, policyStore: policyStore,
            underlying: makeTransport(), storage: storage, locatorStorage: locatorStorage, current: current, unauthorized: unauthorized)
    }
    func favoriteRemovalTransport(accesses: [ProfileFavoriteRemovalAccess], context: RuntimeDependencyContext,
                                  collectionScope: UUID, current: @escaping () -> RuntimeDependencyContext?,
                                  currentScope: @escaping () -> UUID?,
                                  select: @escaping (RuntimeDependencyContext, UUID) -> [ProfileFavoriteRemovalAccess]) -> (any HTTPTransport)? {
        guard case .reviewed(let reviewed) = deployment,
              let api = reviewed.regional.apiConfiguration, reviewed.regional.market == context.market,
              api.baseURL == context.baseURL, reviewed.storageScope.service == context.session.namespace,
              !accesses.isEmpty else { return nil }
        return ProfileFavoriteRemovalTransport(accesses: accesses, collectionScope: collectionScope,
            underlying: makeTransport(), current: current, currentScope: currentScope, select: select)
    }

    /// Select independently reviewed approvals for the exact context. This builder must not
    /// turn authentication, roles, or remote booleans into OperationEndpointApproval values.
    let projectStoryAudioUploadApproval: @MainActor (RuntimeDependencyContext) -> ProjectStoryAudioUploadApproval?
    let makeProjectStoryAudioUploadTransport: @MainActor () -> any HTTPTransport
    let projectTopicImageUploadApproval: @MainActor (RuntimeDependencyContext) -> ProjectTopicImageUploadApproval?
    let makeProjectTopicImageUploadTransport: @MainActor () -> any HTTPTransport
    let projectStoryImageUploadApproval: @MainActor (RuntimeDependencyContext) -> ProjectStoryImageUploadApproval?
    let makeProjectStoryImageUploadTransport: @MainActor () -> any HTTPTransport
    let projectNodeImageUploadApproval: @MainActor (RuntimeDependencyContext) -> ProjectNodeImageUploadApproval?
    let makeProjectNodeImageUploadTransport: @MainActor () -> (any ProjectNodeImageDispatching)?
    let ownedTopicCoverApproval: @MainActor (RuntimeDependencyContext) -> OwnedTopicCoverApproval?
    let makeOwnedTopicCoverTransport: @MainActor (Int) -> any HTTPTransport
    let ownedOrderReadApproval: @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval?
    let manualMapReadApproval: @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval?
    var templateAuthoringOriginalReadApproval: @MainActor (RuntimeDependencyContext) -> OperationEndpointApproval? = { _ in nil }
    var templateAuthoringOriginalSubmitApproval: @MainActor (RuntimeDependencyContext) -> OperationEndpointApproval? = { _ in nil }
    let templateShelfReadApproval: @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval?
    let messagingHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval?
    let roamSessionFactReadAccess: @MainActor (RuntimeDependencyContext) -> RoamSessionFactReadAccess?
    let roamNearbyEventsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamNearbyEventsReadAccess?
    let roamNearbyPlayersReadAccess: @MainActor (RuntimeDependencyContext) -> RoamNearbyPlayersReadAccess?
    /// Roam home 附近活动 peek and passport/private read tools. No reviewed default exists; nil keeps them unavailable, and writes remain strictly independent.
    let roamEntryNearbyReadAccess: @MainActor (RuntimeDependencyContext) -> RoamEntryNearbyReadAccess?
    let roamReceivedStampReadAccess: @MainActor (RuntimeDependencyContext) -> RoamReceivedStampReadAccess?
    let roamPassportHistoryReadAccess: @MainActor (RuntimeDependencyContext) -> RoamPassportHistoryReadAccess?
    let roamPassportToolsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamPassportToolsReadAccess?
    let roamPrivateToolsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamPrivateToolsAccess?
    let profileOwnedCouponReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileOwnedCouponReadAccess?
    let roamAlbumMetadataReadAccess: @MainActor (RuntimeDependencyContext) -> RoamAlbumMetadataReadAccess?
    let roamTileMemoryReadAccess: @MainActor (RuntimeDependencyContext) -> RoamTileMemoryReadAccess?
    let profilePublicInfoReadAccess: @MainActor (RuntimeDependencyContext) -> ProfilePublicInfoReadAccess?
    let profileGuideReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileGuideReadAccess?
    let profileFavoritesReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoritesReadAccess?
    var nativeChannelManagementApproval: @MainActor (RuntimeDependencyContext, UInt64, NativeChannelManagementScope) -> NativeChannelManagementApproval? = { _, _, _ in nil }
    var nativeWebhookRuntimeFactory: (any NativeWebhookRuntimeFactory)? = nil
    var nativeFriendChannelInviteApproval: @MainActor (RuntimeDependencyContext, NativeFriendChannelInviteMode) -> NativeFriendChannelInviteApproval? = { _, _ in nil }
    var nativeFriendChannelSourceApproval: @MainActor (RuntimeDependencyContext, Int64) -> NativeFriendChannelSourceApproval? = { _, _ in nil }
    var nativeFriendTeamInviteApproval: @MainActor (RuntimeDependencyContext, NativeFriendTeamInviteMode) -> NativeFriendTeamInviteApproval? = { _, _ in nil }
    var nativeFriendMetadataApproval: @MainActor (RuntimeDependencyContext) -> NativeFriendMetadataApproval? = { _ in nil }
    var nativeFriendRemovalApproval: @MainActor (RuntimeDependencyContext) -> NativeFriendRemovalApproval? = { _ in nil }
    var nativeBlacklistApproval: @MainActor (RuntimeDependencyContext) -> NativeBlacklistApproval? = { _ in nil }
    var nativeFriendDirectoryApproval: @MainActor (RuntimeDependencyContext) -> NativeFriendDirectoryApproval? = { _ in nil }
    var nativeFriendProgressApproval: @MainActor (RuntimeDependencyContext) -> NativeFriendProgressApproval? = { _ in nil }
    var nativeFriendApproval: @MainActor (RuntimeDependencyContext) -> NativeFriendApproval? = { _ in nil }
    /// Independent current operation and endpoint issuance. Channel metadata is not approval.
    var nativeChannelProgressSelection: @MainActor (RuntimeDependencyContext, NativeChannelManagementIntegrationContext) -> NativeChannelProgressRuntimeSelection? = { _, _ in nil }
    var nativeChannelProgressReceiptApproval: @MainActor (RuntimeDependencyContext, NativeChannelManagementIntegrationContext, NativeChannelProgressPrivacyCommand) -> OperationEndpointApproval? = { _, _, _ in nil }
    /// Actual existing team index only; a missing index must not synthesize filter IDs.
    var nativeChannelProgressTeamOptions: @MainActor (RuntimeDependencyContext, NativeChannelManagementID, NativeChannelProgressBoard) -> [NativeChannelProgressTeamOption]? = { _, _, _ in nil }
    var nativeProgressPrivacyApproval: @MainActor (RuntimeDependencyContext, NativeProgressPrivacyTarget) -> NativeProgressPrivacyApproval? = { _, _ in nil }
    var nativeChannelWelcomeApproval: @MainActor (RuntimeDependencyContext) -> NativeChannelWelcomeApproval? = { _ in nil }
    var nativeChannelOnboardingApproval: @MainActor (RuntimeDependencyContext) -> NativeChannelOnboardingApproval? = { _ in nil }
    // Independent source-owned issuances. Nil is disabled, never a synthesized grant.
    var nativeChannelNotificationAuthorization: @MainActor (RuntimeDependencyContext, UInt64) -> (any NativeChannelNotificationAuthorizing)? = { _, _ in nil }
    var nativeChannelMessageAuthorization: @MainActor (RuntimeDependencyContext, UInt64, NativeChannelMessageBinding) -> NativeChannelMessageHostAuthority? = { _, _, _ in nil }
    var nativeChannelTextReceiptApproval: @MainActor (RuntimeDependencyContext) -> NativeChannelTextApproval? = { _ in nil }
    var nativeChannelTextSendApproval: @MainActor (RuntimeDependencyContext) -> NativeChannelTextApproval? = { _ in nil }
    var profileFavoriteRemovalAccesses: @MainActor (RuntimeDependencyContext, UUID) -> [ProfileFavoriteRemovalAccess] = { _, _ in [] }
    /// 我的 当前权益 (`api/role/info`). No reviewed lease exists yet, so the read stays dormant.
    var memberRoleInfoReadApproval: @MainActor (RuntimeDependencyContext) -> MemberRoleInfoReadApproval? = { _ in nil }
    /// 设置 → 隐私与定位 → 我的待审媒体 (GET list only). Dormant until a reviewed lease exists.
    var ownMediaReadApproval: @MainActor (RuntimeDependencyContext) -> OwnMediaReadApproval? = { _ in nil }
    let ownMediaImagePreviewSelection = OwnMediaImagePreviewSourceSelection()
    let ownMediaApprovedLinkSelection = OwnMediaApprovedLinkSourceSelection()
    let ownMediaAudioPreviewSelection = OwnMediaAudioPreviewSourceSelection()
    let ownMediaModelPreviewSelection = OwnMediaModelPreviewSourceSelection()
    /// 公共地图图层读取 (`POST /api/map/public-layers`). Dormant until a reviewed lease exists.
    var mapPublicLayerReadApproval: @MainActor (RuntimeDependencyContext) -> MapPublicLayerReadApproval? = { _ in nil }
    /// 俱乐部动态读取 (`api/club/post/list`, `feed`, `comment/list`, `history`). Dormant until a reviewed lease exists.
    var clubCommunityReadApproval: @MainActor (RuntimeDependencyContext) -> ClubCommunityReadApproval? = { _ in nil }
    var clubPublicRosterApproval: @MainActor (RuntimeDependencyContext) -> ClubPublicRosterApproval? = { _ in nil }
    var clubPublicTopicsApproval: @MainActor (ClubPublicTopicsContext, Int) -> ClubPublicTopicsApproval? = { _, _ in nil }
    var clubPostOriginalApproval: @MainActor (RuntimeDependencyContext) -> ClubPostOriginalApproval? = { _ in nil }
    var clubCommentOriginalApproval: @MainActor (RuntimeDependencyContext) -> ClubCommentOriginalApproval? = { _ in nil }
    var clubOrdinaryAdmissionApproval: @MainActor (RuntimeDependencyContext) -> ClubOrdinaryAdmissionApproval? = { _ in nil }
    var clubRoleAssignmentApproval: @MainActor (RuntimeDependencyContext) -> ClubRoleAssignmentApproval? = { _ in nil }
    var clubRoleRevocationApproval: @MainActor (RuntimeDependencyContext) -> ClubRoleRevocationApproval? = { _ in nil }
    /// 俱乐部帖子图片上传 (`api/common/uploadOSS`, `bizType=club_post_image`). Dormant until a reviewed lease exists.
    var clubPostImageUploadApproval: @MainActor (RuntimeDependencyContext, Int) -> ClubPostImageUploadApproval? = { _, _ in nil }
    var makeClubPostImageUploadTransport: @MainActor () -> any HTTPTransport = { ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: 64 * 1024) }
    let profileFavoriteTopicReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoriteTopicReadAccess?
    let profileFavoriteDetailAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoriteDetailAccess?
    let profileInviteHistoryReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileInviteHistoryReadAccess?
    let profileWeeklyPointsReadApproval: @MainActor (RuntimeDependencyContext) -> ProfileWeeklyPointsReadApproval?
    /// Independent own-growth lease; nil stays HOLD, including the anonymous leaderboard.
    let growthNormalReadApproval: @MainActor (RuntimeDependencyContext) -> GrowthNormalReadApproval?
    let walletHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval?
    /// Original participation-only provider bundle. No production issuance or endpoint activation by default.
    let cityOrientationOriginalApprovals = CityOrientationTaskApprovalRegistry()
    var cityCurrentSnapshotSelection: @MainActor (RuntimeDependencyContext, UInt64) -> CityCurrentSnapshotRuntimeSelection? = { _, _ in nil }
    var cityOrderedMapSelection: @MainActor (RuntimeDependencyContext, UInt64) -> CityOrderedMapRuntimeSelection? = { _, _ in nil }
    var cityParticipationRuntimeGrants: @MainActor (RuntimeDependencyContext, UInt64) -> CityParticipationRuntimeGrants? = { _, _ in nil }
    var cityActionBudgetRuntimeGrants: @MainActor (RuntimeDependencyContext, UInt64) -> CityActionBudgetRuntimeGrants? = { _, _ in nil }
    var cityNeutralTaskApproval: @MainActor (RuntimeDependencyContext) -> CityNeutralTaskApproval? = { _ in nil }
    var cityTaskHistoryApproval: @MainActor (RuntimeDependencyContext) -> CityTaskHistoryApproval? = { _ in nil }
    /// Separate receipt-read issuance. No verified production issuer is configured.
    var cityNodeReceiptApproval: @MainActor (RuntimeDependencyContext) -> CityNodeRedemptionReceiptApproval? = { _ in nil }
    var cityMerchantValueApproval: @MainActor (RuntimeDependencyContext) -> CityMerchantValueApproval? = { _ in nil }
    var cityValueBoundedMapApproval: @MainActor (RuntimeDependencyContext) -> CityValueBoundedMapApproval? = { _ in nil }
    var cityPlayerValueNodeApproval: @MainActor (RuntimeDependencyContext, Int) -> CityPlayerValueNodeApproval? = { _, _ in nil }
    var cityPlayerValueApproval: @MainActor (RuntimeDependencyContext, CityValueBoundedMapApproval, CityValueBoundedCapture) -> CityPlayerValueApproval? = { _, _, _ in nil }
    var cityPlayerRulesApproval: @MainActor (RuntimeDependencyContext) -> CityPlayerRulesApproval? = { _ in nil }
    var cityAcquisitionApproval: @MainActor (RuntimeDependencyContext) -> CityAcquisitionApproval? = { _ in nil }
    var cityOnsiteTaskApproval: @MainActor (RuntimeDependencyContext) -> CityOnsiteTaskApproval? = { _ in nil }
    var cityArrivalEvidenceApproval: @MainActor (RuntimeDependencyContext, CityArrivalAudience) -> CityArrivalEvidenceApproval? = { _, _ in nil }
    /// CONFIG_ONLY own-store intent remains independently disabled.
    var cityMerchantOperationsApproval: @MainActor (RuntimeDependencyContext) -> CityMerchantOperationsApproval? = { _ in nil }
    let cityPlayerReadApproval: @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval?
    let teamReadApproval: @MainActor (RuntimeDependencyContext) -> TeamReadApproval?
    let workshopCreatorDeclarationTargets: @MainActor (RuntimeDependencyContext, Int64) -> [WorkshopCreatorDeclarationTarget]
    let workshopCreatorPendingAuthorApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingAuthorApproval?
    let workshopCreatorPendingListApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingListApproval?
    let workshopCreatorPendingDetailApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingDetailApproval?
    let workshopCreatorConsentReadApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorConsentReadApproval?
    let workshopCreatorConsentWriteApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorConsentWriteApproval?
    let workshopPaidProfessionalReadApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPaidProfessionalReadApproval?
    let workshopPaidProfessionalWriteApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPaidProfessionalWriteApproval?
    let workshopPaidInstalledTextApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstalledTextApproval?
    let workshopPaidInstallApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstallApproval?
    let workshopPurchasedReadApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPurchasedReadApproval?
    let workshopOwnedReadApproval: @MainActor (RuntimeDependencyContext) -> WorkshopOwnedReadApproval?
    let ownerDraftReadApproval: @MainActor (RuntimeDependencyContext) -> OwnerDraftReadApproval?
    let couponLocks: @MainActor () -> any CouponManagementLocking
    let couponReadApproval: @MainActor (RuntimeDependencyContext) -> CouponManagementReadApproval?
    let couponWriteApproval: @MainActor (RuntimeDependencyContext) -> CouponManagementWriteApproval?
    /// Original per-account marketing source, empty by default and independently revocable.
    let merchantMarketingConsentSelection = MerchantMarketingConsentSourceSelection()
    /// Original evidence reads only, no source or acceptance permission installed by default.
    /// Independent score evidence reads; no production grant is installed.
    let memberScoreReadSelection = MemberScoreAppealSourceSelection()
    /// Latest recorded self-avatar review only; no authority is installed by default.
    let profileCurrentReviewSelection = ProfileCurrentReviewSourceSelection()
    /// Separate read-only nickname source. No production lease is installed.
    let profileNicknameSelection = ProfileNicknameSourceSelection()
    let profileSavedMediaSelection = ProfileSavedMediaSourceSelection()
    let memberIdentityAvatarSelection = MemberIdentityAvatarSourceSelection()
    /// r463 owner-only ticket projections. No issuer or default lease.
    let supportTicketReadSelection = SupportTicketReadSourceSelection()
    /// Existing private text GET only; no default source or issuer.
    let npcChatDataReadSelection = NPCChatDataReadSourceSelection()
    /// Reporter history and public progress only; no source or issuer is installed.
    let memberReportProgressSelection = MemberReportProgressSourceSelection()
    let usageConsentReadSelection = UsageConsentReadSourceSelection()
    let sessionDependencies: @MainActor (RuntimeDependencyContext) -> NativeRuntimeDependencies
    init(deployment: DeploymentState = .unconfigured, storage: AppScopedStorageFactory? = nil,
         makeTransport: @escaping () -> any HTTPTransport = { URLSessionTransport() },
         invoiceLaunchReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> InvoiceLaunchReadApproval? = { _ in nil },
         clubBadgeManagementApproval: @escaping @MainActor (RuntimeDependencyContext) -> ClubBadgeManagementApproval? = { _ in nil },
         merchantReviewOriginalReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> MerchantReviewOriginalReadApproval? = { _ in nil },
         projectStoryAudioUploadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ProjectStoryAudioUploadApproval? = { _ in nil },
         makeProjectStoryAudioUploadTransport: @escaping @MainActor () -> any HTTPTransport = { ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: 64 * 1024) },
         projectTopicImageUploadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ProjectTopicImageUploadApproval? = { _ in nil },
         makeProjectTopicImageUploadTransport: @escaping @MainActor () -> any HTTPTransport = { ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: 64 * 1024) },
         projectStoryImageUploadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ProjectStoryImageUploadApproval? = { _ in nil },
         projectNodeImageUploadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ProjectNodeImageUploadApproval? = { _ in nil },
         makeProjectNodeImageUploadTransport: @escaping @MainActor () -> (any ProjectNodeImageDispatching)? = { ProjectNodeImageNetworkTransport(enabled: true) },
         makeProjectStoryImageUploadTransport: @escaping @MainActor () -> any HTTPTransport = { ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: 64 * 1024) },
         ownedTopicCoverApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedTopicCoverApproval? = { _ in nil },
         makeOwnedTopicCoverTransport: @escaping @MainActor (Int) -> any HTTPTransport = { ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: $0) },
         sessionDependencies: (@MainActor (RuntimeDependencyContext) -> NativeRuntimeDependencies)? = nil,
         couponLocks: @escaping @MainActor () -> any CouponManagementLocking = { CouponManagementAppLocks() },
         couponReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CouponManagementReadApproval? = { _ in nil },
         couponWriteApproval: @escaping @MainActor (RuntimeDependencyContext) -> CouponManagementWriteApproval? = { _ in nil },
         templateShelfReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval? = { _ in nil },
         messagingHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval? = { _ in nil },
         walletHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval? = { _ in nil },
         roamSessionFactReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamSessionFactReadAccess? = { _ in nil },
         roamNearbyEventsReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamNearbyEventsReadAccess? = { _ in nil },
         roamNearbyPlayersReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamNearbyPlayersReadAccess? = { _ in nil },
         roamEntryNearbyReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamEntryNearbyReadAccess? = { _ in nil },
         roamReceivedStampReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamReceivedStampReadAccess? = { _ in nil },
         roamPassportHistoryReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamPassportHistoryReadAccess? = { _ in nil },
         roamPassportToolsReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamPassportToolsReadAccess? = { _ in nil },
         roamPrivateToolsReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamPrivateToolsAccess? = { _ in nil },
         profileOwnedCouponReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileOwnedCouponReadAccess? = { _ in nil },
         roamAlbumMetadataReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamAlbumMetadataReadAccess? = { _ in nil },
         roamTileMemoryReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamTileMemoryReadAccess? = { _ in nil },
         profilePublicInfoReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfilePublicInfoReadAccess? = { _ in nil },
         profileGuideReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileGuideReadAccess? = { _ in nil },
         profileFavoritesReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileFavoritesReadAccess? = { _ in nil },
         profileFavoriteTopicReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileFavoriteTopicReadAccess? = { _ in nil },
         profileFavoriteDetailAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileFavoriteDetailAccess? = { _ in nil },
         profileInviteHistoryReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileInviteHistoryReadAccess? = { _ in nil },
         profileWeeklyPointsReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ProfileWeeklyPointsReadApproval? = { _ in nil },
         growthNormalReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> GrowthNormalReadApproval? = { _ in nil },
         cityPlayerReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval? = { _ in nil },
         teamReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TeamReadApproval? = { _ in nil },
         workshopCreatorDeclarationTargets: @escaping @MainActor (RuntimeDependencyContext, Int64) -> [WorkshopCreatorDeclarationTarget] = { _, _ in [] },
         workshopCreatorPendingAuthorApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingAuthorApproval? = { _ in nil },
         workshopCreatorPendingListApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingListApproval? = { _ in nil },
         workshopCreatorPendingDetailApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingDetailApproval? = { _ in nil },
         workshopCreatorConsentReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorConsentReadApproval? = { _ in nil },
         workshopCreatorConsentWriteApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorConsentWriteApproval? = { _ in nil },
         workshopPaidProfessionalReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidProfessionalReadApproval? = { _ in nil },
         workshopPaidProfessionalWriteApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidProfessionalWriteApproval? = { _ in nil },
         workshopPaidInstalledTextApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstalledTextApproval? = { _ in nil },
         workshopPaidInstallApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstallApproval? = { _ in nil },
         workshopPurchasedReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPurchasedReadApproval? = { _ in nil },
         workshopOwnedReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopOwnedReadApproval? = { _ in nil },
         ownerDraftReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnerDraftReadApproval? = { _ in nil },
         manualMapReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval? = { _ in nil },
         mapPublicLayerReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> MapPublicLayerReadApproval? = { _ in nil },
         ownedOrderReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval? = { _ in nil }) {
        self.deployment = deployment; self.storage = storage ?? .init(); self.makeTransport = makeTransport
        self.projectStoryAudioUploadApproval = projectStoryAudioUploadApproval; self.makeProjectStoryAudioUploadTransport = makeProjectStoryAudioUploadTransport
        self.projectTopicImageUploadApproval = projectTopicImageUploadApproval; self.makeProjectTopicImageUploadTransport = makeProjectTopicImageUploadTransport
        self.projectStoryImageUploadApproval = projectStoryImageUploadApproval; self.makeProjectStoryImageUploadTransport = makeProjectStoryImageUploadTransport
        self.projectNodeImageUploadApproval = projectNodeImageUploadApproval; self.makeProjectNodeImageUploadTransport = makeProjectNodeImageUploadTransport
        self.ownedTopicCoverApproval = ownedTopicCoverApproval; self.makeOwnedTopicCoverTransport = makeOwnedTopicCoverTransport
        self.invoiceLaunchReadApproval = invoiceLaunchReadApproval
        self.clubBadgeManagementApproval = clubBadgeManagementApproval
        self.merchantReviewOriginalReadApproval = merchantReviewOriginalReadApproval
        self.sessionDependencies = sessionDependencies ?? { _ in .dormant }
        self.couponLocks = couponLocks
        self.couponReadApproval = couponReadApproval; self.couponWriteApproval = couponWriteApproval
        self.templateShelfReadApproval = templateShelfReadApproval
        self.messagingHistoryReadApproval = messagingHistoryReadApproval
        self.walletHistoryReadApproval = walletHistoryReadApproval
        self.roamSessionFactReadAccess = roamSessionFactReadAccess
        self.roamNearbyEventsReadAccess = roamNearbyEventsReadAccess
        self.roamNearbyPlayersReadAccess = roamNearbyPlayersReadAccess
        self.roamEntryNearbyReadAccess = roamEntryNearbyReadAccess
        self.roamReceivedStampReadAccess = roamReceivedStampReadAccess
        self.roamPassportHistoryReadAccess = roamPassportHistoryReadAccess
        self.roamPassportToolsReadAccess = roamPassportToolsReadAccess
        self.roamPrivateToolsReadAccess = roamPrivateToolsReadAccess
        self.profileOwnedCouponReadAccess = profileOwnedCouponReadAccess
        self.roamAlbumMetadataReadAccess = roamAlbumMetadataReadAccess
        self.roamTileMemoryReadAccess = roamTileMemoryReadAccess
        self.profilePublicInfoReadAccess = profilePublicInfoReadAccess
        self.profileGuideReadAccess = profileGuideReadAccess
        self.profileFavoritesReadAccess = profileFavoritesReadAccess
        self.profileFavoriteTopicReadAccess = profileFavoriteTopicReadAccess
        self.profileFavoriteDetailAccess = profileFavoriteDetailAccess
        self.profileInviteHistoryReadAccess = profileInviteHistoryReadAccess
        self.profileWeeklyPointsReadApproval = profileWeeklyPointsReadApproval
        self.growthNormalReadApproval = growthNormalReadApproval
        self.cityPlayerReadApproval = cityPlayerReadApproval
        self.teamReadApproval = teamReadApproval
        self.workshopCreatorDeclarationTargets = workshopCreatorDeclarationTargets
        self.workshopCreatorPendingAuthorApproval = workshopCreatorPendingAuthorApproval
        self.workshopCreatorPendingListApproval = workshopCreatorPendingListApproval
        self.workshopCreatorPendingDetailApproval = workshopCreatorPendingDetailApproval
        self.workshopCreatorConsentReadApproval = workshopCreatorConsentReadApproval
        self.workshopCreatorConsentWriteApproval = workshopCreatorConsentWriteApproval
        self.workshopPaidProfessionalReadApproval = workshopPaidProfessionalReadApproval
        self.workshopPaidProfessionalWriteApproval = workshopPaidProfessionalWriteApproval
        self.workshopPaidInstalledTextApproval = workshopPaidInstalledTextApproval
        self.workshopPaidInstallApproval = workshopPaidInstallApproval
        self.workshopPurchasedReadApproval = workshopPurchasedReadApproval
        self.workshopOwnedReadApproval = workshopOwnedReadApproval
        self.ownerDraftReadApproval = ownerDraftReadApproval
        self.manualMapReadApproval = manualMapReadApproval
        self.mapPublicLayerReadApproval = mapPublicLayerReadApproval
        self.ownedOrderReadApproval = ownedOrderReadApproval
    }
    var reviewed: ReviewedAppDeployment? {
        if case .reviewed(let value) = deployment { return value }; return nil
    }
    /// A diagnostic only, never an authorization token. The transport repeats its own
    /// exact route, credential and before/after identity checks at dispatch time.
    func readAvailability(_ surface: ReadSurface, identity: CompositionHTTPTransport.SessionIdentity?) -> ReadAvailability {
        if case .incompatibleBuild = deployment { return .buildMismatch }
        guard let reviewed, reviewed.regional.apiConfiguration != nil,
              reviewed.storageScope.matches(configuration: reviewed.regional) else { return .deploymentMissing }
        switch surface {
        case .home:
            guard reviewed.reads.contains(.homeAndSearch) else { return .homeReadNotApproved }
            guard let identity, identity.isPublicTemplateViewer else { return .sessionUnavailable }
        case .contentDetail:
            guard reviewed.contentDetails == .activityAndTopic else { return .detailReadNotApproved }
            guard let identity else { return .sessionUnavailable }
            if identity.accountID == nil && identity.role == nil && identity.token == nil { return .signInRequired }
            guard identity.isSignedInContentViewer else { return .sessionUnavailable }
        }
        return .available
    }
    func transport() -> CompositionHTTPTransport {
        let transport = CompositionHTTPTransport(deployment: reviewed, underlying: makeTransport(), couponReadApproval: couponReadApproval, couponWriteApproval: couponWriteApproval, templateShelfReadApproval: templateShelfReadApproval, messagingHistoryReadApproval: messagingHistoryReadApproval, walletHistoryReadApproval: walletHistoryReadApproval, roamSessionFactReadAccess: roamSessionFactReadAccess, roamNearbyEventsReadAccess: roamNearbyEventsReadAccess, roamNearbyPlayersReadAccess: roamNearbyPlayersReadAccess, profileOwnedCouponReadAccess: profileOwnedCouponReadAccess, roamAlbumMetadataReadAccess: roamAlbumMetadataReadAccess, roamTileMemoryReadAccess: roamTileMemoryReadAccess, profilePublicInfoReadAccess: profilePublicInfoReadAccess, profileGuideReadAccess: profileGuideReadAccess, profileFavoritesReadAccess: profileFavoritesReadAccess, profileFavoriteTopicReadAccess: profileFavoriteTopicReadAccess, profileFavoriteDetailAccess: profileFavoriteDetailAccess, profileInviteHistoryReadAccess: profileInviteHistoryReadAccess, profileWeeklyPointsReadApproval: profileWeeklyPointsReadApproval, cityPlayerReadApproval: cityPlayerReadApproval, teamReadApproval: teamReadApproval, workshopCreatorPendingAuthorApproval: workshopCreatorPendingAuthorApproval, workshopCreatorPendingListApproval: workshopCreatorPendingListApproval, workshopCreatorPendingDetailApproval: workshopCreatorPendingDetailApproval, workshopCreatorConsentReadApproval: workshopCreatorConsentReadApproval, workshopCreatorConsentWriteApproval: workshopCreatorConsentWriteApproval, workshopPaidProfessionalReadApproval: workshopPaidProfessionalReadApproval, workshopPaidProfessionalWriteApproval: workshopPaidProfessionalWriteApproval, workshopPaidInstalledTextApproval: workshopPaidInstalledTextApproval, workshopPaidInstallApproval: workshopPaidInstallApproval, workshopPurchasedReadApproval: workshopPurchasedReadApproval, workshopOwnedReadApproval: workshopOwnedReadApproval, ownerDraftReadApproval: ownerDraftReadApproval, manualMapReadApproval: manualMapReadApproval, ownedOrderReadApproval: ownedOrderReadApproval)
        transport.officialPublicEventReadSelection = officialPublicEventReadSelection
        transport.merchantGamePlayerReadGrant = merchantGamePlayerReadGrant
        transport.memberRoleInfoReadApproval = memberRoleInfoReadApproval
        transport.ownMediaReadApproval = ownMediaReadApproval
        transport.mapPublicLayerReadApproval = mapPublicLayerReadApproval
        transport.clubCommunityReadApproval = clubCommunityReadApproval
        transport.clubPublicRosterApproval = { self.clubPublicRosterApproval($0) }
        transport.clubPublicTopicsApproval = { self.clubPublicTopicsApproval($0, $1) }
        transport.clubPostOriginalApproval = clubPostOriginalApproval
        transport.clubCommentOriginalApproval = clubCommentOriginalApproval
        transport.clubOrdinaryAdmissionApproval = clubOrdinaryAdmissionApproval
        transport.clubRoleAssignmentApproval = { self.clubRoleAssignmentApproval($0) }
        transport.clubRoleRevocationApproval = { self.clubRoleRevocationApproval($0) }
        transport.clubPostImageUploadApproval = clubPostImageUploadApproval
        transport.roamEntryNearbyReadAccess = roamEntryNearbyReadAccess
        transport.roamReceivedStampReadAccess = roamReceivedStampReadAccess
        transport.roamPassportHistoryReadAccess = roamPassportHistoryReadAccess
        transport.roamPassportToolsReadAccess = roamPassportToolsReadAccess
        transport.roamPrivateToolsReadAccess = roamPrivateToolsReadAccess
        return transport
    }
    func makeSession() -> AppSession { AppSession(composition: self) }
}

/// Existing CN auth and independently reviewed bounded reads; coupon mutations additionally
/// require a one-use confirmed dispatch ticket. Private home keeps its separate owner grant.
/// All other paths stay closed.
/// No device/provider work or authorization is inferred from a feature grant.
@MainActor final class CompositionHTTPTransport: ActivityCoverHTTPTransport, PublisherIdentityRegistrationHTTPTransport, ActivityEditingHTTPTransport, CouponManagementConfirmedHTTPTransport, WorkshopPaidInstallMutationTransport, WorkshopPaidProfessionalMutationTransport, WorkshopCreatorConsentMutationTransport, WorkshopCreatorPendingMutationTransport {
    fileprivate var officialPublicEventReadSelection = OfficialPublicEventReadSelection()
    var merchantGamePlayerReadGrant: @MainActor (RuntimeDependencyContext) -> MerchantGamePlayerReadGrant? = { _ in nil }
    var publisherIdentityRegistrationApproval: @MainActor (RuntimeDependencyContext) -> PublisherIdentityRegistrationGrants = { _ in .init() }
    var activityCoverApproval: @MainActor (RuntimeDependencyContext) -> ActivityCoverApproval? = { _ in nil }
    var activityEditingApproval: @MainActor (RuntimeDependencyContext) -> ActivityEditingGrants = { _ in .init() }
    /// Chapter invite, invite response, and offer withdraw. Each stays closed until AppSession
    /// wires the existing approval. A true flag still cannot admit a different path or body.
    var chapterInviteExecution: @MainActor (RuntimeDependencyContext) -> Bool = { _ in false }
    var chapterRespondExecution: @MainActor (RuntimeDependencyContext) -> Bool = { _ in false }
    var offerWithdrawExecution: @MainActor (RuntimeDependencyContext, Int, String) -> Bool = { _, _, _ in false }
    /// Per-operation reward gate. Default closed, so a constructed client still cannot leave.
    var rewardPledgePermit: @MainActor (String) -> Bool = { _ in false }
    var workshopPaidInstallBeforeForward: (() async -> Void)?
    struct SessionIdentity: Equatable {
        let epoch: UInt64
        let accountID: Int?
        let role: String?
        let token: String?
        /// Advances for identity-only refreshes as well as login/logout. The identity
        /// tuple alone cannot distinguish role A → B → A with an unchanged token.
        let viewerRevision: UInt64
        init(epoch: UInt64, accountID: Int?, role: String?, token: String?, viewerRevision: UInt64 = 0) {
            self.epoch = epoch; self.accountID = accountID; self.role = role
            self.token = token; self.viewerRevision = viewerRevision
        }
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.epoch == rhs.epoch && lhs.accountID == rhs.accountID && lhs.viewerRevision == rhs.viewerRevision &&
            lhs.role.map { Data($0.utf8) } == rhs.role.map { Data($0.utf8) } &&
            lhs.token.map { Data($0.utf8) } == rhs.token.map { Data($0.utf8) }
        }
        /// Anonymous reads carry no partial/restoring identity. Authenticated reads must use
        /// the current complete identity; local role never grants a server viewer projection.
        fileprivate var isSignedInContentViewer: Bool {
            guard let role, ["player", "club", "merchant"].contains(role) else { return false }
            return accountID != nil && isPublicTemplateViewer
        }
        fileprivate var isPublicTemplateViewer: Bool {
            if accountID == nil { return role == nil && token == nil }
            guard let accountID, accountID > 0, let role, !role.isEmpty,
                  let token, AuthRequestBuilder.isValidToken(token) else { return false }
            return true
        }
    }
    private struct MerchantOverviewScope {
        let approval: MerchantOverviewReadApproval
        let context: RuntimeDependencyContext
        let viewer: SessionIdentity
        let approved: () -> Bool
        func matches(deployment: ReviewedAppDeployment, viewer current: SessionIdentity) -> Bool {
            guard approved(), current == viewer, current.isSignedInContentViewer,
                  let api = deployment.regional.apiConfiguration, let account = current.accountID,
                  let role = current.role, let token = current.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: current.epoch,
                    namespace: deployment.storageScope.service, token: token) else { return false }
            return context == RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session) && approval.matches(context)
        }
        static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
            guard request.httpMethod == "POST", request.url?.query == nil, request.url?.fragment == nil,
                  !request.httpShouldHandleCookies, request.httpBodyStream == nil,
                  request.value(forHTTPHeaderField: "Cookie") == nil,
                  request.value(forHTTPHeaderField: "Proxy-Authorization") == nil else { return false }
            if request.url?.absoluteString == baseURL.appendingPathComponent("api/merchant/events").absoluteString {
                return request.value(forHTTPHeaderField: "Content-Type") == "application/json" && request.httpBody == Data("{}".utf8)
            }
            guard request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil else { return false }
            return ["api/merchant/access/me", "api/merchant/dashboard", "api/merchant/todo-summary"].contains {
                request.url?.absoluteString == baseURL.appendingPathComponent($0).absoluteString
            }
        }
    }
    private struct MerchantPredictionScope {
        let approval: MerchantPredictionReadApproval
        let context: RuntimeDependencyContext
        let viewer: SessionIdentity
        let approved: () -> Bool
        func matches(deployment: ReviewedAppDeployment, viewer current: SessionIdentity) -> Bool {
            guard approved(), current == viewer, current.isSignedInContentViewer,
                  let api = deployment.regional.apiConfiguration, let account = current.accountID,
                  let role = current.role, let token = current.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: current.epoch,
                    namespace: deployment.storageScope.service, token: token) else { return false }
            let actual = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            return actual == context && approval.matches(actual)
        }
        static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
            guard request.httpMethod == "POST", request.url?.query == nil, request.url?.fragment == nil,
                  !request.httpShouldHandleCookies, request.httpBody == nil, request.httpBodyStream == nil,
                  request.value(forHTTPHeaderField: "Content-Type") == nil,
                  request.value(forHTTPHeaderField: "Cookie") == nil,
                  request.value(forHTTPHeaderField: "Proxy-Authorization") == nil else { return false }
            return ["api/merchant/access/me", "api/merchant/predict/inbox"].contains {
                request.url?.absoluteString == baseURL.appendingPathComponent($0).absoluteString
            }
        }
    }
    private struct MerchantProjectParticipantsScope {
        let approval: MerchantProjectParticipantsReadApproval
        let topicID: Int
        let context: RuntimeDependencyContext
        let viewer: SessionIdentity
        let approved: () -> Bool
        func matches(deployment: ReviewedAppDeployment, viewer current: SessionIdentity) -> Bool {
            guard approved(), current == viewer, current.isSignedInContentViewer,
                  let api = deployment.regional.apiConfiguration, let account = current.accountID,
                  let role = current.role, let token = current.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: current.epoch,
                    namespace: deployment.storageScope.service, token: token) else { return false }
            let actual = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            return actual == context && approval.matches(actual)
        }
        func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
            guard topicID > 0, request.httpMethod == "POST", request.url?.query == nil, request.url?.fragment == nil,
                  !request.httpShouldHandleCookies, request.httpBodyStream == nil,
                  request.value(forHTTPHeaderField: "Cookie") == nil,
                  request.value(forHTTPHeaderField: "Proxy-Authorization") == nil else { return false }
            if request.url?.absoluteString == baseURL.appendingPathComponent("api/merchant/access/me").absoluteString {
                return request.httpBody == nil && request.value(forHTTPHeaderField: "Content-Type") == nil
            }
            guard request.url?.absoluteString == baseURL.appendingPathComponent("api/project/players").absoluteString,
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json", let body = request.httpBody else { return false }
            // Exactly the two JSONEncoder field orders; no extra, duplicate, coerced or alternate-topic keys.
            let first = "{\"topicId\":\(topicID),\"scope\":\"MERCHANT\"}"
            let second = "{\"scope\":\"MERCHANT\",\"topicId\":\(topicID)}"
            return body == Data(first.utf8) || body == Data(second.utf8)
        }
    }
    private struct MerchantProjectWorkspaceScope {
        let approval: MerchantProjectWorkspaceReadApproval
        let topicID: Int
        let context: RuntimeDependencyContext
        let viewer: SessionIdentity
        let approved: () -> Bool
        func matches(deployment: ReviewedAppDeployment, viewer current: SessionIdentity) -> Bool {
            guard approved(), current == viewer, current.isSignedInContentViewer,
                  let api = deployment.regional.apiConfiguration, let account = current.accountID,
                  let role = current.role, let token = current.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: current.epoch,
                    namespace: deployment.storageScope.service, token: token) else { return false }
            let actual = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            return actual == context && approval.matches(actual)
        }
        func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
            guard topicID > 0, request.httpMethod == "POST", request.url?.query == nil, request.url?.fragment == nil,
                  !request.httpShouldHandleCookies, request.httpBodyStream == nil,
                  request.value(forHTTPHeaderField: "Cookie") == nil,
                  request.value(forHTTPHeaderField: "Proxy-Authorization") == nil else { return false }
            if request.url?.absoluteString == baseURL.appendingPathComponent("api/merchant/access/me").absoluteString {
                return request.httpBody == nil && request.value(forHTTPHeaderField: "Content-Type") == nil
            }
            guard request.url?.absoluteString == baseURL.appendingPathComponent("api/project/home").absoluteString,
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json", let body = request.httpBody else { return false }
            // Exactly the two JSONEncoder field orders; no extra, duplicate, coerced or alternate-topic keys.
            let first = "{\"topicId\":\(topicID),\"scope\":\"MERCHANT\"}"
            let second = "{\"scope\":\"MERCHANT\",\"topicId\":\(topicID)}"
            return body == Data(first.utf8) || body == Data(second.utf8)
        }
    }
    private struct MerchantProjectBrowseScope {
        let approval: MerchantProjectBrowseApproval
        let context: RuntimeDependencyContext
        let viewer: SessionIdentity
        let approved: () -> Bool
        func matches(deployment: ReviewedAppDeployment, viewer current: SessionIdentity) -> Bool {
            guard approved(), current == viewer, current.isSignedInContentViewer,
                  let api = deployment.regional.apiConfiguration, let account = current.accountID,
                  let role = current.role, let token = current.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: current.epoch,
                    namespace: deployment.storageScope.service, token: token) else { return false }
            let actual = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            return actual == context && approval.matches(actual)
        }
        static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
            guard request.httpMethod == "POST", request.url?.query == nil, request.url?.fragment == nil,
                  !request.httpShouldHandleCookies, request.httpBodyStream == nil,
                  request.value(forHTTPHeaderField: "Cookie") == nil,
                  request.value(forHTTPHeaderField: "Proxy-Authorization") == nil else { return false }
            if request.url?.absoluteString == baseURL.appendingPathComponent("api/merchant/access/me").absoluteString {
                return request.httpBody == nil && request.value(forHTTPHeaderField: "Content-Type") == nil
            }
            guard request.url?.absoluteString == baseURL.appendingPathComponent("api/project/my").absoluteString,
                  let type = request.value(forHTTPHeaderField: "Content-Type"),
                  type.hasPrefix("multipart/form-data; boundary="), let body = request.httpBody, body.count <= 4096 else { return false }
            let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
            guard UUID(uuidString: boundary)?.uuidString == boundary,
                  let expected = try? AuthRequestBuilder.makeFormRequest(url: baseURL.appendingPathComponent("api/project/my"),
                    fields: ["type": "all", "state": "all", "ownerType": "all", "scope": "MERCHANT", "pageNum": "1", "pageSize": "200"],
                    token: nil, boundary: boundary) else { return false }
            return body == expected.httpBody
        }
    }
    private struct NearbyMerchantCompositionScope {
        let configuration: RuntimeDependencyConfiguration
        let context: RuntimeDependencyContext
        let viewer: SessionIdentity
        func matches(deployment: ReviewedAppDeployment, viewer current: SessionIdentity) -> Bool {
            guard current == viewer, current.isSignedInContentViewer,
                  configuration.nearbyLocation, configuration.endpoints.paths.contains("api/merchant/nearby"),
                  let api = deployment.regional.apiConfiguration,
                  let account = current.accountID, let role = current.role, let token = current.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: current.epoch,
                    namespace: deployment.storageScope.service, token: token) else { return false }
            let actual = RuntimeDependencyContext(market: deployment.regional.market,
                baseURL: api.baseURL, role: role, session: session)
            return actual == context && configuration.matches(actual)
        }
        /// Accept only the four canonical fields emitted by CoopFlowService.nearby.
        static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
            guard request.httpMethod == "POST",
                  request.url?.absoluteString == baseURL.appendingPathComponent("api/merchant/nearby").absoluteString,
                  request.url?.query == nil, request.url?.fragment == nil,
                  request.httpBodyStream == nil, !request.httpShouldHandleCookies,
                  request.value(forHTTPHeaderField: "Cookie") == nil,
                  request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
                  let contentType = request.value(forHTTPHeaderField: "Content-Type"),
                  contentType.hasPrefix("multipart/form-data; boundary=CoopNative-"),
                  let body = request.httpBody, body.count <= 2048,
                  let text = String(data: body, encoding: .utf8) else { return false }
            let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
            let uuidText = String(boundary.dropFirst("CoopNative-".count))
            guard UUID(uuidString: uuidText)?.uuidString == uuidText else { return false }
            let keys = ["latitude", "limit", "longitude", "radius"]
            var remainder = text, fields: [String: String] = [:]
            for key in keys {
                let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n"
                guard remainder.hasPrefix(prefix) else { return false }
                remainder.removeFirst(prefix.count)
                guard let end = remainder.range(of: "\r\n") else { return false }
                fields[key] = String(remainder[..<end.lowerBound])
                remainder = String(remainder[end.upperBound...])
            }
            guard remainder == "--\(boundary)--\r\n", fields["limit"] == "30", fields["radius"] == "5000",
                  let rawLat = fields["latitude"], let lat = Double(rawLat), lat.isFinite,
                  (-90...90).contains(lat), String(lat) == rawLat,
                  let rawLng = fields["longitude"], let lng = Double(rawLng), lng.isFinite,
                  (-180...180).contains(lng), String(lng) == rawLng else { return false }
            return true
        }
    }
    private struct PublicMerchantHomeCompositionScope {
        let approval: MerchantPublicProductionApproval
        let context: MerchantPublicHostContext
        let viewer: SessionIdentity
        func matches(deployment: ReviewedAppDeployment, viewer current: SessionIdentity) -> Bool {
            guard current == viewer, current.isPublicTemplateViewer, approval.publicHomeRead,
                  let api = deployment.regional.apiConfiguration,
                  let actual = try? MerchantPublicHostContext(market: deployment.regional.market,
                    baseURL: api.baseURL, namespace: deployment.storageScope.service,
                    accountID: current.accountID, epoch: current.epoch, role: current.role, token: current.token)
            else { return false }
            return actual == context && approval.matches(actual)
        }
        static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
            let endpoint = baseURL.appendingPathComponent("api/merchant/public-home")
            guard request.httpMethod == "POST", request.url?.absoluteString == endpoint.absoluteString,
                  request.url?.query == nil, request.url?.fragment == nil,
                  request.httpBodyStream == nil, !request.httpShouldHandleCookies,
                  request.value(forHTTPHeaderField: "Authorization") == nil,
                  request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
                  request.value(forHTTPHeaderField: "Cookie") == nil,
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let body = request.httpBody, body.count <= 128,
                  let fields = try? JSONDecoder().decode([String: Int].self, from: body),
                  fields.count == 1, let entry = fields.first,
                  ["id", "memberId"].contains(entry.key), entry.value > 0,
                  let canonical = try? JSONSerialization.data(withJSONObject: fields), canonical == body else { return false }
            return true
        }
    }
    var current: () -> SessionIdentity? = { nil }
    var memberRoleInfoReadApproval: @MainActor (RuntimeDependencyContext) -> MemberRoleInfoReadApproval? = { _ in nil }
    var ownMediaReadApproval: @MainActor (RuntimeDependencyContext) -> OwnMediaReadApproval? = { _ in nil }
    var mapPublicLayerReadApproval: @MainActor (RuntimeDependencyContext) -> MapPublicLayerReadApproval? = { _ in nil }
    var clubCommunityReadApproval: @MainActor (RuntimeDependencyContext) -> ClubCommunityReadApproval? = { _ in nil }
    var clubPublicRosterApproval: @MainActor (RuntimeDependencyContext) -> ClubPublicRosterApproval? = { _ in nil }
    var clubPublicTopicsApproval: @MainActor (ClubPublicTopicsContext, Int) -> ClubPublicTopicsApproval? = { _, _ in nil }
    var clubPostOriginalApproval: @MainActor (RuntimeDependencyContext) -> ClubPostOriginalApproval? = { _ in nil }
    var clubCommentOriginalApproval: @MainActor (RuntimeDependencyContext) -> ClubCommentOriginalApproval? = { _ in nil }
    var clubOrdinaryAdmissionApproval: @MainActor (RuntimeDependencyContext) -> ClubOrdinaryAdmissionApproval? = { _ in nil }
    var clubRoleAssignmentApproval: @MainActor (RuntimeDependencyContext) -> ClubRoleAssignmentApproval? = { _ in nil }
    var clubRoleRevocationApproval: @MainActor (RuntimeDependencyContext) -> ClubRoleRevocationApproval? = { _ in nil }
    var clubPostImageUploadApproval: @MainActor (RuntimeDependencyContext, Int) -> ClubPostImageUploadApproval? = { _, _ in nil }
    private var clubPostImageUploadClubID: Int?
    var roamEntryNearbyReadAccess: @MainActor (RuntimeDependencyContext) -> RoamEntryNearbyReadAccess? = { _ in nil }
    var roamReceivedStampReadAccess: @MainActor (RuntimeDependencyContext) -> RoamReceivedStampReadAccess? = { _ in nil }
    var roamPassportHistoryReadAccess: @MainActor (RuntimeDependencyContext) -> RoamPassportHistoryReadAccess? = { _ in nil }
    var roamPassportToolsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamPassportToolsReadAccess? = { _ in nil }
    var roamPrivateToolsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamPrivateToolsAccess? = { _ in nil }
    /// Internal scheduling seam, never a grant; the one-use final fence runs after it.
    var couponBeforeForward: (@MainActor () async -> Void)?
    /// Installed by AppSession; no runtime capability can be inferred from a root grant.
    var projectEditConfigurationRevision: @MainActor () -> UInt64? = { nil }
    var projectEditConfiguration: @MainActor (RuntimeDependencyContext) -> BusinessRuntimeConfiguration? = { _ in nil }
    var approvedReleaseConfigurationRevision: @MainActor () -> UInt64? = { nil }
    var approvedReleaseConfiguration: @MainActor (RuntimeDependencyContext) -> BusinessRuntimeConfiguration? = { _ in nil }
    var projectStoryAudioUploadApproval: @MainActor (RuntimeDependencyContext) -> ProjectStoryAudioUploadApproval? = { _ in nil }
    var projectTopicImageUploadApproval: @MainActor (RuntimeDependencyContext) -> ProjectTopicImageUploadApproval? = { _ in nil }
    var projectStoryImageUploadApproval: @MainActor (RuntimeDependencyContext) -> ProjectStoryImageUploadApproval? = { _ in nil }
    var ownedTopicCoverConfigurationRevision: @MainActor () -> UInt64? = { nil }
    var ownedTopicCoverApproval: @MainActor (RuntimeDependencyContext) -> OwnedTopicCoverApproval? = { _ in nil }
    var playReadConfiguration: @MainActor (RuntimeDependencyContext) -> RuntimeDependencyConfiguration? = { _ in nil }
    /// Only the normal GrowthCenterService receives this child. Generic/root routing is unchanged.
    func growthNormalReadTransport(approval: @escaping @MainActor (RuntimeDependencyContext) -> GrowthNormalReadApproval?) -> GrowthNormalReadTransport {
        GrowthNormalReadTransport(deployment: deployment, underlying: underlying,
            current: { [weak self] in self?.current() }, approval: approval)
    }

    private let deployment: ReviewedAppDeployment?
    private let underlying: any HTTPTransport
    private let manualMapReadApproval: @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval?
    private let ownedOrderReadApproval: @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval?
    private let couponReadApproval: @MainActor (RuntimeDependencyContext) -> CouponManagementReadApproval?
    private let couponWriteApproval: @MainActor (RuntimeDependencyContext) -> CouponManagementWriteApproval?
    private var profileFavoriteTopicSelection: ProfileFavoriteTopicSelection?
    private var profilePublicInfoTarget: ProfilePublicInfoTarget?
    private var publicMerchantHomeScope: PublicMerchantHomeCompositionScope?
    private var nearbyMerchantScope: NearbyMerchantCompositionScope?
    private var nearbyMerchantOnly = false
    private var merchantOverviewOnly = false
    private var merchantOverviewScope: MerchantOverviewScope?
    private var merchantPredictionOnly = false
    private var merchantPredictionScope: MerchantPredictionScope?
    private var merchantProjectParticipantsOnly = false
    private var merchantProjectParticipantsScope: MerchantProjectParticipantsScope?
    private var merchantProjectWorkspaceOnly = false
    private var merchantProjectWorkspaceScope: MerchantProjectWorkspaceScope?
    private var merchantProjectBrowseOnly = false
    private var merchantProjectBrowseScope: MerchantProjectBrowseScope?
    private var profileGuideSelection: ProfileGuideArticleSelection?
    private var profileFavoriteSelection: ProfileFavoritePostSelection?
    private let manualMapSelection: ManualMapAreaSelection?
    private let messagingHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval?
    private let roamSessionFactReadAccess: @MainActor (RuntimeDependencyContext) -> RoamSessionFactReadAccess?
    private let roamNearbyEventsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamNearbyEventsReadAccess?
    private let roamNearbyPlayersReadAccess: @MainActor (RuntimeDependencyContext) -> RoamNearbyPlayersReadAccess?
    private let profileOwnedCouponReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileOwnedCouponReadAccess?
    private let roamAlbumMetadataReadAccess: @MainActor (RuntimeDependencyContext) -> RoamAlbumMetadataReadAccess?
    private let roamTileMemoryReadAccess: @MainActor (RuntimeDependencyContext) -> RoamTileMemoryReadAccess?
    private let profilePublicInfoReadAccess: @MainActor (RuntimeDependencyContext) -> ProfilePublicInfoReadAccess?
    private let profileGuideReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileGuideReadAccess?
    private let profileFavoritesReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoritesReadAccess?
    private let profileFavoriteTopicReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoriteTopicReadAccess?
    private let profileFavoriteDetailAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoriteDetailAccess?
    private let profileInviteHistoryReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileInviteHistoryReadAccess?
    private let profileWeeklyPointsReadApproval: @MainActor (RuntimeDependencyContext) -> ProfileWeeklyPointsReadApproval?
    private let walletHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval?
    private let templateShelfReadApproval: @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval?
    private let cityPlayerReadApproval: @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval?
    private let teamReadApproval: @MainActor (RuntimeDependencyContext) -> TeamReadApproval?
    private let workshopCreatorPendingAuthorApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingAuthorApproval?
    private let workshopCreatorPendingListApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingListApproval?
    private let workshopCreatorPendingDetailApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingDetailApproval?
    private let workshopCreatorConsentReadApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorConsentReadApproval?
    private let workshopCreatorConsentWriteApproval: @MainActor (RuntimeDependencyContext) -> WorkshopCreatorConsentWriteApproval?
    private let workshopPaidProfessionalReadApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPaidProfessionalReadApproval?
    private let workshopPaidProfessionalWriteApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPaidProfessionalWriteApproval?
    private let workshopPaidInstalledTextApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstalledTextApproval?
    private let workshopPaidInstallApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstallApproval?
    private let workshopPurchasedReadApproval: @MainActor (RuntimeDependencyContext) -> WorkshopPurchasedReadApproval?
    private let workshopOwnedReadApproval: @MainActor (RuntimeDependencyContext) -> WorkshopOwnedReadApproval?
    private let ownerDraftReadApproval: @MainActor (RuntimeDependencyContext) -> OwnerDraftReadApproval?
    init(deployment: ReviewedAppDeployment?, underlying: any HTTPTransport,
         couponReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CouponManagementReadApproval? = { _ in nil },
         couponWriteApproval: @escaping @MainActor (RuntimeDependencyContext) -> CouponManagementWriteApproval? = { _ in nil },
         templateShelfReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval? = { _ in nil },
         messagingHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval? = { _ in nil },
         walletHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval? = { _ in nil },
         roamSessionFactReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamSessionFactReadAccess? = { _ in nil },
         roamNearbyEventsReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamNearbyEventsReadAccess? = { _ in nil },
         roamNearbyPlayersReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamNearbyPlayersReadAccess? = { _ in nil },
         profileOwnedCouponReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileOwnedCouponReadAccess? = { _ in nil },
         roamAlbumMetadataReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamAlbumMetadataReadAccess? = { _ in nil },
         roamTileMemoryReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> RoamTileMemoryReadAccess? = { _ in nil },
         profilePublicInfoReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfilePublicInfoReadAccess? = { _ in nil },
         profileGuideReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileGuideReadAccess? = { _ in nil },
         profileFavoritesReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileFavoritesReadAccess? = { _ in nil },
         profileFavoriteTopicReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileFavoriteTopicReadAccess? = { _ in nil },
         profileFavoriteDetailAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileFavoriteDetailAccess? = { _ in nil },
         profileInviteHistoryReadAccess: @escaping @MainActor (RuntimeDependencyContext) -> ProfileInviteHistoryReadAccess? = { _ in nil },
         profileWeeklyPointsReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ProfileWeeklyPointsReadApproval? = { _ in nil },
         cityPlayerReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval? = { _ in nil },
         teamReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TeamReadApproval? = { _ in nil },
         workshopCreatorPendingAuthorApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingAuthorApproval? = { _ in nil },
         workshopCreatorPendingListApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingListApproval? = { _ in nil },
         workshopCreatorPendingDetailApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorPendingDetailApproval? = { _ in nil },
         workshopCreatorConsentReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorConsentReadApproval? = { _ in nil },
         workshopCreatorConsentWriteApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopCreatorConsentWriteApproval? = { _ in nil },
         workshopPaidProfessionalReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidProfessionalReadApproval? = { _ in nil },
         workshopPaidProfessionalWriteApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidProfessionalWriteApproval? = { _ in nil },
         workshopPaidInstalledTextApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstalledTextApproval? = { _ in nil },
         workshopPaidInstallApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPaidInstallApproval? = { _ in nil },
         workshopPurchasedReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopPurchasedReadApproval? = { _ in nil },
         workshopOwnedReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WorkshopOwnedReadApproval? = { _ in nil },
         ownerDraftReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnerDraftReadApproval? = { _ in nil },
         manualMapReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval? = { _ in nil },
         manualMapSelection: ManualMapAreaSelection? = nil,
         ownedOrderReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval? = { _ in nil }) {
        self.couponReadApproval = couponReadApproval; self.couponWriteApproval = couponWriteApproval
        self.templateShelfReadApproval = templateShelfReadApproval
        self.messagingHistoryReadApproval = messagingHistoryReadApproval
        self.walletHistoryReadApproval = walletHistoryReadApproval
        self.roamSessionFactReadAccess = roamSessionFactReadAccess
        self.roamNearbyEventsReadAccess = roamNearbyEventsReadAccess
        self.roamNearbyPlayersReadAccess = roamNearbyPlayersReadAccess
        self.profileOwnedCouponReadAccess = profileOwnedCouponReadAccess
        self.roamAlbumMetadataReadAccess = roamAlbumMetadataReadAccess
        self.roamTileMemoryReadAccess = roamTileMemoryReadAccess
        self.profilePublicInfoReadAccess = profilePublicInfoReadAccess
        self.profileGuideReadAccess = profileGuideReadAccess
        self.profileFavoritesReadAccess = profileFavoritesReadAccess
        self.profileFavoriteTopicReadAccess = profileFavoriteTopicReadAccess
        self.profileFavoriteDetailAccess = profileFavoriteDetailAccess
        self.profileInviteHistoryReadAccess = profileInviteHistoryReadAccess
        self.profileWeeklyPointsReadApproval = profileWeeklyPointsReadApproval
        self.cityPlayerReadApproval = cityPlayerReadApproval
        self.teamReadApproval = teamReadApproval
        self.workshopCreatorPendingAuthorApproval = workshopCreatorPendingAuthorApproval
        self.workshopCreatorPendingListApproval = workshopCreatorPendingListApproval
        self.workshopCreatorPendingDetailApproval = workshopCreatorPendingDetailApproval
        self.workshopCreatorConsentReadApproval = workshopCreatorConsentReadApproval
        self.workshopCreatorConsentWriteApproval = workshopCreatorConsentWriteApproval
        self.workshopPaidProfessionalReadApproval = workshopPaidProfessionalReadApproval
        self.workshopPaidProfessionalWriteApproval = workshopPaidProfessionalWriteApproval
        self.workshopPaidInstalledTextApproval = workshopPaidInstalledTextApproval
        self.workshopPaidInstallApproval = workshopPaidInstallApproval
        self.workshopPurchasedReadApproval = workshopPurchasedReadApproval
        self.workshopOwnedReadApproval = workshopOwnedReadApproval
        self.deployment = deployment; self.underlying = underlying; self.ownerDraftReadApproval = ownerDraftReadApproval
        self.manualMapReadApproval = manualMapReadApproval; self.manualMapSelection = manualMapSelection
        self.ownedOrderReadApproval = ownedOrderReadApproval
    }
    func scopedForProfileFavoriteTopic(_ selection: ProfileFavoriteTopicSelection) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.profileFavoriteTopicSelection = selection
        return transport
    }
    /// Forward only an already-issued public-home approval. This does not create one.
    func scopedForPublicMerchantHome(approval: MerchantPublicProductionApproval,
                                     context: MerchantPublicHostContext) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        if let viewer = current() {
            transport.publicMerchantHomeScope = .init(approval: approval, context: context, viewer: viewer)
        }
        return transport
    }
    /// Public-home remains anonymous/read-only. Chat gets a separate signed-in,
    /// exact-route adapter bound to the same deployment/account/viewer revision.
    func scopedForMerchantGameNPC(approval: MerchantPublicProductionApproval, context: MerchantPublicHostContext,
                              grants: @escaping () -> MerchantNPCGrants) -> (any HTTPTransport)? {
        let matches: (ReviewedAppDeployment, SessionIdentity) -> Bool = { deployment, viewer in
            guard viewer.isSignedInContentViewer, let api = deployment.regional.apiConfiguration,
                  let actual = try? MerchantPublicHostContext(market: deployment.regional.market,
                    baseURL: api.baseURL, namespace: deployment.storageScope.service, accountID: viewer.accountID,
                    epoch: viewer.epoch, role: viewer.role, token: viewer.token) else { return false }
            return actual == context && approval.matches(actual)
        }
        guard let viewer = current(), let deployment, matches(deployment, viewer) else { return nil }
        return MerchantGameNPCProductionTransport(approval: approval, context: context, transport: underlying,
            current: { [weak self] in
                guard let self, let current = self.current(), current == viewer,
                      let deployment = self.deployment, matches(deployment, current) else { return nil }
                return context
            }, grants: grants)
    }
    func scopedForMerchantOverview(approval: MerchantOverviewReadApproval, context: RuntimeDependencyContext,
                                   approved: @escaping () -> Bool) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.merchantOverviewOnly = true; transport.merchantOverviewScope = nil
        if let viewer = current() { transport.merchantOverviewScope = .init(approval: approval, context: context, viewer: viewer, approved: approved) }
        return transport
    }
    func scopedForMerchantPrediction(approval: MerchantPredictionReadApproval, context: RuntimeDependencyContext,
                                     approved: @escaping () -> Bool) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.merchantPredictionOnly = true
        transport.merchantPredictionScope = nil
        if let viewer = current() { transport.merchantPredictionScope = .init(approval: approval, context: context, viewer: viewer, approved: approved) }
        return transport
    }
    func scopedForMerchantProjectParticipants(approval: MerchantProjectParticipantsReadApproval, context: RuntimeDependencyContext,
                                          topicID: Int, approved: @escaping () -> Bool) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.merchantProjectParticipantsOnly = true; transport.merchantProjectParticipantsScope = nil
        if topicID > 0, let viewer = current() {
            transport.merchantProjectParticipantsScope = .init(approval: approval, topicID: topicID, context: context, viewer: viewer, approved: approved)
        }
        return transport
    }
    func scopedForMerchantProjectWorkspace(approval: MerchantProjectWorkspaceReadApproval, context: RuntimeDependencyContext,
                                          topicID: Int, approved: @escaping () -> Bool) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.merchantProjectWorkspaceOnly = true; transport.merchantProjectWorkspaceScope = nil
        if topicID > 0, let viewer = current() {
            transport.merchantProjectWorkspaceScope = .init(approval: approval, topicID: topicID, context: context, viewer: viewer, approved: approved)
        }
        return transport
    }
    /// Dedicated read-only scope; no general merchant endpoint receives this grant.
    func scopedForMerchantProjectBrowse(approval: MerchantProjectBrowseApproval, context: RuntimeDependencyContext,
                                       approved: @escaping () -> Bool) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.merchantProjectBrowseOnly = true
        transport.merchantProjectBrowseScope = nil
        if let viewer = current() { transport.merchantProjectBrowseScope = .init(approval: approval, context: context, viewer: viewer, approved: approved) }
        return transport
    }
    /// Carries an existing nearby grant; it never enables the general runtime transport.
    func scopedForNearbyMerchants(configuration: RuntimeDependencyConfiguration,
                                  context: RuntimeDependencyContext) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.nearbyMerchantOnly = true
        if let viewer = current() {
            transport.nearbyMerchantScope = .init(configuration: configuration, context: context, viewer: viewer)
        }
        return transport
    }
    func scopedForProfilePublicInfo(_ target: ProfilePublicInfoTarget) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.profilePublicInfoTarget = target
        return transport
    }
    func scopedForProfileGuide(_ selection: ProfileGuideArticleSelection) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.profileGuideSelection = selection
        return transport
    }
    func scopedForProfileFavorite(_ selection: ProfileFavoritePostSelection) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.profileGuideSelection = profileGuideSelection
        transport.profileFavoriteSelection = selection
        return transport
    }
    func scopedForManualMap(_ selection: ManualMapAreaSelection) -> CompositionHTTPTransport {
        copy(underlying: underlying, manualMapSelection: selection)
    }
    func scopedForClubPostImageUpload(clubID: Int) -> CompositionHTTPTransport {
        let transport = copy(underlying: underlying, manualMapSelection: manualMapSelection)
        transport.clubPostImageUploadClubID = clubID
        return transport
    }
    private func channelMessageContextMatches(_ context: RuntimeDependencyContext, viewer: SessionIdentity) -> Bool {
        guard let deployment, let api = deployment.regional.apiConfiguration, viewer.isSignedInContentViewer else { return false }
        return context.market == deployment.regional.market && context.baseURL == api.baseURL &&
            context.session.namespace == deployment.storageScope.service && context.role == viewer.role &&
            context.session.accountID == viewer.accountID && context.session.epoch == viewer.epoch && context.session.token == viewer.token
    }
    /// Independent descriptor final-forward. A route in the live configuration must
    /// already exist; this does not register routes or admit GET to generic send().
    func makeNativeChannelAttachmentDescriptorTransport(messageID: Int, context: RuntimeDependencyContext,
        issued: BusinessRuntimeConfiguration, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentConfiguration: @escaping () -> BusinessRuntimeConfiguration?,
        stillCurrent: @escaping () -> Bool) -> NativeChannelAttachmentDescriptorTransport? {
        guard let captured = current(), channelMessageContextMatches(context, viewer: captured),
              ContentDraftContextFence.matches(currentRuntime(), context), stillCurrent() else { return nil }
        return NativeChannelAttachmentDescriptorTransport(messageID: messageID, context: context,
            issued: issued, underlying: underlying, runtime: currentRuntime,
            configuration: currentConfiguration, presentation: { [weak self] in
                self?.current() == captured && stillCurrent()
            })
    }
    /// Reuse the private original wire, preserving the generic history gate and independent Text grants.
    func makeNativeChannelMessageOriginalAdapters(context: RuntimeDependencyContext, binding: NativeChannelMessageBinding,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, stillCurrent: @escaping () -> Bool,
        read: @escaping () -> NativeChannelTextApproval?, write: @escaping () -> NativeChannelTextApproval?,
        received401: @escaping () -> Void) throws -> NativeChannelMessageOriginalAdapters {
        guard let api = deployment?.regional.apiConfiguration, let captured = current(),
              channelMessageContextMatches(context, viewer: captured), ContentDraftContextFence.matches(currentRuntime(), context),
              stillCurrent() else { throw APIError.notConfigured }
        let wire = NativeChannelMessageOriginalWireBridge(binding: binding, configuration: api, underlying: underlying,
            current: { [weak self] in self?.current() == captured && stillCurrent() }, received401: received401)
        let scoped = replacingUnderlying(wire)
        return NativeChannelMessageOriginalAdapters(wire: wire, historyTransport: scoped,
            textTransport: scoped.makeNativeChannelTextTransport(context: context, currentRuntime: currentRuntime,
                read: read, write: write, stillCurrent: stillCurrent))
    }
    /// Only the existing message operation protocol is admitted here, never generic IM send.
    func makeNativeChannelMessageDispatcher(authority: NativeChannelMessageHostAuthority,
        journal: NativeChannelMessageMutationJournal, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        stillCurrent: @escaping () -> Bool, onUnauthorized: @escaping (MessagingReadIdentity) -> Void) throws -> NativeChannelMessageFinalForward {
        guard let captured = current(), channelMessageContextMatches(authority.context, viewer: captured),
              captured.viewerRevision == authority.viewerRevision,
              ContentDraftContextFence.matches(currentRuntime(), authority.context), stillCurrent() else { throw APIError.notConfigured }
        return try NativeChannelMessageFinalForward(authority: authority, journal: journal, underlying: underlying,
            current: { [weak self] in self?.current() == captured && stillCurrent() }, onUnauthorized: onUnauthorized)
    }
    /// Dedicated canonical text transport over the existing private adapter. This does not
    /// admit send/send-receipt through generic IM or widen any history/read capability.
    func makeNativeChannelTextTransport(context: RuntimeDependencyContext,
        currentRuntime: @escaping () -> RuntimeDependencyContext?,
        read: @escaping () -> NativeChannelTextApproval? = { nil },
        write: @escaping () -> NativeChannelTextApproval? = { nil },
        stillCurrent: @escaping () -> Bool = { false }) -> NativeChannelTextTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let viewer = current(), viewer.isSignedInContentViewer,
              viewer.accountID == context.session.accountID, viewer.epoch == context.session.epoch,
              viewer.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              viewer.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), stillCurrent() else { return nil }
        return NativeChannelTextTransport(context: context, transport: underlying,
            current: currentRuntime, read: read, write: write, stillCurrent: { [weak self] in
                self?.current() == viewer && stillCurrent()
            })
    }

    /// Consume exact existing host capabilities on the original underlying transport.
    /// Generic send(_:) and all approval selectors remain unchanged.
    func makeNativeChannelManagementDispatcher(context: RuntimeDependencyContext,
        scope: NativeChannelManagementScope, viewerRevision: UInt64,
        currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentViewer: @escaping () -> UInt64,
        selectedApproval: @escaping () -> NativeChannelManagementApproval?) -> NativeChannelManagementFinalForward? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentViewer() == viewerRevision else { return nil }
        return try? NativeChannelManagementFinalForward(context: context, scope: scope, viewerRevision: viewerRevision,
            underlying: underlying, current: { [weak self] in
                guard self?.current() == captured else { return nil }; return currentRuntime()
            }, viewer: currentViewer, selected: selectedApproval)
    }

    func sendNativeFriendChannelInvite(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeFriendChannelInviteApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeFriendChannelInviteTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeFriendChannelInviteTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeFriendChannelSource(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeFriendChannelSourceApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeFriendChannelSourceTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeFriendChannelSourceTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeFriendTeamInvite(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeFriendTeamInviteApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeFriendTeamInviteTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeFriendTeamInviteTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeFriendMetadata(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeFriendMetadataApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeFriendMetadataTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeFriendMetadataTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeFriendRemoval(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeFriendRemovalApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeFriendRemovalTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeFriendRemovalTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeBlacklist(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeBlacklistApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeBlacklistTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeBlacklistFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeBlacklistFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeBlacklistTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeBlacklistFailure.unknown
        }
        return result
    }

    func sendNativeFriendDirectory(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeFriendDirectoryApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeFriendDirectoryTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeFriendDirectoryTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeFriendProgress(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeFriendProgressApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeFriendProgressTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeFriendProgressTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeFriend(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeFriendApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeFriendTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeFriendTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeProgressPrivacy(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeProgressPrivacyApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeProgressPrivacyTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeFriendFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeProgressPrivacyTransportPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeFriendFailure.unknown
        }
        return result
    }

    func sendNativeChannelOnboarding(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeChannelOnboardingApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeChannelOnboardingPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeSpaceAdmissionFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeSpaceAdmissionFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeChannelOnboardingPolicy.accepts(request, context: context, approval: approval) else {
            throw NativeSpaceAdmissionFailure.unknown
        }
        return result
    }

    func sendNativeChannelWelcome(_ request: URLRequest, context: RuntimeDependencyContext,
                          approval: NativeChannelWelcomeApproval, stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), NativeChannelWelcomePolicy.accepts(request, context: context, approval: approval) else {
            throw NativeSpaceAdmissionFailure.notSent
        }
        guard !Task.isCancelled else { throw NativeSpaceAdmissionFailure.notSent }
        let result = try await underlying.send(request)
        guard current() == captured, stillApproved(), !Task.isCancelled,
              NativeChannelWelcomePolicy.accepts(request, context: context, approval: approval) else {
            throw NativeSpaceAdmissionFailure.unknown
        }
        return result
    }

    /// Dedicated Progress final forward, preserving the original client operation fence.
    func makeNativeChannelProgressFinalForward(context: RuntimeDependencyContext,
        selection: NativeChannelProgressRuntimeSelection, journal: NativeChannelProgressPrivacyJournal,
        currentRuntime: @escaping () -> RuntimeDependencyContext?,
        selected: @escaping () -> NativeChannelProgressRuntimeSelection?, stillCurrent: @escaping () -> Bool,
        receiptApproval: @escaping (NativeChannelProgressPrivacyCommand) -> OperationEndpointApproval?) -> NativeChannelProgressFinalForward? {
        guard let captured = current(), channelMessageContextMatches(context, viewer: captured),
              ContentDraftContextFence.matches(currentRuntime(), context), stillCurrent() else { return nil }
        guard let forward = underlying as? any NativeChannelProgressDispatching else { return nil }
        return try? NativeChannelProgressFinalForward(context: context, selection: selection, journal: journal,
            underlying: forward, current: currentRuntime, selected: selected,
            presentation: { [weak self] in self?.current() == captured && stillCurrent() }, receiptApproval: receiptApproval)
    }

    /// Bounded Webhook transport, separate from the generic composition route catalog.
    func makeNativeWebhookFinalForwardTransport(context: RuntimeDependencyContext, scope: NativeWebhookScope,
        issued: OperationEndpointApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentApproval: @escaping () -> OperationEndpointApproval?, stillCurrent: @escaping () -> Bool)
        -> NativeWebhookFinalForwardTransport? {
        guard let captured = current(), channelMessageContextMatches(context, viewer: captured),
              ContentDraftContextFence.matches(currentRuntime(), context), stillCurrent() else { return nil }
        return NativeWebhookFinalForwardTransport(captured: context, scope: scope, issued: issued,
            underlying: underlying, current: currentRuntime, approval: currentApproval,
            presentation: { [weak self] in self?.current() == captured && stillCurrent() })
    }
    func makeNativeChannelHostRuntimeTransport(context: RuntimeDependencyContext,
        issued: BusinessRuntimeConfiguration, features: Set<BusinessRuntimeFeature>,
        currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentConfiguration: @escaping () -> BusinessRuntimeConfiguration?,
        stillCurrent: @escaping () -> Bool) -> NativeChannelHostRuntimeTransport? {
        guard let captured = current(), channelMessageContextMatches(context, viewer: captured),
              ContentDraftContextFence.matches(currentRuntime(), context), stillCurrent() else { return nil }
        return NativeChannelHostRuntimeTransport(context: context, issued: issued, features: features,
            underlying: underlying, runtime: currentRuntime, configuration: currentConfiguration,
            presentation: { [weak self] in self?.current() == captured && stillCurrent() })
    }
    func makeNativeChannelNotificationDispatcher(context: RuntimeDependencyContext, viewerRevision: UInt64,
        source: any NativeChannelNotificationAuthorizing, journal: NativeChannelNotificationJournal,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, currentViewer: @escaping () -> UInt64,
        selectedSource: @escaping () -> (any NativeChannelNotificationAuthorizing)?) -> NativeChannelNotificationFinalForward? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentViewer() == viewerRevision else { return nil }
        return try? NativeChannelNotificationFinalForward(context: context, viewerRevision: viewerRevision,
            source: source, journal: journal, underlying: underlying, current: { [weak self] in
                guard self?.current() == captured else { return nil }; return currentRuntime()
            }, viewer: currentViewer, selected: selectedSource)
    }
    /// Replacing only the network/recorder adapter must preserve every approval selector.
    func replacingUnderlying(_ underlying: any HTTPTransport) -> CompositionHTTPTransport {
        copy(underlying: underlying, manualMapSelection: manualMapSelection)
    }
    private func copy(underlying: any HTTPTransport, manualMapSelection: ManualMapAreaSelection?) -> CompositionHTTPTransport {
        let transport = CompositionHTTPTransport(deployment: deployment, underlying: underlying,
            couponReadApproval: couponReadApproval, couponWriteApproval: couponWriteApproval,
            templateShelfReadApproval: templateShelfReadApproval, messagingHistoryReadApproval: messagingHistoryReadApproval, walletHistoryReadApproval: walletHistoryReadApproval, roamSessionFactReadAccess: roamSessionFactReadAccess, roamNearbyEventsReadAccess: roamNearbyEventsReadAccess, roamNearbyPlayersReadAccess: roamNearbyPlayersReadAccess, profileOwnedCouponReadAccess: profileOwnedCouponReadAccess, roamAlbumMetadataReadAccess: roamAlbumMetadataReadAccess, roamTileMemoryReadAccess: roamTileMemoryReadAccess, profilePublicInfoReadAccess: profilePublicInfoReadAccess, profileGuideReadAccess: profileGuideReadAccess, profileFavoritesReadAccess: profileFavoritesReadAccess, profileFavoriteTopicReadAccess: profileFavoriteTopicReadAccess, profileFavoriteDetailAccess: profileFavoriteDetailAccess, profileInviteHistoryReadAccess: profileInviteHistoryReadAccess, profileWeeklyPointsReadApproval: profileWeeklyPointsReadApproval, cityPlayerReadApproval: cityPlayerReadApproval, teamReadApproval: teamReadApproval, workshopCreatorPendingAuthorApproval: workshopCreatorPendingAuthorApproval, workshopCreatorPendingListApproval: workshopCreatorPendingListApproval, workshopCreatorPendingDetailApproval: workshopCreatorPendingDetailApproval, workshopCreatorConsentReadApproval: workshopCreatorConsentReadApproval, workshopCreatorConsentWriteApproval: workshopCreatorConsentWriteApproval, workshopPaidProfessionalReadApproval: workshopPaidProfessionalReadApproval, workshopPaidProfessionalWriteApproval: workshopPaidProfessionalWriteApproval, workshopPaidInstalledTextApproval: workshopPaidInstalledTextApproval, workshopPaidInstallApproval: workshopPaidInstallApproval, workshopPurchasedReadApproval: workshopPurchasedReadApproval, workshopOwnedReadApproval: workshopOwnedReadApproval, ownerDraftReadApproval: ownerDraftReadApproval, manualMapReadApproval: manualMapReadApproval,
            manualMapSelection: manualMapSelection, ownedOrderReadApproval: ownedOrderReadApproval)
        // Retain the identity source across temporary clone chains. Its AppSession
        // callback is weak, so this does not retain or extend the signed-in session.
        transport.current = { self.current() }
        transport.officialPublicEventReadSelection = officialPublicEventReadSelection
        transport.merchantGamePlayerReadGrant = merchantGamePlayerReadGrant
        transport.memberRoleInfoReadApproval = memberRoleInfoReadApproval
        transport.ownMediaReadApproval = ownMediaReadApproval
        transport.mapPublicLayerReadApproval = mapPublicLayerReadApproval
        transport.clubCommunityReadApproval = { self.clubCommunityReadApproval($0) }
        transport.clubPublicRosterApproval = { self.clubPublicRosterApproval($0) }
        transport.clubPublicTopicsApproval = { self.clubPublicTopicsApproval($0, $1) }
        transport.clubPostOriginalApproval = { self.clubPostOriginalApproval($0) }
        transport.clubCommentOriginalApproval = { self.clubCommentOriginalApproval($0) }
        transport.clubOrdinaryAdmissionApproval = { self.clubOrdinaryAdmissionApproval($0) }
        transport.clubRoleAssignmentApproval = { self.clubRoleAssignmentApproval($0) }
        transport.clubRoleRevocationApproval = { self.clubRoleRevocationApproval($0) }
        transport.clubPostImageUploadApproval = { self.clubPostImageUploadApproval($0, $1) }
        transport.clubPostImageUploadClubID = clubPostImageUploadClubID
        transport.roamEntryNearbyReadAccess = roamEntryNearbyReadAccess
        transport.roamReceivedStampReadAccess = roamReceivedStampReadAccess
        transport.roamPassportHistoryReadAccess = roamPassportHistoryReadAccess
        transport.roamPassportToolsReadAccess = roamPassportToolsReadAccess
        transport.roamPrivateToolsReadAccess = roamPrivateToolsReadAccess
        transport.profileFavoriteTopicSelection = profileFavoriteTopicSelection
        transport.profilePublicInfoTarget = profilePublicInfoTarget
        transport.publicMerchantHomeScope = publicMerchantHomeScope
        transport.nearbyMerchantScope = nearbyMerchantScope
        transport.nearbyMerchantOnly = nearbyMerchantOnly
        transport.merchantOverviewOnly = merchantOverviewOnly
        transport.merchantOverviewScope = merchantOverviewScope
        transport.merchantPredictionOnly = merchantPredictionOnly
        transport.merchantPredictionScope = merchantPredictionScope
        transport.merchantProjectParticipantsOnly = merchantProjectParticipantsOnly
        transport.merchantProjectParticipantsScope = merchantProjectParticipantsScope
        transport.merchantProjectWorkspaceOnly = merchantProjectWorkspaceOnly
        transport.merchantProjectWorkspaceScope = merchantProjectWorkspaceScope
        transport.merchantProjectBrowseOnly = merchantProjectBrowseOnly
        transport.merchantProjectBrowseScope = merchantProjectBrowseScope
        transport.profileGuideSelection = profileGuideSelection
        transport.profileFavoriteSelection = profileFavoriteSelection
        transport.activityCoverApproval = { self.activityCoverApproval($0) }
        transport.activityEditingApproval = { self.activityEditingApproval($0) }
        transport.publisherIdentityRegistrationApproval = { self.publisherIdentityRegistrationApproval($0) }
        transport.workshopPaidInstallBeforeForward = { if let barrier = self.workshopPaidInstallBeforeForward { await barrier() } }
        transport.couponBeforeForward = { if let barrier = self.couponBeforeForward { await barrier() } }
        // Forward the mutable selector itself: later installation or revocation on
        // the root must reach every existing scoped/replaced transport clone.
        transport.playReadConfiguration = { self.playReadConfiguration($0) }
        transport.projectEditConfigurationRevision = { self.projectEditConfigurationRevision() }
        transport.projectEditConfiguration = { self.projectEditConfiguration($0) }
        transport.approvedReleaseConfigurationRevision = { self.approvedReleaseConfigurationRevision() }
        transport.approvedReleaseConfiguration = { self.approvedReleaseConfiguration($0) }
        transport.projectStoryAudioUploadApproval = { self.projectStoryAudioUploadApproval($0) }
        transport.projectTopicImageUploadApproval = { self.projectTopicImageUploadApproval($0) }
        transport.projectStoryImageUploadApproval = { self.projectStoryImageUploadApproval($0) }
        transport.ownedTopicCoverConfigurationRevision = { self.ownedTopicCoverConfigurationRevision() }
        transport.ownedTopicCoverApproval = { self.ownedTopicCoverApproval($0) }
        return transport
    }
    /// No ordinary send path admits these writes, even when a read or write lease exists.
    func sendConfirmed(_ request: URLRequest, authorization: CouponManagementDispatchAuthorization) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration, let captured = current(),
              captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role,
              let token = captured.token, let session = try? PlayExperienceSession(accountID: account,
                epoch: captured.epoch, namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
        let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
        guard let read = couponReadApproval(context), read.matches(context),
              let write = couponWriteApproval(context), let merchantID = authorization.permission.merchantID,
              merchantID == read.merchantID,
              write.matches(context, merchantID: merchantID, path: authorization.record.request.path),
              let expected = CouponManagementRuntimeIdentity.session(context: context, viewerRevision: captured.viewerRevision, read: read, write: write),
              authorization.session == expected else { throw APIError.notConfigured }
        if authorization.record.command != nil {
            guard let capability = read.commandProtocol, capability.matches(context, merchantID: merchantID) else { throw APIError.notConfigured }
        } else if read.commandProtocol != nil { throw APIError.notConfigured }
        func valid() -> Bool {
            current() == captured && couponReadApproval(context)?.revision == read.revision && read.matches(context) &&
            couponWriteApproval(context)?.revision == write.revision && write.matches(context, merchantID: merchantID, path: authorization.record.request.path)
        }
        if let couponBeforeForward { await couponBeforeForward() }
        guard valid() else { throw CouponManagementError.changed }
        let credentials = try CouponManagementReadCredentials(session: expected, token: token)
        try authorization.consume(request, configuration: api, credentials: credentials)
        // No await between one-use validation, durable-record proof and the underlying dispatch.
        do {
            let response = try await underlying.send(request)
            guard valid(), !Task.isCancelled else { throw CouponManagementError.changed }
            try authorization.validate()
            return response
        } catch {
            guard valid(), !Task.isCancelled else { throw CouponManagementError.changed }
            throw error
        }
    }
    /// Only an explicit persisted author command reaches this separately approved route.
    func sendWorkshopCreatorPendingAuthor(_ request: URLRequest, authorization: WorkshopCreatorPendingAuthorization) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration, let captured = current(), captured.isSignedInContentViewer,
              let account = captured.accountID, let role = captured.role, let token = captured.token,
              let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token, role: role),
              WorkshopCreatorPendingRequest.accepts(request, baseURL: api.baseURL) == .author else { throw APIError.notConfigured }
        let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
        guard let grant = workshopCreatorPendingAuthorApproval(context), grant.matches(context) else { throw APIError.notConfigured }
        func valid() -> Bool {
            guard current() == captured, let latest = workshopCreatorPendingAuthorApproval(context) else { return false }
            return latest.revision == grant.revision && latest.matches(context) && grant.matches(context)
        }
        try Task.checkCancellation(); guard valid() else { throw CancellationError() }
        try authorization.consume(request, context: context, revision: grant.revision)
        do {
            let response = try await underlying.send(request)
            guard valid(), !Task.isCancelled else { throw CancellationError() }; try authorization.validate(); return response
        } catch { guard valid(), !Task.isCancelled else { throw CancellationError() }; try authorization.validate(); throw error }
    }
    /// A creator's one-use declaration requires its own write grant and the reviewed read grant.
    func sendWorkshopCreatorConsent(_ request: URLRequest, authorization: WorkshopCreatorConsentDispatchAuthorization) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration, let captured = current(), captured.isSignedInContentViewer,
              let account = captured.accountID, let role = captured.role, let token = captured.token,
              let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token, role: role),
              WorkshopCreatorConsentRequest.accepts(request, baseURL: api.baseURL) == .declare else { throw APIError.notConfigured }
        let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
        guard let read = workshopCreatorConsentReadApproval(context), read.matches(context),
              let write = workshopCreatorConsentWriteApproval(context), write.matches(context) else { throw APIError.notConfigured }
        func valid() -> Bool {
            guard current() == captured, let r = workshopCreatorConsentReadApproval(context), let w = workshopCreatorConsentWriteApproval(context) else { return false }
            return r.revision == read.revision && w.revision == write.revision && r.matches(context) && w.matches(context) && read.matches(context) && write.matches(context)
        }
        try Task.checkCancellation(); guard valid() else { throw CancellationError() }
        try authorization.consume(request, context: context, revision: write.revision)
        do {
            let response = try await underlying.send(request)
            guard valid(), !Task.isCancelled else { throw CancellationError() }; try authorization.validate(); return response
        } catch { guard valid(), !Task.isCancelled else { throw CancellationError() }; try authorization.validate(); throw error }
    }
    /// Independent one-use professional create/cancel dispatch; a read grant never reaches this path.
    func sendWorkshopPaidProfessional(_ request: URLRequest, authorization: WorkshopPaidProfessionalDispatchAuthorization) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration, let captured = current(), captured.isSignedInContentViewer,
              let account = captured.accountID, let role = captured.role, let token = captured.token,
              let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token, role: role),
              let route = WorkshopPaidProfessionalRequest.accepts(request, baseURL: api.baseURL), route == .submit || route == .cancel else { throw APIError.notConfigured }
        let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
        guard let approval = workshopPaidProfessionalWriteApproval(context), approval.matches(context) else { throw APIError.notConfigured }
        func valid() -> Bool {
            guard current() == captured, let fresh = workshopPaidProfessionalWriteApproval(context) else { return false }
            return fresh.revision == approval.revision && fresh.matches(context) && approval.matches(context)
        }
        try Task.checkCancellation(); guard valid() else { throw CancellationError() }
        try authorization.consume(request, context: context, revision: approval.revision)
        do {
            let response = try await underlying.send(request)
            try Task.checkCancellation(); guard valid() else { throw CancellationError() }; try authorization.validate(); return response
        } catch {
            guard valid(), !Task.isCancelled else { throw CancellationError() }; try authorization.validate(); throw error
        }
    }
    /// Dedicated one-use paid private-install dispatch. Ordinary send never admits submit.
    func sendWorkshopPaidInstall(_ request: URLRequest, authorization: WorkshopPaidInstallDispatchAuthorization) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration, let captured = current(), captured.isSignedInContentViewer,
              let account = captured.accountID, let role = captured.role, let token = captured.token,
              let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token),
              WorkshopPaidInstallRequest.accepts(request, baseURL: api.baseURL) == .submit else { throw APIError.notConfigured }
        let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
        guard let approval = workshopPaidInstallApproval(context), approval.matches(context) else { throw APIError.notConfigured }
        func valid() -> Bool { current() == captured && workshopPaidInstallApproval(context)?.revision == approval.revision && approval.matches(context) }
        if let workshopPaidInstallBeforeForward { await workshopPaidInstallBeforeForward() }
        try Task.checkCancellation(); guard valid() else { throw CancellationError() }
        try authorization.consume(request, context: context, revision: approval.revision)
        // No suspension between one-use confirmation validation and underlying dispatch.
        do {
            let response = try await underlying.send(request)
            try Task.checkCancellation(); guard valid() else { throw CancellationError() }; try authorization.validate(); return response
        } catch {
            guard valid(), !Task.isCancelled else { throw CancellationError() }; try authorization.validate(); throw error
        }
    }
    func sendPublisherIdentityRegistration(_ request: URLRequest, session: PublishingSession,
        grants: PublisherIdentityRegistrationGrants) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.market == .china, let api = deployment.regional.apiConfiguration,
              let captured = current(), captured.isSignedInContentViewer,
              let account = captured.accountID, let role = captured.role, role == "club", let token = captured.token,
              session.region == .china, session.accountID == account, session.role == role,
              session.namespace == deployment.storageScope.service,
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(token.utf8),
              let runtime = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                  namespace: deployment.storageScope.service, token: token),
              let path = PublisherIdentityRegistrationWire.path(request, configuration: api) else { throw APIError.notConfigured }
        let context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: role, session: runtime)
        func permitted() -> Bool {
            let live = publisherIdentityRegistrationApproval(context)
            let approval = path == PublisherIdentityRegistrationWire.statusPath ? live.read : live.register
            return live == grants && live.revision != nil &&
                approval?.allows(configuration: api, namespace: session.namespace, accountID: account, path: path) == true
        }
        try Task.checkCancellation(); guard current() == captured, permitted() else { throw APIError.notConfigured }
        let response = try await underlying.send(request)
        try Task.checkCancellation(); guard current() == captured, permitted() else { throw CancellationError() }
        return response
    }

    func sendActivityCover(_ request: URLRequest, session: PublishingSession, approval: ActivityCoverApproval,
                           current ownerCurrent: @escaping () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.market == .china, let api = deployment.regional.apiConfiguration,
              let captured = current(), captured.isSignedInContentViewer, let account = captured.accountID,
              let role = captured.role, let token = captured.token, ["club", "merchant"].contains(role),
              session.region == .china, session.accountID == account, session.role == role,
              session.namespace == deployment.storageScope.service,
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(token.utf8),
              let runtime = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                  namespace: deployment.storageScope.service, token: token),
              ActivityCoverWire.accepts(request, configuration: api) else { throw APIError.notConfigured }
        let context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: role, session: runtime)
        func permitted() -> Bool {
            ownerCurrent() && current() == captured && activityCoverApproval(context) == approval &&
                approval.endpoint.allows(configuration: api, namespace: session.namespace, accountID: account, path: ActivityCoverService.path)
        }
        try Task.checkCancellation(); guard permitted() else { throw APIError.notConfigured }
        let result = try await underlying.send(request)
        try Task.checkCancellation(); guard permitted() else { throw CancellationError() }
        return result
    }

    func sendActivityEditing(_ request: URLRequest, activityID: Int, session: PublishingSession,
                             grants: ActivityEditingGrants) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.market == .china, let api = deployment.regional.apiConfiguration,
              let captured = current(), captured.isSignedInContentViewer,
              let account = captured.accountID, let role = captured.role, let token = captured.token,
              ["club", "merchant"].contains(role), session.region == .china, session.accountID == account, session.role == role,
              session.namespace == deployment.storageScope.service,
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(token.utf8),
              let runtime = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                  namespace: deployment.storageScope.service, token: token),
              let path = ActivityEditingWire.path(request, activityID: activityID, configuration: api) else { throw APIError.notConfigured }
        if path == ActivityEditingService.updatePath {
            guard let body = request.httpBody, let fields = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: body),
                  fields["scope"] == (role == "merchant" ? .string("MERCHANT") : nil) else { throw APIError.notConfigured }
        }
        let context = RuntimeDependencyContext(market: .china, baseURL: api.baseURL, role: role, session: runtime)
        func permitted() -> Bool {
            let currentGrant = activityEditingApproval(context)
            let approval = path == ActivityEditingService.readPath ? currentGrant.read : currentGrant.update
            return currentGrant == grants && currentGrant.revision != nil &&
                approval?.allows(configuration: api, namespace: session.namespace, accountID: account, path: path) == true
        }
        try Task.checkCancellation()
        guard current() == captured, permitted() else { throw APIError.notConfigured }
        let reply = try await underlying.send(request)
        try Task.checkCancellation()
        guard current() == captured, permitted() else { throw CancellationError() }
        return reply
    }

    /// Existing manual-map grant only. The body is the adapter's POST JSON, not a new auth scheme.
    /// `aggregatedQueryEnabled` stays false. The selected manual center has to sit inside the box.
    private static func acceptsPublicLayers(_ request: URLRequest, baseURL: URL, area: RoamSearchArea) -> Bool {
        guard MapLayerFeature.aggregatedQueryEnabled == false,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              let url = request.url, url.query == nil, url.fragment == nil,
              url.absoluteString == baseURL.appendingPathComponent("api/map/public-layers").absoluteString,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let body = request.httpBody, (1...8192).contains(body.count),
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(object.keys).isSubset(of: ["datum", "minLat", "maxLat", "minLng", "maxLng", "limit", "layers", "cursor", "aggregatedQueryEnabled"]),
              (object["datum"] as? String) == MapPublicLayerAdapter.datum else { return false }
        if object.keys.contains("aggregatedQueryEnabled"), (object["aggregatedQueryEnabled"] as? Bool) != false { return false }
        guard let limit = object["limit"] as? NSNumber, CFGetTypeID(limit) != CFBooleanGetTypeID(),
              let limitValue = Int(exactly: limit.doubleValue), MapPublicLayerAdapter.pageLimit.contains(limitValue),
              let layers = object["layers"] as? [String], MapPublicLayerAdapter.layerCount.contains(layers.count),
              Set(layers).count == layers.count, Set(layers).isSubset(of: Set(MapPublicLayerAdapter.knownSources)) else { return false }
        if let cursor = object["cursor"] {
            guard let text = cursor as? String, !text.isEmpty, text.count <= 2048 else { return false }
        }
        func edge(_ key: String) -> Double? {
            guard let number = object[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        guard let south = edge("minLat"), let north = edge("maxLat"), let west = edge("minLng"), let east = edge("maxLng"),
              south <= north, west <= east,
              south <= area.coordinate.latitude, area.coordinate.latitude <= north,
              west <= area.coordinate.longitude, area.coordinate.longitude <= east else { return false }
        return true
    }

    func makeMemberReportProgressTransport(context: RuntimeDependencyContext, approval: MemberReportProgressApproval,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, stillSelected: @escaping () -> Bool) -> MemberReportProgressScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              deployment.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              MemberReportProgressScope.matches(currentRuntime(), context), approval.matches(context), stillSelected() else { return nil }
        return MemberReportProgressScopedTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            stillSelected: stillSelected)
    }
    func makeNPCChatDataReadTransport(context: RuntimeDependencyContext, approval: NPCChatDataReadApproval,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, stillSelected: @escaping () -> Bool) -> NPCChatDataReadScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              deployment.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              NPCChatDataReadScope.matches(currentRuntime(), context), approval.matches(context), stillSelected() else { return nil }
        return NPCChatDataReadScopedTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            stillSelected: stillSelected)
    }
    func makeSupportTicketReadTransport(context: RuntimeDependencyContext, approval: SupportTicketReadApproval,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, stillSelected: @escaping () -> Bool) -> SupportTicketReadScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              deployment.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              SupportTicketReadScope.matches(currentRuntime(), context), approval.matches(context), stillSelected() else { return nil }
        return SupportTicketReadScopedTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            stillSelected: stillSelected)
    }
    func makeMemberScoreReadTransport(context: RuntimeDependencyContext, approval: MemberScoreListApproval,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, stillSelected: @escaping () -> Bool) -> MemberScoreAppealScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              deployment.regional.market == context.market,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              MemberScoreReadScope.matches(currentRuntime(), context), approval.matches(context), stillSelected() else { return nil }
        return MemberScoreAppealScopedTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            stillSelected: stillSelected)
    }
    /// Dedicated original usage-evidence GETs. Generic compliance paths remain unchanged/default-deny.
    func makeUsageConsentReadTransport(context: RuntimeDependencyContext, approval: UsageConsentReadApproval,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, stillApproved: @escaping () -> Bool) -> UsageConsentReadScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              UsageConsentReadScope.matches(currentRuntime(), context), stillApproved(),
              approval.endpoint.paths.contains(where: { approval.allows(context, path: $0) }) else { return nil }
        return UsageConsentReadScopedTransport(context: context, approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            stillApproved: stillApproved)
    }
    /// Original marketing routes only; no generic compliance or campaign permission is borrowed.
    func makeMerchantMarketingConsentOriginalTransport(context: RuntimeDependencyContext,
        approval: MerchantMarketingConsentOriginalApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        stillApproved: @escaping () -> Bool) -> MerchantMarketingConsentScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              context.role.utf8.elementsEqual(context.session.role.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), approval.matches(context), stillApproved() else { return nil }
        return MerchantMarketingConsentScopedTransport(context: context, approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            stillApproved: stillApproved)
    }
    /// Original C08 route only. Reuses the current complete viewer fence, not the old host helper.
    func makeAccountDeregistrationOriginalTransport(context: RuntimeDependencyContext,
        approval: AccountDeregistrationOriginalApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        stillApproved: @escaping () -> Bool) -> AccountDeregistrationScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              context.role.utf8.elementsEqual(context.session.role.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), approval.matches(context), stillApproved() else { return nil }
        return AccountDeregistrationScopedTransport(context: context, approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            stillApproved: stillApproved)
    }
    /// Dedicated original personal template producer and read-only recovery; no new grant is created.
    func makeTemplateAuthoringRequestService(context: RuntimeDependencyContext,
        session: TemplateAuthoringSession,
        readApproval: OperationEndpointApproval?, submitApproval: OperationEndpointApproval?,
        currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentReadApproval: @escaping () -> OperationEndpointApproval?,
        currentSubmitApproval: @escaping () -> OperationEndpointApproval?) -> TemplateAuthoringRequestHTTPService? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              session.accountID == context.session.accountID, session.epoch == context.session.epoch,
              session.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              session.authorizationRevision.utf8.elementsEqual(context.role.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context),
              readApproval != nil || submitApproval != nil else { return nil }
        return TemplateAuthoringRequestHTTPService(configuration: api, transport: underlying,
            readApproval: readApproval, submitApproval: submitApproval,
            currentReadApproval: currentReadApproval, currentSubmitApproval: currentSubmitApproval,
            credentials: { [weak self] in
                guard self?.current() == captured,
                      ContentDraftContextFence.matches(currentRuntime(), context) else { return nil }
                return (session, context.session.token)
            })
    }
    /// Dedicated owned-participant caller; generic send and unrelated grants remain default-deny.
    func makeProfileParticipantTransport(context: RuntimeDependencyContext, access: ProfileParticipantAccess,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, stillCurrent: @escaping () -> Bool) -> ProfileParticipantTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), access.matches(context), stillCurrent() else { return nil }
        return ProfileParticipantTransport(context: context, access: access, underlying: underlying,
            current: currentRuntime, stillCurrent: { [weak self] in self?.current() == captured && stillCurrent() })
    }
    /// Dedicated original current snapshot caller; generic send remains unchanged/default-deny.
    func makeCityCurrentSnapshotTransport(context: RuntimeDependencyContext, revision: UInt64,
        selection: CityCurrentSnapshotRuntimeSelection, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentSelection: @escaping () -> CityCurrentSnapshotRuntimeSelection?,
        unauthorized: @escaping () -> Void) -> CityCurrentSnapshotScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              selection.matches(context, revision: revision), currentSelection() === selection else { return nil }
        return CityCurrentSnapshotScopedTransport(configuration: api, selection: selection, underlying: underlying,
            currentContext: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            currentRevision: currentRevision, currentSelection: currentSelection, unauthorized: unauthorized)
    }
    func makeCityOrderedMapTransport(context: RuntimeDependencyContext, revision: UInt64,
        selection: CityOrderedMapRuntimeSelection, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentSelection: @escaping () -> CityOrderedMapRuntimeSelection?,
        unauthorized: @escaping () -> Void) -> CityOrderedMapScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              selection.matches(context, revision: revision), currentSelection() === selection else { return nil }
        return CityOrderedMapScopedTransport(configuration: api, selection: selection, underlying: underlying,
            currentContext: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            currentRevision: currentRevision, currentSelection: currentSelection, unauthorized: unauthorized)
    }
    /// Dedicated original participation caller; generic send remains unchanged/default-deny.
    func makeCityParticipationTransport(context: RuntimeDependencyContext, revision: UInt64,
        grants: CityParticipationRuntimeGrants, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentGrants: @escaping () -> CityParticipationRuntimeGrants?,
        unauthorized: @escaping () -> Void) -> CityParticipationScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              grants.matches(context, revision: revision), currentGrants() === grants else { return nil }
        return CityParticipationScopedTransport(configuration: api, grants: grants, underlying: underlying,
            currentContext: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            currentRevision: currentRevision, currentGrants: currentGrants, unauthorized: unauthorized)
    }
    /// Dedicated original action-budget caller; generic send remains unchanged/default-deny.
    func makeCityActionBudgetTransport(context: RuntimeDependencyContext, revision: UInt64,
        grants: CityActionBudgetRuntimeGrants, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentGrants: @escaping () -> CityActionBudgetRuntimeGrants?,
        unauthorized: @escaping () -> Void) -> CityActionBudgetScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              grants.matches(context, revision: revision), currentGrants() === grants else { return nil }
        return CityActionBudgetScopedTransport(configuration: api, grants: grants, underlying: underlying,
            currentContext: { [weak self] in guard self?.current() == captured else { return nil }; return currentRuntime() },
            currentRevision: currentRevision, currentGrants: currentGrants, unauthorized: unauthorized)
    }
    /// Dedicated original neutral-task caller; generic send remains unchanged/default-deny.
    func makeCityNeutralTaskTransport(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityNeutralTaskApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentApproval: @escaping () -> CityNeutralTaskApproval?) -> CityNeutralTaskTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              approval.matches(context), currentApproval() === approval else { return nil }
        return CityNeutralTaskTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            selected: { _ in currentApproval() })
    }
    func makeCityTaskHistoryTransport(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityTaskHistoryApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentApproval: @escaping () -> CityTaskHistoryApproval?) -> CityTaskHistoryTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              approval.matches(context), currentApproval() === approval else { return nil }
        return CityTaskHistoryTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            selected: { _ in currentApproval() })
    }
    func makeCityMerchantValueTransport(context: RuntimeDependencyContext, approval: CityMerchantValueApproval,
        scope: CityMerchantValueScope, approved: @escaping () -> Bool) -> CityMerchantValueScopedTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              approval.matches(context), approved() else { return nil }
        return CityMerchantValueScopedTransport(underlying: underlying, approval: approval, scope: scope,
            current: { [weak self] in self?.current() == captured && approved() })
    }
    func makeCityNodeReceiptReader(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityNodeRedemptionReceiptApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentApproval: @escaping () -> CityNodeRedemptionReceiptApproval?) -> CityNodeRedemptionReceiptReader? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision else { return nil }
        guard approval.matches(context), currentApproval() === approval else { return nil }
        return CityNodeRedemptionReceiptReader(approval: approval, transport: underlying,
            context: { [weak self] in
                guard self?.current() == captured, currentRevision() == revision else { return nil }
                return currentRuntime()
            }, selected: currentApproval)
    }
    func makeCityValueBoundedReader(context: RuntimeDependencyContext, revision: UInt64, approval: CityValueBoundedMapApproval,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, currentRevision: @escaping () -> UInt64,
        currentApproval: @escaping () -> CityValueBoundedMapApproval?, unauthorized: @escaping () -> Void) -> CityValueBoundedMapReader? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision else { return nil }
        guard approval.matches(context), currentApproval() === approval else { return nil }
        let transport = CityValueBoundedMapScopedTransport(approval: approval, underlying: underlying,
            context: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            currentApproval: currentApproval, unauthorized: unauthorized)
        return CityValueBoundedMapReader(regionID: approval.readApproval.regionID, transport: transport)
    }
    func makeCityPlayerValueNodeTransport(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityPlayerValueNodeApproval, verification: VerificationCodeApproval?,
        currentRuntime: @escaping () -> RuntimeDependencyContext?, currentRevision: @escaping () -> UInt64,
        approved: @escaping () -> Bool) -> CityPlayerValueNodeTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision else { return nil }
        guard approval.matches(context), approved() else { return nil }
        return CityPlayerValueNodeTransport(underlying: underlying, approval: approval, verification: verification,
            current: { [weak self] in self?.current() == captured && currentRevision() == revision &&
                ContentDraftContextFence.matches(currentRuntime(), context) && approved() })
    }
    func makeCityPlayerValueService(context: RuntimeDependencyContext, revision: UInt64, approval: CityPlayerValueApproval,
        capture: CityValueBoundedCapture, currentRuntime: @escaping () -> RuntimeDependencyContext?, currentRevision: @escaping () -> UInt64,
        currentApproval: @escaping () -> CityPlayerValueApproval?, currentMapApproval: @escaping () -> CityValueBoundedMapApproval?,
        currentCapture: @escaping () -> CityValueBoundedCapture?, unauthorized: @escaping () -> Void) -> CityPlayerValueService? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision else { return nil }
        guard approval.matches(context), currentApproval() === approval, currentMapApproval() === approval.mapApproval,
              approval.capture == capture else { return nil }
        return try? CityPlayerValueService(approval: approval, capture: capture, transport: underlying,
            currentApproval: currentApproval, currentMapApproval: currentMapApproval, currentCapture: currentCapture,
            currentContext: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            unauthorized: unauthorized)
    }
    func makeCityPlayerRulesTransport(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityPlayerRulesApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentApproval: @escaping () -> CityPlayerRulesApproval?) -> CityPlayerRulesTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              approval.matches(context), currentApproval() === approval else { return nil }
        return CityPlayerRulesTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            selected: { _ in currentApproval() })
    }
    func makeCityAcquisitionTransport(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityAcquisitionApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentApproval: @escaping () -> CityAcquisitionApproval?) -> CityAcquisitionTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              approval.matches(context), currentApproval() === approval else { return nil }
        return CityAcquisitionTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            selected: { _ in currentApproval() })
    }
    func makeCityOnsiteTaskTransport(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityOnsiteTaskApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentApproval: @escaping () -> CityOnsiteTaskApproval?) -> CityOnsiteTaskTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              approval.matches(context), currentApproval() === approval else { return nil }
        return CityOnsiteTaskTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            selected: { _ in currentApproval() })
    }
    /// Dedicated original arrival-evidence caller; generic send remains unchanged/default-deny.
    func makeCityMerchantIntentTransport(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityMerchantOperationsApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentApproval: @escaping () -> CityMerchantOperationsApproval?) -> CityMerchantOperationsTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRuntime()?.session == context.session,
              currentRevision() == revision, approval.matches(context), currentApproval() === approval else { return nil }
        return CityMerchantOperationsTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            selected: { _ in currentApproval() })
    }
    func makeCityArrivalEvidenceTransport(context: RuntimeDependencyContext, revision: UInt64,
        approval: CityArrivalEvidenceApproval, currentRuntime: @escaping () -> RuntimeDependencyContext?,
        currentRevision: @escaping () -> UInt64, currentApproval: @escaping () -> CityArrivalEvidenceApproval?) -> CityArrivalEvidenceTransport? {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              api.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              deployment.regional.market == context.market,
              deployment.storageScope.service.utf8.elementsEqual(context.session.namespace.utf8),
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID, captured.epoch == context.session.epoch,
              captured.role.map({ Data($0.utf8) }) == Data(context.role.utf8),
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              ContentDraftContextFence.matches(currentRuntime(), context), currentRevision() == revision,
              approval.matches(context), currentApproval() === approval else { return nil }
        return CityArrivalEvidenceTransport(approval: approval, underlying: underlying,
            current: { [weak self] in guard self?.current() == captured, currentRevision() == revision else { return nil }; return currentRuntime() },
            selected: { _, audience in guard audience == approval.audience else { return nil }; return currentApproval() })
    }
    func sendCityOrientationOriginalReceipt(_ request: URLRequest, context: RuntimeDependencyContext,
                                 receipt: CityOrientationTaskApproval?,
                                 stillApproved: () -> Bool) async throws -> (Data, Int) {
        guard let deployment, deployment.regional.apiConfiguration?.baseURL == context.baseURL,
              deployment.regional.market == context.market,
              deployment.storageScope.service == context.session.namespace,
              let captured = current(), captured.isSignedInContentViewer,
              captured.accountID == context.session.accountID,
              captured.epoch == context.session.epoch, captured.role == context.role,
              captured.token.map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              stillApproved(), let route = CityOrientationTaskRoute(request: request, baseURL: context.baseURL),
              route.capability == .receiptRead, route.approved(request: request, context: context, receipt: receipt, answer: nil) else {
            throw PlayExperienceError.disabled
        }
        try Task.checkCancellation()
        let result = try await underlying.send(request)
        // Only this already-preflighted exact route may deliver auth evidence to its
        // captured approved-port owner. That owner retires itself before lifetime checks.
        if CityOrientationTaskService.isAuthenticationFailure(result) { return result }
        guard current() == captured, stillApproved(), !Task.isCancelled,
              route.capability == .receiptRead, route.approved(request: request, context: context, receipt: receipt, answer: nil) else {
            throw PlayExperienceError.staleSession
        }
        return result
    }


    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              let url = request.url, url.fragment == nil else { throw APIError.notConfigured }
        let merchantGamePlayer = MerchantGamePlayerReadRoute(request: request, baseURL: api.baseURL)
        let merchantOverview = MerchantOverviewScope.accepts(request, baseURL: api.baseURL)
        guard !merchantOverviewOnly || merchantOverview else { throw APIError.notConfigured }
        let merchantPrediction = MerchantPredictionScope.accepts(request, baseURL: api.baseURL)
        guard !merchantPredictionOnly || merchantPrediction else { throw APIError.notConfigured }
        let merchantProjectParticipants = merchantProjectParticipantsScope?.accepts(request, baseURL: api.baseURL) == true
        guard !merchantProjectParticipantsOnly || merchantProjectParticipants else { throw APIError.notConfigured }
        let merchantProjectWorkspace = merchantProjectWorkspaceScope?.accepts(request, baseURL: api.baseURL) == true
        guard !merchantProjectWorkspaceOnly || merchantProjectWorkspace else { throw APIError.notConfigured }
        let merchantProjectBrowse = MerchantProjectBrowseScope.accepts(request, baseURL: api.baseURL)
        guard !merchantProjectBrowseOnly || merchantProjectBrowse else { throw APIError.notConfigured }
        let nearbyMerchant = NearbyMerchantCompositionScope.accepts(request, baseURL: api.baseURL)
        guard !nearbyMerchantOnly || nearbyMerchant else { throw APIError.notConfigured }
        let selectedArea = manualMapSelection?.snapshot
        let manualRead = selectedArea.flatMap { ManualMapReadRoute(request: request, baseURL: api.baseURL, area: $0.area) }
        let publicLayers = selectedArea.map { Self.acceptsPublicLayers(request, baseURL: api.baseURL, area: $0.area) } ?? false
        let publicMapLayer = MapPublicLayerReadRoute(request: request, baseURL: api.baseURL)
        let cityRead = CityReadRoute(request: request, baseURL: api.baseURL)
        let playRead = PlayReadRoute(request: request, baseURL: api.baseURL)
        let characterRead = CharacterCardReadRoute(request: request, baseURL: api.baseURL)
        let ownedCover = OwnedTopicCoverCompositionRoute(request: request, baseURL: api.baseURL)
        let sessionFactRoute = RoamSessionFactReadRoute(request: request, baseURL: api.baseURL)
        let passportHistory = RoamPassportHistoryReadRoute(request: request, baseURL: api.baseURL)
        let nearbyEventsArea = manualMapSelection?.snapshot
        let nearbyEvents = nearbyEventsArea.flatMap { RoamNearbyEventsReadRoute(request: request, baseURL: api.baseURL, area: $0.area) }
        let nearbyPlayersArea = manualMapSelection?.snapshot
        let nearbyPlayers = nearbyPlayersArea.flatMap { RoamNearbyPlayersReadRoute(request: request, baseURL: api.baseURL, area: $0.area) }
        let ownedCoupon = ProfileOwnedCouponReadRoute(request: request, baseURL: api.baseURL)
        let albumMetadata = RoamAlbumMetadataReadRoute(request: request, baseURL: api.baseURL)
        let receivedStamp = RoamReceivedStampReadRoute(request: request, baseURL: api.baseURL)
        let tileMemory = RoamTileMemoryReadRoute(request: request, baseURL: api.baseURL)
        let favoriteTopic = profileFavoriteTopicSelection == nil ? nil : ProfileFavoriteTopicReadRoute(request: request, baseURL: api.baseURL)
        guard profileFavoriteTopicSelection == nil || favoriteTopic != nil else { throw APIError.notConfigured }
        let publicInfo = profilePublicInfoTarget == nil ? nil : ProfilePublicInfoReadRoute(request: request, baseURL: api.baseURL)
        guard profilePublicInfoTarget == nil || publicInfo != nil else { throw APIError.notConfigured }
        let guideRead = ProfileGuideReadRoute(request: request, baseURL: api.baseURL)
        if profileGuideSelection != nil {
            guard let guideRead, case .detail = guideRead else { throw APIError.notConfigured }
        }
        let favoriteList = ProfileFavoritesReadRoute(request: request, baseURL: api.baseURL)
        let favoriteDetail = ProfileFavoriteDetailRoute(request: request, baseURL: api.baseURL)
        let ticketWalletList = TicketWalletListReadRoute(request: request, baseURL: api.baseURL)
        let ownMediaStatus = OwnMediaStatusRoute.assetID(request, baseURL: api.baseURL) != nil
        let ownMedia = OwnMediaReadRoute.accepts(request, baseURL: api.baseURL) || ownMediaStatus
        let entryNearbyArea = manualMapSelection?.snapshot
        let entryNearby: URLRequest? = entryNearbyArea.flatMap { areaSnapshot in
            guard request.httpMethod == "GET",
                  let expected = try? RoamEntryNearbyRoute.request(baseURL: api.baseURL, area: areaSnapshot.area, token: "synthetic"),
                  request.url == expected.url else { return nil }
            return expected
        }
        let requestPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
        let passportToolPath: String? = request.httpMethod == "GET"
            ? RoamPassportToolsService.paths.first(where: { requestPath == api.baseURL.appendingPathComponent($0).path })
            : nil
        let privateToolReadPath: String? = RoamPrivateToolsRoute.reads.first(where: { path in
            guard requestPath == api.baseURL.appendingPathComponent(path).path else { return false }
            let expectedMethod = (path == RoamPrivateToolsRoute.exportPrepare || path == RoamPrivateToolsRoute.exportPage) ? "POST" : "GET"
            return request.httpMethod == expectedMethod
        })
        let rewardPledgeOperation = RewardPledgeRoutes.operation(request, baseURL: api.baseURL)
        guard ownMedia || nearbyEvents != nil || entryNearby != nil || passportHistory != nil || passportToolPath != nil || privateToolReadPath != nil || rewardPledgeOperation != nil || url.query == nil || manualRead != nil || publicLayers || publicMapLayer != nil || playRead != nil || characterRead != nil || cityRead != nil || ownedCover != nil || tileMemory != nil || sessionFactRoute != nil else { throw APIError.notConfigured }
        guard let captured = current() else { throw CancellationError() }
        let authPaths = [AuthEndpoint.smsSend, .phone, .userInfo, .logout].map { api.url(for: $0) }
        let auth = authPaths.contains(url)
        let publicHome = PublicMerchantHomeCompositionScope.accepts(request, baseURL: api.baseURL)
        let publicTopicsRoute = ClubPublicTopicsRoute(request: request, baseURL: api.baseURL)
        let publicTopicsContext = ClubPublicTopicsContext(
            identity: .init(accountID: captured.accountID, epoch: captured.epoch),
            viewerRevision: captured.viewerRevision, role: captured.role,
            baseURL: api.baseURL, namespace: deployment.storageScope.service)
        let publicTopicsGrant = publicTopicsRoute.flatMap { clubPublicTopicsApproval(publicTopicsContext, $0.clubID) }
        let clubRoleContext: RuntimeDependencyContext? = {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role,
                  let token = captured.token, let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { return nil }
            return .init(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
        }()
        let roleAssignmentRoute = ClubRoleAssignmentRoute(request: request, baseURL: api.baseURL)
        let roleRevocationRoute = ClubRoleRevocationRoute(request: request, baseURL: api.baseURL)
        let roleAssignmentGrant = clubRoleContext.flatMap { context in roleAssignmentRoute.flatMap { route in
            clubRoleAssignmentApproval(context).flatMap { $0.permits(context, scope: route.scope, writing: route.writing) ? $0 : nil }
        } }
        let roleRevocationGrant = clubRoleContext.flatMap { context in roleRevocationRoute.flatMap { route in
            clubRoleRevocationApproval(context).flatMap { $0.permits(context, scope: route.scope, writing: route.writing) ? $0 : nil }
        } }
        var readApprovalStillValid: (() -> Bool)?
        let reads = ["api/common/banner", "api/category/list", "api/topic/list", "api/activity/list", "api/club/list", "api/merchant/list"]
        if auth {
            guard deployment.regional.market == .china,
                  deployment.regional.canUseDomesticChinaPhone,
                  CNAccountSessionService.accepts(request, configuration: api) else { throw APIError.notConfigured }
        } else if let rewardPledgeOperation {
            guard captured.isSignedInContentViewer, rewardPledgePermit(rewardPledgeOperation) else { throw APIError.notConfigured }
            let permit = rewardPledgePermit
            readApprovalStillValid = { permit(rewardPledgeOperation) }
        } else if let route = merchantGamePlayer {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = merchantGamePlayerReadGrant(context), approval.matches(context),
                  approval.allows(configuration: api, namespace: session.namespace, accountID: account, path: route.path) else {
                throw APIError.notConfigured
            }
            readApprovalStillValid = { [merchantGamePlayerReadGrant] in
                guard let fresh = merchantGamePlayerReadGrant(context), fresh == approval, fresh.matches(context) else { return false }
                return fresh.allows(configuration: api, namespace: session.namespace, accountID: account, path: route.path)
            }
        } else if merchantOverviewOnly {
            guard merchantOverview, let scope = merchantOverviewScope,
                  scope.matches(deployment: deployment, viewer: captured) else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                guard let self, let viewer = self.current() else { return false }
                return scope.matches(deployment: deployment, viewer: viewer)
            }
        } else if merchantPredictionOnly {
            guard merchantPrediction, let scope = merchantPredictionScope,
                  scope.matches(deployment: deployment, viewer: captured) else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                guard let self, let viewer = self.current() else { return false }
                return scope.matches(deployment: deployment, viewer: viewer)
            }
        } else if merchantProjectParticipantsOnly {
            guard merchantProjectParticipants, let scope = merchantProjectParticipantsScope,
                  scope.matches(deployment: deployment, viewer: captured) else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                guard let self, let viewer = self.current() else { return false }
                return scope.matches(deployment: deployment, viewer: viewer)
            }
        } else if merchantProjectWorkspaceOnly {
            guard merchantProjectWorkspace, let scope = merchantProjectWorkspaceScope,
                  scope.matches(deployment: deployment, viewer: captured) else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                guard let self, let viewer = self.current() else { return false }
                return scope.matches(deployment: deployment, viewer: viewer)
            }
        } else if merchantProjectBrowseOnly {
            guard merchantProjectBrowse, let scope = merchantProjectBrowseScope,
                  scope.matches(deployment: deployment, viewer: captured) else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                guard let self, let viewer = self.current() else { return false }
                return scope.matches(deployment: deployment, viewer: viewer)
            }
        } else if nearbyMerchant {
            guard let scope = nearbyMerchantScope, scope.matches(deployment: deployment, viewer: captured) else {
                throw APIError.notConfigured
            }
            readApprovalStillValid = { [weak self] in
                guard let self, let viewer = self.current() else { return false }
                return scope.matches(deployment: deployment, viewer: viewer)
            }
        } else if publicHome {
            guard let scope = publicMerchantHomeScope, scope.matches(deployment: deployment, viewer: captured) else {
                throw APIError.notConfigured
            }
            readApprovalStillValid = { [weak self] in
                guard let self, let viewer = self.current() else { return false }
                return scope.matches(deployment: deployment, viewer: viewer)
            }
        } else if ProjectStoryAudioCompositionRoute.accepts(request, baseURL: api.baseURL) {
            guard deployment.regional.market == .china, captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token),
                  let revision = projectEditConfigurationRevision(),
                  let editor = try? ProjectEditSession(accountID: account, epoch: captured.epoch, storageNamespace: deployment.storageScope.service, viewerRevision: captured.viewerRevision, configurationRevision: revision) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let issued = projectStoryAudioUploadApproval(context) else { throw APIError.notConfigured }
            func permitted() -> Bool {
                projectEditConfigurationRevision() == revision && projectStoryAudioUploadApproval(context) == issued &&
                    issued.matches(configuration: api, session: editor)
            }
            guard permitted() else { throw APIError.notConfigured }; readApprovalStillValid = permitted
        } else if let field = ProjectTopicImageCompositionRoute.field(request, baseURL: api.baseURL) {
            guard deployment.regional.market == .china, captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token),
                  let revision = projectEditConfigurationRevision(),
                  let editor = try? ProjectEditSession(accountID: account, epoch: captured.epoch, storageNamespace: deployment.storageScope.service, viewerRevision: captured.viewerRevision, configurationRevision: revision) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let issued = projectTopicImageUploadApproval(context) else { throw APIError.notConfigured }
            func permitted() -> Bool {
                projectEditConfigurationRevision() == revision && projectTopicImageUploadApproval(context) == issued &&
                    issued.fields.contains(field) && issued.matches(configuration: api, session: editor)
            }
            guard permitted() else { throw APIError.notConfigured }; readApprovalStillValid = permitted
        } else if ProjectStoryImageCompositionRoute.accepts(request, baseURL: api.baseURL) {
            guard deployment.regional.market == .china, captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token),
                  let revision = projectEditConfigurationRevision(),
                  let editor = try? ProjectEditSession(accountID: account, epoch: captured.epoch, storageNamespace: deployment.storageScope.service, viewerRevision: captured.viewerRevision, configurationRevision: revision) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let issued = projectStoryImageUploadApproval(context) else { throw APIError.notConfigured }
            func permitted() -> Bool {
                projectEditConfigurationRevision() == revision && projectStoryImageUploadApproval(context) == issued &&
                    issued.matches(configuration: api, session: editor)
            }
            guard permitted() else { throw APIError.notConfigured }; readApprovalStillValid = permitted
        } else if let route = ownedCover {
            guard deployment.regional.market == .china, captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token),
                  let revision = ownedTopicCoverConfigurationRevision(),
                  let editor = try? ProjectEditSession(accountID: account, epoch: captured.epoch, storageNamespace: deployment.storageScope.service, viewerRevision: captured.viewerRevision, configurationRevision: revision) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let issued = ownedTopicCoverApproval(context) else { throw APIError.notConfigured }
            func permitted() -> Bool {
                ownedTopicCoverConfigurationRevision() == revision && ownedTopicCoverApproval(context) == issued &&
                    issued.permits(route.operation, configuration: api, session: editor)
            }
            guard permitted() else { throw APIError.notConfigured }; readApprovalStillValid = permitted
        } else if let route = ProjectAuthorInputReadRoute(request: request, baseURL: api.baseURL) {
            guard deployment.regional.market == .china, captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token),
                  let revision = projectEditConfigurationRevision() else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            let exact = try route.businessRoute
            func permitted() -> Bool {
                guard projectEditConfigurationRevision() == revision,
                      let configuration = projectEditConfiguration(context), configuration.matches(context) else { return false }
                return configuration.routes[.projectAuthorInputRead]?.contains(exact) == true
            }
            guard permitted() else { throw APIError.notConfigured }
            readApprovalStillValid = permitted
        } else if let route = ProjectEditCompositionRoute(request: request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let configurationRevision = projectEditConfigurationRevision() else { throw APIError.notConfigured }
            let exact = try BusinessRuntimeRoute.post(route.path)
            func permitted() -> Bool {
                guard projectEditConfigurationRevision() == configurationRevision, let configuration = projectEditConfiguration(context), configuration.matches(context) else { return false }
                return configuration.routes[route.feature]?.contains(exact) == true
            }
            guard permitted() else { throw APIError.notConfigured }
            readApprovalStillValid = permitted
        } else if let route = ApprovedReleaseCompositionRoute(request: request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let configurationRevision = approvedReleaseConfigurationRevision() else { throw APIError.notConfigured }
            let exact = try BusinessRuntimeRoute.post(route.path)
            func permitted() -> Bool {
                guard approvedReleaseConfigurationRevision() == configurationRevision, let configuration = approvedReleaseConfiguration(context), configuration.matches(context) else { return false }
                return configuration.routes[route.feature]?.contains(exact) == true
            }
            guard permitted() else { throw APIError.notConfigured }
            readApprovalStillValid = permitted
        } else if url == api.baseURL.appendingPathComponent("api/common/dict") {
            guard deployment.reads.contains(.homeAndSearch), captured.isPublicTemplateViewer,
                  TemplateMetadataReadRoute(request: request, baseURL: api.baseURL) != nil else { throw APIError.notConfigured }
        } else if url == api.baseURL.appendingPathComponent("api/merchant/coop-profile") || url == api.baseURL.appendingPathComponent("api/coupon/command-receipt") {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = couponReadApproval(context), approval.matches(context),
                  let capability = approval.commandProtocol, capability.matches(context, merchantID: approval.merchantID),
                  CouponCommandReadRoute(request: request, baseURL: api.baseURL, merchantID: approval.merchantID) != nil else { throw APIError.notConfigured }
            readApprovalStillValid = { [couponReadApproval] in
                guard let fresh = couponReadApproval(context) else { return false }
                return fresh.revision == approval.revision && fresh.matches(context) &&
                    fresh.commandProtocol?.revision == capability.revision && capability.matches(context, merchantID: fresh.merchantID)
            }
        } else if CouponManagementReadRoute(request: request, baseURL: api.baseURL) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = couponReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [couponReadApproval] in
                guard let currentApproval = couponReadApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if ownedCoupon != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = profileOwnedCouponReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: ProfileOwnedCouponReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [profileOwnedCouponReadAccess] in
                guard let fresh = profileOwnedCouponReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if albumMetadata != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamAlbumMetadataReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: RoamAlbumMetadataReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamAlbumMetadataReadAccess] in
                guard let fresh = roamAlbumMetadataReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if tileMemory != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamTileMemoryReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: RoamTileMemoryReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamTileMemoryReadAccess] in
                guard let fresh = roamTileMemoryReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if let favoriteTopic {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selection = profileFavoriteTopicSelection, selection.isCurrent,
                  selection.topicID == favoriteTopic.topicID, selection.viewerRevision == captured.viewerRevision,
                  ContentDraftContextFence.matches(selection.context, context),
                  let selected = profileFavoriteTopicReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: ProfileFavoriteTopicReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [profileFavoriteTopicReadAccess] in
                guard selection.isCurrent, let fresh = profileFavoriteTopicReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if let publicInfo {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let target = profilePublicInfoTarget, target.isCurrent,
                  target.memberID == publicInfo.memberID, target.viewerRevision == captured.viewerRevision,
                  ContentDraftContextFence.matches(target.context, context),
                  let selected = profilePublicInfoReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: ProfilePublicInfoReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [profilePublicInfoReadAccess] in
                guard target.isCurrent, let fresh = profilePublicInfoReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if let guideRead {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = profileGuideReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: guideRead.path) else { throw APIError.notConfigured }
            let selection = profileGuideSelection
            if case .detail(let id) = guideRead {
                guard let selection, selection.isCurrent, selection.row.id == id,
                      selection.viewerRevision == captured.viewerRevision,
                      ContentDraftContextFence.matches(selection.context, context) else { throw APIError.notConfigured }
            }
            readApprovalStillValid = { [profileGuideReadAccess] in
                guard selection?.isCurrent != false, let fresh = profileGuideReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if let favoriteList {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = profileFavoritesReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: favoriteList.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [profileFavoritesReadAccess] in
                guard let fresh = profileFavoritesReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if let favoriteDetail {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selection = profileFavoriteSelection, selection.isCurrent,
                  selection.route.generation == .legacySquare, selection.route.id == favoriteDetail.postID,
                  selection.viewerRevision == captured.viewerRevision,
                  ContentDraftContextFence.matches(selection.context, context),
                  let selected = profileFavoriteDetailAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: favoriteDetail.path),
                  favoriteDetail.pageNumber == nil || selection.permitsComments(access: selected) else { throw APIError.notConfigured }
            readApprovalStillValid = { [profileFavoriteDetailAccess] in
                guard selection.isCurrent, let fresh = profileFavoriteDetailAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if sessionFactRoute != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamSessionFactReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: RoamSessionFactReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamSessionFactReadAccess] in
                guard let fresh = roamSessionFactReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if nearbyEvents != nil {
            guard captured.isSignedInContentViewer, let snapshot = nearbyEventsArea,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamNearbyEventsReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: RoamNearbyEventsReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamNearbyEventsReadAccess, manualMapSelection] in
                guard manualMapSelection?.snapshot == snapshot,
                      let fresh = roamNearbyEventsReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if nearbyPlayers != nil {
            guard captured.isSignedInContentViewer, let snapshot = nearbyPlayersArea,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamNearbyPlayersReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: RoamNearbyPlayersReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamNearbyPlayersReadAccess, manualMapSelection] in
                guard manualMapSelection?.snapshot == snapshot,
                      let fresh = roamNearbyPlayersReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if entryNearby != nil {
            guard captured.isSignedInContentViewer, let snapshot = entryNearbyArea,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamEntryNearbyReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: RoamEntryNearbyRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamEntryNearbyReadAccess, manualMapSelection] in
                guard manualMapSelection?.snapshot == snapshot,
                      let fresh = roamEntryNearbyReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if receivedStamp != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamReceivedStampReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: RoamReceivedStampReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamReceivedStampReadAccess] in
                guard let fresh = roamReceivedStampReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if let passportHistory {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamPassportHistoryReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: passportHistory.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamPassportHistoryReadAccess] in
                guard let fresh = roamPassportHistoryReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if let passportToolPath {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            if let selected = roamPassportToolsReadAccess(context), selected.matches(context),
               selected.endpoints.allows(configuration: api, namespace: session.namespace,
                 accountID: account, path: passportToolPath) {
                readApprovalStillValid = { [roamPassportToolsReadAccess] in
                    guard let fresh = roamPassportToolsReadAccess(context) else { return false }
                    return fresh === selected && fresh.matches(context)
                }
            } else if let selected = roamPrivateToolsReadAccess(context), selected.matches(context), !selected.allowsWrites,
                      selected.endpoints.allows(configuration: api, namespace: session.namespace,
                        accountID: account, path: passportToolPath) {
                readApprovalStillValid = { [roamPrivateToolsReadAccess] in
                    guard let fresh = roamPrivateToolsReadAccess(context) else { return false }
                    return fresh === selected && fresh.matches(context) && !fresh.allowsWrites
                }
            } else {
                throw APIError.notConfigured
            }
        } else if let privateToolReadPath {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = roamPrivateToolsReadAccess(context), selected.matches(context), !selected.allowsWrites,
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: privateToolReadPath) else { throw APIError.notConfigured }
            readApprovalStillValid = { [roamPrivateToolsReadAccess] in
                guard let fresh = roamPrivateToolsReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context) && !fresh.allowsWrites
            }
        } else if let inviteRoute = ProfileInviteHistoryReadRoute(request: request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let selected = profileInviteHistoryReadAccess(context), selected.matches(context),
                  selected.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: inviteRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [profileInviteHistoryReadAccess] in
                guard let fresh = profileInviteHistoryReadAccess(context) else { return false }
                return fresh === selected && fresh.matches(context)
            }
        } else if ownMedia {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = ownMediaReadApproval(context), approval.matches(context),
                  !ownMediaStatus || approval.allowsStatus else { throw APIError.notConfigured }
            readApprovalStillValid = { [ownMediaReadApproval] in
                guard let selected = ownMediaReadApproval(context) else { return false }
                return selected === approval && selected.matches(context) && (!ownMediaStatus || selected.allowsStatus)
            }
        } else if MemberRoleInfoReadRoute.accepts(request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = memberRoleInfoReadApproval(context), approval.matches(context),
                  approval.endpoints.allows(configuration: api, namespace: session.namespace,
                    accountID: account, path: MemberRoleInfoReadRoute.path) else { throw APIError.notConfigured }
            readApprovalStillValid = { [memberRoleInfoReadApproval] in
                guard let selected = memberRoleInfoReadApproval(context) else { return false }
                return selected === approval && selected.matches(context)
            }
        } else if ProfileWeeklyPointsReadRoute.accepts(request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = profileWeeklyPointsReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [profileWeeklyPointsReadApproval] in
                guard let selected = profileWeeklyPointsReadApproval(context) else { return false }
                return selected === approval && selected.matches(context)
            }
        } else if WalletHistoryReadRoute(request: request, baseURL: api.baseURL, accountID: captured.accountID ?? 0) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = walletHistoryReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [walletHistoryReadApproval] in
                guard let currentApproval = walletHistoryReadApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if TemplateShelfReadRoute(request: request, baseURL: api.baseURL) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = templateShelfReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [templateShelfReadApproval] in
                guard let currentApproval = templateShelfReadApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if let cityRead {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = cityPlayerReadApproval(context), approval.matches(context), cityRead.regionID == approval.regionID else { throw APIError.notConfigured }
            readApprovalStillValid = { [cityPlayerReadApproval] in
                guard let currentApproval = cityPlayerReadApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if TeamReadRoute(request: request, baseURL: api.baseURL) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = teamReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [teamReadApproval] in
                guard let currentApproval = teamReadApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if url == api.baseURL.appendingPathComponent("api/club/join")
                    || url == api.baseURL.appendingPathComponent("api/club/quit")
                    || url == api.baseURL.appendingPathComponent("api/club/admission/receipt") {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = clubOrdinaryAdmissionApproval(context), approval.matches(context),
                  ClubOrdinaryAdmissionRoute.accepts(request, baseURL: api.baseURL),
                  url == api.baseURL.appendingPathComponent("api/club/admission/receipt") || approval.allowsWrites else { throw APIError.notConfigured }
            readApprovalStillValid = { [clubOrdinaryAdmissionApproval] in
                guard let fresh = clubOrdinaryAdmissionApproval(context) else { return false }
                return fresh.revision == approval.revision && fresh.matches(context)
                    && (url == api.baseURL.appendingPathComponent("api/club/admission/receipt") || fresh.allowsWrites)
            }
        } else if let original = ClubPostOriginalRoute(request: request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = clubPostOriginalApproval(context), approval.matches(context),
                  approval.allows(original) else { throw APIError.notConfigured }
            readApprovalStillValid = { [clubPostOriginalApproval] in
                guard let currentApproval = clubPostOriginalApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
                    && currentApproval.allows(original)
            }
        } else if let original = ClubCommentOriginalRoute(request: request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = clubCommentOriginalApproval(context), approval.matches(context),
                  approval.allows(original) else { throw APIError.notConfigured }
            readApprovalStillValid = { [clubCommentOriginalApproval] in
                guard let currentApproval = clubCommentOriginalApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
                    && currentApproval.allows(original)
            }
        } else if let context = clubRoleContext, let route = roleAssignmentRoute, let issued = roleAssignmentGrant {
            guard issued.endpoints.paths.contains(route.path),
                  route.command.map({ issued.productionApproval?.permits($0, context: context) == true }) ?? !route.writing else {
                throw APIError.notConfigured
            }
            readApprovalStillValid = { [weak self] in
                guard let fresh = self?.clubRoleAssignmentApproval(context) else { return false }
                return (route.writing ? fresh == issued : fresh.sameReadAuthority(as: issued))
                    && fresh.permits(context, scope: route.scope, writing: route.writing)
                    && fresh.endpoints.paths.contains(route.path)
                    && (route.command.map({ fresh.productionApproval?.permits($0, context: context) == true }) ?? !route.writing)
            }
        } else if let context = clubRoleContext, let route = roleRevocationRoute, let issued = roleRevocationGrant {
            guard issued.endpoints.paths.contains(route.path),
                  route.command.map({ issued.productionApproval?.permits($0, context: context) == true }) ?? !route.writing else {
                throw APIError.notConfigured
            }
            readApprovalStillValid = { [weak self] in
                guard let fresh = self?.clubRoleRevocationApproval(context) else { return false }
                return (route.writing ? fresh == issued : fresh.sameReadAuthority(as: issued))
                    && fresh.permits(context, scope: route.scope, writing: route.writing)
                    && fresh.endpoints.paths.contains(route.path)
                    && (route.command.map({ fresh.productionApproval?.permits($0, context: context) == true }) ?? !route.writing)
            }
        } else if let route = publicTopicsRoute, route.isTopics || publicTopicsGrant != nil {
            // A shared detail without this dedicated grant retains its original route.
            // Topics never fall through to membership/governance or retry as a guest.
            guard captured.isPublicTemplateViewer, let issued = publicTopicsGrant,
                  issued.context == publicTopicsContext, issued.clubID == route.clubID else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                self?.clubPublicTopicsApproval(publicTopicsContext, route.clubID) == issued
            }
        } else if ClubPublicRosterRoute.accepts(request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, account > 0, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let issued = clubPublicRosterApproval(context),
                  issued.identity == ClubReadIdentity(accountID: account, epoch: captured.epoch),
                  issued.baseURL == api.baseURL else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                self?.clubPublicRosterApproval(context) == issued
            }
        } else if ClubCommunityReadRoute(request: request, baseURL: api.baseURL) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = clubCommunityReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [clubCommunityReadApproval] in
                guard let currentApproval = clubCommunityReadApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if ClubPostImageUploadCompositionRoute.matches(request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer,
                  let clubID = clubPostImageUploadClubID, clubID > 0,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token),
                  let uploadContext = try? ClubPostImageUploadContext(
                    accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, clubID: clubID
                  ) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = clubPostImageUploadApproval(context, clubID),
                  approval.matches(baseURL: api.baseURL, context: uploadContext) else { throw APIError.notConfigured }
            readApprovalStillValid = { [clubPostImageUploadApproval] in
                guard let currentApproval = clubPostImageUploadApproval(context, clubID) else { return false }
                return currentApproval == approval && currentApproval.matches(baseURL: api.baseURL, context: uploadContext)
            }
        } else if MessagingHistoryReadRoute(request: request, baseURL: api.baseURL) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = messagingHistoryReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [messagingHistoryReadApproval] in
                guard let currentApproval = messagingHistoryReadApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if ticketWalletList != nil {
            // Only the existing wallet owner_type1/2 lists; no order/detail/write grant.
            guard deployment.regional.market == .china, captured.isSignedInContentViewer else { throw APIError.notConfigured }
        } else if OwnedOrderReadRoute(request: request, baseURL: api.baseURL) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = ownedOrderReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [ownedOrderReadApproval] in
                guard let currentApproval = ownedOrderReadApproval(context) else { return false }
                return currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if let playRead {
            guard deployment.reads.contains(.playNodesAndRouteState),
                  let account = captured.accountID, account > 0,
                  let role = captured.role, !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL,
                role: role, session: session)
            guard let issued = playReadConfiguration(context),
                  playRead.isApproved(configuration: issued, context: context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                guard let current = self?.playReadConfiguration(context),
                      current.playReadApprovalID == issued.playReadApprovalID else { return false }
                return playRead.isApproved(configuration: current, context: context)
            }
            guard readApprovalStillValid?() == true else { throw APIError.notConfigured }
        } else if let characterRead {
            guard let account = captured.accountID, account > 0,
                  let role = captured.role, !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL,
                role: role, session: session)
            guard let issued = playReadConfiguration(context),
                  characterRead.isApproved(configuration: issued, context: context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                guard let current = self?.playReadConfiguration(context),
                      current.playReadApprovalID == issued.playReadApprovalID else { return false }
                return characterRead.isApproved(configuration: current, context: context)
            }
            guard readApprovalStillValid?() == true else { throw APIError.notConfigured }
        } else if url == api.baseURL.appendingPathComponent(PrivateHomeService.path) {
            guard let grant = deployment.privateHome,
                  grant.matches(storageScope: deployment.storageScope, accountID: captured.accountID, role: captured.role),
                  let token = captured.token, AuthRequestBuilder.isValidToken(token),
                  PrivateHomeRequestBoundary.accepts(request, baseURL: api.baseURL) else { throw APIError.notConfigured }
        } else if manualRead != nil || publicLayers {
            guard deployment.reads.contains(.manualMap), let selectedArea,
                  let account = captured.accountID, account > 0,
                  let role = captured.role, !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL,
                role: role, session: session)
            guard let approval = manualMapReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [manualMapReadApproval, manualMapSelection] in
                guard let currentApproval = manualMapReadApproval(context) else { return false }
                return manualMapSelection?.snapshot == selectedArea && currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if publicMapLayer != nil {
            guard !deployment.reads.isDisjoint(with: [.manualMap, .publicMapLayers]),
                  captured.isSignedInContentViewer,
                  let account = captured.accountID, account > 0,
                  let role = captured.role, !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL,
                role: role, session: session)
            guard let approval = mapPublicLayerReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [mapPublicLayerReadApproval, manualMapSelection] in
                guard let currentApproval = mapPublicLayerReadApproval(context) else { return false }
                return manualMapSelection?.snapshot == selectedArea && currentApproval.revision == approval.revision && currentApproval.matches(context)
            }
        } else if WorkshopOwnedReadRoute(request: request, baseURL: api.baseURL) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL,
                role: role, session: session)
            guard let approval = workshopOwnedReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [workshopOwnedReadApproval] in
                guard let fresh = workshopOwnedReadApproval(context) else { return false }
                return fresh.revision == approval.revision && fresh.matches(context)
            }
        } else if let route = WorkshopCreatorPendingRequest.accepts(request, baseURL: api.baseURL), route != .author {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token, role: role) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            switch route {
            case .list:
                guard let grant = workshopCreatorPendingListApproval(context), grant.matches(context) else { throw APIError.notConfigured }
                readApprovalStillValid = { [workshopCreatorPendingListApproval] in
                    guard let latest = workshopCreatorPendingListApproval(context) else { return false }
                    return latest.revision == grant.revision && latest.matches(context) && grant.matches(context)
                }
            case .detail:
                guard let grant = workshopCreatorPendingDetailApproval(context), grant.matches(context) else { throw APIError.notConfigured }
                readApprovalStillValid = { [workshopCreatorPendingDetailApproval] in
                    guard let latest = workshopCreatorPendingDetailApproval(context) else { return false }
                    return latest.revision == grant.revision && latest.matches(context) && grant.matches(context)
                }
            case .author: throw APIError.notConfigured
            }
        } else if let route = WorkshopCreatorConsentRequest.accepts(request, baseURL: api.baseURL), route != .declare {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token, role: role) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = workshopCreatorConsentReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [workshopCreatorConsentReadApproval] in
                guard let fresh = workshopCreatorConsentReadApproval(context) else { return false }
                return fresh.revision == approval.revision && fresh.matches(context) && approval.matches(context)
            }
        } else if let route = WorkshopPaidProfessionalRequest.accepts(request, baseURL: api.baseURL), route != .submit && route != .cancel {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token, role: role) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = workshopPaidProfessionalReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [workshopPaidProfessionalReadApproval] in
                guard let fresh = workshopPaidProfessionalReadApproval(context) else { return false }
                return fresh.revision == approval.revision && fresh.matches(context)
            }
        } else if WorkshopPaidInstalledTextRequest.accepts(request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token, role: role) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = workshopPaidInstalledTextApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [workshopPaidInstalledTextApproval] in
                guard let fresh = workshopPaidInstalledTextApproval(context) else { return false }
                return fresh.revision == approval.revision && fresh.matches(context)
            }
        } else if let route = WorkshopPaidInstallRequest.accepts(request, baseURL: api.baseURL), route != .submit {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            guard let approval = workshopPaidInstallApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [workshopPaidInstallApproval] in
                guard let fresh = workshopPaidInstallApproval(context) else { return false }
                return fresh.revision == approval.revision && fresh.matches(context)
            }
        } else if WorkshopPurchasedReadRoute(request: request, baseURL: api.baseURL) != nil {
            guard captured.isSignedInContentViewer,
                  let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL,
                role: role, session: session)
            guard let approval = workshopPurchasedReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [workshopPurchasedReadApproval] in
                guard let fresh = workshopPurchasedReadApproval(context) else { return false }
                return fresh.revision == approval.revision && fresh.matches(context)
            }
        } else if let route = OwnerDraftReadRoute(url: url, baseURL: api.baseURL) {
            guard let account = captured.accountID, let token = captured.token, let role = captured.role,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch,
                    namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL,
                role: role, session: session)
            readApprovalStillValid = { [ownerDraftReadApproval] in ownerDraftReadApproval(context)?.matches(context) == true }
            guard let approval = ownerDraftReadApproval(context), approval.matches(context), route.accepts(request) else {
                throw APIError.notConfigured
            }
        } else if let route = SignedInContentDetailReadRoute(url: url, baseURL: api.baseURL) {
            guard deployment.contentDetails == .activityAndTopic,
                  captured.isSignedInContentViewer, route.accepts(request) else { throw APIError.notConfigured }
        } else if OfficialPublicEventReadRoute.accepts(request, baseURL: api.baseURL) {
            let selection = officialPublicEventReadSelection
            guard deployment.regional.market == .china, deployment.reads.contains(.officialPublicEventCatalogAndDetail),
                  captured.isPublicTemplateViewer, let source = selection.source,
                  let revision = selection.activeRevision(baseURL: api.baseURL, namespace: deployment.storageScope.service) else { throw APIError.notConfigured }
            readApprovalStillValid = { [weak self] in
                guard let self, self.officialPublicEventReadSelection === selection,
                      selection.source === source else { return false }
                return selection.activeRevision(baseURL: api.baseURL, namespace: deployment.storageScope.service) == revision
            }
        } else if let route = PublicTopicTemplateReadRoute(url: url, baseURL: api.baseURL) {
            guard deployment.reads.contains(.publicTopicTemplateCatalogAndDetail),
                  route.accepts(request), captured.isPublicTemplateViewer else { throw APIError.notConfigured }
        } else if let exit = ChapterWriteExit.match(request, baseURL: api.baseURL) {
            guard captured.isSignedInContentViewer, let account = captured.accountID, let role = captured.role, let token = captured.token,
                  let session = try? PlayExperienceSession(accountID: account, epoch: captured.epoch, namespace: deployment.storageScope.service, token: token) else { throw APIError.notConfigured }
            let context = RuntimeDependencyContext(market: deployment.regional.market, baseURL: api.baseURL, role: role, session: session)
            let allowed: Bool
            switch exit {
            case .invite: allowed = chapterInviteExecution(context)
            case .respond: allowed = chapterRespondExecution(context)
            case .withdraw(let id, let reason): allowed = offerWithdrawExecution(context, id, reason)
            }
            guard allowed else { throw APIError.notConfigured }
            readApprovalStillValid = {
                switch exit {
                case .invite: return self.chapterInviteExecution(context)
                case .respond: return self.chapterRespondExecution(context)
                case .withdraw(let id, let reason): return self.offerWithdrawExecution(context, id, reason)
                }
            }
        } else {
            guard request.httpMethod == "POST", deployment.reads.contains(.homeAndSearch),
                  captured.isPublicTemplateViewer,
                  reads.contains(where: { api.baseURL.appendingPathComponent($0) == url }) else { throw APIError.notConfigured }
        }
        if !auth && !publicHome, request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) != captured.token.map({ Data($0.utf8) }) { throw CancellationError() }
        try Task.checkCancellation()
        guard current() == captured, readApprovalStillValid?() != false else { throw CancellationError() }
        do {
            let result = try await underlying.send(request)
            try Task.checkCancellation()
            guard current() == captured, readApprovalStillValid?() != false else { throw CancellationError() }
            if (playRead != nil || characterRead != nil), current() == captured,
               PlayExperienceService.isAuthenticationFailure(result) { return result }
            if let ticketWalletList {
                try ticketWalletList.validateResponse(result, expectedAccountID: captured.accountID ?? 0)
            }
            try ownedCoupon?.validateResponse(result, accountID: captured.accountID ?? 0)
            try albumMetadata?.validateResponse(result)
            try receivedStamp?.validateResponse(result)
            try tileMemory?.validateResponse(result)
            try favoriteList?.validateResponse(result)
            try favoriteDetail?.validateResponse(result)
            try guideRead?.validateResponse(result)
            try sessionFactRoute?.validateResponse(result)
            try passportHistory?.validateResponse(result)
            try favoriteTopic?.validateResponse(result)
            try nearbyEvents?.validateResponse(result)
            try nearbyPlayers?.validateResponse(result)
            try publicInfo?.validateResponse(result)
            try publicMapLayer?.validateResponse(result)
            return result
        } catch {
            guard current() == captured, !Task.isCancelled, readApprovalStillValid?() != false else { throw CancellationError() }
            throw error
        }
    }
}

/// Exact invite, invite-respond, and offer-withdraw bodies. Anything else, including a
/// prefix of the path or an extra JSON key, is not a match and stays on the default deny.
private enum ChapterWriteExit {
    case invite, respond, withdraw(id: Int, reason: String)
    static func match(_ request: URLRequest, baseURL: URL) -> Self? {
        guard request.httpMethod == "POST", request.url?.query == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = request.url, let body = request.httpBody else { return nil }
        let respond = baseURL.appendingPathComponent("api/merchant/chapter-application/invite/respond").absoluteString
        let invite = baseURL.appendingPathComponent("api/merchant/chapter-application/invite").absoluteString
        let withdraw = baseURL.appendingPathComponent(MerchantOfferWithdrawalRequest.path).absoluteString
        if url.absoluteString == respond { return respondBody(body) ? .respond : nil }
        if url.absoluteString == invite { return inviteBody(body) ? .invite : nil }
        if url.absoluteString == withdraw, let parsed = withdrawBody(body) { return .withdraw(id: parsed.0, reason: parsed.1) }
        return nil
    }
    private static func sameJSON(_ fields: [String: MerchantContentValue], _ body: Data) -> Bool {
        (try? JSONEncoder().encode(fields)) == body
    }
    private static func inviteBody(_ body: Data) -> Bool {
        guard let object = (try? JSONDecoder().decode(MerchantContentValue.self, from: body))?.object,
              Set(object.keys).isSubset(of: ["chapterId", "merchantMemberId", "replacementOfOfferId", "scope", "message"]),
              let chapter = object["chapterId"]?.safeInteger, chapter > 0,
              let member = object["merchantMemberId"]?.safeInteger, member > 0,
              let replacement = object["replacementOfOfferId"]?.safeInteger, replacement > 0 else { return false }
        var fields: [String: MerchantContentValue] = ["chapterId": .integer(chapter), "merchantMemberId": .integer(member), "replacementOfOfferId": .integer(replacement)]
        if object["scope"] != nil { guard object["scope"]?.text == "MERCHANT" else { return false }; fields["scope"] = .string("MERCHANT") }
        if object["message"] != nil {
            guard let message = object["message"]?.text, !message.isEmpty, message == message.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            fields["message"] = .string(message)
        }
        return Set(object.keys) == Set(fields.keys) && sameJSON(fields, body)
    }
    private static func respondBody(_ body: Data) -> Bool {
        guard let object = (try? JSONDecoder().decode(MerchantContentValue.self, from: body))?.object,
              Set(object.keys) == ["applicationId", "accepted"],
              let id = object["applicationId"]?.safeInteger, id > 0, let accepted = object["accepted"]?.flag else { return false }
        return sameJSON(["applicationId": .integer(id), "accepted": .bool(accepted)], body)
    }
    private static func withdrawBody(_ body: Data) -> (Int, String)? {
        guard case .object(let object) = try? JSONDecoder().decode(CoopFlowJSON.self, from: body),
              Set(object.keys) == ["offerId", "reason"],
              case .number(let offer) = object["offerId"], case .string(let reason) = object["reason"],
              let id = Int(NSDecimalNumber(decimal: offer).stringValue), id > 0, Decimal(id) == offer,
              (try? MerchantOfferWithdrawalReason(raw: reason))?.value == reason,
              let canonical = try? CoopFlowMutation.withdrawOffer(id: id, reason: reason).body().canonical(),
              canonical == body else { return nil }
        return (id, reason)
    }
}

/// Match exact canonical URLs and only the two request shapes emitted by DiscoveryService.
/// The backend also accepts optional list filters; they are not part of this native grant.
private enum PublicTopicTemplateReadRoute {
    case catalog, detail
    init?(url: URL, baseURL: URL) {
        switch url.absoluteString {
        case baseURL.appendingPathComponent("api/template/topic-template/list").absoluteString: self = .catalog
        case baseURL.appendingPathComponent("api/template/topic-template/info").absoluteString: self = .detail
        default: return nil
        }
    }
    func accepts(_ request: URLRequest) -> Bool {
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              let body = request.httpBody else { return false }
        switch self {
        case .catalog:
            return request.value(forHTTPHeaderField: "Content-Type") == "application/json"
                && body == Data("{}".utf8)
        case .detail:
            let typePrefix = "multipart/form-data; boundary="
            guard let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(typePrefix),
                  body.count <= 512, let text = String(data: body, encoding: .utf8) else { return false }
            let boundary = String(type.dropFirst(typePrefix.count))
            let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n"
            let suffix = "\r\n--\(boundary)--\r\n"
            guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count >= prefix.count + suffix.count else { return false }
            let value = String(text.dropFirst(prefix.count).dropLast(suffix.count))
            guard let id = Int(value), id > 0, String(id) == value,
                  let url = request.url,
                  let canonical = try? AuthRequestBuilder.makeFormRequest(url: url,
                    fields: ["id": value], token: nil, boundary: boundary) else { return false }
            // Reject duplicate/extra fields, malformed framing, alternate encodings and payloads.
            return canonical.httpBody == body
        }
    }
}

// Same device-only, unlocked secure adapter; invoice keys retain their existing owner namespace.
extension TemplateAuthoringSecureStorage: InvoiceLaunchStorage {}


/// Exact welcome-note original writer/receipt dispatch only. This does not add either
/// endpoint to generic CompositionHTTPTransport.send or borrow a general read grant.
extension CompositionHTTPTransport {
    func clubWelcomeNoteDispatchTransport(path: String, approval: @escaping () -> OperationEndpointApproval?) -> any ClubWelcomeNoteDispatching {
        ClubWelcomeNoteCompositionDispatchTransport(configured: { [weak self] in
            guard let self, let deployment = self.deployment else { return false }
            return deployment.regional.market == .china && deployment.regional.apiConfiguration != nil
        }, send: { [weak self] request, authorization in
            guard let self else { throw ClubWelcomeNoteFailure.notSent }
            return try await self.sendClubWelcomeNoteOriginal(request, authorization: authorization, path: path, approval: approval)
        })
    }
    private func sendClubWelcomeNoteOriginal(_ request: URLRequest, authorization: ClubWelcomeNoteDispatchAuthorization,
                                            path: String, approval: @escaping () -> OperationEndpointApproval?) async throws -> (Data, Int) {
        guard [ClubWelcomeNoteService.path, ClubWelcomeNoteService.receiptPath].contains(path),
              let deployment, deployment.regional.market == .china, let api = deployment.regional.apiConfiguration,
              let captured = current(), captured.isSignedInContentViewer, let actor = captured.accountID, let token = captured.token,
              let grant = approval(), grant.paths == [path],
              grant.allows(configuration: api, namespace: deployment.storageScope.service, accountID: actor, path: path),
              request.httpMethod == "POST", request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(token.utf8) == true,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.url?.absoluteString.utf8.elementsEqual(api.baseURL.appendingPathComponent(path).absoluteString.utf8) == true,
              let data = request.httpBody, data.count <= 65_536, let text = String(data: data, encoding: .utf8),
              (try? ContentDraftJSON.parse(text)) != nil,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClubWelcomeNoteFailure.notSent }
        let writing = path == ClubWelcomeNoteService.path
        let allowedHeaders: Set<String> = writing
            ? ["authorization", "content-type", "accept", "x-club-welcome-request-id", "x-club-welcome-source-sha256"]
            : ["authorization", "content-type", "accept"]
        guard (request.allHTTPHeaderFields ?? [:]).keys.allSatisfy({ allowedHeaders.contains($0.lowercased()) }) else { throw ClubWelcomeNoteFailure.notSent }
        let club = body[writing ? "id" : "clubId"] as? NSNumber
        guard let club, CFGetTypeID(club) != CFBooleanGetTypeID(), club.stringValue.range(of: "^[1-9][0-9]{0,17}$", options: .regularExpression) != nil else { throw ClubWelcomeNoteFailure.notSent }
        let requestID: String?, source: String?
        if writing {
            guard Set(body.keys) == ["id", "welcomeNote"], let note = body["welcomeNote"] as? String,
                  note.unicodeScalars.count <= 200,
                  note.utf8.elementsEqual(note.trimmingCharacters(in: .whitespacesAndNewlines).utf8) else { throw ClubWelcomeNoteFailure.notSent }
            requestID = request.value(forHTTPHeaderField: "X-Club-Welcome-Request-Id")
            source = request.value(forHTTPHeaderField: "X-Club-Welcome-Source-SHA256")
        } else {
            guard Set(body.keys) == ["clubId", "requestId", "sourceSHA256"] else { throw ClubWelcomeNoteFailure.notSent }
            requestID = body["requestId"] as? String; source = body["sourceSHA256"] as? String
        }
        guard let requestID, UUID(uuidString: requestID)?.uuidString.lowercased() == requestID,
              let source, source.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw ClubWelcomeNoteFailure.notSent }
        if writing, let note = body["welcomeNote"] as? String {
            guard source == ClubWelcomeNoteOriginalWire.source(clubID: club.stringValue, note: note) else { throw ClubWelcomeNoteFailure.notSent }
        }
        func currentGrant() -> Bool { current() == captured && approval() == grant && authorization.isCurrent && !Task.isCancelled }
        guard currentGrant() else { throw ClubWelcomeNoteFailure.notSent }
        // Mark at the last synchronous handoff to the reviewed underlying client. Any
        // failure after this boundary is conservatively UNKNOWN, never proof of no send.
        try authorization.forward(request) {}
        do {
            let reply = try await underlying.send(request)
            guard currentGrant() else { throw ClubWelcomeNoteFailure.revoked }; return reply
        } catch {
            guard currentGrant() else { throw ClubWelcomeNoteFailure.revoked }; throw error
        }
    }
}
@MainActor private final class ClubWelcomeNoteCompositionDispatchTransport: ClubWelcomeNoteDispatching {
    private let configured: () -> Bool
    private let dispatch: (URLRequest, ClubWelcomeNoteDispatchAuthorization) async throws -> (Data, Int)
    init(configured: @escaping () -> Bool,
         send: @escaping (URLRequest, ClubWelcomeNoteDispatchAuthorization) async throws -> (Data, Int)) {
        self.configured = configured; self.dispatch = send
    }
    var isConfigured: Bool { configured() }
    func send(_ request: URLRequest, authorization: ClubWelcomeNoteDispatchAuthorization) async throws -> (Data, Int) {
        try await dispatch(request, authorization)
    }
}
