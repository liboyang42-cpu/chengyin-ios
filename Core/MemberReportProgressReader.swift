import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Externally supplied read lease. No issuer, writer, appeal or original-request capability is provided here.
@MainActor @Observable public final class MemberReportProgressApproval {
    public let context: RuntimeDependencyContext
    public let revision = UUID()
    public let expiresAt: Date
    public let capabilities: Set<MemberReportProgressCapability>
    public private(set) var revoked = false
    public private(set) var accessDenied = false
    public init(context: RuntimeDependencyContext, expiresAt: Date,
                capabilities: Set<MemberReportProgressCapability> = [.history, .detail, .taxonomy]) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0,
              context.role.utf8.elementsEqual(context.session.role.utf8), AuthRequestBuilder.isValidToken(context.session.token),
              expiresAt.timeIntervalSince1970.isFinite, expiresAt > Date(), !capabilities.isEmpty else { throw MemberReportProgressFailure.disabled }
        self.context = context; self.expiresAt = expiresAt; self.capabilities = capabilities
    }
    public func revoke() { revoked = true }
    func deny() { accessDenied = true; revoked = true }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && MemberReportProgressScope.matches(context, self.context)
    }
}
@MainActor public final class MemberReportProgressReader {
    public static let maximumBytes = 8_388_608
    public static let maximumRecords = 10_000
    public let approval: MemberReportProgressApproval
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> MemberReportProgressApproval?
    private var retired = false
    private final class WeakOwner {
        weak var value: MemberReportProgressCoordinator?
        init(_ value: MemberReportProgressCoordinator) { self.value = value }
    }
    private var owners: [WeakOwner] = []
    public init(approval: MemberReportProgressApproval, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> MemberReportProgressApproval?) {
        self.approval = approval; self.transport = transport; self.current = current; self.selected = selected
    }
    public var isCurrent: Bool {
        guard !retired, let context = current(), approval.matches(context), let selected = selected(context) else { return false }
        return selected === approval && selected.matches(context)
    }
    public func allows(_ capability: MemberReportProgressCapability) -> Bool { isCurrent && approval.capabilities.contains(capability) }
    public func makeCoordinator() -> MemberReportProgressCoordinator {
        let value = MemberReportProgressCoordinator(reader: self)
        owners.removeAll { $0.value == nil }; owners.append(.init(value)); return value
    }
    public func retire() { retired = true; owners.forEach { $0.value?.retire() }; owners.removeAll() }
    private struct Status: Decodable { let code: Int }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private func denied() -> MemberReportProgressFailure {
        // One permission denial invalidates every client retaining this lease, including pushed detail screens.
        approval.deny(); owners.forEach { $0.value?.retire() }; owners.removeAll(); return .denied
    }
    private func read<T: Decodable>(_ route: MemberReportProgressRoute) async throws -> T {
        try Task.checkCancellation()
        guard route.isValid, allows(route.capability) else { throw MemberReportProgressFailure.disabled }
        var request = URLRequest(url: approval.context.baseURL.appendingPathComponent(route.path))
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard MemberReportProgressRoute(request: request, baseURL: approval.context.baseURL) == route else { throw MemberReportProgressFailure.malformed }
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch {
            try Task.checkCancellation()
            guard isCurrent else { throw MemberReportProgressFailure.stale }
            if let api = error as? APIError,
               [APIError.unauthorized, .httpStatus(401), .httpStatus(403), .businessCode(401), .businessCode(403)].contains(api) { throw denied() }
            if error as? MemberReportProgressFailure == .denied { throw denied() }
            throw error
        }
        try Task.checkCancellation()
        guard isCurrent else { throw MemberReportProgressFailure.stale }
        if response.1 == 401 || response.1 == 403 { throw denied() }
        guard (200..<300).contains(response.1) else { throw MemberReportProgressFailure.unavailable }
        guard response.0.count <= Self.maximumBytes else { throw MemberReportProgressFailure.oversized }
        guard let text = String(data: response.0, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil,
              let status = try? JSONDecoder().decode(Status.self, from: response.0) else { throw MemberReportProgressFailure.malformed }
        if status.code == 401 || status.code == 403 { throw denied() }
        guard status.code == 200 else { throw MemberReportProgressFailure.unavailable }
        guard let value = try? JSONDecoder().decode(Envelope<T>.self, from: response.0).data else { throw MemberReportProgressFailure.malformed }
        return value
    }
    public func history() async throws -> [MemberReportProgressRecord] {
        let result: [MemberReportProgressRecord] = try await read(.history)
        guard result.count <= Self.maximumRecords else { throw MemberReportProgressFailure.oversized }
        guard Set(result.map(\.id)).count == result.count else { throw MemberReportProgressFailure.malformed }
        try result.forEach { try $0.validate() }; return result
    }
    public func detail(for original: MemberReportProgressRecord) async throws -> MemberReportProgressRecord {
        try original.validate()
        let value: MemberReportProgressRecord = try await read(.detail(original.id))
        try value.validateDetail(for: original); return value
    }
    public func taxonomy() async throws -> MemberReportProgressTaxonomy {
        let value: MemberReportProgressTaxonomy = try await read(.taxonomy); try value.validate(); return value
    }
}
