import Foundation

/// Mini pages/club/join-requests copy. Display only: approve/reject keep the existing review, claim and lock.
public enum ClubOpsJoinRequestCopy {
    /// `正在通过…` / `正在拒绝…` only on the row whose confirmed write is in flight; nil keeps the existing label.
    public static func progressKey(_ action: ClubManagementAction, submitting: Bool, actingAction: ClubManagementAction?,
                                   actingMemberID: Int?, memberID: Int) -> String? {
        guard submitting, actingAction == action, actingMemberID == memberID else { return nil }
        switch action {
        case .approve: return "clubOpsJoin.approving"
        case .reject: return "clubOpsJoin.rejecting"
        case .remove: return nil
        }
    }
    public enum LoadIssue: Equatable { case failed, stale }
    /// `入会申请加载失败` without a list, `入会申请暂未更新` over a retained one. Denial keeps its own copy.
    /// The only offered action is the existing read refresh, never a replayed write.
    public static func loadIssue(failed: Bool, denied: Bool, stale: Bool, hasSnapshot: Bool) -> LoadIssue? {
        // A kept list is only "not updated" after a failed reload; an in-flight refresh is not an issue.
        if failed && stale && hasSnapshot { return .stale }
        guard failed, !denied, !hasSnapshot else { return nil }
        return .failed
    }
}

/// Mini page-level failure titles for notify / governance / roles reads. Denial uses each page's own note instead.
public struct ClubOpsPageFailureCopy: Equatable {
    public let table: String
    public let titleKey: String
    public let retryKey: String
    public init?(operation: ClubGovernanceRead, failure: ClubGovernanceFailure) {
        guard failure != .forbidden, failure != .signedOut else { return nil }
        switch operation {
        case .audienceCounts: table = "ClubOpsJoinNotify"; titleKey = "clubOpsNotify.failed"; retryKey = "clubOpsNotify.retry"
        case .bans, .members, .cases: table = "ClubOpsGovernance"; titleKey = "clubOpsGov.failed"; retryKey = "clubOpsGov.retry"
        case .roles: table = "ClubOpsGovernance"; titleKey = "clubOpsGov.roles.failed"; retryKey = "clubOpsGov.retry"
        default: return nil
        }
    }
}

