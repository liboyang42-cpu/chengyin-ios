import Foundation

/// C03 route / community-day projection. TAKE_SEGMENT applies frozen effects.
/// Community day reads the server weekpart snapshot, never a client clock.
public struct RouteCommunityDayProjection: Equatable {
    public static let actionTakeSegment = "TAKE_SEGMENT"
    public static let weekpartWeekend = "weekend"
    public var binder: MechanismRequestIdProjection
    public init(binder: MechanismRequestIdProjection = MechanismRequestIdProjection()) {
        self.binder = binder
    }
    public func select(segments: [MechanismSegmentRow]?, communityDay: MechanismCommunityDayRow?) -> MechanismFreeze {
        var block = MechanismFreeze()
        let rows = segments ?? []
        block.segments = rows
        block.communityDay = communityDay
        block.routeCommunityDayEnabled = !rows.isEmpty
        return block
    }
    public mutating func putFrozen(_ play: inout MechanismPlay, segments: [MechanismSegmentRow]?,
                                   communityDay: MechanismCommunityDayRow?) {
        let selected = select(segments: segments, communityDay: communityDay)
        play.frozen.routeCommunityDayEnabled = selected.routeCommunityDayEnabled
        play.frozen.segments = selected.segments
        play.frozen.communityDay = selected.communityDay
    }
    public mutating func simulate(_ play: MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        var copy = play.copyForSimulate()
        copy.originalRequestID = originalRequestID
        var result = try applyLive(&copy)
        result.simulated = true
        result.requestId = originalRequestID
        return result
    }
    public mutating func apply(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        try MechanismRequestIdProjection.requireExplicitChoice(play, .routeCommunityDay)
        try MechanismRequestIdProjection.requireEnabled(play, .routeCommunityDay)
        let action = play.playerChoice?.action
        return try binder.oneShot(&play, mechanism: .routeCommunityDay, choice: action,
                                  originalRequestID: originalRequestID) { live in
            try applyLive(&live)
        }
    }
    public mutating func recoverOriginal(_ play: inout MechanismPlay, originalRequestID: String) throws -> MechanismResult {
        try binder.recoverUnknown(&play, originalRequestID: originalRequestID)
    }
    public mutating func succeedFromClientClock(_ now: Date) throws -> Never {
        _ = now
        throw MechanismFailure.clientClockForbidden
    }
    public mutating func commitV12Docx() throws -> Never {
        throw MechanismFailure.waitingSource(capability: MechanismSourceInventory.v12Docx)
    }
    private func applyLive(_ play: inout MechanismPlay) throws -> MechanismResult {
        let requestId = try MechanismRequestIdProjection.requireRequestID(play.originalRequestID)
        let action = play.playerChoice?.action
        guard action == Self.actionTakeSegment else { throw MechanismFailure.unsupportedAction(action ?? "UNSUPPORTED") }
        guard let segmentId = play.playerChoice?.segmentId else { throw MechanismFailure.missingFrozenRow("MISSING") }
        guard let segment = play.frozen.segments.first(where: { $0.id == segmentId }) else {
            throw MechanismFailure.missingFrozenRow(segmentId)
        }
        if segment.communityDay { try requireCommunityDay(play) }
        try play.state.applyEffects(segment.effects)
        var result = MechanismResult(requestId: requestId, status: MechanismStatus.applied.rawValue)
        result.action = Self.actionTakeSegment
        result.segmentId = segmentId
        result.communityDay = segment.communityDay
        result.weekpart = play.state.environmentText("weekpart")
        return result
    }
    private func requireCommunityDay(_ play: MechanismPlay) throws {
        guard let community = play.frozen.communityDay, community.enabled else {
            throw MechanismFailure.notEnabled("communityDay")
        }
        let expected = community.weekpart
        let actual = play.state.environmentText("weekpart")
        let pass = play.state.conditionsPass(MechanismCondition(
            op: "ENV_IN", key: "weekpart", values: [expected]))
        guard pass, actual != nil else {
            throw MechanismFailure.clientClockForbidden
        }
    }
}
