import Foundation
import Observation

@available(macOS 14.0, *) @MainActor @Observable public final class CityOnsiteTaskController {
    public struct Confirmation: Identifiable { public let id: UUID; public let command: CityOnsiteTaskCommand; public let binding: CityOnsiteTaskBinding; public let task: CityOnsiteTask }
    private var storedResult: CityOnsiteTaskResult?
    private var storedSnapshot: CityOnsiteTaskSnapshot?
    private var storedReceipt: CityOnsiteTaskReceipt?
    public var selectedResult: CityOnsiteTaskResult? { usable ? storedResult : nil }
    public var snapshot: CityOnsiteTaskSnapshot? { usable ? storedSnapshot : nil }
    public var receipt: CityOnsiteTaskReceipt? { usable ? storedReceipt : nil }
    public private(set) var confirmation: Confirmation?
    public private(set) var pendingRequestID: UUID?
    public private(set) var originalRequestID: UUID?
    public private(set) var busy = false
    public private(set) var messageKey = "cityOnsite.status.initial"
    public private(set) var activityID = UUID()
    private let service: CityOnsiteTaskService?
    private let journal: (any OperationPendingJournal)?
    private let unauthorized: () -> Void
    private var retained: OperationPendingRecord?
    private var journalFailed = false
    private var active = true
    private var accessBlocked = false
    private var generation = 0
    @ObservationIgnored private var operation: Task<Void, Never>?
    public init(service: CityOnsiteTaskService?, journal: (any OperationPendingJournal)?, unauthorized: @escaping () -> Void = {}) { self.service = service; self.journal = journal; self.unauthorized = unauthorized }
    public var current: Bool { service?.transport.isCurrent() == true }
    private var usable: Bool { active && current && !accessBlocked }
    public var canWrite: Bool {
        usable && service?.approval.allowsWrite == true && snapshot?.writeApproved == true && !busy && !journalFailed
            && pendingRequestID == nil && journal != nil
            && (originalRequestID == nil || receipt?.requestId == originalRequestID?.uuidString)
    }
    private var owner: String? { service.map { "city-onsite:\($0.approval.context.session.namespace):\($0.approval.context.baseURL.absoluteString):\($0.approval.context.session.accountID)" } }
    private var target: String? { service.map { "\($0.board.regionId):\($0.board.boardId):\($0.board.seasonId)" } }
    public func invalidate() {
        generation += 1; operation?.cancel(); operation = nil; activityID = UUID(); accessBlocked = false
        clearFacts(); confirmation = nil; retained = nil; pendingRequestID = nil; originalRequestID = nil; busy = false
        messageKey = "cityOnsite.status.contextChanged"
    }
    public func activate() { invalidate(); active = true }
    public func suspend() { active = false; invalidate() }
    public func cancelConfirmation() { confirmation = nil }
    public func closeResult() { guard !busy else { return }; storedResult = nil }
    /// Reopen the exact saved request before asking for present-day eligibility. Never replay a command.
    public func load(activity: UUID? = nil) async {
        await perform(activity: activity) { issued in
            self.clearFacts(); self.confirmation = nil
            do {
                if try self.retainedRecord() != nil { await self.recoverOriginal(issued) }
                else { await self.readState(issued) }
            } catch { self.report(error, issued) }
        }
    }
    private func readState(_ issued: Int) async {
        guard let service else { return }; storedSnapshot = nil
        do {
            let value = try await service.state(); guard valid(issued) else { return }; storedSnapshot = value
            if let receipt = storedReceipt { messageKey = receipt.succeeded ? "cityOnsite.status.applied" : "cityOnsite.status.rejected" }
            else { messageKey = "cityOnsite.status.ready" }
        } catch { report(error, issued) }
    }
    public func allows(_ task: CityOnsiteTask) -> Bool { canWrite && task.canAct && task.evidence?.unexpired == true && snapshot?.tasks.contains(task) == true && ["NOT_ACCEPTED", "ACTIVE"].contains(task.status) }
    public func prepare(_ task: CityOnsiteTask, optionID: String? = nil) {
        confirmation = nil
        guard allows(task), let snapshot, let binding = snapshot.binding, let team = snapshot.teamId, let version = snapshot.teamVersion else { return }
        let kind: CityOnsiteTaskAction = task.status == "NOT_ACCEPTED" ? .accept : .submit
        if kind == .submit { guard let optionID, task.definition.options.contains(where: { $0.id == optionID }) else { return } }
        let id = UUID(); let command = CityOnsiteTaskCommand(id: id, kind: kind, binding: binding, teamId: team, teamVersion: version, task: task, optionId: optionID)
        confirmation = .init(id: id, command: command, binding: binding, task: task)
    }
    public func confirm(_ captured: Confirmation) async {
        guard confirmation?.id == captured.id, allows(captured.task), snapshot?.binding == captured.binding,
              snapshot?.teamVersion == captured.command.expectedTeamVersion, let service, let journal, let owner, let target else { confirmation = nil; return }
        confirmation = nil; let expected = retained
        await perform { issued in
            do {
                let previous = try self.retainedRecord(); guard self.valid(issued) else { return }
                guard previous == expected else { self.storedSnapshot = nil; self.messageKey = "cityOnsite.status.recoverFirst"; return }
                self.journalFailed = true
                let record = OperationPendingRecord(operationID: captured.id, ownerKey: owner, targetKey: target)
                if let previous {
                    guard previous.acknowledgedSteps == 1, self.storedReceipt?.requestId == previous.operationID.uuidString,
                          let replacing = journal as? any OperationPendingReplacing else { self.messageKey = "cityOnsite.status.recoverFirst"; return }
                    try replacing.replace(previous, with: record)
                } else {
                    // Identity only. Never persist the answer, token, task response or team roster.
                    try journal.write(record)
                }
                guard try journal.pending(ownerKey: owner, targetKey: target) == record else { throw APIError.malformedResponse }
                guard self.valid(issued) else { return }
                self.retained = record; self.journalFailed = false
                self.pendingRequestID = record.operationID; self.originalRequestID = record.operationID; self.clearFacts()
                try await service.submit(captured.command)
            } catch { self.report(error, issued) }
            guard self.valid(issued), self.pendingRequestID == captured.id else { return }
            await self.recoverOriginal(issued)
        }
    }
    public func recover(activity: UUID? = nil) async {
        await perform(activity: activity) { issued in await self.recoverOriginal(issued) }
    }
    private func recoverOriginal(_ issued: Int) async {
        guard let service, let journal else { return }
        let previousReceipt = storedReceipt
        storedSnapshot = nil; confirmation = nil
        do {
            guard let record = try retainedRecord() else { storedReceipt = nil; storedResult = nil; return }
            if previousReceipt?.requestId != record.operationID.uuidString { storedReceipt = nil; storedResult = nil }
            pendingRequestID = record.operationID
            let value = try await service.receipt(record.operationID); guard valid(issued) else { return }
            if let previousReceipt, previousReceipt.requestId == value.requestId, previousReceipt != value { throw CityOnsiteTaskError.malformed }
            storedReceipt = value
            if let original = value.result {
                let result = try await service.result(original.resultId); guard valid(issued) else { return }
                // The result read must be the immutable record already bound to this exact original receipt.
                guard result == original else { throw CityOnsiteTaskError.malformed }
                storedResult = result
            } else { storedResult = nil }
            // Keep the latest original identity across dismissal/restart. This marker never proves the outcome.
            journalFailed = true
            var resolved = record; resolved.acknowledgedSteps = 1
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { throw APIError.invalidRequest }
            try journal.write(resolved)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == resolved else { throw APIError.malformedResponse }
            guard valid(issued) else { return }
            retained = resolved; pendingRequestID = nil; journalFailed = false
            await readState(issued)
        } catch { report(error, issued) }
    }
    public func readResult(_ id: String, activity: UUID? = nil) async {
        guard usable, let service,
              let original = receipt?.result.flatMap({ $0.resultId == id ? $0 : nil }) ?? snapshot?.tasks.compactMap(\.result).first(where: { $0.resultId == id }) else { return }
        await perform(activity: activity) { issued in
            self.confirmation = nil
            if self.storedResult?.resultId != id { self.storedResult = nil }
            do {
                let value = try await service.result(id); guard self.valid(issued) else { return }
                guard value == original else { throw CityOnsiteTaskError.malformed }
                self.storedResult = value; self.messageKey = "cityOnsite.status.originalResult"
            } catch { self.report(error, issued) }
        }
    }
    private func retainedRecord() throws -> OperationPendingRecord? {
        guard let journal, let owner, let target else { throw CityOnsiteTaskError.disabled }
        do {
            let value = try journal.pending(ownerKey: owner, targetKey: target)
            if let value {
                guard value.ownerKey == owner, value.targetKey == target, (0...1).contains(value.acknowledgedSteps),
                      value.merchantNPCSave == nil, value.themeItemUse == nil, value.sideQuestPlayer == nil, value.merchantSideQuestPublishing == nil else { throw APIError.malformedResponse }
            }
            retained = value; originalRequestID = value?.operationID
            pendingRequestID = value?.acknowledgedSteps == 0 ? value?.operationID : nil
            journalFailed = false; return value
        } catch { journalFailed = true; throw error }
    }
    private func perform(activity: UUID? = nil, _ body: @escaping @MainActor (Int) async -> Void) async {
        guard !Task.isCancelled, !busy, active, activity == nil || activity == activityID else { return }
        guard current, service != nil, journal != nil else { invalidate(); messageKey = "cityOnsite.status.disabled"; return }
        generation += 1; let issued = generation; busy = true; accessBlocked = false
        let task = Task { @MainActor in guard self.valid(issued) else { return }; await body(issued) }
        operation = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if generation == issued { operation = nil; busy = false }
    }
    private func valid(_ issued: Int) -> Bool { usable && generation == issued && !Task.isCancelled }
    private func clearFacts() { storedSnapshot = nil; storedResult = nil; storedReceipt = nil }
    private func report(_ error: Error, _ issued: Int) {
        guard generation == issued, active else { return }
        if !current { clearFacts(); confirmation = nil; pendingRequestID = nil; originalRequestID = nil; messageKey = "cityOnsite.status.contextChanged"; return }
        if Task.isCancelled { clearFacts(); confirmation = nil; messageKey = "cityOnsite.status.unavailable"; return }
        if error as? APIError == .unauthorized { accessBlocked = true; clearFacts(); confirmation = nil; pendingRequestID = nil; originalRequestID = nil; unauthorized(); messageKey = "cityOnsite.status.signedOut"; return }
        if case CityOnsiteTaskError.server(403, _) = error { accessBlocked = true; clearFacts(); confirmation = nil; pendingRequestID = nil; originalRequestID = nil; messageKey = "cityOnsite.status.accessWithdrawn"; return }
        // A verified original is historical only. A failed current read can never leave live write eligibility.
        storedSnapshot = nil
        if storedReceipt != nil {
            messageKey = journalFailed ? "cityOnsite.status.journalUnavailable" : pendingRequestID == nil ? "cityOnsite.status.currentUnavailable" : "cityOnsite.status.resultUnavailable"
        } else { messageKey = pendingRequestID == nil ? "cityOnsite.status.unavailable" : "cityOnsite.status.unknown" }
    }
}
