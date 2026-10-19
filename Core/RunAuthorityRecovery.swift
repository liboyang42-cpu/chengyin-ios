import Foundation
import CryptoKit

/// Reform plan v9 §6 / W03.1–W03.2, client recovery half. `RunAuthorityContract`
/// validates one intent and its receipt; this file adds what a real play page needs
/// around it: the GetRun snapshot shape, a journal written BEFORE dispatch so an
/// unknown outcome survives relaunch, and a coordinator that only ever moves the
/// run from a server snapshot or a validated receipt.
///
/// The proposed operations (GetRun, SubmitAction, GetReceipt) are not reviewed
/// server APIs. `RunAuthorityServing` therefore has no live implementation: the
/// App injects nothing outside DEBUG fixtures and `ReformWorldCapabilities.disabled`
/// keeps the coordinator in `.disabled` in every shipped build.

/// GetRun / ResumeRun response. Unknown statuses fail decoding instead of guessing.
public struct RunSnapshot: Decodable, Equatable, Sendable {
    public struct Node: Decodable, Equatable, Sendable {
        public let nodeId: String
        public let status: RunNodeStatus
        /// Display title from the published release; optional and never a reward or score.
        public let title: String?
    }
    public let runId: String
    public let stateVersion: Int64
    public let status: GameRunStatus
    public let releaseId: String?
    public let nodes: [Node]
    /// Server-listed action kinds the actor may express now (W03.3 kinds only).
    public let allowedKinds: [String]

    public func validate(expectedRunId: String) throws {
        guard runId == expectedRunId, ReformWire.version(stateVersion), nodes.count <= 500,
              Set(nodes.map(\.nodeId)).count == nodes.count, nodes.allSatisfy({ ReformWire.id($0.nodeId) }),
              nodes.allSatisfy({ $0.title.map { ReformWire.label($0) } ?? true }),
              releaseId.map(ReformWire.id) ?? true,
              allowedKinds.allSatisfy(RunActionPayload.knownKinds.contains) else { throw RunAuthorityIssue.invalid }
    }
    public var nodeMap: [String: RunNodeStatus] { Dictionary(uniqueKeysWithValues: nodes.map { ($0.nodeId, $0.status) }) }
}

extension RunActionPayload {
    static let knownKinds: Set<String> = ["CHOICE", "ANSWER", "GEO_ARRIVAL", "SCAN_CONFIRM", "ITEM_USE", "NPC_CLUE"]
}

/// What survives a relaunch for one dispatched intent: identifiers and a digest of the
/// canonical body only. Free-text answers, evidence and entitlement values are never
/// persisted, so a recovered intent can be read back by requestId but not resent.
public struct RunIntentJournalRecord: Codable, Equatable, Sendable {
    public let runId, nodeId, requestId, kind: String
    public let expectedStateVersion: Int64
    public let bodySHA256: String

    public init(_ intent: RunActionIntent) throws {
        runId = intent.runId; nodeId = intent.nodeId; requestId = intent.requestId; kind = intent.payload.kind
        expectedStateVersion = intent.expectedStateVersion
        bodySHA256 = SHA256.hash(data: try intent.body()).map { String(format: "%02x", $0) }.joined()
    }

    public func matches(_ intent: RunActionIntent) -> Bool { (try? RunIntentJournalRecord(intent)) == self }

    var isWellFormed: Bool {
        ReformWire.id(runId) && ReformWire.id(nodeId) && ReformWire.requestID(requestId) &&
        RunActionPayload.knownKinds.contains(kind) && ReformWire.version(expectedStateVersion) && ReformWire.sha256(bodySHA256)
    }

    /// Same identity checks `RunActionReceipt.validate(for:)` makes, for a receipt read
    /// back after relaunch when only the journal record is left.
    public func validate(_ receipt: RunActionReceipt) throws {
        guard receipt.runId == runId, receipt.requestId == requestId, receipt.nodeId == nodeId, ReformWire.version(receipt.stateVersion) else { throw RunAuthorityIssue.receiptMismatch }
        switch receipt.decision {
        case .applied: guard receipt.stateVersion == expectedStateVersion + 1, !receipt.safeToRetry else { throw RunAuthorityIssue.receiptMismatch }
        case .rejected: guard receipt.stateVersion == expectedStateVersion, receipt.reasonCode.map({ ReformWire.label($0, limit: 64) }) == true else { throw RunAuthorityIssue.receiptMismatch }
        case .conflict: guard receipt.stateVersion != expectedStateVersion else { throw RunAuthorityIssue.receiptMismatch }
        case .payloadConflict: guard !receipt.safeToRetry else { throw RunAuthorityIssue.receiptMismatch }
        }
    }
}

/// One slot per account scope and run. Implementations must fail closed: a read error
/// is reported, never treated as "nothing pending".
@MainActor public protocol RunIntentJournal: AnyObject {
    func pending(scope: String, runId: String) throws -> RunIntentJournalRecord?
    func write(_ record: RunIntentJournalRecord, scope: String) throws
    func clear(_ record: RunIntentJournalRecord, scope: String) throws
}

@MainActor public final class RunIntentDefaultsJournal: RunIntentJournal {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    private func key(_ scope: String, _ runId: String) -> String {
        "questify.run-authority.pending.v1." + Data("\(scope.utf8.count):\(scope):\(runId)".utf8).base64EncodedString()
    }
    public func pending(scope: String, runId: String) throws -> RunIntentJournalRecord? {
        guard let raw = defaults.object(forKey: key(scope, runId)) else { return nil }
        guard let data = raw as? Data, let record = try? JSONDecoder().decode(RunIntentJournalRecord.self, from: data),
              record.runId == runId, record.isWellFormed else { throw RunAuthorityIssue.invalid }
        return record
    }
    public func write(_ record: RunIntentJournalRecord, scope: String) throws {
        guard record.isWellFormed else { throw RunAuthorityIssue.invalid }
        if let existing = try pending(scope: scope, runId: record.runId), existing != record { throw RunAuthorityIssue.payloadConflict }
        let data = try JSONEncoder().encode(record), name = key(scope, record.runId)
        defaults.set(data, forKey: name)
        guard defaults.data(forKey: name) == data else { throw RunAuthorityIssue.invalid }
    }
    public func clear(_ record: RunIntentJournalRecord, scope: String) throws {
        guard try pending(scope: scope, runId: record.runId) == record else { throw RunAuthorityIssue.invalid }
        defaults.removeObject(forKey: key(scope, record.runId))
    }
}

/// Read-back result for GetReceipt(requestId).
public enum RunReceiptLookup: Equatable, Sendable {
    case found(RunActionReceipt)
    /// The server holds no receipt for this requestId: the action was never committed.
    case notFound
}

/// Proposed W03 operations. No production conformance exists; see the file header.
@MainActor public protocol RunAuthorityServing: AnyObject {
    func run(_ runId: String) async throws -> RunSnapshot
    /// `nil` means the response was lost or unreadable (unknown outcome).
    func submit(_ intent: RunActionIntent) async throws -> RunActionReceipt?
    func receipt(runId: String, requestId: String) async throws -> RunReceiptLookup
}

public enum RunAuthorityPhase: Equatable, Sendable {
    /// `ReformWorldCapabilities.runAuthority` is off (every shipped build).
    case disabled
    case idle, loading, failed
    /// The user is looking at the exact body before it is sent.
    case reviewing(RunActionIntent)
    case submitting
    case applied
    /// A newer server version exists; the run was re-read and the intent must be re-expressed.
    case refreshRequired(serverVersion: Int64)
    case rejected(reasonCode: String)
    /// Outcome unknown. Only `readBack()` (and, while the payload is still in memory,
    /// `retrySameIntent()`) are offered; nothing is inferred locally.
    case unknown
    /// The same requestId was answered for a different payload; a client bug, never retried.
    case payloadConflict
}

@MainActor public final class RunAuthorityCoordinator {
    public let runId: String
    private let scope: String
    private let capabilities: ReformWorldCapabilities
    private let service: (any RunAuthorityServing)?
    private let journal: any RunIntentJournal
    public private(set) var phase: RunAuthorityPhase
    public private(set) var projection: RunAuthorityProjection?
    public private(set) var snapshot: RunSnapshot?
    /// Journal entry for an intent whose outcome is not yet known (also after relaunch).
    public private(set) var recovered: RunIntentJournalRecord?
    /// In-memory copy of the dispatched intent; lost on relaunch by design.
    private var inFlight: RunActionIntent?
    private var generation: UInt64 = 0
    public var onChange: (() -> Void)?

    public init(runId: String, scope: String, capabilities: ReformWorldCapabilities, service: (any RunAuthorityServing)?, journal: any RunIntentJournal) throws {
        guard ReformWire.id(runId), !scope.isEmpty else { throw RunAuthorityIssue.invalid }
        self.runId = runId; self.scope = scope; self.capabilities = capabilities; self.service = service; self.journal = journal
        guard capabilities.allows(.runAuthority), service != nil else { phase = .disabled; return }
        do {
            recovered = try journal.pending(scope: scope, runId: runId)
            phase = recovered == nil ? .idle : .unknown
        } catch {
            phase = .unknown // an unreadable journal never unlocks new intents
        }
    }

    private var enabled: Bool { phase != .disabled }
    private var busy: Bool {
        if case .reviewing = phase { return true }
        return phase == .loading || phase == .submitting
    }
    public var canExpressIntent: Bool {
        enabled && !busy && recovered == nil && phase != .unknown && phase != .payloadConflict && projection.map { !$0.status.isTerminal && $0.status != .paused } == true
    }
    public var canRetrySameIntent: Bool { phase == .unknown && inFlight != nil && recovered.map { inFlight.map($0.matches) == true } == true }
    public var canReadBack: Bool { phase == .unknown && recovered != nil }

    private func changed() { onChange?() }

    /// GetRun. Late responses (older generation or older version) never move the projection.
    public func load() async {
        guard enabled, let service, !busy else { return }
        generation &+= 1; let request = generation
        let resting = phase
        phase = .loading; changed()
        do {
            let value = try await service.run(runId)
            guard request == generation, !Task.isCancelled else { return }
            try value.validate(expectedRunId: runId)
            if var current = projection {
                try current.adopt(snapshotVersion: value.stateVersion, status: value.status, nodes: value.nodeMap)
                projection = current
            } else {
                projection = try RunAuthorityProjection(runId: runId, stateVersion: value.stateVersion, status: value.status, nodes: value.nodeMap)
            }
            if snapshot.map({ $0.stateVersion < value.stateVersion }) ?? true { snapshot = value }
            phase = recovered == nil ? (resting == .loading || resting == .failed ? .idle : resting) : .unknown
        } catch {
            guard request == generation else { return }
            phase = recovered == nil ? .failed : .unknown
        }
        changed()
    }

    /// Builds the exact body for review. Nothing is sent until `confirm()`.
    public func review(nodeId: String, payload: RunActionPayload, requestId: String = UUID().uuidString) {
        guard canExpressIntent, let projection, snapshot?.allowedKinds.contains(payload.kind) == true,
              let intent = try? RunActionIntent(runId: runId, nodeId: nodeId, expectedStateVersion: projection.stateVersion, payload: payload, requestId: requestId) else { return }
        var probe = projection
        guard (try? probe.begin(intent)) != nil else { return }
        phase = .reviewing(intent); changed()
    }

    public func cancelReview() {
        if case .reviewing = phase { phase = .idle; changed() }
    }

    /// Explicit confirmation. The journal is written before dispatch; if it cannot be
    /// written nothing is sent.
    public func confirm() async {
        guard case .reviewing(let intent) = phase, let service, var current = projection else { return }
        guard let record = try? RunIntentJournalRecord(intent), (try? journal.write(record, scope: scope)) != nil else { phase = .failed; changed(); return }
        do { try current.begin(intent) } catch { try? journal.clear(record, scope: scope); phase = .failed; changed(); return }
        projection = current; recovered = record; inFlight = intent
        await dispatch(intent, record: record, service: service)
    }

    /// Resend the identical body under the identical requestId (server deduplicates).
    public func retrySameIntent() async {
        guard canRetrySameIntent, let intent = inFlight, let record = recovered, let service else { return }
        await dispatch(intent, record: record, service: service)
    }

    private func dispatch(_ intent: RunActionIntent, record: RunIntentJournalRecord, service: any RunAuthorityServing) async {
        phase = .submitting; changed()
        let receipt = try? await service.submit(intent)
        guard var current = projection else { return }
        do {
            let outcome = try current.resolve(receipt)
            projection = current
            try finish(outcome, record: record)
        } catch RunAuthorityIssue.payloadConflict {
            projection = current; settle(record); phase = .payloadConflict
        } catch {
            phase = .unknown // malformed or mismatched receipt: keep the journal, read back later
        }
        changed()
        if case .refreshRequired = phase { await load() }
    }

    /// GetReceipt(requestId) for the journalled intent, including after relaunch.
    public func readBack() async {
        guard canReadBack, let record = recovered, let service else { return }
        phase = .submitting; changed()
        do {
            switch try await service.receipt(runId: runId, requestId: record.requestId) {
            case .notFound:
                // Never committed. Drop the lock; the intent must be re-expressed on a fresh read.
                settle(record); inFlight = nil; phase = .idle
                changed(); await load(); return
            case .found(let receipt):
                try record.validate(receipt)
                if var current = projection, current.pending != nil {
                    let outcome = try current.resolve(receipt); projection = current
                    try finish(outcome, record: record)
                } else {
                    try finish(Self.outcome(of: receipt), record: record)
                }
            }
        } catch RunAuthorityIssue.payloadConflict {
            settle(record); phase = .payloadConflict
        } catch {
            phase = .unknown
        }
        changed()
        if phase != .unknown { await load() }
    }

    private static func outcome(of receipt: RunActionReceipt) throws -> RunAuthorityProjection.Outcome {
        switch receipt.decision {
        case .applied: return .applied
        case .rejected: return .rejected(reasonCode: receipt.reasonCode ?? "")
        case .conflict: return .refreshRequired(serverVersion: receipt.stateVersion)
        case .payloadConflict: throw RunAuthorityIssue.payloadConflict
        }
    }

    private func finish(_ outcome: RunAuthorityProjection.Outcome, record: RunIntentJournalRecord) throws {
        switch outcome {
        case .unknown: phase = .unknown
        case .applied: settle(record); inFlight = nil; phase = .applied
        case .rejected(let reason): settle(record); inFlight = nil; phase = .rejected(reasonCode: reason)
        case .refreshRequired(let version): settle(record); inFlight = nil; phase = .refreshRequired(serverVersion: version)
        }
    }

    private func settle(_ record: RunIntentJournalRecord) {
        if (try? journal.clear(record, scope: scope)) != nil { recovered = nil }
    }
}
