import Foundation

public struct NativeStepChallenge: Equatable {
    public static let provider = "IOS_CMPEDOMETER_V1"
    public let challengeID: String
    public let accountID: Int
    public let sessionID: Int
    public let sessionVersion: Int
    public let deviceKeyID: String
    public let attemptStartedAt: Int
    public let issuedAt: Int
    public let expiresAt: Int
    public let dayKey: String
    public let timeZone: String
    public let dayStartAt: Int
    public let dayEndAt: Int
    public init(_ raw: PlayWireValue, owner: PlayExperienceSession, sessionID: Int, version: Int, deviceKeyID: String) throws {
        guard raw["provider"].text == Self.provider,
              raw["accountId"].integer == owner.accountID,
              raw["sessionId"].integer == sessionID, raw["sessionVersion"].integer == version,
              raw["deviceKeyId"].text == deviceKeyID,
              let id = raw["challengeId"].text, id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let attempt = raw["attemptStartedAt"].integer, attempt > 0,
              let issued = raw["issuedAt"].integer, issued > 0,
              let expires = raw["expiresAt"].integer, expires > issued, expires - issued <= 120_000,
              let start = raw["dayStartAt"].integer, start > 0,
              let end = raw["dayEndAt"].integer, end > start, end - start <= 26 * 3_600_000,
              issued >= start, issued < end,
              let zone = raw["timeZone"].text, let timezone = TimeZone(identifier: zone),
              let day = raw["dayKey"].text, day.count == 10 else { throw NativePlatformIssue.invalidContract }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timezone
        let date = Date(timeIntervalSince1970: Double(issued) / 1000)
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = timezone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.string(from: date) == day,
              abs(calendar.startOfDay(for: date).timeIntervalSince1970 * 1000 - Double(start)) < 1,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)),
              abs(tomorrow.timeIntervalSince1970 * 1000 - Double(end)) < 1 else { throw NativePlatformIssue.invalidContract }
        challengeID = id; accountID = owner.accountID; self.sessionID = sessionID; sessionVersion = version
        self.deviceKeyID = deviceKeyID; attemptStartedAt = attempt; issuedAt = issued; expiresAt = expires
        dayKey = day; timeZone = zone; dayStartAt = start; dayEndAt = end
    }
    public func validate(now: Date) throws {
        let ms = now.timeIntervalSince1970 * 1000
        guard ms >= Double(issuedAt - 5_000), ms < Double(expiresAt), ms < Double(dayEndAt) else { throw NativePlatformIssue.expired }
    }
    public func validate(_ reading: NativePedometerReading, now: Date) throws {
        try validate(now: now)
        let start = Int((reading.start.timeIntervalSince1970 * 1000).rounded())
        let end = Int((reading.end.timeIntervalSince1970 * 1000).rounded())
        let ms = now.timeIntervalSince1970 * 1000
        guard start == dayStartAt, end > start, end >= issuedAt - 5_000, end < dayEndAt,
              Double(end) <= ms + 5_000, ms - Double(end) <= 120_000,
              reading.steps <= 100_000 else { throw NativePlatformIssue.invalidContract }
    }
    public func unsignedPayload(_ reading: NativePedometerReading) -> [String: PlayWireValue] {
        ["provider": .string(Self.provider), "deviceKeyId": .string(deviceKeyID), "challengeId": .string(challengeID),
         "dayKey": .string(dayKey), "sampleStartAt": .int(dayStartAt),
         "sampleEndAt": .int(Int((reading.end.timeIntervalSince1970 * 1000).rounded())), "cumulativeSteps": .int(reading.steps)]
    }
}
@MainActor public protocol NativeStepAssertionProviding: AnyObject {
    var deviceKeyID: String { get }
    var supported: Bool { get }
    func assertion(clientData: Data) async throws -> String
    func cancel()
}
