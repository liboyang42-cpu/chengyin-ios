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
    public let stateContext: ProjectStateRequestContract.Context?
    public let targetKey: String
    fileprivate init(session: PublishingSession, request: PublishingRequest, baseline: PublishingProject? = nil, action: PublishingProjectAction? = nil, listQuery: PublishingRead? = nil, stateContext: ProjectStateRequestContract.Context? = nil) {
        id = UUID(); self.session = session; self.request = request; self.baseline = baseline; self.action = action; self.listQuery = listQuery; self.stateContext = stateContext
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
    private let activityReceiptApproval: OperationEndpointApproval?
    private let activityRequestStore: PublishingDraftStore?
    private let journal: (any OperationPendingJournal)?
    private var reviews: [UUID: PublishingReview] = [:]
    private var busy = false
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approval: OperationEndpointApproval? = nil, journal: (any OperationPendingJournal)? = nil, activityReceiptApproval: OperationEndpointApproval? = nil, activityRequestStore: PublishingDraftStore? = nil, credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.approval = approval; self.journal = journal; self.credentials = credentials
        self.activityReceiptApproval = activityReceiptApproval; self.activityRequestStore = activityRequestStore
    }
    public var currentSession: PublishingSession? {
        guard let session = credentials()?.session else { reviews.removeAll(); return nil }
        return session
    }
    public var mutationsConfigured: Bool { currentSession != nil && approval != nil && journal != nil && activityRequestStore != nil }
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
        guard let credential = credentials(), credential.session == session,
              activityReceiptApproval?.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID,
                  path: ProjectStateRequestContract.contextPath) == true else { throw PublishModesError.unavailable }
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: ProjectStateRequestContract.contextPath,
            body: JSONEncoder().encode(["kind": ProjectEditJSON.string(project.resource.kind.rawValue), "resourceId": .number(Decimal(project.resource.value))]), token: credential.token)
        let (data, status) = try await transport.send(request); try check(credential)
        let envelope = try ApprovedTopicReleaseWire.envelope(data)
        guard (200..<300).contains(status), envelope["code"]?.integer == 200, let value = envelope["data"] else { throw PublishModesError.unavailable }
        let context = try JSONDecoder().decode(ProjectStateRequestContract.Context.self, from: JSONEncoder().encode(value))
        guard context.matches(project) else { throw PublishModesError.conflict }
        let review = PublishingReview(session: session, request: try PublishingContracts.project(project, action: action), baseline: project, action: action, listQuery: query, stateContext: context)
        reviews[review.id] = review; return review
    }
    public func cancel(_ review: PublishingReview) { reviews.removeValue(forKey: review.id) }
    public func invalidateReviews() { reviews.removeAll() }
    public func hasUncertainOutcome(targetKey: String, session: PublishingSession) throws -> Bool {
        guard currentSession == session else { throw PublishModesError.changedSession }
        if targetKey == "publishModes:activity:create", let saved = try activityRequestStore?.activityRequest(session: session), saved.receipt?.terminal != true { return true }
        if let store = activityRequestStore, try store.stateRequests(session: session).contains(where: { $0.targetKey == targetKey && $0.receipt?.terminal != true }) { return true }
        guard let journal else { return false }
        return try journal.pending(ownerKey: session.storageKey, targetKey: targetKey) != nil
    }
    public func submit(_ review: PublishingReview) async -> PublishingWriteOutcome {
        guard !busy, reviews[review.id] == review, let credential = credentials(), credential.session == review.session,
              activityRequestStore != nil, let journal, let approval, approval.allows(configuration: configuration, namespace: review.session.namespace, accountID: review.session.accountID, path: review.request.path) else { return .notSent }
        busy = true; defer { busy = false }
        let record = OperationPendingRecord(operationID: review.id, ownerKey: review.session.storageKey, targetKey: review.targetKey)
        let request: URLRequest
        var activityEnvelope: ActivityCreateRequestContract.Submit?
        var stateEnvelope: ProjectStateRequestContract.Submit?
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
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { return .unknown }
            if review.baseline == nil {
                let envelope = try ActivityCreateRequestContract.Submit(id: review.id, fields: review.request.fields)
                guard let store = activityRequestStore,
                      approval.allows(configuration: configuration, namespace: review.session.namespace,
                          accountID: review.session.accountID, path: envelope.submitPath) else { return .notSent }
                let previous = try store.activityRequest(session: review.session)
                // Also covers a process death after durable intent but before journal persistence.
                guard previous == nil || previous?.receipt?.terminal == true else { return .unknown }
                try store.saveActivityRequest(.init(ownerKey: review.session.storageKey, submit: envelope), session: review.session, expected: previous)
                activityEnvelope = envelope
                request = try OperationAdapterHTTP.json(configuration: configuration, path: envelope.submitPath,
                    body: JSONEncoder().encode(envelope), token: credential.token)
            } else {
                guard let baseline = review.baseline, let action = review.action, let context = review.stateContext,
                      let kind = PublishedResource.Kind(rawValue: context.kind),
                      let store = activityRequestStore,
                      approval.allows(configuration: configuration, namespace: review.session.namespace, accountID: review.session.accountID,
                          path: ProjectStateRequestContract.submitPath) else { return .notSent }
                let resource = try PublishedResource(kind: kind, value: context.resourceId)
                // Also cover a restart between saving the original request and writing its journal lock.
                guard !(try store.stateRequests(session: review.session)).contains(where: { $0.targetKey == review.targetKey && $0.receipt?.terminal != true }) else { return .unknown }
                let envelope = try ProjectStateRequestContract.Submit(id: review.id, request: review.request, project: baseline, context: context)
                try store.saveStateRequest(.init(ownerKey: review.session.storageKey, title: context.title, resource: resource,
                    action: action, submit: envelope), expected: nil, session: review.session)
                stateEnvelope = envelope
                request = try OperationAdapterHTTP.json(configuration: configuration, path: ProjectStateRequestContract.submitPath,
                    body: JSONEncoder().encode(envelope), token: credential.token)
            }
            try journal.write(record)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { return .unknown }
            reviews.removeValue(forKey: review.id)
        } catch { return .notSent }
        do {
            try check(credential)
            let (data, status) = try await transport.send(request); try check(credential)
            guard (200..<300).contains(status), let envelope = try? ApprovedTopicReleaseWire.envelope(data), let code = envelope["code"]?.integer else { return .unknown }
            if let original = activityEnvelope {
                guard code == 200, let value = envelope["data"], let store = activityRequestStore,
                      let saved = try store.activityRequest(session: review.session), saved.submit == original else { return .unknown }
                let receipt = try JSONDecoder().decode(ActivityCreateRequestContract.Receipt.self, from: JSONEncoder().encode(value))
                guard receipt.matches(original) else { return .unknown }
                try store.saveActivityRequest(.init(ownerKey: saved.ownerKey, submit: original, receipt: receipt), session: review.session, expected: saved)
                guard receipt.terminal else { return .unknown }
                try journal.clear(record)
                return receipt.committed ? .acknowledged : .rejected("原创建请求被拒绝，未创建活动")
            }
            if let original = stateEnvelope {
                guard code == 200, let value = envelope["data"], let store = activityRequestStore,
                      let saved = try store.stateRequest(id: original.requestId, session: review.session) else { return .unknown }
                let receipt = try JSONDecoder().decode(ProjectStateRequestContract.Receipt.self, from: JSONEncoder().encode(value))
                guard receipt.matches(original) else { return .unknown }
                try store.saveStateRequest(.init(ownerKey: saved.ownerKey, title: saved.title, resource: saved.resource, action: saved.action,
                    submit: saved.submit, receipt: receipt), expected: saved, session: review.session)
                guard receipt.terminal else { return .unknown }; try journal.clear(record)
                return receipt.applied ? .acknowledged : .rejected(receipt.originalResult?.object?["msg"]?.text ?? "原请求未改变目标状态")
            }
            return .unknown
        } catch { return .unknown }
    }
    public var canReadActivityReceipt: Bool {
        guard let session = currentSession else { return false }
        guard let saved = try? activityRequestStore?.activityRequest(session: session) else { return false }
        return activityReceiptApproval?.allows(configuration: configuration,
            namespace: session.namespace, accountID: session.accountID, path: saved.submit.readPath) == true
    }
    public func retainedActivityReceipt(session: PublishingSession) throws -> ActivityCreateRequestContract.Receipt? {
        guard currentSession == session else { throw PublishModesError.changedSession }
        return try activityRequestStore?.activityRequest(session: session)?.receipt
    }
    public var canResumeActivityProcessing: Bool {
        guard let session = currentSession else { return false }
        guard let saved = try? activityRequestStore?.activityRequest(session: session) else { return false }
        return approval?.allows(configuration: configuration, namespace: session.namespace,
            accountID: session.accountID, path: saved.submit.resumePath) == true
    }
    public func readActivityOutcome(session: PublishingSession) async throws -> ActivityCreateRequestContract.Receipt {
        try await activityOutcome(session: session, resume: false)
    }
    public func resumeActivityProcessing(session: PublishingSession) async throws -> ActivityCreateRequestContract.Receipt {
        try await activityOutcome(session: session, resume: true)
    }
    private func activityOutcome(session: PublishingSession, resume: Bool) async throws -> ActivityCreateRequestContract.Receipt {
        guard !busy, (resume ? canResumeActivityProcessing : canReadActivityReceipt), let credential = credentials(), credential.session == session,
              let store = activityRequestStore, let saved = try store.activityRequest(session: session),
              let journal else { throw PublishModesError.unavailable }
        busy = true; defer { busy = false }
        if resume {
            guard saved.receipt?.committed == true, saved.receipt?.processing?.canResume == true else { throw PublishModesError.unavailable }
        }
        try check(credential)
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: resume ? saved.submit.resumePath : saved.submit.readPath,
            body: JSONEncoder().encode(ActivityCreateRequestContract.Read(saved.submit)), token: credential.token)
        let (data, status) = try await transport.send(request); try check(credential)
        let envelope = try ApprovedTopicReleaseWire.envelope(data)
        guard (200..<300).contains(status), envelope["code"]?.integer == 200, let value = envelope["data"] else { throw PublishModesError.unavailable }
        let receipt = try JSONDecoder().decode(ActivityCreateRequestContract.Receipt.self, from: JSONEncoder().encode(value))
        guard receipt.matches(saved.submit) else { throw PublishModesError.invalidContract }
        try store.saveActivityRequest(.init(ownerKey: saved.ownerKey, submit: saved.submit, receipt: receipt), session: session, expected: saved)
        if receipt.terminal, let pending = try journal.pending(ownerKey: session.storageKey, targetKey: "publishModes:activity:create") {
            guard pending.operationID.uuidString.lowercased() == saved.submit.requestId else { throw PublishModesError.conflict }
            try journal.clear(pending)
        }
        return receipt
    }
    public func stateRequests(session: PublishingSession) throws -> [ProjectStateRequestContract.Saved] {
        guard currentSession == session else { throw PublishModesError.changedSession }
        return try activityRequestStore?.stateRequests(session: session) ?? []
    }
    public var canReadStateReceipt: Bool {
        guard let session = currentSession else { return false }
        return activityReceiptApproval?.allows(configuration: configuration, namespace: session.namespace,
            accountID: session.accountID, path: ProjectStateRequestContract.readPath) == true
    }
    public func readStateOutcome(_ saved: ProjectStateRequestContract.Saved, session: PublishingSession) async throws -> ProjectStateRequestContract.Receipt {
        guard !busy, canReadStateReceipt, let credential = credentials(), credential.session == session,
              saved.ownerKey == session.storageKey, let store = activityRequestStore, let journal,
              try store.stateRequest(id: saved.id, session: session) == saved else { throw PublishModesError.unavailable }
        busy = true; defer { busy = false }
        try check(credential)
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: ProjectStateRequestContract.readPath,
            body: JSONEncoder().encode(ProjectStateRequestContract.Read(saved.submit)), token: credential.token)
        let (data, status) = try await transport.send(request); try check(credential)
        let envelope = try ApprovedTopicReleaseWire.envelope(data)
        guard (200..<300).contains(status), envelope["code"]?.integer == 200, let value = envelope["data"] else { throw PublishModesError.unavailable }
        let receipt = try JSONDecoder().decode(ProjectStateRequestContract.Receipt.self, from: JSONEncoder().encode(value))
        guard receipt.matches(saved.submit) else { throw PublishModesError.invalidContract }
        try store.saveStateRequest(.init(ownerKey: saved.ownerKey, title: saved.title, resource: saved.resource, action: saved.action,
            submit: saved.submit, receipt: receipt), expected: saved, session: session)
        if receipt.terminal, let pending = try journal.pending(ownerKey: session.storageKey, targetKey: saved.targetKey),
           pending.operationID.uuidString.lowercased() == saved.id { try journal.clear(pending) }
        return receipt
    }
    // No automatic resend, identity mutation, upload or AI-provider entry point is exposed.
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
