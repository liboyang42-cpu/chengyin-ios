import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Topic and activity IDs remain separate even when their integer values happen to match.
public enum ContextualReviewTarget: Hashable {
    case topic(Int), activity(Int)
    public var ownerType: Int { if case .topic = self { return 1 }; return 2 }
    public var ownerID: Int { switch self { case .topic(let id), .activity(let id): return id } }
}
public struct ContextualReviewDraft: Equatable {
    public var rating: Int
    public var contents: String
    public init(rating: Int = 0, contents: String = "") { self.rating = rating; self.contents = contents }
    public var isValid: Bool { (1...5).contains(rating) && !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && contents.utf16.count <= 500 }
    public func fields(target: ContextualReviewTarget) throws -> [String: String] {
        guard isValid, target.ownerID > 0 else { throw APIError.invalidRequest }
        return ["owner_type": String(target.ownerType), "owner_id": String(target.ownerID),
                "rating": String(rating), "contents": contents.trimmingCharacters(in: .whitespacesAndNewlines), "reply_id": "0", "img_arr": ""]
    }
}
public struct ContextualReviewSession: Equatable {
    public let identity: ProfileReadIdentity
    public let realm: String
    let token: String
    public private(set) var runtimeContext: RuntimeDependencyContext?
    public init(accountID: Int, epoch: UInt64, realm: String, token: String) throws {
        guard accountID > 0, !realm.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.realm = realm; self.token = token
    }
    public init(context: RuntimeDependencyContext) throws {
        try self.init(accountID: context.session.accountID, epoch: context.session.epoch,
                      realm: context.baseURL.absoluteString, token: context.session.token)
        runtimeContext = context
    }
    var replayOwnerKey: String {
        let namespace = runtimeContext?.session.namespace ?? ""
        return "\(realm.utf8.count):\(realm)|\(namespace.utf8.count):\(namespace)|\(identity.accountID)"
    }

}
public enum ContextualReviewFailure: Error, Equatable { case notSent, rejected(Int), unknown }
@MainActor public protocol ContextualReviewWriting {
    var isConfigured: Bool { get }
    var requiresDurableJournal: Bool { get }
    var session: ContextualReviewSession? { get }
    func submit(_ draft: ContextualReviewDraft, target: ContextualReviewTarget, session: ContextualReviewSession) async throws
    func submit(_ draft: ContextualReviewDraft, target: ContextualReviewTarget, session: ContextualReviewSession, authorization: ContextualOperationAuthorization) async throws
}
extension ContextualReviewWriting {
    public var requiresDurableJournal: Bool { false }
    public func submit(_ draft: ContextualReviewDraft, target: ContextualReviewTarget, session: ContextualReviewSession, authorization: ContextualOperationAuthorization) async throws {
        try await submit(draft, target: target, session: session)
    }
}
@MainActor public struct ContextualReviewHTTPWriter: ContextualReviewWriting {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentSession: () -> ContextualReviewSession?
    public let isConfigured: Bool
    public var session: ContextualReviewSession? { currentSession() }
    /// Explicit disabled default; an account or an API URL never grants review writes.
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false,
                currentSession: @escaping () -> ContextualReviewSession?) {
        self.configuration = configuration; self.transport = transport; self.isConfigured = enabled; self.currentSession = currentSession
    }
    public func submit(_ draft: ContextualReviewDraft, target: ContextualReviewTarget, session: ContextualReviewSession) async throws {
        guard isConfigured, currentSession() == session, session.realm == configuration.baseURL.absoluteString, !Task.isCancelled else { throw ContextualReviewFailure.notSent }
        let request: URLRequest
        do { request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/comment/add"), fields: draft.fields(target: target), token: session.token) }
        catch { throw ContextualReviewFailure.notSent }
        do {
            let (data, status) = try await transport.send(request)
            guard currentSession() == session, !Task.isCancelled else { throw ContextualReviewFailure.unknown }
            struct Envelope: Decodable { let code: Int }
            guard let result = try? JSONDecoder().decode(Envelope.self, from: data) else { throw ContextualReviewFailure.unknown }
            // Only a successfully delivered AjaxResult rejection is definitive. Proxy/timeouts
            // (including 408/499), contradictory non-2xx envelopes and server errors remain unknown.
            if (200..<300).contains(status), result.code != 200 { throw ContextualReviewFailure.rejected(result.code) }
            guard (200..<300).contains(status), result.code == 200 else { throw ContextualReviewFailure.unknown }
        } catch let error as ContextualReviewFailure { throw error }
        catch { throw ContextualReviewFailure.unknown }
    }
}
public enum ContextualReviewState: Equatable { case idle, submitting, acknowledged, notSent, rejected, unknown }
/// Retained by the session factory across sheet dismissals. Comment/add has no idempotency
/// contract; unknown outcomes are locked by account+realm+target and never blindly retried.
@MainActor public final class ContextualReviewCoordinator {
    public let target: ContextualReviewTarget
    public let writer: any ContextualReviewWriting
    private struct Key: Hashable { let owner: String }
    private var states: [Key: ContextualReviewState] = [:]
    private let journal: (any OperationPendingJournal)?
    private var targetKey: String { "contextual-review|\(target.ownerType)|\(target.ownerID)" }
    public var state: ContextualReviewState {
        guard let session = writer.session else { return .idle }
        let key = Key(owner: session.replayOwnerKey)
        if states[key] == .submitting { return .submitting }
        do {
            if let record = try journal?.pending(ownerKey: session.replayOwnerKey, targetKey: targetKey) {
                return record.acknowledgedSteps > 0 ? .acknowledged : .unknown
            }
        } catch { return .unknown }
        return states[key] ?? .idle
    }
    public var canSubmit: Bool { writer.isConfigured && (!writer.requiresDurableJournal || journal != nil) && writer.session != nil && ![.submitting, .unknown, .acknowledged].contains(state) }
    public init(target: ContextualReviewTarget, writer: any ContextualReviewWriting, journal: (any OperationPendingJournal)? = nil) {
        self.target = target; self.writer = writer; self.journal = journal
    }
    public func submit(_ draft: ContextualReviewDraft, expected: ContextualReviewSession) async {
        guard canSubmit, draft.isValid, writer.session == expected else { return }
        let key = Key(owner: expected.replayOwnerKey)
        var record = OperationPendingRecord(ownerKey: expected.replayOwnerKey, targetKey: targetKey)
        do { try journal?.write(record) } catch { states[key] = .notSent; return }
        states[key] = .submitting
        do {
            let authorization = ContextualOperationAuthorization(command: .review(target, draft), owner: expected.replayOwnerKey) {
                guard let journal = self.journal else { return false }
                return try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record
            }
            try await writer.submit(draft, target: target, session: expected, authorization: authorization)
            states[key] = writer.session == expected && !Task.isCancelled ? .acknowledged : .unknown
        } catch let error as ContextualReviewFailure {
            switch error { case .notSent: states[key] = .notSent; case .rejected: states[key] = .rejected; case .unknown: states[key] = .unknown }
        } catch { states[key] = .unknown }
        do {
            if states[key] == .acknowledged { record.acknowledgedSteps = 1; try journal?.write(record) }
            else if states[key] == .notSent || states[key] == .rejected { try journal?.clear(record) }
        } catch { states[key] = .unknown }
    }
}
@MainActor public final class ContextualReviewHost {
    private let writer: any ContextualReviewWriting
    private var owners: [ContextualReviewTarget: ContextualReviewCoordinator] = [:]
    private let journal: (any OperationPendingJournal)?
    public init(writer: any ContextualReviewWriting, journal: (any OperationPendingJournal)? = nil) { self.writer = writer; self.journal = journal }
    public func coordinator(_ target: ContextualReviewTarget) -> ContextualReviewCoordinator {
        if let owner = owners[target] { return owner }
        let owner = ContextualReviewCoordinator(target: target, writer: writer, journal: journal); owners[target] = owner; return owner
    }
}
