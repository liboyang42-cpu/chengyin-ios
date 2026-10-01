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
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt
}

/// Reads detail again immediately before dispatch. A changed account/epoch/token or
/// changed membership/policy cancels the original intent rather than changing it.
@MainActor
public final class ClubActionSessionWriter: ClubActionWriting {
    private let service: ClubActionService?
    private let currentSession: () -> ClubActionSession?
    private let onUnauthorized: (ClubActionSession) -> Void
    public var isConfigured: Bool { service != nil }
    public var identity: ClubReadIdentity? { currentSession()?.identity }
    public var viewerIsMerchant: Bool { currentSession()?.viewerIsMerchant ?? false }
    public init(service: ClubActionService?, currentSession: @escaping () -> ClubActionSession?,
                onUnauthorized: @escaping (ClubActionSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        guard let service else { throw ClubActionWriteError.notSent(.notConfigured) }
        guard let snapshot = currentSession(), snapshot.identity == expectedIdentity else {
            throw ClubActionWriteError.notSent(.unauthorized)
        }
        guard clubID > 0 else { throw ClubActionWriteError.notSent(.invalidRequest) }
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
        do {
            let receipt = try await service.perform(action, clubID: clubID, token: snapshot.token)
            guard currentSession() == snapshot else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
            guard !Task.isCancelled else { throw ClubActionWriteError.outcomeUnknown(.cancelled) }
            return receipt
        } catch {
            guard currentSession() == snapshot else { throw ClubActionWriteError.outcomeUnknown(.accountChanged) }
            if let writeError = error as? ClubActionWriteError, case .rejected(let failure) = writeError, failure.isUnauthorized { onUnauthorized(snapshot) }
            throw error
        }
    }
}
