import Foundation

/// Start payload for ordinary city orienteering. The frozen rule version is copied
/// onto `resultVersionID` so finish and dispute cannot silently follow a later publish.
public struct EventScoreStartPayload: Equatable, Sendable {
    public let courseID: Int
    public let frozenRuleVersionID: String
    public let resultVersionID: String
    public let safetyVersionID: String
}

public struct EventScoreTerminalAction: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case finish, dispute }
    public let kind: Kind
    public let courseID: Int
    public let resultVersionID: String
}

/// Event score version identity. Not Growth personal rank and not a live republish.
public enum EventScoreVersionProjection {
    public static func freeze(
        selection: OrdinaryCityCourseSelection, safety: OrienteeringSafetyVersion
    ) -> EventScoreStartPayload? {
        guard safety.matches(selection),
              OrdinaryCityCourseSelector.versionOK(selection.publishedRuleVersionID) else { return nil }
        return EventScoreStartPayload(
            courseID: selection.courseID,
            frozenRuleVersionID: selection.publishedRuleVersionID,
            resultVersionID: selection.publishedRuleVersionID,
            safetyVersionID: selection.safetyVersionID)
    }
    public static func finish(
        start: EventScoreStartPayload, resultVersionID: String
    ) -> EventScoreTerminalAction? {
        terminal(.finish, start: start, resultVersionID: resultVersionID)
    }
    public static func dispute(
        start: EventScoreStartPayload, resultVersionID: String
    ) -> EventScoreTerminalAction? {
        terminal(.dispute, start: start, resultVersionID: resultVersionID)
    }
    /// A later published rule id cannot rewrite an already frozen start.
    public static func retainsFrozenRule(
        start: EventScoreStartPayload, laterPublishedRuleVersionID: String
    ) -> Bool {
        start.frozenRuleVersionID == start.resultVersionID
            && start.frozenRuleVersionID != laterPublishedRuleVersionID
    }
    private static func terminal(
        _ kind: EventScoreTerminalAction.Kind, start: EventScoreStartPayload, resultVersionID: String
    ) -> EventScoreTerminalAction? {
        guard OrdinaryCityCourseSelector.versionOK(resultVersionID),
              resultVersionID == start.resultVersionID,
              resultVersionID == start.frozenRuleVersionID,
              start.courseID > 0 else { return nil }
        return EventScoreTerminalAction(kind: kind, courseID: start.courseID, resultVersionID: resultVersionID)
    }
}
