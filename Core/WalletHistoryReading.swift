import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently issued CN owner-history read lease; no mutation or membership authority.
/// Server ownership remains authoritative. Default issuance is nil.
/// Revoke an old lease before removing/replacing it. Revocation cannot be reversed.
/// Authentication, display values, roles and other read grants cannot issue this lease.
@available(macOS 14.0, *)
@MainActor @Observable public final class WalletHistoryReadApproval {
    public let context: RuntimeDependencyContext
    /// Legacy service adapter narrowed to this lease’s owner-history paths only.
    public let endpoints: OperationEndpointApproval
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.endpoints = try OperationEndpointApproval(baseURL: context.baseURL,
            namespace: context.session.namespace, accountID: context.session.accountID,
            paths: WalletHistoryReadRoute.paths)
        self.context = context; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            // A queued MainActor task must not start the original duration again.
            // Wall-clock request checks remain authoritative throughout suspension.
            let remaining = Self.expiryDelay(until: expiresAt, now: Date())
            do {
                if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                try Task.checkCancellation()
            }
            catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    static func expiryDelay(until deadline: Date, now: Date) -> TimeInterval {
        max(0, min(deadline.timeIntervalSince(now), 86_400))
    }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
    /// Deterministic expiry seam for tests and foreground reconciliation. Never renews a lease.
    public func expireIfNeeded(now: Date = Date()) { if now >= expiresAt { revoke() } }
}

/// Exact shapes emitted by WalletCommerceService, never a prefix or finance-write grant.
public struct WalletHistoryReadRoute: Equatable {
    public let path: String
    public static let paths: Set<String> = ["api/user/info", "api/wallet/stages", "api/balance/list",
        "api/points/list", "api/user/balance/list", "api/withdrawal/list"]
    public init?(request: URLRequest, baseURL: URL, accountID: Int) {
        guard accountID > 0, let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let path = Self.paths.first(where: { url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent($0).absoluteString.utf8) }) else { return nil }
        if path == "api/withdrawal/list" {
            guard request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil else { return nil }
        } else if path == "api/wallet/stages" {
            guard request.httpBody == Data("{}".utf8), request.value(forHTTPHeaderField: "Content-Type") == "application/json" else { return nil }
        } else {
            guard let body = request.httpBody, body.count <= 2048, let text = String(data: body, encoding: .utf8),
                  let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary=") else { return nil }
            let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
            guard !boundary.isEmpty, boundary.count <= 70,
                  boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
            let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\""
            var fields: [String: String] = [:]
            // Parse only to reconstruct with the canonical native builder. Duplicates,
            // alternate headers/ordering/encodings and trailing bytes are rejected.
            if text != "--\(boundary)--\r\n" {
                let chunks = text.components(separatedBy: prefix)
                guard chunks.first == "", chunks.count <= 4 else { return nil }
                for chunk in chunks.dropFirst() {
                    let pair = chunk.components(separatedBy: "\"\r\n\r\n")
                    guard pair.count == 2, fields[pair[0]] == nil else { return nil }
                    let suffix = pair[1].hasSuffix("\r\n--\(boundary)--\r\n") ? "\r\n--\(boundary)--\r\n" : "\r\n"
                    guard pair[1].hasSuffix(suffix) else { return nil }
                    fields[pair[0]] = String(pair[1].dropLast(suffix.count))
                }
            }
            func positive(_ key: String, limit: Int) -> Bool {
                guard let value = fields[key], let number = Int(value), (1...limit).contains(number) else { return false }
                return value == String(number)
            }
            switch path {
            case "api/user/info": guard fields == ["member_id": String(accountID)] else { return nil }
            case "api/balance/list": guard fields.isEmpty || fields == ["change_type": "1"] || fields == ["change_type": "2"] else { return nil }
            case "api/user/balance/list":
                guard positive("pageNum", limit: 10_000), fields["pageSize"] == "20" else { return nil }
                let keys = Set(fields.keys)
                guard keys == ["pageNum", "pageSize"] || (path == "api/user/balance/list" && keys == ["pageNum", "pageSize", "eventType"] && ["1", "2"].contains(fields["eventType"] ?? "")) else { return nil }
            default: guard fields.isEmpty else { return nil }
            }
            guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields, token: nil, boundary: boundary), canonical.httpBody == body else { return nil }
        }
        self.path = path
    }
}
