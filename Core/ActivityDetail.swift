import Foundation

public struct ActivityTicket: Decodable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let price: Decimal?
    public let remainingInventory: Int?
    public let description: String?
    public let startTime: String?
    public let endTime: String?
    public let selfGuided: Bool?
    public let signupDeadline: String?
    /// Source PublicTicketVO.meetingPoint (oms_ticket.meeting_point): this session's gathering
    /// place, distinct from the activity venue. Blank or non-text values stay absent.
    public let meetingPoint: String?
    /// Early UI guard mirrors the current activity create service, not a purchase grant.
    /// Zone-free timestamps use the existing Shanghai server-date parser. Missing or
    /// malformed ordinary timestamps cannot establish expiry. Self-guided tickets require
    /// a valid end timestamp. The server remains authoritative.
    public func registrationClosed(at now: Date) -> Bool {
        let end = endTime.flatMap(RegistrationWaitlistStatus.parseDeadline)
        if selfGuided == true {
            guard let end else { return true }
            if now >= end { return true }
            if let deadline = signupDeadline.flatMap(RegistrationWaitlistStatus.parseDeadline), now >= deadline { return true }
            return false
        }
        let boundary = startTime.flatMap(RegistrationWaitlistStatus.parseDeadline) ?? end
        return boundary.map { now >= $0 } ?? false
    }
    private enum CodingKeys: String, CodingKey { case id,name,price,remainingInventory,description,startTime,endTime,selfGuided,signupDeadline,meetingPoint }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(Int.self,forKey:.id)
        name=try c.decode(String.self,forKey:.name)
        price=try c.decodeIfPresent(Decimal.self,forKey:.price)
        remainingInventory=try c.decodeIfPresent(Int.self,forKey:.remainingInventory)
        description=try c.decodeIfPresent(String.self,forKey:.description)
        startTime=try c.decodeIfPresent(String.self,forKey:.startTime)
        endTime=try c.decodeIfPresent(String.self,forKey:.endTime)
        selfGuided=try c.decodeIfPresent(Bool.self,forKey:.selfGuided)
        signupDeadline=try c.decodeIfPresent(String.self,forKey:.signupDeadline)
        // Optional display text must not invalidate an otherwise valid ticket.
        let point = ((try? c.decodeIfPresent(String.self,forKey:.meetingPoint)) ?? nil)?.trimmingCharacters(in:.whitespacesAndNewlines)
        meetingPoint = point.flatMap { $0.isEmpty ? nil : $0 }
        guard id > 0, price.map({ $0 >= .zero }) ?? true else { throw APIError.malformedResponse }
    }
    public var isSoldOut: Bool { remainingInventory.map { $0 <= 0 } ?? false }
    public var isConfirmedFree: Bool { price == Decimal.zero }
}

/// Three display fields already included in the allowed activity response.
/// No template ID, private rules, answer, media URL or myinfo authority is retained.
public struct ActivityAssociatedPlay: Decodable, Equatable {
    public let title: String?
    public let players: String?
    public let durationMinutes: Double?
    private enum Keys: String, CodingKey { case title, players, duration }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        func text(_ key: Keys) -> String? {
            guard let raw = try? values.decode(String.self, forKey: key) else { return nil }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        title = text(.title)
        if let text = text(.players) { players = text }
        else if let count = try? values.decode(Int.self, forKey: .players), count >= 0 { players = String(count) }
        else { players = nil }
        if let duration = try? values.decode(Double.self, forKey: .duration), duration.isFinite, duration >= 0 {
            durationMinutes = duration
        } else { durationMinutes = nil }
    }
}

public struct ActivityDetail: Decodable, Equatable {
    /// Fresh source evidence stays separate from display defaults; unavailable proof stays nil.
    public let publisherAuthoritySource: PublisherActivityAuthoritySource?
    public let summary: ActivitySummary
    public let tickets: [ActivityTicket]
    public let people: ActivityPeople
    public let reviews: ActivityReviews
    public let associatedPlays: [ActivityAssociatedPlay]
    public let hostMemberID: Int?
    /// Source `isSignUp`: only exact 0/1 numbers are meaningful; anything else stays unknown.
    public let signUpFlag: Int?
    /// Source `cancelTime`/`cancelReason`: a non-empty cancel time means the host cancelled.
    public let cancelTime: String?
    public let cancelReason: String?
    enum CodingKeys: String, CodingKey { case omsTicketList, memberId, memberTemplateList, isSignUp, cancelTime, cancelReason }
    public init(from decoder:Decoder) throws {
        publisherAuthoritySource = try? PublisherActivityAuthoritySource(from: decoder)
        summary=try ActivitySummary(from:decoder)
        people=try ActivityPeople(from:decoder)
        reviews=try ActivityReviews(from:decoder)
        let c=try decoder.container(keyedBy:CodingKeys.self)
        tickets=try c.decodeIfPresent([ActivityTicket].self,forKey:.omsTicketList) ?? []
        associatedPlays=try c.decodeIfPresent([ActivityAssociatedPlay].self,forKey:.memberTemplateList) ?? []
        hostMemberID=try c.decodeIfPresent(Int.self,forKey:.memberId)
        let flag = (try? c.decodeIfPresent(Int.self,forKey:.isSignUp)) ?? nil
        signUpFlag = flag == 0 || flag == 1 ? flag : nil
        cancelTime=Self.text(c,.cancelTime); cancelReason=Self.text(c,.cancelReason)
    }
    private static func text(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        // Dates may arrive as text or epoch milliseconds; either one is a present cancellation.
        if let number = (try? c.decodeIfPresent(Double.self,forKey:key)) ?? nil, number.isFinite, number > 0 { return String(Int64(number)) }
        guard let value = (try? c.decodeIfPresent(String.self,forKey:key)) ?? nil else { return nil }
        let trimmed = value.trimmingCharacters(in:.whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    public var isCancelled: Bool { cancelTime != nil }
    /// Mirrors the source detail CTA (scene-play-activity-detail actionFor). A missing flag keeps
    /// the existing registration entry, whose sheet and server still own eligibility checks.
    public func primaryAction(now: Date) -> ActivityPrimaryAction {
        if isCancelled { return .cancelled }
        guard signUpFlag == 1 else { return .signUp }
        if let start = ActivityPrimaryAction.chinaDate(summary.startDate), now < start { return .viewRegistration }
        if let end = ActivityPrimaryAction.chinaDate(summary.endDate, dayOnly: true),
           let last = Calendar.chinaActivity.date(byAdding: DateComponents(day: 1, second: -1), to: end), now > last { return .viewTrace }
        return .continueExploring
    }
}

public enum ActivityPrimaryAction: Equatable {
    case signUp, viewRegistration, continueExploring, viewTrace, cancelled
    public var titleKey: String {
        switch self {
        case .signUp: return "activity.cta.signUp"
        case .viewRegistration: return "activity.cta.viewRegistration"
        case .continueExploring: return "activity.cta.continue"
        case .viewTrace: return "activity.cta.trace"
        case .cancelled: return "activity.cta.cancelled"
        }
    }
    /// Source activity dates are Beijing wall-clock text ("yyyy-MM-dd[ HH:mm[:ss]]").
    static func chinaDate(_ raw: String?, dayOnly: Bool = false) -> Date? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "/", with: "-")
        if dayOnly { value = String(value.prefix(10)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = .chinaActivity
        formatter.timeZone = Calendar.chinaActivity.timeZone
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
extension Calendar {
    static let chinaActivity: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }()
}


public enum ActivityDetailAccess: Decodable, Equatable {
    case allowed(ActivityDetail)
    case clubRequired(clubID: Int?, message: String?)
    enum CodingKeys: String, CodingKey { case gate, clubId, message }
    public init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        if try c.decodeIfPresent(Bool.self,forKey:.gate) == true {
            let numeric=try? c.decode(Int.self,forKey:.clubId)
            let text=try? c.decode(String.self,forKey:.clubId)
            let id=numeric ?? text.flatMap(Int.init)
            self = .clubRequired(clubID:id.flatMap { $0 > 0 ? $0 : nil },message:try c.decodeIfPresent(String.self,forKey:.message))
        } else { self = .allowed(try ActivityDetail(from:decoder)) }
    }
}
