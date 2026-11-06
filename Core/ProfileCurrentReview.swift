import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProfileCurrentReviewFailure: Error, Equatable { case unavailable, stale, invalidResponse, unauthorized }

/// Separate principal-only moderation read approval. Upload/public-media/command
/// permissions cannot satisfy this type; ordinary composition issues none.
@MainActor @Observable public final class ProfileCurrentReviewReadApproval: Equatable {
    public let revision = UUID()
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    public let expiresAt: Date
    public private(set) var revoked = false
    public var identity: ProfileReadIdentity { .init(accountID: context.session.accountID, epoch: context.session.epoch) }
    public var baseURL: URL { context.baseURL }
    public var namespace: String { context.session.namespace }
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.role.utf8.elementsEqual(context.session.role.utf8),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              expiresAt.timeIntervalSince1970.isFinite, expiresAt > Date() else { throw ProfileCurrentReviewFailure.unavailable }
        self.context = context; self.viewerRevision = viewerRevision; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ value: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && ContentDraftContextFence.matches(value, context)
            && value.session.role.utf8.elementsEqual(context.session.role.utf8)
    }
    nonisolated public static func == (lhs: ProfileCurrentReviewReadApproval, rhs: ProfileCurrentReviewReadApproval) -> Bool { lhs === rhs }
}

/// Verified c6 preserves the original fixed58 meaning: this describes the latest RECORDED avatar submission, not a particular
/// displayed image: it returns no avatarRef/hash/ownerId or original-write identity.
public struct ProfileCurrentReviewReceipt: Decodable, Equatable {
    public enum State: String, Decodable { case pending = "PENDING", approved = "APPROVED", rejected = "REJECTED", notSubmitted = "NOT_SUBMITTED" }
    public struct Avatar: Decodable, Equatable {
        public let versionNo: Int
        public let state: State
        public let live: Bool
    }
    public let available: Bool
    public let currentVersion: Int?
    public let avatar: Avatar?
    private enum CodingKeys: String, CodingKey { case available, currentVersion, avatar }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        available = try values.decode(Bool.self, forKey: .available)
        guard available else { currentVersion = nil; avatar = nil; return }
        guard values.contains(.currentVersion), values.contains(.avatar) else { throw ProfileCurrentReviewFailure.invalidResponse }
        currentVersion = try values.decodeIfPresent(Int.self, forKey: .currentVersion)
        avatar = try values.decodeIfPresent(Avatar.self, forKey: .avatar)
        guard currentVersion.map({ $0 > 0 }) ?? true else { throw ProfileCurrentReviewFailure.invalidResponse }
        if let avatar {
            guard avatar.versionNo > 0, let currentVersion, avatar.versionNo <= currentVersion else { throw ProfileCurrentReviewFailure.invalidResponse }
        }
        // submittedAt serialization is unqualified; changedFields lists supplied
        // keys, not actual value changes. Neither is inferred or displayed.
    }
    public var rejectedFact: ProfileCurrentReviewRejectedFact? {
        guard available, let avatar, avatar.state == .rejected else { return nil }
        return .init(versionNo: avatar.versionNo, liveWhenRead: avatar.live)
    }
    public static func decode(_ bytes: Data, status: Int) throws -> Self {
        if status == 401 || status == 403 { throw ProfileCurrentReviewFailure.unauthorized }
        guard bytes.count <= 65_536, let text = String(data: bytes, encoding: .utf8) else { throw ProfileCurrentReviewFailure.invalidResponse }
        _ = try ContentDraftJSON.parse(text)
        struct Status: Decodable { let code: Int }
        let code = try JSONDecoder().decode(Status.self, from: bytes).code
        if code == 401 || code == 403 { throw ProfileCurrentReviewFailure.unauthorized }
        guard status == 200, code == 200 else { throw ProfileCurrentReviewFailure.invalidResponse }
        struct Envelope: Decodable { let data: ProfileCurrentReviewReceipt }
        return try JSONDecoder().decode(Envelope.self, from: bytes).data
    }
}
public struct ProfileCurrentReviewRejectedFact: Equatable {
    public let versionNo: Int
    public let liveWhenRead: Bool
}

/// LOCAL presentation fencing only. sourceDigest is not a server echo, an image
/// moderation join or evidence of a write outcome. Keys contain no credential.
public struct ProfileCurrentReviewReadKey: Hashable {
    public let identity: ProfileReadIdentity
    public let viewerRevision: UInt64
    public let approvalRevision: UUID
    public let sessionScope: UUID
    public let editorID: UUID
    public let lifetimeID: UUID
    public let draftRevision: UInt64
    public let readRevision: Int
    public let sourceDigest: String
}
@MainActor public protocol ProfileCurrentReviewDispatching: AnyObject {
    func send(_ request: URLRequest, authorization: ProfileCurrentReviewAuthorization) async throws -> (Data, Int)
}

/// Single-use final-forward fence; a generic HTTP adapter cannot bypass it.
@MainActor public final class ProfileCurrentReviewAuthorization {
    private let endpoint: URL
    private let token: String
    private let current: () -> Bool
    public private(set) var didForward = false
    init(baseURL: URL, token: String, current: @escaping () -> Bool) {
        self.endpoint = baseURL.appendingPathComponent(ProfileCurrentReviewReader.path)
        self.token = token; self.current = current
    }
    public var isCurrent: Bool { !Task.isCancelled && current() }
    public func accepts(_ request: URLRequest) -> Bool {
        guard request.url?.absoluteString.utf8.elementsEqual(endpoint.absoluteString.utf8) == true,
              endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(token.utf8) == true,
              request.value(forHTTPHeaderField: "Accept") == "application/json" else { return false }
        return (request.allHTTPHeaderFields ?? [:]).keys.allSatisfy { ["authorization", "accept"].contains($0.lowercased()) }
    }
    public func forward(_ request: URLRequest, dispatch: () throws -> Void) throws {
        guard !didForward, accepts(request), isCurrent else { throw ProfileCurrentReviewFailure.stale }
        didForward = true
        try dispatch() // Synchronous task.resume, no suspension after this fence.
    }
}

@MainActor public final class ProfileCurrentReviewReader {
    public static let path = "api/user/profile/review"
    private let baseURL: URL
    private let namespace: String
    private let currentSession: () -> ProfileEditSession?
    private let currentApproval: () -> ProfileCurrentReviewReadApproval?
    private let currentContext: () -> RuntimeDependencyContext?
    private var retired = false
    private let transport: any ProfileCurrentReviewDispatching
    private var observedSession: ProfileEditSession?
    private var observedApproval: ProfileCurrentReviewReadApproval?
    private var observedContext: RuntimeDependencyContext?
    private var scopeID = UUID()
    public init(baseURL: URL, namespace: String, currentSession: @escaping () -> ProfileEditSession?,
                currentApproval: @escaping () -> ProfileCurrentReviewReadApproval?,
                currentContext: @escaping () -> RuntimeDependencyContext?,
                transport: (any ProfileCurrentReviewDispatching)? = nil) {
        self.baseURL = baseURL; self.namespace = namespace; self.currentSession = currentSession
        self.currentApproval = currentApproval; self.currentContext = currentContext
        self.transport = transport ?? ProfileCurrentReviewURLSessionTransport()
    }
    public func retire() { retired = true; scopeID = UUID() }
    private func sameSession(_ lhs: ProfileEditSession?, _ rhs: ProfileEditSession?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs == rhs && lhs.token.utf8.elementsEqual(rhs.token.utf8)
    }
    private func sameApproval(_ lhs: ProfileCurrentReviewReadApproval?, _ rhs: ProfileCurrentReviewReadApproval?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs === rhs && lhs.revision == rhs.revision && lhs.identity == rhs.identity && lhs.viewerRevision == rhs.viewerRevision
            && lhs.baseURL.absoluteString.utf8.elementsEqual(rhs.baseURL.absoluteString.utf8)
            && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8)
    }
    private func sameContext(_ lhs: RuntimeDependencyContext?, _ rhs: RuntimeDependencyContext?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return ContentDraftContextFence.matches(lhs, rhs) && lhs.session.role.utf8.elementsEqual(rhs.session.role.utf8)
    }
    private func context() -> (ProfileEditSession, ProfileCurrentReviewReadApproval)? {
        let session = currentSession(), approval = currentApproval(), live = currentContext()
        if !sameSession(session, observedSession) || !sameApproval(approval, observedApproval) || !sameContext(live, observedContext) {
            scopeID = UUID(); observedSession = session; observedApproval = approval; observedContext = live
        }
        guard !retired, let session, let approval, let live, approval.matches(live),
              approval.context.session.token.utf8.elementsEqual(session.token.utf8),
              approval.identity == session.identity, approval.viewerRevision == session.viewerRevision,
              approval.baseURL.absoluteString.utf8.elementsEqual(baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(namespace.utf8) else { return nil }
        return (session, approval)
    }
    public func key(snapshot: ProfileEditSnapshot, editorID: UUID, lifetimeID: UUID,
                    draftRevision: UInt64, readRevision: Int) -> ProfileCurrentReviewReadKey? {
        guard let (session, approval) = context(), snapshot.id == session.identity.accountID else { return nil }
        return .init(identity: session.identity, viewerRevision: session.viewerRevision, approvalRevision: approval.revision,
            sessionScope: scopeID, editorID: editorID, lifetimeID: lifetimeID, draftRevision: draftRevision,
            readRevision: readRevision, sourceDigest: ProfileAvatarExact.snapshot(snapshot))
    }
    public func read(snapshot: ProfileEditSnapshot, key: ProfileCurrentReviewReadKey,
                     isCurrent: @escaping () -> Bool) async throws -> ProfileCurrentReviewReceipt {
        func matches() -> Bool {
            isCurrent() && self.key(snapshot: snapshot, editorID: key.editorID, lifetimeID: key.lifetimeID,
                draftRevision: key.draftRevision, readRevision: key.readRevision) == key
        }
        guard matches(), let (session, approval) = context() else { throw ProfileCurrentReviewFailure.unavailable }
        let endpoint = baseURL.appendingPathComponent(Self.path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        let authorization = ProfileCurrentReviewAuthorization(baseURL: baseURL, token: session.token, current: matches)
        do {
            try Task.checkCancellation()
            let (bytes, status) = try await transport.send(request, authorization: authorization)
            guard authorization.didForward, authorization.isCurrent else { throw ProfileCurrentReviewFailure.stale }
            return try ProfileCurrentReviewReceipt.decode(bytes, status: status)
        } catch {
            guard authorization.isCurrent, sameSession(currentSession(), session) else { throw ProfileCurrentReviewFailure.stale }
            // A current denial retires this read lease, never the account or an UNKNOWN save.
            if error as? ProfileCurrentReviewFailure == .unauthorized { approval.revoke(); retire() }
            if let api = error as? APIError, [APIError.unauthorized, .httpStatus(401), .httpStatus(403), .businessCode(401), .businessCode(403)].contains(api) { approval.revoke(); retire() }
            throw error
        }
    }
}

/// Accepts no draft, save coordinator, original receipt, journal or navigation
/// callback. Reading current facts cannot resolve an UNKNOWN write.
@MainActor public final class ProfileCurrentReviewFlow {
    public enum State: Equatable { case idle, loading, unavailable, loaded(ProfileCurrentReviewReceipt) }
    public private(set) var state: State = .idle
    private var generation: UInt64 = 0
    private var loadedKey: ProfileCurrentReviewReadKey?
    public init() {}
    public func invalidate() { generation &+= 1; loadedKey = nil; state = .idle }
    public func rejectedFact(for key: ProfileCurrentReviewReadKey?) -> ProfileCurrentReviewRejectedFact? {
        guard let key, key == loadedKey, case .loaded(let receipt) = state else { return nil }
        return receipt.rejectedFact
    }
    public func load(reader: ProfileCurrentReviewReader, snapshot: ProfileEditSnapshot, key: ProfileCurrentReviewReadKey,
                     currentKey: @escaping () -> ProfileCurrentReviewReadKey?) async {
        invalidate()
        guard !Task.isCancelled, currentKey() == key else { return }
        let request = generation; state = .loading
        do {
            let receipt = try await reader.read(snapshot: snapshot, key: key, isCurrent: { [weak self] in
                self?.generation == request && currentKey() == key
            })
            guard !Task.isCancelled, generation == request, currentKey() == key else { return }
            loadedKey = key; state = receipt.available ? .loaded(receipt) : .unavailable
        } catch {
            guard !Task.isCancelled, generation == request, currentKey() == key else { return }
            loadedKey = nil; state = .unavailable
        }
    }
}

/// First-party exact GET: bounded, ephemeral, no redirects/cookies/cache/retry or
/// general-transport fallback. Constructing this adapter grants no read permission.
@MainActor public final class ProfileCurrentReviewURLSessionTransport: ProfileCurrentReviewDispatching {
    public init() {}
    public func send(_ request: URLRequest, authorization: ProfileCurrentReviewAuthorization) async throws -> (Data, Int) {
        guard authorization.accepts(request), authorization.isCurrent else { throw ProfileCurrentReviewFailure.unavailable }
        let exchange = ProfileCurrentReviewExchange(endpoint: request.url!)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                exchange.install(continuation)
                do { try authorization.forward(request) { exchange.start(request) } }
                catch { exchange.fail(error) }
            }
        }, onCancel: { exchange.fail(CancellationError()) })
    }
}
private final class ProfileCurrentReviewExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let endpoint: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private var session: URLSession?
    private var finished = false
    private var failure: Error?
    private var bytes = Data()
    private var status: Int?
    init(endpoint: URL) { self.endpoint = endpoint }
    func install(_ value: CheckedContinuation<(Data, Int), Error>) {
        lock.lock()
        if finished { let error = failure ?? ProfileCurrentReviewFailure.unavailable; lock.unlock(); value.resume(throwing: error); return }
        continuation = value; lock.unlock()
    }
    func start(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCredentialStorage = nil
        config.urlCache = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 20
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session; session.dataTask(with: request).resume()
    }
    func fail(_ error: Error) { finish(.failure(error)) }
    private func finish(_ result: Result<(Data, Int), Error>) {
        lock.lock(); guard !finished else { lock.unlock(); return }
        finished = true; if case .failure(let error) = result { failure = error }
        let completion = continuation, session = session; continuation = nil; self.session = nil
        lock.unlock(); session?.invalidateAndCancel(); completion?.resume(with: result)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil); fail(ProfileCurrentReviewFailure.unavailable)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.expectedContentLength <= 65_536,
              response.url?.absoluteString.utf8.elementsEqual(endpoint.absoluteString.utf8) == true else {
            completionHandler(.cancel); fail(ProfileCurrentReviewFailure.invalidResponse); return
        }
        lock.lock(); status = response.statusCode; let live = !finished; lock.unlock()
        completionHandler(live ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); guard !finished else { lock.unlock(); return }
        guard data.count <= 65_536 - bytes.count else { lock.unlock(); fail(ProfileCurrentReviewFailure.invalidResponse); return }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let data = bytes, code = status; lock.unlock()
        if let error { fail(error) }
        else if let code { finish(.success((data, code))) }
        else { fail(ProfileCurrentReviewFailure.unavailable) }
    }
}
