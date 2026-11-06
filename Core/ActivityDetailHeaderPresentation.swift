import Foundation

/// Source meeting-point row (scene-play-activity-detail `activity-meta`): a named place,
/// a coordinate-only location ("查看地图"), or an explicit unconfirmed state ("位置待确认").
public enum ActivityDetailMeetingPoint: Equatable {
    case named(String)
    case mapOnly
    case unconfirmed
}

/// Presentation-only facts for the source detail meta block: 分类 / 集合点 / 已报名.
/// Values come only from the allowed detail response. Nothing is inferred or defaulted:
/// a missing registration count stays unknown instead of being shown as zero.
public struct ActivityDetailHeaderFacts: Equatable {
    /// Source `sysCategoryList[].categoryName` joined with " · "; nil means 分类待确认.
    public let categoryText: String?
    public let meetingPoint: ActivityDetailMeetingPoint
    /// Source `registrationCount`; the bounded roster preview is never counted instead.
    public let registrationCount: Int?

    public init(detail: ActivityDetail) {
        let names = detail.summary.categoryNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        categoryText = names.isEmpty ? nil : names.joined(separator: " · ")
        // Source order: addressName || address, then the coordinate-only map hint.
        if let place = Self.nonempty(detail.summary.addressName) ?? Self.nonempty(detail.summary.address) {
            meetingPoint = .named(place)
        } else if detail.summary.hasValidCoordinates {
            meetingPoint = .mapOnly
        } else {
            meetingPoint = .unconfirmed
        }
        registrationCount = detail.people.registrationCount
    }

    static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Source section order for the ready detail page. `ActivityDetailView` keeps the extra map
/// section between `about` and `tickets` because test_activity_design_structure.py locks
/// header → about → map → tickets; the source itself has no map section (its meeting-point
/// row opens the system map instead).
public enum ActivityDetailSourceSection: String, CaseIterable {
    case header, cancelled, meta, about, host, participants, associatedPlays, tickets, reviews
}
