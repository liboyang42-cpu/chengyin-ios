import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// New, unmounted candidate. Existing owner/deployment acceptance remains required.
/// This approval enables only three GET routes. It never enables reservation dispatch.
@MainActor @Observable final class FreeExploreBundleReadApproval {
    let context: RuntimeDependencyContext
    let revision = UUID()
    let expiresAt: Date
    private(set) var revoked = false
    @ObservationIgnored private var expiry: Task<Void, Never>?
    init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, context.session.accountID > 0,
              ["player", "club", "merchant"].contains(context.role),
              AuthRequestBuilder.isValidToken(context.session.token), duration > 0,
              duration.isFinite, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.expiresAt = expiresAt
        expiry = Task { @MainActor [weak self] in
            guard let end = self?.expiresAt else { return }
            let delay = max(0, end.timeIntervalSinceNow)
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            self?.revoke()
        }
    }
    func matches(_ context: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && self.context == context
    }
    func revoke() { revoked = true; expiry?.cancel(); expiry = nil }
    deinit { expiry?.cancel() }
}

/// Testable, irrevocable navigation lifetime. Pending metadata belongs to the account, not here.
@MainActor @Observable final class FreeExploreBundleReadHost {
    private let captured: RuntimeDependencyContext
    private let approval: FreeExploreBundleReadApproval
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentApproval: () -> FreeExploreBundleReadApproval?
    private let originCurrent: () -> Bool
    private let storage: any TemplateAuthoringStorage
    private let transport: any HTTPTransport
    private let unauthorized: () -> Void
    private(set) var retired = false
    private(set) var busy = false
    private(set) var failed = false
    private(set) var legacy = false
    private(set) var model: FreeExploreBundleLaunchModel?
    private var transportOwner: FreeExploreBundleReadTransport?
    let registrationID: FreeExploreLaunchID
    var current: Bool {
        !retired && currentContext() == captured && currentApproval() === approval &&
        approval.matches(captured) && originCurrent()
    }
    init?(registrationID: Int64, accountID: Int64, context: RuntimeDependencyContext,
          approval: FreeExploreBundleReadApproval?, currentContext: @escaping () -> RuntimeDependencyContext?,
          currentApproval: @escaping () -> FreeExploreBundleReadApproval?, originCurrent: @escaping () -> Bool,
          storage: any TemplateAuthoringStorage, transport: any HTTPTransport, unauthorized: @escaping () -> Void) {
        guard let approval, approval.matches(context), currentApproval() === approval,
              currentContext() == context, originCurrent(), accountID == Int64(context.session.accountID),
              let id = try? FreeExploreLaunchID(registrationID) else { return nil }
        self.registrationID = id; captured = context; self.approval = approval
        self.currentContext = currentContext; self.currentApproval = currentApproval; self.originCurrent = originCurrent
        self.storage = storage; self.transport = transport; self.unauthorized = unauthorized
    }
    func retire() {
        retired = true; transportOwner?.retire(); model?.retire(); model = nil; busy = false
    }
    func load() async {
        guard current, !busy, model == nil else { if !current { retire() }; return }
        busy = true; failed = false; legacy = false
        defer { busy = false; if !current { retire() } }
        do {
            let session = try FreeExploreLaunchSession(baseURL: captured.baseURL,
                accountID: Int64(captured.session.accountID), market: captured.market.rawValue,
                namespace: captured.session.namespace, role: captured.role, epoch: captured.session.epoch,
                token: captured.session.token)
            let pending = FreeExploreLaunchPendingStore(storage: storage, session: session)
            // Read storage before any network request. Unavailable/corrupt storage fails closed.
            _ = try pending.load()
            let gate = try FreeExploreBundleReadTransport(context: captured, registrationID: registrationID,
                pending: pending, underlying: transport, current: { [weak self] in self?.current == true },
                denied: { [weak self] in self?.retire() })
            transportOwner = gate
            let service = FreeExploreLaunchService(session: session, transport: gate,
                currentSession: { [weak self] in self?.current == true ? session : nil },
                onUnauthorized: { [weak self] _ in guard let self, self.current else { return }; self.unauthorized(); self.retire() })
            let order = try await service.order(registrationID: registrationID)
            guard current else { retire(); return }
            guard let bundle = order.bundle else { legacy = true; return }
            // topic comes from the service-validated owned bundle, never ProfileOrder.ownerID.
            gate.bindTopic(bundle.order.topicId)
            model = try FreeExploreBundleLaunchModel(topicID: bundle.order.topicId, registrationID: registrationID,
                service: service, pending: pending) // default host grant FALSE, service writer FALSE
        } catch { if current { failed = true } }
    }
}

@MainActor final class FreeExploreBundleReadTransport: HTTPTransport {
    private let context: RuntimeDependencyContext
    private let registrationID: FreeExploreLaunchID
    private let original: FreeExploreLaunchReservationCommand?
    private let pending: FreeExploreLaunchPendingStore?
    private let underlying: any HTTPTransport
    private let current: () -> Bool
    private let denied: () -> Void
    private var active = true
    private var topicID: FreeExploreLaunchID?
    init(context: RuntimeDependencyContext, registrationID: FreeExploreLaunchID,
         original: FreeExploreLaunchReservationCommand?, underlying: any HTTPTransport,
         current: @escaping () -> Bool, denied: @escaping () -> Void) {
        self.context = context; self.registrationID = registrationID; self.original = original; pending = nil
        self.underlying = underlying; self.current = current; self.denied = denied
    }
    /// A writable composition must share this exact owner-bound store, not an opening-time snapshot.
    init(context: RuntimeDependencyContext, registrationID: FreeExploreLaunchID,
         pending: FreeExploreLaunchPendingStore, underlying: any HTTPTransport,
         current: @escaping () -> Bool, denied: @escaping () -> Void) throws {
        let session = try FreeExploreLaunchSession(baseURL: context.baseURL,
            accountID: Int64(context.session.accountID), market: context.market.rawValue,
            namespace: context.session.namespace, role: context.role, epoch: context.session.epoch,
            token: context.session.token)
        guard pending.matches(session) else { throw FreeExploreLaunchFailure.invalid }
        self.context = context; self.registrationID = registrationID; self.pending = pending; original = nil
        self.underlying = underlying; self.current = current; self.denied = denied
    }
    var isCurrent: Bool { active && current() }
    func isBound(to pending: FreeExploreLaunchPendingStore, context: RuntimeDependencyContext) -> Bool {
        self.pending === pending && self.context == context
    }
    private func currentOriginal() throws -> FreeExploreLaunchReservationCommand? {
        if let pending { return try pending.load() }
        return original
    }
    func retire() { active = false }
    func bindTopic(_ id: FreeExploreLaunchID) { if active && current() { topicID = id } }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard active, current(), request.httpMethod == "GET", request.httpBody == nil,
              request.httpBodyStream == nil, request.value(forHTTPHeaderField: "Authorization") == context.session.token,
              let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil else { throw APIError.notConfigured }
        let original = try currentOriginal()
        let prefix = "api/free-explore/bundle/"
        var candidates: [(String, String, String)] = [("order", "registrationId", registrationID.text)]
        // Recovery may refer to another order of this SAME durable owner, never a new POST.
        if let original {
            candidates.append(("order", "registrationId", original.registrationId.text))
            candidates.append(("reservation/receipt", "idempotencyKey", original.idempotencyKey))
        }
        if let topicID { candidates.append(("catalog", "topicId", topicID.text)) }
        let accepted = candidates.contains { path, name, value in
            var expected = URLComponents(url: context.baseURL.appendingPathComponent(prefix + path), resolvingAgainstBaseURL: false)!
            expected.queryItems = [URLQueryItem(name: name, value: value)]
            return expected.url?.absoluteString == url.absoluteString
        }
        guard accepted else { throw APIError.notConfigured }
        let result = try await underlying.send(request)
        try Task.checkCancellation()
        guard active, current(), try currentOriginal() == original else { throw APIError.notConfigured }
        // Service handles matching 401; a 403 retires this permission, not another login.
        let bodyCode = (try? JSONSerialization.jsonObject(with: result.0) as? [String: Any])?["code"] as? Int
        if result.1 == 403 || bodyCode == 403 { active = false; denied(); throw APIError.notConfigured }
        return result
    }
}
