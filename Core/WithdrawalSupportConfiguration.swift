import Foundation

public enum WithdrawalSupportFailure: Error, Equatable {
    case unavailable, staleSession, changed, expired
}

/// Adapter output for an independently reviewed, public business-contact configuration.
/// This is not an HTTP wire schema. No endpoint or private source contact is assumed.
public struct WithdrawalSupportConfiguration: Equatable {
    public let namespace: String
    public let market: RegionalMarket
    public let revision: String
    public let expiresAt: Date
    public let contact: WithdrawalSupportContact
    public init(namespace: String, market: RegionalMarket, revision: String, expiresAt: Date, contact: WithdrawalSupportContact) throws {
        guard !namespace.isEmpty, !revision.isEmpty else { throw APIError.invalidConfiguration }
        self.namespace = namespace; self.market = market; self.revision = revision; self.expiresAt = expiresAt; self.contact = contact
    }
}

public struct WithdrawalSupportApproval: Equatable {
    public let id: String
    public let market: RegionalMarket
    public init(id: String, market: RegionalMarket) { self.id = id; self.market = market }
}
public struct WithdrawalSupportSnapshot: Equatable {
    public let configuration: WithdrawalSupportConfiguration
    public let scope: WalletCommerceScope
    public let approval: WithdrawalSupportApproval
    public var contact: WithdrawalSupportContact { configuration.contact }
}

@MainActor public final class WithdrawalSupportReader {
    public typealias Source = () async throws -> WithdrawalSupportConfiguration?
    private let source: Source?
    private let session: () -> WalletCommerceScope?
    /// Opaque review ID must be revoked when public-use approval or deployment changes.
    private let approval: () -> WithdrawalSupportApproval?
    private let now: () -> Date
    public init(source: Source? = nil, approval: @escaping () -> WithdrawalSupportApproval? = { nil },
                now: @escaping () -> Date = Date.init, session: @escaping () -> WalletCommerceScope?) {
        self.source = source; self.approval = approval; self.now = now; self.session = session
    }
    public var scope: WalletCommerceScope? { session() }
    public func read() async throws -> WithdrawalSupportSnapshot {
        guard let scope, scope.valid else { throw WithdrawalSupportFailure.staleSession }
        guard let source, let review = approval(), !review.id.isEmpty else { throw WithdrawalSupportFailure.unavailable }
        let value = try await source()
        try Task.checkCancellation()
        guard session() == scope else { throw WithdrawalSupportFailure.staleSession }
        guard approval() == review else { throw WithdrawalSupportFailure.unavailable }
        guard let value, value.namespace == scope.namespace, value.market == review.market else { throw WithdrawalSupportFailure.unavailable }
        guard value.expiresAt > now() else { throw WithdrawalSupportFailure.expired }
        return WithdrawalSupportSnapshot(configuration: value, scope: scope, approval: review)
    }
    /// Refresh on the explicit copy action. An old displayed contact never authorizes a new one.
    public func contactForCopy(_ displayed: WithdrawalSupportSnapshot) async throws -> String {
        let fresh = try await read()
        guard fresh.scope == displayed.scope, fresh.approval == displayed.approval,
              fresh.configuration.namespace == displayed.configuration.namespace,
              fresh.configuration.market == displayed.configuration.market,
              fresh.configuration.revision == displayed.configuration.revision,
              fresh.contact == displayed.contact else { throw WithdrawalSupportFailure.changed }
        return fresh.contact.weChatID
    }
}
