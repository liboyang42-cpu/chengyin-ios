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

/// Distinguishes transport/network failures (`网络连接失败`) from business/service unavailability (`通知工具暂时不可用` / `入会申请加载失败`).
public enum ClubOpsNetworkFailureClassifier: Equatable {
    public enum Kind: Equatable {
        case network
        case serviceUnavailable
    }

    public enum Surface: Equatable {
        case notify
        case joinRequests
    }

    public static let networkFailureTitle = "网络连接失败"
    public static let notifyUnavailableTitle = "通知工具暂时不可用"
    public static let joinRequestsUnavailableTitle = "入会申请加载失败"

    public static func classify(_ error: Error) -> Kind {
        if error is ClubManagementListConnectionFailure {
            return .network
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .dnsLookupFailed, .notConnectedToInternet:
                return .network
            default:
                return .serviceUnavailable
            }
        }
        return .serviceUnavailable
    }

    public static func title(for surface: Surface, kind: Kind) -> String {
        switch kind {
        case .network:
            return networkFailureTitle
        case .serviceUnavailable:
            switch surface {
            case .notify: return notifyUnavailableTitle
            case .joinRequests: return joinRequestsUnavailableTitle
            }
        }
    }

    public static func title(for surface: Surface, error: Error) -> String {
        title(for: surface, kind: classify(error))
    }
}

/// Per-row join-request failure banner (`这次处理没有完成`) paired with a readback-safe `重新核对` action.
/// Never replays a write; its action only triggers a fresh list readback.
public struct ClubJoinRequestRowIssuePresentation: Equatable {
    public static let issueTitle = "这次处理没有完成"
    public static let actionTitle = "重新核对"

    public let memberID: Int
    public let title: String
    public let actionTitle: String
    public let replaysWrite: Bool

    public init?(memberID: Int, failedMemberID: Int?, submitting: Bool = false) {
        guard !submitting, memberID > 0, failedMemberID == memberID else { return nil }
        self.memberID = memberID
        self.title = Self.issueTitle
        self.actionTitle = Self.actionTitle
        self.replaysWrite = false
    }
}
