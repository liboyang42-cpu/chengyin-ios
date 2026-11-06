import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public-viewer scope, not membership or governance authority. A guest has a real
/// epoch and no partial/restoring credentials. No token is exposed in this value.
public struct ClubPublicTopicsContext: Equatable, Hashable {
    public let identity: ClubReadIdentity
    public let viewerRevision: UInt64
    public let role: String?
    public let baseURL: URL
    public let namespace: String
    public init(identity: ClubReadIdentity, viewerRevision: UInt64, role: String?, baseURL: URL, namespace: String) {
        self.identity = identity; self.viewerRevision = viewerRevision; self.role = role
        self.baseURL = baseURL; self.namespace = namespace
    }
}

/// Independently issued read capability for exactly one club's detail/topics.
/// Never authorizes members, access/me, sessions, paid data or any mutation.
public struct ClubPublicTopicsApproval: Equatable, Hashable {
    public let context: ClubPublicTopicsContext
    public let clubID: Int
    public let revision: UUID
    public init(context: ClubPublicTopicsContext, clubID: Int, revision: UUID) {
        self.context = context; self.clubID = clubID; self.revision = revision
    }
}

public struct ClubPublicTopicsSession: Equatable {
    public let context: ClubPublicTopicsContext
    public let membershipRevision: UInt64
    fileprivate let token: String?
    public init(context: ClubPublicTopicsContext, membershipRevision: UInt64, token: String?) throws {
        guard !context.namespace.isEmpty else { throw APIError.notConfigured }
        if let account = context.identity.accountID {
            guard account > 0, let role = context.role, !role.isEmpty,
                  let token, AuthRequestBuilder.isValidToken(token) else { throw APIError.unauthorized }
        } else {
            guard context.role == nil, token == nil else { throw APIError.unauthorized }
        }
        self.context = context; self.membershipRevision = membershipRevision; self.token = token
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.context == rhs.context && lhs.membershipRevision == rhs.membershipRevision &&
            lhs.token.map { Data($0.utf8) } == rhs.token.map { Data($0.utf8) }
    }
}

public struct ClubPublicTopicsScope: Equatable, Hashable {
    public let approval: ClubPublicTopicsApproval
    public let membershipRevision: UInt64
    /// A value container only. Reader.scope validates current session and issuance.
    public init(approval: ClubPublicTopicsApproval, membershipRevision: UInt64) {
        self.approval = approval; self.membershipRevision = membershipRevision
    }
}

/// Only display rows survive decoding; no private/raw topic payload escapes.
public struct ClubPublicTopicsSnapshot: Equatable {
    public let scope: ClubPublicTopicsScope
    public let rows: [ClubActivityRow]
    public let observedAt: Date
}

/// Recognize exact original JSON read shapes; no URL prefix or extra fields.
public struct ClubPublicTopicsRoute {
    public let clubID: Int
    public let isTopics: Bool
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              !(request.allHTTPHeaderFields ?? [:]).keys.contains(where: { $0.lowercased().hasPrefix("x-club-") }),
              let bytes = request.httpBody, bytes.count <= 128,
              let fields = try? JSONDecoder().decode([String: ClubGovernanceValue].self, from: bytes),
              Set(fields.keys) == ["id"], case .integer(let id)? = fields["id"], id > 0,
              let canonical = try? JSONSerialization.data(withJSONObject: ["id": id], options: [.sortedKeys]),
              bytes == canonical,
              let url = request.url, url.query == nil, url.fragment == nil else { return nil }
        if url == baseURL.appendingPathComponent("api/club/topics") { isTopics = true }
        else if url == baseURL.appendingPathComponent("api/club/detail") { isTopics = false }
        else { return nil }
        clubID = id
    }
}

@MainActor public final class ClubPublicTopicsReader {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let currentSession: () -> ClubPublicTopicsSession?
    private let approval: (ClubPublicTopicsContext, Int) -> ClubPublicTopicsApproval?
    private let onUnauthorized: (ClubPublicTopicsSession) -> Void
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                currentSession: @escaping () -> ClubPublicTopicsSession?,
                approval: @escaping (ClubPublicTopicsContext, Int) -> ClubPublicTopicsApproval?,
                onUnauthorized: @escaping (ClubPublicTopicsSession) -> Void = { _ in }) {
        self.configuration = configuration; self.transport = transport; self.currentSession = currentSession
        self.approval = approval; self.onUnauthorized = onUnauthorized
    }
    public func scope(clubID: Int) -> ClubPublicTopicsScope? {
        guard clubID > 0, let session = currentSession(), session.context.baseURL == configuration.baseURL,
              let issued = approval(session.context, clubID), issued.context == session.context,
              issued.clubID == clubID else { return nil }
        return .init(approval: issued, membershipRevision: session.membershipRevision)
    }
    public func isCurrent(_ snapshot: ClubPublicTopicsSnapshot) -> Bool {
        scope(clubID: snapshot.scope.approval.clubID) == snapshot.scope
    }
    public func read(clubID: Int, isCurrent: @escaping () -> Bool) async throws -> ClubPublicTopicsSnapshot {
        guard let session = currentSession(), let scope = scope(clubID: clubID),
              scope.approval.context == session.context else { throw APIError.notConfigured }
        func check() throws {
            guard !Task.isCancelled, isCurrent(), currentSession() == session,
                  self.scope(clubID: clubID) == scope else { throw CancellationError() }
        }
        do {
            try check()
            // Original endpoint performs canViewClub and selectPublicCmsTopicList
            // using the actual optional viewer. Never call access/me or infer active.
            var request = try AuthRequestBuilder.makeFormRequest(
                url: configuration.baseURL.appendingPathComponent("api/club/topics"),
                fields: [:], token: session.token, includesBody: false)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = try JSONSerialization.data(withJSONObject: ["id": clubID], options: [.sortedKeys])
            try check()
            let (bytes, status) = try await transport.send(request)
            try check()
            guard bytes.count <= 4 * 1024 * 1024 else { throw APIError.malformedResponse }
            let envelope = try? JSONDecoder().decode(Status.self, from: bytes)
            if status == 401 || envelope?.code == 401 { throw ClubReadFailure.unauthorized(message: envelope?.msg) }
            if status == 403 || envelope?.code == 403 { throw ClubReadFailure.forbidden(message: envelope?.msg) }
            guard (200..<300).contains(status) else { throw ClubReadFailure.httpStatus(status, message: envelope?.msg) }
            guard let envelope else { throw APIError.malformedResponse }
            guard envelope.code == 200 else { throw ClubReadFailure.rejected(code: envelope.code, message: envelope.msg) }
            guard let values = try? JSONDecoder().decode(Envelope.self, from: bytes).data else { throw APIError.malformedResponse }
            let now = Date()
            var ids = Set<Int>()
            let rows = try values.map { value -> ClubActivityRow in
                guard value.object != nil, let id = value["id"].int, id > 0,
                      ids.insert(id).inserted else { throw APIError.malformedResponse }
                // The mapper includes active execution-cooperation topics whose
                // owning clubId can differ. Do not invent an equality/membership gate.
                return ClubActivityRow(value: value, id: id, now: now)
            }
            // Visibility may change while topics are loading. Recheck the original
            // detail endpoint with the SAME viewer, never retry a refusal as guest.
            let detail = try await ClubService(configuration: configuration, transport: transport).detail(id: clubID, token: session.token)
            try check()
            guard !detail.viewerIdentityUnavailable else { throw ClubReadFailure.forbidden(message: nil) }
            return .init(scope: scope, rows: rows, observedAt: now)
        } catch {
            try check()
            if (error as? ClubReadFailure)?.isUnauthorized == true, session.context.identity.isSignedIn { onUnauthorized(session) }
            throw error
        }
    }
    private struct Status: Decodable {
        let code: Int
        let msg: String?
        enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            msg = try? c.decode(String.self, forKey: .msg)
        }
    }
    private struct Envelope: Decodable { let data: [ClubGovernanceValue] }
}
