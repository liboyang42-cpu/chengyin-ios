import Foundation

public struct ClubActionSession: Equatable {
    public let identity: ClubReadIdentity
    public let viewerIsMerchant: Bool
    fileprivate let token: String
    /// Account must come from the verified server session, never the entry role chooser.
    public init(account: Account, epoch: UInt64, token: String) throws {
        guard account.id > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = ClubReadIdentity(accountID: account.id, epoch: epoch)
        viewerIsMerchant = account.effectiveRole == "merchant"; self.token = token
    }
}

@MainActor
public protocol ClubActionWriting: AnyObject {
    var isConfigured: Bool { get }
    var identity: ClubReadIdentity? { get }
    var viewerIsMerchant: Bool { get }
    var ordinaryAdmissionApproved: Bool { get }
    var ordinaryAdmissionRecoveryApproved: Bool { get }
    var ordinaryAdmissionApprovalRevision: UUID? { get }
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity, joinMessage: String, original: ClubOrdinaryAdmissionPending?) async throws -> ClubActionReceipt
    func recover(_ pending: ClubOrdinaryAdmissionPending, expectedIdentity: ClubReadIdentity) async throws -> ClubOrdinaryAdmissionOriginalReceipt
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity, joinMessage: String) async throws -> ClubActionReceipt
}

public extension ClubActionWriting {
    var ordinaryAdmissionApproved: Bool { false }
    var ordinaryAdmissionRecoveryApproved: Bool { ordinaryAdmissionApproved }
    var ordinaryAdmissionApprovalRevision: UUID? { nil }
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity, joinMessage: String, original: ClubOrdinaryAdmissionPending?) async throws -> ClubActionReceipt {
        guard original == nil else { throw ClubActionWriteError.notSent(.notConfigured) }
        return try await perform(action, clubID: clubID, expectedIdentity: expectedIdentity, joinMessage: joinMessage)
    }
    func recover(_ pending: ClubOrdinaryAdmissionPending, expectedIdentity: ClubReadIdentity) async throws -> ClubOrdinaryAdmissionOriginalReceipt { throw APIError.notConfigured }
}

/// Reads detail again immediately before dispatch. A changed account/epoch/token or
/// changed membership/policy cancels the original intent rather than changing it.
@MainActor
public final class ClubActionSessionWriter: ClubActionWriting {
    private let service: ClubActionService?
    private let currentSession: () -> ClubActionSession?
    private let onUnauthorized: (ClubActionSession) -> Void
    private let approval: () -> ClubOrdinaryAdmissionApproval?
    private let requiresOriginalReceipt: Bool
    public var ordinaryAdmissionApproved: Bool { ordinaryAdmissionRecoveryApproved && approval()?.allowsWrites == true }
    public var ordinaryAdmissionRecoveryApproved: Bool {
        guard let session = currentSession(), let grant = approval() else { return false }
        return grant.identity == session.identity && service?.accepts(grant) == true
    }
    public var ordinaryAdmissionApprovalRevision: UUID? {
        guard ordinaryAdmissionRecoveryApproved, let grant = approval() else { return nil }
        return grant.configurationRevision ?? grant.revision
    }
    public var isConfigured: Bool { service != nil && (!requiresOriginalReceipt || ordinaryAdmissionApproved) }
    public var identity: ClubReadIdentity? { currentSession()?.identity }
    public var viewerIsMerchant: Bool { currentSession()?.viewerIsMerchant ?? false }
    public init(service: ClubActionService?, currentSession: @escaping () -> ClubActionSession?,
                onUnauthorized: @escaping (ClubActionSession) -> Void = { _ in },
                approval: @escaping () -> ClubOrdinaryAdmissionApproval? = { nil },
                requiresOriginalReceipt: Bool = false) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized; self.approval = approval
        self.requiresOriginalReceipt = requiresOriginalReceipt
    }
    public func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity, joinMessage: String = "") async throws -> ClubActionReceipt {
        try await perform(action, clubID: clubID, expectedIdentity: expectedIdentity, joinMessage: joinMessage, original: nil)
    }
    public func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity, joinMessage: String, original: ClubOrdinaryAdmissionPending?) async throws -> ClubActionReceipt {
        guard let service else { throw ClubActionWriteError.notSent(.notConfigured) }
        // A selected original source must never downgrade to a fresh legacy write
        // after revocation, replacement, logout or restart. Legacy-only hosts are unchanged.
        guard !requiresOriginalReceipt || original != nil else { throw ClubActionWriteError.notSent(.notConfigured) }
        let grant = approval()
        if original != nil && !ordinaryAdmissionApproved { throw ClubActionWriteError.notSent(.notConfigured) }
        guard let snapshot = currentSession(), snapshot.identity == expectedIdentity else {
            throw ClubActionWriteError.notSent(.unauthorized)
        }
        guard original == nil || (original?.accountID == snapshot.identity.accountID && original?.clubID == clubID && original?.action == action) else { throw ClubActionWriteError.notSent(.invalidRequest) }
        guard clubID > 0, ClubApplicationMessage.isValid(joinMessage, for: action) else { throw ClubActionWriteError.notSent(.invalidRequest) }
        guard !Task.isCancelled else { throw ClubActionWriteError.cancelledBeforeDispatch }
        let detail: ClubRecord
        do { detail = try await service.detail(id: clubID, token: snapshot.token) }
        catch {
            guard currentSession() == snapshot else { throw ClubActionWriteError.notSent(.unauthorized) }
            if (error as? ClubReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            if Task.isCancelled || error is CancellationError { throw ClubActionWriteError.cancelledBeforeDispatch }
            throw ClubActionWriteError.preflightFailed
        }
        guard currentSession() == snapshot else { throw ClubActionWriteError.notSent(.unauthorized) }
        guard !Task.isCancelled else { throw ClubActionWriteError.cancelledBeforeDispatch }
        guard detail.id == clubID,
              ClubActionAvailability.resolve(detail, viewerIsMerchant: snapshot.viewerIsMerchant) == .available(action) else {
            throw ClubActionWriteError.eligibilityChanged
        }
        guard original == nil || (grant == approval() && ordinaryAdmissionApproved) else { throw ClubActionWriteError.notSent(.notConfigured) }
        if snapshot.viewerIsMerchant && action != .leave && !ordinaryAdmissionApproved { throw ClubActionWriteError.eligibilityChanged }
        do {
            let receipt = try await service.perform(action, clubID: clubID, token: snapshot.token, joinMessage: joinMessage, original: original)
            guard currentSession() == snapshot, original == nil || (grant == approval() && ordinaryAdmissionApproved) else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
            guard !Task.isCancelled else { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
            return receipt
        } catch {
            guard currentSession() == snapshot, original == nil || (grant == approval() && ordinaryAdmissionApproved) else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
            if let writeError = error as? ClubActionWriteError, case .rejected(let failure) = writeError, failure.isUnauthorized { onUnauthorized(snapshot) }
            throw error
        }
    }
    public func recover(_ pending: ClubOrdinaryAdmissionPending, expectedIdentity: ClubReadIdentity) async throws -> ClubOrdinaryAdmissionOriginalReceipt {
        guard let service, ordinaryAdmissionRecoveryApproved, let snapshot = currentSession(), snapshot.identity == expectedIdentity,
              snapshot.identity.accountID == pending.accountID, pending.hasOriginalReceipt else { throw APIError.notConfigured }
        let grant = approval()
        do {
            let result = try await service.recover(pending, token: snapshot.token)
            guard currentSession() == snapshot, approval() == grant, ordinaryAdmissionRecoveryApproved, !Task.isCancelled else { throw CancellationError() }
            return result
        } catch {
            guard currentSession() == snapshot, approval() == grant, !Task.isCancelled else { throw CancellationError() }
            if (error as? ClubReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }

}
