import Foundation
import Observation

@available(macOS 14.0, *) @MainActor @Observable public final class CityNeutralTaskController {
    public struct Confirmation: Identifiable { public let id: UUID; public let command: CityNeutralTaskCommand; public let binding: CityNeutralTaskBinding; public let task: CityNeutralTask }
    public private(set) var snapshot: CityNeutralTaskSnapshot?
    public private(set) var confirmation: Confirmation?
    public private(set) var pendingRequestID: UUID?
    public private(set) var receipt: CityNeutralTaskReceipt?
    public private(set) var busy = false
    public private(set) var messageKey = "cityNeutral.status.initial"
    private let service: CityNeutralTaskService?
    private let journal: (any OperationPendingJournal)?
    private let unauthorized: () -> Void
    private var generation = 0
    public init(service: CityNeutralTaskService?, journal: (any OperationPendingJournal)?, unauthorized: @escaping () -> Void = {}) { self.service = service; self.journal = journal; self.unauthorized = unauthorized }
    public var current: Bool { service?.transport.isCurrent() == true }
    public var canWrite: Bool { current && service?.approval.allowsWrite == true && snapshot?.writeApproved == true && !busy && pendingRequestID == nil && journal != nil }
    private var owner: String? { service.map { "city-neutral:\($0.approval.context.session.namespace):\($0.approval.context.baseURL.absoluteString):\($0.approval.context.session.accountID)" } }
    private var target: String? { service.map { "\($0.board.regionId):\($0.board.boardId):\($0.board.seasonId)" } }
    public func invalidate() { generation += 1; snapshot = nil; confirmation = nil; receipt = nil; pendingRequestID = nil; busy = false; messageKey = "cityNeutral.status.contextChanged" }
    public func cancelConfirmation() { confirmation = nil }
    /// Leaving for the read-only original result must retire live task work, not erase its verified receipt.
    public func suspendForResult() {
        guard current else { invalidate(); return }
        generation += 1; snapshot = nil; confirmation = nil; busy = false
    }
    public func makeResultRecoveryController() -> CityNeutralTaskResultRecoveryController? {
        guard current, let service, let receipt else { return nil }
        return .init(service: service, receipt: receipt, unauthorized: unauthorized, accessWithdrawn: { [weak self] in
            self?.invalidate(); self?.messageKey = "cityNeutral.status.accessWithdrawn"
        })
    }
    public func load() async {
        guard !busy else { return }
        guard current, let service, let journal, let owner, let target else { invalidate(); messageKey = "cityNeutral.status.disabled"; return }
        generation += 1; let issued = generation; busy = true; confirmation = nil; snapshot = nil
        defer { if issued == generation { busy = false } }
        do {
            pendingRequestID = try journal.pending(ownerKey: owner, targetKey: target)?.operationID
            let value = try await service.state(); guard valid(issued) else { return }; snapshot = value
            messageKey = pendingRequestID == nil ? "cityNeutral.status.ready" : "cityNeutral.status.unknown"
        } catch { report(error, issued) }
    }
    public func allows(_ task: CityNeutralTask) -> Bool { canWrite && snapshot?.tasks.contains(task) == true && ["NOT_ACCEPTED", "ACTIVE"].contains(task.status) }
    public func prepare(_ task: CityNeutralTask, optionID: String? = nil) {
        confirmation = nil
        guard allows(task), let snapshot, let binding = snapshot.binding, let team = snapshot.teamId, let version = snapshot.teamVersion else { return }
        let kind: CityNeutralTaskAction = task.status == "NOT_ACCEPTED" ? .accept : .submit
        if kind == .submit { guard let optionID, task.definition.options.contains(where: { $0.id == optionID }) else { return } }
        let id = UUID(); let command = CityNeutralTaskCommand(id: id, kind: kind, binding: binding, teamId: team, teamVersion: version, task: task, optionId: optionID)
        confirmation = .init(id: id, command: command, binding: binding, task: task)
    }
    public func confirm(_ captured: Confirmation) async {
        guard confirmation?.id == captured.id, allows(captured.task), snapshot?.binding == captured.binding,
              snapshot?.teamVersion == captured.command.expectedTeamVersion, let service, let journal, let owner, let target else { confirmation = nil; return }
        confirmation = nil; generation += 1; let issued = generation; busy = true
        defer { if issued == generation { busy = false } }
        do {
            guard try journal.pending(ownerKey: owner, targetKey: target) == nil else { messageKey = "cityNeutral.status.recoverFirst"; return }
            let record = OperationPendingRecord(operationID: captured.id, ownerKey: owner, targetKey: target)
            // Request identity only. Never persist answer, token or team roster in this client journal.
            try journal.write(record); pendingRequestID = record.operationID
            try await service.submit(captured.command)
        } catch { report(error, issued) }
        guard valid(issued) else { return }; busy = false; await recover()
    }
    public func recover() async {
        guard !busy, current, let service, let journal, let owner, let target else { return }
        generation += 1; let issued = generation; busy = true; confirmation = nil
        defer { if issued == generation { busy = false } }
        do {
            guard let record = try journal.pending(ownerKey: owner, targetKey: target) else { pendingRequestID = nil; return }
            pendingRequestID = record.operationID
            let value = try await service.receipt(record.operationID); guard valid(issued) else { return }
            try journal.clear(record); pendingRequestID = nil; receipt = value; snapshot = nil
            let state = try await service.state(); guard valid(issued) else { return }; snapshot = state
            messageKey = value.succeeded ? "cityNeutral.status.applied" : "cityNeutral.status.rejected"
        } catch { report(error, issued) }
    }
    private func valid(_ issued: Int) -> Bool { current && generation == issued && !Task.isCancelled }
    private func report(_ error: Error, _ issued: Int) {
        guard generation == issued else { return }
        if !current { snapshot = nil; confirmation = nil; receipt = nil; messageKey = "cityNeutral.status.contextChanged"; return }
        if error as? APIError == .unauthorized { snapshot = nil; confirmation = nil; receipt = nil; unauthorized(); messageKey = "cityNeutral.status.signedOut"; return }
        if case CityNeutralTaskError.server(403, _) = error { snapshot = nil; confirmation = nil; receipt = nil; messageKey = "cityNeutral.status.accessWithdrawn"; return }
        // Never leave a previously writable task snapshot active after a failed live read or ambiguous write.
        snapshot = nil; messageKey = pendingRequestID == nil ? "cityNeutral.status.unavailable" : "cityNeutral.status.unknown"
    }
}
