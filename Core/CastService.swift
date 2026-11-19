import Foundation

/// Cast contract endpoints (hengyin docs/design/cast-contract-1119.md). Both stay behind
/// the dormant service gates: profile save needs `.castProfile`, the voice lookup `.reads`.
public extension PlayExperienceService {
    /// `POST /api/play/run/profile {runId, name, identityKey}`. Run owner only; the server
    /// filters the name. An empty name is sent as "" and falls back to 「你」 in the story.
    func saveCastProfile(runID: Int, profile: CastPlayerProfile, token: String) async throws {
        guard runID > 0 else { throw PlayExperienceError.invalidAction }
        var body: [String: PlayWireValue] = ["runId": .int(runID), "name": .string(profile.name ?? "")]
        if let key = profile.identityKey { body["identityKey"] = .string(key) }
        _ = try await request("api/play/run/profile", json: body, capability: .castProfile, token: token)
    }
    /// `GET /api/topic/cast/voice?topicId=&chapterId=&blockKey=` → `{url}`. A response without
    /// an https URL (TTS not configured, rate limited) is "no voice", not an error to show.
    func castVoice(topicID: Int, chapterID: Int, blockKey: String, token: String) async throws -> String? {
        let key = blockKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard topicID > 0, chapterID > 0, !key.isEmpty, key.count <= 64 else { throw PlayExperienceError.invalidAction }
        let raw = try await request("api/topic/cast/voice",
            query: ["topicId": String(topicID), "chapterId": String(chapterID), "blockKey": key], capability: .reads, token: token)
        guard let url = raw["url"].text, Self.validHTTPS(url) else { return nil }
        return url
    }
}
