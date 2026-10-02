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
    public init(accountID: Int, epoch: UInt64, realm: String, token: String) throws {
        guard accountID > 0, !realm.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.realm = realm; self.token = token
    }
}
public enum ContextualReviewFailure: Error, Equatable { case notSent, rejected(Int), unknown }
@MainActor public protocol ContextualReviewWriting {
    var isConfigured: Bool { get }
    var session: ContextualReviewSession? { get }
    func submit(_ draft: ContextualReviewDraft, target: ContextualReviewTarget, session: ContextualReviewSession) async throws
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
    private struct Key: Hashable { let account: Int; let realm: String }
    private var states: [Key: ContextualReviewState] = [:]
    public var state: ContextualReviewState {
        guard let session = writer.session else { return .idle }
        return states[Key(account: session.identity.accountID, realm: session.realm)] ?? .idle
    }
    public var canSubmit: Bool { writer.isConfigured && writer.session != nil && ![.submitting, .unknown, .acknowledged].contains(state) }
    public init(target: ContextualReviewTarget, writer: any ContextualReviewWriting) { self.target = target; self.writer = writer }
    public func submit(_ draft: ContextualReviewDraft, expected: ContextualReviewSession) async {
        guard canSubmit, draft.isValid, writer.session == expected else { return }
        let key = Key(account: expected.identity.accountID, realm: expected.realm)
        states[key] = .submitting
        do {
            try await writer.submit(draft, target: target, session: expected)
            states[key] = writer.session == expected && !Task.isCancelled ? .acknowledged : .unknown
        } catch let error as ContextualReviewFailure {
            switch error { case .notSent: states[key] = .notSent; case .rejected: states[key] = .rejected; case .unknown: states[key] = .unknown }
        } catch { states[key] = .unknown }
    }
}
@MainActor public final class ContextualReviewHost {
    private let writer: any ContextualReviewWriting
    private var owners: [ContextualReviewTarget: ContextualReviewCoordinator] = [:]
    public init(writer: any ContextualReviewWriting) { self.writer = writer }
    public func coordinator(_ target: ContextualReviewTarget) -> ContextualReviewCoordinator {
        if let owner = owners[target] { return owner }
        let owner = ContextualReviewCoordinator(target: target, writer: writer); owners[target] = owner; return owner
    }
}
