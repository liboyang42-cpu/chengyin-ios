import Foundation

/// Synthetic offline server for previews, DEBUG UI tests and Core tests. Never a real account's records.
/// Every response is serialized to JSON and decoded by the same strict projections as live responses.
@MainActor public final class RoamPrivateToolsFixture: RoamPrivateToolsServing {
    public enum Scenario: String {
        case content, empty, failure, unauthorized
        /// Writes stay disabled exactly as with a read-only approval.
        case readOnly
        /// The first create dispatch "loses" its response although the fake server stored it.
        case unknownCreate
    }
    public let scenario: Scenario
    /// Fixed synthetic "now": 2026-10-19 12:00 Asia/Shanghai (the passport tools fixture clock).
    public static let asOfMs: Int64 = 1_792_382_400_000
    private let scope = try! RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/synthetic-roam")!, accountID: 900)
    public var pendingCapsule: RoamCapsuleDraft?
    public var pendingGoal: RoamGoalDraft?
    public var confirmedCancelledGoals: Set<String> = []
    public private(set) var dispatchedWrites: [String] = []
    private var capsuleRows: [[String: Any]]
    private var goalRows: [[String: Any]]
    private var capsuleReceipts: [String: String] = [:]
    private var nextID = 300
    private var lostCreate = false

    public init(scenario: Scenario = .content) {
        self.scenario = scenario
        let day = RoamShanghaiCalendar.dayMilliseconds, now = Self.asOfMs
        let filled = scenario != .empty
        capsuleRows = filled ? [
            ["id": "12", "state": "OPEN", "unlockAtMs": now - 2 * day, "createdAtMs": now - 200 * day, "timeZone": "Asia/Shanghai",
             "body": "写给今天的自己：记得那次老城墙夜行。", "photoUrl": NSNull()],
            ["id": "11", "state": "LOCKED", "unlockAtMs": now + 45 * day + 3_600_000, "createdAtMs": now - 20 * day, "timeZone": "Asia/Shanghai"],
        ] : []
        let base: [String: Any] = ["timeZone": "Asia/Shanghai", "countingVersion": "COMPLETED_SESSION_AGGREGATE_V1", "asOfMs": now, "createdAtMs": now - 9 * day]
        goalRows = filled ? [
            base.merging(["id": "22", "requestId": "fixture_goal_active_0001", "metric": "DISTINCT_ROUTES", "target": 5, "startDate": "2026-10-01",
                          "endDateExclusive": "2026-11-01", "progress": 2, "state": "ACTIVE", "privateCommemoration": false]) { $1 },
            base.merging(["id": "21", "requestId": "fixture_goal_done_00001", "metric": "EXPLORATION_DAYS", "target": 3, "startDate": "2026-09-01",
                          "endDateExclusive": "2026-10-01", "progress": 4, "state": "ACHIEVED", "privateCommemoration": true]) { $1 },
        ] : []
    }
    public var identity: RoamExperienceIdentity? { scenario == .unauthorized ? nil : RoamExperienceIdentity(scope: scope, epoch: 1) }
    public var isConfigured: Bool { true }
    public var allowsWrites: Bool { scenario != .readOnly }
    public var isOfflineExample: Bool { true }
    public var now: Date { Date(timeIntervalSince1970: TimeInterval(Self.asOfMs) / 1000) }

    private func check() throws {
        guard identity != nil else { throw APIError.unauthorized }
        if scenario == .failure { throw APIError.httpStatus(503) }
    }
    private func envelope(_ data: Any, code: Int = 200, message: String? = nil) throws -> RoamPrivateEnvelope {
        var object: [String: Any] = ["code": code, "data": data]
        if let message { object["msg"] = message }
        return try RoamPrivateEnvelope.parse(JSONSerialization.data(withJSONObject: object))
    }
    private func metadata(_ row: [String: Any]) -> [String: Any] {
        var out = row
        if out["state"] as? String != "OPEN" { out["body"] = nil; out["photoUrl"] = nil }
        return out
    }

    public func capsules(beforeID: String?) async throws -> RoamCapsulePage {
        try check()
        // Metadata only, as the server's list: no body or photo for any row.
        let rows = capsuleRows.filter { beforeID == nil || Int($0["id"] as! String)! < Int(beforeID!)! }.map { row -> [String: Any] in
            var out = row; out["body"] = nil; out["photoUrl"] = nil; return out
        }
        return try RoamCapsulePage.decode(envelope(["items": rows, "hasMore": false, "nextBeforeId": NSNull()]))
    }
    public func capsule(id: String) async throws -> RoamCapsule {
        try check()
        guard let row = capsuleRows.first(where: { $0["id"] as? String == id }) else { throw APIError.businessCode(500) }
        return try RoamCapsule.decode(envelope(metadata(row)))
    }
    public func capsuleReceipt(requestID: String) async throws -> RoamCapsule {
        try check()
        guard let id = capsuleReceipts[requestID], let row = capsuleRows.first(where: { $0["id"] as? String == id }) else { throw APIError.businessCode(500) }
        var out = metadata(row); out["body"] = nil; out["photoUrl"] = nil
        return try RoamCapsule.decode(envelope(out))
    }
    public func createCapsule(_ draft: RoamCapsuleDraft) async throws -> RoamCapsule {
        try check()
        guard allowsWrites else { throw RoamPrivateWriteError.writesDisabled }
        try draft.validate(now: now)
        dispatchedWrites.append(RoamPrivateToolsRoute.capsuleCreate)
        if capsuleReceipts[draft.requestID] == nil {
            nextID += 1
            let unlock = RoamShanghaiCalendar.parseDate(draft.unlockDate)! * RoamShanghaiCalendar.dayMilliseconds - Int64(RoamShanghaiCalendar.offsetSeconds) * 1000
            capsuleRows.insert(["id": String(nextID), "state": "LOCKED", "unlockAtMs": unlock, "createdAtMs": Self.asOfMs, "timeZone": "Asia/Shanghai"], at: 0)
            capsuleReceipts[draft.requestID] = String(nextID)
        }
        if scenario == .unknownCreate && !lostCreate { lostCreate = true; throw RoamPrivateWriteError.outcomeUnknown }
        return try RoamCapsule.decode(envelope(capsuleRows[0]))
    }
    public func deleteCapsule(id: String) async throws -> RoamCapsule {
        try check()
        guard allowsWrites else { throw RoamPrivateWriteError.writesDisabled }
        dispatchedWrites.append(RoamPrivateToolsRoute.capsuleDelete)
        capsuleRows.removeAll { $0["id"] as? String == id }
        return try RoamCapsule.decode(envelope(["id": id, "state": "DELETED"]))
    }

    public func goals(beforeID: String?) async throws -> RoamGoalPage {
        try check()
        let rows = goalRows.filter { beforeID == nil || Int($0["id"] as! String)! < Int(beforeID!)! }
        return try RoamGoalPage.decode(envelope(["items": rows, "hasMore": false, "nextBeforeId": NSNull()]), confirmedCancelled: confirmedCancelledGoals)
    }
    public func goal(id: String) async throws -> RoamExplorationGoal {
        try check()
        guard let row = goalRows.first(where: { $0["id"] as? String == id }) else { throw APIError.businessCode(500) }
        return try RoamExplorationGoal.decode(envelope(row), confirmedCancelled: confirmedCancelledGoals)
    }
    public func goalReceipt(requestID: String) async throws -> RoamExplorationGoal {
        try check()
        guard let row = goalRows.first(where: { $0["requestId"] as? String == requestID }) else { throw APIError.businessCode(500) }
        let value = try RoamExplorationGoal.decode(envelope(row), confirmedCancelled: confirmedCancelledGoals)
        if let pendingGoal, pendingGoal.requestID == requestID, !value.matches(pendingGoal) { throw APIError.malformedResponse }
        return value
    }
    public func createGoal(_ draft: RoamGoalDraft) async throws -> RoamExplorationGoal {
        try check()
        guard allowsWrites else { throw RoamPrivateWriteError.writesDisabled }
        try draft.validate(now: now)
        dispatchedWrites.append(RoamPrivateToolsRoute.goalCreate)
        let today = RoamShanghaiCalendar.dayNumber(now: now), start = RoamShanghaiCalendar.parseDate(draft.startDate)!
        if !goalRows.contains(where: { $0["requestId"] as? String == draft.requestID }) {
            nextID += 1
            goalRows.insert(["id": String(nextID), "requestId": draft.requestID, "metric": draft.metric.rawValue, "target": draft.target,
                             "startDate": draft.startDate, "endDateExclusive": draft.endDateExclusive, "progress": 0,
                             "state": start > today ? "SCHEDULED" : "ACTIVE", "privateCommemoration": false, "timeZone": "Asia/Shanghai",
                             "countingVersion": "COMPLETED_SESSION_AGGREGATE_V1", "asOfMs": Self.asOfMs, "createdAtMs": Self.asOfMs], at: 0)
        }
        if scenario == .unknownCreate && !lostCreate { lostCreate = true; throw RoamPrivateWriteError.outcomeUnknown }
        let row = goalRows.first { $0["requestId"] as? String == draft.requestID }!
        return try RoamExplorationGoal.decode(envelope(row), confirmedCancelled: confirmedCancelledGoals)
    }
    public func cancelGoal(id: String) async throws -> RoamExplorationGoal {
        try check()
        guard allowsWrites else { throw RoamPrivateWriteError.writesDisabled }
        guard let index = goalRows.firstIndex(where: { $0["id"] as? String == id }) else { throw RoamPrivateWriteError.rejected(nil) }
        dispatchedWrites.append(RoamPrivateToolsRoute.goalCancel)
        goalRows[index]["state"] = "CANCELLED"; goalRows[index]["privateCommemoration"] = false
        confirmedCancelledGoals.insert(id)
        return try RoamExplorationGoal.decode(envelope(goalRows[index]))
    }

    /// Three synthetic completions inside the default 30-day range, newest first, one per page of two.
    private func exportRows(_ snapshot: RoamExportSnapshot) -> [[String: Any]] {
        guard scenario != .empty else { return [] }
        let rows: [[String: Any]] = [
            ["recordId": "903", "completedAt": "2026-10-18T19:42:10.120+08:00", "routeVersion": "4", "elapsedSeconds": 2520, "routeAvailability": "AVAILABLE", "routeTitle": "老城墙夜行"],
            ["recordId": "877", "completedAt": "2026-10-09T09:05:00.000+08:00", "routeVersion": "2", "elapsedSeconds": 3605, "routeAvailability": "AVAILABLE", "routeTitle": "滨江骑行路线"],
            ["recordId": "851", "completedAt": "2026-09-30T16:20:00.500+08:00", "routeVersion": NSNull(), "elapsedSeconds": NSNull(), "routeAvailability": "UNAVAILABLE", "routeTitle": NSNull()],
        ]
        return rows.filter { let day = String(($0["completedAt"] as! String).prefix(10)); return day >= snapshot.startDate && day < snapshot.endDateExclusive }
    }
    private func snapshotObject(_ snapshot: RoamExportSnapshot) -> [String: Any] {
        ["format": RoamExportContract.format, "timeZone": "Asia/Shanghai", "snapshotId": snapshot.snapshotID, "startDate": snapshot.startDate,
         "endDateExclusive": snapshot.endDateExclusive, "asOfMs": snapshot.asOfMs, "expiresAtMs": snapshot.expiresAtMs,
         "upperRecordId": snapshot.upperRecordID, "expectedRows": snapshot.expectedRows, "pageSize": snapshot.pageSize]
    }
    public static let fixturePageSize = 2
    public func prepareExport(_ request: RoamExportRequest) async throws -> RoamExportCheckpoint {
        try check(); try request.validate()
        // The fixture echoes the requested page size; the view requests two rows so chunking stays visible.
        let probe = RoamExportSnapshot(snapshotID: String(repeating: "a", count: 64), startDate: request.startDate, endDateExclusive: request.endDateExclusive,
                                       asOfMs: Self.asOfMs, expiresAtMs: Self.asOfMs + RoamShanghaiCalendar.dayMilliseconds, upperRecordID: "0", expectedRows: 0, pageSize: request.pageSize)
        let rows = exportRows(probe)
        var object = snapshotObject(probe)
        object["upperRecordId"] = (rows.first?["recordId"] as? String) ?? "0"; object["expectedRows"] = rows.count
        object["cursor"] = "c" + String(repeating: "0", count: 47)
        return try RoamExportCheckpoint.prepared(envelope(object), request: request)
    }
    public func exportPage(_ checkpoint: RoamExportCheckpoint) async throws -> RoamExportChunk {
        try check()
        guard let cursor = checkpoint.cursor else { throw APIError.invalidRequest }
        let rows = exportRows(checkpoint.snapshot)
        let slice = Array(rows.dropFirst(checkpoint.offset).prefix(checkpoint.snapshot.pageSize))
        let emitted = checkpoint.offset + slice.count, complete = emitted >= checkpoint.snapshot.expectedRows
        var object = snapshotObject(checkpoint.snapshot)
        object["cursor"] = cursor; object["offset"] = checkpoint.offset; object["items"] = slice; object["complete"] = complete
        object["state"] = complete ? "COMPLETE" : "MORE"; object["emittedRows"] = emitted
        object["nextCursor"] = complete ? NSNull() : ("c" + String(format: "%047d", emitted))
        return try RoamExportChunk.decode(envelope(object), original: checkpoint)
    }
}
