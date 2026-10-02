import Foundation
import Combine
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var account: Account? { willSet { if account?.id != newValue?.id || account?.effectiveRole != newValue?.effectiveRole { invalidateShopNPCConversations(); merchantNPCSessionOwner.invalidate() }; if account?.id != newValue?.id { platformConsumers.invalidate() } } didSet { synchronizeAccountMarketingEntry() } }
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
        return RetainedImageContextCache(configuration: configuration, transport: ResponseLimitedHTTPTransport(),
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
        return RetainedPublicMerchantReviewHost(configuration: configuration, transport: URLSessionTransport(), cache: cache,
            currentSession: { [weak self] in self?.currentPublicMerchantReviewSession })
    }()

    private let merchantNPCSessionOwner = MerchantNPCSessionOwner()
    private let merchantNPCGrants = MerchantNPCGrants()
    private let merchantNPCJournal = OperationDefaultsJournal(defaults: .standard)
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
        guard let configuration = regionalConfiguration?.apiConfiguration else { return .init() }
        return .init(transport: MerchantNPCAuthenticatedTransport(configuration: configuration, transport: URLSessionTransport(), enabled: false,
            currentScope: { [weak self] row in self?.merchantNPCScope(row: row, resource: resource) },
            token: { [weak self] in self?.token }, grants: { [weak self] in self?.merchantNPCGrants ?? .init() }))
    }
    func merchantOperationsDestination(_ destination: MerchantOperationsDestination, access: MerchantOperationsAccess) -> AnyView {
        guard destination == .assets else { return AnyView(MerchantOperationsDocumentView(reader: merchantOperationsReader, destination: destination, imageHost: retainedMerchantImages)) }
        let epoch = merchantOperationsReader.scope
        if merchantNPCAccess?.scope != epoch || merchantNPCAccess?.value != access {
            merchantNPCSessionOwner.invalidate(); merchantNPCAccess = (epoch, access, UUID())
        }
        guard let id = access.identity.merchantID, let row = PublicMerchantRowID(id), access.allows(.assets),
              let captured = merchantNPCScope(row: row, resource: true) else { return AnyView(Text("merchantNPC.unavailable")) }
        let coordinator = MerchantNPCResourcesCoordinator(scope: captured, client: merchantNPCClient(resource: true), reader: merchantOperationsReader,
            journal: merchantNPCJournal, currentScope: { [weak self] in self?.merchantNPCScope(row: row, resource: true) },
            grants: { [weak self] in self?.merchantNPCGrants ?? .init() })
        merchantNPCSessionOwner.register(coordinator)
        return AnyView(MerchantNPCResourceEditor(coordinator: coordinator, imageContext: merchantNPCAvatarContext(captured),
            imageRealm: regionalConfiguration?.apiConfiguration.baseURL.absoluteString, approvedImageHosts: []).id(captured.epoch))
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
    private var publicMerchantHomeReader: any PublicMerchantHomeReading = DisabledPublicMerchantHomeReader()
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
    private var gate = SessionOperationGate()
    private let vault:KeychainTokenStore
    private let storageScope:RegionalSessionStorageScope?
    let regionalConfiguration:RegionalConfiguration?
    var operationalMarket:RegionalMarket? { regionalConfiguration?.market ?? RegionalLaunchConfiguration.market }
    var canUsePassword:Bool { storageScope != nil && regionalConfiguration?.availability(of:.usernamePassword) == .available }
    var supportsDomesticPhoneInput:Bool { operationalMarket == .china }
    private let service: AuthService?
    private let accountSessionService: CNAccountSessionService?
    private let activityService: ActivityService?
    private let searchMapService: SearchMapService?
    private var currentSearchMapContext: SearchMapContext {
        if let account, let token, let context = try? SearchMapContext(accountID: account.id, epoch: gate.currentStamp, token: token) { return context }
        return SearchMapContext(guestEpoch: gate.currentStamp)
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
    })
    private let registrationBackend: any RegistrationCoordinatingService
    private var registrationIdentity: ProfileReadIdentity?
    private lazy var retainedRegistration=RegistrationCoordinator(service:registrationBackend)
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
    private let shopNPCGrants = ShopNPCGrants()
    private let shopNPCProductionWritesEnabled = false
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
        return ShopNPCNodeHost(identity: identity, name: npc.name, greeting: npc.greeting, makeCoordinator: { [weak self, weak runtime] in
            let current: () -> ShopNPCHostSession? = { [weak self, weak runtime] in
                guard let self, let runtime else { return nil }
                return self.currentShopNPCSession(scope: scope, nodeID: nodeID, runtime: runtime, npc: npc)
            }
            let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: configuration, transport: URLSessionTransport(),
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

    private let playService: PlayService?
    private struct PlayReaderKey: Hashable { let accountID:Int?;let scope:PlaySessionScope }
    private var playReaders:[PlayReaderKey:PlaySessionReader]=[:]
    func playReader(for scope:PlaySessionScope) -> PlaySessionReader {
        let key=PlayReaderKey(accountID:account?.id,scope:scope)
        if let reader=playReaders[key] { return reader }
        let reader=PlaySessionReader(scope:scope,service:playService,answersEnabled:false,currentSession:{ [weak self] in
            guard let self,let account=self.account,let token=self.token else { return nil }
            return try? PlayReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
        },onUnauthorized:{ [weak self] snapshot in
            guard let self else { return }
            self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.epoch,credential:self.token)
        })
        playReaders[key]=reader
        return reader
    }
    // Retained scoped runtime; every live capability stays disabled until accepted.
    private var playExperienceCoordinators: [PlayReaderKey: PlayExperienceCoordinator] = [:]
    private let playExperienceRecovery = PlayMemoryCompletionRecovery()
    private let playExperiencePausedStorage = PlayMemoryPausedStorage()
    func playExperience(for scope: PlaySessionScope) -> PlayExperienceCoordinator? {
        guard scope.isValid, let configuration = regionalConfiguration?.apiConfiguration, storageScope != nil else { return nil }
        let key = PlayReaderKey(accountID: account?.id, scope: scope)
        if let retained = playExperienceCoordinators[key] { return retained }
        let api = PlayExperienceService(configuration: configuration, transport: URLSessionTransport())
        let coordinator = PlayExperienceCoordinator(scope: scope, service: api,
            recovery: playExperienceRecovery, pausedStorage: playExperiencePausedStorage,
            currentSession: { [weak self] in
                guard let self, let account = self.account, let token = self.token, let namespace = self.storageScope?.service else { return nil }
                return try? PlayExperienceSession(accountID: account.id, epoch: self.gate.currentStamp, namespace: namespace, token: token)
            }, onUnauthorized: { [weak self] snapshot in
                guard let self else { return }
                self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.epoch, credential: self.token)
            })
        playExperienceCoordinators[key] = coordinator
        return coordinator
    }
    // Journey extras are independent of task completion, advanced games and local dice.
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
        guard let configuration = regionalConfiguration?.apiConfiguration, storageScope != nil else { return nil }
        return JourneyContentService(configuration: configuration, transport: URLSessionTransport())
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
    private var currentPlayRuntimeSession: PlayExperienceSession? {
        guard let account, let token, let namespace = storageScope?.service else { return nil }
        return try? PlayExperienceSession(accountID: account.id, epoch: gate.currentStamp, namespace: namespace, token: token)
    }
    private func dormantPlayRuntimeService() -> PlayExperienceService? {
        guard let configuration = regionalConfiguration?.apiConfiguration, storageScope != nil else { return nil }
        return PlayExperienceService(configuration: configuration, transport: URLSessionTransport())
    }
    private func playRuntimeKey(_ scope: PlaySessionScope, suffix: String) -> String {
        "\(storageScope?.service ?? "none"):\(gate.currentStamp):\(account?.id ?? 0):\(scope.fields.keys.sorted().joined()):\(scope.id):\(suffix)"
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
        let model = PlayPrefabRuntimeCoordinator(scope: scope, service: api, provider: PlayDormantDeviceProvider(),
            store: prefabRuntimeStore, currentSession: { [weak self] in self?.currentPlayRuntimeSession })
        retainedPlayPrefabs[key] = model; return model
    }
    private var retainedPlayStillness: [String: PlayStillnessCoordinator] = [:]
    func playStillness(scope: PlaySessionScope, nodeID: Int, configuration: PlayStillnessConfiguration) -> PlayStillnessCoordinator? {
        guard scope.isValid, nodeID > 0 else { return nil }
        let key = playRuntimeKey(scope, suffix: "stillness:\(nodeID):\(configuration.durationSeconds):\(configuration.tolerance)")
        if let retained = retainedPlayStillness[key] { return retained }
        let model = PlayStillnessCoordinator(configuration: configuration, provider: PlayDormantMotionProvider(), currentContext: { [weak self] in
            guard let session = self?.currentPlayRuntimeSession else { return nil }
            return try? PlayDeviceContext(session: session, scope: scope, nodeID: nodeID)
        })
        retainedPlayStillness[key] = model; return model
    }
    // Session-owned dormant hosts. Identity/epoch keys prevent reuse after logout.
    private var retainedPlayPlayers: [String: PlayPlayerGameCoordinator] = [:]
    private var retainedPlayCircles: [String: PlayCircleCoordinator] = [:]
    private var retainedPlayDevices: [String: PlayDeviceCaptureCoordinator] = [:]
    let playNativeDeviceProvider = PlayNativeDeviceProvider(grants: [])
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
        let model = PlayDeviceCaptureCoordinator(provider: playNativeDeviceProvider, filter: PlayNativePhotoFilter.render,
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
    // Native App WeChat host: no SDK, transport, or live/legal grants by default.
    private var weChatContext: WeChatAppAuthContext {
        WeChatAppAuthContext(session: AuthChannelSessionSnapshot(epoch: gate.currentStamp,
            accountID: account?.id, isBusy: isWorking || authChannels.state.isWorking),
            market: operationalMarket, namespace: storageScope?.service)
    }
    lazy var weChatAuth = WeChatAppAuthCoordinator(context: { [weak self] in
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
        UserDefaults.standard.set(false,forKey:self.restoreBlockedKey)
        self.token=result.token;self.account=result.account;self.errorKey=nil
        self.participantCoordinator.synchronizeSession();self.synchronizeRegistration()
        self.clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
        self.merchantOnboardingCoordinator.synchronizeSession()
        return true
    }
    // Official writes remain dormant. This host permits review only; no write transport is wired.
    private var retainedOfficialActions: OfficialActionCoordinator?
    var officialActionCoordinator: OfficialActionCoordinator? {
        if let retainedOfficialActions { return retainedOfficialActions }
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = root.appendingPathComponent("OfficialActionSafety", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return nil }
        let access = OfficialActionInjectedAccess(current: { [weak self] in
            guard let self, let account = self.account, self.currentOfficialContext.isAuthenticated, let storageScope = self.storageScope else { return nil }
            return OfficialActionIdentity(accountID: account.id, epoch: self.officialEventReader.scope, namespace: storageScope.service)
        }, read: { [weak self] command in
            guard let self, let account = self.account, self.currentOfficialContext.isAuthenticated, let storageScope = self.storageScope else { throw OfficialActionFailure.forbidden }
            let identity = OfficialActionIdentity(accountID: account.id, epoch: self.officialEventReader.scope, namespace: storageScope.service)
            let reader = self.officialEventReader
            switch command {
            case .publish:
                return OfficialActionSnapshot(identity: identity, publisher: try await reader.canPublish())
            case .broadcast(let draft):
                let allowed = try await reader.canPublish()
                var event: OfficialEvent?
                if let id = draft.eventID { event = try await reader.myPublished().events.first { $0.id == id } }
                return OfficialActionSnapshot(identity: identity, publisher: allowed, event: event)
            case .signup(let id), .complete(let id):
                return OfficialActionSnapshot(identity: identity, event: try await reader.detail(id: id))
            case .respond(let id, let type, _, _):
                let permission = type == "OFFICIAL" ? try await reader.canPublish() : false
                let invite = try await reader.partyInbox().first { $0.id == id }
                return OfficialActionSnapshot(identity: identity, publisher: permission, invite: invite)
            case .arrival, .inviteMerchants:
                // Needs approved current roam/session/location or verified merchant candidate integration.
                throw OfficialActionFailure.disabled
            }
        }, write: { _ in throw OfficialActionFailure.disabled })
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
    private var retainedProjectEditors: [Int: ProjectEditCoordinator] = [:]
    private lazy var projectDraftStore = ProjectEditLocalStore(storage: ProjectEditSecureStorage(scope: storageScope))
    private var currentProjectEditSession: ProjectEditSession? {
        guard let account, token != nil, let storageScope else { return nil }
        return try? ProjectEditSession(accountID: account.id, epoch: gate.currentStamp, storageNamespace: storageScope.service)
    }
    func projectEditor(product: ProjectEditProduct) -> ProjectEditCoordinator {
        if let retained = retainedProjectEditors[product.rawValue] { return retained }
        let coordinator = ProjectEditCoordinator(initial: .init(draft: ProjectEditDraft(product: product)),
            service: ProjectEditDisabledService(), store: projectDraftStore,
            currentSession: { [weak self] in self?.currentProjectEditSession })
        retainedProjectEditors[product.rawValue] = coordinator
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
        let context = PublisherLifecycleHostContext(configuration: configuration, transport: URLSessionTransport(), creatorReader: creatorContentReader,
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
    lazy var publishingService: PublishingService? = makePublishingService()
    lazy var publishingDraftStore = PublishingDraftStore(storage: ProjectEditSecureStorage(scope: storageScope))
    /// Production mounts no read grant or write approval. An approved integration may inject
    /// a read transport; the returned service still has no mutation approval or journal.
    func makePublishingService(readApproval: OperationEndpointApproval? = nil,
                               transport: any HTTPTransport = URLSessionTransport()) -> PublishingService? {
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
    var couponManagementSession: CouponManagementSession? {
        guard let account, token != nil, let storageScope else { return nil }
        return try? CouponManagementSession(accountID: account.id, namespace: storageScope.service,
                                             epoch: gate.currentStamp, authorizationRevision: account.effectiveRole)
    }
    private lazy var couponManagementLocks = CouponManagementAppLocks()
    /// Source permissions and endpoint approval are separate. No live read/write grant is installed.
    lazy var couponManagementCoordinator = makeCouponManagementCoordinator()
    func makeCouponManagementCoordinator(readApproval: OperationEndpointApproval? = nil,
                                         transport: any HTTPTransport = URLSessionTransport(),
                                         publisher: (any CouponPublisherAuthorizing)? = nil) -> CouponManagementCoordinator {
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
    func makeWalletCommerceReader(readApproval: OperationEndpointApproval? = nil,
                                  transport: any HTTPTransport = URLSessionTransport()) -> WalletCommerceReader {
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
    lazy var objectCardReader = ObjectCardSessionReader(service: nil,
        currentSession: { [weak self] in self?.currentObjectCardSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentObjectCardSession == captured else { return }
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
    // Runtime writes remain off. Source transport adapter exists separately for isolated contract tests.
    lazy var socialActionAccess = SocialDisabledActionAccess(reader: squareReader, accountReader: socialAccountReader)
    lazy var socialActionCoordinator = SocialActionCoordinator(access: socialActionAccess)
    // Explicit media-origin approval and bounded streaming are required before live preview reads.
    lazy var socialMessageMediaReader = SocialMessageMediaReader(service: nil, currentIdentity: { [weak self] in self?.messagingReader.identity })
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
    private var retainedSquareGovernance: SquareGovernanceCoordinator?
    func squareGovernance() -> SquareGovernanceCoordinator? {
        if let model = retainedSquareGovernance { return model }
        guard let configuration = regionalConfiguration?.apiConfiguration else { return nil }
        let model = SquareGovernanceCoordinator(service: .init(baseURL: configuration.baseURL, transport: URLSessionTransport()))
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
                let post = try await self.squareReader.squareDetail(id: postID)
                guard self.currentSquareGovernanceIdentity == captured, self.squareReader.scope == readScope, post.id == postID else { throw CancellationError() }
                let page = try await self.squareReader.squareComments(postID: postID, pageNumber: 1)
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
                                   transport: any HTTPTransport = URLSessionTransport()) -> NearbyTeamCoordinator {
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
            reader = TeamReadOnlyService(configuration: configuration, transport: URLSessionTransport(),
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
        return try? OrderLifecycleSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var orderLifecycleReader = OrderLifecycleSessionReader(service: orderLifecycleService,
        currentSession: { [weak self] in self?.currentOrderLifecycleSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentOrderLifecycleSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    // One retained coordinator keeps per-account/order unknown-outcome locks across sheets.
    // The dormant command adapter is deliberately not constructed by AppSession.
    lazy var orderLifecycleCoordinator = OrderLifecycleCoordinator(reader: orderLifecycleReader)
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
        return try? TopicReadSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var topicReader=TopicSessionReader(service:topicService,currentSession:{ [weak self] in
        self?.currentTopicSession
    },onUnauthorized:{ [weak self] snapshot in
        guard let self,self.currentTopicSession == snapshot else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:snapshot.epoch,credential:self.token)
    })
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
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantBusinessSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    lazy var merchantExportRecovery = MerchantExportFileRecoveryStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/MerchantBusiness/export-tasks-v1.json"))
    private let merchantBusinessService: MerchantBusinessService?
    private var currentMerchantBusinessSession: MerchantBusinessSession? {
        guard let account, let token else { return nil }
        return try? MerchantBusinessSession(accountID: account.id, epoch: gate.currentStamp, token: token)
    }
    lazy var merchantBusinessReader = MerchantBusinessSessionReader(service: merchantBusinessService,
        currentSession: { [weak self] in self?.currentMerchantBusinessSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantBusinessSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
    lazy var merchantBusinessJournal = MerchantBusinessFileIntentStore(
        url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((storageScope?.service ?? "unconfigured") + "/MerchantBusiness/intents-v1.json"))
    private var currentMerchantContentSession: MerchantContentSession? {
        guard let account, let token, let storageScope else { return nil }
        return try? MerchantContentSession(accountID: account.id, epoch: gate.currentStamp,
            storageScope: storageScope.service, token: token)
    }
    lazy var merchantContentService = MerchantContentService(configuration: regionalConfiguration?.apiConfiguration,
        transport: URLSessionTransport(), currentSession: { [weak self] in self?.currentMerchantContentSession },
        onUnauthorized: { [weak self] captured in
            guard let self, self.currentMerchantContentSession == captured else { return }
            self.expireIfMatching(error: APIError.unauthorized, stamp: captured.epoch, credential: self.token)
        })
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
        return try? MerchantOperationsSession(accountID: account.id, epoch: gate.currentStamp, token: token, storageNamespace: storageScope?.service ?? "")
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
    }, onUnauthorized: { [weak self] identity in
        guard let self, self.currentClubGovernanceSession?.identity == identity else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: identity.epoch, credential: self.token)
    })
    // Session-lived: unresolved operations cannot be replayed by reopening a sheet.
    lazy var clubGovernanceCoordinator = ClubGovernanceCoordinator(access: clubGovernanceAccess)
    var clubGovernanceContext: ClubGovernanceContext { .init(access: clubGovernanceAccess, coordinator: clubGovernanceCoordinator) }
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
    private let profileEditService:ProfileEditService?
    private var currentProfileEditSession:ProfileEditSession? {
        guard let account,let token else { return nil }
        return try? ProfileEditSession(accountID:account.id,epoch:gate.currentStamp,token:token)
    }
    lazy var profileEditCoordinator=ProfileEditCoordinator(service:profileEditService,currentSession:{ [weak self] in self?.currentProfileEditSession },onUnauthorized:{ [weak self] captured in
        guard let self,self.currentProfileEditSession == captured else { return }
        self.expireIfMatching(error:APIError.unauthorized,stamp:captured.identity.epoch,credential:self.token)
    },onSaved:{ [weak self] in Task { await self?.refreshOwnAccount() } })
    private func refreshOwnAccount() async {
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
    lazy var imExpandedWriter = IMExpandedWriter(service: nil, session: { [weak self] in
        guard let self, let account = self.account, let token = self.token else { return nil }
        return try? IMExpandedSession(accountID: account.id, epoch: self.gate.currentStamp, token: token)
    }, onUnauthorized: { [weak self] snapshot in
        guard let self else { return }
        self.expireIfMatching(error: APIError.unauthorized, stamp: snapshot.identity.epoch, credential: self.token)
    })
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
        }), journal: imageUploadJournal, target: target)
        imImageCoordinators[scope] = owner; return owner
    }
    func imConversationStarter() -> IMConversationStarter? {
        guard let identity = imExpandedWriter.identity else { return nil }
        if let existing = imStarters[identity] { return existing }
        let owner = IMConversationStarter(identity: identity, writer: imExpandedWriter)
        imStarters[identity] = owner; return owner
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
    @Published var roamArea: RoamSearchArea?
    lazy var roamReader=RoamSessionReader(service:roamService,currentSession:{ [weak self] in
        guard let self, let account=self.account, let token=self.token else { return nil }
        return try? RoamReadSession(accountID:account.id,epoch:self.gate.currentStamp,token:token)
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
        let service = AccountComplianceService(configuration: configuration, transport: URLSessionTransport(),
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
            transport: URLSessionTransport(), gates: .init(reads: false, insight: false, settlement: false), locks: nil,
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
        let service = DoorReferralService(configuration: configuration, transport: URLSessionTransport(), scanEnabled: false, bindingEnabled: false,
            currentSession: { [weak self] in self?.doorReferralSession ?? DoorReferralSession(accountID: nil, epoch: UUID(), token: nil, restored: false) })
        retainedDoorQueue = DoorReferralQueue(store: DoorReferralFileStore(url: directory.appendingPathComponent("referrals-v1.json")), service: service,
            currentSession: { [weak self] in self?.doorReferralSession ?? DoorReferralSession(accountID: nil, epoch: UUID(), token: nil, restored: false) })
        retainedDoorCoordinator = DoorEntryCoordinator(session: doorReferralSession, service: service)
    }
    var doorReferralQueue: DoorReferralQueue? { prepareDoorRuntime(); return retainedDoorQueue }
    var doorEntryCoordinator: DoorEntryCoordinator? { prepareDoorRuntime(); return retainedDoorCoordinator }
    func receiveNativeURL(_ url: URL) {
        guard let intent = nativeEntryLinkPolicy.parse(url) else { return }
        receiveNativeIntent(intent)
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
        let identityChanged = entryObservedStamp != gate.currentStamp || entryObservedAccountID != account?.id || entryObservedToken != token || entryObservedRole != account?.effectiveRole
        if identityChanged {
            publicMerchantReviewEpoch = UUID(); retainedPublicMerchantReviews?.invalidate(); retainedImageContextCache?.invalidate()
            retainedPublisherLifecycle?.context.invalidate(); retainedPublisherLifecycle = nil
            merchantNPCSessionOwner.invalidate(); merchantNPCAccess = nil
            invalidateShopNPCConversations()
            platformConsumers.invalidate()
            publicMerchantHomeReader = DisabledPublicMerchantHomeReader()
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

    private var token: String? { willSet { if token != newValue { invalidateShopNPCConversations(); platformConsumers.invalidate() } } didSet { synchronizeAccountMarketingEntry() } }
    private var didBootstrap = false
    private let restoreBlockedKey:String
    var isConfigured: Bool { storageScope != nil }

    init() {
        let regional=RegionalLaunchConfiguration.configuration
        regionalConfiguration=regional
        let scope=regional.flatMap { try? RegionalSessionStorageScope(configuration:$0,
            bundleIdentifier:Bundle.main.bundleIdentifier,
            realm:Bundle.main.object(forInfoDictionaryKey:"QuestifySessionRealm") as? String) }
        storageScope=scope
        vault=KeychainTokenStore(scope:scope)
        restoreBlockedKey=scope?.restoreBlockedKey ?? "session.unconfigured.preventRestore"
        // An endpoint alone cannot authorize restoring/sending a persisted credential.
        if let scope, let regional, let configuration=regional.apiConfiguration {
            let transport=URLSessionTransport()
            accountSessionService=try? CNAccountSessionService(configuration:regional,storageScope:scope,transport:transport)
            service=regional.availability(of:.usernamePassword) == .available ? AuthService(configuration:configuration,transport:transport) : nil
            authChannelService=regional.canUseDomesticChinaPhone ? AuthChannelService(configuration:configuration,transport:transport) : nil
            searchMapService=SearchMapService(configuration:configuration,transport:transport)
            activityService=ActivityService(configuration:configuration,transport:transport)
            registrationBackend=RegistrationService(configuration:configuration,transport:transport)
            playService=PlayService(configuration:configuration,transport:transport)
            homeFeedService=HomeFeedService(configuration:configuration,transport:transport)
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
            roamService=RoamService(configuration:configuration,transport:transport)
            roamExperienceService=RoamExperienceService(configuration:configuration,transport:transport)
            messagingService=MessagingService(configuration:configuration,transport:transport)
            messageActionService=MessageActionService(configuration:configuration,transport:transport)
        } else { service=nil;accountSessionService=nil;authChannelService=nil;activityService=nil;searchMapService=nil;registrationBackend=UnconfiguredRegistrationBackend();playService=nil;homeFeedService=nil;orderLifecycleService=nil;ticketWalletService=nil;squareService=nil;socialAccountService=nil;cooperationService=nil;accountCollectionService=nil;officialEventService=nil;growthCenterService=nil;creatorContentService=nil;topicService=nil;discoveryService=nil;profileService=nil;participantService=nil;merchantService=nil;merchantOperationsService=nil;merchantBusinessService=nil;merchantEngagementService=nil;cooperationFlowService=nil;merchantOnboardingService=nil;clubService=nil;clubManagementService=nil;clubOperationsService=nil;clubGovernanceService=nil;profileEditService=nil;clubActionService=nil;roamService=nil;roamExperienceService=nil;messagingService=nil;messageActionService=nil }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap=true
        defer { restorationFinished = true; synchronizeAccountMarketingEntry() }
        guard let accountSessionService, accountSessionService.storageScope == storageScope else { return }
        if UserDefaults.standard.bool(forKey:restoreBlockedKey) {
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
            token=saved;account=restored
            participantCoordinator.synchronizeSession();synchronizeRegistration()
            clubActionCoordinator.synchronizeSession()
            clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession()
            merchantOnboardingCoordinator.synchronizeSession()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), gate.isCurrent(operation) else { return }
            if error as? APIError == .unauthorized {
                UserDefaults.standard.set(true,forKey:restoreBlockedKey)
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
            UserDefaults.standard.set(false,forKey:restoreBlockedKey)
            token=result.token;account=result.account
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
        weChatAuth.cancel()
        if gate.cancelLogin() { isWorking=false;errorKey=nil;clubActionCoordinator.synchronizeSession()
        clubManagementCoordinator.synchronizeSession();clubOperationsCoordinator.synchronizeSession();clubGovernanceCoordinator.cancelReview();profileEditCoordinator.synchronizeSession();merchantOnboardingCoordinator.synchronizeSession() }
    }

    func logout() async {
        weChatAuth.cancel()
        authChannels.cancel()
        let oldToken=token
        gate.invalidate()
        // Persist a non-secret tombstone before deletion. A Keychain failure cannot
        // silently restore a logged-out account at the next cold start.
        UserDefaults.standard.set(true,forKey:restoreBlockedKey)
        roamArea=nil;token=nil;account=nil;isWorking=false;errorKey=nil
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
        guard let activityService else { throw APIError.notConfigured }
        let stamp=gate.currentStamp, credential=token
        do {
            let result=try await activityService.detail(id:id,token:credential)
            guard gate.isCurrent(stamp) else { throw CancellationError() }
            return result
        } catch {
            expireIfMatching(error:error,stamp:stamp,credential:credential)
            throw error
        }
    }

    private func expireIfMatching(error:Error,stamp:UInt64,credential:String?) {
        guard error as? APIError == .unauthorized, credential != nil,
              gate.isCurrent(stamp), credential == token else { return }
        gate.invalidate()
        UserDefaults.standard.set(true,forKey:restoreBlockedKey)
        roamArea=nil;token=nil;account=nil;isWorking=false;errorKey="auth.expired"
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
    private func readDiscovery<Value>(_ operation:(DiscoveryService,String?) async throws -> Value) async throws -> Value {
        guard let discoveryService else { throw APIError.notConfigured }
        let stamp=gate.currentStamp, credential=token
        do {
            let value=try await operation(discoveryService,credential)
            try Task.checkCancellation()
            guard gate.isCurrent(stamp), credential == token else { throw CancellationError() }
            return value
        } catch {
            guard gate.isCurrent(stamp), credential == token else { throw CancellationError() }
            expireIfMatching(error:error,stamp:stamp,credential:credential)
            throw error
        }
    }
    func discoveryBanners() async throws -> [DiscoveryBanner] { try await readDiscovery { try await $0.banners(token:$1) } }
    func discoveryCategories(type:Int?) async throws -> [DiscoveryCategory] { try await readDiscovery { try await $0.categories(type:type,token:$1) } }
    func discoveryTemplateHome() async throws -> DiscoveryTemplateHome { try await readDiscovery { try await $0.templateHome(token:$1) } }
    func discoveryPlayTemplates(keyword:String,packType:DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { try await readDiscovery { try await $0.playTemplates(keyword:keyword,packType:packType,token:$1) } }
    func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { try await readDiscovery { try await $0.topicTemplates(token:$1) } }
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
