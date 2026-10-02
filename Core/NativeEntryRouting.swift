import Foundation

/// Typed, source-backed inbound routes. Never infer merchant/member identity from an invite.
public enum NativeEntryIntent: Equatable {
    case teamInvitation(TeamInvitationRoute)
    case badge(ObjectBadgeDetailParameters)
    case routeError(NativeRouteFailure)
    case door(DoorIntent)
    case merchantInvitation(MerchantOperatorInviteRoute)
    case publicMerchant(PublicMerchantHomeTarget)
}
public struct NativeEntryPresentation: Identifiable {
    public let id = UUID()
    public let intent: NativeEntryIntent
    public init(intent: NativeEntryIntent) { self.intent = intent }
}
/// Empty in the app host. An OS callback alone is not an origin/domain approval.
public struct NativeEntryLinkPolicy {
    private let origins: Set<String>
    public init(verifiedHTTPSOrigins: Set<String> = []) { origins = verifiedHTTPSOrigins }
    public func parse(_ url: URL) -> NativeEntryIntent? {
        guard url.absoluteString.utf8.count <= 8192, let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.port == nil, c.fragment == nil, origins.contains("https://" + host.lowercased()) else { return nil }
        if let route = NativeNavigationContract.parse(path: c.percentEncodedPath, items: c.queryItems ?? []) { return route }
        if c.percentEncodedPath == "/door" {
            return DoorLinkPolicy(verifiedHTTPSOrigins: origins).parse(url).map(NativeEntryIntent.door)
        }
        let parts = c.percentEncodedPath.split(separator: "/").map(String.init)
        if c.percentEncodedPath == "/" + parts.joined(separator: "/"), c.query == nil, parts.count == 4, parts[0] == "merchant", parts[1] == "public-home", parts[2] == "member",
           let value = Int(parts[3]), String(value) == parts[3], let owner = PublicMerchantOwnerID(value) {
            return .publicMerchant(.ownerMemberID(owner))
        }
        if c.percentEncodedPath == "/" + parts.joined(separator: "/"), c.query == nil, parts.count == 3, parts[0] == "merchant", parts[1] == "public-home",
           let value = Int(parts[2]), String(value) == parts[2], let row = PublicMerchantRowID(value) {
            return .publicMerchant(.legacyMerchantRowID(row))
        }
        guard c.percentEncodedPath == "/merchant/team", let items = c.queryItems,
              items.count == 1, items[0].name == "invite",
              c.percentEncodedQuery?.hasPrefix("invite=") == true,
              let route = try? MerchantOperatorInviteRoute(path: c.percentEncodedPath, queryItems: items) else { return nil }
        return .merchantInvitation(route)
    }
}
