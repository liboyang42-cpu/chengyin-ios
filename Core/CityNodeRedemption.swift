import Foundation

/// An opaque player-presented city-node code. Never persisted, logged, copied or treated as a URL.
public struct CityNodeRedemptionCode: Equatable {
    private let value: String
    public init(_ raw: String) throws {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.utf8.count <= 16_384 else { throw MerchantBusinessFailure.invalid }
        value = code
    }
    public var request: MerchantBusinessRequest { .form("api/verify/citynode/redeem", ["code": value]) }
}

/// The original backend message is business information, including rejection and restocking guidance.
/// Do not trim it, prepend generic errors, translate it or interpret a rejection as success.
public struct CityNodeRedemptionResult: Equatable {
    public let redeemed: Bool
    public let message: String
    public init(body: MerchantBusinessObject) throws {
        let code = try body.mbInt("code")
        redeemed = code == 200
        if let raw = body["msg"], raw != .null {
            guard let text = raw.string else { throw MerchantBusinessFailure.malformed }
            message = text
        } else { message = redeemed ? "核销成功" : "核销失败" }
    }
}

/// Immutable, one-use consent. Neither raw payload nor session credential is public/Codable.
public struct CityNodeRedemptionReview: Equatable, Identifiable {
    public let id: UUID
    public let merchantID: Int
    fileprivate let code: CityNodeRedemptionCode
    fileprivate let session: MerchantBusinessSession
}

/// No production mutation transport exists in MerchantBusinessService's default initializer.
/// Tests may inject its synthetic-only transport. Opening this page never starts camera or network.
@MainActor public final class CityNodeRedemptionCoordinator {
    private let service: MerchantBusinessService?
    private let journal: any MerchantBusinessIntentStore
    private let currentSession: () -> MerchantBusinessSession?
    private let unauthorized: (MerchantBusinessSession) -> Void
    private var generation: UInt64 = 0
    public private(set) var review: CityNodeRedemptionReview?
    public private(set) var result: CityNodeRedemptionResult?
    public private(set) var failure: String?
    public private(set) var busy = false
    public var isAvailable: Bool { service?.canExecuteSyntheticMutation == true }
    public var scope: MerchantBusinessScope? {
        guard let service, let session = currentSession() else { return nil }
        return .init(realm: service.realm, accountID: session.accountID, epoch: session.epoch)
    }
    public init(service: MerchantBusinessService?, journal: any MerchantBusinessIntentStore,
                currentSession: @escaping () -> MerchantBusinessSession?,
                onUnauthorized: @escaping (MerchantBusinessSession) -> Void = { _ in }) {
        self.service = service; self.journal = journal; self.currentSession = currentSession; unauthorized = onUnauthorized
    }
    public func prepare(_ raw: String) async {
        guard !busy, review == nil else { return }
        result = nil; failure = nil
        let ticket = generation
        var capturedSession: MerchantBusinessSession?
        do {
            let code = try CityNodeRedemptionCode(raw)
            guard let service, service.canExecuteSyntheticMutation else { throw MerchantBusinessFailure.disabled }
            guard let session = currentSession() else { throw APIError.unauthorized }
            capturedSession = session
            busy = true; defer { busy = false }
            let access = try await service.access(token: session.token)
            try access.require(["merchant:verify"])
            guard generation == ticket, currentSession() == session, !Task.isCancelled else { return }
            let candidate = CityNodeRedemptionReview(id: UUID(), merchantID: access.merchantID, code: code, session: session)
            let target = intent(candidate, realm: service.realm)
            guard !(try journal.intents()).contains(where: { $0.sameTarget(as: target) }) else { throw MerchantBusinessFailure.pending }
            review = candidate
        } catch {
            guard generation == ticket, !Task.isCancelled,
                  capturedSession == nil || currentSession() == capturedSession else { return }
            failure = errorKey(error)
            if error as? APIError == .unauthorized, let capturedSession { unauthorized(capturedSession) }
        }
    }
    public func cancelReview() { review = nil; failure = nil }
    public func next() { guard !busy else { return }; review = nil; result = nil; failure = nil }
    /// Close, scene background and account/region changes invalidate any consent and late UI work.
    /// A submitted operation is NEVER unlocked by this local lifecycle event.
    public func invalidate() { generation &+= 1; review = nil; result = nil; failure = nil }
    public func confirm(_ reviewID: UUID) async {
        guard !busy, let frozen = review, frozen.id == reviewID else { return }
        review = nil; result = nil; failure = nil
        guard let service, service.canExecuteSyntheticMutation else { failure = "merchant.cityRedeem.disabled"; return }
        guard currentSession() == frozen.session else { failure = "merchant.cityRedeem.stale"; return }
        busy = true; defer { busy = false }
        let ticket = generation
        var reserved: MerchantBusinessIntent?
        do {
            // Re-read authoritative permission and merchant identity after the separate confirmation.
            let access = try await service.access(token: frozen.session.token)
            try access.require(["merchant:verify"])
            guard currentSession() == frozen.session, generation == ticket, !Task.isCancelled,
                  access.merchantID == frozen.merchantID else { throw MerchantBusinessFailure.stale }
            let target = intent(frozen, realm: service.realm)
            try journal.reserve(target); reserved = target
            let body = try await service.syntheticEnvelope(frozen.code.request, token: frozen.session.token)
            let value = try CityNodeRedemptionResult(body: body)
            // Late responses cannot clear a lock or disclose data to a changed session/page.
            guard currentSession() == frozen.session, generation == ticket, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            try journal.complete(target); reserved = nil
            result = value
            if body["code"]?.integer == 401 { unauthorized(frozen.session) }
        } catch {
            // Any transport/malformed/cancelled/late result after reservation remains uncertain.
            // No timer, Next, rescan, dismiss, restart or new login removes this coarse lock.
            guard generation == ticket, currentSession() == frozen.session else { return }
            failure = reserved == nil ? errorKey(error) : "merchant.cityRedeem.unknown"
            if reserved == nil, error as? APIError == .unauthorized { unauthorized(frozen.session) }
        }
    }
    private func intent(_ review: CityNodeRedemptionReview, realm: String) -> MerchantBusinessIntent {
        let scope = MerchantBusinessScope(realm: realm, accountID: review.session.accountID, epoch: review.session.epoch)
        // Shared with the other merchant redemption flow, so changing scanner cannot bypass it.
        return .init(scope: scope, merchantID: review.merchantID, target: "redemption", requestID: "local-" + review.id.uuidString)
    }
    private func errorKey(_ error: Error) -> String {
        if error as? APIError == .unauthorized { return "merchant.cityRedeem.signIn" }
        switch error as? MerchantBusinessFailure {
        case .disabled: return "merchant.cityRedeem.disabled"
        case .invalid: return "merchant.cityRedeem.invalid"
        case .pending, .journal: return "merchant.cityRedeem.pending"
        case .stale: return "merchant.cityRedeem.stale"
        case .denied: return "merchant.cityRedeem.denied"
        default: return "merchant.cityRedeem.accessFailed"
        }
    }
}
