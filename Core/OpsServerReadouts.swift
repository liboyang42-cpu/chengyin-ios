import Foundation

// Decoders for two EXISTING anonymous backend contracts, mirrored from the mini-program
// source of truth, plus its write-outcome rule. Neither route is in any reviewed endpoint
// allowlist: these types parse bytes a caller already holds and never send a request.
//
//  * GET  api/status          → AjaxResult{data: ServiceStatusVO} (overallStatus, updatedAt,
//    source, components[], incidents[]); server already returns UNKNOWN when its feed is
//    older than 90s. The mini-program does not call it today.
//  * POST api/config/features → AjaxResult{data: {flagKey: Bool}}; the mini-program keeps
//    every flag OFF when the call fails or a key is missing.

public enum OpsServiceStatus: String, CaseIterable, Equatable {
    case operational = "OPERATIONAL", degraded = "DEGRADED", partialOutage = "PARTIAL_OUTAGE"
    case majorOutage = "MAJOR_OUTAGE", maintenance = "MAINTENANCE", unknown = "UNKNOWN"
}

public struct OpsServiceStatusReadout: Equatable {
    public struct Component: Equatable { public let code: String; public let status: OpsServiceStatus }
    public let overall: OpsServiceStatus
    public let updatedAt: Date
    public let components: [Component]
    public let incidentCount: Int

    /// Maps the overall status to a global readout. Which statuses gate new operations is
    /// an explicit, reviewed input; the default gates nothing and only informs, matching
    /// today's mini-program, which never blocks on service status.
    public func globalReadout(blocking: Set<OpsServiceStatus> = []) -> OpsKillSwitchReadout {
        let state: OpsKillSwitchState
        switch overall {
        case .operational: state = .inactive
        case .unknown: state = .unknown
        default: state = .active(.init(blocksNewOperations: blocking.contains(overall), affectsExisting: nil), incident: .serviceDegraded)
        }
        return .init(target: .global, state: state, observedAt: updatedAt)
    }
}

public enum OpsServiceStatusDecoder {
    private struct Envelope: Decodable { let code: Int?; let data: Payload? }
    private struct Payload: Decodable {
        let overallStatus: String?; let updatedAt: String?
        let components: [Component]?; let incidents: [Incident]?
    }
    private struct Component: Decodable { let code: String?; let status: String? }
    private struct Incident: Decodable { let id: String? }

    public static func decode(_ data: Data) -> OpsServiceStatusReadout? {
        guard data.count <= 524_288, let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.code == 200, let payload = envelope.data,
              let overall = payload.overallStatus.flatMap(OpsServiceStatus.init(rawValue:)),
              let updatedAt = payload.updatedAt.flatMap(parseInstant), let rawComponents = payload.components,
              let incidents = payload.incidents, rawComponents.count <= 64 else { return nil }
        var components: [OpsServiceStatusReadout.Component] = []
        for raw in rawComponents {
            // The server rejects a feed with any invalid component; do the same.
            guard let code = raw.code, !code.isEmpty, code.utf8.count <= 64,
                  let status = raw.status.flatMap(OpsServiceStatus.init(rawValue:)) else { return nil }
            components.append(.init(code: code, status: status))
        }
        return .init(overall: overall, updatedAt: updatedAt, components: components, incidentCount: incidents.count)
    }
    static func parseInstant(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Server feature flags can only narrow a capability the app already gates. A missing,
/// non-boolean or unread flag is OFF, exactly as the mini-program treats a failed read.
public struct OpsServerFeatureFlags: Equatable {
    public static let knownKeys: Set<String> = [
        "drops", "roamDemoPois", "finishNearbyRoute", "clubMembership", "roamNpcEvent", "roamNpcChat",
        "shopNpcChat", "shopNpcVoice", "shopNpcVoiceAvailable", "merchantNpcChat", "communityPostRead", "communityPostWrite"
    ]
    private let values: [String: Bool]
    public static let unread = OpsServerFeatureFlags(values: [:])
    init(values: [String: Bool]) { self.values = values }
    public func allows(_ key: String) -> Bool { values[key] == true }

    public static func decode(_ data: Data) -> OpsServerFeatureFlags {
        guard data.count <= 65_536,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["code"] as? NSNumber)?.intValue == 200, let payload = object["data"] as? [String: Any] else { return .unread }
        var values: [String: Bool] = [:]
        for key in knownKeys {
            // NSNumber bridges both JSON booleans and 0/1; accept only real booleans.
            if let number = payload[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { values[key] = number.boolValue }
        }
        return .init(values: values)
    }
}

/// Mini-program failure-envelope rule: no status, 408 or any 5xx means a write may have
/// been applied. Callers keep the existing unknown/pending lock and read back before retry.
public enum OpsWriteOutcomeClass: Equatable {
    /// `httpDelivered` only means the HTTP layer answered 2xx; the body's business code decides.
    case outcomeUnknown, rejected, httpDelivered
    public init(httpStatus: Int?) {
        switch httpStatus {
        case nil: self = .outcomeUnknown
        case let status? where status == 408 || status >= 500: self = .outcomeUnknown
        case let status? where (200..<300).contains(status): self = .httpDelivered
        default: self = .rejected
        }
    }
}
