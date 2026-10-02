import Foundation

public enum OrderLifecycleAction: String, CaseIterable, Equatable {
    case payment, cancel, refund
    /// Source registrationStatus==2 routes cancellation to cancel-refund, never cancel.
    public var sourcePath: String {
        switch self {
        case .payment: return "api/registration/pay/app"
        case .cancel: return "api/registration/cancel"
        case .refund: return "api/registration/cancel-refund"
        }
    }
}
public struct OrderLifecycleReview: Equatable, Identifiable {
    public let id: UUID
    public let accountID: Int
    public let scope: UUID
    public let detail: OrderLifecycleDetail
    public let action: OrderLifecycleAction
    public let expiresAt: Date
    /// Local deduplication token only. The cancellation contract has NO requestId field.
    public let localAttemptID: UUID
}
public struct OrderCancellationObservation: Decodable, Equatable {
    public let registrationId: Int?
    public let cancellationStatus: String?
    public let cashRefundStatus: String?
    public let pointsRefundStatus: String?
    /// No Boolean success aggregate. Three independent server dimensions stay independent.
}
public enum OrderLifecycleAttemptState: Equatable {
    case submitted(localAttemptID: UUID)
    case outcomeUnknown(localAttemptID: UUID)
    case responseReceived(localAttemptID: UUID, observation: OrderCancellationObservation)
}
public enum OrderLifecycleCoordinatorIssue: String, Equatable {
    case login, notConfigured, unavailable, malformed, network, accessDenied, failure
    case expiredReview, ineligible, alreadyAttempted, stale, dispatchDisabled, cancelled
    public init(_ error: Error) {
        if error is CancellationError { self = .cancelled }
        else if let error = error as? URLError { self = error.code == .cancelled ? .cancelled : .network }
        else if let error = error as? APIError {
            switch error {
            case .unauthorized: self = .login
            case .notConfigured: self = .notConfigured
            case .malformedResponse, .invalidRequest: self = .malformed
            default: self = .failure
            }
        } else if let error = error as? OrderLifecycleFailure {
            switch error {
            case .unavailable: self = .unavailable
            case .accessDenied: self = .accessDenied
            case .expiredReview: self = .expiredReview
            case .ineligible: self = .ineligible
            case .alreadyAttempted: self = .alreadyAttempted
            case .stale: self = .stale
            case .notDispatched: self = .dispatchDisabled
            case .response: self = .failure
            }
        } else { self = .failure }
    }
}
#if DEBUG
/// Offline fixture seam only. Production has no command protocol, adapter or transport.
@MainActor public protocol OrderLifecycleFixtureSimulating: AnyObject {
    func simulate(_ review: OrderLifecycleReview) async throws -> OrderCancellationObservation
}
#endif

/// Retain at session/root level, not inside a short-lived confirmation sheet. Dismissal
/// invalidates callbacks, but never erases an uncertain attempt or creates a retry key.
@MainActor public final class OrderLifecycleCoordinator {
    private let reader: any OrderLifecycleReading
    private let now: () -> Date
    private var generation: UInt64 = 0
    private var visibleScope: UUID?
    private var loadedAt: Date?
    private var storedDetail: OrderLifecycleDetail?
    private var storedReview: OrderLifecycleReview?
    private var records: [AttemptKey: OrderLifecycleAttemptState] = [:]
    private struct AttemptKey: Hashable { let accountID: Int; let orderID: Int }
    private var loading = false
    private var storedIssue: OrderLifecycleCoordinatorIssue?
    private var storedServerMessage: String?
    #if DEBUG
    private var fixtureSimulator: (any OrderLifecycleFixtureSimulating)?
    #endif
    public init(reader: any OrderLifecycleReading, now: @escaping () -> Date = Date.init) {
        self.reader = reader; self.now = now
    }
    #if DEBUG
    public convenience init(reader: any OrderLifecycleReading, fixtureSimulator: any OrderLifecycleFixtureSimulating, now: @escaping () -> Date = Date.init) {
        self.init(reader: reader, now: now)
        // A production reader can never accidentally acquire a DEBUG simulation path.
        if reader.isOfflineExample { self.fixtureSimulator = fixtureSimulator }
    }
    #endif
    public var scope: UUID { reader.scope }
    public var accountID: Int? { reader.accountID }
    public var isOfflineExample: Bool { reader.isOfflineExample }
    public var detail: OrderLifecycleDetail? { visibleScope == reader.scope ? storedDetail : nil }
    public var review: OrderLifecycleReview? { visibleScope == reader.scope ? storedReview : nil }
    public var issue: OrderLifecycleCoordinatorIssue? { visibleScope == reader.scope ? storedIssue : nil }
    public var serverMessage: String? { visibleScope == reader.scope ? storedServerMessage : nil }
    public var isLoading: Bool { visibleScope == reader.scope && loading }
    public var canDispatch: Bool { false }
    public var canSimulate: Bool {
        #if DEBUG
        return reader.isOfflineExample && fixtureSimulator != nil
        #else
        return false
        #endif
    }
    public func attempt(orderID: Int) -> OrderLifecycleAttemptState? {
        guard let accountID = reader.accountID else { return nil }
        return records[AttemptKey(accountID: accountID, orderID: orderID)]
    }
    public func load(id: Int) async {
        invalidateVisible()
        visibleScope = reader.scope
        guard reader.accountID != nil else { storedIssue = .login; return }
        guard reader.isConfigured else { storedIssue = .notConfigured; return }
        guard !Task.isCancelled else { storedIssue = .cancelled; return }
        let stamp = generation, captured = reader.scope
        loading = true
        defer { if stamp == generation { loading = false } }
        do {
            let detail = try await reader.detail(id: id)
            guard stamp == generation, captured == reader.scope, !Task.isCancelled else { return }
            guard detail.id == id else { throw APIError.malformedResponse }
            storedDetail = detail; loadedAt = now()
        } catch {
            guard stamp == generation, captured == reader.scope, !Task.isCancelled else { return }
            storedIssue = OrderLifecycleCoordinatorIssue(error)
            if let failure = error as? OrderLifecycleFailure, case .response(_, let message) = failure { storedServerMessage = message }
        }
    }
    /// Reviews are local only. They are not a server cancellation/refund quote.
    public func prepare(_ action: OrderLifecycleAction, orderID: Int) {
        storedReview = nil; storedIssue = nil; storedServerMessage = nil
        guard let accountID = reader.accountID else { storedIssue = .login; return }
        guard let detail, detail.id == orderID, let loadedAt, now().timeIntervalSince(loadedAt) >= 0,
              now().timeIntervalSince(loadedAt) < 60 else { storedIssue = .stale; return }
        guard attempt(orderID: detail.id) == nil else { storedIssue = .alreadyAttempted; return }
        guard Self.isReviewable(action, detail: detail) else { storedIssue = .ineligible; return }
        storedReview = OrderLifecycleReview(id: UUID(), accountID: accountID, scope: reader.scope, detail: detail,
            action: action, expiresAt: loadedAt.addingTimeInterval(60), localAttemptID: UUID())
    }
    nonisolated public static func isReviewable(_ action: OrderLifecycleAction, detail: OrderLifecycleDetail) -> Bool {
        // Unknown, closed or contradictory status never authorizes cancellation or payment.
        switch action {
        case .payment, .cancel:
            return detail.registrationStatus == 1 && detail.paymentStatus == 1 && detail.verificationStatus == 0 && detail.refundApplication == nil && detail.manualRefundCaseStatus?.isEmpty != false
        case .refund:
            return detail.registrationStatus == 2 && detail.paymentStatus == 2 && detail.verificationStatus == 0 && detail.refundable == true && detail.refundApplication == nil && detail.manualRefundCaseStatus?.isEmpty != false
        }
    }
    /// Production returns dispatchDisabled before any attempt is stored. No call can pay,
    /// cancel, refund or issue a credential. DEBUG can exercise an explicitly offline seam.
    public func confirm(reviewID: UUID) async {
        guard let review, review.id == reviewID, review.scope == reader.scope,
              review.accountID == reader.accountID, review.detail == detail else { storedIssue = .stale; return }
        guard now() < review.expiresAt else { storedReview = nil; storedIssue = .expiredReview; return }
        let key = AttemptKey(accountID: review.accountID, orderID: review.detail.id)
        guard records[key] == nil else { storedIssue = .alreadyAttempted; return }
        guard !Task.isCancelled else { storedIssue = .cancelled; return }
        #if DEBUG
        guard reader.isOfflineExample, let fixtureSimulator, review.action != .payment else { storedIssue = .dispatchDisabled; return }
        let stamp = generation
        records[key] = .submitted(localAttemptID: review.localAttemptID)
        storedReview = nil
        do {
            let observation = try await fixtureSimulator.simulate(review)
            guard !Task.isCancelled, stamp == generation, review.scope == reader.scope, review.accountID == reader.accountID else {
                records[key] = .outcomeUnknown(localAttemptID: review.localAttemptID); return
            }
            if let returnedID = observation.registrationId, returnedID != review.detail.id { throw APIError.malformedResponse }
            records[key] = .responseReceived(localAttemptID: review.localAttemptID, observation: observation)
        } catch {
            // No error is proof that a mutation did not happen. Never silently retry.
            records[key] = .outcomeUnknown(localAttemptID: review.localAttemptID)
        }
        #else
        storedIssue = .dispatchDisabled
        #endif
    }
    public func dismissReview() { storedReview = nil }
    public func invalidateVisible() {
        generation &+= 1
        for (key, value) in records {
            if case .submitted(let id) = value { records[key] = .outcomeUnknown(localAttemptID: id) }
        }
        storedDetail = nil; storedReview = nil; storedIssue = nil; storedServerMessage = nil; loadedAt = nil; visibleScope = nil; loading = false
    }
}
