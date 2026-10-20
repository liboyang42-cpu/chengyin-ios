import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Source: pages/activity/official-detail (_decorate, _cta, _countdown, MISSION_TYPE_TEXT,
// CATEGORY_TEXT, parseContentCards). Display only: nothing here grants participation,
// navigation or a write, and timezone-less text dates are never reinterpreted.

/// Server text shown verbatim, a catalog key, or the source "活动任务 N" fallback.
public enum OfficialDetailText: Equatable {
    case verbatim(String), key(String), numberedTask(Int)
}
public enum OfficialDetailFactValue: Equatable {
    case verbatim(String), key(String), days(Int), hours(Int)
}
public enum OfficialDetailFactSub: Equatable {
    case key(String), countdown(OfficialEventCountdown)
}
public struct OfficialDetailFact: Equatable, Identifiable {
    public let id: String
    public let labelKey: String
    public let value: OfficialDetailFactValue
    public let sub: OfficialDetailFactSub
}
public enum OfficialDetailMissionAction: Equatable {
    case verified, verify, automatic, unsupported
    public var key: String {
        switch self {
        case .verified: return "official.task.verified"
        case .verify: return "official.detailParity.mission.verify"
        case .automatic: return "official.detailParity.mission.automatic"
        case .unsupported: return "official.detailParity.mission.unsupported"
        }
    }
}
public struct OfficialDetailMission: Equatable {
    public let index: Int
    public let title: OfficialDetailText
    public let description: OfficialDetailText
    public let supported: Bool
    public let action: OfficialDetailMissionAction
    public let binding: OfficialMissionBinding?
    public init(_ mission: OfficialMission, index: Int) {
        let meta = Self.meta(mission.type)
        let title = mission.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (mission.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.index = index
        self.title = title.isEmpty ? .key(meta?.label ?? "official.detailParity.mission.unknown") : .verbatim(title)
        self.description = description.isEmpty
            ? .key(meta?.action ?? "official.detailParity.mission.unknownAction") : .verbatim(description)
        supported = meta?.supported == true
        if mission.complete == true { action = .verified }
        else if !supported { action = .unsupported }
        else { action = mission.canVerifyArrival == true ? .verify : .automatic }
        binding = mission.binding
    }
    /// Backend publish/verify support per missionType; unknown types are never supported.
    public static func isSupported(_ type: String?) -> Bool { meta(type)?.supported == true }
    private static func meta(_ type: String?) -> (label: String, action: String, supported: Bool)? {
        switch type {
        case "ROAM_POI_ARRIVAL":
            return ("official.detailParity.mission.roamPoi", "official.detailParity.mission.unsupportedAction", false)
        case "EVENT_POINT_ARRIVAL":
            return ("official.detailParity.mission.eventPoint", "official.detailParity.mission.eventPointAction", true)
        case "THEME_VERIFIED_FINISH":
            return ("official.detailParity.mission.theme", "official.detailParity.mission.themeAction", true)
        case "ROAM_SESSION_AREA":
            return ("official.detailParity.mission.roamArea", "official.detailParity.mission.unsupportedAction", false)
        default: return nil
        }
    }
}
/// Source parseContentCards: v1 `contentJson.tasks`, strings or objects, never completed.
public struct OfficialDetailCard: Equatable {
    public let index: Int
    public let title: OfficialDetailText
    public let description: OfficialDetailText
    public static func cards(contentJSON: String?) -> [OfficialDetailCard] {
        guard let data = contentJSON?.data(using: .utf8),
              let content = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tasks = content["tasks"] as? [Any] else { return [] }
        return tasks.enumerated().map { (index: Int, task: Any) -> OfficialDetailCard in
            if let text = task as? String {
                return OfficialDetailCard(index: index, title: .verbatim(text), description: .numberedTask(index + 1))
            }
            let map: [String: Any] = (task as? [String: Any]) ?? [:]
            func first(_ keys: [String]) -> String? {
                keys.compactMap { map[$0] as? String }.first(where: { !$0.isEmpty })
            }
            return OfficialDetailCard(
                index: index,
                title: first(["title", "name"]).map { OfficialDetailText.verbatim($0) } ?? .numberedTask(index + 1),
                description: first(["description", "shortDescription", "type"]).map { OfficialDetailText.verbatim($0) }
                    ?? .key("official.detailParity.card.defaultDescription"))
        }
    }
}
/// Source `_cta` text; the iOS label never navigates. Signup stays with OfficialParticipationActions.
public enum OfficialDetailCTA: Equatable {
    case ended, paused, roamArrival, themeSync, unsupportedTasks, waitTasks, roamLight, explore
    case signedWaiting, signed, signup, registrationSoon, unavailable
    public var key: String {
        switch self {
        case .ended: return "official.detailParity.cta.ended"
        case .paused: return "official.detailParity.cta.paused"
        case .roamArrival: return "official.detailParity.cta.roamArrival"
        case .themeSync: return "official.detailParity.cta.themeSync"
        case .unsupportedTasks: return "official.detailParity.cta.unsupportedTasks"
        case .waitTasks: return "official.detailParity.cta.waitTasks"
        case .roamLight: return "official.detailParity.cta.roamLight"
        case .explore: return "official.detailParity.cta.explore"
        case .signedWaiting: return "official.detailParity.cta.signedWaiting"
        case .signed: return "official.detailParity.cta.signed"
        case .signup: return "official.detailParity.cta.signup"
        case .registrationSoon: return "official.detailParity.cta.registrationSoon"
        case .unavailable: return "official.detailParity.cta.unavailable"
        }
    }
    /// The source `type` is not wait/ended, so its page would act on a tap.
    public var isSourceAction: Bool {
        switch self {
        case .roamArrival, .themeSync, .roamLight, .explore, .signup: return true
        default: return false
        }
    }
}
/// Source detail load outcome: only an explicit missing event offers the list exit.
public enum OfficialDetailLoadFailure: Equatable {
    case unavailable, network, other
    public init(_ error: Error) {
        if let failure = error as? OfficialReadFailure, failure == .unavailable { self = .unavailable }
        else if error is URLError { self = .network }
        else { self = .other }
    }
}
public extension OfficialEvent {
    /// Source CATEGORY_TEXT; absent or unknown categories read as an official event.
    var categoryKey: String {
        switch category {
        case "city_light": return "official.detailParity.category.cityLight"
        case "custom": return "official.detailParity.category.custom"
        case "festival": return "official.detailParity.category.festival"
        case "brand": return "official.detailParity.category.brand"
        case "challenge": return "official.detailParity.category.challenge"
        case "hidden": return "official.detailParity.category.hidden"
        case "community": return "official.detailParity.category.community"
        case "merchant_hunt": return "official.detailParity.category.merchantHunt"
        default: return "official.detailParity.category.official"
        }
    }
    var detailCTA: OfficialDetailCTA {
        if let status, status >= 5 { return .ended }
        if paused { return .paused }
        if signed == true {
            if status == 3 && isV2 {
                if missions.contains(where: { $0.canVerifyArrival == true }) { return .roamArrival }
                if missions.contains(where: { $0.type == "THEME_VERIFIED_FINISH" }) { return .themeSync }
                // Only backend-unpublishable types: say so rather than promising tasks.
                if !missions.isEmpty && missions.allSatisfy({ !OfficialDetailMission.isSupported($0.type) }) { return .unsupportedTasks }
                return .waitTasks
            }
            if status == 3 { return roamEnabled ? .roamLight : .explore }
            return status == 1 ? .signedWaiting : .signed
        }
        if status == 2 || status == 3 { return .signup }
        if status == 1 { return .registrationSoon }
        return .unavailable
    }
}
public extension OfficialCollectiveProgress {
    var detailPercentText: String { percent.map { "\($0)%" } ?? "--%" }
    var detailCountText: String {
        "\(current.map { String($0) } ?? "--") / \(threshold.map { String($0) } ?? "--")"
    }
}

public struct OfficialEventDetailPresentation: Equatable {
    public let categoryKey: String
    public let facts: [OfficialDetailFact]
    public let intro: String?
    /// The "详情信息" section appears only when both story and subtitle exist.
    public let storyDetail: String?
    public let cards: [OfficialDetailCard]
    public let missions: [OfficialDetailMission]
    public let eligibilityKey: String?
    public let pausedReason: String?
    public let cta: OfficialDetailCTA
    public let collectiveTipKey: String
    public init(event: OfficialEvent, now: Date) {
        func present(_ value: String?) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        categoryKey = event.categoryKey
        cards = event.isV2 ? [] : OfficialDetailCard.cards(contentJSON: event.contentJSON)
        missions = event.isV2 ? event.missions.enumerated().map { OfficialDetailMission($0.element, index: $0.offset) } : []
        intro = present(event.subtitle) ?? present(event.story)
        storyDetail = present(event.subtitle) == nil ? nil : present(event.story)
        eligibilityKey = event.isV2
            ? (event.eligible == true ? "official.detailParity.eligible" : "official.detailParity.notEligible") : nil
        pausedReason = present(event.pausedReason)?.trimmingCharacters(in: .whitespacesAndNewlines)
        cta = event.detailCTA
        collectiveTipKey = event.hasCollectiveReward
            ? "official.detailParity.collective.tipConfigured" : "official.detailParity.collective.tipAbsent"
        var facts = [OfficialDetailFact(id: "participants", labelKey: "official.detailParity.fact.participants",
                                        value: .verbatim(String(event.participants ?? 0)),
                                        sub: .key("official.detailParity.fact.participantsSub"))]
        if event.signed == true {
            facts.append(event.isV2
                ? OfficialDetailFact(id: "progress", labelKey: "official.detailParity.fact.progress",
                                     value: .verbatim("\(event.completedMissionCount)/\(event.missions.count)"),
                                     sub: .key("official.detailParity.fact.progressTasks"))
                : OfficialDetailFact(id: "progress", labelKey: "official.detailParity.fact.progress",
                                     value: .verbatim(String(event.myProgress ?? 0)),
                                     sub: .key("official.detailParity.fact.progressCompleted")))
        }
        facts.append(OfficialDetailFact(id: "duration", labelKey: "official.detailParity.fact.duration",
                                        value: Self.duration(start: event.activityStart, end: event.activityEnd),
                                        sub: .key("official.detailParity.fact.durationSub")))
        facts.append(OfficialDetailFact(id: "dates", labelKey: "official.detailParity.fact.dates",
                                        value: Self.dateRange(start: event.activityStart, end: event.activityEnd),
                                        sub: .key("official.detailParity.fact.datesSub")))
        let countdown: OfficialDetailFactSub
        switch event.countdown(now: now) {
        case .startsIn(let span)?: countdown = .countdown(.startsIn(span))
        case .endsIn(let span)?: countdown = .countdown(.endsIn(span))
        default: countdown = .key(event.statusKey)
        }
        facts.append(OfficialDetailFact(id: "scope", labelKey: "official.detailParity.fact.scope",
                                        value: present(event.city).map { OfficialDetailFactValue.verbatim($0) } ?? .key("official.detailParity.fact.nationwide"),
                                        sub: countdown))
        let taskTotal = event.isV2 ? missions.count : cards.count
        if taskTotal > 0 {
            facts.append(OfficialDetailFact(id: "tasks", labelKey: "official.detailParity.fact.tasks",
                                            value: .verbatim(String(taskTotal)), sub: .key("official.detailParity.fact.tasksSub")))
        }
        self.facts = facts
    }
    /// Ceil days from 24 h, else ceil hours (at least one); numeric timestamps only.
    public static func duration(start: OfficialEventTime?, end: OfficialEventTime?) -> OfficialDetailFactValue {
        guard case .milliseconds(let from)? = start, case .milliseconds(let to)? = end else { return .key("official.notAnnounced") }
        let span = to - from
        guard span > 0, span < 1e15 else { return .key("official.notAnnounced") }
        if span >= 86_400_000 { return .days(max(1, Int((span / 86_400_000).rounded(.up)))) }
        return .hours(max(1, Int((span / 3_600_000).rounded(.up))))
    }
    /// "M.D–M.D" in Beijing time (source chinaParts); one known end shows alone.
    public static func dateRange(start: OfficialEventTime?, end: OfficialEventTime?) -> OfficialDetailFactValue {
        switch (monthDay(start), monthDay(end)) {
        case let (from?, to?): return .verbatim(from + "\u{2013}" + to)
        case let (from?, nil): return .verbatim(from)
        case let (nil, to?): return .verbatim(to)
        case (nil, nil): return .key("official.notAnnounced")
        }
    }
    static func monthDay(_ time: OfficialEventTime?) -> String? {
        guard case .milliseconds(let ms)? = time, ms > 0, ms < 1e15,
              let zone = TimeZone(identifier: "Asia/Shanghai") else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: ms / 1000))
        guard let month = parts.month, let day = parts.day else { return nil }
        return "\(month).\(day)"
    }
}
