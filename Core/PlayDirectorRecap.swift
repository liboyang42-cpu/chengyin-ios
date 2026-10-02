import Foundation

/// Exact privacy allowlist from game_session.dart normalizeClubRecapExport. Never
/// return raw server JSON to a clipboard/share surface, even after a valid envelope.
public enum PlayDirectorRecap {
    public static func normalizeExport(_ raw: PlayWireValue, activityID: Int) throws -> PlayWireValue {
        guard raw["schemaVersion"].text == "GAME_RECAP_EXPORT_V1", raw["activityId"].integer == activityID,
              let sessionID = raw["sessionId"].integer, sessionID > 0,
              let generated = raw["generatedAt"].text, validDateTime(generated) else { throw PlayExperienceError.malformed }
        return .object(["schemaVersion": .string("GAME_RECAP_EXPORT_V1"), "generatedAt": .string(generated),
            "activityId": .int(activityID), "sessionId": .int(sessionID), "recap": try normalize(raw["recap"])])
    }
    public static func normalize(_ raw: PlayWireValue) throws -> PlayWireValue {
        guard raw["schemaVersion"].text == "GAME_RECAP_V1", let generated = raw["generatedAt"].text,
              validDateTime(generated), let available = raw["exportAvailable"].bool,
              let metrics = raw["metrics"].array, let stations = raw["stations"].array else { throw PlayExperienceError.malformed }
        var seen: Set<String> = [], nodeIDs: Set<Int> = []
        let safeMetrics = try metrics.map { metric -> PlayWireValue in
            guard let rawKey = metric["key"].text, let label = bounded(metric["label"], maximum: 120), !label.isEmpty,
                  let unit = bounded(metric["unit"], maximum: 32), let value = metric["value"].integer, value >= 0 else { throw PlayExperienceError.malformed }
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard key.range(of: "^[A-Z][A-Z0-9_]{1,63}$", options: .regularExpression) != nil, seen.insert(key).inserted else { throw PlayExperienceError.malformed }
            return .object(["key": .string(key), "label": .string(label), "value": .int(value), "unit": .string(unit)])
        }
        let safeStations = try stations.map { station -> PlayWireValue in
            guard let id = station["nodeId"].integer, id > 0, nodeIDs.insert(id).inserted,
                  let name = bounded(station["nodeName"], maximum: 120), !name.isEmpty else { throw PlayExperienceError.malformed }
            var fields = try counts(station, ["arrivedPlayers", "submissionCount", "normalCompletedCount", "fallbackCompletedCount", "rejectedCount", "pauseEventCount"])
            fields["nodeId"] = .int(id); fields["nodeName"] = .string(name); return .object(fields)
        }
        let collaboration = try counts(raw["collaboration"], ["eligibleTeams", "completedTeams", "ratePercent"])
        guard collaboration["ratePercent"]!.integer! <= 100,
              collaboration["completedTeams"]!.integer! <= collaboration["eligibleTeams"]!.integer! else { throw PlayExperienceError.malformed }
        return .object([
            "schemaVersion": .string("GAME_RECAP_V1"), "generatedAt": .string(generated), "exportAvailable": .bool(available),
            "metrics": .array(safeMetrics), "stations": .array(safeStations),
            "funnel": .object(try counts(raw["funnel"], ["paidPlayers", "arrivedPlayers", "taskSubmitters", "normalCompleters", "fallbackCompleters", "finishedTeams"])),
            "hints": .object(try counts(raw["hints"], ["level1Uses", "level2Uses", "answerReveals"])),
            "incidents": .object(try counts(raw["incidents"], ["merchantPauseEvents", "merchantFallbackCompletions", "playerRejectedSubmissions"])),
            "collaboration": .object(collaboration), "takeovers": .object(try counts(raw["takeovers"], ["count"]))
        ])
    }
    private static func counts(_ raw: PlayWireValue, _ keys: [String]) throws -> [String: PlayWireValue] {
        guard raw.object != nil else { throw PlayExperienceError.malformed }
        var fields: [String: PlayWireValue] = [:]
        for key in keys { guard let value = raw[key].integer, value >= 0 else { throw PlayExperienceError.malformed }; fields[key] = .int(value) }
        return fields
    }
    private static func bounded(_ raw: PlayWireValue, maximum: Int) -> String? {
        guard let text = raw.text else { return nil }; let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count <= maximum ? value : nil
    }
    public static func validDateTime(_ text: String) -> Bool {
        guard text.range(of: "^\\d{4}-\\d{2}-\\d{2} ([01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d$", options: .regularExpression) != nil else { return false }
        let parts = text.split(whereSeparator: { "- :".contains($0) }).compactMap { Int($0) }
        guard parts.count == 6 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return false }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        return check.year == parts[0] && check.month == parts[1] && check.day == parts[2]
    }
}
extension PlayExperienceService {
    public func directorRecapExport(activityID: Int, token: String) async throws -> PlayWireValue {
        guard activityID > 0 else { throw APIError.invalidRequest }
        return try PlayDirectorRecap.normalizeExport(await request("api/game/session/recap/export", query: ["activityId": String(activityID)], capability: .reads, token: token), activityID: activityID)
    }
}
