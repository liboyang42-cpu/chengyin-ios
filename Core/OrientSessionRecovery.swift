import Foundation

public enum OrientSessionOperation: Codable, Equatable {
    case prepare
    case start(sessionID: Int, ackConfigVersion: Int)
    case abandon(sessionID: Int)
    case task(sessionID: Int, taskID: Int, alternative: OrientSessionAlternativeType?)
    case settle(sessionID: Int)
    case alternative(sessionID: Int, taskID: Int, playInstanceID: String?, evidence: OrientSessionAlternativeEvidence)

    public var sessionID: Int? {
        switch self {
        case .prepare: return nil
        case .start(let id, _), .abandon(let id), .task(let id, _, _), .settle(let id), .alternative(let id, _, _, _): return id
        }
    }
    func validate() throws {
        guard sessionID == nil || sessionID! > 0 else { throw APIError.invalidRequest }
        switch self {
        case .start(_, let version): guard version >= 0 else { throw APIError.invalidRequest }
        case .task(_, let task, _): guard task > 0 else { throw APIError.invalidRequest }
        case .alternative(_, let task, let instance, let evidence):
            guard task > 0, instance == nil || (!instance!.isEmpty && instance!.utf8.count <= 128) else { throw APIError.invalidRequest }
            try evidence.validate()
        default: break
        }
    }
}

/// Durable owner identity omits tokens and process epochs. Namespace must include
/// the reviewed deployment/market/bundle/realm. Role never confers authorization.
public struct OrientSessionRecoveryOwner: Codable, Equatable {
    public let namespace: String
    public let accountID: Int
    public let role: String
    public init(namespace: String, accountID: Int, role: String) throws {
        guard !namespace.isEmpty, namespace.utf8.count <= 2048, accountID > 0,
              ["player", "club", "merchant"].contains(role) else { throw APIError.invalidRequest }
        self.namespace = namespace; self.accountID = accountID; self.role = role
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8)
            && lhs.role.utf8.elementsEqual(rhs.role.utf8)
    }
    func validate() throws { _ = try Self(namespace: namespace, accountID: accountID, role: role) }
}

public struct OrientSessionPending: Codable, Equatable {
    public let version: Int
    public let owner: OrientSessionRecoveryOwner
    public let scope: OrientSessionScope
    public let key: String
    public let operation: OrientSessionOperation
    public init(owner: OrientSessionRecoveryOwner, scope: OrientSessionScope, key: String, operation: OrientSessionOperation) throws {
        self.version = 1; self.owner = owner; self.scope = scope; self.key = key; self.operation = operation
        try validate()
    }
    func validate() throws {
        try owner.validate(); try operation.validate()
        guard version == 1, scope.topicID > 0, scope.activityID >= 0,
              (8...64).contains(key.utf8.count), key.utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [95,46,58,45].contains($0)
              }) else { throw APIError.invalidRequest }
    }
}

public enum OrientSessionFlowError: Error, Equatable {
    case staleIdentity, busy, pendingOperation, storageUnavailable, safetyBlocked
    case confirmationRequired, sessionRequired, notFinished, receiptUnresolved
    case discoveryUnavailable, sessionDiscoveryRequired, sessionSelectionRequired
}

/// Implementations must commit before send, fail on corrupt/colliding records and
/// compare the full pending command before clearing. Logout does not erase records.
@MainActor public protocol OrientSessionRecovery: AnyObject {
    func read() throws -> OrientSessionPending?
    func prepare(_ pending: OrientSessionPending) throws
    func clear(matching pending: OrientSessionPending) throws
}

/// One scoped slot. Production composition supplies an Application Support URL,
/// shared by all coordinators for this owner/topic/activity. No credentials are stored.
/// iOS evidence uses complete file protection and is excluded from backup. The
/// macOS/Linux test path uses owner-only permissions and atomic file replacement.
@MainActor public final class OrientSessionFileRecovery: OrientSessionRecovery {
    private let fileURL: URL
    public init(fileURL: URL) throws {
        guard fileURL.isFileURL, fileURL.standardizedFileURL == fileURL else { throw OrientSessionFlowError.storageUnavailable }
        self.fileURL = fileURL
    }
    public func read() throws -> OrientSessionPending? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let bytes = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            guard bytes.count <= 65_536 else { throw OrientSessionFlowError.storageUnavailable }
            let pending = try JSONDecoder().decode(OrientSessionPending.self, from: bytes)
            try pending.validate(); return pending
        } catch { throw OrientSessionFlowError.storageUnavailable }
    }
    public func prepare(_ pending: OrientSessionPending) throws {
        try pending.validate()
        guard try read() == nil else { throw OrientSessionFlowError.pendingOperation }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let bytes = try JSONEncoder().encode(pending)
            #if os(iOS) || os(tvOS) || os(watchOS)
            try bytes.write(to: fileURL, options: [.atomic, .completeFileProtection])
            var mutableURL = fileURL
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try mutableURL.setResourceValues(resources)
            #else
            try bytes.write(to: fileURL, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            guard try read() == pending else { throw OrientSessionFlowError.storageUnavailable }
        } catch { throw OrientSessionFlowError.storageUnavailable }
    }
    public func clear(matching pending: OrientSessionPending) throws {
        guard try read() == pending else { throw OrientSessionFlowError.storageUnavailable }
        do {
            try FileManager.default.removeItem(at: fileURL)
            guard try read() == nil else { throw OrientSessionFlowError.storageUnavailable }
        } catch { throw OrientSessionFlowError.storageUnavailable }
    }
}
