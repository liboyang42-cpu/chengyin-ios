import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently issued CN team-read lease; no mutation or membership authority.
/// Server membership and invitation visibility remain authoritative. Default issuance is nil.
/// Revoke an old lease before removing/replacing it. Revocation cannot be reversed.
/// Authentication, display values, roles and other read grants cannot issue this lease.
@available(macOS 14.0, *)
@MainActor @Observable public final class TeamReadApproval {
    public let context: RuntimeDependencyContext
    /// Legacy service adapter narrowed to this lease’s two read paths only.
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
            paths: ["api/team/my", "api/team/info"])
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

/// Only canonical requests emitted by TeamReadOnlyService. No member override,
/// query, alternative encoding, duplicate JSON key, or adjacent mutation is admitted.
public enum TeamReadRoute: Equatable {
    case mine, detail(TeamLookup)
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let body = request.httpBody, body.count <= 4096 else { return nil }
        if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/team/my").absoluteString.utf8) {
            guard body == Data("{}".utf8) else { return nil }; self = .mine; return
        }
        guard url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/team/info").absoluteString.utf8),
              let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any], fields.count == 1 else { return nil }
        let canonical: [String: Any]
        let lookup: TeamLookup
        if let id = fields["teamId"] as? Int, id > 0 {
            canonical = ["teamId": id]; lookup = .id(id)
        } else if let code = fields["inviteCode"] as? String, TeamLookup.validInvite(code),
                  code == code.trimmingCharacters(in: .whitespacesAndNewlines) {
            canonical = ["inviteCode": code]; lookup = .invitation(code)
        } else { return nil }
        guard let encoded = try? JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys]), encoded == body else { return nil }
        self = .detail(lookup)
    }
}
