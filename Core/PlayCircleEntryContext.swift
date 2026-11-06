import Foundation

/// Navigation data only. Neither an invitation nor a registration ID grants access.
/// Kept separate from ParticipationPlayEntry and all runtime service factories.
public struct PlayCircleEntryContext: Equatable, Sendable {
    public let topicID: Int?
    public let inviteCode: String?
    public let registrationID: Int?

    public init?(topicID: Int?, inviteCode: String?, registrationID: Int?) {
        guard topicID.map({ $0 > 0 }) ?? true,
              registrationID.map({ $0 > 0 }) ?? true else { return nil }
        if let inviteCode {
            guard !inviteCode.isEmpty, inviteCode.utf8.count <= 64,
                  inviteCode.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        }
        self.topicID = topicID
        self.inviteCode = inviteCode
        self.registrationID = registrationID
    }

    public var legacyLink: PlayCircleLegacyLink {
        guard let topicID else { return .missingParameter }
        return .play(topicID: topicID, inviteCode: inviteCode, registrationID: registrationID)
    }
}

/// Presentation lifetime only, not an authentication or authorization grant.
/// The host must retire on dismissal/background and pass its current session revision.
public struct PlayCircleEntryPresentation {
    private var context: PlayCircleEntryContext?
    private let revision: UInt64

    public init(context: PlayCircleEntryContext, sessionRevision: UInt64) {
        self.context = context
        self.revision = sessionRevision
    }

    public func context(currentSessionRevision: UInt64) -> PlayCircleEntryContext? {
        guard currentSessionRevision == revision else { return nil }
        return context
    }

    public mutating func retire() { context = nil }
}
