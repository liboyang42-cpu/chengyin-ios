import Foundation

/// FE-STORY 6.2 / 7.3 / 7.4: a read-only copy of the chapters the server already unlocked
/// for one account and run. Only visited places and unlocked chapters carry text; a locked
/// place keeps its name so its card can say why it stays locked. Nothing here can write a
/// visit, and nothing is ever re-sent from it.
public struct FreeExplorationStoryArchive: Codable, Equatable {
    public struct Place: Codable, Equatable, Identifiable {
        public let id: Int
        public let name: String?
        public let chapterID: Int?
        public let address: String?
        public let description: String?
        public let cardHookLong: String?
        public let fragmentText: String?
        public let storyText: String?
        public let visitTimeMillis: Int64?
        public let visitTimeText: String?
        public let visitedByTeam: Bool
        public var visitTime: PlayVisitTime? {
            if let visitTimeMillis { return .epochMilliseconds(visitTimeMillis) }
            return visitTimeText.map(PlayVisitTime.text)
        }
        /// Plain text to show, in the server's field order, without duplicates.
        public var paragraphs: [String] {
            FreeExplorationStoryArchive.unique([description, cardHookLong, fragmentText, storyText])
        }
    }
    public struct Chapter: Codable, Equatable, Identifiable {
        public let id: Int
        public let name: String?
        public let sortID: Int?
        public let paragraphs: [String]
    }
    public struct LockedPlace: Codable, Equatable, Identifiable {
        public let id: Int
        public let name: String?
    }
    public static let currentSchema = 1
    /// Bound on archived text so the encrypted record stays well under its 256 KiB slot.
    public static let maximumTextUnits = 4_000
    public static let maximumRows = 120

    public let schema: Int
    public let owner: PlayRecoveryOwner
    public let topicID: Int?
    public let topicName: String?
    public let storyUnlocked: Int?
    public let storyTotal: Int?
    public let chapters: [Chapter]
    public let places: [Place]
    public let lockedPlaces: [LockedPlace]

    init(owner: PlayRecoveryOwner, topicID: Int?, topicName: String?, storyUnlocked: Int?, storyTotal: Int?,
         chapters: [Chapter], places: [Place], lockedPlaces: [LockedPlace]) {
        schema = Self.currentSchema; self.owner = owner; self.topicID = topicID; self.topicName = Self.clip(topicName)
        if let storyUnlocked, let storyTotal, storyTotal >= 0, (0...storyTotal).contains(storyUnlocked) {
            self.storyUnlocked = storyUnlocked; self.storyTotal = storyTotal
        } else { self.storyUnlocked = nil; self.storyTotal = nil }
        let placeIDs = Set(places.map(\.id))
        self.chapters = Array(chapters.prefix(Self.maximumRows)); self.places = Array(places.prefix(Self.maximumRows))
        self.lockedPlaces = Array(lockedPlaces.filter { !placeIDs.contains($0.id) }.prefix(Self.maximumRows))
    }

    /// From an authoritative mode-2 `/api/play/nodes` read. Locked places never contribute
    /// text, even if a stale field arrives; a missing `chapterLocked` stays locked unless a
    /// visited place belongs to that chapter (FE-STORY 7.14).
    public init?(snapshot: PlaySnapshot, chapterStories: [Int: ChapterStoryDocument], owner: PlayRecoveryOwner) {
        guard snapshot.result.mode == 2, snapshot.availability != .registrationRequired else { return nil }
        let visited = snapshot.visibleNodes.filter { snapshot.isVisited($0) && !snapshot.isStoryLocked($0) }
        let visitedChapters = Set(visited.compactMap(\.chapterID))
        let places = visited.map { node in
            Place(id: node.id, name: Self.clip(node.name), chapterID: node.chapterID, address: Self.clip(node.address),
                  description: Self.clip(node.description), cardHookLong: Self.clip(node.cardHookLong),
                  fragmentText: Self.clip(node.fragmentText), storyText: Self.clip(node.storyText),
                  visitTimeMillis: Self.millis(node.visitTime), visitTimeText: Self.timeText(node.visitTime),
                  visitedByTeam: node.visitedByTeam == true)
        }
        var chapters: [Chapter] = []
        for (index, chapter) in snapshot.result.chapters.enumerated()
        where chapter.chapterLocked == false || (chapter.chapterLocked == nil && visitedChapters.contains(chapter.id)) {
            let story = chapterStories[chapter.id]
            let raw = [chapter.description, story?.description] + (story?.blocks ?? []).flatMap(Self.blockText)
            chapters.append(.init(id: chapter.id, name: Self.clip(chapter.name ?? story?.title), sortID: index, paragraphs: Self.unique(raw)))
        }
        let placeIDs = Set(places.map(\.id))
        let locked = snapshot.visibleNodes.filter { !placeIDs.contains($0.id) }.map { LockedPlace(id: $0.id, name: Self.clip($0.name)) }
        self.init(owner: owner, topicID: snapshot.result.topicID, topicName: snapshot.result.topicName,
                  storyUnlocked: snapshot.result.storyUnlocked, storyTotal: snapshot.result.storyTotal,
                  chapters: chapters, places: places, lockedPlaces: locked)
    }

    /// From the expired-ticket `/api/play/history` read, which lists only visited chapters.
    /// Places known from an earlier read but absent here stay locked.
    public init(history: FreeExplorationHistoryDocument, owner: PlayRecoveryOwner, topicID: Int?, topicName: String?, knownPlaces: [LockedPlace]) {
        let places = history.nodes.map { node in
            Place(id: node.nodeID, name: Self.clip(node.name), chapterID: node.chapterID, address: Self.clip(node.address),
                  description: Self.clip(node.description), cardHookLong: Self.clip(node.cardHookLong),
                  fragmentText: Self.clip(node.fragmentText), storyText: Self.clip(node.storyText),
                  visitTimeMillis: Self.millis(node.visitTime), visitTimeText: Self.timeText(node.visitTime),
                  visitedByTeam: node.visitedByTeam == true)
        }
        let chapters = history.chapters.sorted { ($0.sortID ?? .max, $0.chapterID) < ($1.sortID ?? .max, $1.chapterID) }.map { chapter in
            Chapter(id: chapter.chapterID, name: Self.clip(chapter.name), sortID: chapter.sortID,
                    paragraphs: Self.unique([chapter.description] + chapter.blocks.flatMap(Self.blockText)))
        }
        self.init(owner: owner, topicID: topicID, topicName: topicName, storyUnlocked: history.storyUnlocked, storyTotal: history.storyTotal,
                  chapters: chapters, places: places, lockedPlaces: knownPlaces)
    }

    /// Visits are permanent (FE-STORY 7.1 / 7.11 / 7.12): keep every place and chapter either
    /// read unlocked; the newer read wins for the same row. Another owner or topic replaces.
    public func merging(_ newer: FreeExplorationStoryArchive) -> FreeExplorationStoryArchive {
        guard owner == newer.owner, topicID == nil || newer.topicID == nil || topicID == newer.topicID else { return newer }
        func union<Row: Identifiable>(_ old: [Row], _ new: [Row]) -> [Row] where Row.ID == Int {
            let ids = Set(new.map(\.id)); return new + old.filter { !ids.contains($0.id) }
        }
        let mergedPlaces = union(places, newer.places)
        let known = newer.lockedPlaces.isEmpty ? lockedPlaces : newer.lockedPlaces
        return .init(owner: newer.owner, topicID: newer.topicID ?? topicID, topicName: newer.topicName ?? topicName,
                     storyUnlocked: newer.storyUnlocked ?? storyUnlocked, storyTotal: newer.storyTotal ?? storyTotal,
                     chapters: union(chapters, newer.chapters).sorted { ($0.sortID ?? .max, $0.id) < ($1.sortID ?? .max, $1.id) },
                     places: mergedPlaces, lockedPlaces: known)
    }

    public var isEmpty: Bool { chapters.isEmpty && places.isEmpty }
    public func places(in chapterID: Int) -> [Place] { places.filter { $0.chapterID == chapterID } }
    /// Visited places whose chapter row is absent (no chapters configured, or delisted).
    public var placesWithoutChapter: [Place] {
        let ids = Set(chapters.map(\.id)); return places.filter { $0.chapterID.map { !ids.contains($0) } ?? true }
    }

    static func millis(_ time: PlayVisitTime?) -> Int64? {
        if case .epochMilliseconds(let value)? = time { return value }
        return nil
    }
    static func timeText(_ time: PlayVisitTime?) -> String? {
        if case .text(let value)? = time { return clip(value) }
        return nil
    }
    static func blockText(_ block: PlayWireValue) -> [String?] {
        switch block["type"].text {
        case "text", "voice", "reveal": return [block["content"].text]
        default: return []
        }
    }
    static func clip(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        guard trimmed.utf16.count > maximumTextUnits else { return trimmed }
        return String(trimmed.prefix(maximumTextUnits))
    }
    static func unique(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { clip($0) }.filter { seen.insert($0).inserted }
    }
}

/// `GET /api/play/history?activityId=<id or 0>&topicId=<id>` for a free-exploration topic after
/// its ticket expired (FE-STORY 7.4). Only visited chapters arrive; anything else is not this
/// contract and is rejected rather than shown as an empty archive.
public struct FreeExplorationHistoryDocument: Equatable {
    public struct Chapter: Equatable {
        public let chapterID: Int
        public let name: String?
        public let sortID: Int?
        public let description: String?
        public let blocks: [PlayWireValue]
    }
    public struct Node: Equatable {
        public let nodeID: Int
        public let name: String?
        public let chapterID: Int?
        public let address: String?
        public let description: String?
        public let cardHookLong: String?
        public let fragmentText: String?
        public let storyText: String?
        public let visitTime: PlayVisitTime?
        public let visitedByTeam: Bool?
    }
    public let storyUnlocked: Int?
    public let storyTotal: Int?
    public let chapters: [Chapter]
    public let nodes: [Node]

    public init(raw: PlayWireValue) throws {
        guard raw["readOnly"].bool == true, raw["mode"].tolerantInteger == 2,
              let chapterRows = raw["chapters"].array ?? (raw["chapters"] == .null ? [] : nil),
              let nodeRows = raw["nodes"].array ?? (raw["nodes"] == .null ? [] : nil) else { throw PlayExperienceError.malformed }
        storyUnlocked = raw["storyUnlocked"].tolerantInteger; storyTotal = raw["storyTotal"].tolerantInteger
        chapters = try chapterRows.map { row -> Chapter in
            guard let id = row["chapterId"].tolerantInteger, id > 0 else { throw PlayExperienceError.malformed }
            let blocks = row["blocks"].array ?? []
            return Chapter(chapterID: id, name: row["name"].text, sortID: row["sortId"].tolerantInteger,
                           description: row["description"].text, blocks: blocks.filter { $0.object != nil })
        }
        nodes = try nodeRows.map { row -> Node in
            guard let id = row["nodeId"].tolerantInteger, id > 0 else { throw PlayExperienceError.malformed }
            let time: PlayVisitTime?
            if let millis = row["visitTime"].integer, millis > 0 { time = .epochMilliseconds(Int64(millis)) }
            else if let text = row["visitTime"].text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { time = .text(text) }
            else { time = nil }
            return Node(nodeID: id, name: row["name"].text, chapterID: row["chapterId"].tolerantInteger, address: row["address"].text,
                        description: row["description"].text, cardHookLong: row["cardHookLong"].text, fragmentText: row["fragmentText"].text,
                        storyText: row["storyText"].text, visitTime: time, visitedByTeam: row["visitedByTeam"].bool)
        }
        guard Set(chapters.map(\.chapterID)).count == chapters.count, Set(nodes.map(\.nodeID)).count == nodes.count else { throw PlayExperienceError.malformed }
    }
}

/// Where the free-exploration screen's read-only chapters came from.
public enum FreeExplorationArchiveSource: Equatable {
    /// No network: the last unlocked chapters saved on this device for this account and run.
    case offline
    /// The ticket can no longer be played: the server's read-only history.
    case expired
}

/// Local, account- and run-scoped store for the archive. A read is never a server fact.
@MainActor public protocol FreeExplorationStoryArchiveStore: AnyObject {
    func readStoryArchive(key: String) async throws -> FreeExplorationStoryArchive?
    func writeStoryArchive(_ archive: FreeExplorationStoryArchive, key: String) async throws
}

/// Synthetic-only adapter for fixtures and tests; it has no device persistence.
@MainActor public final class FreeExplorationMemoryStoryArchive: FreeExplorationStoryArchiveStore {
    private var values: [String: FreeExplorationStoryArchive] = [:]
    public init() {}
    public func readStoryArchive(key: String) async throws -> FreeExplorationStoryArchive? { values[key] }
    public func writeStoryArchive(_ archive: FreeExplorationStoryArchive, key: String) async throws { values[key] = archive }
}
