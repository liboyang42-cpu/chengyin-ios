import Foundation

/// Rules ported from mini-program `pages/topic/merchantapply` (merchant stop registration form).
public enum MerchantApplyXcx {
    /// Source `canSubmit` order of the first missing item.
    public enum Missing: Equatable { case address, dates, description, photos }
    public static func firstMissing(address: String, startDay: String?, endDay: String?, description: String, photoCount: Int) -> Missing? {
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .address }
        if ((try? dateRange(start: startDay, end: endDay)) ?? nil) == nil { return .dates }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .description }
        if photoCount < 1 { return .photos }
        return nil
    }
    public static let maximumPhotos = 9
    public static let maximumDescription = 500

    /// Both days or neither. Days are `YYYY-MM-DD`; a same-day range is allowed; reversed ranges are invalid.
    public static func dateRange(start: String?, end: String?) throws -> (start: String, end: String)? {
        let a = start?.trimmingCharacters(in: .whitespaces) ?? "", b = end?.trimmingCharacters(in: .whitespaces) ?? ""
        if a.isEmpty && b.isEmpty { return nil }
        guard isDay(a), isDay(b), a <= b else { throw MerchantContentFailure.invalid }
        return (a, b)
    }
    static func isDay(_ value: String) -> Bool {
        let chars = Array(value)
        guard chars.count == 10, chars[4] == "-", chars[7] == "-",
              chars.enumerated().allSatisfy({ [4, 7].contains($0.offset) || $0.element.isASCII && $0.element.isNumber }),
              let month = Int(String(chars[5...6])), let day = Int(String(chars[8...9])) else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }

    /// Source pre-fill of `cooperateDate` from the shop's `businessTime` when it parses as `HH:mm-HH:mm`
    /// (`—`, `～`, `~` normalised to `-`, spaces removed, text after `·` dropped).
    public static func cooperateDate(fromBusinessTime raw: String?) -> String? {
        guard var value = raw else { return nil }
        if let dot = value.firstIndex(of: "·") { value = String(value[..<dot]) }
        value = value.replacingOccurrences(of: "—", with: "-").replacingOccurrences(of: "～", with: "-").replacingOccurrences(of: "~", with: "-")
        value = value.replacingOccurrences(of: " ", with: "")
        let parts = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy(isClock) else { return nil }
        return parts[0] + "-" + parts[1]
    }
    static func isClock(_ value: String) -> Bool {
        let p = value.split(separator: ":").map(String.init)
        guard p.count == 2, p.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }), let h = Int(p[0]), let m = Int(p[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    /// Source edit-block rules for an existing registration.
    public enum EditBlock: Equatable { case topicStarted, approved, stateChanged }
    public static func editBlock(status: Int?, auditStatus: Int?, topicStartDay: String?, today: String) -> EditBlock? {
        if let start = topicStartDay?.prefix(10), isDay(String(start)), String(start) <= today { return .topicStarted }
        let pending = status == 0 && (auditStatus ?? 0) == 0
        let rejected = (status == 2 || status == 3) && auditStatus == 2
        if pending || rejected { return nil }
        if status == 1 || auditStatus == 1 { return .approved }
        return .stateChanged
    }
    /// Today in China time (`YYYY-MM-DD`), the source's comparison calendar.
    public static func chinaToday(_ now: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 8 * 3600); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }

    /// Source dirty-exit confirmation copy (`放弃当前编辑内容？` / `继续编辑` / `放弃并退出`).
    public static let dirtyExitTitle = "放弃当前编辑内容？"
    public static let dirtyExitKeepEditingTitle = "继续编辑"
    public static let dirtyExitDiscardTitle = "放弃并退出"
    public static let submissionNotice = "报名成功不等于中标，需创作者审核选用后才进入正式路线"

    public struct DirtyExitConfirmation: Equatable, Sendable {
        public let title: String
        public let keepEditingTitle: String
        public let discardAndExitTitle: String

        public init(
            title: String = MerchantApplyXcx.dirtyExitTitle,
            keepEditingTitle: String = MerchantApplyXcx.dirtyExitKeepEditingTitle,
            discardAndExitTitle: String = MerchantApplyXcx.dirtyExitDiscardTitle
        ) {
            self.title = title
            self.keepEditingTitle = keepEditingTitle
            self.discardAndExitTitle = discardAndExitTitle
        }
    }

    public static func dirtyExitConfirmation(isDirty: Bool) -> DirtyExitConfirmation? {
        isDirty ? DirtyExitConfirmation() : nil
    }

    /// Source submission success-phase summary for create (`报名已提交`) and edit (`报名信息已更新`).
    public struct SubmissionSuccessSummary: Equatable, Sendable {
        public let isEdit: Bool
        public let title: String
        public let notice: String
        public let chapterTitle: String?
        public let placeSummary: String?
        public let dateRangeText: String?

        public init(
            isEdit: Bool = false,
            chapterTitle: String? = nil,
            placeName: String? = nil,
            placeAddress: String? = nil,
            startDate: String? = nil,
            endDate: String? = nil
        ) {
            self.isEdit = isEdit
            self.title = isEdit ? "报名信息已更新" : "报名已提交"
            self.notice = MerchantApplyXcx.submissionNotice
            let trimmedChapter = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.chapterTitle = (trimmedChapter?.isEmpty == false) ? trimmedChapter : nil
            let trimmedPlace = placeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmedAddress = placeAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedPlace.isEmpty && !trimmedAddress.isEmpty {
                self.placeSummary = "\(trimmedPlace) · \(trimmedAddress)"
            } else if !trimmedPlace.isEmpty {
                self.placeSummary = trimmedPlace
            } else if !trimmedAddress.isEmpty {
                self.placeSummary = trimmedAddress
            } else {
                self.placeSummary = nil
            }
            let s = String((startDate ?? "").prefix(10)).trimmingCharacters(in: .whitespacesAndNewlines)
            let e = String((endDate ?? "").prefix(10)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty && !e.isEmpty {
                self.dateRangeText = "\(s) 至 \(e)"
            } else {
                self.dateRangeText = nil
            }
        }
    }

    public static func submissionSuccessSummary(
        isEdit: Bool = false,
        chapterTitle: String? = nil,
        placeName: String? = nil,
        placeAddress: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil
    ) -> SubmissionSuccessSummary {
        SubmissionSuccessSummary(
            isEdit: isEdit,
            chapterTitle: chapterTitle,
            placeName: placeName,
            placeAddress: placeAddress,
            startDate: startDate,
            endDate: endDate
        )
    }
}
