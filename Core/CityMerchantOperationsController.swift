import Foundation
import Observation

@available(macOS 14.0, *) @MainActor @Observable public final class CityMerchantOperationsController {
    public struct Confirmation: Identifiable, Equatable {
        public let id = UUID()
        public let merchantID: String
        public let version: Int64
        public let approvalHash: String
        public let kind: CityMerchantIntent
        public let reason: String
    }
    public private(set) var snapshot: CityMerchantSnapshot?
    public private(set) var confirmation: Confirmation?
    public private(set) var pendingRequestID: UUID?
    public private(set) var busy = false
    public private(set) var messageKey = "cityMerchant.status.initial"
    public private(set) var receipt: CityMerchantSnapshot?
    public enum CurrentState: Equatable { case idle, loading, ready, unavailable }
    public private(set) var currentState: CurrentState = .idle
    public private(set) var originalRejection: CityMerchantOriginalRejection?
    private var active = true
    private var queuedConfirmation: Confirmation?
    private let service: CityMerchantOperationsService?
    private let journal: (any OperationPendingJournal)?
    private let unauthorized: () -> Void
    private var generation = 0
    public init(service: CityMerchantOperationsService?, journal: (any OperationPendingJournal)?, unauthorized: @escaping () -> Void = {}) {
        self.service = service; self.journal = journal; self.unauthorized = unauthorized
    }
    private var current: Bool { service?.transport.isCurrent() == true }
    private var ownerKey: String? {
        guard let c = service?.approval.context else { return nil }
        return "city-merchant:\(c.session.namespace):\(c.baseURL.absoluteString):\(c.session.accountID)"
    }
    private var targetKey: String? { service.map { "own-store:\($0.approval.regionID)" } }
    private var sourceCanSubmit: Bool { active && current && currentState == .ready && service?.approval.allowsIntent == true && journal != nil && !busy && pendingRequestID == nil && snapshot?.available == true && snapshot?.pendingReview == false }
    public var canPrepare: Bool { sourceCanSubmit && queuedConfirmation == nil }
    public func prepare(_ kind: CityMerchantIntent, reason: String) {
        confirmation = nil
        let clean = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canPrepare, let snapshot, let hash = snapshot.approvalHash, !clean.isEmpty, clean.utf16.count <= 500,
              (kind == .restore ? snapshot.effectiveState == "PAUSED" : snapshot.effectiveState != "PAUSED") else { messageKey = "cityMerchant.status.checkInput"; return }
        confirmation = Confirmation(merchantID: snapshot.merchantId, version: snapshot.version, approvalHash: hash, kind: kind, reason: clean)
    }
    public func dismissConfirmation() { confirmation = nil }
    /// Called synchronously by the explicit alert submit action, before SwiftUI dismisses it.
    /// Dismissing the alert after that tap does not revoke the admitted action; exit/background does.
    public func admitConfirmation(_ captured: Confirmation) -> Bool {
        guard canPrepare, confirmation == captured else { return false }
        queuedConfirmation = captured; confirmation = nil
        return true
    }
    public func invalidate() {
        active = false; generation += 1; confirmation = nil; queuedConfirmation = nil; snapshot = nil; receipt = nil
        originalRejection = nil; currentState = .idle; pendingRequestID = nil; busy = false
        messageKey = "cityMerchant.status.left"
    }
    /// The visible view admits this transition before starting a new read. No write is implied.
    public func activate() { guard current else { return }; active = true }
    public func load() async {
        guard active, !busy, !Task.isCancelled else { return }; confirmation = nil; queuedConfirmation = nil; snapshot = nil
        currentState = .loading
        guard let service, let journal, let ownerKey, let targetKey, current else { messageKey = "cityMerchant.status.disabled"; snapshot = nil; currentState = .idle; return }
        generation += 1; let issued = generation; busy = true
        defer { if issued == generation { busy = false } }
        do {
            let pending = try journal.pending(ownerKey: ownerKey, targetKey: targetKey)
            pendingRequestID = pending?.operationID
            let value = try await service.availability()
            guard current, !Task.isCancelled, issued == generation else { return }
            if let receipt { guard value.merchantId == receipt.merchantId, value.version >= receipt.version else { throw CityMerchantOperationError.malformed } }
            snapshot = value; currentState = .ready; pendingRequestID = pending?.operationID
            messageKey = pending != nil ? "cityMerchant.status.pending" : statusMessageKey(value)
        } catch { report(error, issued: issued) }
    }
    /// Called only from the explicit confirmation alert. Journal is durable before the sole POST.
    public func confirm(_ captured: Confirmation) async {
        guard !Task.isCancelled else { return }
        if confirmation == captured { guard admitConfirmation(captured) else { return } }
        guard queuedConfirmation == captured else { return }
        guard sourceCanSubmit, let service, let journal, let ownerKey, let targetKey, let snapshot,
              snapshot.merchantId == captured.merchantID, snapshot.version == captured.version, snapshot.approvalHash == captured.approvalHash else { queuedConfirmation = nil; confirmation = nil; messageKey = "cityMerchant.status.expired"; return }
        queuedConfirmation = nil; confirmation = nil; receipt = nil; originalRejection = nil
        generation += 1; let issued = generation; busy = true
        defer { if issued == generation { busy = false } }
        do {
            guard try journal.pending(ownerKey: ownerKey, targetKey: targetKey) == nil else { messageKey = "cityMerchant.status.recoverFirst"; return }
            let record = OperationPendingRecord(ownerKey: ownerKey, targetKey: targetKey)
            try journal.write(record); pendingRequestID = record.operationID
            _ = try await service.submit(id: record.operationID, version: captured.version, kind: captured.kind, reason: captured.reason, approvalHash: captured.approvalHash)
            guard current, !Task.isCancelled, issued == generation else { return }
            messageKey = "cityMerchant.status.submitted"
        } catch { report(error, issued: issued) }
        guard current, !Task.isCancelled, issued == generation else { return }
        busy = false
        await recover()
    }
    public func recover() async {
        guard active, !Task.isCancelled, !busy, current, let service, let journal, let ownerKey, let targetKey else { return }
        generation += 1; let issued = generation; busy = true; confirmation = nil
        defer { if issued == generation { busy = false } }
        do {
            guard let record = try journal.pending(ownerKey: ownerKey, targetKey: targetKey) else { pendingRequestID = nil; return }
            pendingRequestID = record.operationID
            do {
                let result = try await service.receipt(id: record.operationID)
                guard active, current, !Task.isCancelled, issued == generation else { return }
                guard result.requestId == record.operationID.uuidString,
                      snapshot == nil || snapshot?.merchantId == result.merchantId else { throw CityMerchantOperationError.malformed }
                receipt = result; originalRejection = nil
            } catch let rejected as CityMerchantOriginalRejection {
                guard active, current, !Task.isCancelled, issued == generation,
                      rejected.requestID == record.operationID else { return }
                originalRejection = rejected; receipt = nil
            }
            // Submission acceptance (including IN_REVIEW) is known independently of current.
            // Keep the original UUID as a read-recovery handle until the current read succeeds.
            snapshot = nil; currentState = .loading
            let value = try await service.availability()
            guard active, current, !Task.isCancelled, issued == generation else { return }
            if let receipt {
                guard value.merchantId == receipt.merchantId, value.version >= receipt.version else {
                    throw CityMerchantOperationError.malformed
                }
            }
            try journal.clear(record); pendingRequestID = nil
            snapshot = value; currentState = .ready
            messageKey = originalRejection == nil ? statusMessageKey(value) : "cityMerchant.status.notApplied"
        } catch { report(error, issued: issued) }
    }
    private func report(_ error: Error, issued: Int) {
        guard active, issued == generation else { return }
        snapshot = nil; confirmation = nil; queuedConfirmation = nil
        if !current {
            receipt = nil; originalRejection = nil; currentState = .idle
            messageKey = "cityMerchant.status.contextChanged"; return
        }
        if let api = error as? APIError, api == .unauthorized {
            receipt = nil; originalRejection = nil; currentState = .idle
            unauthorized(); messageKey = "cityMerchant.status.signedOut"; return
        }
        if case CityMerchantOperationError.server(403, _) = error {
            receipt = nil; originalRejection = nil; currentState = .idle
            messageKey = "cityMerchant.status.accessWithdrawn"; return
        }
        currentState = .unavailable
        messageKey = receipt != nil || originalRejection != nil ? "cityMerchant.status.knownCurrentUnavailable"
            : (pendingRequestID == nil ? "cityMerchant.status.readFailure" : "cityMerchant.status.unknown")
    }
    private func statusMessageKey(_ value: CityMerchantSnapshot) -> String {
        if !value.available { return "cityMerchant.status.sourceMissing" }
        if value.pendingReview { return "cityMerchant.status.review" }
        if value.status == "APPLIED" { return "cityMerchant.status.applied" }
        if value.status == "REJECTED" { return "cityMerchant.status.rejected" }
        return "cityMerchant.status.ready"
    }
}

/// View-owned admission prevents queued work from reactivating a departed/background visit.
public struct CityMerchantVisitAdmission: Equatable {
    public private(set) var revision = UUID()
    public private(set) var visible = false
    public init() {}
    public mutating func appear() { revision = UUID(); visible = true }
    public mutating func invalidate() { revision = UUID() }
    public mutating func disappear() { revision = UUID(); visible = false }
    public func permits(_ captured: UUID, active: Bool, cancelled: Bool = Task.isCancelled) -> Bool {
        visible && active && revision == captured && !cancelled
    }
}
