import Foundation

/// Local upgrade-draft file for one purchased license. No license minting, no network,
/// no installed-release or running-session mutation. A receipt exists only after the
/// bytes just written are read back unchanged.
public enum WorkshopUpgradeDraftIssue: Error, Equatable {
    case invalid, staleLease, stalePresentation, saveFailed, conflict, revoked, unavailable
}

/// Current account scope. Holds no token and no purchase credential.
public struct WorkshopUpgradeAccountLease: Equatable, Sendable {
    public let accountID: Int64
    public let namespace: String
    public let realm: String
    public let epoch: UInt64
    public init(accountID: Int64, namespace: String, realm: String, epoch: UInt64) throws {
        guard accountID > 0, WorkshopUpgradeDraftWire.scope(namespace, 128), WorkshopUpgradeDraftWire.scope(realm, 256), !realm.contains("@") else { throw WorkshopUpgradeDraftIssue.invalid }
        self.accountID = accountID
        self.namespace = namespace
        self.realm = realm
        self.epoch = epoch
    }
}

@MainActor public final class WorkshopUpgradeAccountGate {
    public let lease: WorkshopUpgradeAccountLease
    private var revoked = false
    public init(_ lease: WorkshopUpgradeAccountLease) { self.lease = lease }
    public func revoke() { revoked = true }
    public var isCurrent: Bool { !revoked }
    public func check() throws { guard !revoked else { throw WorkshopUpgradeDraftIssue.staleLease } }
}

public struct WorkshopUpgradeDraftReceipt: Equatable, Sendable {
    public let requestId, licenseId, moduleId, fromVersionId, toVersionId, fromContentHash, toContentHash: String
    public let addedCapabilities, removedCapabilities: [String]
    public let persisted: Bool
}

@MainActor public protocol WorkshopUpgradeDraftWriting: AnyObject {
    func read(_ key: String) throws -> Data?
    func writeAtomic(_ key: String, _ data: Data) throws
    func remove(_ key: String) throws
}

@MainActor public final class WorkshopUpgradeDraftDirectory: WorkshopUpgradeDraftWriting {
    private let root: URL
    public init(root: URL) { self.root = root }
    private func file(_ key: String) throws -> URL {
        guard WorkshopUpgradeDraftWire.fileKey(key) else { throw WorkshopUpgradeDraftIssue.invalid }
        return root.appendingPathComponent(key, isDirectory: false)
    }
    public func read(_ key: String) throws -> Data? {
        let url = try file(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true, let size = values.fileSize, (1...16_384).contains(size) else { throw WorkshopUpgradeDraftIssue.saveFailed }
        return try Data(contentsOf: url)
    }
    public func writeAtomic(_ key: String, _ data: Data) throws {
        guard (1...16_384).contains(data.count) else { throw WorkshopUpgradeDraftIssue.saveFailed }
        let url = try file(key)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true { throw WorkshopUpgradeDraftIssue.saveFailed }
        try data.write(to: url, options: .atomic)
        let readBack = try Data(contentsOf: url)
        guard readBack == data else {
            try? FileManager.default.removeItem(at: url)
            throw WorkshopUpgradeDraftIssue.saveFailed
        }
    }
    public func remove(_ key: String) throws {
        let url = try file(key)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

public struct WorkshopUpgradeDraftRecord: Equatable, Sendable {
    public let schema: String
    public let accountID: Int64
    public let namespace, realm: String
    public let epoch: UInt64
    public let licenseId, moduleId, fromVersionId, toVersionId, fromContentHash, toContentHash, requestId: String
    public let addedCapabilities, removedCapabilities: [String]
    init(lease: WorkshopUpgradeAccountLease, item: WorkshopPurchasedItem, presentation: WorkshopModUpgradePresentation, request: WorkshopUpgradeDraftRequest) throws {
        guard item.status != .revoked else { throw WorkshopUpgradeDraftIssue.revoked }
        guard item.licenseId == request.licenseId,
              item.moduleId == presentation.preview.installed.moduleId,
              item.purchasedVersionId == presentation.preview.installed.versionId,
              item.purchasedVersionId == request.fromVersionId,
              item.contentHash == presentation.preview.installed.contentHash,
              request.toVersionId == presentation.preview.candidate.versionId,
              request.toContentHash == presentation.preview.candidate.contentHash,
              request.fromVersionId != request.toVersionId,
              item.contentHash != request.toContentHash,
              Set(presentation.addedCapabilities) == presentation.preview.addedCapabilities,
              Set(presentation.removedCapabilities) == presentation.preview.removedCapabilities
        else { throw WorkshopUpgradeDraftIssue.invalid }
        schema = "workshop-upgrade-draft-v1"
        accountID = lease.accountID
        namespace = lease.namespace
        realm = lease.realm
        epoch = lease.epoch
        licenseId = item.licenseId
        moduleId = item.moduleId
        fromVersionId = item.purchasedVersionId
        toVersionId = request.toVersionId
        fromContentHash = item.contentHash
        toContentHash = request.toContentHash
        requestId = request.requestId
        addedCapabilities = presentation.addedCapabilities
        removedCapabilities = presentation.removedCapabilities
    }
    init(schema: String, accountID: Int64, namespace: String, realm: String, epoch: UInt64, licenseId: String, moduleId: String, fromVersionId: String, toVersionId: String, fromContentHash: String, toContentHash: String, requestId: String, addedCapabilities: [String], removedCapabilities: [String]) {
        self.schema = schema
        self.accountID = accountID
        self.namespace = namespace
        self.realm = realm
        self.epoch = epoch
        self.licenseId = licenseId
        self.moduleId = moduleId
        self.fromVersionId = fromVersionId
        self.toVersionId = toVersionId
        self.fromContentHash = fromContentHash
        self.toContentHash = toContentHash
        self.requestId = requestId
        self.addedCapabilities = addedCapabilities
        self.removedCapabilities = removedCapabilities
    }
    /// Same upgrade decision, including a repeated confirm that minted a new request id.
    public func sameDecision(_ other: WorkshopUpgradeDraftRecord) -> Bool {
        schema == other.schema && accountID == other.accountID && namespace == other.namespace && realm == other.realm && epoch == other.epoch
            && licenseId == other.licenseId && moduleId == other.moduleId
            && fromVersionId == other.fromVersionId && toVersionId == other.toVersionId
            && fromContentHash == other.fromContentHash && toContentHash == other.toContentHash
            && addedCapabilities == other.addedCapabilities && removedCapabilities == other.removedCapabilities
    }
    public func makeReceipt() -> WorkshopUpgradeDraftReceipt {
        WorkshopUpgradeDraftReceipt(requestId: requestId, licenseId: licenseId, moduleId: moduleId, fromVersionId: fromVersionId, toVersionId: toVersionId, fromContentHash: fromContentHash, toContentHash: toContentHash, addedCapabilities: addedCapabilities, removedCapabilities: removedCapabilities, persisted: true)
    }
}

enum WorkshopUpgradeDraftWire {
    static func scope(_ value: String, _ max: Int) -> Bool {
        let count = value.utf8.count
        return count > 0 && count <= max && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != "\\" }
    }
    static func fileKey(_ key: String) -> Bool {
        (1...1024).contains(key.utf8.count) && key.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 || $0 == 45 || $0 == 61 }
    }
    private static func capability(_ value: String) -> Bool {
        (1...96).contains(value.utf8.count) && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != "\\" }
    }
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
    private static let fields: Set<String> = ["schema", "accountID", "namespace", "realm", "epoch", "licenseId", "moduleId", "fromVersionId", "toVersionId", "fromContentHash", "toContentHash", "requestId", "addedCapabilities", "removedCapabilities"]
    private struct Envelope: Codable, Equatable {
        var schema, namespace, realm, licenseId, moduleId, fromVersionId, toVersionId, fromContentHash, toContentHash, requestId: String
        var accountID: Int64
        var epoch: UInt64
        var addedCapabilities, removedCapabilities: [String]
    }
    static func envelope(_ record: WorkshopUpgradeDraftRecord) throws -> Data {
        let value = Envelope(schema: record.schema, namespace: record.namespace, realm: record.realm, licenseId: record.licenseId, moduleId: record.moduleId, fromVersionId: record.fromVersionId, toVersionId: record.toVersionId, fromContentHash: record.fromContentHash, toContentHash: record.toContentHash, requestId: record.requestId, accountID: record.accountID, epoch: record.epoch, addedCapabilities: record.addedCapabilities, removedCapabilities: record.removedCapabilities)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    static func decode(_ data: Data) throws -> WorkshopUpgradeDraftRecord {
        guard (1...16_384).contains(data.count), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], Set(object.keys) == fields else { throw WorkshopUpgradeDraftIssue.saveFailed }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw WorkshopUpgradeDraftIssue.saveFailed }
        guard envelope.schema == "workshop-upgrade-draft-v1", envelope.accountID > 0, scope(envelope.namespace, 128), scope(envelope.realm, 256), !envelope.realm.contains("@"),
              WorkshopPurchasedWire.license(envelope.licenseId), ReformWire.id(envelope.moduleId), ReformWire.id(envelope.fromVersionId), ReformWire.id(envelope.toVersionId),
              ReformWire.sha256(envelope.fromContentHash), ReformWire.sha256(envelope.toContentHash), envelope.fromContentHash != envelope.toContentHash, envelope.fromVersionId != envelope.toVersionId,
              ReformWire.requestID(envelope.requestId), envelope.addedCapabilities.count <= 32, envelope.removedCapabilities.count <= 32,
              envelope.addedCapabilities == envelope.addedCapabilities.sorted(), envelope.removedCapabilities == envelope.removedCapabilities.sorted(),
              Set(envelope.addedCapabilities).count == envelope.addedCapabilities.count, Set(envelope.removedCapabilities).count == envelope.removedCapabilities.count,
              envelope.addedCapabilities.allSatisfy(capability), envelope.removedCapabilities.allSatisfy(capability)
        else { throw WorkshopUpgradeDraftIssue.saveFailed }
        return WorkshopUpgradeDraftRecord(schema: envelope.schema, accountID: envelope.accountID, namespace: envelope.namespace, realm: envelope.realm, epoch: envelope.epoch, licenseId: envelope.licenseId, moduleId: envelope.moduleId, fromVersionId: envelope.fromVersionId, toVersionId: envelope.toVersionId, fromContentHash: envelope.fromContentHash, toContentHash: envelope.toContentHash, requestId: envelope.requestId, addedCapabilities: envelope.addedCapabilities, removedCapabilities: envelope.removedCapabilities)
    }
}

@MainActor public final class WorkshopUpgradeDraftStore {
    private let writer: any WorkshopUpgradeDraftWriting
    private let gate: WorkshopUpgradeAccountGate
    public init(writer: any WorkshopUpgradeDraftWriting, gate: WorkshopUpgradeAccountGate) {
        self.writer = writer
        self.gate = gate
    }
    public func checkLease() throws { try gate.check() }
    var currentLease: WorkshopUpgradeAccountLease { gate.lease }
    var leaseIsCurrent: Bool { gate.isCurrent }
    private func key(_ licenseId: String) -> String {
        let lease = gate.lease
        let raw = "\(lease.accountID)\n\(lease.namespace)\n\(lease.realm)\n\(lease.epoch)\n\(licenseId)"
        return Data(raw.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
    }
    private func bound(_ record: WorkshopUpgradeDraftRecord, item: WorkshopPurchasedItem) throws {
        guard record.accountID == gate.lease.accountID, record.namespace == gate.lease.namespace, record.realm == gate.lease.realm, record.epoch == gate.lease.epoch else { throw WorkshopUpgradeDraftIssue.staleLease }
        guard record.licenseId == item.licenseId, record.moduleId == item.moduleId, record.fromVersionId == item.purchasedVersionId, record.fromContentHash == item.contentHash else { throw WorkshopUpgradeDraftIssue.invalid }
    }
    public func load(item: WorkshopPurchasedItem) throws -> WorkshopUpgradeDraftRecord? {
        try gate.check()
        guard item.status != .revoked else { throw WorkshopUpgradeDraftIssue.revoked }
        guard let data = try writer.read(key(item.licenseId)) else { return nil }
        let record = try WorkshopUpgradeDraftWire.decode(data)
        try bound(record, item: item)
        return record
    }
    /// Writes one file per account and license. A repeated confirm returns the stored receipt and does not create another file.
    /// ponytail: check-then-write is single-process. Whole-file replace stays atomic; add a file lock if two processes share this directory.
    public func save(item: WorkshopPurchasedItem, presentation: WorkshopModUpgradePresentation, request: WorkshopUpgradeDraftRequest) throws -> WorkshopUpgradeDraftReceipt {
        try gate.check()
        let record = try WorkshopUpgradeDraftRecord(lease: gate.lease, item: item, presentation: presentation, request: request)
        let storageKey = key(item.licenseId)
        if let existingData = try writer.read(storageKey) {
            let existing = try WorkshopUpgradeDraftWire.decode(existingData)
            try bound(existing, item: item)
            guard existing.sameDecision(record) else { throw WorkshopUpgradeDraftIssue.conflict }
            return existing.makeReceipt()
        }
        let data: Data
        do { data = try WorkshopUpgradeDraftWire.envelope(record) } catch { throw WorkshopUpgradeDraftIssue.saveFailed }
        do { try writer.writeAtomic(storageKey, data) } catch { throw WorkshopUpgradeDraftIssue.saveFailed }
        let readBack: Data
        do {
            guard let loaded = try writer.read(storageKey) else { throw WorkshopUpgradeDraftIssue.saveFailed }
            readBack = loaded
        } catch {
            try? writer.remove(storageKey)
            throw WorkshopUpgradeDraftIssue.saveFailed
        }
        guard readBack == data else {
            try? writer.remove(storageKey)
            throw WorkshopUpgradeDraftIssue.saveFailed
        }
        let stored: WorkshopUpgradeDraftRecord
        do { stored = try WorkshopUpgradeDraftWire.decode(readBack) } catch {
            try? writer.remove(storageKey)
            throw WorkshopUpgradeDraftIssue.saveFailed
        }
        guard stored == record else {
            try? writer.remove(storageKey)
            throw WorkshopUpgradeDraftIssue.saveFailed
        }
        return stored.makeReceipt()
    }
}
