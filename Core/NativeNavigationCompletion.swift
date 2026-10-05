import Foundation

public enum NativeRouteFailure: String, Equatable { case unsupported, malformed, cannotOpen }
public struct TeamInvitationRoute: Equatable {
    public let code: String
    public let fromTeamID: Int?
    public init(code: String, fromTeamID: Int? = nil) throws {
        guard TeamLookup.validInvite(code), code.utf8.count <= 512,
              !code.contains("://"), fromTeamID.map({ $0 > 0 }) ?? true else { throw APIError.invalidRequest }
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines); self.fromTeamID = fromTeamID
    }
}
/// Source route paths, not an OS scheme registration or a domain approval. Query values
/// are presentation/invitation data only; they never imply ownership, role or entitlement.
public enum NativeNavigationContract {
    public static func parseInternal(_ text: String) -> NativeEntryIntent? {
        guard text.utf8.count <= 4096, !text.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              let c = URLComponents(string: text), c.scheme == nil, c.host == nil,
              c.user == nil, c.password == nil, c.fragment == nil else { return nil }
        return parse(path: c.percentEncodedPath, items: c.queryItems ?? [])
    }
    static func parse(path: String, items: [URLQueryItem]) -> NativeEntryIntent? {
        guard Set(items.map(\.name)).count == items.count, items.allSatisfy({ $0.value != nil }) else { return nil }
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        if path == "/team/join" {
            guard Set(query.keys).isSubset(of: ["code", "fromTeamId"]), let code = query["code"] else { return nil }
            var fromID: Int?
            if let raw = query["fromTeamId"] {
                guard let id = Int(raw), id > 0, String(id) == raw else { return nil }; fromID = id
            }
            return (try? TeamInvitationRoute(code: code, fromTeamID: fromID)).map(NativeEntryIntent.teamInvitation)
        }
        if path == "/badge" {
            guard Set(query.keys).isSubset(of: ["name", "sub", "img", "style", "rarity"]),
                  query.values.allSatisfy({ $0.utf8.count <= 2048 && $0.rangeOfCharacter(from: .controlCharacters) == nil }) else { return nil }
            return .badge(ObjectBadgeDetailParameters(query: query, fallbackName: ""))
        }
        return nil
    }
}
