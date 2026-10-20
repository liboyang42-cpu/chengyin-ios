import Foundation

/// Additive `w2-11` play runtime auxiliary binding that resolves the read-only ticket
/// `entryCode` (`ParticipationPlayEntry.registrationID`) for a `PlaySessionScope` and
/// coordinates `PlayCircleLegacyLink` retirement state without triggering any network writes.
public struct PlayRuntimeAuxiliaryBinding: Equatable {
    /// Retirement state for legacy `pages/play/circle` links (`w2-11`).
    public enum CircleRetirementState: Equatable {
        /// Missing or non-positive `topicId`: host renders `PlayCircleRetiredLinkView`
        /// (`探索链接不完整` / `请从圈层主题或同行人分享的邀请重新进入` / `返回首页`).
        case missingParameter
        /// Valid `topicId`: redirects to unified play runtime with `.topic(topicID)`,
        /// sanitized `inviteCode`, and optional positive `registrationID`.
        case redirectToPlay(
            scope: PlaySessionScope,
            topicID: Int,
            inviteCode: String?,
            registrationID: Int?
        )

        public var isRetiredMissingPrompt: Bool {
            if case .missingParameter = self { return true }
            return false
        }

        public var playEntry: ParticipationPlayEntry? {
            guard case .redirectToPlay(let scope, _, _, let registrationID?) = self else { return nil }
            return ParticipationPlayEntry(registrationID: registrationID, scope: scope)
        }
    }

    public let scope: PlaySessionScope
    /// Resolved read-only ticket registration ID for `PlayEntryCodeContext`; nil when
    /// absent, non-positive, or scoped to a different activity/topic.
    public let entryRegistrationID: Int?
    public let circleRetirement: CircleRetirementState?

    public var hasEntryCode: Bool {
        guard let entryRegistrationID else { return false }
        return entryRegistrationID > 0
    }

    /// True when the play runtime should show the missing-ticket explanation
    /// (`从票夹进入才能出示入场码`) instead of guessing a ticket.
    public var showsMissingEntryCodeExplanation: Bool {
        !hasEntryCode
    }

    public init(
        scope: PlaySessionScope,
        participationEntry: ParticipationPlayEntry? = nil,
        legacyCircleLink: PlayCircleLegacyLink? = nil
    ) {
        self.scope = scope
        let circleState = legacyCircleLink.map(Self.resolveCircleRetirement)
        self.circleRetirement = circleState
        if let resolvedFromEntry = Self.resolveEntryRegistrationID(for: scope, entry: participationEntry) {
            self.entryRegistrationID = resolvedFromEntry
        } else if let circleEntry = circleState?.playEntry {
            self.entryRegistrationID = Self.resolveEntryRegistrationID(for: scope, entry: circleEntry)
        } else {
            self.entryRegistrationID = nil
        }
    }

    public init(
        scope: PlaySessionScope,
        rawRegistrationID: Int?,
        entryScope: PlaySessionScope?,
        legacyCircleQuery: [String: String]? = nil
    ) {
        self.scope = scope
        let circleState = legacyCircleQuery.map(Self.resolveCircleRetirement(query:))
        self.circleRetirement = circleState
        if let resolved = Self.resolveEntryRegistrationID(
            for: scope,
            rawRegistrationID: rawRegistrationID,
            entryScope: entryScope
        ) {
            self.entryRegistrationID = resolved
        } else if let circleEntry = circleState?.playEntry {
            self.entryRegistrationID = Self.resolveEntryRegistrationID(for: scope, entry: circleEntry)
        } else {
            self.entryRegistrationID = nil
        }
    }

    /// Resolves the read-only `entryCode` registration ID from a `ParticipationPlayEntry`.
    /// Returns `nil` when `entry` is nil, `scope` is invalid, `registrationID <= 0`,
    /// or `entry.scope` does not match `scope`.
    public static func resolveEntryRegistrationID(
        for scope: PlaySessionScope,
        entry: ParticipationPlayEntry?
    ) -> Int? {
        guard scope.isValid, let entry, entry.registrationID > 0, entry.scope == scope else {
            return nil
        }
        return entry.registrationID
    }

    /// Resolves the read-only `entryCode` registration ID from raw registration parameters.
    /// Returns `nil` when `rawRegistrationID` is nil or `<= 0`, `scope` is invalid,
    /// or `entryScope` is nil / mismatched with `scope`.
    public static func resolveEntryRegistrationID(
        for scope: PlaySessionScope,
        rawRegistrationID: Int?,
        entryScope: PlaySessionScope?
    ) -> Int? {
        guard scope.isValid,
              let rawRegistrationID,
              rawRegistrationID > 0,
              let entryScope,
              entryScope == scope,
              let validated = ParticipationPlayEntry(registrationID: rawRegistrationID, scope: entryScope) else {
            return nil
        }
        return validated.registrationID
    }

    /// Coordinates `PlayCircleLegacyLink` retirement state from an incoming query dictionary.
    public static func resolveCircleRetirement(query: [String: String]) -> CircleRetirementState {
        resolveCircleRetirement(link: PlayCircleLegacyLink.resolve(query))
    }

    /// Coordinates `PlayCircleLegacyLink` retirement state from a resolved `PlayCircleLegacyLink`.
    public static func resolveCircleRetirement(link: PlayCircleLegacyLink) -> CircleRetirementState {
        switch link {
        case .missingParameter:
            return .missingParameter
        case .play(let topicID, let inviteCode, let registrationID):
            let scope = PlaySessionScope.topic(topicID)
            guard topicID > 0, scope.isValid else { return .missingParameter }
            let validRegistrationID = registrationID.flatMap { $0 > 0 ? $0 : nil }
            return .redirectToPlay(
                scope: scope,
                topicID: topicID,
                inviteCode: inviteCode,
                registrationID: validRegistrationID
            )
        }
    }
}
