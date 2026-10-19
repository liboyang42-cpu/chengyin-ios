import Foundation

/// Mini-program pages/club/notify presentation. Display only: every read, preview, send and
/// retry keeps the existing governance permission, validation, review and production gates.
public struct ClubOpsNotifyCampaign: Equatable {
    public enum Phase: String, Equatable { case completed, partialFailed, delivering }
    public let id: Int
    public let totalCount: Int
    public let successCount: Int
    public let failedCount: Int
    public let phase: Phase
    /// Only an explicit `PROCESSING` shows "后台还在投递" (CU-C-135).
    public let processing: Bool
    /// `total - success - failed`, never negative; not a separate server field.
    public var pendingCount: Int { max(totalCount - successCount - failedCount, 0) }
    public var canRetryFailed: Bool { failedCount > 0 }
    public init(value: ClubGovernanceValue) throws {
        guard let id = value["id"].int, id > 0 else { throw ClubGovernanceFailure.malformed }
        func count(_ key: String) throws -> Int {
            switch value[key] {
            case .null: return 0
            case .integer(let number) where number >= 0: return number
            default: throw ClubGovernanceFailure.malformed
            }
        }
        self.id = id
        totalCount = try count("totalCount"); successCount = try count("successCount"); failedCount = try count("failedCount")
        let status = (value["status"].string ?? "").uppercased()
        phase = status == "COMPLETED" ? .completed : status == "PARTIAL_FAILED" ? .partialFailed : .delivering
        processing = status == "PROCESSING"
    }
}

public struct ClubOpsNotifyAudienceRow: Equatable, Identifiable {
    public let id: String
    /// Nil when the server sends null (e.g. event audiences without an activity): unknown, not zero.
    public let count: Int?
}

public enum ClubOpsNotifyPresentation {
    public static let audienceIDs = ["ALL_MEMBERS", "ADMINS", "REGISTERED", "WAITLIST", "NO_SHOW", "INACTIVE"]
    public static let titleLimit = 80
    public static let contentLimit = 1000
    public enum DraftIssue: String, Equatable { case title, content }
    public static func audienceRows(_ value: ClubGovernanceValue) throws -> [ClubOpsNotifyAudienceRow] {
        guard let counts = value["counts"].object else { throw ClubGovernanceFailure.malformed }
        return audienceIDs.map { id in
            if case .integer(let number) = counts[id] ?? .null, number >= 0 { return .init(id: id, count: number) }
            return .init(id: id, count: nil)
        }
    }
    /// Same order and bounds as `validDraft()`: title first (1–80), then content (1–1000), trimmed, UTF-16.
    public static func draftIssue(title: String, content: String) -> DraftIssue? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.utf16.count > titleLimit { return .title }
        if content.isEmpty || content.utf16.count > contentLimit { return .content }
        return nil
    }
    /// Preview card: `N 人`, or the empty-audience note when the count is 0.
    public static func previewCount(_ value: ClubGovernanceValue) -> Int? {
        guard case .integer(let count) = value["recipientCount"], count >= 0 else { return nil }
        return count
    }
}
