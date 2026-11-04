import Foundation

/// Recovery metadata only: no token, credential, server response or unit redemption code.
/// The injected app storage must provide durable synchronous writes.
@MainActor public final class FreeExploreLaunchPendingStore {
    private let storage: any TemplateAuthoringStorage
    private let ownerKey: String
    let accountID: FreeExploreLaunchID
    private var key: String { "free-explore-launch.pending.v1." + Data(ownerKey.utf8).base64EncodedString() }
    private struct Record: Codable {
        let version: Int
        let ownerKey: String
        let command: FreeExploreLaunchReservationCommand
    }
    public init(storage: any TemplateAuthoringStorage, session: FreeExploreLaunchSession) {
        self.storage = storage; ownerKey = session.ownerKey; accountID = session.accountID
    }
    func matches(_ session: FreeExploreLaunchSession) -> Bool { ownerKey == session.ownerKey }
    public func load() throws -> FreeExploreLaunchReservationCommand? {
        do {
            guard let data = try storage.read(key) else { return nil }
            guard data.count <= 16_384 else { throw FreeExploreLaunchFailure.storageUnavailable }
            let record = try JSONDecoder().decode(Record.self, from: data)
            guard record.version == 1, record.ownerKey == ownerKey else { throw FreeExploreLaunchFailure.storageUnavailable }
            try record.command.validate(); return record.command
        } catch { throw FreeExploreLaunchFailure.storageUnavailable }
    }
    /// Do not replace any unresolved operation, including one for another order.
    func save(_ command: FreeExploreLaunchReservationCommand) throws {
        try command.validate()
        if let previous = try load() {
            guard previous == command else { throw FreeExploreLaunchFailure.pendingConflict }
            return
        }
        do {
            let data = try JSONEncoder().encode(Record(version: 1, ownerKey: ownerKey, command: command))
            try storage.write(data, key: key)
            guard try load() == command else { throw FreeExploreLaunchFailure.storageUnavailable }
        } catch { throw FreeExploreLaunchFailure.storageUnavailable }
    }
    /// Only a matching receipt AND the same owned order may release the replay lock.
    func acknowledge(receipt: FreeExploreLaunchReservation, order: FreeExploreLaunchOrder) throws {
        guard let command = try load(), receipt.matches(command, owner: accountID) else { throw FreeExploreLaunchFailure.pendingConflict }
        try order.validate(owner: accountID, registration: command.registrationId)
        guard order.bundle?.reservations.contains(where: {
            $0.id == receipt.id && $0.matches(command, owner: accountID)
        }) == true else { throw FreeExploreLaunchFailure.pendingConflict }
        do {
            try storage.remove(key)
            guard try storage.read(key) == nil else { throw FreeExploreLaunchFailure.storageUnavailable }
        } catch { throw FreeExploreLaunchFailure.storageUnavailable }
    }
}
