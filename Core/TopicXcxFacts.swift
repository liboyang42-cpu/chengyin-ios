import Foundation

/// Display rules ported from mini-program `pages/topic/index` and `pages/topic/utils/topic-detail-facts.js`.
/// Pure presentation over `TopicDetail`; no request, purchase or write authority.
public enum TopicXcxFacts {
    /// Source `buildTopicStatBar`: cells are skipped when missing or not positive.
    public enum StatCell: Equatable {
        case rating(value: Double, stars: Int)
        case hours(text: String)
        case open(start: String, end: String)
        case mileage(text: String)
        case merchants(Int)
    }
    public static func statBar(_ topic: TopicDetail) -> [StatCell] {
        var cells: [StatCell] = []
        if let rating = topic.averageRating, rating.isFinite, rating > 0 {
            cells.append(.rating(value: (rating * 10).rounded() / 10, stars: max(0, min(5, Int(rating.rounded())))))
        }
        if let seconds = topic.totalTimeSeconds, Double(seconds) / 3600 >= 0.1 {
            let hours = (Double(seconds) / 3600 * 10).rounded() / 10
            let text = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
            cells.append(.hours(text: text + "+"))
        }
        if let start = monthDay(topic.startDate), let end = monthDay(topic.endDate) { cells.append(.open(start: start, end: end)) }
        if let mileage = topic.totalMileage, mileage.isFinite, mileage > 0 {
            cells.append(.mileage(text: mileage == mileage.rounded() ? String(Int(mileage)) : String(mileage)))
        }
        if let merchants = topic.merchantCount, merchants > 0 { cells.append(.merchants(merchants)) }
        return cells
    }

    /// Source `M.D` in China time from `yyyy-MM-dd[ HH:mm:ss]`.
    public static func monthDay(_ raw: String?) -> String? {
        guard let raw, let date = SquareXcxTime.date(raw.count == 10 ? raw + " 00:00:00" : raw) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }
        return "\(month).\(day)"
    }

    /// Source `formatTimeToChinese(seconds)`.
    public enum Duration: Equatable { case zero, underMinute, minutes(Int), hours(Int), hoursMinutes(Int, Int) }
    public static func duration(seconds: Int?) -> Duration {
        guard let seconds, seconds >= 0 else { return .zero }
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        if hours == 0 { return minutes == 0 ? .underMinute : .minutes(minutes) }
        return minutes == 0 ? .hours(hours) : .hoursMinutes(hours, minutes)
    }

    /// Source `contentIncludes`, in order, each only when present.
    public enum Include: Equatable {
        case chapters(Int), stops(Int), plays(Int), audioMinutes(Int), audio, medal(String?), coupon
    }
    public static func includes(_ topic: TopicDetail) -> [Include] {
        var rows: [Include] = []
        if topic.totalChapterCount > 0 { rows.append(.chapters(topic.totalChapterCount)) }
        if let stops = topic.locationCount, stops > 0 { rows.append(.stops(stops)) }
        if topic.templateCount > 0 { rows.append(.plays(topic.templateCount)) }
        if let audio = topic.audioURL, !audio.trimmingCharacters(in: .whitespaces).isEmpty {
            let minutes = Int((Double(topic.audioDuration ?? 0) / 60).rounded())
            rows.append(minutes > 0 ? .audioMinutes(minutes) : .audio)
        }
        let medal = topic.finishMedalName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (medal?.isEmpty == false) || topic.finishMedalImage?.isEmpty == false {
            // Source fallback chain: finishMedalName, else "<name> · 通关", else 通关纪念 (nil → App copy).
            rows.append(.medal(medal?.isEmpty == false ? medal : (topic.name.isEmpty ? nil : topic.name + " · 通关")))
        }
        if topic.completeRewardCouponID != nil { rows.append(.coupon) }
        return rows
    }

    /// Source `buildVenue`: `名称（地址）` with full-width or ASCII parentheses.
    public static func venue(_ addressName: String?) -> (name: String, address: String?)? {
        guard let raw = addressName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "null" else { return nil }
        for (open, close) in [("（", "）"), ("(", ")")] {
            if raw.hasSuffix(close), let range = raw.range(of: open) {
                let name = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let address = String(raw[range.upperBound..<raw.index(before: raw.endIndex)]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return (name, address.isEmpty ? nil : address) }
            }
        }
        return (raw, nil)
    }

    /// Source `buildLineup`: club first, then distinct node merchants.
    public struct LineupMember: Equatable { public enum Kind: Equatable { case club, merchant }; public let kind: Kind; public let targetID: Int; public let name: String }
    public static func lineup(_ topic: TopicDetail) -> [LineupMember] {
        var rows: [LineupMember] = []
        if let club = topic.clubName?.trimmingCharacters(in: .whitespacesAndNewlines), !club.isEmpty {
            rows.append(.init(kind: .club, targetID: topic.clubID ?? 0, name: club))
        }
        var seen = Set<String>()
        for merchant in topic.chapters.flatMap({ $0.nodes.flatMap(\.merchants) }) {
            let name = merchant.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(merchant.memberID > 0 ? "id:\(merchant.memberID)" : "name:" + name).inserted else { continue }
            rows.append(.init(kind: .merchant, targetID: merchant.memberID, name: name))
        }
        return rows
    }

    /// Source session text: same day `MM-DD HH:mm–HH:mm`, otherwise `start ~ end`.
    public static func sessionTime(start: String?, end: String?) -> String? {
        func parts(_ raw: String?) -> (day: String, time: String)? {
            guard let raw, raw.count >= 16 else { return nil }
            let chars = Array(raw)
            guard chars[4] == "-", chars[7] == "-", chars[13] == ":" else { return nil }
            return (String(chars[5..<10]), String(chars[11..<16]))
        }
        guard let first = parts(start) else { return nil }
        guard let last = parts(end) else { return first.day + " " + first.time }
        return first.day == last.day ? "\(first.day) \(first.time)–\(last.time)" : "\(first.day) \(first.time) ~ \(last.day) \(last.time)"
    }

    /// Bottom bar states (source `is_join`, `lifecycle` 1/2/7, `selfPlay`).
    public enum Action: Equatable { case ticketWallet, locked(Int), selfPlay(price: Decimal?), signUp }
    public static func action(_ topic: TopicDetail) -> Action {
        if topic.isSignUp { return .ticketWallet }
        if let lifecycle = topic.lifecycle, [1, 2, 7].contains(lifecycle) { return .locked(lifecycle) }
        return topic.selfPlay == 1 ? .selfPlay(price: topic.selfPlayPrice) : .signUp
    }
    /// Owner of a topic in pricing (lifecycle 2) is sent to the final-price page instead of a toast.
    public static func opensPricing(_ topic: TopicDetail) -> Bool { topic.isOwner && topic.lifecycle == 2 }
}
