import Foundation
import Observation

/// An original actor-owned request snapshot. It grants no present team qualification or write permission.
public enum CityNeutralTaskResultRecovery {
    static func validate(_ task: CityNeutralTask, requestID: String) throws {
        guard UUID(uuidString: requestID)?.uuidString == requestID,
              task.definition.valid, ["ACTIVE", "PASSED", "EXHAUSTED"].contains(task.status),
              (0...task.definition.maxAttempts).contains(task.attempts),
              task.version == Int64(task.attempts) + 1,
              let instanceID = task.instanceId, serverID(instanceID),
              let acceptedAt = task.acceptedAt, date(acceptedAt) != nil else { throw CityNeutralTaskError.malformed }
        if task.status == "ACTIVE" {
            guard task.attempts < task.definition.maxAttempts, task.result == nil else { throw CityNeutralTaskError.malformed }
        } else {
            guard let result = task.result, serverID(result.resultId), result.requestId == requestID,
                  result.outcome == task.status, result.attemptNumber == task.attempts, task.attempts > 0,
                  result.verifier == "NATIVE_OBJECTIVE_QA_PICK_V1", date(result.createdAt) != nil,
                  task.status != "EXHAUSTED" || task.attempts == task.definition.maxAttempts else { throw CityNeutralTaskError.malformed }
        }
    }
    private static func serverID(_ id: String) -> Bool { UUID(uuidString: id)?.uuidString.lowercased() == id }
    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// Retained independently of the task screen during navigation. Only the captured original GET is possible.
@available(macOS 14.0, *) @MainActor @Observable public final class CityNeutralTaskResultRecoveryController {
    public let requestID: UUID
    public private(set) var task: CityNeutralTask?
    public private(set) var busy = false
    public private(set) var messageKey = "cityNeutralResult.original"
    private let service: CityNeutralTaskService
    private let original: CityNeutralTask
    private let unauthorized: () -> Void
    private let accessWithdrawn: () -> Void
    private var generation = 0
    public init?(service: CityNeutralTaskService, receipt: CityNeutralTaskReceipt, unauthorized: @escaping () -> Void = {}, accessWithdrawn: @escaping () -> Void = {}) {
        guard service.transport.isCurrent(), receipt.succeeded, let id = UUID(uuidString: receipt.requestId),
              let task = receipt.task, (try? CityNeutralTaskResultRecovery.validate(task, requestID: receipt.requestId)) != nil else { return nil }
        self.service = service; requestID = id; self.task = task; original = task; self.unauthorized = unauthorized; self.accessWithdrawn = accessWithdrawn
    }
    public var current: Bool { service.transport.isCurrent() }
    public func invalidate() { generation += 1; task = nil; busy = false; messageKey = "cityNeutralResult.unavailable" }
    public func load() async {
        guard !busy else { return }
        guard current else { withdraw(); return }
        generation += 1; let issued = generation; busy = true
        defer { if issued == generation { busy = false } }
        do {
            let receipt = try await service.receipt(requestID)
            guard issued == generation, !Task.isCancelled else { return }
            guard current else { withdraw(); return }
            // Original receipts are immutable. A newer state/result is not a replacement for this request.
            guard receipt.succeeded, receipt.task == original else { throw CityNeutralTaskError.malformed }
            task = original; messageKey = "cityNeutralResult.original"
        } catch {
            guard issued == generation else { return }
            if !current { withdraw(); return }
            if error as? APIError == .unauthorized { withdraw(); unauthorized(); return }
            if case CityNeutralTaskError.server(403, _) = error { withdraw(); return }
            if Task.isCancelled { return }
            messageKey = task == nil ? "cityNeutralResult.unavailable" : "cityNeutralResult.refreshFailed"
        }
    }
    private func withdraw() { invalidate(); accessWithdrawn() }
}
