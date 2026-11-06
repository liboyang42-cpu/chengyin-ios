import Foundation
import Observation

@available(macOS 14.0, *) @MainActor @Observable public final class CityAcquisitionController {
    private var storedSnapshot: CityAcquisitionSnapshot?
    private var storedTitles: [CityAcquisitionTitle] = []
    private var storedQuote: CityAcquisitionQuote?
    private var storedReceipt: CityAcquisitionReceipt?
    public var snapshot: CityAcquisitionSnapshot? { usable ? storedSnapshot : nil }
    public var titles: [CityAcquisitionTitle] { usable ? storedTitles : [] }
    public var selectedQuote: CityAcquisitionQuote? { usable ? storedQuote : nil }
    public var receipt: CityAcquisitionReceipt? { usable ? storedReceipt : nil }
    public private(set) var confirmation: CityAcquisitionQuote?
    public private(set) var pendingRequestID: UUID?
    public private(set) var originalRequestID: UUID?
    public private(set) var busy = false
    public private(set) var messageKey = "cityAcquire.status.initial"
    public private(set) var activityID = UUID()
    private var active = true, accessBlocked = false, journalFailed = false
    private let service: CityAcquisitionService?
    private let journal: (any OperationPendingJournal)?
    private let unauthorized: () -> Void
    private var generation = 0
    @ObservationIgnored private var operation: Task<Void, Never>?
    public init(service: CityAcquisitionService?, journal: (any OperationPendingJournal)?, unauthorized: @escaping () -> Void = {}) { self.service = service; self.journal = journal; self.unauthorized = unauthorized }
    public var current: Bool { service?.transport.isCurrent() == true }
    private var usable: Bool { active && current && !accessBlocked }
    public var canWrite: Bool {
        usable && service?.approval.allowsWrite == true && !busy && !journalFailed && pendingRequestID == nil && journal != nil
            && (originalRequestID == nil || receipt?.requestId == originalRequestID?.uuidString)
    }
    private var owner: String? { service.map { "city-acquisition:\($0.approval.context.session.namespace):\($0.approval.context.baseURL.absoluteString):\($0.approval.context.session.accountID)" } }
    private var target: String? { service?.approval.regionID }
    public func invalidate() {
        generation += 1; operation?.cancel(); operation = nil; activityID = UUID(); accessBlocked = false
        clearFacts(); confirmation = nil; pendingRequestID = nil; originalRequestID = nil; busy = false
        messageKey = "cityAcquire.status.contextChanged"
    }
    public func activate() { invalidate(); active = true }
    public func suspend() { active = false; invalidate() }
    public func cancelConfirmation() { confirmation = nil }
    /// Point-card compatibility: current facts only, never receipt recovery or a mutation.
    public func load() async {
        await perform { issued in
            self.clearFacts(); self.confirmation = nil
            do { _ = try self.readIdentities(); await self.readCurrent(issued) }
            catch { self.report(error, issued) }
        }
    }
    /// The normal page reauthorizes the original request before restoring any saved quote.
    public func open(activity: UUID) async {
        await perform(activity: activity) { issued in
            self.clearFacts(); self.confirmation = nil
            do {
                let records = try self.readIdentities()
                if records.pending != nil || records.original != nil { await self.recoverOriginal(issued) }
                else { await self.readCurrent(issued) }
            } catch { self.report(error, issued) }
        }
    }
    private func readCurrent(_ issued: Int, preservingOriginal: Bool = false) async {
        guard let service else { return }
        storedSnapshot = nil; storedTitles = []
        do {
            let saved = try await service.titles(); guard valid(issued) else { return }; storedTitles = saved
            let value = try await service.state(); guard valid(issued) else { return }; storedSnapshot = value
            if let original = storedReceipt {
                messageKey = original.succeeded ? (original.title == nil ? "cityAcquire.status.quoted" : "cityAcquire.status.committed") : "cityAcquire.status.rejected"
            } else { messageKey = pendingRequestID == nil ? "cityAcquire.status.ready" : "cityAcquire.status.unknown" }
        } catch { report(error, issued, preservingOriginal: preservingOriginal) }
    }
    public func allows(_ candidate: CityAcquisitionCandidate) -> Bool { canWrite && snapshot?.writeApproved == true && snapshot?.candidates.contains(candidate) == true && candidate.eligibility == "QUOTE_AVAILABLE" }
    public func requestQuote(_ candidate: CityAcquisitionCandidate, activity: UUID? = nil) async {
        guard active, !Task.isCancelled, activity == nil || activity == activityID, allows(candidate), let service else { return }
        let id = UUID(); await submit(.init(id: id, region: service.approval.regionID, instanceID: candidate.instanceId), id: id, activity: activity)
    }
    public func prepareConfirmation() {
        confirmation = nil
        guard canWrite, let quote = selectedQuote, quote.writeApproved, quote.unexpired else { return }
        confirmation = quote
    }
    public func confirm(_ captured: CityAcquisitionQuote, activity: UUID? = nil) async {
        guard active, !Task.isCancelled, activity == nil || activity == activityID,
              confirmation == captured, selectedQuote == captured, canWrite, captured.writeApproved, captured.unexpired,
              let id = UUID(uuidString: captured.confirmRequestId), id.uuidString == captured.confirmRequestId else { confirmation = nil; return }
        confirmation = nil
        // The server's immutable confirmation key only, never a replacement purchase UUID.
        await submit(.init(quote: captured), id: id, activity: activity)
    }
    private func submit(_ command: CityAcquisitionCommand, id: UUID, activity: UUID?) async {
        guard canWrite, let service, let journal, let owner, let target else { return }
        let expectedOriginal = originalRequestID
        await perform(activity: activity) { issued in
            self.confirmation = nil
            do {
                let records = try self.readIdentities()
                guard records.pending == nil else { self.messageKey = "cityAcquire.status.recoverFirst"; return }
                if journal is any CityAcquisitionOriginalJournal {
                    guard records.original?.operationID == expectedOriginal else {
                        self.storedSnapshot = nil; self.storedQuote = nil; self.messageKey = "cityAcquire.status.recoverFirst"; return
                    }
                }
                self.journalFailed = true
                let pending = OperationPendingRecord(operationID: id, ownerKey: owner, targetKey: target)
                try journal.write(pending)
                guard try journal.pending(ownerKey: owner, targetKey: target) == pending else { throw APIError.malformedResponse }
                guard self.valid(issued) else { return }
                self.journalFailed = false; self.pendingRequestID = id; self.originalRequestID = id; self.clearFacts()
                try await service.submit(command)
            } catch { self.report(error, issued) }
            guard self.valid(issued), self.pendingRequestID == id else { return }
            await self.recoverOriginal(issued)
        }
    }
    public func recover(activity: UUID? = nil) async {
        await perform(activity: activity) { issued in await self.recoverOriginal(issued) }
    }
    private func recoverOriginal(_ issued: Int) async {
        guard let service, let journal else { return }
        clearFacts(); confirmation = nil
        do {
            let records = try readIdentities()
            guard let anchor = records.pending ?? records.original else { return }
            let value = try await service.receipt(anchor.operationID); guard valid(issued) else { return }
            storedReceipt = value
            if let original = value.quote {
                let quote = try await service.quote(original.id); guard valid(issued) else { return }
                guard quote.hasSameImmutableTerms(as: original) else { throw CityAcquisitionError.malformed }
                storedQuote = quote
            }
            if let pending = records.pending {
                // A normal journal preserves this exact identity before removing its pending lock.
                // No failed quote re-read, unknown result or malformed receipt reaches this step.
                journalFailed = true
                guard try journal.pending(ownerKey: pending.ownerKey, targetKey: pending.targetKey) == pending else { throw APIError.invalidRequest }
                try journal.clear(pending)
                guard try journal.pending(ownerKey: pending.ownerKey, targetKey: pending.targetKey) == nil else { throw APIError.malformedResponse }
                guard valid(issued) else { return }
                pendingRequestID = nil; journalFailed = false
            }
            originalRequestID = anchor.operationID
            await readCurrent(issued, preservingOriginal: true)
        } catch { report(error, issued, preservingOriginal: true) }
    }
    private func readIdentities() throws -> (pending: OperationPendingRecord?, original: OperationPendingRecord?) {
        guard let journal, let owner, let target else { throw CityAcquisitionError.disabled }
        do {
            let pending = try journal.pending(ownerKey: owner, targetKey: target)
            let original = try (journal as? any CityAcquisitionOriginalJournal)?.original(ownerKey: owner, targetKey: target)
            for record in [pending, original].compactMap({ $0 }) {
                guard record.ownerKey.utf8.elementsEqual(owner.utf8), record.targetKey.utf8.elementsEqual(target.utf8),
                      record.acknowledgedSteps == 0, record.nativeWebhook == nil else { throw APIError.malformedResponse }
            }
            pendingRequestID = pending?.operationID; originalRequestID = (pending ?? original)?.operationID
            journalFailed = false; return (pending, original)
        } catch { journalFailed = true; throw error }
    }
    private func perform(activity: UUID? = nil, _ body: @escaping @MainActor (Int) async -> Void) async {
        guard !Task.isCancelled, !busy, active, activity == nil || activity == activityID else { return }
        guard current, service != nil, journal != nil else { invalidate(); messageKey = "cityAcquire.status.disabled"; return }
        generation += 1; let issued = generation; busy = true; accessBlocked = false
        let task = Task { @MainActor in guard self.valid(issued) else { return }; await body(issued) }
        operation = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if generation == issued { operation = nil; busy = false }
    }
    private func valid(_ issued: Int) -> Bool { usable && generation == issued && !Task.isCancelled }
    private func clearFacts() { storedSnapshot = nil; storedTitles = []; storedQuote = nil; storedReceipt = nil }
    private func report(_ error: Error, _ issued: Int, preservingOriginal: Bool = false) {
        guard generation == issued, active else { return }
        storedSnapshot = nil; confirmation = nil
        if !current { clearFacts(); messageKey = "cityAcquire.status.contextChanged"; return }
        if Task.isCancelled { clearFacts(); messageKey = "cityAcquire.status.unavailable"; return }
        if error as? APIError == .unauthorized { accessBlocked = true; clearFacts(); unauthorized(); messageKey = "cityAcquire.status.signedOut"; return }
        if case CityAcquisitionError.server(403, _) = error { accessBlocked = true; clearFacts(); messageKey = "cityAcquire.status.accessWithdrawn"; return }
        if !preservingOriginal { storedQuote = nil; storedReceipt = nil }
        if storedReceipt != nil { messageKey = "cityAcquire.status.originalUnavailable" }
        else { messageKey = pendingRequestID == nil ? "cityAcquire.status.unavailable" : "cityAcquire.status.unknown" }
    }
}
