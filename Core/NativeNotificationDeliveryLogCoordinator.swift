import Foundation
import Observation

public enum NativeNotificationDeliveryLogState: Equatable { case idle, loading, ready, unavailable, accessClosed }
/// One original authenticated page at a time. No persisted private log cache, event counter or send method.
@MainActor @Observable public final class NativeNotificationDeliveryLogCoordinator {
    private let client: any NativeChannelNotificationAccess
    private var active = false
    // A retired view owner cannot be revived by an already queued activation.
    // Reentry must acquire a fresh original reader from the existing factory.
    private var retired = false
    private var generation: UInt64 = 0
    private var busy = false
    private var storedPage: NativeNotificationDeliveryLogPage?
    private var query: NativeNotificationDeliveryLogQuery?
    public private(set) var state: NativeNotificationDeliveryLogState = .idle
    public init(client: any NativeChannelNotificationAccess) { self.client = client }
    public var isCurrent: Bool { active && !retired && client.isCurrent && client.allows(.deliveryLog, scope: nil) }
    public var page: NativeNotificationDeliveryLogPage? { isCurrent ? storedPage : nil }
    public var isBusy: Bool { busy }
    public var canRead: Bool { isCurrent && !busy }
    public var canReadNext: Bool { canRead && page?.hasMore == true && page?.nextCursor != nil }
    public var currentEvent: String? { isCurrent ? query?.event : nil }
    public func deactivate() {
        client.retireOperations(); retired = true; active = false; generation &+= 1; busy = false
        storedPage = nil; query = nil; state = .accessClosed
    }
    public func activate() async {
        guard !Task.isCancelled, !retired, !active else { return }
        guard client.isCurrent, client.allows(.deliveryLog, scope: nil) else { deactivate(); return }
        active = true; generation &+= 1
        await refresh(event: nil)
    }
    public func refresh(event: String?) async {
        guard !Task.isCancelled, canRead else { return }
        do { await read(try .init(event: event)) }
        catch { storedPage = nil; state = .unavailable }
    }
    public func readNext() async {
        guard !Task.isCancelled, canReadNext, let page, let query, let cursor = page.nextCursor else { return }
        do { await read(try .init(limit: query.limit, event: query.event, cursor: cursor)) }
        catch { storedPage = nil; state = .unavailable }
    }
    public func rereadPage() async {
        guard !Task.isCancelled, canRead, let query else { return }
        await read(query) // safe original GET only; never sends/retries a notification
    }
    private func read(_ selected: NativeNotificationDeliveryLogQuery) async {
        guard !Task.isCancelled, canRead else { return }
        generation &+= 1; let ticket = generation
        busy = true; state = .loading; storedPage = nil; query = selected
        defer { if ticket == generation { busy = false } }
        do {
            let result = try await client.deliveryLog(query: selected)
            guard current(ticket) else { return }
            try result.validate(account: String(client.context.session.accountID), query: selected)
            // Replace, do not retain previous pages whose message/device visibility was not revalidated.
            storedPage = result; state = .ready
        } catch {
            guard current(ticket) else { return }
            storedPage = nil
            if let failure = error as? NativeChannelNotificationError,
               failure == .accessClosed || failure.serverDetails.map({ $0.httpStatus == 401 || $0.httpStatus == 403 || $0.code == 401 || $0.code == 403 }) == true {
                deactivate()
            } else { state = .unavailable }
        }
    }
    private func current(_ ticket: UInt64) -> Bool {
        guard ticket == generation else { return false }
        guard isCurrent else { deactivate(); return false }
        guard !Task.isCancelled else { storedPage = nil; state = .unavailable; return false }
        return true
    }
}
