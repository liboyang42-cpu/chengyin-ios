import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// An explicitly injected, revocable capability for one saved-post removal.
/// This does not turn a favorites-list read approval into write authority.
@MainActor @Observable public final class ProfileFavoriteRemovalAccess {
    public let context: RuntimeDependencyContext
    public let approval: ProfileFavoriteRemovalApproval
    public let collectionScope: UUID
    public let revision = UUID()
    public private(set) var isRevoked = false

    public init(context: RuntimeDependencyContext, collectionScope: UUID,
                approval: ProfileFavoriteRemovalApproval) throws {
        try ProfileFavoritesRequestContract.validate(context, approval.endpoint,
            paths: ProfileFavoriteRemovalApproval.paths)
        guard context.market == .china,
              approval.identity.accountID == context.session.accountID,
              approval.identity.epoch == context.session.epoch,
              approval.identity.role == context.role else { throw APIError.invalidConfiguration }
        self.context = context; self.collectionScope = collectionScope; self.approval = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext, collectionScope: UUID,
                        postID: Int, now: Date = Date()) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current) &&
        self.collectionScope == collectionScope && approval.postID == postID && now < approval.expiresAt
    }
}

/// Only the existing readback or explicit bookmark=0 body is admissible.
/// Toggle, add-favorite, topic-unlike and extra authority fields are excluded.
public struct ProfileFavoriteRemovalRoute: Equatable {
    public enum Kind: Equatable { case readback, remove(requestID: UUID) }
    public let postID: Int
    public let kind: Kind
    public init?(request: URLRequest, baseURL: URL) {
        guard let (path, fields) = ProfileFavoritesRequestContract.fields(request, baseURL: baseURL,
                paths: ProfileFavoriteRemovalApproval.paths),
              let postID = ProfileFavoritesRequestContract.positive(fields["id"]) else { return nil }
        if path == "api/creativesquare/info" {
            guard Set(fields.keys) == ["id"] else { return nil }
            kind = .readback
        } else {
            guard Set(fields.keys) == ["id", "bookmark", "request_id"], fields["bookmark"] == "0",
                  let raw = fields["request_id"], let id = UUID(uuidString: raw),
                  raw == id.uuidString else { return nil }
            kind = .remove(requestID: id)
        }
        self.postID = postID
    }
}

/// Separate from ordinary composition transport. A list/detail reader never receives it.
@MainActor public final class ProfileFavoriteRemovalTransport: HTTPTransport {
    private let accesses: [ProfileFavoriteRemovalAccess]
    private let collectionScope: UUID
    private let current: () -> RuntimeDependencyContext?
    private let currentScope: () -> UUID?
    private let select: (RuntimeDependencyContext, UUID) -> [ProfileFavoriteRemovalAccess]
    private let underlying: any HTTPTransport
    private let now: () -> Date
    public init(accesses: [ProfileFavoriteRemovalAccess], collectionScope: UUID,
                underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                currentScope: @escaping () -> UUID?,
                select: @escaping (RuntimeDependencyContext, UUID) -> [ProfileFavoriteRemovalAccess],
                now: @escaping () -> Date = Date.init) {
        self.accesses = accesses; self.collectionScope = collectionScope; self.underlying = underlying
        self.current = current; self.currentScope = currentScope; self.select = select; self.now = now
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard let context = current(), currentScope() == collectionScope,
              request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              let route = ProfileFavoriteRemovalRoute(request: request, baseURL: context.baseURL) else {
            throw ProfileFavoriteRemovalFailure.disabled
        }
        let candidates = accesses.filter { $0.matches(context, collectionScope: collectionScope, postID: route.postID, now: now()) }
        guard candidates.count == 1, let selected = candidates.first else { throw ProfileFavoriteRemovalFailure.disabled }
        func valid() -> Bool {
            guard let fresh = current(), ContentDraftContextFence.matches(context, fresh), currentScope() == collectionScope,
                  selected.matches(fresh, collectionScope: collectionScope, postID: route.postID, now: now()) else { return false }
            let offered = select(fresh, collectionScope).filter { $0.matches(fresh, collectionScope: collectionScope, postID: route.postID, now: now()) }
            return offered.count == 1 && offered.first === selected
        }
        guard valid() else { throw ProfileFavoriteRemovalFailure.stale }
        do {
            let response = try await underlying.send(request)
            try Task.checkCancellation()
            guard valid() else { throw ProfileFavoriteRemovalFailure.stale }
            return response
        } catch {
            guard valid() else { throw ProfileFavoriteRemovalFailure.stale }
            throw error
        }
    }
}
