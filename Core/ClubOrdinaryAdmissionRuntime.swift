import Foundation

/// Explicit host-issued original-protocol approval. It never changes server membership
/// permissions or the existing native merchant gate. No production issuer is supplied.
public struct ClubOrdinaryAdmissionApproval: Equatable {
    public let context: RuntimeDependencyContext
    public let allowsWrites: Bool
    public let revision: UUID
    public var configurationRevision: UUID? { revision }
    public var identity: ClubReadIdentity { ClubReadIdentity(accountID: context.session.accountID, epoch: context.session.epoch) }
    public var baseURL: URL { context.baseURL }
    public init(context: RuntimeDependencyContext, revision: UUID = UUID(), allowsWrites: Bool = false) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, !context.role.isEmpty, !context.session.namespace.isEmpty,
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token) else { throw APIError.invalidConfiguration }
        self.context = context; self.revision = revision; self.allowsWrites = allowsWrites
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(self.context, context)
    }
}
