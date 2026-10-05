import Foundation
import CryptoKit

/// Display-only P057 projection of the existing sanitized topicOverview read.
/// Array positions identify display rows only; they are never request identifiers.
public struct ClubStoryChapter: Equatable, Identifiable {
    public let id: Int
    public let chapterID: Int?
    public let name: String?
    public let description: String?
    /// Source-authored minutes, not a measured or predicted arrival time.
    public let totalTime: Double?
    public let stops: [ClubStoryStop]
    public let gameplay: [ClubStoryGameplay]
}

public struct ClubStoryStop: Equatable, Identifiable {
    public let id: Int
    public let nodeID: Int?
    public let sequence: Int
    public let businessTime: String?
    public let name: String?
    public let address: String?
    public let imgUrl: String?
}

public struct ClubStoryGameplay: Equatable, Identifiable {
    public let id: Int
    public let chapterID: Int?
    public let nodeID: Int?
    public let memberTemplateID: MemberPlayTemplateID?
    public let sequence: Int
    public let nodeName: String?
    public let title: String?
    public let validationMethod: Int?
    public let validationMethodLabel: String?
    public let players: String?
    /// Source-authored minutes; missing, invalid and non-positive values stay unknown.
    public let duration: Double?
    public let difficulty: String?
    public let imgUrl: String?
    /// An answerable method does not confer permission to read its answer.
    public var isAnswerable: Bool { validationMethod == 1 || validationMethod == 3 }
}

public struct ClubStoryPresentation: Equatable {
    public let topicID: Int
    public let chapters: [ClubStoryChapter]

    public init(snapshot: ClubGovernanceSnapshot) throws {
        guard snapshot.operation == .topicOverview,
              let clubID = snapshot.scope.clubID, clubID > 0,
              let topicID = snapshot.scope.topicID, topicID > 0 else { throw ClubGovernanceFailure.targetChanged }
        try snapshot.scope.validate()
        guard snapshot.permissions?.allows(ClubGovernanceRead.topicOverview.permission, scope: snapshot.scope) == true else {
            throw ClubGovernanceFailure.forbidden
        }
        // Reapply the existing validator/sanitizer even for synthetic snapshots. No
        // raw template, answer, hint, feedback or unreviewed source object is retained.
        let value = try ClubGovernanceValidation.validate(snapshot.value, operation: .topicOverview, scope: snapshot.scope)
        guard ClubCustomerHistoryTopicRoute.positiveID(value["id"]) == topicID else { throw ClubGovernanceFailure.targetChanged }
        let rows = try Self.rows(value["chaptersList"])
        let nodesByChapter = try rows.map { try Self.rows($0["nodes"]) }
        for node in nodesByChapter.flatMap({ $0 }) where node["cmsMemberTemplate"] != .null {
            guard node["cmsMemberTemplate"].object != nil else { throw ClubGovernanceFailure.malformed }
        }
        let chapterIDs = Self.countIDs(rows.map { $0["id"] })
        let nodeIDs = Self.countIDs(nodesByChapter.flatMap { $0 }.map { $0["id"] })
        let templateIDs = Self.countIDs(nodesByChapter.flatMap { $0 }.map { $0["cmsMemberTemplate"]["id"] })
        var sequence = 0
        chapters = zip(rows.indices, rows).map { index, chapter in
            let chapterID = Self.uniqueID(chapter["id"], counts: chapterIDs)
            var stops: [ClubStoryStop] = []
            var gameplay: [ClubStoryGameplay] = []
            for node in nodesByChapter[index] {
                sequence += 1
                let nodeID = chapterID == nil ? nil : Self.uniqueID(node["id"], counts: nodeIDs)
                let name = Self.text(node["name"])
                let cover = Self.image(node["imgUrl"])
                stops.append(.init(id: sequence, nodeID: nodeID, sequence: sequence,
                    businessTime: Self.text(node["businessTime"]), name: name,
                    address: Self.text(node["address"]), imgUrl: cover))
                let template = node["cmsMemberTemplate"]
                guard template.object != nil else { continue }
                let templateID = Self.uniqueID(template["id"], counts: templateIDs).flatMap(MemberPlayTemplateID.init(rawValue:))
                // A missing/ambiguous chapter, node or member-template identity disables
                // every action for the card, without discarding its safe display content.
                let interactive = chapterID != nil && nodeID != nil && templateID != nil
                gameplay.append(.init(id: sequence, chapterID: interactive ? chapterID : nil,
                    nodeID: interactive ? nodeID : nil, memberTemplateID: interactive ? templateID : nil,
                    sequence: sequence, nodeName: name, title: Self.text(template["title"]) ?? name,
                    validationMethod: Self.method(template["validationMethod"]),
                    validationMethodLabel: Self.text(template["validationMethodStr"]),
                    players: Self.text(template["players"]), duration: Self.minutes(template["duration"]),
                    difficulty: Self.text(template["difficulty"]), imgUrl: Self.image(template["imgUrl"]) ?? cover))
            }
            return .init(id: index, chapterID: chapterID, name: Self.text(chapter["name"]),
                description: Self.text(chapter["description"]), totalTime: Self.minutes(chapter["totalTime"]),
                stops: stops, gameplay: gameplay)
        }
        self.topicID = topicID
    }
    private static func rows(_ value: ClubGovernanceValue) throws -> [ClubGovernanceValue] {
        if value == .null { return [] }
        guard let rows = value.array, rows.allSatisfy({ $0.object != nil }) else { throw ClubGovernanceFailure.malformed }
        return rows
    }
    private static func countIDs(_ values: [ClubGovernanceValue]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for id in values.compactMap(ClubCustomerHistoryTopicRoute.positiveID) { counts[id, default: 0] += 1 }
        return counts
    }
    private static func uniqueID(_ value: ClubGovernanceValue, counts: [Int: Int]) -> Int? {
        guard let id = ClubCustomerHistoryTopicRoute.positiveID(value), counts[id] == 1 else { return nil }
        return id
    }
    private static func text(_ value: ClubGovernanceValue) -> String? {
        guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if case .decimal(let number) = value, !number.isFinite { return nil }
        return text
    }
    private static func minutes(_ value: ClubGovernanceValue) -> Double? {
        guard let number = value.number, number.isFinite, number > 0 else { return nil }
        return number
    }
    private static func method(_ value: ClubGovernanceValue) -> Int? {
        // Preserve explicit zero, but never coerce null/false/blank into "manual".
        if value == .integer(0) || value == .decimal(0) || value == .string("0") { return 0 }
        return ClubCustomerHistoryTopicRoute.positiveID(value)
    }
    /// URL screening grants no media access. The existing bounded anonymous image
    /// reader still owns origin approval, redirects, download limits and sanitation.
    private static func image(_ value: ClubGovernanceValue) -> String? {
        guard let raw = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              raw.utf8.count <= 8192, raw.removingPercentEncoding != nil,
              !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let parts = URLComponents(string: raw), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.url != nil else { return nil }
        return raw
    }
}

/// Ephemeral, namespace-safe navigation. A template projection cannot create a
/// member-template read grant; the destination's existing reader remains authoritative.
public struct ClubStoryTemplateRoute: Hashable, Identifiable {
    public let id = UUID()
    public let templateID: MemberPlayTemplateID
    public let context: ClubGovernanceReadContext
    public let snapshotGeneration: UInt64
    private let selection: ClubStorySelection
    public init?(gameplay: ClubStoryGameplay, snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) {
        guard let selection = ClubStorySelection(gameplay: gameplay, snapshot: snapshot, context: context),
              let templateID = gameplay.memberTemplateID else { return nil }
        self.templateID = templateID; self.selection = selection
        self.context = context; self.snapshotGeneration = snapshotGeneration
    }
    public func isCurrent(snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) -> Bool {
        self.context == context && self.snapshotGeneration == snapshotGeneration && selection.isCurrent(snapshot: snapshot, context: context)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Only the existing nodeAnswer read can reveal answers, after its own permission
/// readback. Nothing in the public story projection contains answer data or grants.
public struct ClubStoryAnswerRoute: Hashable, Identifiable {
    public let id = UUID()
    public let nodeID: Int
    public let scope: ClubGovernanceScope
    public let context: ClubGovernanceReadContext
    public let snapshotGeneration: UInt64
    private let selection: ClubStorySelection
    public init?(gameplay: ClubStoryGameplay, snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) {
        guard let selection = ClubStorySelection(gameplay: gameplay, snapshot: snapshot, context: context),
              gameplay.isAnswerable, let nodeID = gameplay.nodeID,
              snapshot.permissions?.allows(ClubGovernanceRead.nodeAnswer.permission, scope: context.scope) == true else { return nil }
        self.nodeID = nodeID; self.selection = selection; self.context = context; self.snapshotGeneration = snapshotGeneration
        scope = .init(clubID: context.scope.clubID, topicID: context.scope.topicID, activityID: context.scope.activityID, nodeID: nodeID)
    }
    public func isCurrent(snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) -> Bool {
        self.context == context && self.snapshotGeneration == snapshotGeneration &&
        snapshot?.permissions?.allows(ClubGovernanceRead.nodeAnswer.permission, scope: scope) == true &&
        selection.isCurrent(snapshot: snapshot, context: context)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct ClubStorySelection {
    let chapter: ClubStoryChapter
    let gameplay: ClubStoryGameplay
    private let fingerprint: [UInt8]
    init?(gameplay: ClubStoryGameplay, snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) {
        guard Self.valid(snapshot, context: context), let chapterID = gameplay.chapterID,
              gameplay.nodeID != nil, gameplay.memberTemplateID != nil,
              let projection = try? ClubStoryPresentation(snapshot: snapshot),
              let chapter = projection.chapters.first(where: { $0.chapterID == chapterID }),
              chapter.gameplay.filter({ $0.id == gameplay.id }) == [gameplay],
              let fingerprint = Self.fingerprint(snapshot.value) else { return nil }
        self.chapter = chapter; self.gameplay = gameplay; self.fingerprint = fingerprint
    }
    func isCurrent(snapshot: ClubGovernanceSnapshot?, context: ClubGovernanceReadContext) -> Bool {
        guard let snapshot, Self.valid(snapshot, context: context),
              Self.fingerprint(snapshot.value) == fingerprint,
              let projection = try? ClubStoryPresentation(snapshot: snapshot) else { return false }
        return projection.chapters.filter({ $0.chapterID == chapter.chapterID }) == [chapter] &&
            chapter.gameplay.filter({ $0.id == gameplay.id }) == [gameplay]
    }
    /// A digest detects every changed source field without retaining opaque wire
    /// objects or potentially private bytes inside a navigation selection.
    private static func fingerprint(_ value: ClubGovernanceValue) -> [UInt8]? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(value) else { return nil }
        return Array(SHA256.hash(data: bytes))
    }
    private static func valid(_ snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) -> Bool {
        context.operation == .topicOverview && context.accepts(snapshot) &&
        (context.identity?.accountID ?? 0) > 0 && context.accessIdentity != nil &&
        snapshot.permissions?.allows(ClubGovernanceRead.topicOverview.permission, scope: context.scope) == true
    }
}
