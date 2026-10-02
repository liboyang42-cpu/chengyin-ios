import Foundation

public enum NativeEnrollmentIssue: String, Error, Equatable {
    case disabled, unsupported, staleSession, invalidContract, expired, clockChanged
    case storageUnavailable, network, rejected, unknownResult, keyRecoveryRequired, busy
}
public struct NativeEnrollmentScope: Codable, Equatable {
    public let namespace: String
    public let accountID: Int
    public let appID: String
    public let environment: String
    public init(namespace: String, accountID: Int, appID: String, environment: String) throws {
        guard !namespace.isEmpty, namespace.count <= 512, accountID > 0,
              appID.count <= 255, appID.range(of: "^[A-Za-z0-9]+\\.[A-Za-z0-9.-]+$", options: .regularExpression) != nil,
              environment == "production" else { throw NativeEnrollmentIssue.invalidContract }
        self.namespace = namespace; self.accountID = accountID; self.appID = appID; self.environment = environment
    }
}
public enum NativeEnrollmentWire {
    public static let provider = "IOS_CMPEDOMETER_V1"
    public static func canonicalBase64(_ text: String, count: ClosedRange<Int>) -> Data? {
        guard text.utf8.count <= ((count.upperBound + 2) / 3) * 4,
              let bytes = Data(base64Encoded: text), count.contains(bytes.count), bytes.base64EncodedString() == text else { return nil }
        return bytes
    }
    public static func validKey(_ value: String) -> Bool { canonicalBase64(value, count: 32...32) != nil }
}
public struct NativeEnrollmentStatus: Equatable {
    public enum State: String { case disabled = "DISABLED", unenrolled = "UNENROLLED", active = "ACTIVE", revoked = "REVOKED", challenge = "CHALLENGE" }
    public let enabled: Bool
    public let state: State
    public let deviceKeyID: String?
    public init(_ raw: PlayWireValue, scope: NativeEnrollmentScope, expectedKey: String?) throws {
        guard raw["protocolVersion"].integer == 1, raw["provider"].text == NativeEnrollmentWire.provider,
              raw["accountId"].integer == scope.accountID, raw["environment"].text == scope.environment,
              raw["rewardEnabled"].bool == false, raw["hardwareVerified"].bool == false,
              let enabled = raw["enabled"].bool, let stateText = raw["status"].text, let state = State(rawValue: stateText),
              raw["deviceKeyId"].text == expectedKey,
              expectedKey.map(NativeEnrollmentWire.validKey) ?? true else { throw NativeEnrollmentIssue.invalidContract }
        if enabled {
            guard state != .disabled, raw["appId"].text == scope.appID else { throw NativeEnrollmentIssue.invalidContract }
        } else { guard state == .disabled, raw["appId"] == .null else { throw NativeEnrollmentIssue.invalidContract } }
        if [.active, .revoked, .challenge].contains(state) { guard expectedKey != nil else { throw NativeEnrollmentIssue.invalidContract } }
        self.enabled = enabled; self.state = state; self.deviceKeyID = expectedKey
    }
}
public struct NativeEnrollmentChallenge: Codable, Equatable {
    public let challengeID: String
    public let challengeBase64: String
    public let deviceKeyID: String
    public let issuedAt: Int
    public let expiresAt: Int
    public init(_ raw: PlayWireValue, scope: NativeEnrollmentScope, key: String) throws {
        let status = try NativeEnrollmentStatus(raw, scope: scope, expectedKey: key)
        guard status.enabled, status.state == .challenge,
              let id = raw["challengeId"].text, id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let nonce = raw["challengeBase64"].text, NativeEnrollmentWire.canonicalBase64(nonce, count: 32...32) != nil,
              let issued = raw["issuedAt"].integer, let expiry = raw["expiresAt"].integer,
              issued > 0, expiry > issued, expiry - issued <= 300_000 else { throw NativeEnrollmentIssue.invalidContract }
        challengeID = id; challengeBase64 = nonce; deviceKeyID = key; issuedAt = issued; expiresAt = expiry
    }
    public func validateIntegrity(expectedKey: String) throws {
        guard deviceKeyID == expectedKey, NativeEnrollmentWire.validKey(deviceKeyID),
              challengeID.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil, nonce != nil,
              issuedAt > 0, expiresAt > issuedAt, expiresAt - issuedAt <= 300_000 else { throw NativeEnrollmentIssue.invalidContract }
    }
    public func validate(now: Date) throws {
        try validateIntegrity(expectedKey: deviceKeyID)
        let ms = now.timeIntervalSince1970 * 1000
        guard ms >= Double(issuedAt - 5_000), ms < Double(expiresAt) else { throw NativeEnrollmentIssue.expired }
    }
    public var nonce: Data? { NativeEnrollmentWire.canonicalBase64(challengeBase64, count: 32...32) }
}
public struct NativeEnrollmentProof: Codable, Equatable {
    public let deviceKeyID: String
    public let challengeID: String
    public let attestationObject: String
    public init(deviceKeyID: String, challengeID: String, attestationObject: String) throws {
        guard NativeEnrollmentWire.validKey(deviceKeyID), challengeID.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              NativeEnrollmentWire.canonicalBase64(attestationObject, count: 1...65_536) != nil else { throw NativeEnrollmentIssue.invalidContract }
        self.deviceKeyID = deviceKeyID; self.challengeID = challengeID; self.attestationObject = attestationObject
    }
    public var payload: [String: PlayWireValue] { ["provider": .string(NativeEnrollmentWire.provider), "deviceKeyId": .string(deviceKeyID), "challengeId": .string(challengeID), "attestationObject": .string(attestationObject)] }
}
public struct NativeEnrollmentRecord: Codable, Equatable {
    public enum Phase: String, Codable { case generating, keyReady, requestingChallenge, attesting, review, enrolling, active, revoking, revoked, rejected }
    public let schema: Int
    public let operationID: UUID
    public let scope: NativeEnrollmentScope
    public var phase: Phase
    public var deviceKeyID: String?
    public var challenge: NativeEnrollmentChallenge?
    public var proof: NativeEnrollmentProof?
    public var retiredKeys: [String]
    public init(scope: NativeEnrollmentScope, phase: Phase = .generating, retiredKeys: [String] = []) {
        schema = 1; operationID = UUID(); self.scope = scope; self.phase = phase; self.retiredKeys = retiredKeys
    }
    public func validate(scope expected: NativeEnrollmentScope) throws {
        guard schema == 1, scope == expected, retiredKeys.count <= 100,
              retiredKeys.allSatisfy(NativeEnrollmentWire.validKey), Set(retiredKeys).count == retiredKeys.count,
              deviceKeyID.map(NativeEnrollmentWire.validKey) ?? true else { throw NativeEnrollmentIssue.invalidContract }
        if phase != .generating { guard deviceKeyID != nil else { throw NativeEnrollmentIssue.invalidContract } }
        if let key = deviceKeyID { guard !retiredKeys.contains(key) else { throw NativeEnrollmentIssue.invalidContract } }
        if let challenge { try challenge.validateIntegrity(expectedKey: deviceKeyID ?? "") }
        if let proof {
            _ = try NativeEnrollmentProof(deviceKeyID: proof.deviceKeyID, challengeID: proof.challengeID, attestationObject: proof.attestationObject)
            guard proof.deviceKeyID == deviceKeyID, proof.challengeID == challenge?.challengeID else { throw NativeEnrollmentIssue.invalidContract }
        }
        if [.review, .enrolling].contains(phase) { guard proof != nil else { throw NativeEnrollmentIssue.invalidContract } }
    }
}
@MainActor public protocol NativeEnrollmentStoring: AnyObject {
    func read(scope: NativeEnrollmentScope) throws -> NativeEnrollmentRecord?
    func write(_ record: NativeEnrollmentRecord) throws
}
@MainActor public protocol NativeEnrollmentDeviceProviding: AnyObject {
    var supported: Bool { get }
    func generateKey() async throws -> String
    /// Implementations must SHA256 these decoded 32 bytes; never hash Base64 text.
    func attest(key: String, challengeBytes: Data) async throws -> String
    func cancel()
}
@MainActor public protocol NativeEnrollmentServing {
    func status(key: String?) async throws -> NativeEnrollmentStatus
    func challenge(key: String) async throws -> NativeEnrollmentChallenge
    func enroll(_ proof: NativeEnrollmentProof) async throws -> NativeEnrollmentStatus
    func revoke(key: String) async throws -> NativeEnrollmentStatus
}
