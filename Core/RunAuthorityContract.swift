import Foundation

/// Reform plan v9 §6 / W03: the client reports intents and evidence; the server
/// decides transitions. This contract keeps the App from advancing a run on a
/// local animation, timestamp or cache. Proposed operations (StartRun, GetRun,
/// SubmitAction, ResumeRun, GetReceipt) are not reviewed endpoints yet, so the
/// types below build and validate bodies but perform no I/O.
public enum RunAuthorityIssue: Error, Equatable {
    case invalid, unknownField, oversize, clientReward, staleVersion, terminal, receiptMismatch, payloadConflict
}

public enum GameRunStatus: String, Decodable, Sendable {
    case created = "CREATED", active = "ACTIVE", paused = "PAUSED", completed = "COMPLETED", abandoned = "ABANDONED", expired = "EXPIRED"
    public var isTerminal: Bool { [.completed, .abandoned, .expired].contains(self) }
}

public enum RunNodeStatus: String, Decodable, Sendable {
    case locked = "LOCKED", available = "AVAILABLE", inProgress = "IN_PROGRESS", succeeded = "SUCCEEDED", failed = "FAILED", skipped = "SKIPPED"
    public var isTerminal: Bool { [.succeeded, .failed, .skipped].contains(self) }
}

/// W03.3: the first five interaction kinds. Each has its own schema version and typed payload.
public enum RunActionPayload: Equatable, Sendable {
    case choice(optionId: String)
    case answer(text: String)
    case arrival(evidenceRef: String)
    case scan(evidenceRef: String)
    case itemUse(entitlementId: String)
    case npcClue(clueId: String)

    public var kind: String {
        switch self {
        case .choice: return "CHOICE"
        case .answer: return "ANSWER"
        case .arrival: return "GEO_ARRIVAL"
        case .scan: return "SCAN_CONFIRM"
        case .itemUse: return "ITEM_USE"
        case .npcClue: return "NPC_CLUE"
        }
    }
    static let schemaVersion = 1
    fileprivate var fields: [String: String] {
        switch self {
        case .choice(let v): return ["optionId": v]
        case .answer(let v): return ["text": v]
        case .arrival(let v), .scan(let v): return ["evidenceRef": v]
        case .itemUse(let v): return ["entitlementId": v]
        case .npcClue(let v): return ["clueId": v]
        }
    }
    func validate() throws {
        switch self {
        case .answer(let text):
            guard ReformWire.label(text, limit: 500) else { throw RunAuthorityIssue.oversize }
        default:
            guard fields.values.allSatisfy(ReformWire.id) else { throw RunAuthorityIssue.invalid }
        }
    }
}

/// Exact SubmitAction body. No reward, score, completion flag or timestamp is client-supplied.
public struct RunActionIntent: Equatable, Sendable {
    public let runId, nodeId, requestId: String
    public let expectedStateVersion: Int64
    public let payload: RunActionPayload
    public init(runId: String, nodeId: String, expectedStateVersion: Int64, payload: RunActionPayload, requestId: String = UUID().uuidString) throws {
        guard ReformWire.id(runId), ReformWire.id(nodeId), ReformWire.requestID(requestId), ReformWire.version(expectedStateVersion) else { throw RunAuthorityIssue.invalid }
        try payload.validate()
        self.runId = runId; self.nodeId = nodeId; self.requestId = requestId; self.expectedStateVersion = expectedStateVersion; self.payload = payload
    }
    /// Canonical JSON with sorted keys; also the input of `payloadDigest`.
    public func body() throws -> Data {
        let object: [String: Any] = [
            "runId": runId, "nodeId": nodeId, "requestId": requestId, "expectedStateVersion": expectedStateVersion,
            "kind": payload.kind, "schemaVersion": RunActionPayload.schemaVersion, "payload": payload.fields
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    /// Retrying keeps requestId AND identical semantics; a different payload under
    /// the same requestId is a client bug the server will reject.
    public func sameIntent(as other: RunActionIntent) -> Bool {
        runId == other.runId && nodeId == other.nodeId && expectedStateVersion == other.expectedStateVersion && payload == other.payload
    }
}

/// Server receipt for one SubmitAction / GetReceipt.
public struct RunActionReceipt: Decodable, Equatable, Sendable {
    public enum Decision: String, Decodable, Sendable { case applied = "APPLIED", rejected = "REJECTED", conflict = "VERSION_CONFLICT", payloadConflict = "PAYLOAD_CONFLICT" }
    public let runId, requestId: String
    public let decision: Decision
    public let stateVersion: Int64
    public let runStatus: GameRunStatus
    public let nodeId: String
    public let nodeStatus: RunNodeStatus
    public let safeToRetry: Bool
    public let reasonCode: String?
    public func validate(for intent: RunActionIntent) throws {
        guard runId == intent.runId, requestId == intent.requestId, nodeId == intent.nodeId, ReformWire.version(stateVersion) else { throw RunAuthorityIssue.receiptMismatch }
        switch decision {
        case .applied: guard stateVersion == intent.expectedStateVersion + 1, !safeToRetry else { throw RunAuthorityIssue.receiptMismatch }
        case .rejected: guard stateVersion == intent.expectedStateVersion, reasonCode.map({ ReformWire.label($0, limit: 64) }) == true else { throw RunAuthorityIssue.receiptMismatch }
        case .conflict: guard stateVersion != intent.expectedStateVersion else { throw RunAuthorityIssue.receiptMismatch }
        case .payloadConflict: guard !safeToRetry else { throw RunAuthorityIssue.receiptMismatch }
        }
    }
}

/// Local projection of a run. Only server snapshots and validated receipts move it;
/// versions never go backwards and terminal states are not overwritten by ordinary updates.
public struct RunAuthorityProjection: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case applied
        /// Refresh from the server, then re-express the intent with the new version.
        case refreshRequired(serverVersion: Int64)
        case rejected(reasonCode: String)
        /// Unknown result: retry with the SAME intent, or read the receipt by requestId.
        case unknown
    }
    public let runId: String
    public private(set) var stateVersion: Int64
    public private(set) var status: GameRunStatus
    public private(set) var nodes: [String: RunNodeStatus]
    /// The one in-flight intent, persisted by callers before dispatch.
    public private(set) var pending: RunActionIntent?

    public init(runId: String, stateVersion: Int64, status: GameRunStatus, nodes: [String: RunNodeStatus]) throws {
        guard ReformWire.id(runId), ReformWire.version(stateVersion), nodes.count <= 500, nodes.keys.allSatisfy(ReformWire.id) else { throw RunAuthorityIssue.invalid }
        self.runId = runId; self.stateVersion = stateVersion; self.status = status; self.nodes = nodes
    }

    public mutating func begin(_ intent: RunActionIntent) throws {
        guard intent.runId == runId else { throw RunAuthorityIssue.invalid }
        guard !status.isTerminal, status != .paused else { throw RunAuthorityIssue.terminal }
        if let pending { guard pending.sameIntent(as: intent), pending.requestId == intent.requestId else { throw RunAuthorityIssue.payloadConflict }; return }
        guard intent.expectedStateVersion == stateVersion else { throw RunAuthorityIssue.staleVersion }
        guard let node = nodes[intent.nodeId], node == .available || node == .inProgress else { throw RunAuthorityIssue.invalid }
        pending = intent
    }

    public mutating func resolve(_ receipt: RunActionReceipt?) throws -> Outcome {
        guard let intent = pending else { throw RunAuthorityIssue.invalid }
        guard let receipt else { return .unknown } // keep pending; never infer success.
        try receipt.validate(for: intent)
        switch receipt.decision {
        case .applied:
            pending = nil
            if receipt.stateVersion > stateVersion { apply(version: receipt.stateVersion, status: receipt.runStatus, node: receipt.nodeId, nodeStatus: receipt.nodeStatus) }
            return .applied
        case .rejected:
            pending = nil
            return .rejected(reasonCode: receipt.reasonCode ?? "")
        case .conflict:
            pending = nil
            return .refreshRequired(serverVersion: receipt.stateVersion)
        case .payloadConflict:
            pending = nil
            throw RunAuthorityIssue.payloadConflict
        }
    }

    /// Resume / GetRun snapshot. Older or equal versions are ignored (late responses).
    @discardableResult
    public mutating func adopt(snapshotVersion: Int64, status newStatus: GameRunStatus, nodes newNodes: [String: RunNodeStatus]) throws -> Bool {
        guard ReformWire.version(snapshotVersion), newNodes.keys.allSatisfy(ReformWire.id) else { throw RunAuthorityIssue.invalid }
        guard snapshotVersion > stateVersion else { return false }
        if status.isTerminal, newStatus != status { throw RunAuthorityIssue.terminal }
        // A pending intent survives a newer snapshot: callers read GetReceipt(requestId)
        // and use clearPending(after:) rather than assuming it was or was not applied.
        stateVersion = snapshotVersion; status = newStatus; nodes = newNodes
        return true
    }

    /// After a newer snapshot, the pending intent can only be cleared once its receipt is read.
    public mutating func clearPending(after receipt: RunActionReceipt) throws {
        guard let intent = pending else { return }
        try receipt.validate(for: intent)
        pending = nil
    }

    private mutating func apply(version: Int64, status newStatus: GameRunStatus, node: String, nodeStatus: RunNodeStatus) {
        stateVersion = version
        if !status.isTerminal { status = newStatus }
        if let current = nodes[node], current.isTerminal { return }
        nodes[node] = nodeStatus
    }
}
