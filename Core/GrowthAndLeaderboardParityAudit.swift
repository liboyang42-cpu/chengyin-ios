import Foundation

/// Pure self-contained value types auditing `w2-10` & `I07` growth, badge & leaderboard parity:
/// 1. `GrowthCenterService.leaderboard`: `application/x-www-form-urlencoded` body encoding (`type`, `pageNum`, `pageSize`).
/// 2. `GrowthLeaderboardStanding`: server standing preservation (never fabricating rank when absent).
/// 3. Blank nickname avatar monogram fallback (`"匿"`).
/// 4. `ProfileReadFailure.isDenied`: `403` permission denied distinct from `401` unauthorized session expiry.
public enum GrowthLeaderboardStandingAudit: Equatable, Sendable {
    case ranked(Int)
    case unrankedServerOmitted
}

public enum GrowthProfileHTTPFailureKind: Equatable, Sendable {
    case unauthorizedSessionExpired401
    case permissionDenied403
    case otherStatus(Int)

    public var isDenied: Bool {
        self == .permissionDenied403
    }

    public var isSessionExpired: Bool {
        self == .unauthorizedSessionExpired401
    }
}

public struct GrowthAndLeaderboardParityAudit: Equatable, Sendable {
    public static let expectedContentType = "application/x-www-form-urlencoded"
    public static let blankNicknameMonogramFallback = "匿"

    public let contentType: String
    public let preservesAbsentServerRank: Bool
    public let blankMonogramFallback: String
    public let separates403From401: Bool

    public init(
        contentType: String = GrowthAndLeaderboardParityAudit.expectedContentType,
        preservesAbsentServerRank: Bool = true,
        blankMonogramFallback: String = GrowthAndLeaderboardParityAudit.blankNicknameMonogramFallback,
        separates403From401: Bool = true
    ) {
        self.contentType = contentType
        self.preservesAbsentServerRank = preservesAbsentServerRank
        self.blankMonogramFallback = blankMonogramFallback
        self.separates403From401 = separates403From401
    }

    public var isAllCompliant: Bool {
        contentType == Self.expectedContentType
            && preservesAbsentServerRank
            && blankMonogramFallback == Self.blankNicknameMonogramFallback
            && separates403From401
    }

    /// Builds and validates the `application/x-www-form-urlencoded` body for `GrowthCenterService.leaderboard`.
    public static func encodeLeaderboardFormBody(
        type: String,
        pageNum: Int,
        pageSize: Int
    ) -> String? {
        let trimmedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedType.isEmpty, pageNum >= 1, (1...100).contains(pageSize) else {
            return nil
        }
        let escapedType = trimmedType.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedType
        return "type=\(escapedType)&pageNum=\(pageNum)&pageSize=\(pageSize)"
    }

    /// Preserves the server-supplied standing rank if positive; never fabricates a rank from array index when absent or non-positive.
    public static func resolveServerStanding(serverRank: Int?) -> GrowthLeaderboardStandingAudit {
        guard let serverRank, serverRank > 0 else {
            return .unrankedServerOmitted
        }
        return .ranked(serverRank)
    }

    /// Resolves avatar monogram text, falling back to `"匿"` when the nickname is nil or whitespace-only.
    public static func avatarMonogram(for nickname: String?) -> String {
        guard let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
              let first = trimmed.first else {
            return blankNicknameMonogramFallback
        }
        return String(first)
    }

    /// Classifies profile/growth HTTP status codes so `403` (`isDenied == true`) is never conflated with `401` session expiry.
    public static func classifyHTTPFailure(statusCode: Int) -> GrowthProfileHTTPFailureKind {
        switch statusCode {
        case 401:
            return .unauthorizedSessionExpired401
        case 403:
            return .permissionDenied403
        default:
            return .otherStatus(statusCode)
        }
    }
}
