import Foundation

/// Installation-local and server-bound identity. This is not a device attestation.
public enum NativePlatformIssue: String, Error, Equatable {
    case disabled, unsupported, denied, restricted, purposeMissing, staleSession
    case interrupted, clockChanged, reset, expired, invalidContract, unknownResult
    case notificationMissing, windowChanged, openingRequired, network
}
public enum NativePlatformPermission: String { case notDetermined, allowed, denied, restricted, unsupported }
public struct NativePedometerReading: Equatable {
    public let start: Date
    public let end: Date
    public let steps: Int
    public init(start: Date, end: Date, steps: Int) throws {
        guard start <= end, steps >= 0 else { throw NativePlatformIssue.reset }
        self.start = start; self.end = end; self.steps = steps
    }
}
@MainActor public protocol NativePedometerProviding: AnyObject {
    var permission: NativePlatformPermission { get }
    func read(from: Date, to: Date) async throws -> NativePedometerReading
    func cancel()
}

/// Wall-clock changes are checked against monotonic uptime before any sample is
/// submitted. A fresh server challenge is required after reboot/background/reset.
public struct NativePlatformClockAnchor: Equatable {
    public let wall: Date
    public let uptime: TimeInterval
    public init(wall: Date, uptime: TimeInterval) { self.wall = wall; self.uptime = uptime }
    public func validate(wall: Date, uptime: TimeInterval, tolerance: TimeInterval = 5) throws {
        guard uptime.isFinite, self.uptime.isFinite, uptime >= self.uptime else { throw NativePlatformIssue.reset }
        guard abs(wall.timeIntervalSince(self.wall) - (uptime - self.uptime)) <= tolerance else { throw NativePlatformIssue.clockChanged }
    }
}

/// OS-local readback only. There is deliberately no WeChat subscribed flag,
/// push token, claim, reward, or completion field.
public struct NativeLocalReminder: Equatable {
    public let identifier: String
    public let owner: String
    public let windowRevision: String
    public let fireAt: Date
    public let timeZone: String
    public init(identifier: String, owner: String, windowRevision: String, fireAt: Date, timeZone: String) {
        self.identifier = identifier; self.owner = owner; self.windowRevision = windowRevision
        self.fireAt = fireAt; self.timeZone = timeZone
    }
}
@MainActor public protocol NativeLocalReminderProviding: AnyObject {
    func permission() async -> NativePlatformPermission
    func requestPermission() async throws -> NativePlatformPermission
    func pending() async -> [NativeLocalReminder]
    func replace(_ reminder: NativeLocalReminder, title: String, body: String) async throws
    func cancel(identifier: String)
    func cancelAllOwned(owner: String)
}
