import Foundation

public struct MerchantExportRecoveryRecord: Codable, Equatable {
    public let realm: String
    public let accountID: Int
    public let merchantID: Int
    public let taskID: Int
    public let requestID: String
    public init(scope: MerchantBusinessScope, merchantID: Int, taskID: Int, requestID: String) {
        realm = scope.realm; accountID = scope.accountID; self.merchantID = merchantID; self.taskID = taskID; self.requestID = requestID
    }
}
@MainActor public protocol MerchantExportRecoveryStoring: AnyObject {
    func read() throws -> [MerchantExportRecoveryRecord]
    func save(_ record: MerchantExportRecoveryRecord) throws
    func remove(_ record: MerchantExportRecoveryRecord) throws
}
@MainActor public final class MerchantExportFileRecoveryStore: MerchantExportRecoveryStoring {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func read() throws -> [MerchantExportRecoveryRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([MerchantExportRecoveryRecord].self, from: Data(contentsOf: url)) } catch { throw MerchantBusinessFailure.journal }
    }
    public func save(_ record: MerchantExportRecoveryRecord) throws {
        var records = try read(); records.removeAll { $0.realm == record.realm && $0.accountID == record.accountID && $0.merchantID == record.merchantID }; records.append(record); try write(records)
    }
    public func remove(_ record: MerchantExportRecoveryRecord) throws { try write(read().filter { $0 != record }) }
    private func write(_ records: [MerchantExportRecoveryRecord]) throws {
        do { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder().encode(records).write(to: url, options: .atomic) }
        catch { throw MerchantBusinessFailure.journal }
    }
}
@MainActor public final class MerchantExportMemoryRecoveryStore: MerchantExportRecoveryStoring {
    private var records: [MerchantExportRecoveryRecord] = []
    public init() {}
    public func read() throws -> [MerchantExportRecoveryRecord] { records }
    public func save(_ record: MerchantExportRecoveryRecord) throws { records.removeAll { $0.realm == record.realm && $0.accountID == record.accountID && $0.merchantID == record.merchantID }; records.append(record) }
    public func remove(_ record: MerchantExportRecoveryRecord) throws { records.removeAll { $0 == record } }
}
public struct MerchantEngagementReview: Equatable, Identifiable {
    public let id: UUID
    public let command: MerchantEngagementCommand
    public let proof: MerchantEngagementProof
    public let scope: MerchantBusinessScope
    public let requestID: String
}
@MainActor public protocol MerchantContactDelivering {
    /// Injected platform action. Default app host does not create a dialer or clipboard adapter.
    func deliverSynthetic(phone: String, purpose: MerchantContactPurpose) async throws
}
@MainActor public final class MerchantEngagementCoordinator {
    public let reader: any MerchantEngagementReading
    private let journal: any MerchantBusinessIntentStore
    private let exports: any MerchantExportRecoveryStoring
    public private(set) var review: MerchantEngagementReview?
    public private(set) var receipt: MerchantEngagementReceipt?
    public private(set) var receiptScope: MerchantBusinessScope?
    private var receiptMerchantID: Int?
    public private(set) var exportTicket: MerchantExportTicket?
    public private(set) var exportScope: MerchantBusinessScope?
    public private(set) var exportMerchantID: Int?
    public private(set) var failure: MerchantBusinessFailure?
    public private(set) var busy = false
    public private(set) var locked = false
    private var generation = 0
    public init(reader: any MerchantEngagementReading, journal: any MerchantBusinessIntentStore, exportRecovery: any MerchantExportRecoveryStoring) {
        self.reader = reader; self.journal = journal; exports = exportRecovery
    }
    public func cancelReview() { review = nil }
    public func invalidate() {
        generation += 1; review = nil; receipt = nil; receiptScope = nil; receiptMerchantID = nil; exportTicket = nil; exportScope = nil; exportMerchantID = nil; failure = nil; busy = false
    }
    public func clearSensitiveReceipt() { receipt = nil; receiptScope = nil; receiptMerchantID = nil }
    public func prepare(_ command: MerchantEngagementCommand) async {
        guard !busy else { return }
        generation += 1; let stamp = generation, scope = reader.scope
        review = nil; receipt = nil; receiptScope = nil; receiptMerchantID = nil; failure = nil; busy = true
        defer { if generation == stamp { busy = false } }
        do {
            guard let scope else { throw MerchantBusinessFailure.stale }
            let proof = try await reader.proof(command)
            guard generation == stamp, reader.scope == scope, !Task.isCancelled else { return }
            let requestID = "crm-" + command.key + "-" + UUID().uuidString.lowercased()
            _ = try command.request(requestID: requestID)
            let intent = MerchantBusinessIntent(scope: scope, merchantID: proof.access.merchantID ?? 0, target: command.lockTarget, requestID: requestID)
            guard try !journal.intents().contains(where: { $0.sameTarget(as: intent) }) else { throw MerchantBusinessFailure.pending }
            if case .createExport = command {
                let saved = try exports.read().first { $0.realm == scope.realm && $0.accountID == scope.accountID && $0.merchantID == proof.access.merchantID }
                if let saved {
                    guard case .exportStatus(let task) = try await reader.read(.exportStatus(saved.taskID)), !task.isRunning else { throw MerchantBusinessFailure.pending }
                    guard reader.scope == scope, generation == stamp else { return }
                }
            }
            review = .init(id: UUID(), command: command, proof: proof, scope: scope, requestID: requestID)
        } catch { if generation == stamp, reader.scope == scope { failure = error as? MerchantBusinessFailure ?? .invalid } }
    }
    public func confirm(_ frozen: MerchantEngagementReview) async {
        guard !busy, review == frozen, reader.scope == frozen.scope else { failure = .stale; return }
        guard reader.isSyntheticEnabled else { failure = .disabled; return }
        busy = true; review = nil; let stamp = generation
        defer { if stamp == generation { busy = false } }
        do {
            let fresh = try await reader.proof(frozen.command)
            guard stamp == generation, reader.scope == frozen.scope, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            guard fresh == frozen.proof else { throw MerchantBusinessFailure.conflict }
        } catch { if stamp == generation { failure = error as? MerchantBusinessFailure ?? .stale }; return }
        let intent = MerchantBusinessIntent(scope: frozen.scope, merchantID: frozen.proof.access.merchantID ?? 0, target: frozen.command.lockTarget, requestID: frozen.requestID)
        do { try journal.reserve(intent) } catch { failure = error as? MerchantBusinessFailure ?? .journal; return }
        locked = true
        do {
            let result = try await reader.execute(frozen.command, requestID: frozen.requestID, proof: frozen.proof, scope: frozen.scope)
            guard stamp == generation, reader.scope == frozen.scope, !Task.isCancelled else { return }
            if case .exportCreated(let ticket) = result {
                guard let merchant = frozen.proof.access.merchantID else { throw MerchantBusinessFailure.malformed }
                try exports.save(.init(scope: frozen.scope, merchantID: merchant, taskID: ticket.task.id, requestID: frozen.requestID))
                exportTicket = ticket; exportScope = frozen.scope; exportMerchantID = merchant
            }
            try journal.complete(intent); receipt = result; receiptScope = frozen.scope; receiptMerchantID = frozen.proof.access.merchantID; locked = false; failure = nil
        } catch {
            let definite = MerchantMutationFailureDisposition.provesNoDispatch(error)
            if definite { do { try journal.complete(intent) } catch { if stamp == generation { failure = .journal }; return } }
            guard stamp == generation, reader.scope == frozen.scope else { return }
            locked = !definite; failure = definite ? (error as? MerchantBusinessFailure ?? .denied) : .unknown
        }
    }
    /// Read-only source status progression. Invalid/newly unauthorized frames do not invent terminal states.
    public func refreshExport() async {
        let stamp = generation, scope = reader.scope
        do {
            guard let scope else { throw MerchantBusinessFailure.stale }
            let access = try await reader.access(); try access.require(["merchant:crm:read", "merchant:crm:export"])
            guard stamp == generation, reader.scope == scope, let merchant = access.merchantID else { return }
            if exportScope != scope || exportMerchantID != merchant { exportTicket = nil; exportScope = nil; exportMerchantID = nil }
            guard let record = try exports.read().first(where: { $0.realm == scope.realm && $0.accountID == scope.accountID && $0.merchantID == merchant }) else { return }
            guard case .exportStatus(let status) = try await reader.read(.exportStatus(record.taskID)) else { throw MerchantBusinessFailure.malformed }
            guard stamp == generation, reader.scope == scope, !Task.isCancelled else { return }
            if exportScope == scope, exportMerchantID == merchant, let current = exportTicket, current.task.id == status.id {
                exportTicket = try current.updating(status)
            } else {
                // Process restart loses the one-time token intentionally; status remains useful.
                exportTicket = try .init(creation: ["id": .int(status.id), "status": .string(status.status), "rowCount": .optional(status.rowCount), "errorMessage": .optional(status.errorMessage)])
            }
            exportScope = scope; exportMerchantID = merchant; failure = nil
        } catch {
            guard stamp == generation, reader.scope == scope else { return }
            failure = error as? MerchantBusinessFailure ?? .malformed
            if error as? MerchantBusinessFailure == .denied || error as? APIError == .unauthorized { exportTicket = nil; exportScope = nil; exportMerchantID = nil }
        }
    }
    /// The receiving aftercare form supplies its fresh exact context. Upload does not itself submit an opinion.
    public func takeEvidenceForResponse(refundID: MerchantRefundID, scope: MerchantBusinessScope, merchantID: Int) -> MerchantAftercareEvidenceReceipt? {
        guard reader.scope == scope, receiptScope == scope, receiptMerchantID == merchantID,
              let receipt, case .evidenceUploaded(let returnedRefund, _, let evidence) = receipt, returnedRefund == refundID else { return nil }
        clearSensitiveReceipt(); return evidence
    }
    public func consumeContact(using delivery: any MerchantContactDelivering) async throws {
        guard reader.isSyntheticEnabled, let receipt, case .contact(let contact) = receipt, let captured = receiptScope else { throw MerchantBusinessFailure.disabled }
        guard reader.scope == captured else { clearSensitiveReceipt(); throw MerchantBusinessFailure.stale }
        let access = try await reader.access(); try access.require(["merchant:crm:read", "merchant:crm:sensitive:read"])
        guard reader.scope == captured, access.merchantID == receiptMerchantID else { clearSensitiveReceipt(); throw MerchantBusinessFailure.stale }
        // One-shot consumption: no retry using a cached number, even if the device action fails.
        clearSensitiveReceipt()
        try await delivery.deliverSynthetic(phone: contact.phone, purpose: contact.purpose)
    }
}
