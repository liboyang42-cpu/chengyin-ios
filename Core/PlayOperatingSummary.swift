import Foundation
import Observation

public struct PlayOperatingSummary: Equatable {
    public struct Tag: Equatable, Identifiable {
        public let id: Int; public let value: String; public let status: String
        public var revoked: Bool { status == "REVOKED" }
    }
    public struct Card: Equatable { public let title: String; public let body: String }
    public struct Anchor: Equatable, Identifiable { public let id: Int; public let name: String; public let latitude: Double; public let longitude: Double }
    public let topicID: Int; public let edition: String?; public let tags: [Tag]; public let cards: [Card]
    public let anchors: [Anchor]; public let actions7Days: [String]; public let actions30Days: [String]
    public init(_ raw: PlayWireValue, topicID: Int) throws {
        guard raw["topicId"].tolerantInteger == topicID, topicID > 0 else { throw PlayExperienceError.malformed }
        self.topicID = topicID; edition = raw["edition"].text
        tags = (raw["tags"].array ?? []).compactMap {
            guard let id = $0["id"].tolerantInteger, id > 0, let value = $0["tagValue"].text ?? $0["value"].text, !value.isEmpty else { return nil }
            return Tag(id: id, value: value, status: ($0["status"].text ?? "").uppercased())
        }
        guard Set(tags.map(\.id)).count == tags.count else { throw PlayExperienceError.malformed }
        cards = (raw["resultCards"].array ?? []).compactMap {
            let title = $0["title"].text ?? $0["name"].text ?? "", body = $0["body"].text ?? $0["description"].text ?? $0["text"].text ?? ""
            return title.isEmpty && body.isEmpty ? nil : Card(title: title, body: body)
        }
        anchors = (raw["mapAnchors"].array ?? []).compactMap {
            guard let id = $0["nodeId"].tolerantInteger, id > 0, let lat = $0["latitude"].double, let lon = $0["longitude"].double,
                  lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
            return Anchor(id: id, name: $0["name"].text ?? "", latitude: lat, longitude: lon)
        }
        func strings(_ raw: PlayWireValue) -> [String] {
            (raw.array ?? []).compactMap { $0.text ?? $0["title"].text ?? $0["text"].text ?? $0["action"].text }.filter { !$0.isEmpty }
        }
        actions7Days = strings(raw["actions7Days"]); actions30Days = strings(raw["actions30Days"])
    }
    public var isEmpty: Bool { tags.isEmpty && cards.isEmpty && anchors.isEmpty && actions7Days.isEmpty && actions30Days.isEmpty }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayOperatingSummaryCoordinator {
    public let topicID: Int
    public private(set) var summary: PlayOperatingSummary?
    public private(set) var phase = "idle"
    public private(set) var issue: PlayExperienceError?
    public private(set) var unresolvedTagIDs: Set<Int> = []
    private let service: PlayExperienceService
    private let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    public init(topicID: Int, service: PlayExperienceService, currentSession: @escaping () -> PlayExperienceSession?) { self.topicID = topicID; self.service = service; self.currentSession = currentSession }
    public func load() async {
        guard phase != "submitting", let session = currentSession() else { return }
        if let owner, owner != session { summary = nil; phase = "stale"; return }
        owner = session; generation &+= 1; let generation = generation; phase = "loading"; issue = nil
        do {
            let value = try PlayOperatingSummary(await service.operatingSystem(topicID: topicID, token: session.token), topicID: topicID); try check(session, generation)
            summary = value
            unresolvedTagIDs = unresolvedTagIDs.filter { id in value.tags.contains { $0.id == id && !$0.revoked } }
            phase = unresolvedTagIDs.isEmpty ? "ready" : "unknown"
        } catch { fail(error, session, generation) }
    }
    public func revoke(tagID: Int) async {
        guard phase == "ready", unresolvedTagIDs.isEmpty, let session = owner, session == currentSession(),
              summary?.tags.contains(where: { $0.id == tagID && !$0.revoked }) == true else { return }
        let generation = generation; unresolvedTagIDs.insert(tagID); phase = "submitting"
        do {
            _ = try await service.revokeTag(tagID: tagID, token: session.token); try check(session, generation)
            phase = "unknown"; await load()
        } catch {
            if case PlayExperienceError.rejected = error { unresolvedTagIDs.remove(tagID) }
            if case PlayExperienceError.disabled = error { unresolvedTagIDs.remove(tagID) }
            fail(error, session, generation)
        }
    }
    private func check(_ session: PlayExperienceSession, _ generation: UInt64) throws { guard self.generation == generation, currentSession() == session, !Task.isCancelled else { throw PlayExperienceError.staleSession } }
    private func fail(_ error: Error, _ session: PlayExperienceSession, _ generation: UInt64) {
        guard self.generation == generation else { return }; guard currentSession() == session else { summary = nil; phase = "stale"; return }
        issue = error as? PlayExperienceError ?? .unknownResult; phase = unresolvedTagIDs.isEmpty ? "failed" : "unknown"
    }
}
