import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently issued CN IM history-read lease; no mutation or membership authority.
/// Server conversation membership and blocked-user history semantics remain authoritative. Default issuance is nil.
/// Revoke an old lease before removing/replacing it. Revocation cannot be reversed.
/// Authentication, display values, roles and other read grants cannot issue this lease.
@available(macOS 14.0, *)
@MainActor @Observable public final class MessagingHistoryReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        _ = try APIConfiguration(baseURL: context.baseURL)
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

/// Canonical source history forms only. No caller-supplied member identity, receipt,
/// start/send/mute/block/unblock action, query, duplicate field or alternate encoding.
public enum MessagingHistoryReadRoute: Equatable {
    case conversations
    case messages(conversationID: Int, cursor: Int, size: Int)
    public init?(request: URLRequest, baseURL: URL) {
        let prefix = "multipart/form-data; boundary="
        guard let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(prefix),
              let body = request.httpBody, body.count <= 4096,
              let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst(prefix.count))
        let fields: [String: String]
        let route: Self
        if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/im/conversations").absoluteString.utf8) {
            fields = [:]; route = .conversations
        } else if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/im/messages").absoluteString.utf8) {
            // Extract only digits; canonical reconstruction below validates every byte.
            func value(_ key: String) -> String? {
                let marker = "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n"
                guard let range = text.range(of: marker), let end = text[range.upperBound...].range(of: "\r\n") else { return nil }
                return String(text[range.upperBound..<end.lowerBound])
            }
            guard let cid = value("conversation_id"), let id = Int(cid), id > 0, String(id) == cid,
                  let cursor = value("cursor_id"), let cursorID = Int(cursor), cursorID >= 0, String(cursorID) == cursor,
                  let size = value("size"), let count = Int(size), (1...50).contains(count), String(count) == size else { return nil }
            fields = ["conversation_id": cid, "cursor_id": cursor, "size": size]
            route = .messages(conversationID: id, cursor: cursorID, size: count)
        } else { return nil }
        guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: fields,
            token: request.value(forHTTPHeaderField: "Authorization"), boundary: boundary), canonical.httpBody == body else { return nil }
        self = route
    }
}
