import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A saved-topic selection never substitutes for this independent detail approval.
@MainActor @Observable public final class ProfileFavoriteTopicReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        try ProfileFavoritesRequestContract.validate(context, approval, paths: [ProfileFavoriteTopicReadRoute.path])
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}
public struct ProfileFavoriteTopicReadRoute: Equatable {
    public static let path = "api/topic/info-to-user"
    public let topicID: Int
    public init?(request: URLRequest, baseURL: URL) {
        guard let (_, fields) = ProfileFavoritesRequestContract.fields(request, baseURL: baseURL, paths: [Self.path]),
              Set(fields.keys) == ["id"], let id = ProfileFavoritesRequestContract.positive(fields["id"]) else { return nil }
        topicID = id
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard try ProfileFavoritesRequestContract.isSuccess(response) else { return }
        struct Topic: Decodable { let id: Int; let name: String }
        struct Envelope: Decodable { let data: Topic }
        do {
            let topic = try JSONDecoder().decode(Envelope.self, from: response.0).data
            guard topic.id == topicID, !topic.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.malformedResponse }
        } catch { throw APIError.malformedResponse }
    }
}

/// The exact current saved-list receipt and explicit topic action own this lifetime.
@MainActor @Observable public final class ProfileFavoriteTopicSelection: Identifiable, Hashable {
    public nonisolated let id = UUID()
    public let topicID: Int
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    private let current: () -> Bool
    public private(set) var isRetired = false
    init(topicID: Int, context: RuntimeDependencyContext, viewerRevision: UInt64, current: @escaping () -> Bool) {
        self.topicID = topicID; self.context = context; self.viewerRevision = viewerRevision; self.current = current
    }
    public var isCurrent: Bool {
        guard !isRetired else { return false }
        guard current() else { isRetired = true; return false }
        return true
    }
    public func retire() { isRetired = true }
    public nonisolated static func == (lhs: ProfileFavoriteTopicSelection, rhs: ProfileFavoriteTopicSelection) -> Bool { lhs.id == rhs.id }
    public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor public final class ProfileFavoriteTopicReader: TopicReading {
    public let selection: ProfileFavoriteTopicSelection
    private let service: TopicService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> ProfileFavoriteTopicReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var observedAccess: UUID?
    private var stamp = UUID()
    public init(selection: ProfileFavoriteTopicSelection, service: TopicService?,
                current: @escaping () -> RuntimeDependencyContext?, viewerRevision: @escaping () -> UInt64,
                access: @escaping (RuntimeDependencyContext) -> ProfileFavoriteTopicReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.selection = selection; self.service = service; self.current = current; self.viewerRevision = viewerRevision
        selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var isConfigured: Bool { activeAccess() != nil && service != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID { _ = activeAccess(); return stamp }
    private func activeAccess() -> ProfileFavoriteTopicReadAccess? {
        let access: ProfileFavoriteTopicReadAccess?
        if selection.isCurrent, let fresh = current(), ContentDraftContextFence.matches(selection.context, fresh),
           viewerRevision() == selection.viewerRevision, let selected = selectAccess(fresh), selected.matches(fresh) { access = selected }
        else { access = nil }
        if observedAccess != access?.revision { observedAccess = access?.revision; stamp = UUID() }
        return access
    }
    public func topicList(query: TopicQuery, pageNumber: Int) async throws -> TopicPage { throw APIError.notConfigured }
    public func topicDetail(id: Int) async throws -> TopicDetail {
        guard id == selection.topicID else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        guard let access = activeAccess(), let service else { throw APIError.notConfigured }
        let capturedScope = stamp
        func valid() -> Bool { !Task.isCancelled && activeAccess() === access && stamp == capturedScope }
        do {
            let result = try await service.detail(id: id, token: selection.context.session.token)
            guard valid() else { throw CancellationError() }
            return result
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(selection.context) }
            throw error
        }
    }
}
