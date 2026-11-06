import Foundation

/// Reform plan v9 §28 / W19.3–W19.6: "I'm back" at the private base, then a one-time
/// resource restore. Extends the existing private-home contract (SetHome/GetMyHome/
/// ChangeHome/DeleteHome via `api/native/home`) with VerifyReturnHome and
/// RestoreHomeResources client contracts. Neither endpoint is reviewed yet, so this
/// file performs no I/O. Radius, dwell, freshness, cooldown and restore frequency are
/// server-versioned policy, never client defaults. The home point and the device fix
/// are never logged or exported (`description` is redacted). W20 never reads this.
public enum HomeReturnFailure: Error, Equatable {
    case disabled, locationOff, permissionDenied, lowAccuracy, staleFix, cooldown(retryAfterSeconds: Int)
    case outOfRadius, homeChanged, proofExpired, noHome, network, unknown, invalid
    /// Whether the user can act on it right now (vs. waiting or changing settings).
    public var retryableNow: Bool { [.lowAccuracy, .staleFix, .network, .unknown].contains(self) }
}

/// Resource scope: a global player resource or one run/theme. Never "all games".
public enum HomeResourceScope: Equatable, Hashable, Sendable {
    case global(resourceType: String)
    case run(runId: String, resourceType: String)
    case theme(themeId: String, resourceType: String)
    public var wire: [String: String] {
        switch self {
        case .global(let t): return ["scopeType": "GLOBAL", "resourceType": t]
        case .run(let id, let t): return ["scopeType": "RUN", "scopeId": id, "resourceType": t]
        case .theme(let id, let t): return ["scopeType": "THEME", "scopeId": id, "resourceType": t]
        }
    }
    func validate() throws { guard wire.values.allSatisfy(ReformWire.id) else { throw HomeReturnFailure.invalid } }
}

/// Server policy for a manual return check. Absent policy means the feature is unavailable.
public struct HomeReturnPolicy: Decodable, Equatable, Sendable {
    public let policyVersion: String
    public let maxAccuracyMeters: Double
    public let maxFixAgeSeconds: Double
    public func validate() throws {
        guard ReformWire.label(policyVersion, limit: 64), maxAccuracyMeters.isFinite, maxAccuracyMeters > 0, maxFixAgeSeconds.isFinite, maxFixAgeSeconds > 0 else { throw HomeReturnFailure.invalid }
    }
}

/// Local location situation, produced by the existing native location provider; never sampled here.
public enum HomeReturnLocationStatus: Equatable, Sendable {
    case servicesOff, denied, notDetermined
    case fix(accuracyMeters: Double, capturedAt: Date)
}

public struct HomeReturnCheck: Equatable, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    public let homeVersion: Int64
    public let scope: HomeResourceScope
    public let requestId: String
    public let policyVersion: String
    /// Client preflight only: rejects what the server would certainly reject, never decides arrival.
    public static func preflight(home: PrivateHomeSnapshot?, status: HomeReturnLocationStatus, policy: HomeReturnPolicy, scope: HomeResourceScope, now: Date, requestId: String = UUID().uuidString) throws -> HomeReturnCheck {
        try policy.validate(); try scope.validate()
        guard let home, home.status == .active else { throw HomeReturnFailure.noHome }
        switch status {
        case .servicesOff: throw HomeReturnFailure.locationOff
        case .denied, .notDetermined: throw HomeReturnFailure.permissionDenied
        case .fix(let accuracy, let capturedAt):
            guard accuracy.isFinite, accuracy >= 0, accuracy <= policy.maxAccuracyMeters else { throw HomeReturnFailure.lowAccuracy }
            let age = now.timeIntervalSince(capturedAt)
            guard age >= -5, age <= policy.maxFixAgeSeconds else { throw HomeReturnFailure.staleFix }
        }
        guard ReformWire.requestID(requestId) else { throw HomeReturnFailure.invalid }
        return HomeReturnCheck(homeVersion: home.version, scope: scope, requestId: requestId, policyVersion: policy.policyVersion)
    }
    public var description: String { "HomeReturnCheck[redacted]" }
    public var debugDescription: String { description }
}

/// Short-lived single-use proof bound to owner (implicit, server side), home version and scope.
public struct HomeReturnProof: Equatable, Sendable {
    public let proofId: String
    public let homeVersion: Int64
    public let scope: HomeResourceScope
    public let expiresAt: Date
    public init(proofId: String, homeVersion: Int64, scope: HomeResourceScope, expiresAtMillis: Int64, for check: HomeReturnCheck) throws {
        guard ReformWire.id(proofId), expiresAtMillis > 0 else { throw HomeReturnFailure.invalid }
        guard homeVersion == check.homeVersion else { throw HomeReturnFailure.homeChanged }
        guard scope == check.scope else { throw HomeReturnFailure.invalid }
        self.proofId = proofId; self.homeVersion = homeVersion; self.scope = scope
        expiresAt = Date(timeIntervalSince1970: Double(expiresAtMillis) / 1000)
    }
}

public struct HomeRestoreRequest: Equatable, Sendable {
    public let proofId, requestId: String
    public let homeVersion, expectedAccountVersion: Int64
    public let scope: HomeResourceScope
    public init(proof: HomeReturnProof, currentHomeVersion: Int64, expectedAccountVersion: Int64, deviceNow: Date, serverOffset: TimeInterval, requestId: String = UUID().uuidString) throws {
        guard currentHomeVersion == proof.homeVersion else { throw HomeReturnFailure.homeChanged }
        guard deviceNow.addingTimeInterval(serverOffset) < proof.expiresAt else { throw HomeReturnFailure.proofExpired }
        guard ReformWire.version(expectedAccountVersion), ReformWire.requestID(requestId) else { throw HomeReturnFailure.invalid }
        proofId = proof.proofId; self.requestId = requestId; homeVersion = proof.homeVersion; self.expectedAccountVersion = expectedAccountVersion; scope = proof.scope
    }
}

public struct HomeRestoreReceipt: Decodable, Equatable, Sendable {
    public enum Decision: String, Decodable, Sendable {
        case restored = "RESTORED", alreadyAtMax = "ALREADY_AT_MAX", proofConsumed = "PROOF_CONSUMED", staleHome = "STALE_HOME"
        case proofExpired = "PROOF_EXPIRED", cooldown = "COOLDOWN", versionConflict = "VERSION_CONFLICT"
    }
    public let requestId, proofId: String
    public let decision: Decision
    public let current, maximum: Int64
    public let accountVersion: Int64
    public let retryAfterSeconds: Int?
    /// Server max is authoritative; restore lands exactly on it and never exceeds it.
    public func validate(for request: HomeRestoreRequest) throws {
        guard requestId == request.requestId, proofId == request.proofId, current >= 0, maximum > 0, current <= maximum, ReformWire.version(accountVersion) else { throw HomeReturnFailure.invalid }
        switch decision {
        case .restored: guard current == maximum, accountVersion == request.expectedAccountVersion + 1, retryAfterSeconds == nil else { throw HomeReturnFailure.invalid }
        case .cooldown: guard let retryAfterSeconds, retryAfterSeconds > 0, accountVersion == request.expectedAccountVersion else { throw HomeReturnFailure.invalid }
        default: guard retryAfterSeconds == nil else { throw HomeReturnFailure.invalid }
        }
    }
    /// User-facing failure for non-success decisions; nil when the resource is now full.
    public var failure: HomeReturnFailure? {
        switch decision {
        case .restored, .alreadyAtMax: return nil
        case .proofConsumed: return nil // the same proof already restored once; show current values.
        case .staleHome: return .homeChanged
        case .proofExpired: return .proofExpired
        case .cooldown: return .cooldown(retryAfterSeconds: retryAfterSeconds ?? 0)
        case .versionConflict: return .unknown
        }
    }
}
