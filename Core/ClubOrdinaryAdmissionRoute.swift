import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact request shapes only; this cannot be used as a generic club-prefix grant.
public enum ClubOrdinaryAdmissionRoute {
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let bytes = request.httpBody, bytes.count <= 8_192,
              let fields = try? JSONDecoder().decode([String: ClubGovernanceValue].self, from: bytes), let url = request.url else { return false }
        func positive(_ name: String) -> Bool { guard let value = fields[name] else { return false }; if case .integer(let id) = value, id > 0 { return true }; return false }
        func text(_ name: String) -> String? { fields[name]?.string }
        func uuid(_ value: String?) -> Bool { guard let value, let id = UUID(uuidString: value) else { return false }; return id.uuidString.lowercased() == value }
        func digest(_ value: String?) -> Bool { guard let value else { return false }; return value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
        let headers = ["X-Club-Admission-Request-Id", "X-Club-Admission-Action", "X-Club-Admission-Payload-SHA256"]
        if url == baseURL.appendingPathComponent("api/club/detail") {
            return Set(fields.keys) == ["id"] && positive("id") && headers.allSatisfy { request.value(forHTTPHeaderField: $0) == nil }
        }
        if url == baseURL.appendingPathComponent("api/club/admission/receipt") {
            return Set(fields.keys) == ["clubId", "requestId", "action", "payloadSHA256"] && positive("clubId") &&
                uuid(text("requestId")) && digest(text("payloadSHA256")) && ClubAction(rawValue: text("action") ?? "") != nil &&
                headers.allSatisfy { request.value(forHTTPHeaderField: $0) == nil }
        }
        let isJoin = url == baseURL.appendingPathComponent("api/club/join")
        let isQuit = url == baseURL.appendingPathComponent("api/club/quit")
        guard isJoin || isQuit, positive("id"), uuid(request.value(forHTTPHeaderField: headers[0])),
              let action = ClubAction(rawValue: request.value(forHTTPHeaderField: headers[1]) ?? ""),
              isQuit == (action == .leave), let hash = request.value(forHTTPHeaderField: headers[2]), digest(hash) else { return false }
        let message = text("joinMessage") ?? ""
        guard Set(fields.keys) == (action == .apply ? ["id", "joinMessage"] : ["id"]),
              ClubApplicationMessage.isValid(message, for: action) else { return false }
        return SHA256.hash(data: Data((action.rawValue + "\n" + message).utf8)).map { String(format: "%02x", $0) }.joined() == hash
    }
}
