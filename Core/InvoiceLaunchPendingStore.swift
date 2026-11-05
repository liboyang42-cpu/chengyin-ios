import Foundation

/// Use the app's unlocked, device-only secure storage adapter. No token, title name,
/// full tax number, invoice document or amount is persisted by this journal.
@MainActor public protocol InvoiceLaunchStorage: AnyObject {
    func read(_ key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(_ key: String) throws
}
public struct InvoiceLaunchPending: Codable, Equatable {
    public enum Kind: String, Codable { case apply, saveTitle, deleteTitle, cancel }
    public let operationID: UUID
    public let kind: Kind
    public let apply: InvoiceLaunchApply?
    public let targetID: Int64?
    /// Original title-save key only, never title/tax input. Missing in legacy journals.
    public let titleRequestID: String?
    public let originalApplicationReceipt: Bool?
    public private(set) var applicationID: Int64?
    /// ID from a validated, session-bound save response, not an inferred title
    /// match or a server request receipt. Missing in earlier v1 records.
    public private(set) var acknowledgedTitleID: Int64?
    init(kind: Kind, apply: InvoiceLaunchApply? = nil, targetID: Int64? = nil, titleRequestID: String? = nil, originalApplicationReceipt: Bool? = nil) {
        operationID = UUID(); self.kind = kind; self.apply = apply; self.targetID = targetID; self.titleRequestID = titleRequestID; self.originalApplicationReceipt = originalApplicationReceipt
    }
    func validate() throws {
        guard (originalApplicationReceipt == nil || kind == .apply), titleRequestID.map(InvoiceLaunchWire.requestID) != false,
              (titleRequestID == nil || kind == .saveTitle), targetID.map({ $0 > 0 }) != false, applicationID.map({ $0 > 0 }) != false,
              acknowledgedTitleID.map({ $0 > 0 }) != false else { throw InvoiceLaunchIssue.storageUnavailable }
        switch kind {
        case .apply:
            guard let apply, targetID == nil, acknowledgedTitleID == nil else { throw InvoiceLaunchIssue.storageUnavailable }; try apply.validate()
        case .saveTitle:
            guard apply == nil, applicationID == nil,
                  acknowledgedTitleID == nil || targetID == nil || acknowledgedTitleID == targetID else { throw InvoiceLaunchIssue.storageUnavailable }
        case .deleteTitle, .cancel:
            guard apply == nil, targetID != nil, applicationID == nil, acknowledgedTitleID == nil else { throw InvoiceLaunchIssue.storageUnavailable }
        }
    }
    mutating func recordApplication(_ id: Int64) { applicationID = id }
    mutating func recordAcknowledgedTitle(_ id: Int64) { acknowledgedTitleID = id }
}
@MainActor public final class InvoiceLaunchPendingStore {
    let ownerKey: String
    private let storage: any InvoiceLaunchStorage
    private var key: String { "invoice-launch.pending.v1." + Data(ownerKey.utf8).base64EncodedString() }
    public init(session: InvoiceLaunchSession, storage: any InvoiceLaunchStorage) {
        ownerKey = session.ownerKey; self.storage = storage
    }
    private struct Record: Codable { let version: Int; let ownerKey: String; let pending: InvoiceLaunchPending }
    public func load() throws -> InvoiceLaunchPending? {
        do {
            guard let data = try storage.read(key) else { return nil }
            guard data.count <= 65_536 else { throw InvoiceLaunchIssue.storageUnavailable }
            let record = try JSONDecoder().decode(Record.self, from: data)
            guard record.version == 1, record.ownerKey == ownerKey else { throw InvoiceLaunchIssue.storageUnavailable }
            try record.pending.validate(); return record.pending
        } catch { throw InvoiceLaunchIssue.storageUnavailable }
    }
    func save(_ pending: InvoiceLaunchPending) throws {
        try pending.validate()
        guard try load() == nil else { throw InvoiceLaunchIssue.pendingConflict }
        try persist(pending)
    }
    func checkpoint(_ pending: InvoiceLaunchPending, applicationID: Int64) throws -> InvoiceLaunchPending {
        guard applicationID > 0, pending.kind == .apply,
              pending.applicationID == nil || pending.applicationID == applicationID,
              try load() == pending else { throw InvoiceLaunchIssue.pendingConflict }
        var updated = pending; updated.recordApplication(applicationID); try persist(updated); return updated
    }
    func checkpointTitle(_ pending: InvoiceLaunchPending, acknowledgedTitleID: Int64) throws -> InvoiceLaunchPending {
        guard acknowledgedTitleID > 0, pending.kind == .saveTitle,
              pending.targetID == nil || pending.targetID == acknowledgedTitleID,
              pending.acknowledgedTitleID == nil || pending.acknowledgedTitleID == acknowledgedTitleID,
              try load() == pending else { throw InvoiceLaunchIssue.pendingConflict }
        var updated = pending; updated.recordAcknowledgedTitle(acknowledgedTitleID); try persist(updated); return updated
    }
    private func persist(_ pending: InvoiceLaunchPending) throws {
        do {
            try storage.write(InvoiceLaunchWire.encode(Record(version: 1, ownerKey: ownerKey, pending: pending)), key: key)
            guard try load() == pending else { throw InvoiceLaunchIssue.storageUnavailable }
        } catch { throw InvoiceLaunchIssue.storageUnavailable }
    }
    func clear(_ pending: InvoiceLaunchPending) throws {
        guard try load() == pending else { throw InvoiceLaunchIssue.pendingConflict }
        do {
            try storage.remove(key); guard try storage.read(key) == nil else { throw InvoiceLaunchIssue.storageUnavailable }
        } catch { throw InvoiceLaunchIssue.storageUnavailable }
    }
}
