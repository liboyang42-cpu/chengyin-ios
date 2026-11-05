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
    public private(set) var applicationID: Int64?
    init(kind: Kind, apply: InvoiceLaunchApply? = nil, targetID: Int64? = nil) {
        operationID = UUID(); self.kind = kind; self.apply = apply; self.targetID = targetID
    }
    func validate() throws {
        guard targetID.map({ $0 > 0 }) != false, applicationID.map({ $0 > 0 }) != false else { throw InvoiceLaunchIssue.storageUnavailable }
        switch kind {
        case .apply:
            guard let apply, targetID == nil else { throw InvoiceLaunchIssue.storageUnavailable }; try apply.validate()
        case .saveTitle:
            guard apply == nil, applicationID == nil else { throw InvoiceLaunchIssue.storageUnavailable }
        case .deleteTitle, .cancel:
            guard apply == nil, targetID != nil, applicationID == nil else { throw InvoiceLaunchIssue.storageUnavailable }
        }
    }
    mutating func recordApplication(_ id: Int64) { applicationID = id }
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
        guard applicationID > 0, pending.kind == .apply, try load() == pending else { throw InvoiceLaunchIssue.pendingConflict }
        var updated = pending; updated.recordApplication(applicationID); try persist(updated); return updated
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
