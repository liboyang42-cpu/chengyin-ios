import Foundation

/// Separate token capsule: existing MessageActionSession intentionally keeps token fileprivate.
public struct IMExpandedSession: Equatable {
    public let identity: MessagingReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}
@MainActor public protocol IMExpandedWriting: AnyObject {
    var identity: MessagingReadIdentity? { get }
    var isConfigured: Bool { get }
    func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt
    func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL
}
@MainActor public final class IMExpandedWriter: IMExpandedWriting {
    private let service: IMExpandedService?
    private let session: () -> IMExpandedSession?
    private let onUnauthorized: (IMExpandedSession) -> Void
    public var identity: MessagingReadIdentity? { session()?.identity }
    public var isConfigured: Bool { service?.isConfigured == true }
    public init(service: IMExpandedService? = nil, session: @escaping () -> IMExpandedSession?, onUnauthorized: @escaping (IMExpandedSession) -> Void = { _ in }) { self.service = service; self.session = session; self.onUnauthorized = onUnauthorized }
    public func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = session(), snapshot.identity == expectedIdentity else { throw APIError.unauthorized }
        if case .send(let intent) = mutation, intent.scope.identity != expectedIdentity { throw IMCapabilityGap.staleScope }
        do {
            let result = try await service.perform(mutation, token: snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }; return result
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
    public func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = session(), snapshot.identity == expectedIdentity, selection.scope.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            let result = try await service.upload(selection, consent: consent, token: snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }; return result
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
}
public enum IMReviewState: Equatable { case idle, reviewing(IMMutation), submitting(IMMutation), acknowledged(IMMutationReceipt), outcomeUnknown(IMMutation), rejected(IMMutation), closed }
/// One immutable reviewed mutation per owner. Unknown sends cannot be edited/replaced;
/// retries preserve the exact ID and bytes. No task starts on initialization or dismissal.
@MainActor public final class IMExpandedCoordinator {
    public let scope: IMScope
    public let writer: any IMExpandedWriting
    private var state: IMReviewState = .idle
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { writer.identity == scope.identity }
    public var visibleState: IMReviewState { isCurrent ? state : .idle }
    public init(scope: IMScope, writer: any IMExpandedWriting) { self.scope = scope; self.writer = writer }
    @discardableResult public func review(_ mutation: IMMutation) -> Bool {
        guard isCurrent, writer.isConfigured else { return false }
        switch state { case .submitting, .outcomeUnknown, .closed: return false; default: break }
        guard mutation.conversationID == nil || mutation.conversationID == scope.conversationID else { return false }
        if case .send(let intent) = mutation, intent.scope != scope { return false }
        state = .reviewing(mutation); onChange?(); return true
    }
    public func cancelReview() { if case .reviewing = state { state = .idle; onChange?() } }
    public func confirm() async {
        guard case .reviewing(let mutation) = state else { return }
        await dispatch(mutation)
    }
    public func retryUnchanged() async {
        switch state { case .outcomeUnknown(let mutation), .rejected(let mutation): await dispatch(mutation); default: return }
    }
    private func dispatch(_ mutation: IMMutation) async {
        guard isCurrent, writer.isConfigured, !Task.isCancelled else { return }
        state = .submitting(mutation); onChange?()
        do {
            let receipt = try await writer.perform(mutation, expectedIdentity: scope.identity)
            guard isCurrent, !Task.isCancelled else { state = .outcomeUnknown(mutation); onChange?(); return }
            state = .acknowledged(receipt)
        } catch {
            if isCurrent, let failure = error as? MessagingReadFailure, failure.httpStatus == nil, failure.isClosed { state = .closed }
            else if isCurrent, let failure = error as? MessagingReadFailure, failure.httpStatus == nil, let code = failure.code, [400,401,403,404].contains(code) { state = .rejected(mutation) }
            else { state = .outcomeUnknown(mutation) }
        }
        onChange?()
    }
}
/// Source uses explicit latest-page refresh, not realtime. Generation protects against old
/// completions across conversation, account epoch, cancellation and repeated refreshes.
public struct IMRefreshGate: Equatable {
    public private(set) var scope: IMScope?
    public private(set) var generation: UInt64 = 0
    public private(set) var loading = false
    public init() {}
    public mutating func begin(_ scope: IMScope) -> UInt64 { generation &+= 1; self.scope = scope; loading = true; return generation }
    public mutating func finish(_ generation: UInt64, scope: IMScope) -> Bool {
        guard self.generation == generation, self.scope == scope, loading else { return false }; loading = false; return true
    }
    public mutating func cancel() { generation &+= 1; scope = nil; loading = false }
}

@MainActor public final class IMConversationStarter {
    public let identity: MessagingReadIdentity
    public let writer: any IMExpandedWriting
    private var state: IMReviewState = .idle
    public var onChange: (() -> Void)?
    public var visibleState: IMReviewState { writer.identity == identity ? state : .idle }
    public init(identity: MessagingReadIdentity, writer: any IMExpandedWriting) { self.identity = identity; self.writer = writer }
    public func cancelReview() { if case .reviewing = state { state = .idle; onChange?() } }
    public func review(targetMemberID: Int) {
        guard writer.identity == identity, writer.isConfigured, targetMemberID > 0 else { return }
        switch state { case .submitting, .outcomeUnknown: return; default: break }
        state = .reviewing(.start(targetMemberID: targetMemberID)); onChange?()
    }
    public func confirm() async {
        guard writer.identity == identity, case .reviewing(let mutation) = state else { return }
        state = .submitting(mutation); onChange?()
        do {
            let receipt = try await writer.perform(mutation, expectedIdentity: identity)
            guard writer.identity == identity, !Task.isCancelled else { state = .outcomeUnknown(mutation); onChange?(); return }
            state = .acknowledged(receipt)
        } catch { state = .outcomeUnknown(mutation) }
        onChange?()
    }
    public func retryUnchanged() async {
        guard writer.identity == identity, case .outcomeUnknown(let mutation) = state else { return }
        state = .reviewing(mutation); await confirm()
    }
}
