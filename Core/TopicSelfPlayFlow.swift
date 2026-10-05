import Foundation

public enum TopicSelfPlayPhase: Equatable { case editing, reviewing, creating, paymentUnavailable, verifying, complete, failed, unknown, changed }
/// Retain per account/topic in the session owner. Closing a sheet cannot erase an order lock.
@MainActor public final class TopicSelfPlayFlow {
    public let topic: TopicDetail
    public var realName = ""
    public var phone = ""
    public var consented = false
    public private(set) var document: TopicSelfPlayDocument?
    public private(set) var review: TopicSelfPlayReview?
    public private(set) var paymentReview: TopicSelfPlayPaymentReview?
    public private(set) var phase: TopicSelfPlayPhase = .editing
    public private(set) var pending: TopicSelfPlayPending?
    public private(set) var result: PaymentProviderReturnFlow?
    public private(set) var messageKey: String?
    public var onChange: (() -> Void)?
    private let client: (any TopicSelfPlayServing)?
    private let provider: (any TopicSelfPlayPaymentProviding)?
    private let journal: any TopicSelfPlayJournaling
    private let operationGate: TopicSelfPlayOperationGate
    private let openedSession: PublishingSession?
    private let scope = UUID()
    private let invalidScope = UUID()
    private var generation = 0
    public init(topic: TopicDetail, client: (any TopicSelfPlayServing)?, provider: (any TopicSelfPlayPaymentProviding)? = nil,
                journal: any TopicSelfPlayJournaling, operationGate: TopicSelfPlayOperationGate? = nil) {
        self.topic = topic; self.client = client; self.provider = provider; self.journal = journal; self.operationGate = operationGate ?? TopicSelfPlayOperationGate(); openedSession = client?.session
    }
    public var current: Bool { openedSession != nil && client?.session == openedSession }
    public var configured: Bool { current && client?.configured == true }
    public var canEdit: Bool { current && pending == nil && phase != .creating && phase != .verifying }
    public var canCreate: Bool { configured && canEdit && document != nil && topic.selfPlay == 1 && topic.canOfferPurchase && topic.selfPlayPrice != nil && openedSession?.role != "merchant" }
    public var registrationID: Int? { pending?.registrationID }
    public func open() async {
        generation += 1; let stamp = generation; review = nil; paymentReview = nil; result = nil; document = nil; pending = nil; realName = ""; phone = ""; consented = false
        guard configured, let client, let session = openedSession, let id = SelfPlayTopicID(rawValue: topic.id) else { messageKey = "contextSelfPlay.unavailable"; onChange?(); return }
        do {
            pending = try journal.pending(owner: session.storageKey, topic: id)
            phase = pending == nil ? .editing : (pending?.registrationID == nil || pending?.paymentAttempted == true ? .unknown : .paymentUnavailable)
            let notice = try await client.document()
            guard stamp == generation, current, !Task.isCancelled else { return }
            document = notice
            messageKey = pending == nil ? nil : "contextSelfPlay.retained"
        } catch { guard stamp == generation, current else { return }; messageKey = "contextSelfPlay.unavailable" }
        onChange?()
    }
    public func changed() { review = nil; if pending == nil { phase = .editing }; onChange?() }
    @discardableResult public func prepare() -> Bool {
        guard canCreate, consented, let session = openedSession, let document,
              let topicID = SelfPlayTopicID(rawValue: topic.id), let price = topic.selfPlayPrice, price >= 0,
              let intent = try? TopicSelfPlayIntent(topic: topicID, realName: realName, phone: phone, requestID: "app-" + UUID().uuidString) else {
            messageKey = !consented ? "contextSelfPlay.consentRequired" : "contextSelfPlay.invalid"; onChange?(); return false
        }
        review = TopicSelfPlayReview(id: UUID(), session: session, intent: intent, price: price, document: document)
        phase = .reviewing; messageKey = nil; onChange?(); return true
    }
    public func cancelReview() { review = nil; if pending == nil && phase == .reviewing { phase = .editing }; onChange?() }
    public func confirm(_ value: TopicSelfPlayReview) async {
        guard review == value, canCreate, consented, current, value.session == openedSession, let client,
              realName.trimmingCharacters(in: .whitespacesAndNewlines) == value.intent.realName,
              phone.trimmingCharacters(in: .whitespacesAndNewlines) == value.intent.phone else { return }
        guard operationGate.acquire() else { messageKey = "contextSelfPlay.busy"; onChange?(); return }
        defer { operationGate.release() }
        generation += 1; let stamp = generation; review = nil; phase = .creating; messageKey = nil; onChange?()
        do {
            let fresh = try await client.freshTopic(value.intent.topic)
            guard stamp == generation, current else { return }
            guard fresh.id == topic.id, fresh.canOfferPurchase, fresh.selfPlay == 1, fresh.selfPlayPrice == value.price else { throw TopicSelfPlayFailure.priceChanged }
            try await client.recordConsent(requestID: value.intent.requestID, document: value.document)
            guard stamp == generation, current else { return }
            let record = TopicSelfPlayPending(owner: value.session.storageKey, topic: value.intent.topic, requestID: value.intent.requestID)
            // Durable lock precedes create; failure to write blocks dispatch.
            try journal.write(record); pending = record
            // A synchronous journal callback can invalidate the flow after the prior fence.
            guard stamp == generation, current, !Task.isCancelled else { return }
            let created = try await client.create(value.intent)
            guard stamp == generation, current else { return }
            var known = record; known.registrationID = created.registrationID
            try journal.write(known); pending = known
            let order = try await checkedOrder(client, id: created.registrationID)
            guard stamp == generation, current else { return }
            let observation = OrderPaymentObservation(payment: order.paymentStatus, registration: order.registrationStatus)
            if observation == .paid || observation == .registrationAccepted { showReadback(); return }
            guard observation == .pending, order.payableAmount == value.price else { phase = .unknown; messageKey = "contextSelfPlay.unknown"; onChange?(); return }
            guard let provider, provider.isConfigured else { phase = .paymentUnavailable; messageKey = "contextSelfPlay.paymentUnavailable"; onChange?(); return }
            let params: [String: String]
            if let supplied = created.payParams, TopicSelfPlayHTTPClient.validPaymentParameters(supplied) { params = supplied }
            else { params = try await client.paymentParameters(registrationID: created.registrationID) }
            guard stamp == generation, current else { return }
            // Every provider return, including cancellation/error, follows the same readback path.
            try markPaymentAttempted()
            guard stamp == generation, current, !Task.isCancelled else { return }
            _ = await provider.pay(registrationID: created.registrationID, parameters: params)
            guard stamp == generation, current else { return }; showReadback()
        } catch {
            guard stamp == generation, current else { return }
            phase = pending == nil ? .editing : .unknown
            messageKey = pending == nil ? "contextSelfPlay.notCreated" : "contextSelfPlay.unknown"; onChange?()
        }
    }
    public func prepareExistingPayment() async {
        guard current, let client, let id = registrationID, let session = openedSession,
              phase != .creating, phase != .verifying, pending?.paymentAttempted != true else { return }
        generation += 1; let stamp = generation; paymentReview = nil; phase = .creating; onChange?()
        do {
            let order = try await checkedOrder(client, id: id)
            let document = try await client.document()
            guard stamp == generation, current else { return }
            let observation = OrderPaymentObservation(payment: order.paymentStatus, registration: order.registrationStatus)
            if observation == .paid || observation == .registrationAccepted { showReadback(); return }
            guard order.registrationStatus == 1, observation == .pending, let price = order.payableAmount, price > 0 else { throw TopicSelfPlayFailure.unknown }
            paymentReview = .init(id: UUID(), session: session, registrationID: id, price: price, document: document)
            phase = .paymentUnavailable
        } catch { guard stamp == generation, current else { return }; phase = .unknown; messageKey = "contextSelfPlay.unknown" }
        onChange?()
    }
    public func cancelPaymentReview() { paymentReview = nil; onChange?() }
    public func confirmExistingPayment(_ value: TopicSelfPlayPaymentReview, consented: Bool) async {
        guard paymentReview == value, value.session == openedSession, current, consented,
              registrationID == value.registrationID, pending?.paymentAttempted != true, let client else { return }
        guard let provider, provider.isConfigured else { messageKey = "contextSelfPlay.paymentUnavailable"; onChange?(); return }
        guard operationGate.acquire() else { messageKey = "contextSelfPlay.busy"; onChange?(); return }
        defer { operationGate.release() }
        generation += 1; let stamp = generation; paymentReview = nil; phase = .creating; onChange?()
        do {
            let fresh = try await checkedOrder(client, id: value.registrationID)
            guard stamp == generation, current, fresh.registrationStatus == 1, fresh.paymentStatus != 2, fresh.payableAmount == value.price else { throw TopicSelfPlayFailure.changed }
            try await client.recordConsent(requestID: "pay-" + value.id.uuidString, document: value.document)
            let params = try await client.paymentParameters(registrationID: value.registrationID)
            guard stamp == generation, current else { return }
            try markPaymentAttempted()
            guard stamp == generation, current, !Task.isCancelled else { return }
            _ = await provider.pay(registrationID: value.registrationID, parameters: params)
            guard stamp == generation, current else { return }; showReadback()
        } catch { guard stamp == generation, current else { return }; phase = .unknown; messageKey = "contextSelfPlay.unknown"; onChange?() }
    }
    /// A new intent requires authoritative terminal proof and a fresh user review.
    /// Ambiguous 409/410 text or an unknown create with no order ID cannot clear the lock.
    public func prepareNewOrderAfterClosure() async {
        guard current, let client, let pending, let id = pending.registrationID,
              phase != .creating, phase != .verifying else { return }
        generation += 1; let stamp = generation; phase = .creating; review = nil; paymentReview = nil; onChange?()
        do {
            let order = try await checkedOrder(client, id: id)
            guard stamp == generation, current, [3, 4].contains(order.registrationStatus ?? 0) else { throw TopicSelfPlayFailure.unknown }
            try journal.resolve(pending, authoritativeOrder: order)
            self.pending = nil; realName = ""; phone = ""; consented = false; document = nil
            let notice = try await client.document()
            guard stamp == generation, current else { return }
            document = notice; phase = .editing; messageKey = "contextSelfPlay.closedCanReview"
        } catch { guard stamp == generation, current else { return }; phase = .unknown; messageKey = "contextSelfPlay.unknown" }
        onChange?()
    }
    private func markPaymentAttempted() throws {
        guard var record = pending, record.registrationID != nil, record.paymentAttempted != true else { throw TopicSelfPlayFailure.unknown }
        record.paymentAttempted = true; try journal.write(record); pending = record
    }
    private func checkedOrder(_ client: any TopicSelfPlayServing, id: Int) async throws -> OrderLifecycleDetail {
        let value = try await client.readOrder(registrationID: id)
        guard value.id == id, value.ownerType == 1, value.ownerID == topic.id else { throw APIError.malformedResponse }
        return value
    }
    public func showReadback() {
        guard current, let client, let id = registrationID, phase != .verifying else { return }
        phase = .verifying
        let currentScope: () -> UUID = { [weak self] in guard let self else { return UUID() }; return self.current ? self.scope : self.invalidScope }
        let verifier = OrderPaymentVerifier(currentScope: currentScope, read: { [weak self, client] id in
            guard let self else { throw TopicSelfPlayFailure.changed }; return try await self.checkedOrder(client, id: id)
        })
        result = PaymentProviderReturnFlow(registrationID: id, verifier: verifier, currentScope: currentScope); onChange?()
    }
    public func closeResult(_ outcome: PaymentProviderReturnPhase) {
        result?.leave(); result = nil
        switch outcome {
        case .accepted, .paid: phase = .complete; messageKey = "contextSelfPlay.ready"
        case .failed: phase = .failed; messageKey = "contextSelfPlay.failed"
        case .accessDenied: phase = .changed; messageKey = "contextSelfPlay.changed"
        default: phase = .unknown; messageKey = "contextSelfPlay.unknown"
        }
        onChange?()
    }
    public func leave() {
        generation += 1; result?.leave(); result = nil; review = nil; paymentReview = nil; realName = ""; phone = ""; consented = false; document = nil
        if pending != nil { phase = .unknown }; onChange?()
    }
}
