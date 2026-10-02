import Foundation
import Observation

/// Server calendar policy is authoritative. HH:mm values and the phone timezone
/// are never used to calculate the next opening locally.
public struct NativeTimeWindow: Equatable {
    public let timeZone: String
    public let serverNow: Date
    public let openNow: Bool
    public let nextOpenAt: Date
    public let nextCloseAt: Date
    public let windowVersion: String
    public init(_ raw: PlayWireValue) throws {
        guard raw["enabled"].bool == true, raw["notificationProvider"].text == "LOCAL_ONLY",
              let zone = raw["timeZone"].text, TimeZone(identifier: zone) != nil,
              let server = raw["serverNow"].integer, server > 0,
              let opening = raw["nextOpenAt"].integer, opening > server,
              let closing = raw["nextCloseAt"].integer, closing > server,
              let open = raw["openNow"].bool,
              let version = raw["windowVersion"].text, !version.isEmpty, version.count <= 256 else { throw NativePlatformIssue.invalidContract }
        guard open || closing > opening else { throw NativePlatformIssue.invalidContract }
        timeZone = zone; serverNow = Date(timeIntervalSince1970: Double(server) / 1000)
        nextOpenAt = Date(timeIntervalSince1970: Double(opening) / 1000)
        nextCloseAt = Date(timeIntervalSince1970: Double(closing) / 1000)
        openNow = open; windowVersion = version
    }
    public func reminder(identifier: String, owner: String, now: Date) throws -> NativeLocalReminder {
        guard nextOpenAt.timeIntervalSince(now) >= 1, abs(now.timeIntervalSince(serverNow)) <= 120 else { throw NativePlatformIssue.expired }
        return NativeLocalReminder(identifier: identifier, owner: owner, windowRevision: windowVersion, fireAt: Date(timeIntervalSince1970: floor(nextOpenAt.timeIntervalSince1970)), timeZone: timeZone)
    }
    public func matches(_ reminder: NativeLocalReminder) -> Bool {
        reminder.windowRevision == windowVersion && reminder.timeZone == timeZone && abs(reminder.fireAt.timeIntervalSince(nextOpenAt)) < 1
    }
}

/// Consent belongs to exactly the reviewed server instant + window revision.
/// A changed window cancels the old request and requires a new tap to replace it.
@available(macOS 14.0, *)
@MainActor @Observable public final class NativeLocalReminderCoordinator {
    public private(set) var window: NativeTimeWindow?
    public private(set) var scheduled: NativeLocalReminder?
    public private(set) var issue: NativePlatformIssue?
    public private(set) var phase = "idle"
    public let identifier: String
    public let owner: String
    private let provider: any NativeLocalReminderProviding
    private let current: () -> Bool
    private let now: () -> Date
    private var generation = UUID()
    public init(identifier: String, owner: String, provider: any NativeLocalReminderProviding,
                current: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.identifier = identifier; self.owner = owner; self.provider = provider; self.current = current; self.now = now
    }
    public func refresh(_ next: NativeTimeWindow?) async {
        guard current() else { invalidate(); return }
        generation = UUID(); let token = generation
        let previous = window; window = next
        let permission = await provider.permission()
        guard current(), token == generation else { return }
        let pending = await provider.pending().first { $0.identifier == identifier && $0.owner == owner }
        guard current(), token == generation else { return }
        guard permission != .denied && permission != .restricted else {
            provider.cancel(identifier: identifier); scheduled = nil; issue = .denied; phase = "denied"; return
        }
        guard let next, next.nextOpenAt > now() else {
            provider.cancel(identifier: identifier); scheduled = nil; issue = .expired; phase = "expired"; return
        }
        if let pending, !next.matches(pending) {
            provider.cancel(identifier: identifier); scheduled = nil; issue = .windowChanged; phase = "changed"; return
        }
        if let previous, previous != next, previous.windowVersion != next.windowVersion || previous.nextOpenAt != next.nextOpenAt {
            provider.cancel(identifier: identifier); scheduled = nil; issue = .windowChanged; phase = "changed"; return
        }
        scheduled = pending; issue = nil; phase = pending == nil ? "ready" : "scheduled"
    }
    public func enable(reviewed: NativeTimeWindow, title: String, body: String) async {
        guard current(), phase != "scheduling", window == reviewed else { issue = .windowChanged; return }
        let token = generation; phase = "scheduling"; issue = nil
        do {
            let request = try reviewed.reminder(identifier: identifier, owner: owner, now: now())
            guard try await provider.requestPermission() == .allowed else { throw NativePlatformIssue.denied }
            guard current(), token == generation, window == reviewed else { throw NativePlatformIssue.staleSession }
            guard request.fireAt > now() else { throw NativePlatformIssue.expired }
            try await provider.replace(request, title: title, body: body)
            guard current(), token == generation, window == reviewed else { provider.cancel(identifier: identifier); throw NativePlatformIssue.staleSession }
            guard await provider.permission() == .allowed else { provider.cancel(identifier: identifier); throw NativePlatformIssue.denied }
            let readback = await provider.pending().first { $0 == request }
            guard current(), token == generation else { provider.cancel(identifier: identifier); return }
            guard let readback else { provider.cancel(identifier: identifier); throw NativePlatformIssue.notificationMissing }
            scheduled = readback; phase = "scheduled"
        } catch {
            guard token == generation else { return }
            scheduled = nil; issue = error as? NativePlatformIssue ?? .notificationMissing; phase = "failed"
        }
    }
    public func cancel() {
        generation = UUID(); provider.cancel(identifier: identifier); scheduled = nil; issue = nil; phase = "ready"
    }
    public func invalidate() { cancel(); window = nil; issue = .staleSession; phase = "stale" }
    public func clockChanged() { cancel(); window = nil; issue = .clockChanged; phase = "stale" }
}
