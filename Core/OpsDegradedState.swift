import Foundation

// Reform plan v9 §18–§19 / W11.6–W11.9: client readouts for layered kill switches,
// fixed degraded copy and deadline outcomes. No server contract for kill-switch
// readouts exists yet; the decoder below is a proposed shape that stays unused until
// an exact reviewed route and approval are injected. Nothing here can enable a
// feature, bypass authorization or decide a server fact.

/// The six layers named by W11.9. Order is from broadest to narrowest scope.
public enum OpsKillSwitchLayer: String, CaseIterable, Codable, Equatable {
    case global, theme, merchant, sku, node, aiTool
}

/// One switch target. Global has no identifier; every other layer needs one exact,
/// bounded server identifier. The client never widens a narrow target to a broader one.
public struct OpsKillSwitchTarget: Hashable {
    public let layer: OpsKillSwitchLayer
    public let identifier: String?
    public init?(layer: OpsKillSwitchLayer, identifier: String?) {
        if layer == .global {
            guard identifier == nil else { return nil }
        } else {
            guard let identifier, !identifier.isEmpty, identifier.utf8.count <= 128,
                  identifier.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        }
        self.layer = layer; self.identifier = identifier
    }
    public static let global = OpsKillSwitchTarget(layer: .global, identifier: nil)!
}

/// What a client is about to do. Preserved services are the §18 rollback guarantees:
/// order query, refund, after-sales, already-paid fulfilment and support stay reachable
/// whatever a switch says. A switch only gates new operations, and gates continuation
/// of existing ones only when the server explicitly states that it does.
public enum OpsOperationKind: String, Codable, Equatable, CaseIterable {
    case newOperation, continuation, preservedService
}

/// W11.9 requires each switch to state whether it blocks new operations and whether it
/// affects existing ones. A missing statement stays nil and is never guessed.
public struct OpsKillSwitchImpact: Equatable, Codable {
    public let blocksNewOperations: Bool
    public let affectsExisting: Bool?
    public init(blocksNewOperations: Bool, affectsExisting: Bool?) {
        self.blocksNewOperations = blocksNewOperations; self.affectsExisting = affectsExisting
    }
}

public enum OpsKillSwitchState: Equatable {
    case inactive
    case active(OpsKillSwitchImpact, incident: OpsIncidentKind)
    /// Not read, unreadable, or outside the approved scope. Never treated as inactive.
    case unknown
}

public struct OpsKillSwitchReadout: Equatable {
    public let target: OpsKillSwitchTarget
    public let state: OpsKillSwitchState
    public let observedAt: Date
    public init(target: OpsKillSwitchTarget, state: OpsKillSwitchState, observedAt: Date) {
        self.target = target; self.state = state; self.observedAt = observedAt
    }
}

/// Fixed-copy incidents from the §19 first-release runbook. Each maps to bilingual copy
/// that states only what the client knows: no times, compensation, refunds or prices.
public enum OpsIncidentKind: String, CaseIterable, Codable, Equatable {
    case nodeUnsafeOrClosed, aiDisabled, paymentPendingEntitlement
    case inventoryPaused, eventBacklog, redemptionFrozen, serviceDegraded

    public var copyKey: String { "opsSafety.incident." + rawValue }
    /// Actions the copy may point at. They reuse existing entries; none is created here.
    public var preservedActions: [OpsPreservedAction] {
        switch self {
        case .nodeUnsafeOrClosed: return [.viewAlternativeIfProvided, .contactSupport]
        case .aiDisabled: return [.continueWithoutAI]
        case .paymentPendingEntitlement: return [.doNotPayAgain, .viewOrder, .contactSupport]
        case .inventoryPaused: return [.viewOrder, .afterSales]
        case .eventBacklog: return [.viewOrder, .contactSupport]
        case .redemptionFrozen: return [.viewOrder, .contactSupport]
        case .serviceDegraded: return [.contactSupport]
        }
    }
}

public enum OpsPreservedAction: String, CaseIterable, Codable, Equatable {
    case viewAlternativeIfProvided, contactSupport, continueWithoutAI, doNotPayAgain, viewOrder, afterSales
    public var copyKey: String { "opsSafety.action." + rawValue }
}

public enum OpsGateDecision: Equatable {
    /// Every layer in the chain was read and none is active for this kind.
    case proceed
    /// An active switch gates this kind. The server still decides; this is a pre-check.
    case blocked(OpsKillSwitchTarget, OpsIncidentKind)
    /// At least one layer could not be read. The client must not claim availability, and
    /// must not block either: the server's response remains authoritative.
    case unverified([OpsKillSwitchLayer])
    /// Preserved service: never gated by the client.
    case preserved
}

/// Pure resolver. Readouts outside the requested chain are ignored; a readout for a
/// different identifier on the same layer never applies. A readout older than
/// `maximumAge`, or observed in the future, is stale and counts as unknown, so a cached
/// "inactive" cannot outlive a later switch.
public enum OpsKillSwitchResolver {
    public static func decision(kind: OpsOperationKind, chain: [OpsKillSwitchTarget],
                                readouts: [OpsKillSwitchReadout], now: Date,
                                maximumAge: TimeInterval) -> OpsGateDecision {
        if kind == .preservedService { return .preserved }
        var chain = chain
        if !chain.contains(.global) { chain.insert(.global, at: 0) }
        var missing: [OpsKillSwitchLayer] = []
        for target in chain {
            let matches = readouts.filter { $0.target == target }
            // Conflicting duplicate readouts for one target are unreadable, not resolved.
            guard matches.count == 1, let readout = matches.first, maximumAge > 0,
                  readout.observedAt <= now, now.timeIntervalSince(readout.observedAt) <= maximumAge else {
                missing.append(target.layer); continue
            }
            switch readout.state {
            case .unknown: missing.append(target.layer)
            case .inactive: continue
            case let .active(impact, incident):
                switch kind {
                case .newOperation where impact.blocksNewOperations: return .blocked(target, incident)
                case .continuation where impact.affectsExisting == true: return .blocked(target, incident)
                case .continuation where impact.affectsExisting == nil: missing.append(target.layer)
                default: continue
                }
            }
        }
        return missing.isEmpty ? .proceed : .unverified(missing)
    }
}

/// Proposed readout envelope, pending backend review (no endpoint exists):
/// {"code":200,"data":{"switches":[{"layer":"theme","targetId":"12","active":true,
///  "blocksNew":true,"affectsExisting":false,"incident":"aiDisabled"}]}}
/// Rows with an unknown layer or invalid target are dropped (the resolver then treats that
/// layer as unread). Unknown incidents or missing flags become `.unknown`, never inactive.
/// A non-200 or oversized envelope yields nil: nothing was read.
public enum OpsKillSwitchReadoutDecoder {
    private struct Envelope: Decodable { let code: Int?; let data: Payload? }
    private struct Payload: Decodable { let switches: [Row]? }
    private struct Row: Decodable {
        let layer: String?; let targetId: String?; let active: Bool?
        let blocksNew: Bool?; let affectsExisting: Bool?; let incident: String?
    }
    public static let maximumRows = 256
    public static func decode(_ data: Data, observedAt: Date) -> [OpsKillSwitchReadout]? {
        guard data.count <= 262_144, let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.code == 200, let rows = envelope.data?.switches, rows.count <= maximumRows else { return nil }
        return rows.compactMap { (row: Row) -> OpsKillSwitchReadout? in
            guard let layer = row.layer.flatMap(OpsKillSwitchLayer.init(rawValue:)),
                  let target = OpsKillSwitchTarget(layer: layer, identifier: layer == .global ? nil : row.targetId),
                  layer != .global || row.targetId == nil else { return nil }
            let state: OpsKillSwitchState
            switch (row.active, row.blocksNew, row.incident.flatMap(OpsIncidentKind.init(rawValue:))) {
            case (false?, _, _): state = .inactive
            case let (true?, blocksNew?, incident?):
                state = .active(.init(blocksNewOperations: blocksNew, affectsExisting: row.affectsExisting), incident: incident)
            default: state = .unknown
            }
            return OpsKillSwitchReadout(target: target, state: state, observedAt: observedAt)
        }
    }
}

/// Client deadline outcomes. A timed-out read may show fixed copy; a timed-out write is
/// an unknown outcome — the server may have applied it — and must keep the existing
/// pending/unknown lock instead of reporting failure or retrying automatically.
public enum OpsRequestKind: String, Codable, Equatable {
    case read, write, aiGeneration
    public var timeoutCopyKey: String {
        switch self {
        case .read: return "opsSafety.timeout.read"
        case .write: return "opsSafety.timeout.writeUnknown"
        case .aiGeneration: return "opsSafety.timeout.ai"
        }
    }
}

public enum OpsDeadlineOutcome<Value> {
    case completed(Value)
    case readTimedOut
    case writeOutcomeUnknown
    case aiFallback
}

/// §19 numbers (AI total 8s; read P95 500ms; write P95 800ms) are review starting points
/// for server budgets, not client timeouts. The shipped policy is `.disabled`, which keeps
/// each service's existing transport timeout. A reviewed policy is injected explicitly.
public struct OpsDeadlinePolicy: Equatable {
    public let aiGeneration: Duration?
    public let read: Duration?
    public let write: Duration?
    public init?(aiGeneration: Duration? = nil, read: Duration? = nil, write: Duration? = nil) {
        func valid(_ value: Duration?) -> Bool { value.map { $0 > .zero && $0 <= .seconds(120) } ?? true }
        guard valid(aiGeneration), valid(read), valid(write) else { return nil }
        self.aiGeneration = aiGeneration; self.read = read; self.write = write
    }
    public static let disabled = OpsDeadlinePolicy()!
    /// Proposal only (plan §19 AI total timeout). Not referenced by the shipped composition.
    public static let planProposalAIOnly = OpsDeadlinePolicy(aiGeneration: .seconds(8))!
    public func limit(for kind: OpsRequestKind) -> Duration? {
        switch kind { case .read: return read; case .write: return write; case .aiGeneration: return aiGeneration }
    }
}

private enum OpsDeadlineRace<Value: Sendable>: Sendable { case value(Value), deadline }

public enum OpsDeadline {
    /// Races `operation` against the policy limit. Without a limit the operation runs
    /// unchanged. Cancellation of the caller propagates as CancellationError.
    public static func run<Value: Sendable>(_ kind: OpsRequestKind, policy: OpsDeadlinePolicy,
                                            clock: ContinuousClock = .init(),
                                            operation: @escaping @Sendable () async throws -> Value) async throws -> OpsDeadlineOutcome<Value> {
        guard let limit = policy.limit(for: kind) else { return .completed(try await operation()) }
        return try await withThrowingTaskGroup(of: OpsDeadlineRace<Value>.self, returning: OpsDeadlineOutcome<Value>.self) { group in
            group.addTask { .value(try await operation()) }
            group.addTask { try await clock.sleep(for: limit); return .deadline }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            if case let .value(value) = first { return .completed(value) }
            try Task.checkCancellation()
            switch kind {
            case .read: return .readTimedOut
            case .write: return .writeOutcomeUnknown
            case .aiGeneration: return .aiFallback
            }
        }
    }
}
