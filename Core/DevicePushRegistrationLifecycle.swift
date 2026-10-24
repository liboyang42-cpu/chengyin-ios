import Foundation

/// C09 exclusive device / environment / silent push registration lifecycle.
/// Fixture tokens are not production APNs credentials. Revoked or disabled devices
/// must not send even if the current projection claims APPLIED.
public struct DevicePushRegistrationLifecycle: Equatable {
    public static let envSandbox = "SANDBOX"
    public static let envProductionLabel = "PRODUCTION_LABEL"
    public static let statusActive = "ACTIVE"
    public static let statusRevoked = "REVOKED"
    public static let statusDisabled = "DISABLED"

    public struct Registration: Equatable, Sendable {
        public var deviceId: String?
        public var environment: String?
        public var silent: Bool
        public var fixtureToken: String?
        public var status: String?
        public func jsonObject() -> [String: Any] {
            [
                "deviceId": deviceId.map { $0 as Any } ?? NSNull(),
                "environment": environment.map { $0 as Any } ?? NSNull(),
                "silent": silent,
                "status": status.map { $0 as Any } ?? NSNull(),
                "fixtureTokenPrefix": "fixture-"
            ]
        }
        public func withToken(environment: String, silent: Bool, fixtureToken: String, status: String) -> Registration {
            var copy = self
            copy.environment = environment
            copy.silent = silent
            copy.fixtureToken = fixtureToken
            copy.status = status
            return copy
        }
        public func withStatus(_ status: String) -> Registration {
            var copy = self
            copy.status = status
            return copy
        }
    }

    public struct SendDecision: Equatable, Sendable {
        public var allowed: Bool
        public var registration: Registration
        public var reason: String
        public var currentProjectionClaimsApplied: Bool
    }

    public private(set) var originalByDeviceID: [String: Registration] = [:]
    public init() {}

    public mutating func register(deviceId: String?, environment: String?, silent: Bool, fixtureToken: String?) throws -> Registration {
        let id = try Self.requireDeviceId(deviceId)
        let env = try Self.requireEnvironment(environment)
        let token = try Self.requireFixtureToken(fixtureToken)
        if let existing = originalByDeviceID[id] {
            if existing.status == Self.statusRevoked {
                throw NotifyFailure.revokedDeviceCannotReregister
            }
            if existing.environment != env || existing.silent != silent || existing.fixtureToken != token {
                let updated = existing.withToken(environment: env, silent: silent, fixtureToken: token, status: Self.statusActive)
                originalByDeviceID[id] = updated
                return updated
            }
            return existing
        }
        let created = Registration(deviceId: id, environment: env, silent: silent, fixtureToken: token, status: Self.statusActive)
        originalByDeviceID[id] = created
        return created
    }

    public mutating func disable(deviceId: String?) throws -> Registration {
        let original = try require(deviceId)
        if original.status == Self.statusRevoked { return original }
        let next = original.withStatus(Self.statusDisabled)
        if let id = next.deviceId { originalByDeviceID[id] = next }
        return next
    }

    public mutating func revoke(deviceId: String?) throws -> Registration {
        var original = try require(deviceId)
        original = original.withStatus(Self.statusRevoked)
        if let id = original.deviceId { originalByDeviceID[id] = original }
        return original
    }

    public func maySend(deviceId: String?, appliedProjection: String?) throws -> SendDecision {
        let original = try require(deviceId)
        let projectionClaimsApplied = appliedProjection == ImmutableReceiptProducer.projectionApplied
        if original.status == Self.statusRevoked || original.status == Self.statusDisabled {
            return SendDecision(allowed: false, registration: original, reason: "REVOKED_OR_DISABLED",
                                currentProjectionClaimsApplied: projectionClaimsApplied)
        }
        return SendDecision(allowed: true, registration: original, reason: "ACTIVE",
                            currentProjectionClaimsApplied: projectionClaimsApplied)
    }

    public mutating func recoverOriginal(originalRequestID: String, appliedProjection: String?) -> Registration {
        recoverUnknown(originalRequestID: originalRequestID, appliedProjection: appliedProjection)
    }

    public mutating func recoverUnknown(originalRequestID: String, appliedProjection: String?) -> Registration {
        guard let id = ImmutableReceiptProducer.parse(originalRequestID, limit: 128) else {
            return Registration(deviceId: nil, environment: nil, silent: false, fixtureToken: nil, status: "UNKNOWN")
        }
        if let original = originalByDeviceID[id] { return original }
        return Registration(deviceId: id, environment: nil, silent: false, fixtureToken: nil, status: "UNKNOWN")
    }

    public func treatsAppliedProjectionAsAuthorization(_ appliedProjection: String?) -> Bool {
        false
    }

    public func treatsAppliedProjectionAsOriginalProof(_ appliedProjection: String?) -> Bool {
        false
    }

    private func require(_ deviceId: String?) throws -> Registration {
        let id = try Self.requireDeviceId(deviceId)
        guard let original = originalByDeviceID[id] else { throw NotifyFailure.originalMissing(id) }
        return original
    }

    static func requireDeviceId(_ deviceId: String?) throws -> String {
        guard let id = ImmutableReceiptProducer.parse(deviceId, limit: 128) else {
            throw NotifyFailure.missingOriginalRequestID
        }
        return id
    }

    static func requireEnvironment(_ environment: String?) throws -> String {
        guard let env = ImmutableReceiptProducer.parse(environment),
              env == envSandbox || env == envProductionLabel else {
            throw NotifyFailure.invalidEnvironment
        }
        return env
    }

    static func requireFixtureToken(_ fixtureToken: String?) throws -> String {
        guard let token = ImmutableReceiptProducer.parse(fixtureToken, limit: 256), token.hasPrefix("fixture-") else {
            throw NotifyFailure.invalidFixtureToken
        }
        return token
    }
}
