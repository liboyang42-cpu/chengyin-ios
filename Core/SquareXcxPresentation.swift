import Foundation

/// Display rules ported from the mini-program Square pages (`pages/square/list`, `pages/square/detail`,
/// `components/cy/post-card`). Pure presentation: no request, write or media authority lives here.
public enum SquareXcxTime {
    /// Source `toTimestamp`: wall-clock strings are China time (+08:00); ISO strings keep their offset;
    /// all-digit values are epoch milliseconds. Unparseable values stay unknown (nil), never "now".
    public static func date(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.utf8.allSatisfy({ (48...57).contains($0) }), let ms = Double(value), ms > 0 { return Date(timeIntervalSince1970: ms / 1000) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        for pattern in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
    public static func date(_ time: OfficialEventTime?) -> Date? {
        switch time {
        case .milliseconds(let ms)?: return ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
        case .text(let text)?: return date(text)
        case nil: return nil
        }
    }
}

/// Source `formatTimeDifference`: `N天前`, otherwise `[H时][M分]前`, and `刚刚` at zero minutes.
public enum SquareRelativeAge: Equatable {
    case justNow
    case days(Int)
    case hoursMinutes(hours: Int, minutes: Int)
    public static func of(_ createTime: String, now: Date) -> Self? {
        guard let date = SquareXcxTime.date(createTime) else { return nil }
        let elapsed = now.timeIntervalSince(date)
        guard elapsed.isFinite, elapsed > 0 else { return .justNow }
        let totalMinutes = Int(elapsed / 60)
        let days = totalMinutes / (24 * 60)
        if days > 0 { return .days(days) }
        let hours = totalMinutes / 60, minutes = totalMinutes % 60
        return hours == 0 && minutes == 0 ? .justNow : .hoursMinutes(hours: hours, minutes: minutes)
    }
}

/// Source list banner: official events with `bannerEnabled`, status 1 or 2, starting within the next 24 hours.
public struct SquareUpcomingBannerItem: Equatable, Identifiable {
    public enum Countdown: Equatable { case days(Int), hours(Int), minutes(Int), soon }
    public let id: Int
    public let title: String
    public let subtitle: String?
    public let start: Date
    public let avatars: [String]
    public let overflow: Int
    public func countdown(now: Date) -> Countdown {
        let seconds = start.timeIntervalSince(now)
        if seconds >= 86_400 { return .days(Int(seconds / 86_400)) }
        if seconds >= 3_600 { return .hours(Int(seconds / 3_600)) }
        if seconds >= 60 { return .minutes(Int(seconds / 60)) }
        return .soon
    }
    public static func select(_ events: [OfficialEvent], now: Date) -> [Self] {
        let horizon = now.addingTimeInterval(86_400)
        return events.compactMap { event -> Self? in
            guard event.isCompleteRecord, event.bannerEnabled, event.status == 1 || event.status == 2,
                  let start = SquareXcxTime.date(event.activityStart), start >= now, start < horizon else { return nil }
            let avatars = Array(event.participantAvatars.prefix(3))
            let total = max(event.participants ?? 0, event.participantAvatars.count)
            let subtitle = [event.subtitle, event.city].lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            return .init(id: event.id, title: event.title, subtitle: subtitle, start: start, avatars: avatars, overflow: max(0, total - 3))
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    }
}

/// Derived post-card facts (source `cy-post-card` and `feed-play-card`).
public struct SquarePostCardFacts: Equatable {
    public enum Lifecycle: String, Equatable { case draft = "DRAFT", checking = "CHECKING", limited = "LIMITED", hidden = "HIDDEN", removed = "REMOVED" }
    public enum PlaySubtitle: Equatable { case completedNodes(Int), progress(done: Int, total: Int), completed, inProgress }
    public let isCompletionShare: Bool
    public let hasPlayCover: Bool
    public let playCover: String?
    public let playSubtitle: PlaySubtitle?
    public let lifecycle: Lifecycle?
    public let bodyExpandable: Bool
    /// Images shown in the horizontal strip; a route preview leads when the post has no play card.
    public let strip: [String]
    public let leadingRoutePreview: String?
    public let showsCountPill: Bool
    public let isRemixable: Bool
    public init(_ post: SquarePost) {
        let cover = SquarePostCardFacts.nonempty(post.routeImage) ?? SquarePostCardFacts.nonempty(post.referenceCover)
        let title = SquarePostCardFacts.nonempty(post.referenceTitle)
        isCompletionShare = post.dataType == 3 || (post.dataType == 1 && post.completed && title != nil)
        hasPlayCover = title != nil && cover != nil
        playCover = isCompletionShare ? (post.images.first ?? cover) : (hasPlayCover ? cover : nil)
        if title == nil { playSubtitle = nil }
        else if post.nodeTotal > 0 { playSubtitle = post.completed ? .completedNodes(post.nodeTotal) : .progress(done: max(0, min(post.nodeDoneCount, post.nodeTotal)), total: post.nodeTotal) }
        else { playSubtitle = post.completed ? .completed : .inProgress }
        lifecycle = Lifecycle(rawValue: post.lifecycle)
        let body = post.contents ?? ""
        bodyExpandable = body.count > 40 || body.filter({ $0 == "\n" }).count >= 2
        leadingRoutePreview = isCompletionShare || title != nil ? nil : cover
        strip = isCompletionShare ? [] : post.images
        showsCountPill = post.images.count >= 2
        isRemixable = post.isTopicTemplate && (post.topicID ?? 0) > 0
    }
    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
