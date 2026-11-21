import Foundation

/// Cast contract endpoints (hengyin docs/design/cast-contract-1119.md). All stay behind the
/// dormant service gates: profile save needs `.castProfile`, a story-branch pick `.castBranch`,
/// the voice lookup `.reads`.
public extension PlayExperienceService {
    /// `POST /api/play/run/profile {runId, name, identityKey}`. Run owner only; the server
    /// filters the name and requires 1–12 characters, so an empty answer is sent as 「你」, the
    /// same fallback the story uses (and what the mini-program sends).
    func saveCastProfile(runID: Int, profile: CastPlayerProfile, token: String) async throws {
        guard runID > 0 else { throw PlayExperienceError.invalidAction }
        var body: [String: PlayWireValue] = ["runId": .int(runID), "name": .string(profile.name ?? CastStoryVariables.playerFallback)]
        if let key = profile.identityKey { body["identityKey"] = .string(key) }
        _ = try await request("api/play/run/profile", json: body, capability: .castProfile, token: token)
    }
    /// `GET /api/topic/cast/voice?topicId=&chapterId=&blockKey=` → `{url}`. A response without
    /// an https URL (TTS not configured, rate limited) is "no voice", not an error to show.
    /// `runId` lets the server voice `{玩家}` with this run's chosen name; it is omitted when unknown.
    func castVoice(topicID: Int, chapterID: Int, blockKey: String, runID: Int? = nil, token: String) async throws -> String? {
        let key = blockKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard topicID > 0, chapterID > 0, !key.isEmpty, key.count <= 64 else { throw PlayExperienceError.invalidAction }
        var query = ["topicId": String(topicID), "chapterId": String(chapterID), "blockKey": key]
        if let runID, runID > 0 { query["runId"] = String(runID) }
        let raw = try await request("api/topic/cast/voice", query: query, capability: .reads, token: token)
        guard let url = raw["url"].text, Self.validHTTPS(url) else { return nil }
        return url
    }
    /// `POST /api/play/run/branch {runId, chapterId, blockKey, optionIndex}`. The server settles
    /// trust; the client never sends trust values. A repeat answer returns the run's original
    /// pick (`duplicate: true`), which is returned here so the caller can adopt it.
    func recordCastBranch(runID: Int, chapterID: Int, blockKey: String, optionIndex: Int, token: String) async throws -> Int? {
        let key = blockKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard runID > 0, chapterID > 0, !key.isEmpty, key.count <= 64, (0..<3).contains(optionIndex) else { throw PlayExperienceError.invalidAction }
        let raw = try await request("api/play/run/branch", json: ["runId": .int(runID), "chapterId": .int(chapterID),
            "blockKey": .string(key), "optionIndex": .int(optionIndex)], capability: .castBranch, token: token)
        return raw["optionIndex"].tolerantInteger.flatMap { (0..<3).contains($0) ? $0 : nil }
    }
}
