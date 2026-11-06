import Foundation

/// Invitation-history failure copy from the mini-program 邀请记录 page:
/// signed out, 403, and other failures each keep their own title and hint.
public enum ProfileInviteHistoryIssueKind: Equatable {
    case signIn, denied, unavailable, failed
    public init(_ error: Error) {
        switch error {
        case APIError.unauthorized: self = .signIn
        case APIError.notConfigured: self = .unavailable
        case APIError.httpStatus(403), APIError.businessCode(403): self = .denied
        case SocialAccountFailure.rejected(code: 401, message: _): self = .signIn
        case SocialAccountFailure.rejected(code: 403, message: _): self = .denied
        default: self = .failed
        }
    }
    public var titleKey: String {
        switch self {
        case .signIn: return "profile.inviteHistory.signIn"
        case .denied: return "profile.inviteHistory.denied"
        case .unavailable: return "social.notConfigured"
        case .failed: return "profile.inviteHistory.failed"
        }
    }
    public var detailKey: String? {
        switch self {
        case .signIn: return "profile.inviteHistory.signInHint"
        case .denied: return "profile.inviteHistory.deniedHint"
        case .unavailable: return nil
        case .failed: return "profile.inviteHistory.failedHint"
        }
    }
    /// Only ordinary failures retry; access problems need a new session or permission.
    public var canRetry: Bool { self == .failed }
}
