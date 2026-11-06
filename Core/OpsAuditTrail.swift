import Foundation

// Reform plan v9 W01.1 / W11.7–W11.8: a client-side audit hook that records which
// degraded-state decisions the app made, so a support timeline can be correlated later.
// Memory only, bounded, and structurally free of personal data: events carry enum cases,
// exact switch targets and a locally generated correlation ID — never tokens, text,
// coordinates, phone numbers, order contents or server messages. Nothing is uploaded.

public enum OpsAuditEventKind: String, CaseIterable, Equatable {
    case gateBlocked, gateUnverified, preservedServiceAllowed
    case readTimedOut, writeOutcomeUnknown, aiFallbackShown
    case offlineNodeStopped, sensitiveTextWarned
}

public struct OpsAuditEvent: Equatable {
    public let kind: OpsAuditEventKind
    public let layer: OpsKillSwitchLayer?
    public let targetIdentifier: String?
    public let incident: OpsIncidentKind?
    /// Local only. Lets one support case line up client events; it is not a server request ID.
    public let correlationID: UUID
    public let at: Date
}

@MainActor public final class OpsAuditTrail {
    public static let defaultCapacity = 64
    public let capacity: Int
    public private(set) var events: [OpsAuditEvent] = []
    private let now: () -> Date
    public init(capacity: Int = 64, now: @escaping () -> Date = { Date() }) {
        self.capacity = max(1, min(capacity, 512)); self.now = now
    }
    @discardableResult
    public func record(_ kind: OpsAuditEventKind, target: OpsKillSwitchTarget? = nil,
                       incident: OpsIncidentKind? = nil, correlationID: UUID = UUID()) -> OpsAuditEvent {
        let event = OpsAuditEvent(kind: kind, layer: target?.layer, targetIdentifier: target?.identifier,
                                  incident: incident, correlationID: correlationID, at: now())
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
        return event
    }
    /// Records the gate decision and returns it unchanged, so call sites stay one line.
    @discardableResult
    public func record(_ decision: OpsGateDecision, correlationID: UUID = UUID()) -> OpsGateDecision {
        switch decision {
        case .proceed: break
        case let .blocked(target, incident): record(.gateBlocked, target: target, incident: incident, correlationID: correlationID)
        case .unverified: record(.gateUnverified, correlationID: correlationID)
        case .preserved: record(.preservedServiceAllowed, correlationID: correlationID)
        }
        return decision
    }
    /// Account switch, logout or region change: the trail belongs to the previous session.
    public func clear() { events.removeAll() }
}
