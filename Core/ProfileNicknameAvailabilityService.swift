import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProfileNicknameCheck: Equatable { case available, taken, invalid }
public enum ProfileNicknameSuggestionFailure: Error, Equatable { case invalid, exhausted }
public enum ProfileNicknameReadFailure: Error, Equatable { case unavailable, stale, invalidResponse, unauthorized }
public struct ProfileNicknameSuggestion: Equatable { public let nickname: String; public let cursor: Int? }

/// c6 Java String.trim removes code points <= U+0020, not every Unicode whitespace.
/// These are read-input rules only; the existing editor/save normalization is unchanged.
public enum ProfileNicknameRules {
    public static func normalize(_ value: String) -> String {
        let scalars = value.unicodeScalars
        var start = scalars.startIndex, end = scalars.endIndex
        while start < end && scalars[start].value <= 0x20 { start = scalars.index(after: start) }
        while start < end {
            let previous = scalars.index(before: end)
            guard scalars[previous].value <= 0x20 else { break }; end = previous
        }
        return String(scalars[start..<end])
    }
    public static func issue(_ raw: String) -> String? {
        let value = normalize(raw)
        guard !value.isEmpty else { return "nickname.read.invalid.empty" }
        guard value.unicodeScalars.count >= 2 else { return "nickname.read.invalid.short" }
        guard value.unicodeScalars.count <= 24 else { return "nickname.read.invalid.long" }
        guard value.range(of: "\\A[\\p{L}\\p{N}_#\\-.· ]+\\z", options: .regularExpression) != nil else { return "nickname.read.invalid.characters" }
        return nil
    }
}

/// Dedicated temporary reads; no reservation, nickname command, or write authority.
@MainActor @Observable public final class ProfileNicknameReadApproval {
    public let revision = UUID(), context: RuntimeDependencyContext, viewerRevision: UInt64, expiresAt: Date
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.role.utf8.elementsEqual(context.session.role.utf8),
              expiresAt.timeIntervalSince1970.isFinite, expiresAt > Date() else { throw ProfileNicknameReadFailure.unavailable }
        self.context=context; self.viewerRevision=viewerRevision; self.expiresAt=expiresAt
    }
    public func revoke() { revoked=true }
    public func matches(_ value: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && ContentDraftContextFence.matches(value,context)
            && value.session.role.utf8.elementsEqual(context.session.role.utf8)
    }
}

@MainActor public protocol ProfileNicknameAvailabilityReading: AnyObject {
    var identity: ProfileReadIdentity? { get }
    var viewerRevision: UInt64? { get }
    var sourceRevision: UUID? { get }
    var isConfigured: Bool { get }
    func check(_ nickname: String) async throws -> ProfileNicknameCheck
    func suggest(_ base: String, cursor: Int?) async throws -> ProfileNicknameSuggestion
}
@MainActor public protocol ProfileNicknameDispatching: AnyObject {
    func send(_ request: URLRequest, authorization: ProfileNicknameReadAuthorization) async throws -> (Data,Int)
}
/// Exact prepared read request, single-use at synchronous task.resume. No generic adapter.
@MainActor public final class ProfileNicknameReadAuthorization {
    private let expected: URLRequest
    private let current: () -> Bool
    public private(set) var didForward=false
    fileprivate init(expected: URLRequest, current: @escaping () -> Bool) { self.expected=expected; self.current=current }
    public var isCurrent: Bool { !Task.isCancelled && current() }
    public func accepts(_ r: URLRequest) -> Bool {
        r.url?.absoluteString.utf8.elementsEqual(expected.url!.absoluteString.utf8) == true && r.httpMethod == "POST"
            && r.httpBody == expected.httpBody && r.httpBodyStream == nil && !r.httpShouldHandleCookies
            && r.allHTTPHeaderFields == expected.allHTTPHeaderFields
    }
    public func forward(_ request: URLRequest, dispatch: () throws -> Void) throws {
        guard !didForward, accepts(request), isCurrent else { throw ProfileNicknameReadFailure.stale }
        didForward=true; try dispatch()
    }
}

@MainActor public final class ProfileNicknameAvailabilityReader: ProfileNicknameAvailabilityReading {
    private let approval: ProfileNicknameReadApproval
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentSession: () -> ProfileEditSession?
    private let selected: () -> ProfileNicknameReadApproval?
    private let transport: any ProfileNicknameDispatching
    private var retired=false
    public init(approval: ProfileNicknameReadApproval, currentContext: @escaping () -> RuntimeDependencyContext?,
                currentSession: @escaping () -> ProfileEditSession?, selected: @escaping () -> ProfileNicknameReadApproval?,
                transport: (any ProfileNicknameDispatching)? = nil) {
        self.approval=approval;self.currentContext=currentContext;self.currentSession=currentSession;self.selected=selected
        self.transport=transport ?? ProfileNicknameURLSessionTransport()
    }
    public func retire() { retired=true }
    public var isConfigured: Bool {
        guard !retired else { return false }
        guard selected() === approval, let c=currentContext(), approval.matches(c),let s=currentSession(),
              s.identity.accountID == c.session.accountID, s.identity.epoch == c.session.epoch,
              s.token.utf8.elementsEqual(c.session.token.utf8), s.viewerRevision == approval.viewerRevision else {
            retired=true; return false
        }
        return true
    }
    public var identity: ProfileReadIdentity? { isConfigured ? currentSession()?.identity : nil }
    public var viewerRevision: UInt64? { isConfigured ? approval.viewerRevision : nil }
    public var sourceRevision: UUID? { isConfigured ? approval.revision : nil }
    private struct Value: Decodable { let nickname: String; let available: Bool; let errorCode: String?; let cursor: Int? }
    private struct Envelope: Decodable { let code: Int; let errorCode: String?; let data: Value? }
    private func read(_ path: String, fields: [String:String]) async throws -> Envelope {
        guard isConfigured else { throw ProfileNicknameReadFailure.unavailable }
        var r=try AuthRequestBuilder.makeFormRequest(url:approval.context.baseURL.appendingPathComponent(path),fields:fields,token:approval.context.session.token)
        r.httpShouldHandleCookies=false;r.cachePolicy = .reloadIgnoringLocalCacheData
        guard (r.httpBody?.count ?? Int.max) <= 4096 else { throw ProfileNicknameReadFailure.invalidResponse }
        let auth=ProfileNicknameReadAuthorization(expected:r,current:{[weak self] in self?.isConfigured == true})
        do {
            try Task.checkCancellation()
            let (data,status)=try await transport.send(r,authorization:auth)
            guard auth.didForward,auth.isCurrent else { throw ProfileNicknameReadFailure.stale }
            if status == 401 || status == 403 { throw ProfileNicknameReadFailure.unauthorized }
            guard data.count <= 65_536,let text=String(data:data,encoding:.utf8) else { throw ProfileNicknameReadFailure.invalidResponse }
            _=try ContentDraftJSON.parse(text)
            struct Status: Decodable { let code: Int }
            let code=try JSONDecoder().decode(Status.self,from:data).code
            if code == 401 || code == 403 { throw ProfileNicknameReadFailure.unauthorized }
            let value=try JSONDecoder().decode(Envelope.self,from:data)
            guard status == 200 else { throw ProfileNicknameReadFailure.invalidResponse }
            return value
        } catch {
            guard auth.isCurrent else { throw ProfileNicknameReadFailure.stale }
            if error as? ProfileNicknameReadFailure == .unauthorized { approval.revoke();retire() }
            throw error
        }
    }
    public func check(_ nickname: String) async throws -> ProfileNicknameCheck {
        let input=ProfileNicknameRules.normalize(nickname)
        guard ProfileNicknameRules.issue(input) == nil else { return .invalid }
        let result=try await read("api/user/nickname/check",fields:["nickname":input])
        guard result.code == 200,result.errorCode == nil,let value=result.data,value.nickname.utf8.elementsEqual(input.utf8) else { throw ProfileNicknameReadFailure.invalidResponse }
        if value.available && value.errorCode == nil { return .available }
        if !value.available && value.errorCode == "NICKNAME_TAKEN" { return .taken }
        if !value.available && value.errorCode == "NICKNAME_INVALID" { return .invalid }
        throw ProfileNicknameReadFailure.invalidResponse
    }
    public func suggest(_ base: String,cursor: Int?) async throws -> ProfileNicknameSuggestion {
        let input=ProfileNicknameRules.normalize(base)
        guard ProfileNicknameRules.issue(input) == nil else { throw ProfileNicknameSuggestionFailure.invalid }
        var fields=["baseName":input]
        if let cursor { guard (0..<1_679_616).contains(cursor) else { throw ProfileNicknameReadFailure.invalidResponse };fields["cursor"]=String(cursor) }
        let result=try await read("api/user/nickname/suggest",fields:fields)
        if result.code == 400 && result.errorCode == "NICKNAME_INVALID" { throw ProfileNicknameSuggestionFailure.invalid }
        if result.code == 400 && result.errorCode == "NICKNAME_SUFFIX_EXHAUSTED" { throw ProfileNicknameSuggestionFailure.exhausted }
        guard result.code == 200,result.errorCode == nil,let value=result.data,value.available,value.errorCode == nil,
              let next=value.cursor,(1..<1_679_616).contains(next),
              ProfileNicknameRules.issue(value.nickname) == nil,
              value.nickname.utf8.elementsEqual(ProfileNicknameRules.normalize(value.nickname).utf8) else { throw ProfileNicknameReadFailure.invalidResponse }
        // Validate the original producer's response relation without locally offering a generated name.
        let suffix=String(next,radix:36,uppercase:true), padded=String(repeating:"0",count:4-suffix.count)+suffix
        let stripped=input.replacingOccurrences(of:"#[0-9A-Z]{4}$",with:"",options:.regularExpression)
        let prefix=String(String.UnicodeScalarView(Array(stripped.unicodeScalars.prefix(19))))
        let distance=(next-(cursor ?? 0)+1_679_616)%1_679_616
        guard (1...128).contains(distance),value.nickname.utf8.elementsEqual((prefix+"#"+padded).utf8) else { throw ProfileNicknameReadFailure.invalidResponse }
        return .init(nickname:value.nickname,cursor:next)
    }
}

/// First-party exact POST reads: bounded, ephemeral, no redirects/cookies/cache/retry or
/// general-transport fallback. Constructing this adapter grants no read permission.
@MainActor public final class ProfileNicknameURLSessionTransport: ProfileNicknameDispatching {
    public init() {}
    public func send(_ request: URLRequest, authorization: ProfileNicknameReadAuthorization) async throws -> (Data, Int) {
        guard authorization.accepts(request), authorization.isCurrent else { throw ProfileNicknameReadFailure.unavailable }
        let exchange = ProfileNicknameExchange(endpoint: request.url!)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                exchange.install(continuation)
                do { try authorization.forward(request) { exchange.start(request) } }
                catch { exchange.fail(error) }
            }
        }, onCancel: { exchange.fail(CancellationError()) })
    }
}
private final class ProfileNicknameExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
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
        if finished { let error = failure ?? ProfileNicknameReadFailure.unavailable; lock.unlock(); value.resume(throwing: error); return }
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
        completionHandler(nil); fail(ProfileNicknameReadFailure.unavailable)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.expectedContentLength <= 65_536,
              response.url?.absoluteString.utf8.elementsEqual(endpoint.absoluteString.utf8) == true else {
            completionHandler(.cancel); fail(ProfileNicknameReadFailure.invalidResponse); return
        }
        lock.lock(); status = response.statusCode; let live = !finished; lock.unlock()
        completionHandler(live ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); guard !finished else { lock.unlock(); return }
        guard data.count <= 65_536 - bytes.count else { lock.unlock(); fail(ProfileNicknameReadFailure.invalidResponse); return }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let data = bytes, code = status; lock.unlock()
        if let error { fail(error) }
        else if let code { finish(.success((data, code))) }
        else { fail(ProfileNicknameReadFailure.unavailable) }
    }
}
