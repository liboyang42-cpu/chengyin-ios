import Foundation

/// Both direct join and an approval request use the source /join route. No approval,
/// payment, administrator, invite, or owner-transfer route is implied by these cases.
public enum ClubAction: String, Equatable { case join, apply, leave }

public enum ClubActionAvailability: Equatable {
    case available(ClubAction), owner, pending, merchant, unsupportedStatus
    public static func resolve(_ club: ClubRecord, viewerIsMerchant: Bool) -> Self {
        if club.isOwner { return .owner }
        if club.isJoined { return .available(.leave) }
        if viewerIsMerchant { return .merchant }
        if club.joinPending { return .pending }
        if let status = club.myJoinStatus, ![1, 2].contains(status) { return .unsupportedStatus }
        return .available(club.needsApproval ? .apply : .join)
    }
}

public struct ClubActionResponseFailure: Error, Equatable {
    public let httpStatus: Int?
    public let code: Int?
    public let message: String?
    public var isUnauthorized: Bool { httpStatus == 401 || code == 401 }
    public init(httpStatus: Int? = nil, code: Int? = nil, message: String? = nil) {
        self.httpStatus = httpStatus; self.code = code; self.message = message
    }
}

public enum ClubActionIssue: Equatable {
    case cancelled, transport, malformedResponse, accountChanged
    case response(ClubActionResponseFailure)
}
public enum ClubActionWriteError: Error, Equatable {
    case notSent(APIError), cancelledBeforeDispatch, eligibilityChanged
    case preflightFailed
    case rejected(ClubActionResponseFailure)
    case outcomeUnknown(ClubActionIssue)
}

/// Acknowledgment is not a membership fact. In particular nil/unknown state is never
/// converted to joined or pending; a subsequent /detail is the visible source of truth.
public struct ClubActionReceipt: Equatable {
    public let state: String?
    public let message: String?
    public init(state: String?, message: String?) { self.state = state; self.message = message }
}
