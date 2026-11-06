import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Unmounted, independently reviewed permission for one owned registration at one full context.
/// No shipped factory issues this grant. Login, catalog flags and read approvals cannot mint it.
@MainActor @Observable final class FreeExploreBundleReservationApproval {
    let context: RuntimeDependencyContext
    let registrationID: FreeExploreLaunchID
    let revision = UUID()
    let expiresAt: Date
    private(set) var revoked = false
    @ObservationIgnored private var expiry: Task<Void, Never>?
    init(context: RuntimeDependencyContext, registrationID: FreeExploreLaunchID, expiresAt: Date) throws {
        let remaining = expiresAt.timeIntervalSinceNow
        guard context.market == .china, context.session.accountID > 0,
              ["player", "club", "merchant"].contains(context.role),
              AuthRequestBuilder.isValidToken(context.session.token), remaining.isFinite,
              remaining > 0, remaining <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.registrationID = registrationID; self.expiresAt = expiresAt
        expiry = Task { @MainActor [weak self] in
            guard let end = self?.expiresAt else { return }
            do { try await Task.sleep(nanoseconds: UInt64(max(0, end.timeIntervalSinceNow) * 1_000_000_000)) }
            catch { return }
            self?.revoke()
        }
    }
    func matches(context: RuntimeDependencyContext, registrationID: FreeExploreLaunchID) -> Bool {
        !revoked && Date() < expiresAt && self.context == context && self.registrationID == registrationID
    }
    func revoke() { revoked = true; expiry?.cancel(); expiry = nil }
    deinit { expiry?.cancel() }
}

/// Composes with an ALREADY scoped read transport. GET delegation does not widen its allowlist.
/// POST requires the durable exact original command; this adapter never creates/changes/clears it.
@MainActor final class FreeExploreBundleReservationTransport: HTTPTransport {
    private let captured: RuntimeDependencyContext
    private let registrationID: FreeExploreLaunchID
    private let pending: FreeExploreLaunchPendingStore
    private let readTransport: FreeExploreBundleReadTransport
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selectApproval: () -> FreeExploreBundleReservationApproval?
    private var active = true
    init(context: RuntimeDependencyContext, registrationID: FreeExploreLaunchID,
         pending: FreeExploreLaunchPendingStore, readTransport: FreeExploreBundleReadTransport,
         underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
         selectApproval: @escaping () -> FreeExploreBundleReservationApproval? = { nil }) throws {
        let session = try FreeExploreLaunchSession(baseURL: context.baseURL, accountID: Int64(context.session.accountID),
            market: context.market.rawValue, namespace: context.session.namespace, role: context.role,
            epoch: context.session.epoch, token: context.session.token)
        guard pending.matches(session), readTransport.isBound(to: pending, context: context), readTransport.isCurrent else { throw FreeExploreLaunchFailure.invalid }
        captured = context; self.registrationID = registrationID; self.pending = pending
        self.readTransport = readTransport; self.underlying = underlying
        self.current = current; self.selectApproval = selectApproval
    }
    var permitsReservationDispatch: Bool {
        active && readTransport.isCurrent && current() == captured && selectApproval()?.matches(context: captured, registrationID: registrationID) == true
    }
    func retire() { active = false }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard active, readTransport.isCurrent, current() == captured else { throw FreeExploreLaunchFailure.staleSession }
        if request.httpMethod == "GET" { return try await readTransport.send(request) }
        guard request.httpMethod == "POST", let approval = selectApproval(),
              approval.matches(context: captured, registrationID: registrationID),
              request.url?.absoluteString == captured.baseURL.appendingPathComponent("api/free-explore/bundle/reservation").absoluteString,
              request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Authorization") == captured.session.token,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8",
              let body = request.httpBody, body.count <= 16_384,
              request.value(forHTTPHeaderField: "Content-Length") == String(body.count),
              let original = try pending.load(), original.registrationId == registrationID,
              body == (try original.wireData()) else { throw FreeExploreLaunchFailure.disabled }
        // Persistence and all authorization fences are checked again at the actual transport boundary.
        try Task.checkCancellation()
        guard active, readTransport.isCurrent, current() == captured, selectApproval() === approval,
              approval.matches(context: captured, registrationID: registrationID) else { throw FreeExploreLaunchFailure.disabled }
        let result = try await underlying.send(request)
        try Task.checkCancellation()
        guard active, readTransport.isCurrent, current() == captured, selectApproval() === approval,
              approval.matches(context: captured, registrationID: registrationID) else { throw FreeExploreLaunchFailure.outcomeUnknown }
        if result.0.count <= 1_048_576,
           let envelope = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] {
            // A legacy controller may express login loss as business 409 + LOGIN_REQUIRED.
            // Never treat that as receipt absence or clear the original durable command.
            if result.1 == 403 || envelope["code"] as? Int == 403 || envelope["businessCode"] as? String == "LOGIN_REQUIRED" {
                approval.revoke()
            }
        } else if result.1 == 403 { approval.revoke() }
        // Matching 401 remains for FreeExploreLaunchService's captured-session expiry callback.
        return result
    }
}
