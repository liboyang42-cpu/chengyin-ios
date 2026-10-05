import Foundation

public enum ChapterThoughtSyncPhase: String, Equatable { case idle, syncing, synced, needsReadback, disabled, failed }

public extension ChapterStoryProjection {
    /// Only keys actually reached before the first incomplete/unknown/locked node can be
    /// claimed. Names remain hidden until the server returns earned thought facts.
    static func claimableThoughtKeys(chapter: ChapterStoryDocument, snapshot: PlaySnapshot,
                                     thoughts: [PlayWireValue]) -> [String] {
        let known = Set(thoughts.compactMap { $0["key"].text })
        var keys: [String] = []
        for block in chapter.blocks {
            if block["type"].text == "node" {
                guard let id = block["nodeId"].tolerantInteger,
                      let node = snapshot.visibleNodes.first(where: { $0.id == id && $0.chapterID == chapter.chapterID }),
                      !snapshot.isLocked(node), snapshot.isDone(node) else { break }
            } else if block["type"].text == "thought",
                      let key = ParticipationRecord.text(block["thoughtKey"]), !known.contains(key), !keys.contains(key) {
                keys.append(key)
            }
        }
        return keys
    }
}
public extension PlayExperienceService {
    /// Current backend explicitly supports claim-only sync without a WeRun reading. Do not
    /// synthesize step counts, encryptedData, code, iv or a native health-data equivalent.
    func syncChapterThoughts(scope: PlaySessionScope, topicID: Int, claims: [String],
                             sessionID: Int, previousVersion: Int, token: String) async throws -> PlayRouteState {
        guard scope.isValid, topicID > 0, sessionID > 0, previousVersion >= 0, !claims.isEmpty,
              claims.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(claims).count == claims.count else { throw PlayExperienceError.invalidAction }
        if case .topic(let id) = scope, id != topicID { throw PlayExperienceError.invalidAction }
        var body: [String: PlayWireValue] = ["topicId": .int(topicID), "claim": .array(claims.map(PlayWireValue.string))]
        if case .activity(let id) = scope { body["activityId"] = .int(id) }
        let raw = try await request("api/play/journey/thought/sync", json: body, capability: .thoughtClaims, token: token)
        let route: PlayRouteState = try raw.decoded()
        guard route.sessionID == sessionID, let version = route.version, version > previousVersion else { throw PlayExperienceError.malformed }
        return route
    }
}
