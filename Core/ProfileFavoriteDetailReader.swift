import Foundation

/// Reuses the existing detail service, scoped to one explicit current saved-post selection.
@MainActor public final class ProfileFavoriteDetailReader: SquareReading {
    public let selection: ProfileFavoritePostSelection
    private let service: SquareService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> ProfileFavoriteDetailAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var pendingDetail: (id: UUID, task: Task<SquarePost, Error>)?
    private var confirmedAccess: UUID?
    public let scope = UUID()
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
    public func retire() { selection.retire(); pendingDetail?.task.cancel(); pendingDetail = nil; confirmedAccess = nil }
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
        if let pendingDetail { started = pendingDetail }
        else {
            confirmedAccess = nil; selection.beginDetailRead()
            let id = UUID()
            let task = Task { @MainActor [self] in
                guard let access = activeAccess() else { throw APIError.notConfigured }
                let post = try await read { try await $0.detail(route: selection.route, token: $1) }
                guard activeAccess() === access, post.id == selection.route.id, post.generation == selection.route.generation else { throw CancellationError() }
                selection.confirmDetailRead(access: access)
                confirmedAccess = access.revision
                return post
            }
            started = (id, task); pendingDetail = started
        }
        do {
            let post = try await started.task.value
            try Task.checkCancellation()
            guard activeAccess() === capturedAccess else { throw CancellationError() }
            if pendingDetail?.id == started.id { pendingDetail = nil }
            return post
        } catch {
            if pendingDetail?.id == started.id { pendingDetail = nil }
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
