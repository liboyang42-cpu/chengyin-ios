import Foundation
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var isWorking = false
    @Published private(set) var errorKey: String?
    private var gate = SessionOperationGate()
    private let vault = KeychainTokenStore()
    private let service: AuthService?
    private let activityService: ActivityService?
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
    private let authChannelService: AuthChannelService?
    var authChannelSnapshot: AuthChannelSessionSnapshot {
        AuthChannelSessionSnapshot(epoch:gate.currentStamp,accountID:account?.id,isBusy:isWorking)
    }
    lazy var authChannels=AuthChannelCoordinator(service:authChannelService,currentSession:{ [weak self] in
        self?.authChannelSnapshot ?? AuthChannelSessionSnapshot(epoch:0,accountID:nil,isBusy:true)
    },commitLogin:{ [weak self] result,expected in
        guard let self, self.authChannelSnapshot == expected, self.account == nil, !self.isWorking else { return false }
        try self.vault.write(result.token)
        self.gate.invalidate()
        UserDefaults.standard.set(false,forKey:self.restoreBlockedKey)
        self.token=result.token;self.account=result.account;self.errorKey=nil
        self.participantCoordinator.synchronizeSession();self.synchronizeRegistration()
        self.clubActionCoordinator.synchronizeSession()
        return true
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
    private let clubService: ClubService?
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
    private let roamService: RoamService?
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
    private var token: String?
    private var didBootstrap = false
    private let restoreBlockedKey = "session.preventRestore"
    var isConfigured: Bool { service != nil }

    init() {
        if let value=Bundle.main.object(forInfoDictionaryKey:"QuestifyAPIBaseURL") as? String,
           let url=URL(string:value), let configuration=try? APIConfiguration(baseURL:url) {
            let transport=URLSessionTransport()
            service=AuthService(configuration:configuration,transport:transport)
            authChannelService=AuthChannelService(configuration:configuration,transport:transport)
            activityService=ActivityService(configuration:configuration,transport:transport)
            registrationBackend=RegistrationService(configuration:configuration,transport:transport)
            playService=PlayService(configuration:configuration,transport:transport)
            discoveryService=DiscoveryService(configuration:configuration,transport:transport)
            profileService=ProfileService(configuration:configuration,transport:transport)
            participantService=ParticipantService(configuration:configuration,transport:transport)
            merchantService=MerchantService(configuration:configuration,transport:transport)
            clubService=ClubService(configuration:configuration,transport:transport)
            clubActionService=ClubActionService(configuration:configuration,transport:transport)
            roamService=RoamService(configuration:configuration,transport:transport)
            messagingService=MessagingService(configuration:configuration,transport:transport)
            messageActionService=MessageActionService(configuration:configuration,transport:transport)
        } else { service=nil;authChannelService=nil;activityService=nil;registrationBackend=UnconfiguredRegistrationBackend();playService=nil;discoveryService=nil;profileService=nil;participantService=nil;merchantService=nil;clubService=nil;clubActionService=nil;roamService=nil;messagingService=nil;messageActionService=nil }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap=true
        guard let service else { return }
        if UserDefaults.standard.bool(forKey:restoreBlockedKey) {
            try? vault.clear()
            return
        }
        let operation=gate.begin(.bootstrap)
        clubActionCoordinator.synchronizeSession()
        isWorking=true
        defer { if gate.isCurrent(operation) { isWorking=false;gate.finish(operation) } }
        do {
            guard let saved=try vault.read() else { return }
            let restored=try await service.currentAccount(token:saved)
            guard gate.isCurrent(operation) else { return }
            token=saved;account=restored
            participantCoordinator.synchronizeSession();synchronizeRegistration()
            clubActionCoordinator.synchronizeSession()
        } catch {
            guard gate.isCurrent(operation) else { return }
            if error as? APIError == .unauthorized {
                UserDefaults.standard.set(true,forKey:restoreBlockedKey)
                try? vault.clear()
            }
            // Offline or server failure never silently deletes a valid saved credential.
            errorKey=Self.messageKey(for:error)
        }
    }

    func login(username:String,password:String) async {
        guard !isWorking, !authChannels.state.isWorking else { return }
        guard let service else { errorKey="auth.notConfigured";return }
        let operation=gate.begin(.login)
        clubActionCoordinator.synchronizeSession()
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
        } catch {
            guard gate.isCurrent(operation) else { return }
            errorKey=Self.messageKey(for:error)
        }
    }

    func cancelPendingLogin() {
        if gate.cancelLogin() { isWorking=false;errorKey=nil;clubActionCoordinator.synchronizeSession() }
    }

    func logout() async {
        authChannels.cancel()
        let oldToken=token
        gate.invalidate()
        // Persist a non-secret tombstone before deletion. A Keychain failure cannot
        // silently restore a logged-out account at the next cold start.
        UserDefaults.standard.set(true,forKey:restoreBlockedKey)
        roamArea=nil;token=nil;account=nil;isWorking=false;errorKey=nil
        participantCoordinator.synchronizeSession();synchronizeRegistration()
        clubActionCoordinator.synchronizeSession()
        do { try vault.clear() } catch { errorKey="auth.storageError" }
        if let service, let oldToken {
            // Captured old credential only. Completion cannot mutate a newer login.
            try? await service.logout(token:oldToken)
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
