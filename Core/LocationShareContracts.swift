import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reform plan v9 §21 / W13.5–W13.8. OS location permission is not sharing consent.
/// The proposed grant service has no reviewed endpoint; nothing here is wired to a network.
public enum LocationShareFeature {
    public static let preciseGrantEnabled = false
}

public enum LocationSharePrecision: String, CaseIterable, Codable { case exact, coarse, distanceOnly }
/// No stranger or public audience exists: precise positions go only to a named person or team (W13.6).
public enum LocationShareAudience: Hashable, Codable {
    case member(Int), team(Int)
    public var isValid: Bool { switch self { case .member(let id), .team(let id): id > 0 } }
}
public enum LocationSharePurpose: String, CaseIterable, Codable { case teamActivity }

/// Every disclosure must be acknowledged before a request can be formed.
public enum LocationShareDisclosure: String, CaseIterable {
    case audience, precision, duration, foregroundOnly, stopAnytime, alreadySeenCannotBeRecalled
}

/// Durations are user choices; the server may shorten but never extend them.
public enum LocationShareDuration: Int, CaseIterable {
    case fifteenMinutes = 900, oneHour = 3600, untilActivityEnds = 0
}

public struct LocationShareGrantRequest: Equatable {
    public let requestID: UUID
    public let audience: LocationShareAudience
    public let precision: LocationSharePrecision
    public let purpose: LocationSharePurpose
    public let duration: LocationShareDuration
    public let consentVersion: String
    public let background: Bool
}

public struct LocationShareDraft: Equatable {
    public var audience: LocationShareAudience?
    public var precision: LocationSharePrecision = .distanceOnly
    public var duration: LocationShareDuration = .fifteenMinutes
    public private(set) var acknowledged: Set<LocationShareDisclosure> = []
    public init() {}
    public mutating func acknowledge(_ item: LocationShareDisclosure) { acknowledged.insert(item) }
    public mutating func withdraw(_ item: LocationShareDisclosure) { acknowledged.remove(item) }
    /// Changing what is shared invalidates the matching acknowledgements.
    public mutating func choose(precision: LocationSharePrecision) {
        if precision != self.precision { acknowledged.remove(.precision) }
        self.precision = precision
    }
    public mutating func choose(audience: LocationShareAudience) {
        if audience != self.audience { acknowledged.remove(.audience) }
        self.audience = audience
    }
    public mutating func choose(duration: LocationShareDuration) {
        if duration != self.duration { acknowledged.remove(.duration) }
        self.duration = duration
    }
    public var missingDisclosures: [LocationShareDisclosure] { LocationShareDisclosure.allCases.filter { !acknowledged.contains($0) } }
    public func request(consentVersion: String, requestID: UUID = UUID()) throws -> LocationShareGrantRequest {
        guard LocationShareFeature.preciseGrantEnabled else { throw LocationShareFailure.featureDisabled }
        guard let audience, audience.isValid, missingDisclosures.isEmpty, !consentVersion.isEmpty, consentVersion.count <= 64 else {
            throw LocationShareFailure.consentIncomplete
        }
        return .init(requestID: requestID, audience: audience, precision: precision, purpose: .teamActivity,
                     duration: duration, consentVersion: consentVersion, background: false)
    }
}

public enum LocationShareFailure: Error, Equatable { case featureDisabled, consentIncomplete, stale, notAuthorized, precisionViolation, outOfOrder }

public struct LocationShareGrant: Equatable {
    public enum Status: String, Codable { case active, revoked, expired }
    public let grantID: String
    public let audience: LocationShareAudience
    public let precision: LocationSharePrecision
    public let startsAt: Date
    public let expiresAt: Date
    public let status: Status
    public let version: Int
    public init(grantID: String, audience: LocationShareAudience, precision: LocationSharePrecision,
                startsAt: Date, expiresAt: Date, status: Status, version: Int) {
        self.grantID = grantID; self.audience = audience; self.precision = precision
        self.startsAt = startsAt; self.expiresAt = expiresAt; self.status = status; self.version = version
    }
    public func effectiveStatus(now: Date) -> Status { status == .active && now >= expiresAt ? .expired : status }
}

/// Owner-side sharing state. Default off. Revoke wins over any late create response (U04).
public struct LocationShareOwnerState: Equatable {
    public enum Phase: Equatable { case off, requesting(UUID), active(LocationShareGrant), revoking(String), unknown }
    public private(set) var phase: Phase = .off
    private var revokedAfter: Set<UUID> = []
    public init() {}
    public mutating func begin(_ request: LocationShareGrantRequest) -> Bool {
        guard case .off = phase else { return false }
        phase = .requesting(request.requestID); return true
    }
    public mutating func finishCreate(_ requestID: UUID, grant: LocationShareGrant?) {
        guard case .requesting(let current) = phase, current == requestID, !revokedAfter.contains(requestID) else { return }
        phase = grant.map(Phase.active) ?? .unknown
    }
    /// Stop is always available and immediate locally; the server confirms afterwards.
    public mutating func stop() {
        switch phase {
        case .requesting(let id): revokedAfter.insert(id); phase = .revoking("")
        case .active(let grant): phase = .revoking(grant.grantID)
        case .unknown: phase = .revoking("")
        case .off, .revoking: break
        }
    }
    public mutating func finishRevoke() { if case .revoking = phase { phase = .off } }
    public mutating func expireIfNeeded(now: Date) {
        if case .active(let grant) = phase, grant.effectiveStatus(now: now) != .active { phase = .off }
    }
    /// Sharing never continues past session end, team exit, sign-out or OS location loss (W13.8).
    public mutating func endForSessionChange() { if case .requesting(let id) = phase { revokedAfter.insert(id) }; phase = .off }
    public var isSharing: Bool { if case .active = phase { true } else { false } }
}

/// W13.7: distance-only output uses coarse bands, never a precise meter count.
/// Band edges are client display candidates pending review, not an approved privacy policy.
public enum MapDistanceBand: String, CaseIterable {
    case under500m, under1km, under3km, beyond3km
    public static func band(meters: Double) -> MapDistanceBand? {
        guard meters.isFinite, meters >= 0 else { return nil }
        return meters < 500 ? .under500m : meters < 1_000 ? .under1km : meters < 3_000 ? .under3km : .beyond3km
    }
}

/// Receiver-side view of what others chose to share with this account.
public struct SharedPeerLocation: Equatable {
    public enum Payload: Equatable { case point(MapCoordinateObservation), band(MapDistanceBand) }
    public let grantID: String
    public let ownerID: Int
    public let revision: Int
    public let payload: Payload
    public let observedAt: Date
    public init(grantID: String, ownerID: Int, revision: Int, payload: Payload, observedAt: Date) {
        self.grantID = grantID; self.ownerID = ownerID; self.revision = revision; self.payload = payload; self.observedAt = observedAt
    }
}

public struct SharedPeerLocationBoard: Equatable {
    public private(set) var grants: [String: LocationShareGrant] = [:]
    public private(set) var latest: [String: SharedPeerLocation] = [:]
    public init() {}
    /// Replaces the authorized grant set from a fresh read; anything not present is removed at once.
    public mutating func replaceGrants(_ incoming: [LocationShareGrant], now: Date) {
        grants = Dictionary(incoming.filter { $0.effectiveStatus(now: now) == .active }.map { ($0.grantID, $0) }, uniquingKeysWith: { a, b in a.version >= b.version ? a : b })
        latest = latest.filter { grants[$0.key] != nil }
    }
    public mutating func revoke(grantID: String) { grants[grantID] = nil; latest[grantID] = nil }
    public mutating func apply(_ update: SharedPeerLocation, now: Date) throws {
        guard let grant = grants[update.grantID], grant.effectiveStatus(now: now) == .active else {
            latest[update.grantID] = nil; throw LocationShareFailure.notAuthorized
        }
        switch (grant.precision, update.payload) {
        case (.distanceOnly, .point): throw LocationShareFailure.precisionViolation
        case (.exact, .point(let point)), (.coarse, .point(let point)):
            guard point.accuracyMeters != nil else { throw LocationShareFailure.precisionViolation }
        default: break
        }
        if let current = latest[update.grantID], current.revision >= update.revision || current.observedAt > update.observedAt {
            throw LocationShareFailure.outOfOrder
        }
        guard update.observedAt.timeIntervalSince(now) <= 60 else { throw LocationShareFailure.stale }
        latest[update.grantID] = update
    }
    /// Stale entries remain visible only as "last seen"; nothing is interpolated.
    public func isStale(grantID: String, now: Date, maxAge: TimeInterval) -> Bool {
        guard let entry = latest[grantID] else { return true }
        return now.timeIntervalSince(entry.observedAt) > maxAge
    }
}

/// Existing mini-program behavior: per-roam-session approximate presence to nearby roamers
/// (`/api/roam/presence-visibility`, consent `roam-presence-v1`). Request/response contract
/// only; the path is not in any approved iOS endpoint allowlist yet.
public enum RoamPresenceVisibilityContract {
    public static let path = "api/roam/presence-visibility"
    public static let consentVersion = "roam-presence-v1"
    public static func readRequest(baseURL: URL, sessionID: Int) throws -> URLRequest {
        guard sessionID > 0, var parts = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw LocationShareFailure.consentIncomplete
        }
        parts.queryItems = [URLQueryItem(name: "sessionId", value: String(sessionID))]
        guard let url = parts.url else { throw LocationShareFailure.consentIncomplete }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    /// Turning on requires a live roam session and explicit consent; turning off never does.
    public static func changeRequest(baseURL: URL, sessionID: Int?, visible: Bool, consentAccepted: Bool) throws -> URLRequest {
        if visible { guard let sessionID, sessionID > 0, consentAccepted else { throw LocationShareFailure.consentIncomplete } }
        var request = URLRequest(url: baseURL.appendingPathComponent(path)); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let fields = [("sessionId", sessionID.map(String.init) ?? ""), ("visible", visible ? "true" : "false"),
                      ("consentVersion", visible ? consentVersion : "")]
        request.httpBody = Data(fields.map { "\($0.0)=\($0.1)" }.joined(separator: "&").utf8)
        return request
    }
    /// `{code:200,data:Bool}` only. Anything else is unknown, never "off" or "on".
    public static func decode(_ data: Data) -> Bool? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code.intValue == 200,
              let value = object["data"] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    /// Mini-program parity: enabling is confirmed only when the change echo and a fresh read both say true.
    /// Any mismatch or missing value is unknown and must be retried or re-read, never assumed.
    public static func confirmedEnabled(changeEcho: Bool?, readback: Bool?) -> Bool? {
        changeEcho == true && readback == true ? true : nil
    }
}
