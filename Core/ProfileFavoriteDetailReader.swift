import Foundation
import Observation

/// Reuses the existing detail service, scoped to one explicit current saved-post selection.
@MainActor @Observable public final class ProfileFavoriteDetailReader: SquareReading {
    public let selection: ProfileFavoritePostSelection
    private let service: SquareService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> ProfileFavoriteDetailAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    // These existing read-state fields must invalidate the mounted detail entry even
    // when its guard returns before reading the observable selection/access.
    private var pendingDetail: (id: UUID, access: UUID, task: Task<SquarePost, Error>)?
    private var latestDetailRead: UUID?
    private var confirmedAccess: UUID?
    private let unavailableScope = UUID()
    /// The original detail view already keys its loaded projection and read task by
    /// this scope. A current access replacement must invalidate both post and comments,
    /// even when the account, selection and configured Boolean remain unchanged.
    /// Reading the selector/revocation here also participates in Swift Observation;
    /// a supplied replacement selector must publish changes (or revoke its old access).
    public var scope: UUID { activeAccess()?.revision ?? unavailableScope }
    public init(selection: ProfileFavoritePostSelection, service: SquareService?,
                current: @escaping () -> RuntimeDependencyContext?, viewerRevision: @escaping () -> UInt64,
                access: @escaping (RuntimeDependencyContext) -> ProfileFavoriteDetailAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.selection = selection; self.service = service; self.current = current; self.viewerRevision = viewerRevision
        selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var isConfigured: Bool { activeAccess() != nil && service != nil }
    public var isSignedIn: Bool { current() != nil }
    public var isOfflineExample: Bool { false }
    /// True only while the CURRENT detail access is the exact revision that confirmed this
    /// selection's detail read. Revocation, revision replacement, account/viewer change,
    /// a later failed or in-flight re-read, or a retired selection all make it false.
    public var confirmsCurrentDetail: Bool {
        guard pendingDetail == nil, let access = activeAccess(), let confirmedAccess,
              confirmedAccess == access.revision else { return false }
        return selection.permitsComments(access: access)
    }
    public func retire() { selection.retire(); pendingDetail?.task.cancel(); pendingDetail = nil; latestDetailRead = nil; confirmedAccess = nil }
    private func activeAccess() -> ProfileFavoriteDetailAccess? {
        guard selection.isCurrent, let context = current(),
              ContentDraftContextFence.matches(selection.context, context), viewerRevision() == selection.viewerRevision,
              let selected = selectAccess(context), selected.matches(context) else { return nil }
        return selected
    }
    public func squareFeed(query: SquareQuery, cursor: SquareCursor?) async throws -> SquareFeedPage { throw APIError.notConfigured }
    public func squareDetail(id: Int) async throws -> SquarePost {
        guard id == selection.route.id else { throw APIError.invalidRequest }
        return try await detail()
    }
    public func squareDetail(route: SquareContentRoute) async throws -> SquarePost {
        guard route == selection.route else { throw APIError.invalidRequest }
        return try await detail()
    }
    public func squareComments(route: SquareContentRoute, pageNumber: Int) async throws -> SquareCommentPage {
        guard route == selection.route else { throw APIError.invalidRequest }
        return try await squareComments(postID: route.id, pageNumber: pageNumber)
    }
    public func squareComments(postID: Int, pageNumber: Int) async throws -> SquareCommentPage {
        guard postID == selection.route.id, pageNumber > 0 else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        guard let access = activeAccess() else { throw APIError.notConfigured }
        // The existing screen starts both reads together. Join its detail request;
        // never expose comments if the selected detail is denied or unavailable.
        if pendingDetail != nil || confirmedAccess != access.revision { _ = try await detail() }
        guard confirmedAccess == access.revision, activeAccess() === access else { throw CancellationError() }
        return try await read { try await $0.comments(postID: postID, pageNumber: pageNumber, token: $1) }
    }
    private func detail() async throws -> SquarePost {
        try Task.checkCancellation()
        guard let capturedAccess = activeAccess() else { throw APIError.notConfigured }
        let started: (id: UUID, task: Task<SquarePost, Error>)
        if let pendingDetail, pendingDetail.access == capturedAccess.revision {
            started = (pendingDetail.id, pendingDetail.task)
        } else {
            // Coalesce only reads made under the same approval. B must not join A's
            // suspended task or wait for an uncooperative retired transport to finish.
            pendingDetail?.task.cancel()
            confirmedAccess = nil; selection.beginDetailRead()
            let id = UUID()
            latestDetailRead = id
            let task = Task { @MainActor [self] in
                guard activeAccess() === capturedAccess, latestDetailRead == id else { throw CancellationError() }
                let post = try await read { try await $0.detail(route: selection.route, token: $1) }
                guard activeAccess() === capturedAccess, latestDetailRead == id,
                      post.id == selection.route.id, post.generation == selection.route.generation else { throw CancellationError() }
                selection.confirmDetailRead(access: capturedAccess)
                confirmedAccess = capturedAccess.revision
                return post
            }
            started = (id, task); pendingDetail = (id, capturedAccess.revision, task)
        }
        do {
            let post = try await started.task.value
            try Task.checkCancellation()
            guard activeAccess() === capturedAccess, latestDetailRead == started.id else { throw CancellationError() }
            if pendingDetail?.id == started.id { pendingDetail = nil }
            return post
        } catch {
            // Keep the latest attempt identity after completion as well: a retired A
            // may fail after B completed and cleared pendingDetail. It must not erase B.
            if latestDetailRead == started.id {
                pendingDetail = nil; confirmedAccess = nil; selection.beginDetailRead()
            }
            throw error
        }
    }
    private func read<T>(_ operation: (SquareService, String) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard let access = activeAccess(), let service else { throw APIError.notConfigured }
        func valid() -> Bool { !Task.isCancelled && activeAccess() === access }
        do {
            let value = try await operation(service, selection.context.session.token)
            guard valid() else { throw CancellationError() }
            return value
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(selection.context) }
            throw error
        }
    }
}
