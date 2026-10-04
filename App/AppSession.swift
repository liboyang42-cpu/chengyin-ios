import Foundation
import Combine
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var account: Account? { willSet { invalidateOwnerDraftBrowser(); if account?.id != newValue?.id || account?.effectiveRole != newValue?.effectiveRole { invalidateShopNPCConversations(); merchantNPCSessionOwner.invalidate() }; if account?.id != newValue?.id { platformConsumers.invalidate() } } didSet { _ = runtimeDependencies; synchronizeAccountMarketingEntry() } }
    @Published private(set) var isWorking = false { didSet { synchronizeAccountMarketingEntry() } }
    @Published private(set) var errorKey: String?
    let platformConsumers = PlatformConsumerSessionOwner()
    let retainedImagePickerHost = RetainedImagePickerHost()
    private var publicMerchantReviewEpoch = UUID()
    private var currentRetainedImageCredentials: RetainedImageHostCredentials? {
        guard let account, let token, let namespace = storageScope?.service,
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        return RetainedImageHostCredentials(accountID: account.id, sessionVersion: gate.currentStamp,
            realm: configuration.baseURL.absoluteString, namespace: namespace, token: token, authorizationRevision: account.effectiveRole)
    }
    private lazy var imageUploadStorage = ImageUploadSecureStorage(scope: storageScope)
    private lazy var imageUploadJournal = StoredImageUploadJournal(
        read: { [unowned self] in try self.imageUploadStorage.read($0) },
        write: { [unowned self] in try self.imageUploadStorage.write($0, key: $1) })
    private lazy var retainedImageContextCache: RetainedImageContextCache? = {
        guard let configuration = regionalConfiguration?.apiConfiguration, storageScope != nil else { return nil }
        return RetainedImageContextCache(configuration: configuration, transport: runtimeHTTPTransport,
            pickerHost: retainedImagePickerHost, journal: imageUploadJournal, currentCredentials: { [weak self] in self?.currentRetainedImageCredentials })
    }()
    lazy var retainedMerchantImages: MerchantRetainedImageHost? = retainedImageContextCache.map { MerchantRetainedImageHost(cache: $0) }
    private var currentPublicMerchantReviewSession: PublicMerchantReviewSession? {
        guard let credentials = currentRetainedImageCredentials else { return nil }
        return try? PublicMerchantReviewSession(accountID: credentials.accountID, scope: publicMerchantReviewEpoch,
            realm: credentials.realm, token: credentials.token)
    }
    private lazy var retainedPublicMerchantReviews: RetainedPublicMerchantReviewHost? = {
        guard let configuration = regionalConfiguration?.apiConfiguration, let cache = retainedImageContextCache else { return nil }
        return RetainedPublicMerchantReviewHost(configuration: configuration, transport: runtimeHTTPTransport, cache: cache,
            currentSession: { [weak self] in self?.currentPublicMerchantReviewSession })
    }()

    private let merchantNPCSessionOwner = MerchantNPCSessionOwner()
    private var merchantNPCGrants: MerchantNPCGrants { merchantPublicFactory?.chatGrants ?? .init() }
    private var merchantNPCJournal: any OperationPendingJournal { composition.storage.operationJournal() }
    private var merchantNPCAccess: (scope: UUID, value: MerchantOperationsAccess, revision: UUID)?
    private func merchantNPCScope(row: PublicMerchantRowID, resource: Bool = false) -> MerchantNPCScope? {
        guard let account, token != nil, let namespace = storageScope?.service else { return nil }
        let epoch = merchantOperationsReader.scope
        let revision: UUID
        if resource {
            guard let proof = merchantNPCAccess, proof.scope == epoch, proof.value.identity.merchantID == row.rawValue,
                  proof.value.allows(.assets) else { return nil }
            revision = proof.revision
        } else { revision = publicMerchantHomeReader.scope }
        return MerchantNPCScope(accountID: account.id, namespace: namespace, epoch: epoch, merchantRowID: row, accessRevision: revision)
    }
    private func merchantNPCClient(resource: Bool) -> MerchantNPCHTTPClient {
        guard let factory = merchantPublicFactory else { return .init() }
        if resource { return factory.resourceClient() }
        return factory.chatClient(currentScope: { [weak self] row in self?.merchantNPCScope(row: row) })
    }
    func merchantOperationsDestination(_ destination: MerchantOperationsDestination, access: MerchantOperationsAccess) -> AnyView {
        guard destination == .assets else { return AnyView(MerchantOperationsDocumentView(reader: merchantOperationsReader, destination: destination, imageHost: retainedMerchantImages, templateAssistFactory: { [weak self] coordinator in
            self?.merchantTemplateAssistFlow(coordinator: coordinator) ?? MerchantTemplateAssistFlow(coordinator: coordinator, client: nil)
        })) }
        // CURRENT backend has no legacy script/avatar resource contract. Do not query invented routes.
        guard MerchantPublicProductionFactory.supportsLegacyResources else { return AnyView(Text("merchantNPC.unavailable")) }
        let epoch = merchantOperationsReader.scope
        if merchantNPCAccess?.scope != epoch || merchantNPCAccess?.value != access {
            merchantNPCSessionOwner.invalidate(); merchantNPCAccess = (epoch, access, UUID())
        }
        guard let id = access.identity.merchantID, let row = PublicMerchantRowID(id), access.allows(.assets),
              let captured = merchantNPCScope(row: row, resource: true) else { return AnyView(Text("merchantNPC.unavailable")) }
        let coordinator = MerchantNPCResourcesCoordinator(scope: captured, client: merchantNPCClient(resource: true), reader: merchantOperationsReader,
            journal: merchantNPCJournal, currentScope: { [weak self] in self?.merchantNPCScope(row: row, resource: true) },
            grants: { .init() })
        merchantNPCSessionOwner.register(coordinator)
        return AnyView(MerchantNPCResourceEditor(coordinator: coordinator, imageContext: merchantNPCAvatarContext(captured),
            imageRealm: regionalConfiguration?.apiConfiguration?.baseURL.absoluteString, approvedImageHosts: []).id(captured.epoch))
    }
    private func merchantNPCAvatarContext(_ captured: MerchantNPCScope) -> RetainedImageSelectionContext? {
        guard let cache = retainedImageContextCache, let credentials = currentRetainedImageCredentials,
              merchantNPCScope(row: captured.merchantRowID, resource: true) == captured,
              let imageScope = try? RetainedImageScope(accountID: captured.accountID, epoch: captured.epoch,
                realm: credentials.realm, destination: .merchant(merchantRowID: captured.merchantRowID.rawValue, field: .avatar),
                accessRevision: captured.accessRevision, namespace: captured.namespace) else { return nil }
        return cache.context(scope: imageScope, destination: .merchant(captured.merchantRowID, .avatar, templateID: nil, newDraftID: nil),
            ownerID: captured.accessRevision, isCurrent: { [weak self] in
                self?.merchantNPCScope(row: captured.merchantRowID, resource: true) == captured
            })
    }
    private let disabledPublicMerchantHomeReader = DisabledPublicMerchantHomeReader()
    private var retainedMerchantPublicFactory: MerchantPublicProductionFactory?
    private var currentMerchantPublicContext: MerchantPublicHostContext? {
        guard let regionalConfiguration, let api = regionalConfiguration.apiConfiguration,
              let namespace = storageScope?.service else { return nil }
        return try? .init(market: regionalConfiguration.market, baseURL: api.baseURL, namespace: namespace,
            accountID: account?.id, epoch: gate.currentStamp, role: account?.effectiveRole, token: token)
    }
    private var merchantPublicFactory: MerchantPublicProductionFactory? {
        guard let api = regionalConfiguration?.apiConfiguration, let context = currentMerchantPublicContext else { return nil }
        if let retainedMerchantPublicFactory, retainedMerchantPublicFactory.captured == context { return retainedMerchantPublicFactory }
        let factory = runtimeDependencies.makeMerchantPublicFactory(api: api, journal: merchantNPCJournal, transportOverride: runtimeHTTPTransport,
            current: { [weak self] in self?.currentMerchantPublicContext })
        retainedMerchantPublicFactory = factory
        return factory
    }
    private var publicMerchantHomeReader: any PublicMerchantHomeReading {
        merchantPublicFactory?.homeReader ?? disabledPublicMerchantHomeReader
    }
    private var publicMerchantReviewReader: any PublicMerchantReviewReading = DisabledPublicMerchantReviewReader()
    var publicMerchantHomeContext: PublicMerchantHomeContext {
        let retained = retainedPublicMerchantReviews
        let reviews: any PublicMerchantReviewReading = retained?.reader ?? publicMerchantReviewReader
        let images: any RetainedPublicImageReading = retained?.imageReader ?? RetainedPublicImageReader(enabled: false, origins: [])
        let writes = retained?.writeContext(journal: merchantBusinessJournal)
        var context = PublicMerchantHomeContext(reader: publicMerchantHomeReader,
            publicReviews: { AnyView(PublicMerchantReviewsView(target: $0, reader: reviews, imageReader: images, writes: writes)) })
        context.installMerchantNPC(grants: { [weak self] in self?.merchantNPCGrants ?? .init() },
            scopeForRow: { [weak self] in self?.merchantNPCScope(row: $0) },
            currentScope: { [weak self] in self?.merchantNPCScope(row: $0) }, client: merchantNPCClient(resource: false),
            register: { [weak self] in self?.merchantNPCSessionOwner.register($0) })
        return context
    }
    private let communityService = ClubCommunityService(dormantBaseURL: URL(string: "https://disabled.invalid")!, transport: CommunityDormantHTTPTransport())
    private func currentCommunitySession() throws -> ClubCommunitySession {
        try ClubCommunitySession(identity: clubIdentity, token: token)
    }
    private lazy var communityCoordinator = ClubCommunityCoordinator(service: communityService, currentSession: { [weak self] in
        guard let self else { throw ClubCommunityFailure.unavailable }; return try self.currentCommunitySession()
    }, refreshEvidence: { [weak self] old in
        guard let self else { throw ClubCommunityFailure.unavailable }
        return try await self.communityEvidence(clubID: old.clubID, post: old.post, comment: old.comment)
    })
    var clubCommunityContext: ClubCommunityContext {
        ClubCommunityContext(service: communityService, currentSession: { [weak self] in
            guard let self else { throw ClubCommunityFailure.unavailable }; return try self.currentCommunitySession()
        }, coordinator: communityCoordinator, evidence: { [weak self] clubID, post, comment in
            guard let self else { throw ClubCommunityFailure.unavailable }
            return try await self.communityEvidence(clubID: clubID, post: post, comment: comment)
        })
    }
    private func communityEvidence(clubID: Int, post: ClubCommunityPost?, comment: ClubCommunityComment?) async throws -> ClubCommunityEvidence {
        let captured = try currentCommunitySession()
        let membership = try await clubDetail(id: clubID)
        guard membership.id == clubID, try currentCommunitySession() == captured else { throw ClubCommunityFailure.stale }
        var freshPost: ClubCommunityPost?
        var freshComment: ClubCommunityComment?
        if let post {
            let page = try await communityService.read(.posts(clubID: clubID, page: 1), session: captured) {
                guard try self.currentCommunitySession() == captured else { throw ClubCommunityFailure.stale }
            }
            guard let exact = page.posts.first(where: { $0.id == post.id }), exact.clubID == clubID else { throw ClubCommunityFailure.stale }
            freshPost = exact
            if let comment {
                let comments = try await communityService.read(.comments(postID: exact.id, page: 1), session: captured) {
                    guard try self.currentCommunitySession() == captured else { throw ClubCommunityFailure.stale }
                }
                guard let exactComment = comments.comments.first(where: { $0.id == comment.id }), exactComment.postID == exact.id else { throw ClubCommunityFailure.stale }
                freshComment = exactComment
            }
        } else if comment != nil { throw ClubCommunityFailure.invalid }
        guard try currentCommunitySession() == captured else { throw ClubCommunityFailure.stale }
        return .init(identity: captured.identity, clubID: clubID, joined: membership.isJoined, owner: membership.isOwner,
            administrator: membership.viewerIsAdmin, post: freshPost, comment: freshComment)
    }
    private var gate = SessionOperationGate() { didSet { retainedSocialMemberActions?.synchronizeSession(); synchronizePrivateHome(); synchronizeOwnerDraftBrowser() } }
    private let vault: any AppTokenStorage
    private let composition: AppCompositionRoot
    private let compositionTransport: CompositionHTTPTransport
    private var compositionViewerRevision: UInt64 = 0
    private var sessionDefaults: UserDefaults { composition.storage.defaults }
    private let storageScope:RegionalSessionStorageScope?
    let regionalConfiguration:RegionalConfiguration?
    var operationalMarket:RegionalMarket? { regionalConfiguration?.market ?? RegionalLaunchConfiguration.market }
    var canUsePassword:Bool { storageScope != nil && regionalConfiguration?.availability(of:.usernamePassword) == .available }
    var supportsDomesticPhoneInput:Bool { operationalMarket == .china }
    private let service: AuthService?
    private let accountSessionService: CNAccountSessionService?
    private let activityService: ActivityService?
    private let searchMapService: SearchMapService?
    private let searchMapSelection = ManualMapAreaSelection()
    private let roamMapSelection = ManualMapAreaSelection()
    private var currentSearchMapContext: SearchMapContext {
        if let account, let token, let context = try? SearchMapContext(accountID: account.id, epoch: gate.currentStamp, token: token, role: account.effectiveRole, viewerRevision: compositionViewerRevision, manualMapApprovalRevision: currentManualMapApprovalRevision) { return context }
        return SearchMapContext(guestEpoch: gate.currentStamp)
    }
    /// Re-evaluate current approval at the reader/UI boundary as well as the raw transport.
    /// Service decode/fan-out can suspend after an individual transport returns.
    private var currentManualMapApprovalRevision: UUID? {
        guard composition.reviewed?.reads.contains(.manualMap) == true,
              let context = currentRuntimeDependencyContext,
              let approval = composition.manualMapReadApproval(context), approval.matches(context) else { return nil }
        return approval.revision
    }
    var searchMapHistoryNamespace: String? {
        guard let storageScope else { return nil }
        return storageScope.service + ".search." + (account.map { String($0.id) } ?? "guest")
    }
    lazy var searchMapReader = SearchMapSessionReader(service: searchMapService, currentContext: { [weak self] in
        self?.currentSearchMapContext ?? SearchMapContext(guestEpoch: 0)
    }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentSearchMapContext == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    }, manualAreaSelection: searchMapSelection)
    private let registrationApproval: RegistrationProductionApproval?
    private let registrationStorefront: () -> String?
    private var registrationJournal: any OperationPendingJournal { composition.storage.operationJournal() }
    private var currentRegistrationProductionSession: RegistrationProductionSession? {
        guard let identity = profileReader.identity, let namespace = storageScope?.service,
              let market = regionalConfiguration?.market, let storefront = registrationStorefront(), let token else { return nil }
        return try? .init(identity: identity, namespace: namespace, market: market, storefront: storefront, token: token)
    }
    private lazy var productionRegistrationService: RegistrationProductionService? = {
        guard let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        return RegistrationProductionFactory.make(configuration: configuration, approval: registrationApproval,
            journal: registrationJournal, current: { [weak self] in self?.currentRegistrationProductionSession })
    }()
    func registrationWaitlistService(activityID: Int) -> (any RegistrationWaitlistServing)? {
        guard case .approved = registrationCreationPolicy(activityID: activityID) else { return nil }
        return productionRegistrationService
    }
    func registrationCreationPolicy(activityID: Int) -> RegistrationUICreationPolicy {
        guard let service = productionRegistrationService, let current = currentRegistrationProductionSession,
              current.identity == service.approval.identity, current.storefront == service.approval.storefront,
              current.market == service.approval.market, current.namespace == service.approval.endpoint.namespace,
              activityID == service.approval.activityID, Date() < service.approval.expiresAt else { return .disabled }
        return .approved(service.approval)
    }
    private let registrationBackend: any RegistrationCoordinatingService
    private var registrationIdentity: ProfileReadIdentity?
    private lazy var retainedRegistration: RegistrationCoordinator = {
        let backend: any RegistrationCoordinatingService = productionRegistrationService.map { $0 as any RegistrationCoordinatingService } ?? registrationBackend
        return RegistrationCoordinator(service: backend)
    }()
    var registrationCoordinator: RegistrationCoordinator { synchronizeRegistration();return retainedRegistration }
    private func synchronizeRegistration() {
        let identity=profileReader.identity
        guard registrationIdentity != identity else { return }
        registrationIdentity=identity
        if let identity,let token { try? retainedRegistration.setAccount(id:identity.accountID,token:token) }
        else { retainedRegistration.clearAccount() }
    }
    // Shop NPC remains node-addressed and dormant. No grant derives from a role/name/image.
    private let shopNPCSessionOwner = ShopNPCSessionOwner()
    private var shopNPCGrants: ShopNPCGrants { runtimeDependencyFactory?.accepted != nil ? runtimeDependencies.shopNPCGrants : ShopNPCGrants() }
    private var shopNPCProductionWritesEnabled: Bool { runtimeDependencyFactory?.accepted?.shopNPCWrites == true }
    func invalidateShopNPCConversations() { shopNPCSessionOwner.invalidate() }
    private func currentShopNPCSession(scope: PlaySessionScope, nodeID: Int,
                                       runtime: PlayExperienceCoordinator, npc: PlayNPCBrief) -> ShopNPCHostSession? {
        guard scope.isValid, runtime.scope == scope, runtime.hasCurrentMediaSnapshot,
              let snapshot = runtime.snapshot, snapshot.availability == .active,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }),
              !snapshot.isLocked(node), node.npc == npc,
              let nodeID = ShopNPCNodeID(nodeID), let account, let token,
              let namespace = storageScope?.service, regionalConfiguration?.apiConfiguration != nil else { return nil }
        let kind: String
        switch scope { case .activity: kind = "activity"; case .topic: kind = "topic" }
        let binding = ShopNPCScope(sessionID: "\(namespace):\(gate.currentStamp):\(kind):\(scope.id)",
            accountID: String(account.id), roleID: account.effectiveRole,
            accessRevision: shopNPCSessionOwner.accessRevision, nodeID: nodeID)
        return try? ShopNPCHostSession(scope: binding, token: token)
    }
    func shopNPCNodeHost(scope: PlaySessionScope, nodeID: Int, runtime: PlayExperienceCoordinator) -> ShopNPCNodeHost? {
        guard let npc = runtime.snapshot?.visibleNodes.first(where: { $0.id == nodeID })?.npc,
              let captured = currentShopNPCSession(scope: scope, nodeID: nodeID, runtime: runtime, npc: npc),
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let identity = "\(captured.scope.sessionID):\(captured.scope.accountID):\(captured.scope.roleID):\(captured.scope.accessRevision):\(nodeID):\(npc.name):\(npc.greeting ?? "")"
        let fallbackTransport = runtimeHTTPTransport
        return ShopNPCNodeHost(identity: identity, name: npc.name, greeting: npc.greeting, makeCoordinator: { [weak self, weak runtime] in
            let current: () -> ShopNPCHostSession? = { [weak self, weak runtime] in
                guard let self, let runtime else { return nil }
                return self.currentShopNPCSession(scope: scope, nodeID: nodeID, runtime: runtime, npc: npc)
            }
            let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: configuration, transport: self?.runtimeDependencyFactory?.transport ?? RuntimeDependencyTransport(configuration: nil, captured: nil, transport: fallbackTransport, current: { nil }),
                productionWritesEnabled: self?.shopNPCProductionWritesEnabled ?? false, currentSession: current,
                currentGrants: { [weak self] in self?.shopNPCGrants ?? .init() },
                onUnauthorized: { [weak self] old in
                    guard let self, current() == old else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: self.gate.currentStamp, credential: self.token)
                })
            let coordinator = ShopNPCCoordinator(scope: captured.scope, grants: self?.shopNPCGrants ?? .init(),
                client: ShopNPCHTTPClient(transport: adapter))
            self?.shopNPCSessionOwner.register(coordinator)
            // Re-resolve node data and identity at navigation time; a stale destination fails closed.
            if current() != captured { coordinator.invalidate() }
            return coordinator
        })
    }

    private var currentPlayerJourneySession: PlayerJourneySession? {
        guard let account, let token, let namespace = storageScope?.service else { return nil }
        return try? PlayerJourneySession(accountID: account.id, epoch: gate.currentStamp, namespace: namespace, token: token)
    }
    lazy var playerJourneyReader = PlayerJourneySessionReader(service: regionalConfiguration?.apiConfiguration.map {
        PlayerJourneyService(configuration: $0, transport: runtimeHTTPTransport)
    }, currentSession: { [weak self] in self?.currentPlayerJourneySession }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentPlayerJourneySession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    }) // Dedicated history read grant remains off until independently accepted.
    private struct PlayReadApprovalKey: Hashable { let issuance: UUID; let paths: Set<String> }
    /// Called at construction and final projection, outside service decode work as well.
    private var currentPlayReadApprovalKey: PlayReadApprovalKey? {
        guard composition.reviewed?.reads.contains(.playNodesAndRouteState) == true,
              let context = currentRuntimeDependencyContext,
              let approval = compositionTransport.playReadConfiguration(context),
              let issuance = approval.playReadApprovalID,
              approval.matches(context), approval.play.contains(.reads),
              approval.endpoints.paths.contains("api/play/nodes") else { return nil }
        return .init(issuance: issuance,
            paths: approval.endpoints.paths.intersection(["api/play/nodes", "api/play/route-state"]))
    }
    private var playReadDependencyFactory: RuntimeDependencyFactory? {
        guard let api = regionalConfiguration?.apiConfiguration, let context = currentRuntimeDependencyContext else { return nil }
        return RuntimeDependencyFactory(api: api, configuration: compositionTransport.playReadConfiguration(context),
            transport: compositionTransport, current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    private var playService: PlayService? {
        guard currentPlayReadApprovalKey != nil,
              composition.reviewed?.reads.contains(.playNodesAndRouteState) == true,
              let api = regionalConfiguration?.apiConfiguration,
              let factory = playReadDependencyFactory, factory.accepted?.play.contains(.reads) == true else { return nil }
        return PlayService(configuration: api, transport: factory.transport)
    }
    private struct PlayReaderKey: Hashable { let accountID:Int?;let epoch:UInt64;let role:String?;let viewerRevision:UInt64;let approval:PlayReadApprovalKey?;let scope:PlaySessionScope }
    private var playReaders:[PlayReaderKey:PlaySessionReader]=[:]
    func playReader(for scope:PlaySessionScope) -> PlaySessionReader {
        let key=PlayReaderKey(accountID:account?.id,epoch:gate.currentStamp,role:account?.effectiveRole,viewerRevision:compositionViewerRevision,approval:currentPlayReadApprovalKey,scope:scope)
        if let reader=playReaders[key] { return reader }
        let reader=PlaySessionReader(scope:scope,service:playService,answersEnabled:false,currentSession:{ [weak self] in
            guard let self, self.compositionViewerRevision == key.viewerRevision,
                  key.approval != nil, self.currentPlayReadApprovalKey == key.approval,
                  let account=self.account,let token=self.token else { return nil }
            return try? PlayReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
        },onUnauthorized:{ [weak self] snapshot in
            guard let self, self.compositionViewerRevision == key.viewerRevision,
                  key.approval != nil, self.currentPlayReadApprovalKey == key.approval else { return }
            self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.epoch,credential:self.token)
        })
        playReaders[key]=reader
        return reader
    }
    // Retained owner/scope-bound durable recovery; all normal-root write grants stay off.
    private var playExperienceCoordinators: [PlayReaderKey: PlayExperienceCoordinator] = [:]
    func playExperience(for scope: PlaySessionScope) -> PlayExperienceCoordinator? {
        guard scope.isValid, let regional = regionalConfiguration,
              let configuration = regional.apiConfiguration, let storageScope else { return nil }
        let key = PlayReaderKey(accountID: account?.id, epoch: gate.currentStamp, role: account?.effectiveRole, viewerRevision: compositionViewerRevision, approval: currentPlayReadApprovalKey, scope: scope)
        if let retained = playExperienceCoordinators[key] { return retained }
        guard key.approval != nil, composition.reviewed?.reads.contains(.playNodesAndRouteState) == true,
              let factory = playReadDependencyFactory, factory.accepted?.play.contains(.reads) == true else { return nil }
        // One selector supplies both the captured storage owner and every later callback.
        // Keep the issuance and ABA fences even when the same account/role returns.
        let current: () -> PlayExperienceSession? = { [weak self] in
            guard let self, !self.committingAuthenticatedSession,
                  self.compositionViewerRevision == key.viewerRevision,
                  key.approval != nil, self.currentPlayReadApprovalKey == key.approval,
                  let account = self.account, let token = self.token,
                  let role = PlayRecoveryAccountRole(rawValue: account.effectiveRole) else { return nil }
            return try? PlayExperienceSession(accountID: account.id, epoch: self.gate.currentStamp,
                namespace: storageScope.service, token: token, role: role.rawValue)
        }
        guard let captured = current(),
              let recovery = try? composition.storage.playRecovery.make(session: captured, scope: scope,
                regionalConfiguration: regional, storageScope: storageScope),
              current() == captured else { return nil }
        // The normal root admits only progress reads. Durable recovery does not grant writes.
        let api = PlayExperienceService(configuration: configuration, transport: factory.transport,
            enabled: factory.accepted?.play.intersection([.reads]) ?? [])
        let coordinator = PlayExperienceCoordinator(scope: scope, service: api,
            recovery: recovery, pausedStorage: recovery,
            currentSession: { current() == captured ? captured : nil },
            onUnauthorized: { [weak self] snapshot in
                guard let self, snapshot == captured, current() == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
        playExperienceCoordinators[key] = coordinator
        return coordinator
    }
    // Journey extras are independent of task completion, advanced games and local dice.
    private var retainedJourneyNarratives: [String: JourneyNarrativeCoordinator] = [:]
    var journeyNarrativeImageReader: (any RetainedPublicImageReading)? { runtimeDependencies.journeyNarrativeImageReader }
    private lazy var journeyNarrativeJournal = JourneyStoredNarrativeJournal(
        read: { [weak self] key in try self?.templateAuthoringSecureStorage.read(key) },
        write: { [weak self] data, key in
            guard let self else { throw APIError.notConfigured }
            try self.templateAuthoringSecureStorage.write(data, key: key)
        })
    func journeyNarrative(scope: PlaySessionScope, topicID: Int?, query: JourneyNarrativeQuery) -> JourneyNarrativeCoordinator? {
        guard let topicID, let target = try? JourneyNarrativeScope(scope: scope, topicID: topicID),
              let factory = runtimeDependencyFactory else { return nil }
        let key = playRuntimeKey(scope, suffix: "journey-narrative:\(topicID):\(query.key)")
        if let model = retainedJourneyNarratives[key] { model.synchronize(); return model }
        let model = JourneyNarrativeCoordinator(scope: target, query: query, service: factory.journeyNarrativeService(),
            journal: journeyNarrativeJournal, currentSession: { [weak self] in self?.currentPlayRuntimeSession },
            onUnauthorized: { [weak self] captured in
                guard let self else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
        retainedJourneyNarratives[key] = model; return model
    }
    private var retainedJourneyChecks: [String: JourneyCheckCoordinator] = [:]
    private var retainedJourneyAmbient: [String: JourneyAmbientCoordinator] = [:]
    private lazy var journeySeenStore = JourneyPersistentEggSeenStorage(
        read: { [weak self] key in try self?.templateAuthoringSecureStorage.read(key) },
        write: { [weak self] data, key in
            guard let self else { throw APIError.notConfigured }
            try self.templateAuthoringSecureStorage.write(data, key: key)
        })
    private lazy var journeyCheckJournal = JourneyStoredCheckJournal(
        read: { [weak self] key in try self?.templateAuthoringSecureStorage.read(key) },
        write: { [weak self] data, key in
            guard let self else { throw APIError.notConfigured }
            try self.templateAuthoringSecureStorage.write(data, key: key)
        })
    private func dormantJourneyService() -> JourneyContentService? {
        guard regionalConfiguration?.apiConfiguration != nil, storageScope != nil else { return nil }
        return runtimeDependencyFactory?.journeyService()
    }
    func journeyCheck(scope: PlaySessionScope, topicID: Int?, nodeID: Int) -> JourneyCheckCoordinator? {
        guard scope.isValid, let topicID, topicID > 0, nodeID > 0, let service = dormantJourneyService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "journey:\(topicID):\(nodeID)")
        if let model = retainedJourneyChecks[key] { model.synchronize(); return model }
        let model = JourneyCheckCoordinator(scope: scope, topicID: topicID, nodeID: nodeID, service: service,
            journal: journeyCheckJournal, currentSession: { [weak self] in self?.currentPlayRuntimeSession },
            onUnauthorized: { [weak self] captured in
                guard let self else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
        retainedJourneyChecks[key] = model; return model
    }
    func journeyAmbient(scope: PlaySessionScope) -> JourneyAmbientCoordinator? {
        guard scope.isValid, let service = dormantJourneyService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "journey-ambient")
        if let model = retainedJourneyAmbient[key] { model.synchronize(); return model }
        let model = JourneyAmbientCoordinator(scope: scope, service: service, store: journeySeenStore,
                                            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedJourneyAmbient[key] = model; return model
    }

    private var retainedPlayAdvanced: [String: PlayAdvancedCoordinator] = [:]
    private var retainedPlayPreferences: [String: PlayPreferenceCoordinator] = [:]
    private var retainedPlaySummaries: [String: PlayOperatingSummaryCoordinator] = [:]
    private var retainedPlayDirectors: [String: PlayDirectorCoordinator] = [:]
    private var retainedPlayPrefabs: [String: PlayPrefabRuntimeCoordinator] = [:]
    private lazy var prefabRuntimeStore = PlayPrefabRuntimeStore(storage: templateAuthoringSecureStorage)
    @Published private var ownerDraftPresentationActive = true
    private var retainedOwnerDraftBrowser: (context: RuntimeDependencyContext, browser: OwnerDraftBrowser)?
    private var currentOwnerDraftContext: RuntimeDependencyContext? {
        guard ownerDraftPresentationActive, !committingAuthenticatedSession else { return nil }
        return currentRuntimeDependencyContext
    }
    var ownerDraftBrowser: OwnerDraftBrowser? {
        synchronizeOwnerDraftBrowser()
        if let retainedOwnerDraftBrowser { return retainedOwnerDraftBrowser.browser }
        guard let captured = currentOwnerDraftContext,
              let browser = composition.makeOwnerDraftBrowser(context: captured, transport: compositionTransport,
                current: { [weak self] in self?.currentOwnerDraftContext },
                onUnauthorized: { [weak self] context in
                    guard let self, ContentDraftContextFence.matches(self.currentOwnerDraftContext, context) else { return }
                    self.expireIfMatching(error: APIError.unauthorized, stamp: context.session.epoch, credential: context.session.token)
                }) else { return nil }
        retainedOwnerDraftBrowser = (captured, browser); return browser
    }
    private func synchronizeOwnerDraftBrowser() {
        if let retainedOwnerDraftBrowser,
           !ContentDraftContextFence.matches(currentOwnerDraftContext, retainedOwnerDraftBrowser.context) { invalidateOwnerDraftBrowser() }
    }
    func invalidateOwnerDraftBrowser() {
        retainedOwnerDraftBrowser?.browser.invalidate(); retainedOwnerDraftBrowser = nil
    }
    func setOwnerDraftPresentationActive(_ active: Bool) {
        ownerDraftPresentationActive = active
        if !active { invalidateOwnerDraftBrowser() }
    }
    @Published private var privateHomePresentationActive = true
    private var retainedPrivateHome: (context: RuntimeDependencyContext, coordinator: PrivateHomeCoordinator)?
    private var currentPrivateHomeContext: RuntimeDependencyContext? {
        guard !committingAuthenticatedSession, privateHomePresentationActive else { return nil }
        return currentRuntimeDependencyContext
    }
    /// AccountView receives this exact session-owned instance; no independent UI/service owner.
    var privateHomeCoordinator: PrivateHomeCoordinator? {
        synchronizePrivateHome()
        if let retainedPrivateHome { return retainedPrivateHome.coordinator }
        guard let captured = currentPrivateHomeContext,
              let coordinator = composition.makePrivateHomeCoordinator(context: captured, transport: compositionTransport,
                  current: { [weak self] in self?.currentPrivateHomeContext }) else { return nil }
        retainedPrivateHome = (captured, coordinator)
        return coordinator
    }
    private func synchronizePrivateHome() {
        if let retainedPrivateHome, retainedPrivateHome.context != currentPrivateHomeContext { invalidatePrivateHome() }
    }
    /// An offscreen old root cannot reconstruct a coordinator. Reentry explicitly reactivates
    /// the current session and creates a fresh owner that reloads the exact durable journal.
    func setPrivateHomePresentationActive(_ active: Bool) {
        privateHomePresentationActive = active
        if !active { invalidatePrivateHome() }
    }
    /// Also called when the root leaves (including immutable deployment/realm replacement).
    /// Revokes retained references and clears display only; the durable unknown record survives.
    func invalidatePrivateHome() {
        retainedPrivateHome?.coordinator.invalidate(); retainedPrivateHome = nil
    }
    private var committingAuthenticatedSession = false
    private let injectedRuntimeDependencies: NativeRuntimeDependencies?
    private var retainedDependencyContext: RuntimeDependencyContext?
    private var retainedDependencies: NativeRuntimeDependencies = .dormant
    private var runtimeDependencies: NativeRuntimeDependencies {
        retainedSocialMemberActions?.synchronizeSession()
        guard !committingAuthenticatedSession, let context = currentRuntimeDependencyContext else {
            retainedDependencyContext = nil; retainedDependencies = .dormant
            return .dormant
        }
        if retainedDependencyContext != context {
            retainedDependencyContext = context
            retainedDependencies = injectedRuntimeDependencies ?? composition.sessionDependencies(context)
        }
        return retainedDependencies
    }
    var walkingNavigationFactory: NativeWalkingNavigationFactory { NativeWalkingNavigationFactory(
        dependencies: runtimeDependencies.walkingNavigation, context: { [weak self] in self?.currentRuntimeDependencyContext }) }
    private var runtimeHTTPTransport: any HTTPTransport { compositionTransport }
    private func scopedTransport(_ injected: (any HTTPTransport)?) -> any HTTPTransport {
        guard let injected else { return compositionTransport }
        return compositionTransport.replacingUnderlying(injected)
    }
    private var currentRuntimeDependencyContext: RuntimeDependencyContext? {
        guard !committingAuthenticatedSession, let regionalConfiguration, let api = regionalConfiguration.apiConfiguration,
              let session = currentPlayRuntimeSession, let account else { return nil }
        return RuntimeDependencyContext(market: regionalConfiguration.market, baseURL: api.baseURL,
            role: account.effectiveRole, session: session)
    }
    private var businessRuntimeFactory: BusinessRuntimeFactory? {
        guard let api = regionalConfiguration?.apiConfiguration, storageScope != nil,
              let configuration = runtimeDependencies.businessConfiguration, let context = currentRuntimeDependencyContext,
              configuration.matches(context) else { return nil }
        return BusinessRuntimeFactory(configuration: configuration, api: api,
            transport: runtimeHTTPTransport,
            current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    private var runtimeDependencyFactory: RuntimeDependencyFactory? {
        guard let api = regionalConfiguration?.apiConfiguration, storageScope != nil else { return nil }
        return RuntimeDependencyFactory(api: api, configuration: runtimeDependencies.configuration,
            transport: runtimeHTTPTransport,
            current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    private var currentPlayRuntimeSession: PlayExperienceSession? {
        guard let account, let token, let namespace = storageScope?.service else { return nil }
        return try? PlayExperienceSession(accountID: account.id, epoch: gate.currentStamp, namespace: namespace, token: token)
    }
    private func dormantPlayRuntimeService() -> PlayExperienceService? {
        guard regionalConfiguration?.apiConfiguration != nil, storageScope != nil else { return nil }
        return runtimeDependencyFactory?.playService()
    }
    private func playRuntimeKey(_ scope: PlaySessionScope, suffix: String) -> String {
        "\(storageScope?.service ?? "none"):\(gate.currentStamp):\(account?.id ?? 0):\(account?.effectiveRole ?? "none"):\(scope.fields.keys.sorted().joined()):\(scope.id):\(suffix)"
    }
    func playAdvanced(scope: PlaySessionScope, nodeID: Int, topicID: Int?) -> PlayAdvancedCoordinator? {
        guard scope.isValid, nodeID > 0, let topicID, topicID > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "advanced:\(nodeID)")
        if let retained = retainedPlayAdvanced[key] { return retained }
        let activityID: Int
        switch scope { case .activity(let id): activityID = id; case .topic(let id): guard id == topicID else { return nil }; activityID = 0 }
        let model = PlayAdvancedCoordinator(activityID: activityID, topicID: topicID, nodeID: nodeID, service: api,
            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayAdvanced[key] = model; return model
    }
    func playPreference(scope: PlaySessionScope, nodeID: Int) -> PlayPreferenceCoordinator? {
        guard scope.isValid, nodeID > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "preference:\(nodeID)")
        if let retained = retainedPlayPreferences[key] { return retained }
        let model = PlayPreferenceCoordinator(scope: scope, nodeID: nodeID, service: api,
            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayPreferences[key] = model; return model
    }
    func playOperatingSummary(topicID: Int) -> PlayOperatingSummaryCoordinator? {
        guard topicID > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(.topic(topicID), suffix: "summary")
        if let retained = retainedPlaySummaries[key] { return retained }
        let model = PlayOperatingSummaryCoordinator(topicID: topicID, service: api,
            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlaySummaries[key] = model; return model
    }
    func playDirector(activityID: Int) -> PlayDirectorCoordinator? {
        guard activityID > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(.activity(activityID), suffix: "director")
        if let retained = retainedPlayDirectors[key] { return retained }
        let model = PlayDirectorCoordinator(activityID: activityID, service: api,
            currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayDirectors[key] = model; return model
    }
    func playPrefab(scope: PlaySessionScope) -> PlayPrefabRuntimeCoordinator? {
        guard scope.isValid, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "prefab")
        if let retained = retainedPlayPrefabs[key] { return retained }
        let model = PlayPrefabRuntimeCoordinator(scope: scope, service: api, provider: scopedPlayDeviceProvider(),
            store: prefabRuntimeStore, currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayPrefabs[key] = model; return model
    }
    private var retainedPlayStillness: [String: PlayStillnessCoordinator] = [:]
    func playStillness(scope: PlaySessionScope, nodeID: Int, configuration: PlayStillnessConfiguration) -> PlayStillnessCoordinator? {
        guard scope.isValid, nodeID > 0 else { return nil }
        let key = playRuntimeKey(scope, suffix: "stillness:\(nodeID):\(configuration.durationSeconds):\(configuration.tolerance)")
        if let retained = retainedPlayStillness[key] { return retained }
        let model = PlayStillnessCoordinator(configuration: configuration, provider: makeRuntimeMotionProvider(), currentContext: { [weak self] in
            guard let session = self?.currentPlayRuntimeSession else { return nil }
            return try? PlayDeviceContext(session: session, scope: scope, nodeID: nodeID)
        })
        retainedPlayStillness[key] = model; return model
    }
    // Session-owned dormant hosts. Identity/epoch keys prevent reuse after logout.
    private var retainedPlayPlayers: [String: PlayPlayerGameCoordinator] = [:]
    private var retainedPlayCircles: [String: PlayCircleCoordinator] = [:]
    private var retainedPlayDevices: [String: PlayDeviceCaptureCoordinator] = [:]
    private let unconfiguredPlayNativeDeviceProvider = PlayNativeDeviceProvider(grants: [])
    private var retainedNativePlayDevice: (context: RuntimeDependencyContext, provider: PlayNativeDeviceProvider)?
    var playNativeDeviceProvider: PlayNativeDeviceProvider {
        guard let context = currentRuntimeDependencyContext, let accepted = runtimeDependencyFactory?.accepted else { return unconfiguredPlayNativeDeviceProvider }
        if let retainedNativePlayDevice, retainedNativePlayDevice.context == context { return retainedNativePlayDevice.provider }
        retainedNativePlayDevice?.provider.cancel()
        let provider = PlayNativeDeviceProvider(grants: accepted.devices.intersection([.photo, .scan, .motion]))
        retainedNativePlayDevice = (context, provider); return provider
    }
    private func scopedPlayDeviceProvider() -> any PlayDeviceProviding {
        guard let captured = currentRuntimeDependencyContext, let accepted = runtimeDependencyFactory?.accepted else { return PlayDormantDeviceProvider() }
        return RuntimePlayDeviceProvider(native: playNativeDeviceProvider,
            location: runtimeDependencies.location ?? RuntimeNativeLocationProvider(enabled: accepted.devices.contains(.location)),
            grants: accepted.devices, isCurrent: { [weak self] in self?.currentRuntimeDependencyContext == captured })
    }
    private var retainedNativePlatform: NativePlatformRuntime?
    var nativePlatformRuntime: NativePlatformRuntime? {
        guard let owner = currentPlayRuntimeSession, let api = regionalConfiguration?.apiConfiguration,
              let factory = runtimeDependencyFactory, let accepted = factory.accepted,
              let approval = runtimeDependencies.nativePlatform, approval.validPurpose,
              (approval.stepsEnabled || approval.localRemindersEnabled || approval.enrollment?.enabled == true),
              (approval.enrollment?.requiredPaths ?? []).isSubset(of: accepted.endpoints.paths),
              (approval.enrollment?.enabled != true || approval.enrollment?.isValid == true),
              (!approval.stepsEnabled || accepted.endpoints.paths.contains(NativePlatformService.actionPath)),
              (!approval.localRemindersEnabled || accepted.endpoints.paths.contains(NativePlatformService.windowPath)) else {
            retainedNativePlatform?.invalidate(); retainedNativePlatform = nil; return nil
        }
        if let retainedNativePlatform, retainedNativePlatform.owner == owner { return retainedNativePlatform }
        retainedNativePlatform?.invalidate()
        let current = { [weak self] in self?.currentPlayRuntimeSession }
        let service = NativePlatformService(configuration: api, transport: factory.transport, owner: owner,
            stepsEnabled: approval.stepsEnabled, remindersEnabled: approval.localRemindersEnabled, current: current)
        let enrollment = NativeEnrollmentComposition.make(owner: owner, api: api, transport: factory.transport, approval: approval, current: current)
        guard approval.enrollment?.enabled != true || enrollment != nil else { return nil }
        let runtime = NativePlatformRuntime(owner: owner, acceptance: approval, service: service, current: current,
            makePedometer: { IPhonePedometerProvider(enabled: approval.stepsEnabled) },
            assertion: AppAttestStepAssertionProvider(deviceKeyID: approval.enrolledAppAttestKeyID ?? "", enabled: approval.stepsEnabled),
            reminders: AppleLocalReminderProvider(enabled: approval.localRemindersEnabled),
            enrollment: enrollment)
        retainedNativePlatform = runtime; return runtime
    }
    var playKitArtworkHosts: Set<String> { runtimeDependencyFactory?.accepted?.artworkHosts ?? [] }
    var playKitSpatialApproval: PlayKitSpatialApproval { runtimeDependencyFactory?.accepted?.spatial ?? .init() }
    private var runtimeSensorProviders: [RuntimeSensorReference] = []
    var playKitSensorFactory: (@MainActor () -> any PlayKitSensorProviding)? {
        guard let captured = currentRuntimeDependencyContext, let accepted = runtimeDependencyFactory?.accepted,
              !accepted.sensors.isEmpty else { return nil }
        return { [weak self] in
            guard self?.currentRuntimeDependencyContext == captured else { return PlayKitDormantSensorProvider() }
            let provider = RuntimePlayKitSensorProvider(provider: PlayKitNativeSensorProvider(grants: accepted.sensors),
                isCurrent: { [weak self] in self?.currentRuntimeDependencyContext == captured })
            self?.runtimeSensorProviders.removeAll { $0.value == nil }
            self?.runtimeSensorProviders.append(RuntimeSensorReference(provider))
            return provider
        }
    }
    private func makeRuntimeMotionProvider() -> any PlayMotionSampleProviding {
        guard let captured = currentRuntimeDependencyContext, let accepted = runtimeDependencyFactory?.accepted,
              accepted.sensors.contains(.acceleration) else { return PlayDormantMotionProvider() }
        if let injected = runtimeDependencies.motion { return injected }
        return RuntimeMotionSampleProvider(provider: PlayKitNativeSensorProvider(grants: [.acceleration]),
            isCurrent: { [weak self] in self?.currentRuntimeDependencyContext == captured })
    }
    func playPlayer(scope: PlaySessionScope) -> PlayPlayerGameCoordinator? {
        guard case .activity(let id) = scope, id > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(scope, suffix: "player")
        if let retained = retainedPlayPlayers[key] { return retained }
        let model = PlayPlayerGameCoordinator(activityID: id, service: api, currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayPlayers[key] = model; return model
    }
    func playCircle(topicID: Int?) -> PlayCircleCoordinator? {
        guard let id = topicID, id > 0, let api = dormantPlayRuntimeService() else { return nil }
        let key = playRuntimeKey(.topic(id), suffix: "circle")
        if let retained = retainedPlayCircles[key] { return retained }
        let model = PlayCircleCoordinator(topicID: id, service: api, currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayCircles[key] = model; return model
    }
    func playDevice(scope: PlaySessionScope, nodeID: Int) -> PlayDeviceCaptureCoordinator {
        let key = playRuntimeKey(scope, suffix: "device:\(nodeID)")
        if let retained = retainedPlayDevices[key] { return retained }
        let api = dormantPlayRuntimeService()
        let model = PlayDeviceCaptureCoordinator(provider: scopedPlayDeviceProvider(), filter: PlayNativePhotoFilter.render,
            upload: api?.enabled.contains(.mediaUpload) == true ? { [weak self] bytes, mime, context in
                guard let self, let session = self.currentPlayRuntimeSession,
                      (try? PlayDeviceContext(session: session, scope: scope, nodeID: nodeID)) == context,
                      let api else { throw PlayExperienceError.staleSession }
                return try await api.uploadPhoto(bytes, mimeType: mime, token: session.token)
            } : nil,
            current: { [weak self] in
                guard let session = self?.currentPlayRuntimeSession else { return nil }
                return try? PlayDeviceContext(session: session, scope: scope, nodeID: nodeID)
            })
        retainedPlayDevices[key] = model; return model
    }
    // Native App WeChat host: the adapter is mounted but all provider configuration,
    // SDK opt-in, service transport and live/legal grants remain unconfigured.
    private let weChatSDKDriver = WeChatNativeSDKDriver()
    private let weChatSDKConfiguration: WeChatSDKConfiguration? = nil
    private let weChatSDKGate = WeChatAppAuthGate()
    private lazy var weChatSDKAdapter = WeChatSDKAuthAdapter(driver: weChatSDKDriver,
        configuration: weChatSDKConfiguration, gate: { [weak self] in self?.weChatSDKGate ?? .init() },
        context: { [weak self] in
            self?.weChatContext ?? WeChatAppAuthContext(session: .init(epoch: 0, accountID: nil, isBusy: true), market: nil, namespace: nil)
        })
    private var weChatContext: WeChatAppAuthContext {
        WeChatAppAuthContext(session: AuthChannelSessionSnapshot(epoch: gate.currentStamp,
            accountID: account?.id, isBusy: isWorking || authChannels.state.isWorking),
            market: operationalMarket, namespace: storageScope?.service)
    }
    lazy var weChatAuth = WeChatAppAuthCoordinator(adapter: weChatSDKAdapter, gate: { [weak self] in self?.weChatSDKGate ?? .init() }, context: { [weak self] in
        self?.weChatContext ?? WeChatAppAuthContext(session: .init(epoch: 0, accountID: nil, isBusy: true), market: nil, namespace: nil)
    }, commit: { [weak self] result, expected in
        guard let self, self.weChatContext == expected, expected.permitsLogin else { return false }
        return try self.commitChannelLogin(result, expected: expected.session)
    })
    private let authChannelService: AuthChannelService?
    var authChannelSnapshot: AuthChannelSessionSnapshot {
        AuthChannelSessionSnapshot(epoch:gate.currentStamp,accountID:account?.id,isBusy:isWorking)
    }
    lazy var authChannels=AuthChannelCoordinator(service:authChannelService,currentSession:{ [weak self] in
        self?.authChannelSnapshot ?? AuthChannelSessionSnapshot(epoch:0,accountID:nil,isBusy:true)
    },commitLogin:{ [weak self] result,expected in
        guard let self else { return false }
        return try self.commitChannelLogin(result, expected: expected)
    })
    private func commitChannelLogin(_ result: LoginResult, expected: AuthChannelSessionSnapshot) throws -> Bool {
        guard self.authChannelSnapshot == expected, self.account == nil, !self.isWorking else { return false }
        try self.vault.write(result.token)
        self.gate.invalidate()
        sessionDefaults.set(false,forKey:self.restoreBlockedKey)
        self.commitAuthenticatedSession(token: result.token, account: result.account);self.errorKey=nil
        self.participantCoordinator.synchronizeSession();self.synchronizeRegistration()
        self.clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        self.merchantOnboardingCoordinator.synchronizeSession()
        return true
    }
    // Source-backed production factory, dormant until exact scoped approvals are injected.
    private var retainedOfficialActions: OfficialActionCoordinator?
    var officialActionCoordinator: OfficialActionCoordinator? {
        if let retainedOfficialActions { return retainedOfficialActions }
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = root.appendingPathComponent("OfficialActionSafety", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return nil }
        let access = OfficialActionProductionFactory(api: regionalConfiguration?.apiConfiguration,
            approval: runtimeDependencies.officialActionApproval, transport: runtimeHTTPTransport,
            current: { [weak self] in self?.currentRuntimeDependencyContext }, identity: { [weak self] in
                guard let self, let account = self.account, self.currentOfficialContext.isAuthenticated, let storageScope = self.storageScope else { return nil }
                return OfficialActionIdentity(accountID: account.id, epoch: self.officialEventReader.scope, namespace: storageScope.service)
            })
        let coordinator = OfficialActionCoordinator(access: access, locks: OfficialActionFileLocks(url: directory.appendingPathComponent("locks.json")))
        retainedOfficialActions = coordinator
        return coordinator
    }
    private let officialEventService:OfficialEventService?
    private var currentOfficialContext:OfficialReadContext {
        if let account,let token,
           let context=try? OfficialReadContext(accountID:account.id,epoch:gate.currentStamp,token:token) {
            return context
        }
        return OfficialReadContext(guestEpoch:gate.currentStamp)
    }
    lazy var officialEventReader=OfficialSessionReader(service:officialEventService,currentContext:{ [weak self] in
        self?.currentOfficialContext ?? OfficialReadContext(guestEpoch:0)
    },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentOfficialContext == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private let growthCenterService:GrowthCenterService?
    private var currentGrowthCenterSession:GrowthCenterReadSession? {
        guard let account,let token else { return nil }
        return try? GrowthCenterReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var growthCenterReader=GrowthCenterSessionReader(service:growthCenterService,currentSession:{ [weak self] in self?.currentGrowthCenterSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentGrowthCenterSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private var retainedProjectEditors: [String: ProjectEditCoordinator] = [:]
    private lazy var projectDraftStore = ProjectEditLocalStore(storage: ProjectEditSecureStorage(scope: storageScope))
    private var currentProjectEditSession: ProjectEditSession? {
        guard let account, token != nil, let storageScope else { return nil }
        return try? ProjectEditSession(accountID: account.id, epoch: gate.currentStamp, storageNamespace: storageScope.service)
    }
    var projectEditorIsConfigured: Bool { businessRuntimeFactory?.permits(.projectRead) == true }
    func projectEditor(product: ProjectEditProduct, owner: ProjectEditOwner = .personal) -> ProjectEditCoordinator {
        let key = "\(gate.currentStamp):\(account?.id ?? 0):\(account?.effectiveRole ?? "guest"):\(product.rawValue):\(owner.rawValue)"
        if let retained = retainedProjectEditors[key] { return retained }
        let service: any ProjectEditServing
        if let factory = businessRuntimeFactory, factory.permits(.projectRead), let configuration = regionalConfiguration?.apiConfiguration {
            let captured = factory.captured
            service = ProjectEditHTTPService(configuration: configuration, transport: factory.client([.projectRead, .projectWrite]),
                owner: owner, approval: factory.approval([.projectWrite]), store: projectDraftStore,
                currentCredentials: { [weak self] in
                    guard let self, self.currentRuntimeDependencyContext == captured,
                          let session = self.currentProjectEditSession, let token = self.token else { return nil }
                    return try? ProjectEditCredentials(session: session, token: token)
                })
        } else { service = ProjectEditDisabledService() }
        var draft = ProjectEditDraft(product: product); draft.owner = owner
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: projectDraftStore,
            currentSession: { [weak self] in self?.currentProjectEditSession })
        retainedProjectEditors[key] = coordinator
        return coordinator
    }
    private var publishingEpochCache: (stamp: UInt64, accountID: Int, role: String, epoch: UUID)?
    var publishingSession: PublishingSession? {
        guard let account, token != nil, let storageScope, let market = operationalMarket else { return nil }
        let role = account.effectiveRole
        if publishingEpochCache?.stamp != gate.currentStamp || publishingEpochCache?.accountID != account.id || publishingEpochCache?.role != role {
            publishingEpochCache = (gate.currentStamp, account.id, role, UUID())
        }
        guard let epoch = publishingEpochCache?.epoch else { return nil }
        return PublishingSession(namespace: storageScope.service, accountID: account.id, epoch: epoch, role: role,
                                 region: market == .china ? .china : .unitedStates)
    }
    private var retainedPublisherLifecycle: (session: PublishingSession, context: PublisherLifecycleHostContext)?
    var publisherLifecycleContext: PublisherLifecycleHostContext? {
        guard let publishingSession, let configuration = regionalConfiguration?.apiConfiguration else {
            retainedPublisherLifecycle?.context.invalidate(); retainedPublisherLifecycle = nil; return nil
        }
        if let retainedPublisherLifecycle, retainedPublisherLifecycle.session == publishingSession { return retainedPublisherLifecycle.context }
        retainedPublisherLifecycle?.context.invalidate()
        guard let factory = runtimeDependencyFactory else { return nil }
        let context = PublisherLifecycleHostContext(configuration: configuration, transport: factory.transport, creatorReader: creatorContentReader,
            grants: factory.publisherGrants,
            credentials: { [weak self] in
                guard let self, let session = self.publishingSession, let token = self.token else { return nil }
                return try? PublishingCredentials(session: session, token: token)
            }, freshAuthority: { [weak self] resource, captured in
                guard let self else { throw PublisherLifecycleError.unavailable }
                return try await self.freshPublisherAuthority(resource, session: captured)
            })
        retainedPublisherLifecycle = (publishingSession, context); return context
    }
    func freshPublisherAuthority(_ resource: PublishedResource, session captured: PublishingSession) async throws -> PublisherAuthority {
        let reader = PublisherSourceAuthorityReader(topics: topicReader, clubs: self,
            activityDetail: { [weak self] id in
                guard let self else { throw PublisherLifecycleError.unavailable }; return try await self.activityDetail(id: id)
            }, currentSession: { [weak self] in self?.publishingSession })
        return try await reader.freshAuthority(resource, session: captured)
    }
    private var retainedPublishingService: (context: RuntimeDependencyContext, service: PublishingService)?
    var publishingService: PublishingService? {
        guard let factory = businessRuntimeFactory, factory.permits(.publishingRead),
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        if let retainedPublishingService, retainedPublishingService.context == factory.captured { return retainedPublishingService.service }
        retainedPublishingService?.service.invalidateReviews()
        let captured = factory.captured
        let service = PublishingService(configuration: configuration, transport: factory.client([.publishingRead, .publishingWrite]),
            approval: factory.approval([.publishingWrite]), journal: composition.storage.operationJournal(),
            credentials: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured, let session = self.publishingSession,
                      let token = self.token else { return nil }
                return try? PublishingCredentials(session: session, token: token)
            })
        retainedPublishingService = (captured, service); return service
    }
    /// Separate provider-grant feature; publishing read/write grants never enable AI.
    func makePublishingAuxiliaryService(feature: BusinessRuntimeFeature) -> PublishingAuxiliaryService? {
        guard let factory = businessRuntimeFactory else { return nil }
        let captured = factory.captured
        return factory.publishingAuxiliary(feature: feature, journal: composition.storage.operationJournal(), credentials: { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured,
                  let session = self.publishingSession, let token = self.token else { return nil }
            return try? PublishingCredentials(session: session, token: token)
        })
    }
    var publishingAIDraftFactory: (() -> any PublishingAIDraftServing)? {
        guard let factory = businessRuntimeFactory, factory.permits(.publishingAIQuota), factory.permits(.publishingAITheme),
              let configuration = regionalConfiguration?.apiConfiguration,
              let assistance = makePublishingAuxiliaryService(feature: .publishingAITheme) else { return nil }
        let captured = factory.captured
        let quotaTransport = PublishingAIRuntimeTransport(feature: .publishingAIQuota, baseURL: configuration.baseURL, transport: factory.client([.publishingAIQuota]))
        let reads = PublishingService(configuration: configuration, transport: quotaTransport, credentials: { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured,
                  let session = self.publishingSession, let token = self.token else { return nil }
            return try? PublishingCredentials(session: session, token: token)
        })
        let client = PublishingAIDraftClient(reads: reads, assistance: assistance)
        return { client }
    }
    lazy var publishingDraftStore = PublishingDraftStore(storage: ProjectEditSecureStorage(scope: storageScope))
    /// Production mounts no read grant or write approval. An approved integration may inject
    /// a read transport; the returned service still has no mutation approval or journal.
    func makePublishingService(readApproval: OperationEndpointApproval? = nil,
                               transport: (any HTTPTransport)? = nil) -> PublishingService? {
        let transport = scopedTransport(transport)
        guard let configuration = regionalConfiguration?.apiConfiguration, let readApproval,
              let scope = storageScope, readApproval.baseURL == configuration.baseURL,
              readApproval.namespace == scope.service else { return nil }
        let guarded = PublishingApprovedReadTransport(configuration: configuration, approval: readApproval,
                                                      transport: transport, currentCredentials: { [weak self] in
                guard let self, let session = self.publishingSession, let token = self.token else { return nil }
                return try? PublishingCredentials(session: session, token: token)
            })
        return PublishingService(configuration: configuration, transport: guarded, credentials: { [weak self] in
            guard let self, let session = self.publishingSession, let token = self.token else { return nil }
            return try? PublishingCredentials(session: session, token: token)
        })
    }
    private let nativeWeChatPaymentDriver = WeChatNativePaymentDriver()
    private lazy var nativeWeChatPaymentAdapter = WeChatSDKPaymentAdapter(driver: nativeWeChatPaymentDriver,
        configuration: runtimeDependencies.weChatPaymentConfiguration,
        allowed: { [weak self] in
            guard let self else { return false }
            if let auth = self.weChatSDKConfiguration, let payment = self.runtimeDependencies.weChatPaymentConfiguration,
               auth.appID != payment.sdk.appID || auth.universalLink != payment.sdk.universalLink { return false }
            let selfPlayAllowed = self.businessRuntimeFactory.map {
                $0.configuration.selfPlayExternalCheckoutApproved && $0.configuration.selfPlayPayment && $0.permits(.topicSelfPlayPay)
            } ?? false
            return selfPlayAllowed || self.orderLifecyclePaymentProviderAllowed
        }, context: { [weak self] in self?.currentRuntimeDependencyContext })
    private let selfPlayOperationGate = TopicSelfPlayOperationGate()
    private var retainedSelfPlayFlows: [String: TopicSelfPlayFlow] = [:]
    func topicSelfPlayFlow(topic: TopicDetail) -> TopicSelfPlayFlow? {
        guard let factory = businessRuntimeFactory, let configuration = regionalConfiguration?.apiConfiguration,
              factory.configuration.selfPlayExternalCheckoutApproved, factory.permits(.topicSelfPlayRead), factory.permits(.topicSelfPlayCreate),
              factory.permits(.topicSelfPlayConsentRead), factory.permits(.topicSelfPlayConsentWrite),
              let document = runtimeDependencies.signupDocument, let directory = safetyDirectory("TopicSelfPlayConsent"),
              let session = publishingSession, ["player", "club"].contains(session.role), topic.selfPlay == 1 else { return nil }
        let captured = factory.captured
        let key = "\(session.storageKey)|\(session.epoch)|\(topic.id)"
        if let retained = retainedSelfPlayFlows[key] { return retained }
        let features: Set<BusinessRuntimeFeature> = [.topicSelfPlayRead, .topicSelfPlayCreate, .topicSelfPlayPay, .topicSelfPlayConsentRead, .topicSelfPlayConsentWrite]
        let transport = TopicSelfPlayRuntimeTransport(baseURL: configuration.baseURL, transport: factory.client(features))
        let compliance = AccountComplianceService(configuration: configuration, transport: transport,
            journal: ComplianceFileJournal(url: directory.appendingPathComponent("operations-v1.json")),
            current: { [weak self] in self?.currentRuntimeDependencyContext == captured ? self?.complianceSession : nil },
            token: { [weak self] in self?.currentRuntimeDependencyContext == captured ? self?.token : nil },
            readsEnabled: true, writesEnabled: true,
            legalApproved: { [weak self] subject, scope in subject == .signup && self?.currentRuntimeDependencyContext == captured && self?.complianceSession == scope })
        let client = TopicSelfPlayHTTPClient(configuration: configuration, transport: transport, consent: compliance,
            complianceSession: { [weak self] in self?.complianceSession }, documentProvider: document, captured: captured,
            current: { [weak self] in self?.currentRuntimeDependencyContext }, credentials: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured, let session = self.publishingSession, let token = self.token else { return nil }
                return try? PublishingCredentials(session: session, token: token)
            })
        let payment: (any TopicSelfPlayPaymentProviding)? = factory.configuration.selfPlayPayment && factory.permits(.topicSelfPlayPay)
            ? (runtimeDependencies.selfPlayPayment ?? nativeWeChatPaymentAdapter) : nil
        let flow = TopicSelfPlayFlow(topic: topic, client: client, provider: payment, journal: TopicSelfPlayDefaultsJournal(defaults: .standard), operationGate: selfPlayOperationGate)
        retainedSelfPlayFlows[key] = flow; return flow
    }
    var couponManagementSession: CouponManagementSession? {
        guard let account, token != nil, let storageScope else { return nil }
        return try? CouponManagementSession(accountID: account.id, namespace: storageScope.service,
                                             epoch: gate.currentStamp, authorizationRevision: account.effectiveRole)
    }
    private lazy var couponManagementLocks = CouponManagementAppLocks()
    /// Source permissions and endpoint approval are separate. No live read/write grant is installed.
    lazy var couponManagementCoordinator = makeCouponManagementCoordinator()
    func makeCouponManagementCoordinator(readApproval: OperationEndpointApproval? = nil,
                                         transport: (any HTTPTransport)? = nil,
                                         publisher: (any CouponPublisherAuthorizing)? = nil) -> CouponManagementCoordinator {
        let transport = scopedTransport(transport)
        var reader: (any CouponManagementTransport)?
        if let configuration = regionalConfiguration?.apiConfiguration, let readApproval,
           let storageScope, readApproval.baseURL == configuration.baseURL, readApproval.namespace == storageScope.service {
            let guarded = CouponManagementApprovedReadTransport(configuration: configuration, approval: readApproval,
                transport: transport, currentSession: { [weak self] in self?.couponManagementSession })
            reader = CouponManagementHTTPReadTransport(configuration: configuration, http: guarded, credentials: { [weak self] in
                guard let self, let session = self.couponManagementSession, let token = self.token else { return nil }
                return try? CouponManagementReadCredentials(session: session, token: token)
            })
        }
        return CouponManagementCoordinator(adapter: .init(transport: reader),
            authorizer: publisher ?? CouponPublisherUnavailable(), locks: couponManagementLocks,
            currentSession: { [weak self] in self?.couponManagementSession })
    }
    // Source-backed media composition remains dormant: hardware, upload origins and write grants are empty.
    private var roamMediaScope: RetainedImageScope? {
        guard let wallet = walletCommerceScope, let credentials = currentRetainedImageCredentials else { return nil }
        return try? RetainedImageScope(accountID: wallet.accountID, epoch: wallet.epoch,
            realm: credentials.realm, destination: .stamp, namespace: wallet.namespace)
    }
    var stampCameraEnabled: Bool { businessRuntimeFactory?.configuration.stampCamera == true }
    func makeRoamStampCaptureCoordinator() -> RoamStampCaptureCoordinator? {
        guard let factory = businessRuntimeFactory, let scope = roamMediaScope, let configuration = regionalConfiguration?.apiConfiguration,
              let credentials = currentRetainedImageCredentials else { return nil }
        let current: () -> RetainedImageScope? = { [weak self] in
            guard let self, self.currentRetainedImageCredentials == credentials else { return nil }; return self.roamMediaScope
        }
        let token: () -> String? = { [weak self] in self?.currentRetainedImageCredentials == credentials ? credentials.token : nil }
        let uploader = RetainedImageHTTPUploader(configuration: configuration, transport: factory.client([.stampUpload]),
            enabled: factory.permits(.stampUpload), approvedOrigins: factory.configuration.stampImageOrigins, currentScope: current, token: token)
        let executor = RoamMediaMutationService(configuration: configuration, transport: factory.client([.stampCreate]),
            enabled: factory.permits(.stampCreate), approval: factory.approval([.stampCreate]),
            approvedImageOrigins: factory.configuration.stampImageOrigins, currentScope: current, token: token)
        let storage = StoredRoamStampPending(read: { [unowned self] in try self.imageUploadStorage.read($0) },
            write: { [unowned self] in try self.imageUploadStorage.write($0, key: $1) })
        return RoamStampCaptureCoordinator(scope: scope,
            uploads: RetainedImageUploadCoordinator(uploader: uploader, journal: imageUploadJournal), executor: executor, storage: storage)
    }
    func makeRoamPosterCoordinator(node: RoamNodeDetail) -> RoamPosterCoordinator? {
        guard let mediaScope = roamMediaScope, let configuration = regionalConfiguration?.apiConfiguration,
              let credentials = currentRetainedImageCredentials,
              let scope = try? RetainedImageScope(accountID: mediaScope.accountID, epoch: mediaScope.epoch,
                realm: mediaScope.realm, destination: .roamPoster(poiID: node.poiId), namespace: mediaScope.namespace) else { return nil }
        let executor = RoamMediaMutationService(configuration: configuration, transport: runtimeHTTPTransport,
            enabled: false, approval: nil, currentScope: { [weak self] in
                guard let self, self.currentRetainedImageCredentials == credentials, self.roamMediaScope == mediaScope else { return nil }; return scope
            }, token: { [weak self] in self?.currentRetainedImageCredentials == credentials ? credentials.token : nil })
        return RoamPosterCoordinator(scope: scope, poiID: node.poiId, node: { node }, location: DisabledRoamPosterLocation(),
            executor: executor, journal: composition.storage.operationJournal(), refreshNode: { [weak self] in
                guard let self else { throw APIError.unauthorized }; return try await self.roamReader.roamNodeDetail(id: node.poiId)
            })
    }
    func makeBankWithdrawalContext() -> BankWithdrawalRuntimeContext? {
        guard let factory = businessRuntimeFactory, factory.permits(.bankPrepare), factory.permits(.bankConsentRead),
              let provider = runtimeDependencies.bankDocument, let scope = walletCommerceScope,
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let captured = factory.captured
        let routes = BankWithdrawalRuntimeRoutes(factory: factory)
        let consent = BankWithdrawalConsentReader(configuration: configuration, transport: factory.client([.bankConsentRead]),
            provider: provider, captured: captured, scope: scope, current: { [weak self] in self?.currentRuntimeDependencyContext })
        let adapter = BankWithdrawalAdapter(configuration: configuration,
            transport: factory.client([.bankPrepare, .bankCreate], additionalRoutes: { routes.dynamicRoutes }),
            journal: composition.storage.operationJournal(), enableReviewedWrites: true,
            approvalForPath: { routes.approval(path: $0) }, refreshConsent: { try await consent.refresh() },
            validatedChallenge: { routes.validatedChallenge($0) }, consentEvidence: { consent.evidence },
            currentSession: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured, self.walletCommerceScope == scope,
                      let token = self.token else { return nil }
                return BankWithdrawalSession(scope: scope, token: token)
            })
        return BankWithdrawalRuntimeContext(adapter: adapter, consent: consent)
    }
    private var walletEpochCache: (stamp: UInt64, accountID: Int, epoch: UUID)?
    var walletCommerceScope: WalletCommerceScope? {
        guard let account, token != nil, let storageScope else { return nil }
        if walletEpochCache?.stamp != gate.currentStamp || walletEpochCache?.accountID != account.id {
            walletEpochCache = (gate.currentStamp, account.id, UUID())
        }
        guard let epoch = walletEpochCache?.epoch else { return nil }
        return WalletCommerceScope(namespace: storageScope.service, accountID: account.id, epoch: epoch)
    }
    /// No production read grant or mutation adapter is installed. iOS redemption stays dormant.
    lazy var walletCommerceReader = makeWalletCommerceReader()
    /// Public contact approval/transport is not supplied by current deployment composition.
    /// Does not grant wallet reads or any financial command.
    lazy var withdrawalSupportReader = makeWithdrawalSupportReader()
    func makeWithdrawalSupportReader(source: WithdrawalSupportReader.Source? = nil,
                                     approval: @escaping () -> WithdrawalSupportApproval? = { nil }) -> WithdrawalSupportReader {
        WithdrawalSupportReader(source: source, approval: approval, session: { [weak self] in self?.walletCommerceScope })
    }
    func makeWalletCommerceReader(readApproval: OperationEndpointApproval? = nil,
                                  transport: (any HTTPTransport)? = nil) -> WalletCommerceReader {
        let transport = scopedTransport(transport)
        var service: WalletCommerceService?
        if let configuration = regionalConfiguration?.apiConfiguration, let readApproval,
           let storageScope, readApproval.baseURL == configuration.baseURL,
           readApproval.namespace == storageScope.service {
            let guarded = WalletCommerceApprovedReadTransport(configuration: configuration, approval: readApproval,
                transport: transport, currentSession: { [weak self] in
                    guard let self, let scope = self.walletCommerceScope, let token = self.token else { return nil }
                    return (scope, token)
                })
            service = WalletCommerceService(configuration: configuration, transport: guarded)
        }
        return WalletCommerceReader(service: service, onUnauthorized: { [weak self] captured in
            guard let self, self.walletCommerceScope == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: self.gate.currentStamp, credential: self.token)
        }, session: { [weak self] in
            guard let self, let scope = self.walletCommerceScope, let token = self.token else { return nil }
            return (scope, token)
        })
    }
    private var retainedTemplateAuthors: [Int: TemplateAuthoringCoordinator] = [:]
    private lazy var templateAuthoringSecureStorage = TemplateAuthoringSecureStorage(scope: storageScope)
    private lazy var templateAuthoringDraftStore = TemplateAuthoringLocalStore(storage: templateAuthoringSecureStorage)
    lazy var prefabPreviewStore = PrefabPreviewStore(storage: templateAuthoringSecureStorage)
    var currentTemplateAuthoringSession: TemplateAuthoringSession? {
        guard let account, token != nil, let storageScope else { return nil }
        return try? TemplateAuthoringSession(accountID: account.id, namespace: storageScope.service,
                                             epoch: gate.currentStamp, authorizationRevision: account.effectiveRole)
    }
    var templateAuthoringViewIdentity: String {
        currentTemplateAuthoringSession.map { $0.ownerKey + ":\($0.epoch):" + $0.authorizationRevision } ?? "signed-out"
    }
    func templateAuthoringEditor(adopting source: DiscoveryPlayTemplate? = nil) -> TemplateAuthoringCoordinator {
        let key = source?.id ?? 0
        let coordinator: TemplateAuthoringCoordinator
        if let retained = retainedTemplateAuthors[key] { coordinator = retained }
        else {
            // Production stays hard-off; exact wire adapters are authored but not mounted.
            coordinator = TemplateAuthoringCoordinator(adapter: TemplateAuthoringAdapter(), store: templateAuthoringDraftStore,
                                                       currentSession: { [weak self] in self?.currentTemplateAuthoringSession })
            retainedTemplateAuthors[key] = coordinator
        }
        coordinator.open(seed: source.flatMap { try? TemplateAuthoringDraft.adopt($0) })
        return coordinator
    }
    private let creatorContentService:CreatorContentService?
    private var currentCreatorContentSession:CreatorContentReadSession? {
        guard let account,let token else { return nil }
        return try? CreatorContentReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var creatorContentReader=CreatorContentSessionReader(service:creatorContentService,currentSession:{ [weak self] in self?.currentCreatorContentSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentCreatorContentSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    // No API/media approval is inferred from the account route.
    private var currentObjectCardSession: ObjectCardSession? {
        guard let account, let token else { return nil }
        return try? ObjectCardSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var objectCardReader = makeObjectCardReader()
    func makeObjectCardReader() -> ObjectCardSessionReader {
        ObjectCardSessionReader(serviceProvider: { [weak self] in
            guard let self else { return nil }
            return SocialReaderProductionFactory(configuration: self.regionalConfiguration?.apiConfiguration,
                approval: self.runtimeDependencies.socialReaderApproval, apiTransport: self.runtimeHTTPTransport,
                current: { [weak self] in self?.currentRuntimeDependencyContext }).objectCards()
        }, currentSession: { [weak self] in self?.currentObjectCardSession },
        currentContext: { [weak self] in self?.currentRuntimeDependencyContext },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentObjectCardSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    }
    private var currentCouponCodeSession: CouponCodeSession? {
        guard let account, let token, let namespace = storageScope?.service else { return nil }
        return try? CouponCodeSession(accountID: account.id, epoch: gate.currentStamp, namespace: namespace, role: account.effectiveRole, token: token)
    }
    func makeCouponCodeCoordinator(historyID: Int) -> CouponCodeCoordinator {
        CouponCodeCoordinator(historyID: historyID,
            service: CouponCodeApprovedService(configuration: regionalConfiguration?.apiConfiguration,
                approval: runtimeDependencies.couponCodeApproval, transport: runtimeHTTPTransport,
                current: { [weak self] in self?.currentRuntimeDependencyContext }),
            currentSession: { [weak self] in self?.currentCouponCodeSession },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentCouponCodeSession == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
    }
    // No live source/deployment approval exists yet. Keep the reward read capability nil.
    private let nonCashRewardService: NonCashRewardService? = nil
    private var currentNonCashRewardSession: NonCashRewardReadSession? {
        guard let account, let token else { return nil }
        return try? NonCashRewardReadSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var nonCashRewardReader = NonCashRewardSessionReader(service: nonCashRewardService,
        currentSession: { [weak self] in self?.currentNonCashRewardSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentNonCashRewardSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    private let accountCollectionService:AccountCollectionService?
    private var currentAccountCollectionSession:AccountCollectionReadSession? {
        guard let account,let token else { return nil }
        return try? AccountCollectionReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var accountCollectionReader=AccountCollectionSessionReader(service:accountCollectionService,currentSession:{ [weak self] in self?.currentAccountCollectionSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentAccountCollectionSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private let cooperationService:CooperationService?
    private var currentCooperationSession:CooperationReadSession? {
        guard let account,let token else { return nil }
        return try? CooperationReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var cooperationReader=CooperationSessionReader(service:cooperationService,currentSession:{ [weak self] in self?.currentCooperationSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentCooperationSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private let socialAccountService: SocialAccountService?
    private var currentSocialAccountSession: SocialAccountSession {
        if let account, let token, let snapshot = try? SocialAccountSession(accountID: account.id, epoch: gate.currentStamp, role: account.effectiveRole, token: token) { return snapshot }
        return SocialAccountSession(guestEpoch: gate.currentStamp)
    }
    lazy var socialAccountReader = SocialAccountSessionReader(service: socialAccountService, currentSession: { [weak self] in
        self?.currentSocialAccountSession ?? SocialAccountSession(guestEpoch: 0)
    }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentSocialAccountSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.identity.epoch, credential: self.token)
    })
    // Only exact member-action grants can authorize this path; Square writes stay separate.
    private var socialMemberActionJournal: any OperationPendingJournal { composition.storage.operationJournal() }
    private var retainedSocialMemberActions: SocialMemberActionSessionOwner?
    private var socialMemberActions: SocialMemberActionSessionOwner {
        if let retainedSocialMemberActions { return retainedSocialMemberActions }
        let owner = SocialMemberActionSessionOwner(configuration: regionalConfiguration?.apiConfiguration,
            transport: runtimeHTTPTransport, journal: socialMemberActionJournal,
            current: { [weak self] in self?.currentRuntimeDependencyContext },
            currentIdentity: { [weak self] in self?.currentSocialAccountSession.identity ?? .init(accountID: nil, epoch: 0) },
            approvals: { [weak self] context in
                guard let self, self.currentRuntimeDependencyContext == context else { return [] }
                return self.runtimeDependencies.socialMemberActionApprovals
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
        retainedSocialMemberActions = owner
        return owner
    }
    var socialActionAccess: any SocialActionAccess { socialMemberActions.access }
    var socialActionCoordinator: SocialActionCoordinator { socialMemberActions.coordinator }
    // Explicit media-origin approval and bounded streaming are required before live preview reads.
    lazy var socialMessageMediaReader = makeSocialMessageMediaReader()
    func makeSocialMessageMediaReader() -> SocialMessageMediaReader {
        SocialMessageMediaReader(serviceProvider: { [weak self] in
            guard let self else { return nil }
            return SocialReaderProductionFactory(configuration: self.regionalConfiguration?.apiConfiguration,
                approval: self.runtimeDependencies.socialReaderApproval,
                apiTransport: self.runtimeHTTPTransport, mediaTransport: self.runtimeHTTPTransport,
                current: { [weak self] in self?.currentRuntimeDependencyContext }).messageMedia()
        }, currentIdentity: { [weak self] in self?.messagingReader.identity },
        currentContext: { [weak self] in self?.currentRuntimeDependencyContext }, onUnauthorized: { [weak self] captured in
            guard let self, self.messagingReader.identity == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    }
    // Square workspace and governance stay distinct from Club and legacy SocialAction.
    private var currentSquareWorkspaceSession: SquareWorkspaceSession? {
        guard let account, token != nil, let storageScope else { return nil }
        return try? SquareWorkspaceSession(accountID: account.id, namespace: storageScope.service, epoch: gate.currentStamp)
    }
    private lazy var squareWorkspaceStore = SquareWorkspaceStore(storage: SquareWorkspaceSecureStorage(scope: storageScope))
    private var retainedSquareWorkspace: SquareWorkspaceCoordinator?
    func squareWorkspace() -> SquareWorkspaceCoordinator? {
        guard let identity = currentSquareWorkspaceSession else { retainedSquareWorkspace = nil; return nil }
        if let model = retainedSquareWorkspace, model.session == identity { return model }
        let model = SquareWorkspaceCoordinator(session: identity, store: squareWorkspaceStore,
            currentSession: { [weak self] in self?.currentSquareWorkspaceSession },
            token: { [weak self] in
                guard let self, self.currentSquareWorkspaceSession == identity else { return nil }
                return self.token
            }) // service nil, live/media/legal grants all off.
        retainedSquareWorkspace = model; return model
    }
    private var currentSquareGovernanceIdentity: SquareGovernanceIdentity? {
        guard let account, token != nil, let storageScope else { return nil }
        return .init(accountID: account.id, epoch: gate.currentStamp, namespace: storageScope.service)
    }
    private var retainedSquareReports: SquareReportCoordinator?
    private var retainedSquareReportBaseURL: URL?
    func squareReportContext() -> SquareReportContext? {
        guard let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        if retainedSquareReports == nil || retainedSquareReportBaseURL != configuration.baseURL {
            retainedSquareReports = SquareReportCoordinator(service: .init(configuration: configuration, transport: runtimeHTTPTransport))
            retainedSquareReportBaseURL = configuration.baseURL
        }
        guard let coordinator = retainedSquareReports else { return nil }
        let captured = currentSquareGovernanceIdentity
        let access = SquareReportSessionAccess(identity: { [weak self] in self?.currentSquareGovernanceIdentity },
            token: { [weak self] in
                guard let self, self.currentSquareGovernanceIdentity == captured else { return nil }; return self.token
            }, subject: { [weak self] target in
                guard let self, let captured, self.currentSquareGovernanceIdentity == captured else { throw SquareReportFailure.signedOut }
                let value = try await self.socialActionAccess.snapshot(target: target, generation: .communityV1)
                guard self.currentSquareGovernanceIdentity == captured else { throw CancellationError() }; return value
            })
        return .init(coordinator: coordinator, access: access) // Default policy reads and report writes remain OFF.
    }
    private var retainedSquareGovernance: SquareGovernanceCoordinator?
    func squareGovernance() -> SquareGovernanceCoordinator? {
        if let model = retainedSquareGovernance { return model }
        guard let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let model = SquareGovernanceCoordinator(service: .init(baseURL: configuration.baseURL, transport: runtimeHTTPTransport))
        retainedSquareGovernance = model; return model // reads and every operation grant off.
    }
    func squareGovernanceAccess(postID: Int? = nil) -> SquareGovernanceSessionAccess {
        let captured = currentSquareGovernanceIdentity
        return SquareGovernanceSessionAccess(identity: { [weak self] in self?.currentSquareGovernanceIdentity },
            token: { [weak self] in
                guard let self, self.currentSquareGovernanceIdentity == captured else { return nil }
                return self.token
            }, freshComments: { [weak self] in
                guard let self, let captured, self.currentSquareGovernanceIdentity == captured else { throw SquareGovernanceFailure.signedOut }
                guard let postID, postID > 0 else { return [] }
                // Fresh exact-post author + fresh comments, never cached UI or an inferred moderator role.
                let readScope = self.squareReader.scope
                let post = try await self.squareReader.squareDetail(route: .init(id: postID, generation: .communityV1))
                guard self.currentSquareGovernanceIdentity == captured, self.squareReader.scope == readScope, post.id == postID else { throw CancellationError() }
                let page = try await self.squareReader.squareComments(route: .init(id: postID, generation: .communityV1), pageNumber: 1)
                guard self.currentSquareGovernanceIdentity == captured, self.squareReader.scope == readScope else { throw CancellationError() }
                return page.items.map { SquareGovernanceComment(comment: $0, post: post) }
            })
    }
    private let squareService:SquareService?
    private var currentSquareSession:SquareReadSession? {
        guard let account,let token else { return nil }
        return try? SquareReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var squareReader=SquareSessionReader(service:squareService,currentSession:{ [weak self] in self?.currentSquareSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentSquareSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    // Team transport remains unconfigured until this module's read deployment is verified.
    // Source write adapters exist, but no production write approval is supplied here.
    private let teamService = TeamReadOnlyService()
    private lazy var teamJournal = TeamDefaultsJournal(defaults: .standard)
    private var currentTeamSession: TeamSession? {
        guard let account, let token, let storageScope, let market = operationalMarket else { return nil }
        return try? TeamSession(account: account, epoch: gate.currentStamp, region: market.rawValue,
                                storageNamespace: storageScope.service, token: token)
    }
    var teamViewIdentity: String {
        "\(gate.currentStamp):\(account?.id ?? 0):\(account?.effectiveRole ?? "guest"):\(operationalMarket?.rawValue ?? "unconfigured")"
    }
    var nearbyTeamSession: NearbyTeamSession? { currentTeamSession.map { NearbyTeamSession(teamSession: $0) } }
    var nearbyTeamQueryContext: NearbyQueryContext? {
        guard let area = roamArea else { return nil }
        return NearbyTeamBridge.roamQuery(latitude: area.coordinate.latitude, longitude: area.coordinate.longitude)
    }
    lazy var nearbyTeamCoordinator = makeNearbyTeamCoordinator()
    func makeNearbyTeamCoordinator(readApproval: OperationEndpointApproval? = nil,
                                   writeApproval: OperationEndpointApproval? = nil,
                                   writeEvidence: ((NearbyTeamReview) async throws -> NearbyTeamWriteEvidence)? = nil,
                                   transport: (any HTTPTransport)? = nil) -> NearbyTeamCoordinator {
        let transport = scopedTransport(transport)
        // No default caller supplies an operation grant or evidence loader; writes remain off.
        let writer: NearbyTeamHTTPWriteAdapter?
        if let writeApproval, let writeEvidence, let configuration = regionalConfiguration?.apiConfiguration {
            writer = NearbyTeamHTTPWriteAdapter(configuration: configuration, transport: transport, approval: writeApproval,
                journal: NearbyTeamDefaultsDispatchJournal(defaults: .standard),
                currentSession: { [weak self] in self?.nearbyTeamSession },
                token: { [weak self] captured in guard let self, self.nearbyTeamSession == captured else { return nil }; return self.token },
                freshEvidence: writeEvidence)
        } else { writer = nil }
        let service: NearbyTeamService
        if let readApproval, let configuration = regionalConfiguration?.apiConfiguration {
            let reader = NearbyTeamHTTPReadTransport(configuration: configuration, transport: transport, approval: readApproval,
                currentSession: { [weak self] in self?.nearbyTeamSession },
                token: { [weak self] captured in guard let self, self.nearbyTeamSession == captured else { return nil }; return self.token })
            service = NearbyTeamService(readTransport: reader, liveReadGrant: true, writeAdapter: writer)
        } else { service = NearbyTeamService(writeAdapter: writer) }
        return NearbyTeamCoordinator(service: service, session: nearbyTeamSession)
    }
    func makeTeamCoordinator(readApproval: OperationEndpointApproval? = nil,
                             creationSource: OrderLifecycleTeamSource? = nil) -> TeamCoordinator {
        // Default callers provide neither deployment approval nor a registration source.
        // An approved read factory is reusable without silently enabling any write endpoint.
        let reader: TeamReadOnlyService
        if let readApproval, let configuration = regionalConfiguration?.apiConfiguration {
            reader = TeamReadOnlyService(configuration: configuration, transport: runtimeHTTPTransport,
                readApproval: readApproval, currentSession: { [weak self] in self?.currentTeamSession },
                creationLoader: { [weak self] ownerID, session in
                    guard let self, self.currentTeamSession == session, let token = self.token,
                          let creationSource, creationSource.context.ownerID == ownerID,
                          readApproval.allows(configuration: configuration, namespace: session.storageNamespace,
                              accountID: session.accountID, path: "api/registration/info"),
                          let service = self.orderLifecycleService else { throw TeamFailure.notConfigured }
                    let detail = try await service.detail(id: creationSource.registrationID, token: token)
                    guard !Task.isCancelled, self.currentTeamSession == session,
                          let source = detail.teamCreationSource, source.registrationID == creationSource.registrationID,
                          source.context.ownerID == ownerID else { throw TeamFailure.stale }
                    return source.context
                })
        } else { reader = teamService }
        return TeamCoordinator(service: reader, journal: teamJournal,
            currentSession: { [weak self] in self?.currentTeamSession },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentTeamSession == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
            })
    }
    private let orderLifecycleService: OrderLifecycleService?
    private var currentOrderLifecycleSession: OrderLifecycleSession? {
        guard let account, let token else { return nil }
        let contextID = currentRuntimeDependencyContext.map {
            [$0.market.rawValue, $0.baseURL.absoluteString, $0.session.namespace, $0.role].map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        } ?? account.effectiveRole
        let replayContext = currentRuntimeDependencyContext.map { OrderLifecycleReplayContext(context: $0) }
        return try? OrderLifecycleSession(accountID: account.id, epoch: gate.currentStamp, token: token,
            contextID: contextID, replayContext: replayContext)
    }
    lazy var orderLifecycleReader = OrderLifecycleSessionReader(service: orderLifecycleService,
        currentSession: { [weak self] in self?.currentOrderLifecycleSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentOrderLifecycleSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    // Default nil configuration cannot construct a writer. One file survives account
    // switches/relaunch; its keys bind exact origin, market, namespace, account and order.
    private lazy var orderLifecycleJournal: OrderLifecycleFileJournal? = {
        guard let directory = safetyDirectory("OrderLifecycle") else { return nil }
        return OrderLifecycleFileJournal(url: directory.appendingPathComponent("orders-v1.json"))
    }()
    private var orderLifecyclePaymentProviderAllowed: Bool {
        guard let configuration = runtimeDependencies.orderLifecycleConfiguration,
              let context = currentRuntimeDependencyContext, configuration.matches(context),
              configuration.externalCheckoutApproved, configuration.devicePaymentApproved else { return false }
        return configuration.approvals.contains { $0.action == .payment && $0.expiresAt > Date() }
    }
    private func makeOrderLifecycleDispatcher() -> OrderLifecycleProductionDispatcher? {
        guard let api = regionalConfiguration?.apiConfiguration, let journal = orderLifecycleJournal else { return nil }
        return OrderLifecycleProductionFactory.make(configuration: runtimeDependencies.orderLifecycleConfiguration,
            api: api, transport: runtimeHTTPTransport, journal: journal,
            document: runtimeDependencies.signupDocument,
            provider: runtimeDependencies.selfPlayPayment ?? nativeWeChatPaymentAdapter,
            sharedGate: selfPlayOperationGate, selfPlayJournal: TopicSelfPlayDefaultsJournal(defaults: .standard),
            current: { [weak self] in self?.currentRuntimeDependencyContext },
            reviewScope: { [weak self] in self?.orderLifecycleReader.scope ?? UUID() })
    }
    lazy var orderLifecycleCoordinator = OrderLifecycleCoordinator(reader: orderLifecycleReader,
        production: { [weak self] in self?.makeOrderLifecycleDispatcher() })
    func makeVerificationCodeCoordinator(target: VerificationCodeTarget) -> VerificationCodeCoordinator {
        VerificationCodeCoordinator(target: target,
            service: VerificationCodeHTTPService(configuration: regionalConfiguration?.apiConfiguration,
                approval: runtimeDependencies.verificationCodeApproval, kind: target.kind,
                transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext }),
            current: { [weak self] in self?.currentRuntimeDependencyContext },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            })
    }
    private let ticketWalletService:TicketWalletService?
    private var currentTicketWalletSession:TicketWalletReadSession? {
        guard let account,let token else { return nil }
        return try? TicketWalletReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var ticketWalletReader=TicketWalletSessionReader(service:ticketWalletService,currentSession:{ [weak self] in self?.currentTicketWalletSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentTicketWalletSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private let homeFeedService:HomeFeedService?
    private var currentHomeFeedSession:HomeFeedSession? {
        guard let account,let token else { return nil }
        return try? HomeFeedSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var homeFeedReader=HomeFeedSessionReader(service:homeFeedService,currentSession:{ [weak self] in self?.currentHomeFeedSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentHomeFeedSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.epoch,credential:self.token)
    })
    private let topicService: TopicService?
    private var currentTopicSession: TopicReadSession? {
        guard let account, let token else { return nil }
        return try? TopicReadSession(accountID:account.id,epoch:gate.currentStamp,token:token,
            role:account.effectiveRole,viewerRevision:compositionViewerRevision)
    }
    lazy var topicReader=TopicSessionReader(service:topicService,currentSession:{ [weak self] in
        self?.currentTopicSession
    },onUnauthorized:{ [weak self] snapshot in
        guard let self,self.currentTopicSession == snapshot else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.epoch,credential:self.token)
    })
    private let publicTemplateDetails = PublicTemplateDetailOwner()
    private let discoveryService: DiscoveryService?
    private let profileService: ProfileService?
    private let participantService: ParticipantService?
    @Published private(set) var participantRevision: UInt64=0
    lazy var participantWriter=ParticipantSessionWriter(service:participantService,currentSession:{ [weak self] in
        guard let self,let account=self.account,let token=self.token else { return nil }
        return try? ParticipantWriteSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
    },onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    lazy var participantCoordinator=ParticipantMutationCoordinator(writer:participantWriter,reader:profileReader,onParticipantsChanged:{ [weak self] in
        self?.participantRevision &+= 1
    })
    private let merchantService: MerchantService?
    private let merchantEngagementService: MerchantEngagementService?
    lazy var merchantEngagementReader = MerchantEngagementSessionReader(
        service: merchantEngagementService,
        session: { [weak self] in self?.currentMerchantBusinessSession },
        productionService: { [weak self] command, merchantID in self?.merchantEngagementFactory?.service(for: command, merchantID: merchantID) },
        devicePermission: { [weak self] action, merchantID in self?.merchantEngagementFactory?.permitsDevice(action, merchantID: merchantID) == true },
        runtimeContext: { [weak self] in self?.currentRuntimeDependencyContext },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantBusinessSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    private var merchantEngagementFactory: MerchantEngagementProductionFactory? {
        guard let api = regionalConfiguration?.apiConfiguration else { return nil }
        return .init(api: api, approval: runtimeDependencies.merchantEngagementApproval,
                     transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext })
    }
    lazy var merchantExportRecovery = MerchantExportFileRecoveryStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/MerchantBusiness/export-tasks-v1.json"))
    private let merchantBusinessService: MerchantBusinessService?
    private var currentMerchantBusinessSession: MerchantBusinessSession? {
        guard let account, let token else { return nil }
        return try? MerchantBusinessSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var merchantBusinessReader = MerchantBusinessSessionReader(service: merchantBusinessService,
        verificationService: { [weak self] in self?.makeMerchantVerificationService() },
        currentSession: { [weak self] in self?.currentMerchantBusinessSession },
        productionService: { [weak self] mutation, merchantID in
            guard let self, let api = self.regionalConfiguration?.apiConfiguration else { return nil }
            return MerchantBusinessProductionFactory(api: api, approval: self.runtimeDependencies.merchantBusinessApproval,
                transport: self.runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext }).service(for: mutation, merchantID: merchantID)
        }, runtimeContext: { [weak self] in self?.currentRuntimeDependencyContext },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantBusinessSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    lazy var merchantBusinessJournal = MerchantBusinessFileIntentStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/MerchantBusiness/intents-v1.json"))
    private func makeMerchantVerificationService() -> MerchantBusinessService? {
        guard let factory = businessRuntimeFactory, factory.permits(.directVerification),
              factory.routes([.directVerification]).contains(where: { MerchantVerificationHTTPTransport.paths.contains($0.path) }),
              let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let client = factory.client([.directVerification])
        return MerchantBusinessService(configuration: configuration, readTransport: client,
            verificationTransport: MerchantVerificationHTTPTransport(baseURL: configuration.baseURL, transport: client))
    }
    var verificationCameraEnabled: Bool { businessRuntimeFactory?.configuration.verificationCamera == true }
    private var retainedNativeVerification: (context: RuntimeDependencyContext, flow: NativeVerificationWorkflow)?
    private lazy var disabledNativeVerification = NativeVerificationWorkflow(reader: merchantBusinessReader, journal: merchantBusinessJournal, redemption: nil)
    var nativeVerificationFlow: NativeVerificationWorkflow {
        guard let factory = businessRuntimeFactory, let service = makeMerchantVerificationService() else { return disabledNativeVerification }
        if let retainedNativeVerification, retainedNativeVerification.context == factory.captured { return retainedNativeVerification.flow }
        retainedNativeVerification?.flow.deactivate()
        let captured = factory.captured
        let redemption = MerchantRedemptionCoordinator(service: service, journal: merchantBusinessJournal,
            currentSession: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured else { return nil }; return self.currentMerchantBusinessSession
            })
        let flow = NativeVerificationWorkflow(reader: merchantBusinessReader, journal: merchantBusinessJournal, redemption: redemption)
        retainedNativeVerification = (captured, flow); return flow
    }
    private var currentMerchantContentSession: MerchantContentSession? {
        guard let account, let token, let storageScope else { return nil }
        return try? MerchantContentSession(accountID: account.id, epoch: gate.currentStamp,
            storageScope: storageScope.service, token: token)
    }
    lazy var merchantContentService = MerchantContentService(configuration: regionalConfiguration?.apiConfiguration,
        transport: runtimeHTTPTransport, currentSession: { [weak self] in self?.currentMerchantContentSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantContentSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    private var retainedNearbyMerchants: (context: RuntimeDependencyContext, coordinator: NearbyMerchantCoordinator)?
    var nearbyMerchantCoordinator: NearbyMerchantCoordinator? {
        guard let captured = currentRuntimeDependencyContext, let api = regionalConfiguration?.apiConfiguration,
              let factory = runtimeDependencyFactory else { return nil }
        if let retainedNearbyMerchants, retainedNearbyMerchants.context == captured { return retainedNearbyMerchants.coordinator }
        retainedNearbyMerchants?.coordinator.cancel()
        let reader = CoopFlowSessionReader(service: CoopFlowService(configuration: api, transport: factory.transport),
            current: { [weak self] in self?.currentCooperationFlowSession }, unauthorized: { [weak self] old in
                guard let self, self.currentCooperationFlowSession == old else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: old.epoch, credential: self.token)
            })
        let model = NearbyMerchantCoordinator(reader: reader,
            location: runtimeDependencies.location ?? RuntimeNativeLocationProvider(enabled: factory.allowsNearbyLocation),
            approved: { [weak self] in factory.allowsNearbyLocation && self?.currentRuntimeDependencyContext == captured })
        retainedNearbyMerchants = (captured, model); return model
    }
    private let cooperationFlowService: CoopFlowService?
    private var currentCooperationFlowSession: CoopFlowSession? {
        guard let account, let token else { return nil }
        return try? CoopFlowSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var cooperationFlowReader = CoopFlowSessionReader(service: cooperationFlowService,
        current: { [weak self] in self?.currentCooperationFlowSession },
        unauthorized: { [weak self] captured in
            guard let self, self.currentCooperationFlowSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    private let merchantOperationsService: MerchantOperationsService?
    private var currentMerchantOperationsSession: MerchantOperationsSession? {
        guard let account, let token else { return nil }
        return try? MerchantOperationsSession(accountID: account.id, epoch: gate.currentStamp, token: token, storageNamespace: storageScope?.service ?? "", viewerRevision: compositionViewerRevision)
    }
    lazy var merchantOperationsReader = MerchantOperationsSessionReader(service: merchantOperationsService, currentSession: { [weak self] in
        self?.currentMerchantOperationsSession
    }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentMerchantOperationsSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
    })
    private let merchantOnboardingService: MerchantOnboardingService?
    private var currentMerchantOnboardingSession: MerchantOnboardingSession? {
        guard let account, let token else { return nil }
        return try? MerchantOnboardingSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var merchantOnboardingAdapter = MerchantOnboardingSessionAdapter(service: merchantOnboardingService, currentSession: { [weak self] in
        self?.currentMerchantOnboardingSession
    }, onUnauthorized: { [weak self] snapshot in
        guard let self, self.currentMerchantOnboardingSession == snapshot else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
    })
    // Retained outside navigation so unresolved submissions cannot be replayed by reopening.
    lazy var merchantOnboardingCoordinator = MerchantOnboardingCoordinator(server: merchantOnboardingAdapter)
    private let clubService: ClubService?
    private let clubOperationsService: ClubOperationsService?
    private let clubGovernanceService: ClubGovernanceService?
    private var currentClubGovernanceSession: ClubGovernanceSession? {
        guard let account, let token else { return nil }
        return try? ClubGovernanceSession(accountID: account.id, epoch: gate.currentStamp, token: token, storageNamespace: storageScope?.service ?? "")
    }
    lazy var clubGovernanceAccess = ClubGovernanceSessionAccess(service: clubGovernanceService, currentSession: { [weak self] in
        self?.currentClubGovernanceSession
    }, productionService: { [weak self] command in
        guard let self, let api = self.regionalConfiguration?.apiConfiguration else { return nil }
        return ClubGovernanceProductionFactory(api: api, approval: self.runtimeDependencies.clubGovernanceApproval,
            transport: self.runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext }).service(for: command)
    }, runtimeContext: { [weak self] in self?.currentRuntimeDependencyContext }, onUnauthorized: { [weak self] identity in
        guard let self, self.currentClubGovernanceSession?.identity == identity else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: identity.epoch, credential: self.token)
    })
    // Session-lived: unresolved operations cannot be replayed by reopening a sheet.
    lazy var clubGovernanceCoordinator = ClubGovernanceCoordinator(access: clubGovernanceAccess,
        journal: ClubGovernanceFileIntentStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClubGovernanceIntents", isDirectory: true)))
    lazy var clubOwnerRefundCoordinator = ClubOwnerRefundCoordinator(
        access: ClubOwnerRefundConfiguredAccess(fallback: ClubOwnerRefundReadOnlyAccess(governance: clubGovernanceAccess),
            configuration: regionalConfiguration?.apiConfiguration, approval: runtimeDependencies.ownerRefundApproval,
            transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            }),
        locks: ClubOwnerRefundFileLocks(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("ClubOwnerRefundLocks", isDirectory: true)))
    private var contextualOperationJournal: any OperationPendingJournal { composition.storage.operationJournal() }
    private lazy var clubOpsTimeHost: ClubOpsTimeHost? = regionalConfiguration?.apiConfiguration.map {
        ClubOpsTimeHost(service: ClubOpsTimeConfiguredService(configuration: $0, approval: runtimeDependencies.clubOpsTimeApproval,
            transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            }), journal: contextualOperationJournal)
    }
    var clubGovernanceContext: ClubGovernanceContext { .init(viewerRevision: compositionViewerRevision, access: clubGovernanceAccess, coordinator: clubGovernanceCoordinator, enrollmentProfile: .init(reader: socialAccountReader, squareReader: squareReader, actions: socialActionCoordinator), ownerRefund: clubOwnerRefundCoordinator, opsTimeFactory: { [weak self] in self?.clubOpsTimeHost?.coordinator(activityID: $0) }) }
    private var currentClubOperationsSession: ClubOperationsSession? {
        guard let account, let token else { return nil }
        return try? ClubOperationsSession(accountID: account.id, epoch: gate.currentStamp, token: token, storageNamespace: storageScope?.service ?? "")
    }
    lazy var clubOperationsAccess = ClubOperationsSessionAccess(service: clubOperationsService, currentSession: { [weak self] in self?.currentClubOperationsSession }, onUnauthorized: { [weak self] captured in
        guard let self, self.currentClubOperationsSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: captured.identity.epoch, credential: self.token)
    })
    lazy var clubOperationsCoordinator = ClubOperationsCoordinator(access: clubOperationsAccess)
    var clubOperationsContext: ClubOperationsContext { .init(access: clubOperationsAccess, coordinator: clubOperationsCoordinator) }
    private let clubManagementService:ClubManagementService?
    private var currentClubManagementSession:ClubManagementSession? {
        guard let account,let token else { return nil }
        return try? ClubManagementSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var clubManagementAccess=ClubManagementSessionAccess(service:clubManagementService,currentSession:{ [weak self] in self?.currentClubManagementSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentClubManagementSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.identity.epoch,credential:self.token)
    })
    lazy var clubManagementCoordinator=ClubManagementCoordinator(access:clubManagementAccess,onMembershipChanged:{ [weak self] _ in self?.clubMembershipRevision &+= 1 })
    var clubManagementContext:ClubManagementContext { .init(access:clubManagementAccess,coordinator:clubManagementCoordinator,operations:clubOperationsContext,governance:clubGovernanceContext) }
    lazy var contextualReviews: ContextualReviewHost? = regionalConfiguration?.apiConfiguration.map {
        ContextualReviewHost(writer: ContextualReviewConfiguredWriter(configuration: $0, approval: runtimeDependencies.contextualReviewApproval,
            transport: runtimeHTTPTransport, current: { [weak self] in self?.currentRuntimeDependencyContext },
            onUnauthorized: { [weak self] captured in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.session.epoch, credential: captured.session.token)
            }), journal: contextualOperationJournal)
    }
    private let profileEditService:ProfileEditService?
    private var currentProfileEditSession:ProfileEditSession? {
        guard let account,let token else { return nil }
        return try? ProfileEditSession(accountID:account.id,epoch:gate.currentStamp,token:token,viewerRevision:compositionViewerRevision)
    }
    lazy var profileEditCoordinator=ProfileEditCoordinator(service:profileEditService,currentSession:{ [weak self] in self?.currentProfileEditSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentProfileEditSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.identity.epoch,credential:self.token)
    },onSaved:{ [weak self] in Task { await self?.refreshOwnAccount() } })
    func refreshOwnAccount() async {
        guard let accountSessionService, accountSessionService.storageScope == storageScope,
              let credential=token,let accountID=account?.id else { return }
        let stamp=gate.currentStamp
        do {
            let fresh=try await accountSessionService.currentAccount(token:credential)
            guard !Task.isCancelled,gate.currentStamp == stamp,token == credential,account?.id == accountID,fresh.id == accountID else { return }
            account=fresh
        } catch { expireIfMatching(error:error,stamp:stamp,credential:credential) }
    }
    private let clubActionService: ClubActionService?
    @Published private(set) var clubMembershipRevision: UInt64 = 0
    private var currentClubActionSession: ClubActionSession? {
        guard let account, let token else { return nil }
        return try? ClubActionSession(account: account, epoch: gate.currentStamp, token: token)
    }
    lazy var clubActionWriter = ClubActionSessionWriter(service: clubActionService, currentSession: { [weak self] in
        self?.currentClubActionSession
    }, onUnauthorized: { [weak self] snapshot in
        // Compare the whole captured snapshot, including credential and verified role.
        // A late failure can never expire a replacement account or token.
        guard let self, self.currentClubActionSession == snapshot else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
    })
    lazy var clubActionCoordinator = ClubActionCoordinator(writer: clubActionWriter, reader: clubReader, onMembershipChanged: { [weak self] _ in
        self?.clubMembershipRevision &+= 1
    })
    private let roamLiveDependencies: NativeRoamLiveDependencies
    private var retainedRoamLiveSession: RoamLiveSessionController?
    func makeRoamLiveSessionController() -> RoamLiveSessionController {
        if let existing = retainedRoamLiveSession { return existing }
        let storage = RoamHistoryKeychainStorage()
        let journal = RoamLiveJournal(storage: storage)
        var liveService: RoamLiveService?
        var location: (any RoamDeviceLocationProviding)?
        if let snapshot = currentRoamExperienceSession, let api = regionalConfiguration?.apiConfiguration,
           let approval = roamLiveDependencies.approval, approval.allows(snapshot.identity, api: api),
           let transport = roamLiveDependencies.transport, let makeLocation = roamLiveDependencies.makeLocation {
            liveService = RoamLiveService(api: api, approval: approval, transport: scopedTransport(transport),
                currentSession: { [weak self] in self?.currentRoamExperienceSession })
            location = makeLocation()
        }
        let controller = RoamLiveSessionController(service: liveService, location: location, journal: journal, history: roamHistoryStore)
        retainedRoamLiveSession = controller
        return controller
    }
    private let roamExperienceService: RoamExperienceService?
    private var currentRoamExperienceSession: RoamExperienceSession? {
        guard let account, let token, let storageScope,
              let regional = regionalConfiguration, let configuration = regional.apiConfiguration,
              storageScope.matches(configuration: regional),
              let scope = try? RoamHistoryScope(market: regional.market.rawValue,
                  deployment: configuration.baseURL, accountID: account.id, namespace: storageScope.service) else { return nil }
        return try? RoamExperienceSession(scope: scope, epoch: gate.currentStamp, token: token)
    }
    private lazy var roamHistoryStore = RoamHistoryStore(storage: RoamHistoryKeychainStorage(), currentScope: { [weak self] in
        self?.currentRoamExperienceSession?.identity.scope
    })
    lazy var roamExperienceReader = RoamExperienceSessionReader(service: roamExperienceService, store: roamHistoryStore,
        currentSession: { [weak self] in self?.currentRoamExperienceSession }, onUnauthorized: { [weak self] captured in
            guard let self, self.currentRoamExperienceSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.identity.epoch, credential: self.token)
        })
    private let roamService: RoamService?
    // Exact dormant IM adapter exists, but ordinary production composition has no live grant.
    private var imExpandedCoordinators: [IMScope: IMExpandedCoordinator] = [:]
    private var imImageCoordinators: [IMScope: IMImageUploadCoordinator] = [:]
    private var imStarters: [MessagingReadIdentity: IMConversationStarter] = [:]
    private var retainedIMWriter: (context: RuntimeDependencyContext, writer: IMExpandedWriter)?
    private lazy var disabledIMWriter = IMExpandedWriter(service: nil, session: { [weak self] in self?.currentIMExpandedSession })
    private var currentIMExpandedSession: IMExpandedSession? {
        guard let account, let token else { return nil }
        return try? IMExpandedSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    var imExpandedWriter: IMExpandedWriter {
        let features: Set<BusinessRuntimeFeature> = [.imStart, .imRead, .imMute, .imSend, .imUpload]
        guard let factory = businessRuntimeFactory, !factory.routes(features).isEmpty,
              let configuration = regionalConfiguration?.apiConfiguration else { return disabledIMWriter }
        if let retainedIMWriter, retainedIMWriter.context == factory.captured { return retainedIMWriter.writer }
        let captured = factory.captured
        let service = IMExpandedService(configuration: configuration, transport: factory.client(features),
            approvedMediaOrigins: factory.configuration.imMediaOrigins, writesEnabled: true,
            enabledPaths: Set(factory.routes(features).map(\.path)))
        let writer = IMExpandedWriter(service: service, session: { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured else { return nil }; return self.currentIMExpandedSession
        }, onUnauthorized: { [weak self] snapshot in
            guard let self, self.currentRuntimeDependencyContext == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
        })
        retainedIMWriter = (captured, writer); return writer
    }
    func imExpandedCoordinator(for conversationID: Int) -> IMExpandedCoordinator? {
        guard let identity = imExpandedWriter.identity, let scope = try? IMScope(identity: identity, conversationID: conversationID) else { return nil }
        if let existing = imExpandedCoordinators[scope] { return existing }
        let owner = IMExpandedCoordinator(scope: scope, writer: imExpandedWriter)
        imExpandedCoordinators[scope] = owner; return owner
    }
    func imImageUploadCoordinator(for conversationID: Int) -> IMImageUploadCoordinator? {
        guard let identity = imExpandedWriter.identity, let scope = try? IMScope(identity: identity, conversationID: conversationID) else { return nil }
        if let existing = imImageCoordinators[scope] { return existing }
        guard let namespace = storageScope?.service, let realm = regionalConfiguration?.apiConfiguration?.baseURL.absoluteString,
              let target = try? ImageUploadTarget(accountID: identity.accountID, namespace: namespace, realm: realm,
                kind: "im", entityID: conversationID, field: "image") else { return nil }
        let owner = IMImageUploadCoordinator(scope: scope, writer: imExpandedWriter, picker: retainedImagePickerHost.imPicker(scope: scope, currentScope: { [weak self] in
            guard let self, self.imExpandedWriter.identity == scope.identity else { return nil }; return scope
        }, selectionApproval: { [weak self] in
            guard let self, self.imExpandedWriter.identity == scope.identity, let factory = self.businessRuntimeFactory else { return false }
            return factory.permits(.imUpload) && factory.configuration.imImageSelection
        }), journal: imageUploadJournal, target: target)
        imImageCoordinators[scope] = owner; return owner
    }
    func imConversationStarter() -> IMConversationStarter? {
        guard let identity = imExpandedWriter.identity else { return nil }
        if let existing = imStarters[identity] { return existing }
        let owner = IMConversationStarter(identity: identity, writer: imExpandedWriter)
        imStarters[identity] = owner; return owner
    }
    private var clubChatOwners: [Int: ClubChatCoordinator] = [:]
    func clubChatCoordinator(clubID: Int) -> ClubChatCoordinator? {
        if let owner = clubChatOwners[clubID], owner.isCurrent { return owner }
        guard let account, let token, let configuration = regionalConfiguration?.apiConfiguration,
              let snapshot = try? GroupPollSession(accountID: account.id, epoch: gate.currentStamp, token: token) else { return nil }
        let captured = currentRuntimeDependencyContext, factory = businessRuntimeFactory
        let transport: any HTTPTransport
        if let factory { transport = factory.client([.clubChat]) } else { transport = runtimeHTTPTransport }
        let service = ClubChatService(configuration: configuration, transport: transport, enabled: factory?.permits(.clubChat) == true,
            session: { [weak self] in
                guard let self, self.currentRuntimeDependencyContext == captured, let account = self.account, let token = self.token else { return nil }
                return try? GroupPollSession(accountID: account.id, epoch: self.gate.currentStamp, token: token)
            }, onUnauthorized: { [weak self] value in
                guard let self, self.currentRuntimeDependencyContext == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: value.identity.epoch, credential: self.token)
            })
        guard let owner = try? ClubChatCoordinator(clubID: clubID, identity: snapshot.identity, service: service, clubs: clubReader, messages: messagingReader) else { return nil }
        clubChatOwners[clubID] = owner; return owner
    }
    private struct GroupPollOwnerKey: Hashable { let scope: IMScope; let reference: GroupPollReference? }
    private var groupPollOwners: [GroupPollOwnerKey: GroupPollCoordinator] = [:]
    func groupPollCoordinator(conversationID: Int, reference: GroupPollReference?) -> GroupPollCoordinator? {
        guard let account, let token, let namespace = storageScope?.service,
              let configuration = regionalConfiguration?.apiConfiguration,
              let snapshot = try? GroupPollSession(accountID: account.id, epoch: gate.currentStamp, token: token),
              let scope = try? IMScope(identity: snapshot.identity, conversationID: conversationID) else { return nil }
        let key = GroupPollOwnerKey(scope: scope, reference: reference)
        if let owner = groupPollOwners[key] { return owner }
        let captured = currentRuntimeDependencyContext
        let features: Set<BusinessRuntimeFeature> = [.imPollResult, .imPollCreate, .imPollVote, .imPollClose]
        let service: GroupPollService?
        if let factory = businessRuntimeFactory {
            service = GroupPollService(configuration: configuration, transport: factory.client(features),
                enabledPaths: Set(factory.routes(features).map(\.path)))
        } else { service = nil }
        let client = GroupPollSessionClient(service: service, session: { [weak self] in
            guard let self, self.currentRuntimeDependencyContext == captured, let account = self.account, let token = self.token else { return nil }
            return try? GroupPollSession(accountID: account.id, epoch: self.gate.currentStamp, token: token)
        }, onUnauthorized: { [weak self] value in
            guard let self, self.currentRuntimeDependencyContext == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: value.identity.epoch, credential: self.token)
        })
        guard let owner = try? GroupPollCoordinator(scope: scope, reference: reference, client: client,
            reader: messagingReader, journal: composition.storage.operationJournal(), namespace: namespace, realm: configuration.baseURL) else { return nil }
        groupPollOwners[key] = owner; return owner
    }
    private let messagingService: MessagingService?
    private let messageActionService: MessageActionService?
    private struct MessageSenderKey: Hashable { let accountID:Int;let conversationID:Int }
    private var messageSenders:[MessageSenderKey:MessageActionCoordinator]=[:]
    lazy var messageWriter=MessageSessionWriter(service:messageActionService,currentSession:{ [weak self] in
        guard let self,let account=self.account,let token=self.token else { return nil }
        return try? MessageActionSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
    },onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    func messageSender(for conversationID:Int) -> MessageActionCoordinator? {
        guard conversationID>0,let account else { return nil }
        let key=MessageSenderKey(accountID:account.id,conversationID:conversationID)
        if let sender=messageSenders[key] { return sender }
        let sender=MessageActionCoordinator(accountID:account.id,conversationID:conversationID,writer:messageWriter)
        messageSenders[key]=sender;return sender
    }
    lazy var messagingReader=MessagingSessionReader(service:messagingService,currentSession:{ [weak self] in
        guard let self, let account=self.account, let token=self.token else { return nil }
        return try? MessagingReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
    },onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    @Published var roamArea: RoamSearchArea? { didSet { roamMapSelection.select(roamArea) } }
    lazy var roamReader=RoamSessionReader(service:roamService,currentSession:{ [weak self] in
        guard let self, let account=self.account, let token=self.token else { return nil }
        return try? RoamReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token,role:account.effectiveRole,viewerRevision:self.compositionViewerRevision,areaRevision:self.roamMapSelection.revision,manualMapApprovalRevision:self.currentManualMapApprovalRevision)
    },searchArea:{ [weak self] in self?.roamArea },onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    lazy var clubReader=ClubSessionReader(service:clubService,currentSession:{ [weak self] in
        guard let self else { return ClubReadSession(guestEpoch:0) }
        if let account=self.account, let token=self.token,
           let snapshot=try? ClubReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token) { return snapshot }
        return ClubReadSession(guestEpoch:self.gate.currentStamp)
    },onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    private var merchantAccessRecord: (stamp:UInt64, access:MerchantAccess)?
    var isSignedIn: Bool { account != nil && token != nil }
    var sessionRevision: UInt64 { gate.currentStamp }
    var contentDetailRevision: UInt64 { compositionViewerRevision }
    private var currentOwnedOrderSession: OwnedOrderReadSession? {
        guard let context = currentRuntimeDependencyContext,
              let approval = composition.ownedOrderReadApproval(context), approval.matches(context) else { return nil }
        return .init(context: context, viewerRevision: compositionViewerRevision, approvalRevision: approval.revision)
    }
    private var ownedOrderSignedInIdentity: ProfileReadIdentity? {
        guard let account, let token, AuthRequestBuilder.isValidToken(token),
              ["player", "club", "merchant"].contains(account.effectiveRole), !committingAuthenticatedSession else { return nil }
        return .init(accountID: account.id, epoch: gate.currentStamp, viewerRevision: compositionViewerRevision)
    }
    lazy var ownedOrderReader = OwnedOrderSessionReader(service: profileService,
        current: { [weak self] in self?.currentOwnedOrderSession },
        signedInIdentity: { [weak self] in self?.ownedOrderSignedInIdentity },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentOwnedOrderSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.context.session.epoch, credential: captured.context.session.token)
        })
    lazy var profileReader = ProfileSessionReader(service:profileService, currentSession:{ [weak self] in
        guard let self, let account=self.account, let token=self.token else { return nil }
        return try? ProfileReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
    }, onUnauthorized:{ [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.identity.epoch,credential:self.token)
    })
    // Default-off source adapters share the existing account/session/token owner.
    private var retainedCompliance: AccountComplianceCoordinator?
    private var retainedComplianceService: AccountComplianceService?
    private var retainedMarketing: MerchantMarketingCoordinator?
    private var retainedDoorQueue: DoorReferralQueue?
    private var retainedDoorCoordinator: DoorEntryCoordinator?
    private var doorEpoch = UUID()
    private var entryObservedStamp: UInt64 = 0
    private var entryObservedAccountID: Int?
    private var entryObservedRole: String?
    private var entryObservedToken: String?
    @Published private(set) var restorationFinished = false
    @Published private(set) var nativeEntry: NativeEntryPresentation?
    let nativeEntryLinkPolicy = NativeEntryLinkPolicy(verifiedHTTPSOrigins: [])
    var doorReferralSession: DoorReferralSession {
        DoorReferralSession(accountID: account?.id, epoch: doorEpoch, token: token, restored: restorationFinished)
    }
    private var complianceSession: ComplianceSession? {
        guard let account, token != nil, let market = operationalMarket, let namespace = storageScope?.service else { return nil }
        return ComplianceSession(accountID: account.id, epoch: gate.currentStamp, market: market.rawValue, namespace: namespace)
    }
    private func safetyDirectory(_ component: String) -> URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = root.appendingPathComponent(component, isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory }
        catch { return nil }
    }
    var accountComplianceCoordinator: AccountComplianceCoordinator? {
        if let retainedCompliance { return retainedCompliance }
        guard let configuration = regionalConfiguration?.apiConfiguration, let authChannelService,
              let directory = safetyDirectory("AccountComplianceSafety") else { return nil }
        let service = AccountComplianceService(configuration: configuration, transport: runtimeHTTPTransport,
            journal: ComplianceFileJournal(url: directory.appendingPathComponent("operations-v1.json")),
            current: { [weak self] in self?.complianceSession }, token: { [weak self] in self?.token },
            readsEnabled: false, writesEnabled: false, legalApproved: { _, _ in false }, authoritativeMerchantID: { nil })
        let coordinator = AccountComplianceCoordinator(service: service, auth: authChannelService,
            effects: DormantComplianceRoamEffects(), current: { [weak self] in self?.complianceSession },
            invalidateSession: { [weak self] captured in
                guard let self, self.complianceSession == captured else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
            })
        retainedComplianceService = service; retainedCompliance = coordinator; return coordinator
    }
    func complianceSignupContext() -> (AccountComplianceService, ComplianceSession)? {
        _ = accountComplianceCoordinator
        guard let service = retainedComplianceService, let session = complianceSession else { return nil }
        return (service, session)
    }
    var merchantMarketingCoordinator: MerchantMarketingCoordinator {
        if let retainedMarketing { return retainedMarketing }
        let service = MerchantMarketingService(configuration: regionalConfiguration?.apiConfiguration,
            transport: runtimeHTTPTransport, gates: .init(reads: false, insight: false, settlement: false), locks: nil,
            currentSession: { [weak self] in
                guard let self, let account = self.account, let token = self.token, let namespace = self.storageScope?.service else { return nil }
                return try? MerchantMarketingScope(namespace: namespace, accountID: account.id, epoch: self.gate.currentStamp, token: token)
            }, onUnauthorized: { [weak self] captured in
                guard let self, self.account?.id == captured.accountID, self.token == captured.token else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: captured.token)
            })
        let model = MerchantMarketingCoordinator(service: service); retainedMarketing = model; return model
    }
    private func prepareDoorRuntime() {
        guard retainedDoorQueue == nil, let configuration = regionalConfiguration?.apiConfiguration, let namespace = storageScope?.service,
              let directory = safetyDirectory("DoorReferralSafety/" + namespace) else { return }
        let service = DoorReferralService(configuration: configuration, transport: runtimeHTTPTransport, scanEnabled: false, bindingEnabled: false,
            currentSession: { [weak self] in self?.doorReferralSession ?? DoorReferralSession(accountID: nil, epoch: UUID(), token: nil, restored: false) })
        retainedDoorQueue = DoorReferralQueue(store: DoorReferralFileStore(url: directory.appendingPathComponent("referrals-v1.json")), service: service,
            currentSession: { [weak self] in self?.doorReferralSession ?? DoorReferralSession(accountID: nil, epoch: UUID(), token: nil, restored: false) })
        retainedDoorCoordinator = DoorEntryCoordinator(session: doorReferralSession, service: service)
    }
    var doorReferralQueue: DoorReferralQueue? { prepareDoorRuntime(); return retainedDoorQueue }
    var doorEntryCoordinator: DoorEntryCoordinator? { prepareDoorRuntime(); return retainedDoorCoordinator }
    func receiveNativeURL(_ url: URL) {
        if nativeWeChatPaymentDriver.handle(url, adapter: nativeWeChatPaymentAdapter) { return }
        if weChatSDKDriver.handle(url, adapter: weChatSDKAdapter) { return }
        guard let intent = nativeEntryLinkPolicy.parse(url) else {
            receiveNativeIntent(.routeError(.unsupported)); return
        }
        receiveNativeIntent(intent)
    }
    func receiveWeChatUserActivity(_ activity: NSUserActivity) {
        if nativeWeChatPaymentDriver.handle(activity, adapter: nativeWeChatPaymentAdapter) { return }
        _ = weChatSDKDriver.handle(activity, adapter: weChatSDKAdapter)
    }
    func receiveNativeIntent(_ intent: NativeEntryIntent) {
        if case .door(let door) = intent {
            prepareDoorRuntime()
            if let inviter = door.inviter, !inviter.isEmpty { try? retainedDoorQueue?.capture(inviter) }
            retainedDoorCoordinator?.updateSession(doorReferralSession)
            retainedDoorCoordinator?.receive(door)
        }
        nativeEntry = NativeEntryPresentation(intent: intent)
    }
    func dismissNativeEntry() { retainedDoorCoordinator?.cancel(); nativeEntry = nil }
    private func synchronizeAccountMarketingEntry() {
        synchronizePrivateHome()
        synchronizeOwnerDraftBrowser()
        let identityChanged = entryObservedStamp != gate.currentStamp || entryObservedAccountID != account?.id || entryObservedToken != token || entryObservedRole != account?.effectiveRole
        if identityChanged {
            publicTemplateDetails.invalidate()
            // Account refresh can change roles without advancing the login operation gate.
            // Preserve an ABA fence even when the same account/role/token later returns.
            compositionViewerRevision &+= 1
            retainedNativeVerification?.flow.deactivate(); retainedNativeVerification = nil
            retainedPublishingService?.service.invalidateReviews(); retainedPublishingService = nil
            clubChatOwners.removeAll(); groupPollOwners.removeAll(); retainedIMWriter = nil; imExpandedCoordinators.removeAll(); imImageCoordinators.removeAll(); imStarters.removeAll()
            retainedProjectEditors.values.forEach { $0.synchronizeSession() }; retainedProjectEditors.removeAll()
            retainedRoamLiveSession?.invalidate(); retainedRoamLiveSession = nil
            retainedNativePlatform?.invalidate(); retainedNativePlatform = nil
            runtimeSensorProviders.forEach { $0.value?.cancel() }; runtimeSensorProviders.removeAll()
            retainedNativePlayDevice?.provider.cancel(); retainedNativePlayDevice = nil
            retainedPlayDevices.values.forEach { $0.cancel() }; retainedPlayDevices.removeAll()
            retainedPlayStillness.values.forEach { $0.pause() }; retainedPlayStillness.removeAll()
            retainedPlayPrefabs.values.forEach { $0.cancelDeviceWork() }; retainedPlayPrefabs.removeAll()
            playReaders.removeAll()
            playExperienceCoordinators.values.forEach { $0.invalidate() }; playExperienceCoordinators.removeAll()
            retainedNearbyMerchants?.coordinator.cancel(); retainedNearbyMerchants = nil
            publicMerchantReviewEpoch = UUID(); retainedPublicMerchantReviews?.invalidate(); retainedImageContextCache?.invalidate()
            retainedPublisherLifecycle?.context.invalidate(); retainedPublisherLifecycle = nil
            merchantNPCSessionOwner.invalidate(); merchantNPCAccess = nil
            invalidateShopNPCConversations()
            platformConsumers.invalidate()
            retainedMerchantPublicFactory = nil
            publicMerchantReviewReader = DisabledPublicMerchantReviewReader()
            let oldAccount = entryObservedAccountID
            entryObservedStamp = gate.currentStamp; entryObservedAccountID = account?.id; entryObservedToken = token; entryObservedRole = account?.effectiveRole
            doorEpoch = UUID(); retainedCompliance?.invalidate(); retainedMarketing?.sessionChanged()
            if restorationFinished, let entry = nativeEntry, case .door = entry.intent { dismissNativeEntry() }
            // Guest invitation survives initial login; an existing account's route cannot jump accounts.
            if oldAccount != nil, oldAccount != account?.id { dismissNativeEntry() }
        }
        retainedDoorCoordinator?.updateSession(doorReferralSession)
    }

    private var token: String? { willSet { invalidateOwnerDraftBrowser(); if token != newValue { invalidateShopNPCConversations(); platformConsumers.invalidate() } } didSet { _ = runtimeDependencies; synchronizeAccountMarketingEntry() } }
    private var didBootstrap = false
    private let restoreBlockedKey:String
    var isConfigured: Bool { storageScope != nil }

    init(composition: AppCompositionRoot? = nil, runtimeDependencies: NativeRuntimeDependencies? = nil, roamLiveDependencies: NativeRoamLiveDependencies? = nil,
         registrationApproval: RegistrationProductionApproval? = nil,
         registrationStorefront: @escaping () -> String? = { nil }) {
        let composition = composition ?? RegionalLaunchConfiguration.composition
        self.registrationApproval = registrationApproval; self.registrationStorefront = registrationStorefront
        self.roamLiveDependencies = roamLiveDependencies ?? .dormant
        self.composition = composition
        self.compositionTransport = composition.transport()
        self.injectedRuntimeDependencies = runtimeDependencies
        let regional=composition.reviewed?.regional
        regionalConfiguration=regional
        let scope=composition.reviewed?.storageScope
        storageScope=scope
        vault=composition.storage.tokenStore(scope)
        restoreBlockedKey=scope?.restoreBlockedKey ?? "session.unconfigured.preventRestore"
        // An endpoint alone cannot authorize restoring/sending a persisted credential.
        if let scope, let regional, let configuration=regional.apiConfiguration {
            let transport=compositionTransport
            accountSessionService=try? CNAccountSessionService(configuration:regional,storageScope:scope,transport:transport)
            service=regional.availability(of:.usernamePassword) == .available ? AuthService(configuration:configuration,transport:transport) : nil
            authChannelService=regional.canUseDomesticChinaPhone ? AuthChannelService(configuration:configuration,transport:transport) : nil
            searchMapService=composition.reviewed?.reads.isDisjoint(with: [.homeAndSearch, .manualMap]) == false ? SearchMapService(configuration:configuration,transport:transport.scopedForManualMap(searchMapSelection)) : nil
            activityService=ActivityService(configuration:configuration,transport:transport)
            registrationBackend=RegistrationService(configuration:configuration,transport:transport)
            homeFeedService=composition.reviewed?.reads.contains(.homeAndSearch) == true ? HomeFeedService(configuration:configuration,transport:transport) : nil
            orderLifecycleService=OrderLifecycleService(configuration:configuration,transport:transport)
            ticketWalletService=TicketWalletService(configuration:configuration,transport:transport)
            squareService=SquareService(configuration:configuration,transport:transport)
            socialAccountService=SocialAccountService(configuration:configuration,transport:transport)
            officialEventService=OfficialEventService(configuration:configuration,transport:transport)
            growthCenterService=GrowthCenterService(configuration:configuration,transport:transport)
            creatorContentService=CreatorContentService(configuration:configuration,transport:transport)
            accountCollectionService=AccountCollectionService(configuration:configuration,transport:transport)
            cooperationService=CooperationService(configuration:configuration,transport:transport)
            topicService=TopicService(configuration:configuration,transport:transport)
            discoveryService=DiscoveryService(configuration:configuration,transport:transport)
            profileService=ProfileService(configuration:configuration,transport:transport)
            participantService=ParticipantService(configuration:configuration,transport:transport)
            merchantService=MerchantService(configuration:configuration,transport:transport)
            merchantEngagementService=MerchantEngagementService(configuration:configuration,readTransport:transport)
            merchantBusinessService=MerchantBusinessService(configuration:configuration,readTransport:transport)
            cooperationFlowService=CoopFlowService(configuration:configuration,transport:transport)
            merchantOperationsService=MerchantOperationsService(configuration:configuration,transport:transport)
            merchantOnboardingService=MerchantOnboardingService(configuration:configuration,transport:transport)
            clubService=ClubService(configuration:configuration,transport:transport)
            clubManagementService=ClubManagementService(configuration:configuration,transport:transport)
            clubOperationsService=ClubOperationsService(configuration:configuration,transport:transport)
            clubGovernanceService=ClubGovernanceService(configuration:configuration,transport:transport)
            profileEditService=ProfileEditService(configuration:configuration,transport:transport)
            clubActionService=ClubActionService(configuration:configuration,transport:transport)
            roamService=RoamService(configuration:configuration,transport:transport.scopedForManualMap(roamMapSelection))
            roamExperienceService=RoamExperienceService(configuration:configuration,transport:transport)
            messagingService=MessagingService(configuration:configuration,transport:transport)
            messageActionService=MessageActionService(configuration:configuration,transport:transport)
        } else { service=nil;accountSessionService=nil;authChannelService=nil;activityService=nil;searchMapService=nil;registrationBackend=UnconfiguredRegistrationBackend();homeFeedService=nil;orderLifecycleService=nil;ticketWalletService=nil;squareService=nil;socialAccountService=nil;cooperationService=nil;accountCollectionService=nil;officialEventService=nil;growthCenterService=nil;creatorContentService=nil;topicService=nil;discoveryService=nil;profileService=nil;participantService=nil;merchantService=nil;merchantOperationsService=nil;merchantBusinessService=nil;merchantEngagementService=nil;cooperationFlowService=nil;merchantOnboardingService=nil;clubService=nil;clubManagementService=nil;clubOperationsService=nil;clubGovernanceService=nil;profileEditService=nil;clubActionService=nil;roamService=nil;roamExperienceService=nil;messagingService=nil;messageActionService=nil }
        compositionTransport.playReadConfiguration = { [weak self] context in
            guard let self, self.currentRuntimeDependencyContext == context else { return nil }
            // Re-read the reviewed selector at the boundary: retained providers must not
            // keep a revoked read grant alive for an otherwise unchanged viewer.
            return (self.injectedRuntimeDependencies ?? self.composition.sessionDependencies(context)).configuration
        }
        compositionTransport.current = { [weak self] in
            guard let self, !self.committingAuthenticatedSession else { return nil }
            return .init(epoch: self.gate.currentStamp, accountID: self.account?.id,
                         role: self.account?.effectiveRole, token: self.token,
                         viewerRevision: self.compositionViewerRevision)
        }
    }

    private func commitAuthenticatedSession(token: String, account: Account) {
        // Never build account-bound clients with the old account and the new credential.
        committingAuthenticatedSession = true
        self.token = token; self.account = account
        committingAuthenticatedSession = false
        _ = runtimeDependencies
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap=true
        defer { restorationFinished = true; synchronizeAccountMarketingEntry() }
        guard let accountSessionService, accountSessionService.storageScope == storageScope else { return }
        if sessionDefaults.bool(forKey:restoreBlockedKey) {
            try? vault.clear()
            return
        }
        let operation=gate.begin(.bootstrap)
        clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        merchantOnboardingCoordinator.synchronizeSession()
        isWorking=true
        defer { if gate.isCurrent(operation) { isWorking=false;gate.finish(operation) } }
        do {
            guard let saved=try vault.read() else { return }
            let restored=try await accountSessionService.currentAccount(token:saved)
            guard !Task.isCancelled, gate.isCurrent(operation) else { return }
            commitAuthenticatedSession(token: saved, account: restored)
            participantCoordinator.synchronizeSession();synchronizeRegistration()
            clubActionCoordinator.synchronizeSession()
            clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
            merchantOnboardingCoordinator.synchronizeSession()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), gate.isCurrent(operation) else { return }
            if error as? APIError == .unauthorized {
                sessionDefaults.set(true,forKey:restoreBlockedKey)
                try? vault.clear()
            }
            // Offline or server failure never silently deletes a valid saved credential.
            errorKey=Self.messageKey(for:error)
        }
    }

    func login(username:String,password:String) async {
        guard !isWorking, !authChannels.state.isWorking, !weChatAuth.isWorking else { return }
        guard let service else { errorKey="auth.notConfigured";return }
        let operation=gate.begin(.login)
        clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        merchantOnboardingCoordinator.synchronizeSession()
        isWorking=true;errorKey=nil
        defer { if gate.isCurrent(operation) { isWorking=false;gate.finish(operation) } }
        do {
            let result=try await service.login(username:username,password:password)
            guard gate.isCurrent(operation) else { return }
            try vault.write(result.token)
            sessionDefaults.set(false,forKey:restoreBlockedKey)
            commitAuthenticatedSession(token: result.token, account: result.account)
            participantCoordinator.synchronizeSession();synchronizeRegistration()
            clubActionCoordinator.synchronizeSession()
            clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
            merchantOnboardingCoordinator.synchronizeSession()
        } catch {
            guard gate.isCurrent(operation) else { return }
            errorKey=Self.messageKey(for:error)
        }
    }

    func cancelPendingLogin() {
        nativeWeChatPaymentAdapter.cancelPending()
        weChatAuth.cancel()
        // Close must invalidate SMS login immediately, before SwiftUI dismisses its sheet.
        // Transport cancellation is best-effort; the coordinator generation fences late replies.
        authChannels.cancel()
        if gate.cancelLogin() { isWorking=false;errorKey=nil;clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession();merchantOnboardingCoordinator.synchronizeSession() }
    }

    func logout() async {
        nativeWeChatPaymentAdapter.cancelPending()
        weChatAuth.cancel()
        authChannels.cancel()
        let oldToken=token
        gate.invalidate()
        // Persist a non-secret tombstone before deletion. A Keychain failure cannot
        // silently restore a logged-out account at the next cold start.
        sessionDefaults.set(true,forKey:restoreBlockedKey)
        roamArea=nil;searchMapSelection.select(nil);token=nil;account=nil;isWorking=false;errorKey=nil
        participantCoordinator.synchronizeSession();synchronizeRegistration()
        clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        merchantOnboardingCoordinator.synchronizeSession()
        do { try vault.clear() } catch { errorKey="auth.storageError" }
        if let accountSessionService, accountSessionService.storageScope == storageScope, let oldToken {
            // Captured old credential only. Completion cannot mutate a newer login.
            try? await accountSessionService.logout(token:oldToken)
        }
    }

    func activities(page:Int,keyword:String) async throws -> [ActivitySummary] {
        guard let activityService else { throw APIError.notConfigured }
        let stamp=gate.currentStamp, credential=token
        do {
            let result=try await activityService.list(page:page,keyword:keyword,token:credential)
            guard gate.isCurrent(stamp) else { throw CancellationError() }
            return result
        } catch {
            expireIfMatching(error:error,stamp:stamp,credential:credential)
            throw error
        }
    }

    func activityDetail(id:Int) async throws -> ActivityDetailAccess {
        guard account != nil, let credential = token else { throw APIError.unauthorized }
        guard let activityService else { throw APIError.notConfigured }
        let stamp = gate.currentStamp, viewerRevision = compositionViewerRevision
        do {
            let result = try await activityService.detail(id:id,token:credential)
            try Task.checkCancellation()
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision else { throw CancellationError() }
            return result
        } catch {
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision, !Task.isCancelled else { throw CancellationError() }
            expireIfMatching(error:error,stamp:stamp,credential:credential)
            throw error
        }
    }

    private func expireIfMatching(error:Error,stamp:UInt64,credential:String?) {
        guard error as? APIError == .unauthorized, credential != nil,
              gate.isCurrent(stamp), credential == token else { return }
        nativeWeChatPaymentAdapter.cancelPending()
        gate.invalidate()
        sessionDefaults.set(true,forKey:restoreBlockedKey)
        roamArea=nil;searchMapSelection.select(nil);token=nil;account=nil;isWorking=false;errorKey="auth.expired"
        participantCoordinator.synchronizeSession();synchronizeRegistration()
        clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        merchantOnboardingCoordinator.synchronizeSession()
        try? vault.clear()
    }

    private static func messageKey(for error:Error) -> String {
        if error is KeychainTokenStore.StoreError { return "auth.storageError" }
        switch error as? APIError {
        case .notConfigured, .invalidConfiguration: return "auth.notConfigured"
        case .unauthorized: return "auth.expired"
        case .invalidRequest: return "auth.invalidInput"
        case .malformedResponse: return "auth.invalidResponse"
        case .businessCode: return "auth.loginRejected"
        default: return "auth.networkError"
        }
    }
}

// Views never own credentials; every completion is bound to the captured session.
extension AppSession: DiscoveryReading, MerchantReading {
    private func readDiscovery<Value>(expiresSession: Bool = true,
        _ operation:(DiscoveryService,String?) async throws -> Value) async throws -> Value {
        guard let discoveryService else { throw APIError.notConfigured }
        let stamp=gate.currentStamp, credential=token, viewerRevision=compositionViewerRevision
        do {
            let value=try await operation(discoveryService,credential)
            try Task.checkCancellation()
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision else { throw CancellationError() }
            return value
        } catch {
            // Fence identity-only refreshes before unauthorized expiration, including ABA.
            guard gate.isCurrent(stamp), credential == token,
                  viewerRevision == compositionViewerRevision, !Task.isCancelled else { throw CancellationError() }
            if expiresSession { expireIfMatching(error:error,stamp:stamp,credential:credential) }
            throw error
        }
    }
    func discoveryBanners() async throws -> [DiscoveryBanner] { try await readDiscovery { try await $0.banners(token:$1) } }
    func discoveryCategories(type:Int?) async throws -> [DiscoveryCategory] { try await readDiscovery { try await $0.categories(type:type,token:$1) } }
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome { try await readDiscovery { try await $0.templateHome(token:$1) } }
    func discoveryPlayTemplates(keyword:String,packType:DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { try await readDiscovery { try await $0.playTemplates(keyword:keyword,packType:packType,token:$1) } }
    func publicTopicTemplateCoordinator(id: Int) -> PublicTopicTemplateCoordinator {
        makePublicTopicTemplateCoordinator(id: id) { [weak self] id in
            guard let self else { throw CancellationError() }
            // The coordinator expires only an accepted current-generation failure.
            return try await self.readPublicTopicTemplate(id: id, expiresSession: false)
        }
    }
    /// Shared owner construction permits offline lifecycle tests without granting an HTTP route.
    func makePublicTopicTemplateCoordinator(id: Int,
        read: @escaping @MainActor (Int) async throws -> PublicTopicTemplateDetail) -> PublicTopicTemplateCoordinator {
        publicTemplateDetails.synchronize(PublicTemplateViewerContext(
            accountID: account?.id, role: account?.effectiveRole,
            realm: regionalConfiguration?.apiConfiguration?.baseURL.absoluteString ?? "",
            revision: gate.currentStamp))
        let stamp = gate.currentStamp, credential = token, epoch = publicTemplateDetails.epoch
        return publicTemplateDetails.coordinator(id: id, onUnauthorized: { [weak self] in
            guard let self, self.publicTemplateDetails.epoch == epoch else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: stamp, credential: credential)
        }, read: read)
    }
    func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail {
        try await readPublicTopicTemplate(id: id, expiresSession: true)
    }
    private func readPublicTopicTemplate(id: Int, expiresSession: Bool) async throws -> PublicTopicTemplateDetail {
        guard let discoveryService else { throw APIError.notConfigured }
        let stamp = gate.currentStamp, credential = token, epoch = publicTemplateDetails.epoch
        func current() -> Bool {
            gate.isCurrent(stamp) && credential == token && epoch == publicTemplateDetails.epoch
        }
        do {
            let result = try await discoveryService.publicTopicTemplate(id: id, token: credential)
            try Task.checkCancellation()
            guard current() else { throw CancellationError() }
            return result
        } catch {
            // A revoked role's late 401 must not expire the new viewer context.
            guard current(), !Task.isCancelled else { throw CancellationError() }
            if expiresSession { expireIfMatching(error: error, stamp: stamp, credential: credential) }
            throw error
        }
    }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { try await readDiscovery { try await $0.topicTemplates(token:$1) } }
    func publicTopicTemplateCatalogRequest() -> DiscoveryReadRequest<[DiscoveryTopicTemplate]> {
        let stamp = gate.currentStamp, credential = token, viewerRevision = compositionViewerRevision
        return DiscoveryReadRequest(read: { [weak self] in
            guard let self, self.gate.isCurrent(stamp), credential == self.token,
                  viewerRevision == self.compositionViewerRevision else { throw CancellationError() }
            return try await self.readDiscovery(expiresSession: false) { try await $0.topicTemplates(token: $1) }
        }, onUnauthorized: { [weak self] in
            guard let self, viewerRevision == self.compositionViewerRevision else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: stamp, credential: credential)
        })
    }
    func discoveryPlayTemplate(id:Int) async throws -> DiscoveryPlayTemplate { try await readDiscovery { try await $0.playTemplate(id:id,token:$1) } }

    private func readMerchant<Value>(access:MerchantAccess?=nil,_ operation:(MerchantService,String) async throws -> Value) async throws -> Value {
        guard let merchantService else { throw APIError.notConfigured }
        guard account != nil, let credential=token else { throw APIError.unauthorized }
        let stamp=gate.currentStamp
        if let access {
            guard let record=merchantAccessRecord, record.stamp == stamp, record.access == access else { throw MerchantReadError.accessDenied }
        }
        do {
            let value=try await operation(merchantService,credential)
            try Task.checkCancellation()
            guard gate.isCurrent(stamp), credential == token else { throw CancellationError() }
            return value
        } catch {
            guard gate.isCurrent(stamp), credential == token else { throw CancellationError() }
            expireIfMatching(error:error,stamp:stamp,credential:credential)
            throw error
        }
    }
    func merchantAccess() async throws -> MerchantAccess {
        merchantAccessRecord=nil
        let access=try await readMerchant { try await $0.access(token:$1) }
        merchantAccessRecord=(gate.currentStamp,access)
        return access
    }
    func merchantDashboard(access:MerchantAccess) async throws -> MerchantDashboard { try await readMerchant(access:access) { try await $0.dashboard(access:access,token:$1) } }
    func merchantTodo(access:MerchantAccess) async throws -> MerchantTodo { try await readMerchant(access:access) { try await $0.todo(access:access,token:$1) } }
    func merchantEvents(access:MerchantAccess) async throws -> [MerchantEvent] { try await readMerchant(access:access) { try await $0.events(access:access,token:$1) } }
    func merchantOrders(access:MerchantAccess,filter:MerchantOrderFilter) async throws -> [MerchantOrder] { try await readMerchant(access:access) { try await $0.orders(access:access,filter:filter,token:$1) } }
    func merchantProjects(access:MerchantAccess) async throws -> MerchantProjectPage { try await readMerchant(access:access) { try await $0.projects(access:access,token:$1) } }
}

extension AppSession: ClubReading {
    var isClubConfigured: Bool { clubReader.isClubConfigured }
    var clubIdentity: ClubReadIdentity { clubReader.clubIdentity }
    func clubHome() async throws -> ClubHome { try await clubReader.clubHome() }
    func clubOwned() async throws -> [ClubRecord] { try await clubReader.clubOwned() }
    func clubDirectory(name:String?) async throws -> [ClubRecord] { try await clubReader.clubDirectory(name:name) }
    func clubDetail(id:Int) async throws -> ClubRecord { try await clubReader.clubDetail(id:id) }
    func clubMembers(id:Int) async throws -> ClubMemberDirectory { try await clubReader.clubMembers(id:id) }
}

@MainActor private struct UnconfiguredRegistrationBackend:RegistrationCoordinatingService {
    func quote(_ selection:RegistrationQuoteRequest,token:String) async throws -> RegistrationQuote { throw APIError.notConfigured }
    func create(_ intent:RegistrationCreateIntent,token:String) async throws -> RegistrationCreateResult { throw APIError.notConfigured }
    func readStatus(registrationID:Int,token:String) async throws -> RegistrationStatusSnapshot { throw APIError.notConfigured }
}

// Registration intent is navigation only; merchant authorization still comes from access/me.
extension AppSession: MerchantOnboardingObserving {}
