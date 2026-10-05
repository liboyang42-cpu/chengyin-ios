import Foundation

/// Independently reviewed deployment grant, deliberately absent from shipped configuration.
/// Scope includes one session/activity, explicit tickets, storefront, legal version and expiry.
/// This is local activation evidence, never a replacement for server authorization.
public enum RegistrationApprovedProduct: Equatable { case physicalActivity }

public struct RegistrationProductionApproval: Equatable {
    public let product: RegistrationApprovedProduct
    public let endpoint: OperationEndpointApproval
    public let identity: ProfileReadIdentity
    public let market: RegionalMarket
    public let storefront: String
    public let activityID: Int
    public let ticketIDs: Set<Int>
    public let consentVersion: String
    public let noticeURL: URL
    public let expiresAt: Date
    public static let registrationPaths: Set<String> = ["api/registration/quote", "api/registration/create", "api/registration/info", "api/compliance/consents/latest", "api/compliance/consents"]
    public static let waitlistPaths: Set<String> = ["api/club/event-ops/waitlist/status", "api/club/event-ops/waitlist/join", "api/club/event-ops/waitlist/cancel"]
    public init(endpoint: OperationEndpointApproval, identity: ProfileReadIdentity,
                market: RegionalMarket, storefront: String, product: RegistrationApprovedProduct, activityID: Int, ticketIDs: Set<Int>,
                consentVersion: String, noticeURL: URL, expiresAt: Date) throws {
        // Existing contact validation and checkout contract are CN-specific. US requires its
        // own accepted contract; locale selection must not grant an alternate storefront.
        guard market == .china, storefront == "CHN", identity.accountID == endpoint.accountID,
              activityID > 0, !ticketIDs.isEmpty, ticketIDs.allSatisfy({ $0 > 0 }),
              !consentVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.registrationPaths.isSubset(of: endpoint.paths),
              endpoint.paths.isSubset(of: Self.registrationPaths.union(Self.waitlistPaths)),
              noticeURL.scheme == "https", noticeURL.host != nil,
              noticeURL.user == nil, noticeURL.password == nil, noticeURL.fragment == nil else { throw APIError.invalidConfiguration }
        self.product = product
        self.endpoint = endpoint; self.identity = identity; self.market = market; self.storefront = storefront
        self.activityID = activityID; self.ticketIDs = ticketIDs; self.consentVersion = consentVersion
        self.noticeURL = noticeURL; self.expiresAt = expiresAt
    }
    public func permits(identity: ProfileReadIdentity?, activityID: Int, ticketID: Int?, now: Date) -> Bool {
        identity == self.identity && activityID == self.activityID && ticketID.map(ticketIDs.contains) == true && now < expiresAt
    }
}

public struct RegistrationProductionSession: Equatable {
    public let identity: ProfileReadIdentity
    public let namespace: String
    public let market: RegionalMarket
    public let storefront: String
    let token: String
    public init(identity: ProfileReadIdentity, namespace: String, market: RegionalMarket, storefront: String, token: String) throws {
        guard identity.accountID > 0, !namespace.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.identity = identity; self.namespace = namespace; self.market = market; self.storefront = storefront; self.token = token
    }
}

/// Real transport factory. There is no production Bool, fixture switch, token persistence,
/// consent auto-agreement, retry or payment dispatch. The app supplies no grant by default.
@MainActor public enum RegistrationProductionFactory {
    public static func make(configuration: APIConfiguration, approval: RegistrationProductionApproval?,
                            journal: any OperationPendingJournal,
                            current: @escaping () -> RegistrationProductionSession?) -> RegistrationProductionService? {
        guard let approval, approval.endpoint.baseURL == configuration.baseURL else { return nil }
        return RegistrationProductionService(configuration: configuration, approval: approval,
            transport: URLSessionTransport(), journal: journal, current: current)
    }
}

public enum RegistrationPendingFailure: Error { case waitlistUnknown, busy }
public enum RegistrationDurableCreation: Equatable { case none, pending(registrationID: Int?) }
@MainActor public protocol RegistrationPendingServing {
    func creationLock(_ scope: RegistrationWaitlistScope) throws -> RegistrationDurableCreation
    func readRetainedStatus(_ scope: RegistrationWaitlistScope) async throws -> RegistrationStatusSnapshot
}

@MainActor public protocol RegistrationLegalServing {
    /// Call only after the user reads the approved notice and explicitly chooses agreement.
    func agreeToSignupNotice(_ scope: RegistrationWaitlistScope) async throws
}

@MainActor public final class RegistrationProductionService: RegistrationCoordinatingService, RegistrationWaitlistServing, RegistrationLegalServing, RegistrationPendingServing {
    public let approval: RegistrationProductionApproval
    private let configuration: APIConfiguration
    private let registration: RegistrationService
    private let waitlist: RegistrationWaitlistService
    private let transport: any HTTPTransport
    private let journal: any OperationPendingJournal
    private let current: () -> RegistrationProductionSession?
    private let now: () -> Date
    private var quoteGeneration: UInt64 = 0
    private var mutatingWaitlistScopes: Set<RegistrationWaitlistScope> = []
    private var lastQuote: (selection: RegistrationQuoteRequest, quote: RegistrationQuote, receivedAt: Date)?
    // Internal injected transport exists for deterministic tests; public factory always uses real transport.
    init(configuration: APIConfiguration, approval: RegistrationProductionApproval, transport: any HTTPTransport,
         journal: any OperationPendingJournal, current: @escaping () -> RegistrationProductionSession?, now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.approval = approval; self.transport = transport
        registration = .init(configuration: configuration, transport: transport)
        waitlist = .init(configuration: configuration, transport: transport)
        self.journal = journal; self.current = current; self.now = now
    }
    private var ownerKey: String { "registration|\(approval.endpoint.namespace)|\(approval.market.rawValue)|\(approval.endpoint.baseURL.absoluteString)|\(approval.identity.accountID)" }
    private func scope(_ selection: RegistrationQuoteRequest) throws -> RegistrationWaitlistScope {
        guard let ticketID = selection.ticketID else { throw APIError.invalidRequest }
        return try .init(activityID: selection.ownerID, ticketID: ticketID)
    }
    private func check(_ scope: RegistrationWaitlistScope, path: String, token: String? = nil) throws -> RegistrationProductionSession {
        try Task.checkCancellation()
        guard let session = current(), session.identity == approval.identity,
              session.namespace == approval.endpoint.namespace, session.market == approval.market,
              session.storefront == approval.storefront, token == nil || token == session.token,
              approval.permits(identity: session.identity, activityID: scope.activityID, ticketID: scope.ticketID, now: now()),
              approval.endpoint.allows(configuration: configuration, namespace: session.namespace, accountID: session.identity.accountID, path: path) else { throw APIError.notConfigured }
        return session
    }
    private func fence(_ session: RegistrationProductionSession, scope: RegistrationWaitlistScope, path: String) throws {
        guard try check(scope, path: path) == session else { throw APIError.unauthorized }
    }
    private struct ConsentPayload: Decodable {
        let value: ComplianceConsent?
        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        init(from decoder: Decoder) throws {
            if try decoder.singleValueContainer().decodeNil() { value = nil; return }
            let container = try decoder.container(keyedBy: Key.self)
            value = container.allKeys.isEmpty ? nil : try ComplianceConsent(from: decoder)
        }
    }
    private func latestConsent(scope: RegistrationWaitlistScope, session: RegistrationProductionSession) async throws -> Bool {
        let path = "api/compliance/consents/latest"
        try fence(session, scope: scope, path: path)
        let body = try JSONSerialization.data(withJSONObject: ComplianceSubject.signup.fields(), options: .sortedKeys)
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: body, token: session.token)
        let (data, status) = try await transport.send(request)
        try fence(session, scope: scope, path: path)
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let consent = try JSONDecoder().decode(RegistrationResponse<ConsentPayload>.self, from: data).data.value
        return consent?.matches(.signup, event: .agree) == true && consent?.docVersion == approval.consentVersion
    }
    private func consent(scope: RegistrationWaitlistScope, session: RegistrationProductionSession) async throws {
        guard try await latestConsent(scope: scope, session: session) else { throw APIError.invalidRequest }
    }
    public func agreeToSignupNotice(_ scope: RegistrationWaitlistScope) async throws {
        let path = "api/compliance/consents", session = try check(scope, path: "api/compliance/consents")
        let key = "consent|activity_signup|\(approval.consentVersion)"
        // Reconcile first. A pending unknown consent can only be read back, never resent.
        let alreadyAgreed = try await latestConsent(scope: scope, session: session)
        if alreadyAgreed {
            if let old = try journal.pending(ownerKey: ownerKey, targetKey: key) { try journal.clear(old) }
            return
        }
        try fence(session, scope: scope, path: path)
        guard try journal.pending(ownerKey: ownerKey, targetKey: key) == nil else { throw APIError.invalidRequest }
        let pending = OperationPendingRecord(ownerKey: ownerKey, targetKey: key)
        var fields = try ComplianceSubject.signup.fields()
        fields["eventType"] = "AGREE"; fields["requestId"] = pending.operationID.uuidString
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: path,
            body: JSONSerialization.data(withJSONObject: fields, options: .sortedKeys), token: session.token)
        try journal.write(pending)
        let (data, status) = try await transport.send(request)
        try fence(session, scope: scope, path: path)
        guard (200..<300).contains(status), let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              response["code"] as? Int == 200 else { throw APIError.malformedResponse }
        guard try await latestConsent(scope: scope, session: session) else { throw APIError.malformedResponse }
        try fence(session, scope: scope, path: path); try journal.clear(pending)
    }
    public func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        quoteGeneration &+= 1; let quoteStamp = quoteGeneration
        lastQuote = nil
        let scope = try scope(selection), path = "api/registration/quote"
        let session = try check(scope, path: path, token: token)
        try await consent(scope: scope, session: session)
        if let offer = selection.waitlistOffer { try await validateOffer(offer, scope: scope, session: session) }
        try fence(session, scope: scope, path: path)
        let result = try await registration.quote(selection, token: token)
        try fence(session, scope: scope, path: path)
        guard quoteGeneration == quoteStamp else { throw APIError.invalidRequest }
        lastQuote = (selection, result, now()); return result
    }
    private func hasFreshQuote(_ intent: RegistrationCreateIntent) -> Bool {
        guard let lastQuote else { return false }
        return lastQuote.selection == intent.selection && lastQuote.quote.quoteSign == intent.quoteSign
            && lastQuote.quote.isUsableForCreate && now().timeIntervalSince(lastQuote.receivedAt) >= 0
            && now().timeIntervalSince(lastQuote.receivedAt) < 120
    }
    public func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        let scope = try scope(intent.selection), path = "api/registration/create"
        let session = try check(scope, path: path, token: token)
        guard hasFreshQuote(intent), intent.selection.waitlistOffer == intent.waitlistOffer else { throw APIError.invalidRequest }
        let target = "create|\(scope.activityID)|\(scope.ticketID)"
        guard try journal.pending(ownerKey: ownerKey, targetKey: target) == nil else { throw APIError.invalidRequest }
        try await consent(scope: scope, session: session)
        if let offer = intent.waitlistOffer { try await validateOffer(offer, scope: scope, session: session) }
        try fence(session, scope: scope, path: path)
        // Recheck after all awaits; concurrent reviews cannot cross the durable write boundary.
        guard try journal.pending(ownerKey: ownerKey, targetKey: target) == nil else { throw APIError.invalidRequest }
        guard hasFreshQuote(intent) else { throw APIError.invalidRequest }
        var pending = OperationPendingRecord(ownerKey: ownerKey, targetKey: target)
        try journal.write(pending)
        lastQuote = nil
        let result = try await registration.create(intent, token: token)
        try fence(session, scope: scope, path: path)
        pending.acknowledgedSteps = result.registrationID; try journal.write(pending)
        // Keep the lock even on a valid response. It is not evidence of completed payment.
        return result
    }
    public func creationLock(_ scope: RegistrationWaitlistScope) throws -> RegistrationDurableCreation {
        _ = try check(scope, path: "api/registration/create")
        guard let record = try journal.pending(ownerKey: ownerKey, targetKey: "create|\(scope.activityID)|\(scope.ticketID)") else { return .none }
        return .pending(registrationID: record.acknowledgedSteps > 0 ? record.acknowledgedSteps : nil)
    }
    public func readRetainedStatus(_ scope: RegistrationWaitlistScope) async throws -> RegistrationStatusSnapshot {
        let session = try check(scope, path: "api/registration/info")
        guard case .pending(let id) = try creationLock(scope), let id else { throw APIError.invalidRequest }
        return try await readStatus(registrationID: id, token: session.token)
    }
    public func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        let path = "api/registration/info"
        guard let ticketID = approval.ticketIDs.first else { throw APIError.notConfigured }
        let scope = try RegistrationWaitlistScope(activityID: approval.activityID, ticketID: ticketID)
        let session = try check(scope, path: path, token: token)
        var known = false
        for ticketID in approval.ticketIDs {
            if try journal.pending(ownerKey: ownerKey, targetKey: "create|\(approval.activityID)|\(ticketID)")?.acknowledgedSteps == registrationID { known = registrationID > 0 }
        }
        guard known else { throw APIError.invalidRequest }
        let result = try await registration.readStatus(registrationID: registrationID, token: token)
        try fence(session, scope: scope, path: path); return result
    }
    private func validateOffer(_ offer: RegistrationWaitlistOffer, scope: RegistrationWaitlistScope, session: RegistrationProductionSession) async throws {
        let snapshot = try await status(scope)
        try fence(session, scope: scope, path: "api/club/event-ops/waitlist/status")
        guard snapshot.offer(at: now()) == offer else { throw APIError.invalidRequest }
    }
    public func status(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        guard !mutatingWaitlistScopes.contains(scope) else { throw RegistrationPendingFailure.busy }
        return try await readWaitlist(scope)
    }
    private func readWaitlist(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        let path = "api/club/event-ops/waitlist/status", session = try check(scope, path: "api/club/event-ops/waitlist/status")
        let result = try await waitlist.status(scope, accountID: session.identity.accountID, token: session.token)
        try fence(session, scope: scope, path: path)
        for operation in ["join", "cancel"] {
            let key = "\(operation)|\(scope.activityID)|\(scope.ticketID)"
            if let pending = try journal.pending(ownerKey: ownerKey, targetKey: key), reconciles(result, operation: operation, receiptID: pending.acknowledgedSteps) { try journal.clear(pending) }
        }
        for operation in ["join", "cancel"] {
            if try journal.pending(ownerKey: ownerKey, targetKey: "\(operation)|\(scope.activityID)|\(scope.ticketID)") != nil { throw RegistrationPendingFailure.waitlistUnknown }
        }
        return result
    }
    private func reconciles(_ status: RegistrationWaitlistStatus, operation: String, receiptID: Int) -> Bool {
        if operation == "cancel" { return [.none, .cancelled, .expired].contains(status.state) }
        return [.waiting, .offered, .claimed, .converted].contains(status.state) && (receiptID == 0 || receiptID == status.id)
    }
    public func join(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus { try await mutate("join", scope: scope) }
    public func cancel(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus { try await mutate("cancel", scope: scope) }
    private func mutate(_ operation: String, scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        guard !mutatingWaitlistScopes.contains(scope) else { throw RegistrationPendingFailure.busy }
        mutatingWaitlistScopes.insert(scope); defer { mutatingWaitlistScopes.remove(scope) }
        let path = "api/club/event-ops/waitlist/\(operation)", session = try check(scope, path: "api/club/event-ops/waitlist/\(operation)")
        // Explicit read may reconcile a previous request; it never resends it automatically.
        let before = try await readWaitlist(scope)
        try fence(session, scope: scope, path: path)
        guard operation == "join" ? before.canJoin : before.canCancel else { throw APIError.invalidRequest }
        for other in ["join", "cancel"] {
            guard try journal.pending(ownerKey: ownerKey, targetKey: "\(other)|\(scope.activityID)|\(scope.ticketID)") == nil else { throw APIError.invalidRequest }
        }
        var record = OperationPendingRecord(ownerKey: ownerKey, targetKey: "\(operation)|\(scope.activityID)|\(scope.ticketID)")
        try journal.write(record)
        do {
            if operation == "join" {
                record.acknowledgedSteps = try await waitlist.join(scope, accountID: session.identity.accountID, token: session.token)
                try fence(session, scope: scope, path: path); try journal.write(record)
            } else { try await waitlist.cancel(scope, token: session.token) }
        } catch let failure as RegistrationResponseFailure {
            // A decoded source business refusal is distinct from transport/protocol uncertainty.
            // Clear only this exact record; the UI still requires a new authoritative read.
            try fence(session, scope: scope, path: path); try journal.clear(record)
            throw failure
        }
        try fence(session, scope: scope, path: path)
        let after = try await readWaitlist(scope)
        try fence(session, scope: scope, path: path)
        guard reconciles(after, operation: operation, receiptID: record.acknowledgedSteps) else { throw APIError.malformedResponse }
        return after
    }
}
