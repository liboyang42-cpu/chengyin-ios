import Foundation

/// One anniversary card's link to the *current* route for its topic.
/// Read-only navigation reference only: it never starts or continues a roam,
/// and it is never derived from the memory id, title or completion time.
public struct RoamAnniversaryRouteTarget: Equatable, Hashable {
    public let memoryID: String
    /// Canonical topic id text, passed unchanged to the host's existing topic detail.
    public let topicID: String
    public let topicValue: Int64

    public init?(memory: RoamAnniversaryMemory) {
        guard Self.isCanonicalPositiveID(memory.id),
              Self.isCanonicalPositiveID(memory.topicID),
              let value = Int64(memory.topicID) else { return nil }
        memoryID = memory.id; topicID = memory.topicID; topicValue = value
    }

    static func isCanonicalPositiveID(_ text: String) -> Bool {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let value = Int64(text), value > 0 else { return false }
        return String(value) == text
    }
}

public enum RoamAnniversaryRouteAvailability: Equatable {
    case available(RoamAnniversaryRouteTarget)
    case invalidTopicID
    case noDestination

    /// An unusable card is reported as unavailable, never silently linked or
    /// redirected to another topic. Invalid ids win over a missing host so a
    /// malformed record is not mistaken for an unconfigured destination.
    public static func resolve(memory: RoamAnniversaryMemory, hasDestination: Bool) -> Self {
        guard let target = RoamAnniversaryRouteTarget(memory: memory) else { return .invalidTopicID }
        return hasDestination ? .available(target) : .noDestination
    }
}

/// Lease for one presented route. Every return/cover callback must carry
/// this exact value back; owner alone, or the same target re-opened later,
/// is never enough to complete a different presentation.
public struct RoamAnniversaryRoutePresentation: Equatable, Hashable {
    public let target: RoamAnniversaryRouteTarget
    public let generation: UInt64
}

/// Owner-fenced navigation state for anniversary -> route -> back.
/// The selected date and rows stay in the view; this state only remembers
/// that a route was opened under one account/epoch so the return can ask
/// for exactly one refresh of that same date, and so a late or foreign
/// return can never refresh or reopen another owner's private records.
public struct RoamAnniversaryNavigationState: Equatable {
    public private(set) var owner: RoamExperienceIdentity?
    public private(set) var openedPresentation: RoamAnniversaryRoutePresentation?
    public var openedTarget: RoamAnniversaryRouteTarget? { openedPresentation?.target }
    /// Bumped on every open, owner/date invalidation and completed return;
    /// a lease minted before a bump can never match a later presentation.
    public private(set) var generation: UInt64 = 0

    public init() {}

    /// Account, epoch or signed-out changes clear the opened route and
    /// (via the caller observing the same change) the private rows.
    /// Rebinding the same owner is a no-op.
    public mutating func bind(to newOwner: RoamExperienceIdentity?) {
        guard newOwner != owner else { return }
        owner = newOwner
        openedPresentation = nil
        generation += 1
    }

    /// Date changes retire any route opened for the previous date.
    public mutating func invalidate() {
        openedPresentation = nil
        generation += 1
    }

    /// Records a route opening only if the exact rendered card is still in
    /// the current rows under the bound owner. A replaced row with the same
    /// memory id but a different topic, a paginated-out row, or a foreign
    /// owner can no longer issue the action.
    @discardableResult
    public mutating func open(_ target: RoamAnniversaryRouteTarget,
                              memory: RoamAnniversaryMemory,
                              currentRows: [RoamAnniversaryMemory],
                              owner currentOwner: RoamExperienceIdentity?) -> Bool {
        guard openedPresentation == nil,
              let currentOwner, currentOwner == owner,
              currentRows.contains(memory),
              RoamAnniversaryRouteTarget(memory: memory) == target else { return false }
        generation += 1
        openedPresentation = RoamAnniversaryRoutePresentation(target: target, generation: generation)
        return true
    }

    /// The opened route may stay on screen only for the exact lease that
    /// opened it, under the owner that opened it.
    public func mayRemainOpen(_ presentation: RoamAnniversaryRoutePresentation?,
                              owner currentOwner: RoamExperienceIdentity?) -> Bool {
        guard let currentOwner, currentOwner == owner, let presentation else { return false }
        return openedPresentation == presentation
    }

    /// A disappearance that is not a return: the detail was covered (for
    /// example it pushed a child page) or otherwise temporarily hidden.
    /// The lease survives untouched, so drilling down and coming back to
    /// the same detail neither closes the route nor earns a refresh.
    public mutating func noteCovered(_ presentation: RoamAnniversaryRoutePresentation?,
                                     owner currentOwner: RoamExperienceIdentity?) {
        guard mayRemainOpen(presentation, owner: currentOwner) else { return }
    }

    /// The one true pop/close of the presented route. Only the anniversary
    /// screen becoming visible again may deliver this, and only with the
    /// original lease: a late callback from route A (same owner, possibly
    /// even the same target) cannot clear or consume route B's return.
    /// Succeeds exactly once; replaying the same event is rejected.
    @discardableResult
    public mutating func completeReturn(presentation: RoamAnniversaryRoutePresentation?,
                                        owner currentOwner: RoamExperienceIdentity?) -> Bool {
        guard mayRemainOpen(presentation, owner: currentOwner) else { return false }
        openedPresentation = nil
        generation += 1
        return true
    }
}

/// Confirmed anniversary list and its in-flight read lease. A route return
/// revalidates the previously loaded depth atomically, rather than replacing
/// a paginated list with page one or showing half of a failed refresh.
public struct RoamAnniversaryListState {
    public struct Day: Equatable {
        public let month: Int
        public let day: Int
        public init?(month: Int, day: Int) {
            guard RoamShanghaiCalendar.isValidMonthDay(month: month, day: day) else { return nil }
            self.month = month; self.day = day
        }
        /// The picker displays a real Shanghai calendar day; February 29
        /// uses the latest leap year, never Calendar's March 1 normalization.
        public func pickerDate(referenceYear: Int) -> Date? {
            guard (2000...9999).contains(referenceYear) else { return nil }
            var year = referenceYear
            if month == 2 && day == 29 {
                while !(year % 4 == 0 && year % 100 != 0 || year % 400 == 0) { year -= 1 }
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: RoamShanghaiCalendar.offsetSeconds)!
            return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        }
    }
    public enum Intent: Equatable { case refresh, more }
    public struct Request: Equatable {
        public let owner: RoamExperienceIdentity
        public let generation: UInt64
        public let intent: Intent
        public let query: RoamAnniversaryQuery
        public let boundary: RoamAnniversaryMemory?
        public let pageCount: Int
    }
    public private(set) var owner: RoamExperienceIdentity?
    public private(set) var selected: Day?
    public private(set) var page: RoamAnniversaryPage?
    public private(set) var rows: [RoamAnniversaryMemory] = []
    public private(set) var loadedPageCount = 0
    public private(set) var error: Error?
    public private(set) var retryIntent: Intent = .refresh
    public private(set) var needsRefresh = true
    public private(set) var generation: UInt64 = 0
    private var activeRequest: Request?
    private var consumedCursors: Set<String> = []
    public var isLoading: Bool { activeRequest != nil }
    public var displayedDay: Day? { selected ?? page.flatMap { Day(month: $0.month, day: $0.day) } }

    public init() {}

    public mutating func bind(to newOwner: RoamExperienceIdentity?) {
        guard newOwner != owner else { return }
        suspend(); owner = newOwner; selected = nil; page = nil
        rows = []; loadedPageCount = 0; consumedCursors = []; error = nil; retryIntent = .refresh
        needsRefresh = true
    }

    /// Selecting a new month/day retires all old requests and pagination.
    @discardableResult
    public mutating func select(_ day: Day) -> Bool {
        guard day != displayedDay else { return false }
        suspend(); selected = day; page = nil; rows = []; loadedPageCount = 0
        consumedCursors = []; error = nil; retryIntent = .refresh
        needsRefresh = true
        return true
    }

    /// Covering or leaving the list invalidates callbacks, not confirmed rows.
    public mutating func suspend() {
        generation += 1; activeRequest = nil
    }

    /// Resume/route-pop can arrive while the list is still covered. Retain
    /// the refresh until a visible, foreground, authorized read can begin.
    public mutating func requestRefresh() { needsRefresh = true }

    /// A revoked read grant must hide its private records immediately. Keep
    /// the confirmed day as the retry intent, not the now-possibly-new today.
    public mutating func revokeAccess(_ failure: Error) {
        selected = displayedDay
        suspend()
        rows = []; page = nil; loadedPageCount = 0; consumedCursors = []
        error = failure; retryIntent = .refresh; needsRefresh = true
    }

    public mutating func begin(_ intent: Intent, owner currentOwner: RoamExperienceIdentity?) -> Request? {
        guard activeRequest == nil, let currentOwner, currentOwner == owner else { return nil }
        let cursor: String?
        if intent == .more {
            guard let page, page.hasMore, let next = page.nextCursor else { return nil }
            cursor = next
        } else { cursor = nil }
        generation += 1
        // "Today" is server-resolved only on initial entry. Later reads keep
        // that confirmed Shanghai day, even if midnight passes in a detail.
        let day = displayedDay
        let request = Request(owner: currentOwner, generation: generation, intent: intent,
            query: RoamAnniversaryQuery(month: day?.month, day: day?.day, limit: 20, cursor: cursor,
                referenceYear: intent == .more ? page?.referenceYear : nil),
            boundary: intent == .more ? rows.last : nil,
            pageCount: intent == .more ? 1 : max(1, loadedPageCount))
        activeRequest = request; error = nil; retryIntent = intent
        if intent == .refresh { needsRefresh = false }
        return request
    }

    public func isCurrent(_ request: Request, owner currentOwner: RoamExperienceIdentity?) -> Bool {
        currentOwner == owner && currentOwner == request.owner && activeRequest == request
    }

    /// All pages are committed together. A failed/expired continuation cannot
    /// splice another date/year, duplicate rows, or silently replace the list.
    @discardableResult
    public mutating func accept(_ pages: [RoamAnniversaryPage], for request: Request,
                                owner currentOwner: RoamExperienceIdentity?) throws -> Bool {
        guard isCurrent(request, owner: currentOwner) else { return false }
        guard let first = pages.first, let last = pages.last,
              pages.count <= request.pageCount,
              pages.count == request.pageCount || !last.hasMore else { throw APIError.malformedResponse }
        var result = request.intent == .more ? rows : []
        var seenIDs = Set(result.map(\.id))
        var cursors = request.intent == .more ? consumedCursors : []
        var query = request.query
        var previous = request.boundary
        for (index, value) in pages.enumerated() {
            guard value.month == first.month, value.day == first.day, value.referenceYear == first.referenceYear,
                  RoamShanghaiCalendar.isValidMonthDay(month: value.month, day: value.day),
                  value.items.count <= query.limit,
                  query.month == nil || query.month == value.month,
                  query.day == nil || query.day == value.day,
                  query.referenceYear == nil || query.referenceYear == value.referenceYear else { throw APIError.malformedResponse }
            if let cursor = query.cursor {
                guard cursors.insert(cursor).inserted else { throw APIError.malformedResponse }
            }
            if value.hasMore {
                guard value.items.count == query.limit, let next = value.nextCursor,
                      RoamAnniversaryPage.isValidCursor(next), !cursors.contains(next) else { throw APIError.malformedResponse }
            } else {
                guard value.nextCursor == nil, index == pages.count - 1 else { throw APIError.malformedResponse }
            }
            for item in value.items {
                guard seenIDs.insert(item.id).inserted else { throw APIError.malformedResponse }
                if let previous {
                    let ordered = previous.completedAt > item.completedAt ||
                        (previous.completedAt == item.completedAt &&
                         (previous.id.count > item.id.count || (previous.id.count == item.id.count && previous.id > item.id)))
                    guard ordered else { throw APIError.malformedResponse }
                }
                result.append(item); previous = item
            }
            query = RoamAnniversaryQuery(month: first.month, day: first.day, limit: request.query.limit,
                cursor: value.nextCursor, referenceYear: first.referenceYear)
        }
        rows = result; page = last; consumedCursors = cursors
        loadedPageCount = request.intent == .more ? loadedPageCount + pages.count : pages.count
        activeRequest = nil; error = nil
        return true
    }

    public mutating func fail(_ failure: Error, for request: Request,
                              owner currentOwner: RoamExperienceIdentity?, isConfigured: Bool = true) {
        guard isCurrent(request, owner: currentOwner) else { return }
        // Session readers intentionally turn revoked in-flight reads into
        // cancellation. A current grant check must precede that benign path.
        guard isConfigured else { revokeAccess(APIError.notConfigured); return }
        activeRequest = nil
        if failure is CancellationError { return }
        error = failure
        if let api = failure as? APIError,
           api == .unauthorized || api == .notConfigured || api == .httpStatus(403) || api == .businessCode(403) {
            revokeAccess(failure)
            return
        }
        // A cursor expires when Shanghai's reference year changes. Keep the
        // confirmed list, but make Retry rebuild that same day from page one.
        if let api = failure as? APIError, api == .httpStatus(400) || api == .businessCode(400) || api == .malformedResponse {
            retryIntent = .refresh
        }
    }
}
