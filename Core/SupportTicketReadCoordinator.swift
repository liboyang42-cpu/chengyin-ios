import Foundation
import Observation

public struct SupportTicketReadVisit: Equatable { fileprivate let id: UUID }
public struct SupportTicketReadIntent { fileprivate let owner: SupportTicketReadVisit; fileprivate let generation: UInt64 }
/// One ordinary owner history/detail presentation. No local journal, request UUID or writer is present.
@MainActor @Observable public final class SupportTicketReadCoordinator {
    public let reader: SupportTicketReadReader
    private var owner: SupportTicketReadVisit?
    private var generation: UInt64 = 0
    private var active = false
    private var rows: [SupportTicketReadTicket] = []
    private var selected: SupportTicketReadTicket?
    private var texts: [SupportTicketReadMessage] = []
    private var history: [SupportTicketReadEvent] = []
    private var listCursor: Int64 = 0, messageCursor: Int64 = 0, eventCursor: Int64 = 0
    private var listMore = false, messageMore = false, eventMore = false
    private var didLoad = false, eventsLoaded = false, running = false
    private var problem: SupportTicketReadFailure?
    public init(reader: SupportTicketReadReader) { self.reader = reader }
    public var isCurrent: Bool { active && reader.isCurrent }
    public var tickets: [SupportTicketReadTicket] { isCurrent ? rows : [] }
    public var ticket: SupportTicketReadTicket? { isCurrent ? selected : nil }
    public var messages: [SupportTicketReadMessage] { isCurrent ? texts : [] }
    public var events: [SupportTicketReadEvent] { isCurrent ? history : [] }
    public var hasMoreTickets: Bool { isCurrent && listMore }
    public var hasMoreMessages: Bool { isCurrent && messageMore }
    public var hasMoreEvents: Bool { isCurrent && eventMore }
    public var loaded: Bool { isCurrent && didLoad }
    public var timelineLoaded: Bool { isCurrent && eventsLoaded }
    public var busy: Bool { isCurrent && running }
    public var failure: SupportTicketReadFailure? { isCurrent ? problem : nil }
    public func begin() -> SupportTicketReadVisit { retire(); let value = SupportTicketReadVisit(id: UUID()); owner = value; active = true; return value }
    public func capture(_ visit: SupportTicketReadVisit) -> SupportTicketReadIntent? {
        guard isCurrent, owner == visit, !Task.isCancelled else { return nil }; return .init(owner: visit, generation: generation)
    }
    public func accepts(_ intent: SupportTicketReadIntent) -> Bool { isCurrent && owner == intent.owner && generation == intent.generation && !Task.isCancelled }
    public func end(_ visit: SupportTicketReadVisit) { guard owner == visit else { return }; retire() }
    public func retire() { generation &+= 1; owner = nil; active = false; clear(); running = false; problem = nil }
    private func clear() { rows = []; selected = nil; texts = []; history = []; listCursor = 0; messageCursor = 0; eventCursor = 0; listMore = false; messageMore = false; eventMore = false; didLoad = false; eventsLoaded = false }
    private func start(_ intent: SupportTicketReadIntent) -> UInt64? {
        guard accepts(intent), !running else { return nil }; generation &+= 1; running = true; problem = nil; return generation
    }
    private func current(_ stamp: UInt64) -> Bool { isCurrent && stamp == generation && !Task.isCancelled }
    private func failed(_ error: Error, stamp: UInt64) {
        guard current(stamp) else { return }; clear(); problem = error as? SupportTicketReadFailure ?? .unavailable
    }
    public func loadHistory(_ intent: SupportTicketReadIntent, next: Bool = false) async {
        guard !next || (selected == nil && listMore), let stamp = start(intent) else { return }
        let before = next ? listCursor : 0
        if !next { clear() }
        defer { if generation == stamp { running = false } }
        do {
            let page = try await reader.history(before: before); guard current(stamp) else { return }
            guard !next || Set(rows.map(\.id)).isDisjoint(with: page.list.map(\.id)), rows.count + page.list.count <= 10_000 else { throw SupportTicketReadFailure.malformed }
            rows += page.list; listCursor = page.next_cursor; listMore = page.has_more; didLoad = true
        } catch { failed(error, stamp: stamp) }
    }
    public func open(_ row: SupportTicketReadTicket, intent: SupportTicketReadIntent) async {
        guard accepts(intent), rows.contains(row) else { return }
        await loadDetail(number: row.ticket_no, intent: intent, next: false)
    }
    /// Resume only the same presentation's retained ticket number after its private text was cleared.
    public func resumeDetail(number: String, intent: SupportTicketReadIntent) async {
        guard selected == nil, rows.isEmpty, SupportTicketReadRoute.validNumber(number) else { return }
        await loadDetail(number: number, intent: intent, next: false)
    }
    public func reloadDetail(_ intent: SupportTicketReadIntent, next: Bool = false) async {
        guard let row = selected, !next || messageMore else { return }
        await loadDetail(number: row.ticket_no, intent: intent, next: next)
    }
    private func loadDetail(number: String, intent: SupportTicketReadIntent, next: Bool) async {
        guard let stamp = start(intent) else { return }
        let after = next ? messageCursor : 0, priorVersion = next ? selected?.version : nil
        if !next { selected = nil; texts = []; history = []; eventsLoaded = false; eventMore = false; messageMore = false; didLoad = false }
        defer { if generation == stamp { running = false } }
        do {
            let page = try await reader.detail(number: number, after: after); guard current(stamp) else { return }
            guard !next || (selected?.ticket_no == number && (priorVersion.map { page.ticket.version >= $0 } ?? false)), texts.count + page.messages.count <= 10_000 else { throw SupportTicketReadFailure.malformed }
            selected = page.ticket; texts += page.messages; messageCursor = page.next_cursor; messageMore = page.has_more; didLoad = true
        } catch { failed(error, stamp: stamp) }
    }
    public func loadTimeline(_ intent: SupportTicketReadIntent, next: Bool = false) async {
        guard let no = selected?.ticket_no, !next || eventMore, let stamp = start(intent) else { return }
        let before = next ? eventCursor : 0
        if !next { history = []; eventsLoaded = false; eventMore = false }
        defer { if generation == stamp { running = false } }
        do {
            let page = try await reader.timeline(number: no, before: before); guard current(stamp), selected?.ticket_no == no else { return }
            guard history.count + page.events.count <= 10_000 else { throw SupportTicketReadFailure.oversized }
            history += page.events; eventCursor = page.next_before; eventMore = page.has_more; eventsLoaded = true
        } catch { failed(error, stamp: stamp) }
    }
}
