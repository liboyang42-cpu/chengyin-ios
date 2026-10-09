import Foundation

/// Native UI works with instants in the phone's zone. The real topic/ticket DTOs
/// parse their wall-clock strings with fixed GMT+8, not a device or ISO-week year.
public enum ProjectEditDateSelection {
    public enum Field: Hashable {
        case start, end, deadline
        case ticketStart(String), ticketEnd(String), saleStart(String), saleEnd(String)
        public var identifier: String {
            switch self {
            case .start: return "theme-start"
            case .end: return "theme-end"
            case .deadline: return "recruit-deadline"
            case .ticketStart(let id): return "ticket-start-" + id
            case .ticketEnd(let id): return "ticket-end-" + id
            case .saleStart(let id): return "sale-start-" + id
            case .saleEnd(let id): return "sale-end-" + id
            }
        }
        public var ending: Bool {
            switch self { case .end, .deadline, .ticketEnd, .saleEnd: return true; default: return false }
        }
        public var ticketID: String? {
            switch self {
            case .ticketStart(let id), .ticketEnd(let id), .saleStart(let id), .saleEnd(let id): return id
            default: return nil
            }
        }
        public func raw(in draft: ProjectEditDraft) -> String? {
            switch self {
            case .start: return draft.startDate
            case .end: return draft.endDate
            case .deadline: return draft.product == .freeExplore ? draft.recruitDeadline : nil
            default:
                guard let id = ticketID, draft.tickets.filter({ $0.id == id }).count == 1,
                      let ticket = draft.tickets.first(where: { $0.id == id }) else { return nil }
                switch self {
                case .ticketStart: return ticket.startTime
                case .ticketEnd: return ticket.endTime
                case .saleStart: return ticket.saleStartTime
                case .saleEnd: return ticket.saleEndTime
                default: return nil
                }
            }
        }
        public func editable(in draft: ProjectEditDraft) -> Bool {
            guard raw(in: draft) != nil else { return false }
            guard let id = ticketID, let ticket = draft.tickets.first(where: { $0.id == id }) else { return true }
            switch self {
            case .ticketStart, .ticketEnd: return !(draft.product == .freeExplore && ticket.syncsWithThemeDates)
            case .saleStart: return ticket.canEditSaleTime(end: false)
            case .saleEnd: return ticket.canEditSaleTime(end: true)
            default: return true
            }
        }
    }
    public enum Failure: Error { case unsupportedValue, staleTarget, invalidRange }
    private static func formatter() -> DateFormatter {
        let value = DateFormatter(); value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        value.dateFormat = "yyyy-MM-dd HH:mm:ss"; value.isLenient = false; return value
    }
    public static func date(_ raw: String, ending: Bool) -> Date? {
        guard let normalized = ProjectEditValidation.dateTime(raw, endOfDay: ending) else { return nil }
        let formatter = formatter()
        guard let result = formatter.date(from: normalized), formatter.string(from: result) == normalized else { return nil }
        return result
    }
    public static func beijingValue(_ date: Date) -> String? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let value = formatter().string(from: date)
        return ProjectEditValidation.dateTime(value) == value ? value : nil
    }
    public static func applying(_ selected: Date, field: Field, to draft: ProjectEditDraft) throws -> ProjectEditDraft {
        guard field.editable(in: draft), let original = field.raw(in: draft) else { throw Failure.staleTarget }
        guard original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || date(original, ending: field.ending) != nil else { throw Failure.unsupportedValue }
        if date(original, ending: field.ending) == selected { return draft } // Retain exact original spelling/precision.
        guard let value = beijingValue(selected) else { throw Failure.unsupportedValue }
        var next = draft
        switch field {
        case .start: next.startDate = value
        case .end: next.endDate = value
        case .deadline: next.recruitDeadline = value
        default:
            guard let id = field.ticketID, let index = next.tickets.firstIndex(where: { $0.id == id }) else { throw Failure.staleTarget }
            switch field {
            case .ticketStart: next.tickets[index].startTime = value
            case .ticketEnd: next.tickets[index].endTime = value
            case .saleStart: next.tickets[index].saleStartTime = value
            case .saleEnd: next.tickets[index].saleEndTime = value
            default: break
            }
        }
        let start: Date?, end: Date?, strict: Bool
        switch field {
        case .start, .end:
            start = date(next.startDate, ending: false); end = date(next.endDate, ending: true); strict = false
        case .deadline: return next
        default:
            guard let id = field.ticketID, let ticket = next.tickets.first(where: { $0.id == id }) else { throw Failure.staleTarget }
            switch field {
            case .saleStart, .saleEnd:
                start = date(ticket.saleStartTime, ending: false); end = date(ticket.saleEndTime, ending: true); strict = false
            default:
                let schedule = ticket.schedule(in: next)
                start = date(schedule.start, ending: false); end = date(schedule.end, ending: true); strict = next.product == .city
            }
        }
        if let start, let end, end < start || (strict && end == start) { throw Failure.invalidRange }
        return next
    }
}
