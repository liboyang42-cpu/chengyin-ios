import Foundation

/// Host-level coordinator bridging play-surface interactions to `RunAuthorityProjection`
/// and `RunActionIntent` under `ReformWorldCapabilities` (reform plan v9 §6 / W03.1–W03.3).
///
/// All operations are gated behind `ReformWorldCapabilities.disabled` by default (`runAuthority` OFF)
/// and perform zero network or persistence I/O.
public final class RunAuthorityHostCoordinator {
    public enum State: Equatable, Sendable {
        case disabled
        case ready
        case inFlight(RunActionIntent)
        case unknownOutcome(RunActionIntent)
        case refreshRequired(serverVersion: Int64)
        case rejected(reasonCode: String)
        case payloadConflict
    }

    public static let forbiddenClientFields: Set<String> = [
        "reward", "score", "completed", "completion", "timestamp"
    ]

    public let capabilities: ReformWorldCapabilities
    public private(set) var projection: RunAuthorityProjection
    public private(set) var state: State
    public private(set) var lastOutcome: RunAuthorityProjection.Outcome?

    public init(
        projection: RunAuthorityProjection,
        capabilities: ReformWorldCapabilities = .disabled
    ) {
        self.projection = projection
        self.capabilities = capabilities
        self.state = capabilities.allows(.runAuthority) ? .ready : .disabled
    }

    public var isEnabled: Bool {
        capabilities.allows(.runAuthority) && state != .disabled
    }

    public var pendingIntent: RunActionIntent? {
        projection.pending
    }

    /// Validates and builds a `RunActionIntent` for one of the typed `RunActionPayload` interaction kinds,
    /// ensuring the canonical body carries no client-reported reward, score, completion or timestamp fields,
    /// and begins the intent on `RunAuthorityProjection` with CAS `expectedStateVersion` checks.
    @discardableResult
    public func beginAction(
        nodeId: String,
        expectedStateVersion: Int64? = nil,
        payload: RunActionPayload,
        requestId: String = UUID().uuidString
    ) throws -> RunActionIntent {
        guard isEnabled else { throw RunAuthorityIssue.invalid }
        let targetVersion = expectedStateVersion ?? projection.stateVersion
        let intent = try RunActionIntent(
            runId: projection.runId,
            nodeId: nodeId,
            expectedStateVersion: targetVersion,
            payload: payload,
            requestId: requestId
        )
        try Self.verifyNoClientRewardOrTimestamp(in: intent)
        do {
            try projection.begin(intent)
        } catch RunAuthorityIssue.payloadConflict {
            state = .payloadConflict
            throw RunAuthorityIssue.payloadConflict
        }
        state = .inFlight(intent)
        return intent
    }

    /// Retries the currently pending intent by reusing the exact same `requestId` and payload.
    /// Any attempt to retry with a modified payload or mismatched `requestId` surfaces `.payloadConflict`.
    @discardableResult
    public func retryPending(_ intent: RunActionIntent) throws -> RunActionIntent {
        guard isEnabled else { throw RunAuthorityIssue.invalid }
        guard projection.pending != nil else { throw RunAuthorityIssue.invalid }
        try Self.verifyNoClientRewardOrTimestamp(in: intent)
        do {
            try projection.begin(intent)
        } catch RunAuthorityIssue.payloadConflict {
            state = .payloadConflict
            throw RunAuthorityIssue.payloadConflict
        }
        state = .inFlight(intent)
        return intent
    }

    /// Resolves the in-flight intent using the server receipt (or `nil` when the response was lost).
    /// - `nil` keeps `pending` intact and transitions to `.unknownOutcome(intent)`.
    /// - `.conflict` clears `pending` and transitions to `.refreshRequired(serverVersion:)`.
    /// - `.payloadConflict` clears `pending`, transitions to `.payloadConflict`, and throws `RunAuthorityIssue.payloadConflict`.
    @discardableResult
    public func resolve(_ receipt: RunActionReceipt?) throws -> RunAuthorityProjection.Outcome {
        guard isEnabled else { throw RunAuthorityIssue.invalid }
        do {
            let outcome = try projection.resolve(receipt)
            lastOutcome = outcome
            switch outcome {
            case .applied:
                state = .ready
            case .refreshRequired(let serverVersion):
                state = .refreshRequired(serverVersion: serverVersion)
            case .rejected(let reasonCode):
                state = .rejected(reasonCode: reasonCode)
            case .unknown:
                if let pending = projection.pending {
                    state = .unknownOutcome(pending)
                }
            }
            return outcome
        } catch RunAuthorityIssue.payloadConflict {
            state = .payloadConflict
            throw RunAuthorityIssue.payloadConflict
        }
    }

    /// Adopts a server snapshot when `snapshotVersion > projection.stateVersion`.
    /// Late or equal-version snapshots are ignored (`false`).
    /// If an intent is still pending, it survives the newer snapshot until `clearPending(after:)` is called with its receipt.
    @discardableResult
    public func adoptSnapshot(
        version: Int64,
        status: GameRunStatus,
        nodes: [String: RunNodeStatus]
    ) throws -> Bool {
        guard isEnabled else { throw RunAuthorityIssue.invalid }
        let adopted = try projection.adopt(snapshotVersion: version, status: status, nodes: nodes)
        if adopted {
            if let pending = projection.pending {
                state = .unknownOutcome(pending)
            } else {
                state = .ready
            }
        }
        return adopted
    }

    /// Clears a surviving pending intent after a newer snapshot only once its authoritative receipt is read back.
    public func clearPending(after receipt: RunActionReceipt) throws {
        guard isEnabled else { throw RunAuthorityIssue.invalid }
        try projection.clearPending(after: receipt)
        if receipt.decision == .payloadConflict {
            state = .payloadConflict
            throw RunAuthorityIssue.payloadConflict
        }
        state = .ready
    }

    /// Verifies that the canonical JSON body of `RunActionIntent` contains no client-supplied reward,
    /// score, completion or timestamp fields (W03.3).
    public static func verifyNoClientRewardOrTimestamp(in intent: RunActionIntent) throws {
        let data = try intent.body()
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunAuthorityIssue.invalid
        }
        for key in object.keys where forbiddenClientFields.contains(key.lowercased()) {
            throw RunAuthorityIssue.clientReward
        }
        if let payloadFields = object["payload"] as? [String: Any] {
            for key in payloadFields.keys where forbiddenClientFields.contains(key.lowercased()) {
                throw RunAuthorityIssue.clientReward
            }
        }
    }
}
