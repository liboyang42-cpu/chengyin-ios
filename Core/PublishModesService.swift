import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PublishingCredentials: Equatable {
    public let session: PublishingSession
    let token: String
    public init(session: PublishingSession, token: String) throws {
        guard session.accountID > 0, !session.namespace.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw PublishModesError.changedSession }
        self.session = session; self.token = token
    }
}
public struct PublishingReview: Equatable, Identifiable {
    public let id: UUID
    public let session: PublishingSession
    public let request: PublishingRequest
    public let baseline: PublishingProject?
    public let action: PublishingProjectAction?
    public let listQuery: PublishingRead?
    public let targetKey: String
    fileprivate init(session: PublishingSession, request: PublishingRequest, baseline: PublishingProject? = nil, action: PublishingProjectAction? = nil, listQuery: PublishingRead? = nil) {
        id = UUID(); self.session = session; self.request = request; self.baseline = baseline; self.action = action; self.listQuery = listQuery
        // Create uncertainty is account-wide: regenerating a local draft must not bypass it.
        targetKey = baseline.map { "publishModes:\($0.id)" } ?? "publishModes:activity:create"
    }
}
public enum PublishingWriteOutcome: Equatable { case acknowledged, rejected(String), notSent, unknown }

@MainActor public final class PublishingService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let credentials: () -> PublishingCredentials?
    private let approval: OperationEndpointApproval?
    private let journal: (any OperationPendingJournal)?
    private var reviews: [UUID: PublishingReview] = [:]
    private var busy = false
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approval: OperationEndpointApproval? = nil, journal: (any OperationPendingJournal)? = nil, credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.approval = approval; self.journal = journal; self.credentials = credentials
    }
    public var currentSession: PublishingSession? { credentials()?.session }
    public var mutationsConfigured: Bool { approval != nil && journal != nil }
    private func check(_ credential: PublishingCredentials) throws {
        try Task.checkCancellation(); guard credentials() == credential else { reviews.removeAll(); throw PublishModesError.changedSession }
    }
    private func build(_ descriptor: PublishingRequest, credential: PublishingCredentials) throws -> URLRequest {
        switch descriptor.encoding {
        case .json: return try OperationAdapterHTTP.json(configuration: configuration, path: descriptor.path, body: JSONEncoder().encode(descriptor.fields), token: credential.token)
        case .form, .none:
            var fields: [String: String] = [:]
            for (key, value) in descriptor.fields { guard let text = value.text else { throw PublishModesError.invalidContract }; fields[key] = text }
            return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(descriptor.path), fields: fields, token: credential.token, includesBody: descriptor.encoding != .none)
        }
    }
    public func read(_ query: PublishingRead, session: PublishingSession) async throws -> ProjectEditJSON {
        guard let credential = credentials(), credential.session == session else { throw PublishModesError.changedSession }
        if query == .identityStatus && session.region != .china { throw PublishModesError.unavailable }
        if case .projects(_, _, _, _, let size) = query, !(1...200).contains(size) { throw PublishModesError.invalidDraft }
        try check(credential)
        let request = try build(query.request, credential: credential)
        let response: (Data, Int)
        if let approved = transport as? PublishingApprovedReadTransport {
            response = try await approved.send(request, credential: credential)
        } else { response = try await transport.send(request) }
        let (data, status) = response; try check(credential)
        let envelope = try OperationAdapterHTTP.envelope(data)
        guard (200..<300).contains(status), envelope["code"]?.integer == 200 else { throw PublishModesError.rejected(envelope["msg"]?.text ?? "") }
        return envelope["data"] ?? .null
    }
    /// Only an authoritative Boolean is a status. Unavailable, malformed and stale reads throw.
    public func identityRegistered(session: PublishingSession) async throws -> Bool {
        let result = try await read(.identityStatus, session: session)
        guard currentSession == session else { throw PublishModesError.changedSession }
        guard case .bool(let registered)? = result.object?["registered"] else { throw PublishModesError.invalidContract }
        return registered
    }
    public func prepareActivity(_ draft: ActivityPublishDraft, session: PublishingSession) async throws -> PublishingReview {
        guard session.role == "club" else { throw PublishModesError.forbidden }
        let request = try PublishingContracts.activity(draft)
        let value = try await read(.capability, session: session)
        guard let body = value.object, PublishingCapability(body).activity else { throw PublishModesError.forbidden }
        let review = PublishingReview(session: session, request: request); reviews[review.id] = review; return review
    }
    public func prepareProject(_ project: PublishingProject, action: PublishingProjectAction, query: PublishingRead, session: PublishingSession) async throws -> PublishingReview {
        guard case .projects = query else { throw PublishModesError.invalidContract }
        let page = try PublishingContracts.decodeProjects(await read(query, session: session))
        guard page.rows.first(where: { $0.resource == project.resource }) == project else { throw PublishModesError.conflict }
        let review = PublishingReview(session: session, request: try PublishingContracts.project(project, action: action), baseline: project, action: action, listQuery: query)
        reviews[review.id] = review; return review
    }
    public func cancel(_ review: PublishingReview) { reviews.removeValue(forKey: review.id) }
    public func invalidateReviews() { reviews.removeAll() }
    public func hasUncertainOutcome(targetKey: String, session: PublishingSession) throws -> Bool {
        guard currentSession == session else { throw PublishModesError.changedSession }
        guard let journal else { return false }
        return try journal.pending(ownerKey: session.storageKey, targetKey: targetKey) != nil
    }
    public func submit(_ review: PublishingReview) async -> PublishingWriteOutcome {
        guard !busy, reviews[review.id] == review, let credential = credentials(), credential.session == review.session,
              let journal, let approval, approval.allows(configuration: configuration, namespace: review.session.namespace, accountID: review.session.accountID, path: review.request.path) else { return .notSent }
        busy = true; defer { busy = false }
        let record = OperationPendingRecord(operationID: review.id, ownerKey: review.session.storageKey, targetKey: review.targetKey)
        let request: URLRequest
        do {
            try check(credential)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { return .unknown }
            if let baseline = review.baseline, let action = review.action, let query = review.listQuery {
                let page = try PublishingContracts.decodeProjects(await read(query, session: review.session))
                guard page.rows.first(where: { $0.resource == baseline.resource }) == baseline,
                      try PublishingContracts.project(baseline, action: action) == review.request else { return .notSent }
            } else {
                guard review.request.path == "api/activity/publish", review.session.role == "club" else { return .notSent }
                let value = try await read(.capability, session: review.session)
                guard let body = value.object, PublishingCapability(body).activity else { return .notSent }
            }
            try check(credential)
            // Cancellation or field edits while preflight was suspended invalidate this exact review.
            guard reviews[review.id] == review else { return .notSent }
            request = try build(review.request, credential: credential)
            try journal.write(record)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { return .unknown }
            reviews.removeValue(forKey: review.id)
        } catch { return .notSent }
        do {
            let (data, status) = try await transport.send(request); try check(credential)
            guard (200..<300).contains(status), let envelope = try? OperationAdapterHTTP.envelope(data), let code = envelope["code"]?.integer else { return .unknown }
            // Explicit response is only an immediate acknowledgment, never proof of publication.
            try journal.clear(record)
            return code == 200 ? .acknowledged : .rejected(envelope["msg"]?.text ?? "")
        } catch { return .unknown }
    }
    // No resend/reconcile/identity/upload/AI-provider transport entry point is exposed.
}

@MainActor public protocol PublishingPlaceSearching: AnyObject {
    func search(_ query: String) async throws -> [PublishingPlace]
}
@MainActor public final class PublishingPlaceCoordinator {
    private let provider: any PublishingPlaceSearching
    private var generation = 0
    public private(set) var rows: [PublishingPlace] = []
    public private(set) var selected: PublishingPlace?
    public private(set) var searching = false
    public private(set) var failed = false
    public init(provider: any PublishingPlaceSearching) { self.provider = provider }
    public func search(_ raw: String) async {
        generation += 1; let stamp = generation; selected = nil; rows = []; failed = false
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { searching = false; return }; searching = true
        do { let found = try await provider.search(query); guard stamp == generation else { return }; rows = found; searching = false }
        catch { guard stamp == generation else { return }; failed = true; searching = false }
    }
    public func select(_ place: PublishingPlace) { guard rows.contains(place) else { return }; selected = place }
    public func cancel() { generation += 1; selected = nil; rows = []; searching = false }
}

/// Explicit read approval wrapper used by AppSession. Even a permissive caller cannot
/// route a publication, AI generation or identity registration through this transport.
public final class PublishingApprovedReadTransport: HTTPTransport {
    private let configuration: APIConfiguration
    private let approval: OperationEndpointApproval
    private let transport: any HTTPTransport
    private let currentCredentials: @MainActor () -> PublishingCredentials?
    public init(configuration: APIConfiguration, approval: OperationEndpointApproval, transport: any HTTPTransport,
                currentCredentials: @escaping @MainActor () -> PublishingCredentials?) {
        self.configuration = configuration; self.approval = approval; self.transport = transport; self.currentCredentials = currentCredentials
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        // A bare URLRequest has no trustworthy account/epoch provenance.
        throw PublishModesError.unavailable
    }
    @MainActor public func send(_ request: URLRequest, credential: PublishingCredentials) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard currentCredentials() == credential,
              request.value(forHTTPHeaderField: "Authorization") == credential.token else { throw PublishModesError.changedSession }
        let session = credential.session
        let readPaths = ["api/publish/home", "api/publisher/identity/status", "api/category/list", "api/user/list", "api/template/my-list", "api/project/my", "api/ai/theme/draft/quota"]
        guard request.httpMethod == "POST",
              let path = readPaths.first(where: { configuration.baseURL.appendingPathComponent($0) == request.url }),
              approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: path) else { throw PublishModesError.unavailable }
        let reply = try await transport.send(request)
        try Task.checkCancellation()
        guard currentCredentials() == credential else { throw PublishModesError.changedSession }; return reply
    }
}
