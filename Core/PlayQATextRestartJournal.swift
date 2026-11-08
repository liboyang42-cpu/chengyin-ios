import Foundation

/// Local encrypted-slot binding. Uses the existing exact recovery owner and run
/// scope; a fresh auth epoch may read it, but another role/realm/account may not.
public struct PlayQATextRestartContext: Codable, Equatable {
    public let owner: PlayRecoveryOwner
    public let deployment: String
    public let routeKey: String
    public let activityID: Int
    public let topicID: Int
    public let nodeID: Int

    public init(configuration: APIConfiguration, session: PlayExperienceSession, scope: PlaySessionScope,
                activityID: Int, topicID: Int, nodeID: Int) throws {
        guard scope.isValid, session.accountID > 0, !session.namespace.isEmpty, !session.role.isEmpty,
              activityID >= 0, topicID > 0, nodeID > 0 else { throw PlayExperienceError.persistenceUnavailable }
        switch scope {
        case .activity(let id): guard activityID == id else { throw PlayExperienceError.persistenceUnavailable }
        case .topic(let id): guard activityID == 0, topicID == id else { throw PlayExperienceError.persistenceUnavailable }
        }
        owner = .init(session: session); deployment = configuration.baseURL.absoluteString
        routeKey = PlayRunStorageKey.make(session: session, scope: scope)
        self.activityID = activityID; self.topicID = topicID; self.nodeID = nodeID
    }
    public var storageBinding: String {
        // Role and expected topic/activity are checked INSIDE the record. They
        // must not create a fresh empty slot around an older unresolved lock.
        let fields = [deployment, routeKey, String(nodeID)]
        return "play.qa-text.receipt.v1:" + fields.map { "\($0.utf8.count):\($0)" }.joined()
    }
    public func matches(_ request: PlayQATextReceiptRequest) -> Bool {
        request.activityID == activityID && request.topicID == topicID && request.nodeID == nodeID
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.owner == rhs.owner && lhs.deployment.utf8.elementsEqual(rhs.deployment.utf8) &&
        lhs.routeKey.utf8.elementsEqual(rhs.routeKey.utf8) && lhs.activityID == rhs.activityID &&
        lhs.topicID == rhs.topicID && lhs.nodeID == rhs.nodeID
    }
}

/// Version is the local file schema, never a backend field. The record is written
/// before a possible POST and therefore always means unresolved, even if a crash
/// happened before transport. It must never authorize POST replay.
public struct PlayQATextRestartRecord: Codable, Equatable {
    public let schema: Int
    public let context: PlayQATextRestartContext
    public let request: PlayQATextReceiptRequest
    public init(pending: PlayAdvancedPending, qa: PlayWireValue, context: PlayQATextRestartContext) throws {
        guard PlayQATextActionReceipt.matchesTextMode(qa) else { throw PlayExperienceError.unsupported }
        schema = 1; self.context = context
        request = try .init(pending, activityID: context.activityID, topicID: context.topicID, nodeID: context.nodeID)
        try validate(context: context)
    }
    public func validate(context expected: PlayQATextRestartContext) throws {
        guard schema == 1, context == expected, context.matches(request) else { throw PlayExperienceError.persistenceUnavailable }
        try request.validate()
    }
}

public struct PlayQATextRestartSnapshot: Equatable {
    public let value: PlayQATextRestartRecord
    public let generation: Data
    let persistedBytes: Data
    init(value: PlayQATextRestartRecord, generation: Data, persistedBytes: Data) {
        self.value = value; self.generation = generation; self.persistedBytes = persistedBytes
    }
}

/// The reviewed AES-GCM adapter is provided as a precise shared-file patch. This
/// protocol itself grants neither OS durability provenance nor network authority.
@MainActor public protocol PlayQATextRestartJournal: AnyObject {
    var context: PlayQATextRestartContext { get }
    func read() async throws -> PlayQATextRestartSnapshot?
    func reserve(_ record: PlayQATextRestartRecord) async throws -> PlayQATextRestartSnapshot
    func clear(_ snapshot: PlayQATextRestartSnapshot) async throws
}

@MainActor public protocol PlayQATextReceiptReading {
    func qaTextReceipt(_ identity: PlayQATextReceiptRequest, token: String) async throws -> PlayQATextActionReceipt
}
