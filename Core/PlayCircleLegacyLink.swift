import Foundation

/// Mini-program `pages/play/circle/index.js onLoad`: circle themes were merged into free
/// exploration, so the page is only a shim for old share links. A topic id redirects to
/// the unified play page with `inviteCode` / `registrationId` carried over; anything
/// else shows 探索链接不完整. The invite join itself stays with the play page.
public enum PlayCircleLegacyLink: Equatable, Sendable {
    case play(topicID: Int, inviteCode: String?, registrationID: Int?)
    case missingParameter

    public static func resolve(_ query: [String: String]) -> PlayCircleLegacyLink {
        // The mini-program only checks presence; a native route additionally needs a positive id.
        guard let raw = query["topicId"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let topicID = Int(raw), topicID > 0 else { return .missingParameter }
        let invite = query["inviteCode"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let inviteCode = invite.flatMap { $0.isEmpty || $0.count > 64 || !$0.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) ? nil : $0 }
        let registrationID = query["registrationId"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.flatMap { $0 > 0 ? $0 : nil }
        return .play(topicID: topicID, inviteCode: inviteCode, registrationID: registrationID)
    }

    public var playScope: PlaySessionScope? {
        if case .play(let topicID, _, _) = self { return .topic(topicID) }
        return nil
    }
}
