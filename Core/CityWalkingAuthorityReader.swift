import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// First-party read of the original public city POI and explicit normalized navigation declaration. No cached coordinates,
/// client country inference, synthetic release ID or client-side WGS84 relabeling.
@MainActor public final class CityWalkingAuthorityReader: WalkingTargetAuthorizing {
    private let owner: RuntimeDependencyContext
    private let transport: any HTTPTransport
    private let current: () -> Bool
    public init(owner: RuntimeDependencyContext, transport: any HTTPTransport,
                current: @escaping () -> Bool) {
        self.owner=owner;self.transport=transport;self.current=current
    }
    private struct Wire: Decodable {
        let schemaVersion: Int
        let kind: String
        let id: Int
        let title: String
        let longitude: Double
        let latitude: Double
        let datum: String
        let region: String
        let authorityRevision: String
        let issuedAtMs: Int64
        let expiresAtMs: Int64
    }
    public func authorize(_ reference: WalkingTargetReference) async throws -> AuthorizedWalkingTarget {
        try fence()
        guard reference.isValid else { throw WalkingNavigationFailure.targetUnavailable }
        guard reference.kind == .cityNode, reference.missionID == nil else { throw WalkingTargetReadFailure.unsupportedKind }
        guard var url=URLComponents(url: owner.baseURL.appendingPathComponent("api/city/walking/target"), resolvingAgainstBaseURL:false) else { throw WalkingNavigationFailure.unavailable }
        url.queryItems=[.init(name:"poi_id",value:String(reference.id))]
        guard let endpoint=url.url, endpoint.scheme == "https" else { throw WalkingNavigationFailure.unavailable }
        var request=URLRequest(url:endpoint);request.httpMethod="GET"
        request.setValue(owner.session.token, forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        let (bytes,status)=try await transport.send(request);try fence()
        guard status == 200 else { throw APIError.httpStatus(status) }
        guard bytes.count <= 16_384 else { throw WalkingNavigationFailure.targetUnavailable }
        let wire=try JSONDecoder().decode(Wire.self,from:bytes)
        let now=Date().timeIntervalSince1970, issued=Double(wire.issuedAtMs)/1000, expires=Double(wire.expiresAtMs)/1000
        guard wire.schemaVersion == 1, wire.kind == reference.kind.rawValue, wire.id == reference.id,
              wire.datum == "wgs84", wire.longitude.isFinite, wire.latitude.isFinite,
              abs(wire.longitude) <= 180, abs(wire.latitude) <= 90,
              wire.issuedAtMs > 0, expires > issued, expires-issued <= 300,
              abs(now-issued) <= 30, expires > now, expires-now <= 300,
              wire.authorityRevision.hasPrefix("city:\(reference.id):") else {
            throw WalkingNavigationFailure.targetUnavailable
        }
        guard let point=RoamCoordinate(latitude:wire.latitude,longitude:wire.longitude) else { throw WalkingNavigationFailure.targetUnavailable }
        return try AuthorizedWalkingTarget(reference:reference,title:wire.title,
            coordinate:WalkingCoordinate(point:point,datum:.wgs84,region:wire.region),
            authorityRevision:wire.authorityRevision,expiresAt:Date(timeIntervalSince1970:expires))
    }
    private func fence() throws {try Task.checkCancellation();guard current() else {throw WalkingNavigationFailure.staleContext}}
}

public enum CityWalkingReadRoute {
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.httpMethod == "GET", request.httpBody == nil,
              request.value(forHTTPHeaderField:"Cookie") == nil, let url=request.url,
              var parts=URLComponents(url:url,resolvingAgainstBaseURL:false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else {return false}
        let items=parts.queryItems ?? [];parts.query=nil
        guard parts.url == baseURL.appendingPathComponent("api/city/walking/target"),
              items.count == 1, Set(items.map(\.name)) == ["poi_id"] else {return false}
        return items.allSatisfy {item in guard let raw=item.value,let n=Int(raw),n>0 else{return false};return String(n)==raw}
    }
}
