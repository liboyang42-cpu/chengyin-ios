import Foundation

/// A datum belongs to the coordinate, never to the selected UI language.
public enum WalkingCoordinateDatum: String, Codable, Hashable { case wgs84, gcj02 }
public struct WalkingCoordinate: Hashable {
    public let point: RoamCoordinate
    public let datum: WalkingCoordinateDatum
    public let region: String
    public init(point: RoamCoordinate, datum: WalkingCoordinateDatum, region: String) throws {
        guard region.count == 2, region.utf8.allSatisfy({ (65...90).contains($0) }) else { throw WalkingNavigationFailure.coordinateUnsupported }
        self.point = point; self.datum = datum; self.region = region
    }
}

/// Identity only. A reference is not proof of access and contains no future-node geometry.
public struct WalkingTargetReference: Codable, Hashable {
    public enum Kind: String, Codable { case cityNode, nearbyNode, merchant, storyNode }
    public let kind: Kind
    public let id: Int
    public let missionID: Int?
    public init(kind: Kind, id: Int, missionID: Int? = nil) throws {
        guard id > 0, kind == .storyNode ? (missionID ?? 0) > 0 : missionID == nil else { throw WalkingNavigationFailure.targetUnavailable }
        self.kind = kind; self.id = id; self.missionID = missionID
    }
    public var isValid: Bool { id > 0 && (kind == .storyNode ? (missionID ?? 0) > 0 : missionID == nil) }
}

/// Supplied only by the current backend-authoritative target reader. The route provider may
/// calculate a physical path to this target, but cannot choose, sort or unlock story nodes.
public struct AuthorizedWalkingTarget: Equatable {
    public let reference: WalkingTargetReference
    public let title: String
    public let coordinate: WalkingCoordinate
    public let authorityRevision: String
    public let releaseID: String?
    public let expiresAt: Date
    public let address: String?
    public let businessTime: String?
    public init(reference: WalkingTargetReference, title: String, coordinate: WalkingCoordinate,
                authorityRevision: String, releaseID: String? = nil, expiresAt: Date,
                address: String? = nil, businessTime: String? = nil) throws {
        guard reference.isValid, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 300, !authorityRevision.isEmpty, authorityRevision.count <= 200,
              reference.kind != .storyNode || !(releaseID ?? "").isEmpty,
              expiresAt.timeIntervalSince1970.isFinite else { throw WalkingNavigationFailure.targetUnavailable }
        self.reference = reference; self.title = title; self.coordinate = coordinate
        self.authorityRevision = authorityRevision; self.releaseID = releaseID; self.expiresAt = expiresAt
        self.address = address; self.businessTime = businessTime
    }
}

public enum WalkingNavigationFailure: String, Error, Equatable {
    case unavailable, targetUnavailable, coordinateUnsupported, permissionRequired, permissionDenied
    case weakGPS, noRoute, network, throttled, cancelled, staleContext, replanLimit
}
public enum WalkingLocationAuthorization: Equatable { case notDetermined, authorized, denied }
@MainActor public protocol WalkingTargetAuthorizing {
    func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget
}
@MainActor public protocol WalkingLocationProviding: AnyObject {
    var authorization: WalkingLocationAuthorization { get }
    /// Must never prompt for permission. Authorization is an independent, explicit workflow.
    func currentFix() async throws -> RoamDeviceFix
    func stop()
}

/// All provider output geometry stays in its declared datum. AppKit/MapKit rendering is not
/// evidence that a GCJ02 value is WGS84. A future reviewed mainland provider fits this seam.
public struct WalkingProviderEvidence: Equatable {
    public let identifier: String
    public let attribution: String
    public let fetchedAt: Date
    public let advisoryNotices: [String]
    public init(identifier: String, attribution: String, fetchedAt: Date, advisoryNotices: [String] = []) {
        self.identifier = identifier; self.attribution = attribution
        self.fetchedAt = fetchedAt; self.advisoryNotices = advisoryNotices
    }
}

/// Minimal optional resume record: no coordinates, fixes, route geometry or credential.
/// It is scoped by the owning factory; restoration always reauthorizes and obtains a new route.
public struct WalkingNavigationCheckpoint: Codable, Equatable {
    public let reference: WalkingTargetReference
    public let ownerNamespace: String
    public init(reference: WalkingTargetReference, ownerNamespace: String) {
        self.reference = reference; self.ownerNamespace = ownerNamespace
    }
}
