import Foundation

@MainActor public protocol PersonalLocationShareServicing: AnyObject {
    var scope: PersonalLocationShareScope { get }
    var isSynthetic: Bool { get }
    func context(recipientId: Int64) async throws -> PersonalLocationShareContext
    func create(_ request: PersonalLocationShareCreate) async throws -> PersonalLocationShareReceipt
    func requestStatus(requestKey: String) async throws -> PersonalLocationShareReceipt
    func revoke(requestKey: String) async throws -> PersonalLocationShareReceipt
    func owned() async throws -> PersonalLocationShareOwned
    func received() async throws -> PersonalLocationShareSnapshot
    func events(cursor: Int64) async throws -> PersonalLocationShareEventBatch
    func publish(grantId: String, observation: PersonalLocationSharePublish, synthetic: Bool) async throws -> PersonalLocationSharePublished
}
public enum PersonalLocationShareSystemAccuracy: String, Sendable { case full, reduced, unknown }
public struct PersonalLocationShareSample: Sendable {
    public let observedAtMs: Int64
    public let datum: String
    public let latitude: Double
    public let longitude: Double
    public let sourceId: String
    public let systemAccuracy: PersonalLocationShareSystemAccuracy
    public init(observedAtMs: Int64, datum: String, latitude: Double, longitude: Double, sourceId: String, systemAccuracy: PersonalLocationShareSystemAccuracy) {
        self.observedAtMs = observedAtMs; self.datum = datum; self.latitude = latitude; self.longitude = longitude; self.sourceId = sourceId; self.systemAccuracy = systemAccuracy
    }
}
/// The App host supplies a grant-bound CoreLocation adapter. This interface never requests OS permission.
@MainActor public protocol PersonalLocationShareCoordinateProviding: AnyObject {
    var isSynthetic: Bool { get }
    func sample() async throws -> PersonalLocationShareSample
    func stop()
}

/// In-memory only. Constructed after this session's final confirmation and authoritative ACTIVE grant.
public struct PersonalLocationShareCaptureBinding: Equatable, Sendable {
    public let scope: PersonalLocationShareScope
    public let grant: PersonalLocationShareGrant
    public let confirmationId: UUID
    public let allowsFirstPermissionRequest: Bool
    public let capturePurpose: PersonalLocationShareCaptureApproval
    public init(scope: PersonalLocationShareScope, grant: PersonalLocationShareGrant, confirmationId: UUID, allowsFirstPermissionRequest: Bool, capturePurpose: PersonalLocationShareCaptureApproval) throws {
        guard grant.structurallyValid, grant.ownerId == scope.accountId, grant.status == .active, capturePurpose.scope == scope else {
            throw PersonalLocationShareFailure.invalidContract
        }
        self.scope = scope; self.grant = grant; self.confirmationId = confirmationId; self.allowsFirstPermissionRequest = allowsFirstPermissionRequest; self.capturePurpose = capturePurpose
    }
}
@MainActor public protocol PersonalLocationShareCoordinateFactory: AnyObject {
    var isSynthetic: Bool { get }
    /// Capability inspection only. MUST NOT construct a manager, request permission, or collect coordinates.
    func canCreate(scope: PersonalLocationShareScope) -> Bool
    func confirmationPurpose(scope: PersonalLocationShareScope) -> PersonalLocationShareCaptureApproval?
    func make(binding: PersonalLocationShareCaptureBinding, isCurrent: @escaping () -> Bool) throws -> any PersonalLocationShareCoordinateProviding
}
