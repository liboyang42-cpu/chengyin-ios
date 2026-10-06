import Foundation

/// Device-local recovery metadata only. Stores no credential or protected package body. Server
/// history remains authoritative. Owner/realm scoping intentionally survives logout and token rotation.
@MainActor public final class WorkshopPaidInstallPendingStore {
    private let storage: any TemplateAuthoringStorage
    private let ownerKey: String
    private let licenseId: String
    public init(storage: any TemplateAuthoringStorage, context: RuntimeDependencyContext, licenseId: String) throws {
        guard context.session.accountID > 0, WorkshopPurchasedWire.license(licenseId) else { throw WorkshopPaidInstallIssue.invalid }
        self.storage = storage; self.licenseId = licenseId
        ownerKey = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), licenseId]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: ":")
    }
    private var key: String { "workshop-paid-install.pending.v1." + Data(ownerKey.utf8).base64EncodedString() }
    private struct Record: Codable {
        let format: String, ownerKey: String
        let command: WorkshopPaidInstallCommand
        private enum CodingKeys: String, CodingKey { case format, ownerKey, command }
        init(ownerKey: String, command: WorkshopPaidInstallCommand) { format = "workshop-paid-pending-v1"; self.ownerKey = ownerKey; self.command = command }
        init(from decoder: Decoder) throws {
            try WorkshopPaidInstallWire.keys(decoder, ["format", "ownerKey", "command"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            format = try c.decode(String.self, forKey: .format); ownerKey = try c.decode(String.self, forKey: .ownerKey); command = try c.decode(WorkshopPaidInstallCommand.self, forKey: .command)
            guard format == "workshop-paid-pending-v1" else { throw WorkshopPaidInstallIssue.storageUnavailable }
        }
    }
    public func load() throws -> WorkshopPaidInstallCommand? {
        do {
            guard let data = try storage.read(key) else { return nil }
            let record = try WorkshopPaidInstallWire.decode(Record.self, data: data, maximum: 16_384)
            guard WorkshopPaidInstallWire.same(record.ownerKey, ownerKey), record.command.licenseId == licenseId else { throw WorkshopPaidInstallIssue.storageUnavailable }
            return record.command
        } catch { throw WorkshopPaidInstallIssue.storageUnavailable }
    }
    /// Synchronous save and exact readback precede dispatch. Never overwrite another unknown outcome.
    public func save(_ command: WorkshopPaidInstallCommand) throws {
        guard command.licenseId == licenseId else { throw WorkshopPaidInstallIssue.invalid }
        if let old = try load() {
            guard try old.wireData() == command.wireData() else { throw WorkshopPaidInstallIssue.pendingConflict }
            return
        }
        do {
            try storage.write(JSONEncoder().encode(Record(ownerKey: ownerKey, command: command)), key: key)
            guard let saved = try load(), try saved.wireData() == command.wireData() else { throw WorkshopPaidInstallIssue.storageUnavailable }
        } catch { throw WorkshopPaidInstallIssue.storageUnavailable }
    }
    public func acknowledge(_ outcome: WorkshopPaidInstallOutcome) throws {
        guard outcome.state.terminal, let pending = try load(), outcome.matches(pending) else { throw WorkshopPaidInstallIssue.pendingConflict }
        do { try storage.remove(key); guard try storage.read(key) == nil else { throw WorkshopPaidInstallIssue.storageUnavailable } }
        catch { throw WorkshopPaidInstallIssue.storageUnavailable }
    }
}
