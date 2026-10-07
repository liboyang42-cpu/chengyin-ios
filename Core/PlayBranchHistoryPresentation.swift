import Foundation

/// The exact scope, run and version that opened the read-only presentation.
/// It stores no rows and cannot carry an old route into a newly loaded snapshot.
public struct PlayBranchHistorySelection: Equatable, Identifiable {
    public let scope: PlaySessionScope
    public let sessionID: Int
    public let version: Int
    public var id: String { "\(scope.fields.keys.sorted().joined()):\(scope.id):\(sessionID):\(version)" }
    public init?(snapshot: PlaySnapshot) {
        guard snapshot.result.mode == 1, let route = snapshot.route, route.isBranch,
              let sessionID = route.sessionID, sessionID > 0, let version = route.version, version >= 0 else { return nil }
        scope = snapshot.scope; self.sessionID = sessionID; self.version = version
    }
    public func presentation(snapshot: PlaySnapshot?) -> PlayBranchHistoryPresentation? {
        guard let snapshot, Self(snapshot: snapshot) == self else { return nil }
        return PlayBranchHistoryPresentation(snapshot: snapshot)
    }
}

/// Server sequence only. No sorting by time, deduplication, inferred edges, node
/// navigation, result mutation or additional network reads belongs in this value.
public struct PlayBranchHistoryPresentation: Equatable {
    public struct Row: Equatable, Identifiable {
        /// Position is stable for this read and permits repeated edges / loop visits.
        public let id: Int
        public let fromName: String?
        public let toName: String?
        public let time: String?
    }
    public enum State: Equatable { case unavailable, empty, recorded }
    public let state: State
    public let rows: [Row]
    public let containsInvalidEntries: Bool
    public init(snapshot: PlaySnapshot) {
        guard PlayBranchHistorySelection(snapshot: snapshot) != nil, let log = snapshot.route?.decisionLog else {
            state = .unavailable; rows = []; containsInvalidEntries = false; return
        }
        // Names may come only from nodes already visible under current authority.
        // Neither nodeStates keys nor hidden raw node names may become a title.
        let names = Dictionary(uniqueKeysWithValues: snapshot.visibleNodes.compactMap { node -> (Int, String)? in
            guard let name = node.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name.utf8.count <= 512,
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return (node.id, name)
        })
        rows = log.entries.enumerated().map { index, entry in
            Row(id: log.sourceIndices[index], fromName: names[entry.fromNodeID], toName: names[entry.toNodeID], time: entry.recordedAt?.displayText)
        }
        containsInvalidEntries = log.discardedEntryCount > 0
        state = rows.isEmpty ? (containsInvalidEntries ? .unavailable : .empty) : .recorded
    }
}
