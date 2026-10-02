import Foundation

/// Both inputs come from the SAME authorized play/nodes snapshot. No extra endpoint or credential is introduced.
public struct PlatformChapterAudioSelection: Equatable {
    public let chapterID: Int
    public let chapterName: String?
    public let narrationURL: String?
    public let guideURL: String?
    public static func resolve(snapshot: PlaySnapshot?, nodeID: Int, extras: [Int: PlayNodeExtras], currentRead: Bool) -> Self? {
        guard currentRead, let snapshot, snapshot.availability == .active || snapshot.availability == .completed,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }), !snapshot.isLocked(node),
              let chapterID = node.chapterID,
              let chapter = snapshot.result.chapters.first(where: { $0.id == chapterID }) else { return nil }
        return .init(chapterID: chapterID, chapterName: chapter.name,
                     narrationURL: nonempty(chapter.audioURL), guideURL: nonempty(extras[nodeID]?.audioURL))
    }
    private static func nonempty(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
