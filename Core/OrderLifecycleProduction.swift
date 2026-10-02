import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A source contract label, not a server version or a deployment grant.
public enum OrderLifecycleSourceContract {
    public static let revision = "registration-lifecycle-2026-10-02"
}
public struct OrderLifecycleOrderApproval: Equatable {
    public let orderID: Int
    public let ownerType: Int
    public let ownerID: Int
    public let action: OrderLifecycleAction
    public let expiresAt: Date
    /// Required for payment; supplied by the approved current-document integration.
    public let signupDocument: TopicSelfPlayDocument?
    public init(orderID: Int, ownerType: Int, ownerID: Int, action: OrderLifecycleAction,
                expiresAt: Date, signupDocument: TopicSelfPlayDocument? = nil) throws {
        guard orderID > 0, [1, 2].contains(ownerType), ownerID > 0,
              action != .payment || signupDocument != nil else { throw APIError.invalidConfiguration }
        self.orderID = orderID; self.ownerType = ownerType; self.ownerID = ownerID
        self.action = action; self.expiresAt = expiresAt; self.signupDocument = signupDocument
    }
    func matches(_ review: OrderLifecycleReview, now: Date) -> Bool {
        orderID == review.detail.id && ownerType == review.detail.ownerType && ownerID == review.detail.ownerID &&
        action == review.action && now < expiresAt
    }
}
/// Explicit composition injection only. Cancellation and cash-refund grants are distinct
/// order/action rows. A payment grant additionally needs storefront and device approval.
public struct OrderLifecycleProductionConfiguration {
    public let market: RegionalMarket
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public let role: String
    public let sourceRevision: String
    public let approvals: [OrderLifecycleOrderApproval]
    public let externalCheckoutApproved: Bool
    public let devicePaymentApproved: Bool
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int, role: String,
                sourceRevision: String, approvals: [OrderLifecycleOrderApproval] = [],
                externalCheckoutApproved: Bool = false, devicePaymentApproved: Bool = false) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard market == .china, !namespace.isEmpty, accountID > 0, ["player", "club"].contains(role),
              sourceRevision == OrderLifecycleSourceContract.revision,
              Set(approvals.map { "\($0.orderID)|\($0.action.rawValue)" }).count == approvals.count else { throw APIError.invalidConfiguration }
        self.market = market; self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID; self.role = role
        self.sourceRevision = sourceRevision; self.approvals = approvals
        self.externalCheckoutApproved = externalCheckoutApproved; self.devicePaymentApproved = devicePaymentApproved
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        market == .china && context.market == market && context.baseURL == baseURL && context.role == role &&
        context.session.namespace == namespace && context.session.accountID == accountID
    }
}

/// Only non-secret lock identifiers are durable. No reset/clear API is offered: neither
/// errors, SDK callbacks, dismissal nor a new login unlocks another attempt. Only server
/// paid readback admits a separately approved refund while retaining the payment history.
public struct OrderLifecycleReservation: Codable, Equatable {
    public let owner: String
    public let orderID: Int
    public let attemptID: UUID
    public let action: String
    public var paymentObservedPaid: Bool?
    public init(owner: String, orderID: Int, attemptID: UUID, action: OrderLifecycleAction) {
        self.owner = owner; self.orderID = orderID; self.attemptID = attemptID; self.action = action.rawValue; paymentObservedPaid = false
    }
}
@MainActor public protocol OrderLifecycleJournaling: AnyObject {
    func pending(owner: String, orderID: Int) throws -> OrderLifecycleReservation?
    /// Must atomically reject an existing order lock. Callers fence every awaited reserve.
    func reserve(_ record: OrderLifecycleReservation) async throws
    func observePaid(_ record: OrderLifecycleReservation, detail: OrderLifecycleDetail) throws
}
@MainActor public final class OrderLifecycleFileJournal: OrderLifecycleJournaling {
    private let url: URL
    public init(url: URL) { self.url = url }
    private func records() throws -> [OrderLifecycleReservation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let rows = try JSONDecoder().decode([OrderLifecycleReservation].self, from: Data(contentsOf: url))
        guard rows.allSatisfy({ !$0.owner.isEmpty && $0.orderID > 0 && OrderLifecycleAction(rawValue: $0.action) != nil }),
              Set(rows.map { "\($0.owner.utf8.count):\($0.owner)|\($0.orderID)|\($0.action)" }).count == rows.count,
              rows.allSatisfy({ $0.paymentObservedPaid != true || $0.action == OrderLifecycleAction.payment.rawValue }) else { throw APIError.malformedResponse }
        return rows
    }
    public func pending(owner: String, orderID: Int) throws -> OrderLifecycleReservation? {
        try records().last { $0.owner == owner && $0.orderID == orderID && $0.paymentObservedPaid != true }
    }
    public func reserve(_ record: OrderLifecycleReservation) async throws {
        try Task.checkCancellation()
        guard !record.owner.isEmpty, record.orderID > 0, OrderLifecycleAction(rawValue: record.action) != nil, record.paymentObservedPaid != true else { throw APIError.invalidRequest }
        var rows = try records()
        let previous = rows.filter { $0.owner == record.owner && $0.orderID == record.orderID }
        guard previous.isEmpty || (record.action == OrderLifecycleAction.refund.rawValue && previous.allSatisfy({ $0.action == OrderLifecycleAction.payment.rawValue && $0.paymentObservedPaid == true })) else { throw OrderLifecycleFailure.alreadyAttempted }
        rows.append(record)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(rows).write(to: url, options: .atomic)
        guard try pending(owner: record.owner, orderID: record.orderID) == record else { throw APIError.malformedResponse }
    }
    public func observePaid(_ record: OrderLifecycleReservation, detail: OrderLifecycleDetail) throws {
        guard record.action == OrderLifecycleAction.payment.rawValue, detail.id == record.orderID,
              detail.paymentStatus == 2, detail.registrationStatus == 2 else { throw APIError.invalidRequest }
        var rows = try records()
        guard let index = rows.firstIndex(of: record) else { throw APIError.invalidRequest }
        rows[index].paymentObservedPaid = true
        try JSONEncoder().encode(rows).write(to: url, options: .atomic)
        guard try records()[index].paymentObservedPaid == true else { throw APIError.malformedResponse }
    }
}

/// The last scoped entry to an injected transport fences actor/executor hops. The
/// underlying HTTPTransport must submit once; no retrying transport is permitted here.
@MainActor private final class OrderLifecycleEntryTransport: HTTPTransport {
    private let transport: any HTTPTransport
    private let beforeSend: (URLRequest) throws -> Void
    init(transport: any HTTPTransport, beforeSend: @escaping (URLRequest) throws -> Void) {
        self.transport = transport; self.beforeSend = beforeSend
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation(); try beforeSend(request)
        return try await transport.send(request)
    }
}

public enum OrderLifecycleProductionResult {
    case cancellation(OrderCancellationResponse, readback: OrderLifecycleDetail?)
    case payment(PaymentProviderReturnFlow)
}
/// Narrow ordinary-HTTP path; no DEBUG or fixture initializer is required. Signed payment
/// fields remain ephemeral and the injected existing provider alone handles SDK behavior.
@MainActor public final class OrderLifecycleProductionDispatcher {
    private let configuration: OrderLifecycleProductionConfiguration
    private let api: APIConfiguration
    private let captured: RuntimeDependencyContext
    private let current: () -> RuntimeDependencyContext?
    private let currentReviewScope: () -> UUID
    private let openedReviewScope: UUID
    private let transport: any HTTPTransport
    private let journal: any OrderLifecycleJournaling
    private let document: (any TopicSelfPlayDocumentProviding)?
    private let provider: (any TopicSelfPlayPaymentProviding)?
    private let sharedGate: TopicSelfPlayOperationGate
    private let selfPlayJournal: any TopicSelfPlayJournaling
    private let now: () -> Date
    private var scope = UUID()
    private var ownedPaymentFlows: [UUID: UUID] = [:]
    private var owner: String {
        [captured.baseURL.absoluteString, captured.market.rawValue, captured.session.namespace, String(captured.session.accountID)]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
    public init?(configuration: OrderLifecycleProductionConfiguration?, api: APIConfiguration,
                 transport: any HTTPTransport, journal: any OrderLifecycleJournaling,
                 document: (any TopicSelfPlayDocumentProviding)? = nil, provider: (any TopicSelfPlayPaymentProviding)? = nil,
                 sharedGate: TopicSelfPlayOperationGate, selfPlayJournal: any TopicSelfPlayJournaling,
                 current: @escaping () -> RuntimeDependencyContext?, reviewScope: @escaping () -> UUID, now: @escaping () -> Date = Date.init) {
        guard let configuration, let captured = current(), configuration.matches(captured), captured.baseURL == api.baseURL else { return nil }
        self.configuration = configuration; self.api = api; self.captured = captured; self.current = current
        self.transport = transport; self.journal = journal; self.document = document; self.provider = provider
        self.sharedGate = sharedGate; self.selfPlayJournal = selfPlayJournal; self.now = now
        self.currentReviewScope = reviewScope; self.openedReviewScope = reviewScope()
    }
    public func pending(orderID: Int) throws -> OrderLifecycleReservation? { try journal.pending(owner: owner, orderID: orderID) }
    /// Server-confirmed payment can permit a separately approved refund. It cannot permit
    /// another payment or remove any historical attempt; registration acceptance is insufficient.
    public func observePaid(_ flow: PaymentProviderReturnFlow) throws {
        guard current() == captured, currentReviewScope() == openedReviewScope, flow.phase == .paid,
              let attemptID = ownedPaymentFlows[flow.id], let detail = flow.detail,
              let record = try pending(orderID: flow.registrationID), record.attemptID == attemptID else { throw OrderLifecycleFailure.stale }
        try journal.observePaid(record, detail: detail)
        ownedPaymentFlows.removeValue(forKey: flow.id)
    }
    private func approval(_ review: OrderLifecycleReview) -> OrderLifecycleOrderApproval? {
        guard current() == captured, configuration.matches(captured), review.accountID == captured.session.accountID,
              review.scope == openedReviewScope, currentReviewScope() == openedReviewScope else { return nil }
        return configuration.approvals.first { $0.matches(review, now: now()) }
    }
    public func canDispatch(_ review: OrderLifecycleReview) -> Bool {
        guard approval(review) != nil, now() < review.expiresAt else { return false }
        if review.action == .payment {
            return configuration.externalCheckoutApproved && configuration.devicePaymentApproved && document != nil && provider?.isConfigured == true
        }
        return true
    }
    private func check(_ review: OrderLifecycleReview, visible: () -> Bool) throws {
        try Task.checkCancellation()
        guard visible(), current() == captured, currentReviewScope() == openedReviewScope else { throw OrderLifecycleFailure.stale }
        guard now() < review.expiresAt else { throw OrderLifecycleFailure.expiredReview }
        guard canDispatch(review) else { throw OrderLifecycleFailure.notDispatched }
    }
    private func fresh(_ review: OrderLifecycleReview, visible: () -> Bool) async throws -> OrderLifecycleDetail {
        try check(review, visible: visible)
        let value = try await readOrder(review.detail.id)
        try check(review, visible: visible)
        // The source has no version/ETag contract: compare the full immutable projection.
        guard value == review.detail, OrderLifecycleCoordinator.isReviewable(review.action, detail: value) else { throw OrderLifecycleFailure.stale }
        if review.action == .payment {
            guard let deadline = OrderLifecycleTime.date(value.payExpireTime), now() < deadline,
                  let amount = value.payableAmount, amount > 0 else { throw OrderLifecycleFailure.ineligible }
        }
        if review.action == .refund, let raw = value.refundDeadline {
            guard let deadline = OrderLifecycleTime.date(raw), now() < deadline else { throw OrderLifecycleFailure.ineligible }
        }
        return value
    }
    private func readOrder(_ id: Int) async throws -> OrderLifecycleDetail {
        try Task.checkCancellation()
        guard current() == captured else { throw OrderLifecycleFailure.stale }
        let guarded = OrderLifecycleEntryTransport(transport: transport) { request in
            try Task.checkCancellation()
            guard self.current() == self.captured else { throw OrderLifecycleFailure.stale }
            try self.validateForm(request, path: "api/registration/info", id: id)
        }
        let result = try await OrderLifecycleService(configuration: api, transport: guarded).detail(id: id, token: captured.session.token)
        try Task.checkCancellation()
        guard current() == captured else { throw OrderLifecycleFailure.stale }
        return result
    }
    private func checkLegal(_ review: OrderLifecycleReview, visible: @escaping () -> Bool) async throws {
        guard review.action == .payment else { return }
        guard let expected = approval(review)?.signupDocument, let document else { throw OrderLifecycleFailure.notDispatched }
        let latest = try await document.currentDocument(context: captured)
        try check(review, visible: visible)
        guard latest == expected else { throw OrderLifecycleFailure.stale }
        let request = try OperationAdapterHTTP.json(configuration: api, path: "api/compliance/consents/latest",
            body: JSONSerialization.data(withJSONObject: ComplianceSubject.signup.fields(), options: .sortedKeys), token: captured.session.token)
        try check(review, visible: visible)
        let data = try await send(request, review: review, visible: visible)
        struct Envelope: Decodable { let data: ComplianceConsent? }
        let consent = try JSONDecoder().decode(Envelope.self, from: data).data
        guard consent?.matches(.signup, event: .agree) == true, consent?.docVersion == expected.version else { throw OrderLifecycleFailure.ineligible }
        // A provider may change while the consent read is suspended.
        let finalDocument = try await document.currentDocument(context: captured)
        try check(review, visible: visible)
        guard finalDocument == expected else { throw OrderLifecycleFailure.stale }
    }
    private func send(_ request: URLRequest, review: OrderLifecycleReview, visible: @escaping () -> Bool) async throws -> Data {
        try check(review, visible: visible)
        let guarded = OrderLifecycleEntryTransport(transport: transport) { request in
            try self.check(review, visible: visible)
            if request.url == self.api.baseURL.appendingPathComponent("api/compliance/consents/latest") {
                guard review.action == .payment, request.httpMethod == "POST",
                      request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                      request.value(forHTTPHeaderField: "Authorization") == self.captured.session.token,
                      let data = request.httpBody,
                      let fields = try JSONSerialization.jsonObject(with: data) as? [String: String],
                      fields == ["docType": ComplianceSubject.signup.docType, "scene": ComplianceSubject.signup.scene] else { throw APIError.invalidRequest }
            } else {
                try self.validateForm(request, path: review.action.sourcePath, id: review.detail.id)
                guard let lock = try self.pending(orderID: review.detail.id), lock.attemptID == review.localAttemptID,
                      lock.action == review.action.rawValue else { throw OrderLifecycleFailure.alreadyAttempted }
            }
        }
        let (data, status) = try await guarded.send(request)
        try check(review, visible: visible)
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw OrderLifecycleFailure.accessDenied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        struct Status: Decodable { let code: Int; let msg: String? }
        let envelope = try JSONDecoder().decode(Status.self, from: data)
        if envelope.code == 401 { throw APIError.unauthorized }
        if envelope.code == 403 { throw OrderLifecycleFailure.accessDenied }
        guard envelope.code == 200 else { throw OrderLifecycleFailure.response(code: envelope.code, message: envelope.msg) }
        return data
    }
    private func validateForm(_ request: URLRequest, path: String, id: Int) throws {
        let prefix = "multipart/form-data; boundary="
        guard request.httpMethod == "POST", request.url == api.baseURL.appendingPathComponent(path),
              request.value(forHTTPHeaderField: "Authorization") == captured.session.token,
              let contentType = request.value(forHTTPHeaderField: "Content-Type"), contentType.hasPrefix(prefix) else { throw APIError.invalidRequest }
        // Reuse the actual request boundary; a newly randomized builder comparison is invalid.
        let boundary = String(contentType.dropFirst(prefix.count))
        let expected = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent(path),
            fields: ["id": String(id)], token: captured.session.token, boundary: boundary)
        guard request.httpBody == expected.httpBody else { throw APIError.invalidRequest }
    }
    private func topicRecord(_ review: OrderLifecycleReview) throws -> TopicSelfPlayPending? {
        guard review.detail.ownerType == 1, let id = review.detail.ownerID, let topic = SelfPlayTopicID(rawValue: id) else { return nil }
        // A retained self-play flow owns its own monotonic payment marker. Never create
        // a second entry path around it, including an unknown create with no order ID.
        let publishingOwner = "\(captured.session.namespace)|\(PublishingRegion.china.rawValue)|\(captured.session.accountID)"
        let record = try selfPlayJournal.pending(owner: publishingOwner, topic: topic)
        if record != nil { throw OrderLifecycleFailure.alreadyAttempted }
        return record
    }
    public func dispatch(_ review: OrderLifecycleReview, visible: @escaping () -> Bool, providerWillOpen: () -> Void = {}) async throws -> OrderLifecycleProductionResult {
        try check(review, visible: visible)
        guard try pending(orderID: review.detail.id) == nil, sharedGate.acquire() else { throw OrderLifecycleFailure.alreadyAttempted }
        defer { sharedGate.release() }
        _ = try topicRecord(review)
        _ = try await fresh(review, visible: visible)
        try await checkLegal(review, visible: visible)
        _ = try await fresh(review, visible: visible)
        try check(review, visible: visible)
        let record = OrderLifecycleReservation(owner: owner, orderID: review.detail.id, attemptID: review.localAttemptID, action: review.action)
        try await journal.reserve(record)
        // Reservation is a suspension point. Never send after cancellation/account/role/
        // token/namespace/context/sheet changes, even when the journal ignored cancellation.
        try check(review, visible: visible)
        guard try pending(orderID: review.detail.id) == record else { throw OrderLifecycleFailure.alreadyAttempted }
        _ = try await fresh(review, visible: visible)
        try await checkLegal(review, visible: visible)
        try check(review, visible: visible)
        if review.action != .payment {
            let request = try OrderLifecycleRequestContract.cancellation(review: review, baseURL: api.baseURL, token: captured.session.token)
            let response = try JSONDecoder().decode(OrderCancellationResponse.self, from: await send(request, review: review, visible: visible))
            if let id = response.observation?.registrationId, id != review.detail.id { throw APIError.malformedResponse }
            let readback = try? await readOrder(review.detail.id)
            try check(review, visible: visible)
            return .cancellation(response, readback: readback)
        }
        let request = try OrderLifecycleRequestContract.paymentParameters(registrationID: review.detail.id, baseURL: api.baseURL, token: captured.session.token)
        let data = try await send(request, review: review, visible: visible)
        struct Envelope: Decodable { let data: Payload }
        struct Payload: Decodable { let payParams: [String: String] }
        let parameters = try JSONDecoder().decode(Envelope.self, from: data).data.payParams
        guard TopicSelfPlayHTTPClient.validPaymentParameters(parameters), let provider else { throw APIError.malformedResponse }
        // Parameters never authorize stale prices, expired orders or a changed legal version.
        _ = try await fresh(review, visible: visible)
        try await checkLegal(review, visible: visible)
        try check(review, visible: visible)
        providerWillOpen()
        try check(review, visible: visible)
        _ = await provider.pay(registrationID: review.detail.id, parameters: parameters)
        try Task.checkCancellation()
        guard visible(), current() == captured, currentReviewScope() == openedReviewScope else { throw OrderLifecycleFailure.stale }
        // The review may expire while the provider owns the foreground. There are no more
        // mutations: server-only reconciliation must still run for this exact retained order.
        let flow = PaymentProviderReturnFlow(registrationID: review.detail.id,
            verifier: OrderPaymentVerifier(currentScope: { self.readbackScope() },
                read: { id in try await self.readOrder(id) }),
            currentScope: { self.readbackScope() })
        ownedPaymentFlows[flow.id] = review.localAttemptID
        return .payment(flow)
    }
    private func readbackScope() -> UUID { if current() != captured || currentReviewScope() != openedReviewScope { scope = UUID() }; return scope }
}

/// Production composition entry point. With the default nil configuration this returns
/// nil even when a real HTTP transport, document provider and SDK have been supplied.
@MainActor public enum OrderLifecycleProductionFactory {
    public static func make(configuration: OrderLifecycleProductionConfiguration? = nil, api: APIConfiguration,
                            transport: any HTTPTransport, journal: any OrderLifecycleJournaling,
                            document: (any TopicSelfPlayDocumentProviding)? = nil,
                            provider: (any TopicSelfPlayPaymentProviding)? = nil,
                            sharedGate: TopicSelfPlayOperationGate, selfPlayJournal: any TopicSelfPlayJournaling,
                            current: @escaping () -> RuntimeDependencyContext?, reviewScope: @escaping () -> UUID,
                            now: @escaping () -> Date = Date.init) -> OrderLifecycleProductionDispatcher? {
        OrderLifecycleProductionDispatcher(configuration: configuration, api: api, transport: transport, journal: journal,
            document: document, provider: provider, sharedGate: sharedGate, selfPlayJournal: selfPlayJournal, current: current, reviewScope: reviewScope, now: now)
    }
}
