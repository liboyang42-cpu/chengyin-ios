import Foundation

/// Reviewed in source/composition, never reconstructed from a login response or remote flags.
/// Adding a host is insufficient: native identity, capability evidence and read grants are separate.
struct ReviewedAppDeployment {
    let regional: RegionalConfiguration
    let storageScope: RegionalSessionStorageScope
    let reads: Set<ReadGrant>
    let privateHome: PrivateHomeTransportGrant?
    let contentDetails: SignedInContentDetailReadApproval?
    enum ReadGrant: Hashable {
        case homeAndSearch
        case manualMap
        /// Only the public route-template shelf and its projected detail, not standalone games.
        case publicTopicTemplateCatalogAndDetail
        /// Authenticated progress projection only; runtime approval is independently required.
        case playNodesAndRouteState
    }

    init(market: RegionalMarket, baseURL: String, approvedBaseURLs: [RegionalMarket: Set<String>],
         verifiedCapabilities: Set<RegionalCapability>, bundleIdentifier: String, realm: String,
         reads: Set<ReadGrant> = [], contentDetails: SignedInContentDetailReadApproval? = nil, privateHome: PrivateHomeTransportGrant? = nil) throws {
        regional = try RegionalConfiguration(market: market, baseURL: baseURL,
            approvedBaseURLs: approvedBaseURLs, verifiedCapabilities: verifiedCapabilities)
        storageScope = try RegionalSessionStorageScope(configuration: regional, bundleIdentifier: bundleIdentifier, realm: realm)
        guard privateHome == nil || privateHome?.storageScope == storageScope else { throw APIError.invalidConfiguration }
        self.reads = reads; self.privateHome = privateHome; self.contentDetails = contentDetails
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
    let defaults: UserDefaults
    let tokenStore: (RegionalSessionStorageScope?) -> any AppTokenStorage
    let privateHomeKeychain: (any PrivateHomeKeychainPrimitive)?
    let playRecovery: PlayRecoveryConstruction
#if DEBUG
    /// Explicit fixture-only override. Ordinary and Release composition keep system storage.
    var syntheticWorkshopCreatorPendingRecoveryStorage: (any TemplateAuthoringStorage)? = nil
#endif
    init(defaults: UserDefaults = .standard,
         tokenStore: @escaping (RegionalSessionStorageScope?) -> any AppTokenStorage = { KeychainTokenStore(scope: $0) },
         privateHomeKeychain: (any PrivateHomeKeychainPrimitive)? = nil,
         playRecovery: PlayRecoveryConstruction = .system) {
        self.defaults = defaults; self.tokenStore = tokenStore; self.privateHomeKeychain = privateHomeKeychain
        self.playRecovery = playRecovery
    }
    /// Existing adapters already use deployment/account-scoped owner keys. Preserve the
    /// persisted key format so an unknown operation can never disappear during migration.
    func operationJournal() -> any OperationPendingJournal {
        OperationDefaultsJournal(defaults: defaults)
    }
}

@MainActor struct AppCompositionRoot {
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
    let deployment: DeploymentState
    let storage: AppScopedStorageFactory
    private let makeTransport: () -> any HTTPTransport
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
    let templateShelfReadApproval: @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval?
    let messagingHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval?
    let roamSessionFactReadAccess: @MainActor (RuntimeDependencyContext) -> RoamSessionFactReadAccess?
    let roamNearbyEventsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamNearbyEventsReadAccess?
    let roamNearbyPlayersReadAccess: @MainActor (RuntimeDependencyContext) -> RoamNearbyPlayersReadAccess?
    /// Roam home 附近活动 peek and passport/private read tools. No reviewed default exists; nil keeps them unavailable, and writes remain strictly independent.
    let roamEntryNearbyReadAccess: @MainActor (RuntimeDependencyContext) -> RoamEntryNearbyReadAccess?
    let roamPassportToolsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamPassportToolsReadAccess?
    let roamPrivateToolsReadAccess: @MainActor (RuntimeDependencyContext) -> RoamPrivateToolsAccess?
    let profileOwnedCouponReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileOwnedCouponReadAccess?
    let roamAlbumMetadataReadAccess: @MainActor (RuntimeDependencyContext) -> RoamAlbumMetadataReadAccess?
    let roamTileMemoryReadAccess: @MainActor (RuntimeDependencyContext) -> RoamTileMemoryReadAccess?
    let profilePublicInfoReadAccess: @MainActor (RuntimeDependencyContext) -> ProfilePublicInfoReadAccess?
    let profileGuideReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileGuideReadAccess?
    let profileFavoritesReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoritesReadAccess?
    var profileFavoriteRemovalAccesses: @MainActor (RuntimeDependencyContext, UUID) -> [ProfileFavoriteRemovalAccess] = { _, _ in [] }
    /// 我的 当前权益 (`api/role/info`). No reviewed lease exists yet, so the read stays dormant.
    var memberRoleInfoReadApproval: @MainActor (RuntimeDependencyContext) -> MemberRoleInfoReadApproval? = { _ in nil }
    /// 设置 → 隐私与定位 → 我的待审媒体 (GET list only). Dormant until a reviewed lease exists.
    var ownMediaReadApproval: @MainActor (RuntimeDependencyContext) -> OwnMediaReadApproval? = { _ in nil }
    let profileFavoriteTopicReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoriteTopicReadAccess?
    let profileFavoriteDetailAccess: @MainActor (RuntimeDependencyContext) -> ProfileFavoriteDetailAccess?
    let profileInviteHistoryReadAccess: @MainActor (RuntimeDependencyContext) -> ProfileInviteHistoryReadAccess?
    let profileWeeklyPointsReadApproval: @MainActor (RuntimeDependencyContext) -> ProfileWeeklyPointsReadApproval?
    let walletHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval?
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
    let sessionDependencies: @MainActor (RuntimeDependencyContext) -> NativeRuntimeDependencies
    init(deployment: DeploymentState = .unconfigured, storage: AppScopedStorageFactory? = nil,
         makeTransport: @escaping () -> any HTTPTransport = { URLSessionTransport() },
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
         ownedOrderReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval? = { _ in nil }) {
        self.deployment = deployment; self.storage = storage ?? .init(); self.makeTransport = makeTransport
        self.projectStoryAudioUploadApproval = projectStoryAudioUploadApproval; self.makeProjectStoryAudioUploadTransport = makeProjectStoryAudioUploadTransport
        self.projectTopicImageUploadApproval = projectTopicImageUploadApproval; self.makeProjectTopicImageUploadTransport = makeProjectTopicImageUploadTransport
        self.projectStoryImageUploadApproval = projectStoryImageUploadApproval; self.makeProjectStoryImageUploadTransport = makeProjectStoryImageUploadTransport
        self.projectNodeImageUploadApproval = projectNodeImageUploadApproval; self.makeProjectNodeImageUploadTransport = makeProjectNodeImageUploadTransport
        self.ownedTopicCoverApproval = ownedTopicCoverApproval; self.makeOwnedTopicCoverTransport = makeOwnedTopicCoverTransport
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
        transport.memberRoleInfoReadApproval = memberRoleInfoReadApproval
        transport.ownMediaReadApproval = ownMediaReadApproval
        transport.roamEntryNearbyReadAccess = roamEntryNearbyReadAccess
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
    var publisherIdentityRegistrationApproval: @MainActor (RuntimeDependencyContext) -> PublisherIdentityRegistrationGrants = { _ in .init() }
    var activityCoverApproval: @MainActor (RuntimeDependencyContext) -> ActivityCoverApproval? = { _ in nil }
    var activityEditingApproval: @MainActor (RuntimeDependencyContext) -> ActivityEditingGrants = { _ in .init() }
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
    var roamEntryNearbyReadAccess: @MainActor (RuntimeDependencyContext) -> RoamEntryNearbyReadAccess? = { _ in nil }
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
        transport.memberRoleInfoReadApproval = memberRoleInfoReadApproval
        transport.ownMediaReadApproval = ownMediaReadApproval
        transport.roamEntryNearbyReadAccess = roamEntryNearbyReadAccess
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

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              let url = request.url, url.fragment == nil else { throw APIError.notConfigured }
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
        let cityRead = CityReadRoute(request: request, baseURL: api.baseURL)
        let playRead = PlayReadRoute(request: request, baseURL: api.baseURL)
        let ownedCover = OwnedTopicCoverCompositionRoute(request: request, baseURL: api.baseURL)
        let sessionFactRoute = RoamSessionFactReadRoute(request: request, baseURL: api.baseURL)
        let nearbyEventsArea = manualMapSelection?.snapshot
        let nearbyEvents = nearbyEventsArea.flatMap { RoamNearbyEventsReadRoute(request: request, baseURL: api.baseURL, area: $0.area) }
        let nearbyPlayersArea = manualMapSelection?.snapshot
        let nearbyPlayers = nearbyPlayersArea.flatMap { RoamNearbyPlayersReadRoute(request: request, baseURL: api.baseURL, area: $0.area) }
        let ownedCoupon = ProfileOwnedCouponReadRoute(request: request, baseURL: api.baseURL)
        let albumMetadata = RoamAlbumMetadataReadRoute(request: request, baseURL: api.baseURL)
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
        let ownMedia = OwnMediaReadRoute.accepts(request, baseURL: api.baseURL)
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
        guard ownMedia || nearbyEvents != nil || entryNearby != nil || passportToolPath != nil || privateToolReadPath != nil || url.query == nil || manualRead != nil || playRead != nil || cityRead != nil || ownedCover != nil || tileMemory != nil || sessionFactRoute != nil else { throw APIError.notConfigured }
        guard let captured = current() else { throw CancellationError() }
        let authPaths = [AuthEndpoint.smsSend, .phone, .userInfo, .logout].map { api.url(for: $0) }
        let auth = authPaths.contains(url)
        let publicHome = PublicMerchantHomeCompositionScope.accepts(request, baseURL: api.baseURL)
        var readApprovalStillValid: (() -> Bool)?
        let reads = ["api/common/banner", "api/category/list", "api/topic/list", "api/activity/list", "api/club/list", "api/merchant/list"]
        if auth {
            guard deployment.regional.market == .china,
                  deployment.regional.canUseDomesticChinaPhone,
                  CNAccountSessionService.accepts(request, configuration: api) else { throw APIError.notConfigured }
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
            guard let approval = ownMediaReadApproval(context), approval.matches(context) else { throw APIError.notConfigured }
            readApprovalStillValid = { [ownMediaReadApproval] in
                guard let selected = ownMediaReadApproval(context) else { return false }
                return selected === approval && selected.matches(context)
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
        } else if url == api.baseURL.appendingPathComponent(PrivateHomeService.path) {
            guard let grant = deployment.privateHome,
                  grant.matches(storageScope: deployment.storageScope, accountID: captured.accountID, role: captured.role),
                  let token = captured.token, AuthRequestBuilder.isValidToken(token),
                  ["GET", "PUT", "DELETE"].contains(request.httpMethod ?? "") else { throw APIError.notConfigured }
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
        } else if let route = PublicTopicTemplateReadRoute(url: url, baseURL: api.baseURL) {
            guard deployment.reads.contains(.publicTopicTemplateCatalogAndDetail),
                  route.accepts(request), captured.isPublicTemplateViewer else { throw APIError.notConfigured }
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
            if let ticketWalletList {
                try ticketWalletList.validateResponse(result, expectedAccountID: captured.accountID ?? 0)
            }
            try ownedCoupon?.validateResponse(result, accountID: captured.accountID ?? 0)
            try albumMetadata?.validateResponse(result)
            try tileMemory?.validateResponse(result)
            try favoriteList?.validateResponse(result)
            try favoriteDetail?.validateResponse(result)
            try guideRead?.validateResponse(result)
            try sessionFactRoute?.validateResponse(result)
            try favoriteTopic?.validateResponse(result)
            try nearbyEvents?.validateResponse(result)
            try nearbyPlayers?.validateResponse(result)
            try publicInfo?.validateResponse(result)
            return result
        } catch {
            guard current() == captured, !Task.isCancelled, readApprovalStillValid?() != false else { throw CancellationError() }
            throw error
        }
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
