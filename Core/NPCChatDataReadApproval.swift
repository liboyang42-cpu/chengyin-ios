import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NPCChatDataReadScope {
    public static func matches(_ current: RuntimeDependencyContext?, _ captured: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(current, captured) &&
            current?.session.role.utf8.elementsEqual(captured.session.role.utf8) == true &&
            captured.role.utf8.elementsEqual(captured.session.role.utf8)
    }
}
/// Externally supplied, expiring permission for the owner's already-stored text only.
/// No chat/model, deletion, consent, file export, clipboard or original-request capability.
@MainActor @Observable public final class NPCChatDataReadApproval {
    public let context: RuntimeDependencyContext
    public let revision = UUID()
    public let expiresAt: Date
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0,
              context.role.utf8.elementsEqual(context.session.role.utf8), AuthRequestBuilder.isValidToken(context.session.token),
              expiresAt.timeIntervalSince1970.isFinite, expiresAt > Date() else { throw NPCChatDataFailure.unavailable }
        self.context = context; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && NPCChatDataReadScope.matches(context, self.context)
    }
}
public enum NPCChatDataReadRoute {
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil, parts.query == nil else { return false }
        return url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(NPCChatData.path).absoluteString.utf8)
    }
}
/// Separate from compliance mutation journals and auth-channel services. Reuses the original private DTO/UI.
@MainActor public final class NPCChatDataReader {
    public let approval: NPCChatDataReadApproval
    public let session: ComplianceSession
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> NPCChatDataReadApproval?
    private var retired = false
    private final class WeakOwner {
        weak var value: NPCChatDataCoordinator?
        init(_ value: NPCChatDataCoordinator) { self.value = value }
    }
    private var owners: [WeakOwner] = []
    public init(approval: NPCChatDataReadApproval, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> NPCChatDataReadApproval?) {
        self.approval = approval; self.transport = transport; self.current = current; self.selected = selected
        session = .init(accountID: approval.context.session.accountID, epoch: approval.context.session.epoch,
            market: approval.context.market.rawValue, namespace: approval.context.session.namespace)
    }
    public var isCurrent: Bool {
        guard !retired, let context = current(), approval.matches(context), let selected = selected(context) else { return false }
        return selected === approval && selected.matches(context)
    }
    public func canRead(_ session: ComplianceSession) -> Bool { session.valid && session == self.session && isCurrent }
    public func makeCoordinator() -> NPCChatDataCoordinator {
        let owner = NPCChatDataCoordinator(current: { [weak self] in
            guard let self, self.isCurrent else { return nil }; return self.session
        }, available: { [weak self] in self?.canRead($0) == true }, read: { [self] in try await read($0) })
        // No optional deletion closure, service or receipt coordinator is passed.
        owners.removeAll { $0.value == nil }; owners.append(.init(owner)); return owner
    }
    public func retire() { retired = true; owners.forEach { $0.value?.invalidate() }; owners.removeAll() }
    private func denied(_ signedOut: Bool) -> NPCChatDataFailure {
        approval.revoke(); owners.forEach { $0.value?.invalidate() }; owners.removeAll()
        return signedOut ? .signedOut : .rejected
    }
    private struct Status: Decodable { let code: Int }
    public func read(_ session: ComplianceSession) async throws -> NPCChatData {
        try Task.checkCancellation()
        guard canRead(session) else { throw NPCChatDataFailure.unavailable }
        var request = URLRequest(url: approval.context.baseURL.appendingPathComponent(NPCChatData.path))
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard NPCChatDataReadRoute.accepts(request, baseURL: approval.context.baseURL) else { throw NPCChatDataFailure.malformed }
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch {
            try Task.checkCancellation(); guard isCurrent else { throw NPCChatDataFailure.staleSession }
            if let api = error as? APIError {
                if [APIError.unauthorized, .httpStatus(401), .businessCode(401)].contains(api) { throw denied(true) }
                if [APIError.httpStatus(403), .businessCode(403)].contains(api) { throw denied(false) }
            }
            throw error
        }
        try Task.checkCancellation(); guard isCurrent else { throw NPCChatDataFailure.staleSession }
        if response.1 == 401 || response.1 == 403 { throw denied(response.1 == 401) }
        guard (200..<300).contains(response.1) else { throw NPCChatDataFailure.failed }
        guard response.0.count <= 8_388_608 else { throw NPCChatDataFailure.tooLarge }
        guard let text = String(data: response.0, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil,
              let status = try? JSONDecoder().decode(Status.self, from: response.0) else { throw NPCChatDataFailure.malformed }
        if status.code == 401 || status.code == 403 { throw denied(status.code == 401) }
        guard status.code == 200 else { throw NPCChatDataFailure.rejected }
        return try NPCChatData.decode(response.0, expectedAccountID: session.accountID)
    }
}
