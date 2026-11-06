import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public metadata only. A configured viewer approval is independent of the selected member.
@MainActor @Observable public final class ProfilePublicInfoReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        try ProfileFavoritesRequestContract.validate(context, approval, paths: [ProfilePublicInfoReadRoute.path])
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}
public struct ProfilePublicInfoReadRoute: Equatable {
    public static let path = "api/user/public-info"
    public let memberID: Int
    public init?(request: URLRequest, baseURL: URL) {
        guard let (_, fields) = ProfileFavoritesRequestContract.fields(request, baseURL: baseURL, paths: [Self.path]),
              Set(fields.keys) == ["member_id"], let id = ProfileFavoritesRequestContract.positive(fields["member_id"]) else { return nil }
        memberID = id
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard try ProfileFavoritesRequestContract.isSuccess(response) else { return }
        struct Member: Decodable { let id: Int }
        struct Envelope: Decodable { let data: Member }
        do {
            guard try JSONDecoder().decode(Envelope.self, from: response.0).data.id == memberID else { throw APIError.malformedResponse }
        } catch { throw APIError.malformedResponse }
    }
}

/// One explicit profile target and one signed-in viewer lifetime; this is not a grant.
@MainActor @Observable public final class ProfilePublicInfoTarget {
    public let id = UUID()
    public let memberID: Int
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    private let current: () -> Bool
    public private(set) var isRetired = false
    public init(memberID: Int, context: RuntimeDependencyContext, viewerRevision: UInt64, current: @escaping () -> Bool) throws {
        guard memberID > 0 else { throw APIError.invalidRequest }
        self.memberID = memberID; self.context = context; self.viewerRevision = viewerRevision; self.current = current
    }
    public var isCurrent: Bool {
        guard !isRetired else { return false }
        guard current() else { isRetired = true; return false }
        return true
    }
    public func retire() { isRetired = true }
}
