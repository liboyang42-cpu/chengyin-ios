import Foundation

public extension OfficialMissionBinding {
    /// A THEME binding's sourceRefId is a cms_topic id; other bindings have no topic route.
    var themeTopicID: Int? {
        guard bindingType == "THEME", let id = sourceRefID, id > 0, id <= Int64(Int.max) else { return nil }
        return Int(id)
    }
}

/// Source official-detail onMissionTap/goBoundTopic/_loadBoundTopicNames. Opening a topic is
/// navigation only: completion is still verified and synced by the server.
public enum OfficialDetailTopicLinks {
    public static let themeMission = "THEME_VERIFIED_FINISH"
    /// Unique bound topic ids in mission order, for the public topic name read.
    public static func topicIDs(_ event: OfficialEvent) -> [Int] {
        guard event.isV2 else { return [] }
        var seen = Set<Int>()
        return event.missions.compactMap { $0.binding?.themeTopicID }.filter { seen.insert($0).inserted }
    }
    /// An incomplete THEME mission opens its topic for a signed viewer; arrival, unsupported
    /// and unsigned taps keep their own source paths and never open a topic.
    public static func linkedTopic(_ mission: OfficialMission, signed: Bool) -> Int? {
        guard signed, mission.complete != true, mission.canVerifyArrival != true,
              mission.type == themeMission else { return nil }
        return mission.binding?.themeTopicID
    }
    /// The theme CTA opens the first incomplete bound THEME mission, as the source does.
    public static func ctaTopic(_ event: OfficialEvent, cta: OfficialDetailCTA) -> Int? {
        guard cta == .themeSync else { return nil }
        return event.missions.lazy.compactMap { linkedTopic($0, signed: event.signed == true) }.first
    }
}

/// Source "活动内容没加载成功": a server or response failure that is retryable, as opposed to
/// missing content, a network outage or an access state.
public enum OfficialDetailServiceFailure {
    public static func matches(_ error: Error) -> Bool {
        if case OfficialReadFailure.rejected? = error as? OfficialReadFailure { return true }
        switch error as? APIError {
        case .httpStatus?, .malformedResponse?: return true
        default: return false
        }
    }
}
