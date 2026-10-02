import Foundation

extension RetainedUploadedImage {
    public func validateReview(target: PublicMerchantReviewTarget, registrationID: Int, session: PublicMerchantReviewSession) throws {
        guard scope.accountID == session.accountID, scope.epoch == session.scope, scope.realm == session.realm,
              scope.destination == .publicReview(merchantRowID: target.merchantRowID.rawValue, registrationID: registrationID) else { throw PublicMerchantReviewWriteFailure.sessionChanged }
    }
    /// Changes a local draft only. Existing MerchantOperations review/journal/save still owns mutation.
    public func applying(to draft: MerchantOperationsDraft, expectedScope: RetainedImageScope) throws -> MerchantOperationsDraft {
        guard scope == expectedScope, case .merchant(_, let field) = scope.destination else { throw RetainedImageFailure.stale }
        let value = url.absoluteString
        switch (field, draft) {
        case (.logo, .profile(var d)): d.logo = value; return .profile(d)
        case (.coverImage, .decor(var d)): d.coverImage = value; return .decor(d)
        case (.gallery, .gallery(var d)):
            guard d.gallery.count < 9, !d.gallery.contains(value) else { throw RetainedImageFailure.invalid }
            d.gallery.append(value); return .gallery(d)
        case (.avatar, .character(var d)): d.avatar = value; return .character(d)
        case (.imgUrl, .template(var d)):
            guard d.id == scope.resourceID, scope.accessRevision != nil else { throw RetainedImageFailure.stale }
            d.imgURL = value; return .template(d)
        default: throw RetainedImageFailure.invalid
        }
    }
    /// This is avatar-image provenance only; voice sample identity is never fabricated here.
    public func npcAvatar(scope npc: MerchantNPCScope, realm: String, approvedHosts: Set<String>) throws -> MerchantNPCMediaReference {
        guard let namespace = scope.namespace, !namespace.isEmpty, namespace == npc.namespace,
              scope.accountID == npc.accountID, scope.epoch == npc.epoch, scope.realm == realm, scope.accessRevision == npc.accessRevision,
              scope.destination == .merchant(merchantRowID: npc.merchantRowID.rawValue, field: .avatar) else { throw RetainedImageFailure.stale }
        return try .init(scope: npc, selectionID: id, kind: .avatarImage, url: url, approvedHosts: approvedHosts)
    }
}
