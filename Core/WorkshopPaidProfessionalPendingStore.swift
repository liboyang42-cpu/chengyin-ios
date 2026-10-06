import Foundation

/// Recovery metadata only. No token, protected source, terms document or purported entitlement.
@MainActor public final class WorkshopPaidProfessionalPendingStore {
    private let storage: any TemplateAuthoringStorage
    private let ownerKey: String
    private let ownedDraftID: Int64
    private let licenseID: String
    public init(storage: any TemplateAuthoringStorage, context: RuntimeDependencyContext, reference: WorkshopPaidInstalledTextReference) throws {
        guard context.market == .china, context.session.accountID > 0 else { throw WorkshopPaidProfessionalIssue.invalid }
        self.storage = storage; ownedDraftID = reference.ownedDraftID; licenseID = reference.item.licenseId
        ownerKey = [context.baseURL.absoluteString, context.session.namespace, String(context.session.accountID), licenseID, String(ownedDraftID)]
            .map { "\($0.utf8.count):\($0)" }.joined(separator: ":")
    }
    private var key: String { "workshop-paid-professional.pending.v1." + Data(ownerKey.utf8).base64EncodedString() }
    private struct Record: Codable {
        let schema, ownerKey: String
        let command: WorkshopPaidProfessionalCommand
        private enum CodingKeys: String, CodingKey { case schema, ownerKey, command }
        init(ownerKey: String, command: WorkshopPaidProfessionalCommand) { schema = "w18-paid-professional-pending-v1"; self.ownerKey = ownerKey; self.command = command }
        init(from decoder: Decoder) throws {
            try WorkshopPaidInstallWire.keys(decoder, ["schema", "ownerKey", "command"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema = try c.decode(String.self, forKey: .schema); ownerKey = try c.decode(String.self, forKey: .ownerKey)
            command = try c.decode(WorkshopPaidProfessionalCommand.self, forKey: .command)
            guard schema == "w18-paid-professional-pending-v1" else { throw WorkshopPaidProfessionalIssue.storageUnavailable }
        }
    }
    public func load() throws -> WorkshopPaidProfessionalCommand? {
        do {
            guard let data = try storage.read(key) else { return nil }
            let value = try WorkshopPaidInstallWire.decode(Record.self, data: data, maximum: 16_384)
            guard WorkshopPaidInstallWire.same(value.ownerKey, ownerKey), value.command.ownedDraftId == ownedDraftID, value.command.licenseId == licenseID else { throw WorkshopPaidProfessionalIssue.storageUnavailable }
            return value.command
        } catch { throw WorkshopPaidProfessionalIssue.storageUnavailable }
    }
    /// Save and byte-exact readback before dispatch. An unresolved command cannot be overwritten.
    public func save(_ command: WorkshopPaidProfessionalCommand) throws {
        guard command.ownedDraftId == ownedDraftID, command.licenseId == licenseID else { throw WorkshopPaidProfessionalIssue.invalid }
        if let old = try load() {
            guard try old.wireData() == command.wireData() else { throw WorkshopPaidProfessionalIssue.pendingConflict }; return
        }
        do {
            try storage.write(JSONEncoder().encode(Record(ownerKey: ownerKey, command: command)), key: key)
            guard let saved = try load(), try saved.wireData() == command.wireData() else { throw WorkshopPaidProfessionalIssue.storageUnavailable }
        } catch { throw WorkshopPaidProfessionalIssue.storageUnavailable }
    }
    public func acknowledge(_ history: WorkshopPaidProfessionalOperation) throws {
        guard history.state.terminal, let old = try load(), history.matches(old) else { throw WorkshopPaidProfessionalIssue.pendingConflict }
        do { try storage.remove(key); guard try storage.read(key) == nil else { throw WorkshopPaidProfessionalIssue.storageUnavailable } }
        catch { throw WorkshopPaidProfessionalIssue.storageUnavailable }
    }
    // No "clear unknown" operation. Back/logout/cancellation cannot imply the server rolled back.
}
