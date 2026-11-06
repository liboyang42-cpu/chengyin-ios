import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supplied, expiring read lease. It cannot authorize a submission, receipt replay or scoring change.
@MainActor @Observable public final class MemberScoreListApproval {
    public let context: RuntimeDependencyContext
    public let revision = UUID()
    public let expiresAt: Date
    public let capabilities: Set<MemberScoreReadCapability>
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, expiresAt: Date,
                capabilities: Set<MemberScoreReadCapability> = [.list, .sessionDetail]) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0,
              context.role.utf8.elementsEqual(context.session.role.utf8), AuthRequestBuilder.isValidToken(context.session.token),
              expiresAt.timeIntervalSince1970.isFinite, expiresAt > Date(), !capabilities.isEmpty else { throw MemberScoreListFailure.disabled }
        self.context = context; self.expiresAt = expiresAt; self.capabilities = capabilities
    }
    public func revoke() { revoked = true }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && MemberScoreReadScope.matches(context, self.context)
    }
}
@MainActor public final class MemberScoreAppealListClient {
    public let approval: MemberScoreListApproval
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> MemberScoreListApproval?
    private var retired = false
    private final class WeakOwner {
        weak var value: MemberScoreAppealReadCoordinator?
        init(_ value: MemberScoreAppealReadCoordinator) { self.value = value }
    }
    private var owners: [WeakOwner] = []
    public init(approval: MemberScoreListApproval, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> MemberScoreListApproval?) {
        self.approval = approval; self.transport = transport; self.current = current; self.selected = selected
    }
    public var isCurrent: Bool {
        guard !retired, let context = current(), approval.matches(context),
              let selected = selected(context) else { return false }
        return selected === approval && selected.matches(context)
    }
    public func allows(_ capability: MemberScoreReadCapability) -> Bool { isCurrent && approval.capabilities.contains(capability) }
    public func makeCoordinator() -> MemberScoreAppealReadCoordinator {
        let owner = MemberScoreAppealReadCoordinator(client: self)
        owners.removeAll { $0.value == nil }; owners.append(.init(owner)); return owner
    }
    public func retire() { retired = true; owners.forEach { $0.value?.retire() }; owners.removeAll() }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private func read<T: Decodable>(_ route: MemberScoreReadRoute) async throws -> T {
        try Task.checkCancellation()
        guard route.isValid, allows(route.capability) else { throw MemberScoreListFailure.disabled }
        guard var parts = URLComponents(url: approval.context.baseURL.appendingPathComponent(route.path), resolvingAgainstBaseURL: false) else { throw MemberScoreListFailure.malformed }
        parts.queryItems = route.query.isEmpty ? nil : route.query
        guard let url = parts.url else { throw MemberScoreListFailure.malformed }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard MemberScoreReadRoute(request: request, baseURL: approval.context.baseURL) == route else { throw MemberScoreListFailure.malformed }
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch { guard isCurrent else { throw MemberScoreListFailure.stale }; throw error }
        try Task.checkCancellation()
        guard isCurrent else { throw MemberScoreListFailure.stale }
        if response.1 == 401 || response.1 == 403 { throw MemberScoreListFailure.denied }
        guard (200..<300).contains(response.1) else { throw MemberScoreListFailure.unavailable }
        guard response.0.count <= 8_388_608, let text = String(data: response.0, encoding: .utf8),
              (try? ContentDraftJSON.parse(text)) != nil else { throw MemberScoreListFailure.malformed }
        let result = try JSONDecoder().decode(Envelope<T>.self, from: response.0)
        if result.code == 401 || result.code == 403 { throw MemberScoreListFailure.denied }
        guard result.code == 200, let value = result.data else { throw MemberScoreListFailure.unavailable }
        return value
    }
    public func list(page: Int = 1, filter: MemberScoreAppealFilter = .all) async throws -> MemberScoreAppealPage {
        let result: MemberScoreAppealPage = try await read(.list(page: page, filter: filter))
        try result.validate()
        guard filter == .all || result.rows.allSatisfy({ filter == .active ? $0.status == .open : $0.status != .open }) else { throw MemberScoreListFailure.malformed }
        return result
    }
    public func detail(_ row: MemberScoreAppealRow) async throws -> MemberScoreAppealDetail {
        guard row.canReadSession, let id = row.sessionID else { throw MemberScoreListFailure.unavailable }
        let value: MemberScoreSessionWire = try await read(.detail(sessionID: id))
        return try value.detail(for: row, account: approval.context.session.accountID)
    }
    public func reputation() async throws -> MemberScoreReputation {
        struct Value: Decodable { let status: MemberScoreReputation }
        let value: Value = try await read(.reputation); return value.status
    }
}
