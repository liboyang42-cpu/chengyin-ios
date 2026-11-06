import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public roster capability matches three exact POST read shapes, never a prefix.
public enum ClubPublicRosterRoute {
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let bytes = request.httpBody, bytes.count <= 1_024,
              let fields = try? JSONDecoder().decode([String: ClubGovernanceValue].self, from: bytes), let url = request.url else { return false }
        func positive(_ key: String) -> Bool { guard let value = fields[key] else { return false }; if case .integer(let id) = value { return id > 0 }; return false }
        // A public read grant must not carry a command/recovery header from another lane.
        guard !(request.allHTTPHeaderFields ?? [:]).keys.contains(where: { $0.lowercased().hasPrefix("x-club-") }) else { return false }
        if url == baseURL.appendingPathComponent("api/club/detail") { return Set(fields.keys) == ["id"] && positive("id") }
        if url == baseURL.appendingPathComponent("api/club/members") { return Set(fields.keys) == ["clubId"] && positive("clubId") }
        if url == baseURL.appendingPathComponent("api/club/leaderboard") {
            return Set(fields.keys) == ["id", "sortBy"] && positive("id") &&
                ["composite", "mileage", "pace", "duration"].contains(fields["sortBy"]?.string ?? "")
        }
        return false
    }
}
