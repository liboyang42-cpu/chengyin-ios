import Foundation

public struct ClubCalendarSession: Hashable, Identifiable {
    public enum State: String { case published = "PUBLISHED", unpublished = "UNPUBLISHED", cancelled = "CANCELLED" }
    public let activityID: Int
    public let topicID: Int?
    public let name: String?
    public let day: ClubEventDay
    public let startDate: String
    public let endDate: String?
    public let state: State
    public let updatedAt: String?
    public var id: Int { activityID }
}

/// Original cms_activity rows. Topic IDs are metadata, never selectable activity IDs.
public struct ClubCalendarSessionsSnapshot: Equatable {
    public enum Visibility: String { case governor = "GOVERNOR", publicVisible = "PUBLIC" }
    public let clubID: Int
    public let month: ClubEventMonth
    public let visibility: Visibility
    public let sessions: [ClubCalendarSession]
    public let truncated: Bool
    public let updatedAt: String?
    public init(value: ClubGovernanceValue, clubID: Int, month: ClubEventMonth) throws {
        guard clubID > 0, value["clubId"].int == clubID, value["month"].string == month.key,
              let scope = value["scope"].string, let visibility = Visibility(rawValue: scope),
              let truncated = value["truncated"].bool, let rows = value["sessions"].array else { throw ClubGovernanceFailure.malformed }
        var sessions: [ClubCalendarSession] = [], seen = Set<Int>()
        for row in rows {
            guard row.object != nil, let activityID = row["activityId"].int, activityID > 0, seen.insert(activityID).inserted,
                  let date = row["date"].string, date.count == 10, let day = ClubEventDay(source: date), month.contains(day),
                  let start = row["startDate"].string, Self.localTimestamp(start), start.hasPrefix(date),
                  let rawState = row["state"].string, let state = ClubCalendarSession.State(rawValue: rawState),
                  visibility == .governor || state == .published else { throw ClubGovernanceFailure.malformed }
            let topicID: Int?
            if row["topicId"] == .null { topicID = nil }
            else { guard let id = row["topicId"].int, id >= 0 else { throw ClubGovernanceFailure.malformed }; topicID = id > 0 ? id : nil }
            let name = try Self.optionalString(row["name"])
            let end = try Self.optionalTimestamp(row["endDate"])
            let updated = try Self.optionalTimestamp(row["updatedAt"])
            sessions.append(.init(activityID: activityID, topicID: topicID, name: name, day: day,
                                  startDate: start, endDate: end, state: state, updatedAt: updated))
        }
        self.clubID = clubID; self.month = month; self.visibility = visibility
        self.sessions = sessions; self.truncated = truncated; updatedAt = try Self.optionalTimestamp(value["updatedAt"])
    }
    private static func optionalString(_ value: ClubGovernanceValue) throws -> String? {
        if value == .null { return nil }
        guard let text = value.string else { throw ClubGovernanceFailure.malformed }; return text
    }
    private static func optionalTimestamp(_ value: ClubGovernanceValue) throws -> String? {
        guard let text = try optionalString(value) else { return nil }
        guard localTimestamp(text) else { throw ClubGovernanceFailure.malformed }; return text
    }
    private static func localTimestamp(_ text: String) -> Bool {
        // Server writes database-local time. Do not shift its date with device TZ.
        guard text.utf8.count == 19, ClubEventDay(source: text) != nil else { return false }
        let bytes = Array(text.utf8)
        guard bytes[10] == 32, bytes[13] == 58, bytes[16] == 58 else { return false }
        let indexes = [11,12,14,15,17,18]
        guard indexes.allSatisfy({ (48...57).contains(bytes[$0]) }) else { return false }
        let hour = Int(bytes[11] - 48) * 10 + Int(bytes[12] - 48)
        let minute = Int(bytes[14] - 48) * 10 + Int(bytes[15] - 48)
        let second = Int(bytes[17] - 48) * 10 + Int(bytes[18] - 48)
        return hour < 24 && minute < 60 && second < 60
    }
}
