import Foundation

/// Ephemeral manual sample. It is neither Codable nor retained by the restore journal.
public struct NativeHomeReturnFix: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let latitude, longitude, accuracyMeters: Double
    public let capturedAt: Date
    public init(latitude: Double, longitude: Double, accuracyMeters: Double, capturedAt: Date) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude),
              accuracyMeters.isFinite, accuracyMeters >= 0, capturedAt.timeIntervalSince1970.isFinite,
              capturedAt.timeIntervalSince1970 > 0, capturedAt.timeIntervalSince1970 < 9_007_199_254_740_991 / 1000 else { throw NativeHomeReturnFailure.invalid }
        self.latitude = try Self.wireNumber(latitude, rounding: .plain).doubleValue
        self.longitude = try Self.wireNumber(longitude, rounding: .plain).doubleValue
        let conservativeAccuracy = try Self.wireNumber(accuracyMeters, rounding: .up).doubleValue
        guard conservativeAccuracy >= accuracyMeters else { throw NativeHomeReturnFailure.invalid }
        self.accuracyMeters = conservativeAccuracy
        self.capturedAt = capturedAt
    }
    /// Decimal wire scale is bounded. Accuracy rounds upward so it can never become more precise.
    static func wireNumber(_ value: Double, rounding: Decimal.RoundingMode) throws -> NSDecimalNumber {
        guard value.isFinite, var decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")),
              !decimal.isNaN else { throw NativeHomeReturnFailure.invalid }
        var rounded = Decimal(); NSDecimalRound(&rounded, &decimal, 6, rounding)
        guard !rounded.isNaN else { throw NativeHomeReturnFailure.invalid }
        return NSDecimalNumber(decimal: rounded)
    }
    public var description: String { "NativeHomeReturnFix[redacted]" }
    public var debugDescription: String { description }
}

public struct NativeHomeReturnRun: Decodable, Equatable, Identifiable, Sendable {
    public let runId, activityId, topicId, playInstanceId, resourceType: String
    public let current, maximum, version: Int64
    public var id: String { runId }
    public var scope: NativeHomeResourceScope { .run(runId: runId, resourceType: resourceType) }
    public func validate() throws {
        try scope.validateNative()
        guard (activityId == "0" || NativeHomeResourceScope.decimalID(activityId)), NativeHomeResourceScope.decimalID(topicId),
              !playInstanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, current > 0, maximum > 0, current <= maximum,
              ReformWire.version(version) else { throw NativeHomeReturnFailure.invalid }
    }
}
public struct NativeHomeReturnRuns: Decodable, Equatable, Sendable {
    public let runs: [NativeHomeReturnRun]
    public let truncated: Bool
    public let nextBeforeRunId: String?
    public func validate() throws {
        guard runs.count <= 50, Set(runs.map(\.runId)).count == runs.count else { throw NativeHomeReturnFailure.invalid }
        guard truncated == (nextBeforeRunId != nil), nextBeforeRunId.map(NativeHomeResourceScope.decimalID) ?? true else { throw NativeHomeReturnFailure.invalid }
        try runs.forEach { try $0.validate() }
        let ids = runs.compactMap { Int64($0.runId) }
        guard zip(ids, ids.dropFirst()).allSatisfy({ pair in pair.0 > pair.1 }),
              nextBeforeRunId.flatMap(Int64.init).map({ cursor in ids.allSatisfy { $0 >= cursor } }) ?? true else { throw NativeHomeReturnFailure.invalid }
    }
}

/// Confidential, atomic owner+realm journal. No coordinates, auto replay, defaults or plaintext fallback.
@MainActor public protocol NativeHomeReturnSecureJournaling: AnyObject {
    var scope: PrivateHomeJournalScope { get }
    func read() async throws -> NativeHomeRestoreRequest?
    func save(_ request: NativeHomeRestoreRequest) async throws
    func clear(matching request: NativeHomeRestoreRequest) async throws
}

@MainActor public protocol NativeHomeReturnRunServing: NativeHomeReturnServing {
    func runs(beforeRunId: String?) async throws -> NativeHomeReturnRuns
}
