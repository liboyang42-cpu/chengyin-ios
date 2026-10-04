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
    enum DeploymentState { case unconfigured, reviewed(ReviewedAppDeployment) }
    let deployment: DeploymentState
    let storage: AppScopedStorageFactory
    private let makeTransport: () -> any HTTPTransport
    /// Select independently reviewed approvals for the exact context. This builder must not
    /// turn authentication, roles, or remote booleans into OperationEndpointApproval values.
    let ownedOrderReadApproval: @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval?
    let manualMapReadApproval: @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval?
    let templateShelfReadApproval: @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval?
    let messagingHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval?
    let walletHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval?
    let cityPlayerReadApproval: @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval?
    let teamReadApproval: @MainActor (RuntimeDependencyContext) -> TeamReadApproval?
    let ownerDraftReadApproval: @MainActor (RuntimeDependencyContext) -> OwnerDraftReadApproval?
    let couponLocks: @MainActor () -> any CouponManagementLocking
    let couponReadApproval: @MainActor (RuntimeDependencyContext) -> CouponManagementReadApproval?
    let couponWriteApproval: @MainActor (RuntimeDependencyContext) -> CouponManagementWriteApproval?
    let sessionDependencies: @MainActor (RuntimeDependencyContext) -> NativeRuntimeDependencies
    init(deployment: DeploymentState = .unconfigured, storage: AppScopedStorageFactory? = nil,
         makeTransport: @escaping () -> any HTTPTransport = { URLSessionTransport() },
         sessionDependencies: (@MainActor (RuntimeDependencyContext) -> NativeRuntimeDependencies)? = nil,
         couponLocks: @escaping @MainActor () -> any CouponManagementLocking = { CouponManagementAppLocks() },
         couponReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CouponManagementReadApproval? = { _ in nil },
         couponWriteApproval: @escaping @MainActor (RuntimeDependencyContext) -> CouponManagementWriteApproval? = { _ in nil },
         templateShelfReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval? = { _ in nil },
         messagingHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval? = { _ in nil },
         walletHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval? = { _ in nil },
         cityPlayerReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval? = { _ in nil },
         teamReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TeamReadApproval? = { _ in nil },
         ownerDraftReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnerDraftReadApproval? = { _ in nil },
         manualMapReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval? = { _ in nil },
         ownedOrderReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval? = { _ in nil }) {
        self.deployment = deployment; self.storage = storage ?? .init(); self.makeTransport = makeTransport
        self.sessionDependencies = sessionDependencies ?? { _ in .dormant }
        self.couponLocks = couponLocks
        self.couponReadApproval = couponReadApproval; self.couponWriteApproval = couponWriteApproval
        self.templateShelfReadApproval = templateShelfReadApproval
        self.messagingHistoryReadApproval = messagingHistoryReadApproval
        self.walletHistoryReadApproval = walletHistoryReadApproval
        self.cityPlayerReadApproval = cityPlayerReadApproval
        self.teamReadApproval = teamReadApproval
        self.ownerDraftReadApproval = ownerDraftReadApproval
        self.manualMapReadApproval = manualMapReadApproval
        self.ownedOrderReadApproval = ownedOrderReadApproval
    }
    var reviewed: ReviewedAppDeployment? {
        if case .reviewed(let value) = deployment { return value }; return nil
    }
    func transport() -> CompositionHTTPTransport {
        CompositionHTTPTransport(deployment: reviewed, underlying: makeTransport(), couponReadApproval: couponReadApproval, couponWriteApproval: couponWriteApproval, templateShelfReadApproval: templateShelfReadApproval, messagingHistoryReadApproval: messagingHistoryReadApproval, walletHistoryReadApproval: walletHistoryReadApproval, cityPlayerReadApproval: cityPlayerReadApproval, teamReadApproval: teamReadApproval, ownerDraftReadApproval: ownerDraftReadApproval, manualMapReadApproval: manualMapReadApproval, ownedOrderReadApproval: ownedOrderReadApproval)
    }
    func makeSession() -> AppSession { AppSession(composition: self) }
}

/// Existing CN auth and independently reviewed bounded reads; coupon mutations additionally
/// require a one-use confirmed dispatch ticket. Private home keeps its separate owner grant.
/// All other paths stay closed.
/// No device/provider work or authorization is inferred from a feature grant.
@MainActor final class CompositionHTTPTransport: CouponManagementConfirmedHTTPTransport {
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
    var current: () -> SessionIdentity? = { nil }
    /// Internal scheduling seam, never a grant; the one-use final fence runs after it.
    var couponBeforeForward: (@MainActor () async -> Void)?
    /// Installed by AppSession; no runtime capability can be inferred from a root grant.
    var playReadConfiguration: @MainActor (RuntimeDependencyContext) -> RuntimeDependencyConfiguration? = { _ in nil }
    private let deployment: ReviewedAppDeployment?
    private let underlying: any HTTPTransport
    private let manualMapReadApproval: @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval?
    private let ownedOrderReadApproval: @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval?
    private let couponReadApproval: @MainActor (RuntimeDependencyContext) -> CouponManagementReadApproval?
    private let couponWriteApproval: @MainActor (RuntimeDependencyContext) -> CouponManagementWriteApproval?
    private let manualMapSelection: ManualMapAreaSelection?
    private let messagingHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval?
    private let walletHistoryReadApproval: @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval?
    private let templateShelfReadApproval: @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval?
    private let cityPlayerReadApproval: @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval?
    private let teamReadApproval: @MainActor (RuntimeDependencyContext) -> TeamReadApproval?
    private let ownerDraftReadApproval: @MainActor (RuntimeDependencyContext) -> OwnerDraftReadApproval?
    init(deployment: ReviewedAppDeployment?, underlying: any HTTPTransport,
         couponReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CouponManagementReadApproval? = { _ in nil },
         couponWriteApproval: @escaping @MainActor (RuntimeDependencyContext) -> CouponManagementWriteApproval? = { _ in nil },
         templateShelfReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TemplateShelfReadApproval? = { _ in nil },
         messagingHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> MessagingHistoryReadApproval? = { _ in nil },
         walletHistoryReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> WalletHistoryReadApproval? = { _ in nil },
         cityPlayerReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> CityPlayerReadApproval? = { _ in nil },
         teamReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> TeamReadApproval? = { _ in nil },
         ownerDraftReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnerDraftReadApproval? = { _ in nil },
         manualMapReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> ManualMapReadApproval? = { _ in nil },
         manualMapSelection: ManualMapAreaSelection? = nil,
         ownedOrderReadApproval: @escaping @MainActor (RuntimeDependencyContext) -> OwnedOrderReadApproval? = { _ in nil }) {
        self.couponReadApproval = couponReadApproval; self.couponWriteApproval = couponWriteApproval
        self.templateShelfReadApproval = templateShelfReadApproval
        self.messagingHistoryReadApproval = messagingHistoryReadApproval
        self.walletHistoryReadApproval = walletHistoryReadApproval
        self.cityPlayerReadApproval = cityPlayerReadApproval
        self.teamReadApproval = teamReadApproval
        self.deployment = deployment; self.underlying = underlying; self.ownerDraftReadApproval = ownerDraftReadApproval
        self.manualMapReadApproval = manualMapReadApproval; self.manualMapSelection = manualMapSelection
        self.ownedOrderReadApproval = ownedOrderReadApproval
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
            templateShelfReadApproval: templateShelfReadApproval, messagingHistoryReadApproval: messagingHistoryReadApproval, walletHistoryReadApproval: walletHistoryReadApproval, cityPlayerReadApproval: cityPlayerReadApproval, teamReadApproval: teamReadApproval, ownerDraftReadApproval: ownerDraftReadApproval, manualMapReadApproval: manualMapReadApproval,
            manualMapSelection: manualMapSelection, ownedOrderReadApproval: ownedOrderReadApproval)
        // Retain the identity source across temporary clone chains. Its AppSession
        // callback is weak, so this does not retain or extend the signed-in session.
        transport.current = { self.current() }
        transport.couponBeforeForward = { if let barrier = self.couponBeforeForward { await barrier() } }
        // Forward the mutable selector itself: later installation or revocation on
        // the root must reach every existing scoped/replaced transport clone.
        transport.playReadConfiguration = { self.playReadConfiguration($0) }
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
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let deployment, let api = deployment.regional.apiConfiguration,
              let url = request.url, url.fragment == nil else { throw APIError.notConfigured }
        let selectedArea = manualMapSelection?.snapshot
        let manualRead = selectedArea.flatMap { ManualMapReadRoute(request: request, baseURL: api.baseURL, area: $0.area) }
        let cityRead = CityReadRoute(request: request, baseURL: api.baseURL)
        let playRead = PlayReadRoute(request: request, baseURL: api.baseURL)
        guard url.query == nil || manualRead != nil || playRead != nil || cityRead != nil else { throw APIError.notConfigured }
        guard let captured = current() else { throw CancellationError() }
        let authPaths = [AuthEndpoint.smsSend, .phone, .userInfo, .logout].map { api.url(for: $0) }
        let auth = authPaths.contains(url)
        var readApprovalStillValid: (() -> Bool)?
        let reads = ["api/common/banner", "api/category/list", "api/topic/list", "api/activity/list", "api/club/list", "api/merchant/list"]
        if auth {
            guard deployment.regional.market == .china,
                  deployment.regional.canUseDomesticChinaPhone,
                  CNAccountSessionService.accepts(request, configuration: api) else { throw APIError.notConfigured }
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
        } else if manualRead != nil {
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
                  reads.contains(where: { api.baseURL.appendingPathComponent($0) == url }) else { throw APIError.notConfigured }
        }
        if !auth, request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) != captured.token.map({ Data($0.utf8) }) { throw CancellationError() }
        try Task.checkCancellation()
        guard current() == captured, readApprovalStillValid?() != false else { throw CancellationError() }
        do {
            let result = try await underlying.send(request)
            try Task.checkCancellation()
            guard current() == captured, readApprovalStillValid?() != false else { throw CancellationError() }
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
