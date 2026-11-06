import Foundation

/// Mini-program complaint/index topic-load failure copy: one title, with a sub line
/// per failure kind. Display only; retry rules stay with ProfileComplaintReadIssue.
public extension ProfileComplaintReadIssue {
    /// Source title 可投诉活动没能加载出来 for every load failure.
    var sourceTitleKey: String { "profile.complaintP2.loadFailed.title" }

    /// Source sub line: generic 可投诉活动加载失败，请重试, or 登录状态已失效，请重新进入 for an
    /// expired session. The selector-unavailable case keeps its own native line.
    var sourceDetailKey: String {
        switch self {
        case .failed: return "profile.complaintP2.loadFailed.generic"
        case .signIn: return "profile.complaintP2.loadFailed.signIn"
        case .unavailable: return titleKey
        }
    }
}
