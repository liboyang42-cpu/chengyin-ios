import Foundation

public extension SquareGovernanceComment {
    /// Apply patches/SquareContracts.version.patch first. Both arguments must be
    /// refreshed by the host for the same post/session; a cached display is not proof.
    init(comment: SquareComment, post: SquarePost) {
        self.init(id: comment.id, postID: post.id, postAuthorID: post.memberID, raw: .object([
            "author_id": .integer(comment.memberID),
            "version": comment.version.map { .integer($0) } ?? .null,
            "author_approval_state": .string(comment.approvalState),
            "lifecycle": .string(comment.lifecycle)
        ]))
    }
}
