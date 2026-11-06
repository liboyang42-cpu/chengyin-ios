import Foundation

/// Reform plan v9 §28 / W19.3–W19.6: "I'm back" at the private base, then a one-time
/// resource restore. Extends the existing private-home contract (SetHome/GetMyHome/
/// ChangeHome/DeleteHome via `api/native/home`) with VerifyReturnHome and
/// RestoreHomeResources client contracts. The independently gated native transport is
/// in NativeHomeReturnService; this value layer performs no I/O. Radius, dwell, freshness, cooldown and restore frequency are
/// server-versioned policy, never client defaults. The home point and the device fix
/// are never logged or exported (`description` is redacted). W20 never reads this.
public enum NativeHomeReturnFailure: Error, Equatable {
    case disabled, locationOff, permissionDenied, lowAccuracy, staleFix, cooldown(retryAfterSeconds: Int)
    case outOfRadius, homeChanged, proofExpired, noHome, network, unknown, invalid, runUnavailable, storageUnavailable
    case dwellRequired(retryAfterSeconds: Int)
    /// Whether the user can act on it right now (vs. waiting or changing settings).
    public var retryableNow: Bool { [.lowAccuracy, .staleFix, .network, .unknown].contains(self) }
}

/// Resource scope: a global player resource or one run/theme. Never "all games".
public enum NativeHomeResourceScope: Equatable, Hashable, Sendable {
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
    func validate() throws { guard wire.values.allSatisfy(ReformWire.id) else { throw NativeHomeReturnFailure.invalid } }
    /// Production W19 permits one actual server run and its frozen HP only.
    public func validateNative() throws {
        guard case .run(let id, let resource) = self, Self.decimalID(id), resource == "sys.hp" else { throw NativeHomeReturnFailure.invalid }
    }
    static func decimalID(_ value: String) -> Bool {
        guard let number = Int64(value), number > 0 else { return false }
        return String(number) == value
    }
}

/// Server policy for a manual return check. Absent policy means the feature is unavailable.
public struct NativeHomeReturnPolicy: Decodable, Equatable, Sendable {
    public let policyVersion: String
    public let maxAccuracyMeters: Double
    public let maxFixAgeSeconds: Double
    public let dwellSeconds: Double
    public let serverTimeMillis: Int64
    public func validate() throws {
        guard policyVersion.range(of: "\\A[A-Za-z0-9._:-]{1,64}\\z", options: .regularExpression) != nil,
              maxAccuracyMeters.isFinite, maxAccuracyMeters > 0, maxFixAgeSeconds.isFinite, maxFixAgeSeconds > 0, dwellSeconds.isFinite, dwellSeconds >= 0, serverTimeMillis > 0 else { throw NativeHomeReturnFailure.invalid }
    }
}

/// Local location situation, produced by the existing native location provider; never sampled here.
public enum NativeHomeReturnLocationStatus: Equatable, Sendable {
    case servicesOff, denied, notDetermined
    case fix(accuracyMeters: Double, capturedAt: Date)
    case measured(NativeHomeReturnFix)
}

public struct NativeHomeReturnCheck: Equatable, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    public let homeVersion: Int64
    public let scope: NativeHomeResourceScope
    public let requestId: String
    public let policyVersion: String
    public let expectedAccountVersion: Int64?
    public let fix: NativeHomeReturnFix?
    public let challengeId: String?
    /// Client preflight only: rejects what the server would certainly reject, never decides arrival.
    public static func preflight(home: PrivateHomeSnapshot?, status: NativeHomeReturnLocationStatus, policy: NativeHomeReturnPolicy, scope: NativeHomeResourceScope, now: Date, requestId: String = UUID().uuidString, expectedAccountVersion: Int64? = nil, challengeId: String? = nil) throws -> NativeHomeReturnCheck {
        try policy.validate(); try scope.validate()
        guard let home, home.status == .active else { throw NativeHomeReturnFailure.noHome }
        let accuracy: Double, capturedAt: Date, fix: NativeHomeReturnFix?
        switch status {
        case .servicesOff: throw NativeHomeReturnFailure.locationOff
        case .denied, .notDetermined: throw NativeHomeReturnFailure.permissionDenied
        case .fix(let value, let timestamp): accuracy = value; capturedAt = timestamp; fix = nil
        case .measured(let value): accuracy = value.accuracyMeters; capturedAt = value.capturedAt; fix = value
        }
        guard accuracy.isFinite, accuracy >= 0, accuracy <= policy.maxAccuracyMeters else { throw NativeHomeReturnFailure.lowAccuracy }
        let age = now.timeIntervalSince(capturedAt)
        guard age >= 0, age <= policy.maxFixAgeSeconds else { throw NativeHomeReturnFailure.staleFix }
        guard ReformWire.requestID(requestId), expectedAccountVersion.map(ReformWire.version) ?? true,
              challengeId.map({ ReformWire.id($0) && $0.utf8.count <= 64 }) ?? true else { throw NativeHomeReturnFailure.invalid }
        return NativeHomeReturnCheck(homeVersion: home.version, scope: scope, requestId: requestId, policyVersion: policy.policyVersion,
                               expectedAccountVersion: expectedAccountVersion, fix: fix, challengeId: challengeId)
    }
    public var description: String { "NativeHomeReturnCheck[redacted]" }
    public var debugDescription: String { description }
}

/// Short-lived single-use proof bound to owner (implicit, server side), home version and scope.
public struct NativeHomeReturnProof: Equatable, Sendable {
    public let proofId: String
    public let homeVersion: Int64
    public let scope: NativeHomeResourceScope
    public let expiresAt: Date
    public init(proofId: String, homeVersion: Int64, scope: NativeHomeResourceScope, expiresAtMillis: Int64, for check: NativeHomeReturnCheck) throws {
        guard ReformWire.id(proofId), proofId.utf8.count <= 64, expiresAtMillis > 0 else { throw NativeHomeReturnFailure.invalid }
        guard homeVersion == check.homeVersion else { throw NativeHomeReturnFailure.homeChanged }
        guard scope == check.scope else { throw NativeHomeReturnFailure.invalid }
        self.proofId = proofId; self.homeVersion = homeVersion; self.scope = scope
        expiresAt = Date(timeIntervalSince1970: Double(expiresAtMillis) / 1000)
    }
}

public struct NativeHomeRestoreRequest: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let proofId, requestId: String
    public let homeVersion, expectedAccountVersion: Int64
    public let scope: NativeHomeResourceScope
    public init(proof: NativeHomeReturnProof, currentHomeVersion: Int64, expectedAccountVersion: Int64, deviceNow: Date, serverOffset: TimeInterval, requestId: String = UUID().uuidString) throws {
        guard currentHomeVersion == proof.homeVersion else { throw NativeHomeReturnFailure.homeChanged }
        guard deviceNow.addingTimeInterval(serverOffset) < proof.expiresAt else { throw NativeHomeReturnFailure.proofExpired }
        guard ReformWire.version(expectedAccountVersion), ReformWire.requestID(requestId) else { throw NativeHomeReturnFailure.invalid }
        proofId = proof.proofId; self.requestId = requestId; homeVersion = proof.homeVersion; self.expectedAccountVersion = expectedAccountVersion; scope = proof.scope
    }
    public var description: String { "NativeHomeRestoreRequest[redacted]" }
    public var debugDescription: String { description }
    private enum CodingKeys: String, CodingKey { case proofId, requestId, homeVersion, expectedAccountVersion, scopeType, scopeId, resourceType }
    public func validateNative() throws {
        try scope.validateNative()
        guard ReformWire.id(proofId), proofId.utf8.count <= 64, ReformWire.requestID(requestId), ReformWire.version(homeVersion),
              ReformWire.version(expectedAccountVersion) else { throw NativeHomeReturnFailure.invalid }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proofId = try c.decode(String.self, forKey: .proofId); requestId = try c.decode(String.self, forKey: .requestId)
        homeVersion = try c.decode(Int64.self, forKey: .homeVersion)
        expectedAccountVersion = try c.decode(Int64.self, forKey: .expectedAccountVersion)
        guard try c.decode(String.self, forKey: .scopeType) == "RUN" else { throw NativeHomeReturnFailure.invalid }
        scope = .run(runId: try c.decode(String.self, forKey: .scopeId), resourceType: try c.decode(String.self, forKey: .resourceType))
        try validateNative()
    }
    public func encode(to encoder: Encoder) throws {
        try validateNative()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(proofId, forKey: .proofId); try c.encode(requestId, forKey: .requestId)
        try c.encode(homeVersion, forKey: .homeVersion); try c.encode(expectedAccountVersion, forKey: .expectedAccountVersion)
        try c.encode(scope.wire["scopeType"], forKey: .scopeType)
        try c.encode(scope.wire["scopeId"], forKey: .scopeId); try c.encode(scope.wire["resourceType"], forKey: .resourceType)
    }

}

public struct NativeHomeRestoreReceipt: Decodable, Equatable, Sendable {
    public enum Decision: String, Decodable, Sendable {
        case restored = "RESTORED", alreadyAtMax = "ALREADY_AT_MAX", proofConsumed = "PROOF_CONSUMED", staleHome = "STALE_HOME"
        case proofExpired = "PROOF_EXPIRED", cooldown = "COOLDOWN", versionConflict = "VERSION_CONFLICT", runUnavailable = "RUN_UNAVAILABLE", proofUnavailable = "PROOF_UNAVAILABLE"
    }
    public let requestId, proofId: String
    public let decision: Decision
    public let current, maximum: Int64
    public let accountVersion: Int64
    public let retryAfterSeconds: Int?
    /// Server max is authoritative; restore lands exactly on it and never exceeds it.
    public func validate(for request: NativeHomeRestoreRequest) throws {
        guard requestId == request.requestId, proofId == request.proofId, current >= 0, maximum >= 0, current <= maximum, ReformWire.version(accountVersion) else { throw NativeHomeReturnFailure.invalid }
        if decision == .restored || decision == .alreadyAtMax {
            guard maximum > 0, current == maximum else { throw NativeHomeReturnFailure.invalid }
        }
        switch decision {
        case .restored: guard current == maximum, accountVersion == request.expectedAccountVersion + 1, retryAfterSeconds == nil else { throw NativeHomeReturnFailure.invalid }
        case .alreadyAtMax: guard accountVersion == request.expectedAccountVersion, retryAfterSeconds == nil else { throw NativeHomeReturnFailure.invalid }
        case .cooldown: guard let retryAfterSeconds, retryAfterSeconds > 0, accountVersion == request.expectedAccountVersion else { throw NativeHomeReturnFailure.invalid }
        case .versionConflict:
            guard accountVersion != request.expectedAccountVersion, retryAfterSeconds == nil else { throw NativeHomeReturnFailure.invalid }
        default: guard retryAfterSeconds == nil else { throw NativeHomeReturnFailure.invalid }
        }
    }
    /// User-facing failure for non-success decisions; nil when the resource is now full.
    public var failure: NativeHomeReturnFailure? {
        switch decision {
        case .restored, .alreadyAtMax: return nil
        case .proofConsumed, .proofUnavailable: return .proofExpired // A consumed/missing proof is NOT evidence this request restored.
        case .staleHome: return .homeChanged
        case .proofExpired: return .proofExpired
        case .cooldown: return .cooldown(retryAfterSeconds: retryAfterSeconds ?? 0)
        case .versionConflict: return .unknown
        case .runUnavailable: return .runUnavailable
        }
    }
}
