import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// r463 source-only successor read lease. No issuer, writer, attachment or request-recovery authority.
@MainActor @Observable public final class SupportTicketReadApproval {
    public let context: RuntimeDependencyContext
    public let revision = UUID()
    public let expiresAt: Date
    public let capabilities: Set<SupportTicketReadCapability>
    public private(set) var revoked = false
    public private(set) var accessDenied = false
    public init(context: RuntimeDependencyContext, expiresAt: Date,
                capabilities: Set<SupportTicketReadCapability> = [.history, .detail, .timeline]) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0,
              context.role.utf8.elementsEqual(context.session.role.utf8), AuthRequestBuilder.isValidToken(context.session.token),
              expiresAt.timeIntervalSince1970.isFinite, expiresAt > Date(), !capabilities.isEmpty else { throw SupportTicketReadFailure.disabled }
        self.context = context; self.expiresAt = expiresAt; self.capabilities = capabilities
    }
    public func revoke() { revoked = true }
    func deny() { accessDenied = true; revoked = true }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && SupportTicketReadScope.matches(context, self.context)
    }
}
@MainActor public final class SupportTicketReadReader {
    public static let maximumBytes = 8_388_608
    public let approval: SupportTicketReadApproval
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> SupportTicketReadApproval?
    private var retired = false
    private final class WeakOwner {
        weak var value: SupportTicketReadCoordinator?
        init(_ value: SupportTicketReadCoordinator) { self.value = value }
    }
    private var owners: [WeakOwner] = []
    public init(approval: SupportTicketReadApproval, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> SupportTicketReadApproval?) {
        self.approval = approval; self.transport = transport; self.current = current; self.selected = selected
    }
    public var isCurrent: Bool {
        guard !retired, let context = current(), approval.matches(context), let selected = selected(context) else { return false }
        return selected === approval && selected.matches(context)
    }
    public func allows(_ capability: SupportTicketReadCapability) -> Bool { isCurrent && approval.capabilities.contains(capability) }
    public func makeCoordinator() -> SupportTicketReadCoordinator {
        let value = SupportTicketReadCoordinator(reader: self)
        owners.removeAll { $0.value == nil }; owners.append(.init(value)); return value
    }
    public func retire() { retired = true; owners.forEach { $0.value?.retire() }; owners.removeAll() }
    private struct Status: Decodable { let code: Int }
    private struct CapabilityDenial: Decodable { let msg: String }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private func denied() -> SupportTicketReadFailure {
        // One permission denial invalidates every client retaining this lease, including pushed detail screens.
        approval.deny(); owners.forEach { $0.value?.retire() }; owners.removeAll(); return .denied
    }
    private func read<T: Decodable>(_ route: SupportTicketReadRoute) async throws -> T {
        try Task.checkCancellation()
        guard route.isValid, allows(route.capability) else { throw SupportTicketReadFailure.disabled }
        var request = URLRequest(url: approval.context.baseURL.appendingPathComponent(route.path))
        request.httpMethod = "POST"; request.httpBody = try route.body(); request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard SupportTicketReadRoute(request: request, baseURL: approval.context.baseURL) == route else { throw SupportTicketReadFailure.malformed }
        let response: (Data, Int)
        do { response = try await transport.send(request) }
        catch {
            try Task.checkCancellation()
            guard isCurrent else { throw SupportTicketReadFailure.stale }
            if let api = error as? APIError,
               [APIError.unauthorized, .httpStatus(401), .httpStatus(403), .businessCode(401), .businessCode(403)].contains(api) { throw denied() }
            if error as? SupportTicketReadFailure == .denied { throw denied() }
            throw error
        }
        try Task.checkCancellation()
        guard isCurrent else { throw SupportTicketReadFailure.stale }
        if response.1 == 401 || response.1 == 403 { throw denied() }
        guard (200..<300).contains(response.1) else { throw SupportTicketReadFailure.unavailable }
        guard response.0.count <= Self.maximumBytes else { throw SupportTicketReadFailure.oversized }
        guard let text = String(data: response.0, encoding: .utf8), (try? ContentDraftJSON.parse(text)) != nil,
              let status = try? JSONDecoder().decode(Status.self, from: response.0) else { throw SupportTicketReadFailure.malformed }
        if status.code == 401 || status.code == 403 { throw denied() }
        // r463 CsTicketCapability throws this exact 409 reason when its read gate is withdrawn.
        if status.code == 409, (try? JSONDecoder().decode(CapabilityDenial.self, from: response.0).msg) == "CS_CAPABILITY_NOT_ENABLED" { throw denied() }
        guard status.code == 200 else { throw SupportTicketReadFailure.unavailable }
        guard let value = try? JSONDecoder().decode(Envelope<T>.self, from: response.0).data else { throw SupportTicketReadFailure.malformed }
        return value
    }
    public func history(before: Int64 = 0) async throws -> SupportTicketReadPage {
        let page: SupportTicketReadPage = try await read(.history(before: before))
        guard page.list.count <= 30, Set(page.list.map(\.id)).count == page.list.count,
              page.list.isEmpty ? (page.next_cursor == 0 && !page.has_more) : (page.next_cursor > 0 && (before == 0 || page.next_cursor < before)),
              !page.has_more || page.list.count == 30 else { throw SupportTicketReadFailure.malformed }
        try page.list.forEach { try $0.validate(owner: approval.context.session.accountID) }; return page
    }
    public func detail(number: String, after: Int64 = 0) async throws -> SupportTicketReadDetail {
        let page: SupportTicketReadDetail = try await read(.detail(number: number, after: after))
        try validate(page, number: number, after: after); return page
    }
    private func validate(_ page: SupportTicketReadDetail, number: String, after: Int64) throws {
        try page.ticket.validate(owner: approval.context.session.accountID)
        guard page.ticket.ticket_no == number, page.business_result == "NO_FINANCIAL_ACTION", page.messages.count <= 50,
              page.next_cursor == (page.messages.last?.id ?? after), !page.has_more || page.messages.count == 50 else { throw SupportTicketReadFailure.malformed }
        var previous = after
        for message in page.messages { guard message.id > previous else { throw SupportTicketReadFailure.malformed }; previous = message.id }
    }
    public func timeline(number: String, before: Int64 = 0) async throws -> SupportTicketReadTimeline {
        let result: SupportTicketReadDetail = try await read(.timeline(number: number, before: before))
        try validate(result, number: number, after: 0)
        guard let page = result.timeline, page.ticket_no == number, page.resource_type == "CS_TICKET",
              page.audience == "MEMBER", page.source == "cs_ticket_event", page.events.count <= 50,
              page.next_before == (page.events.last?.id ?? before), !page.has_more || page.events.count == 50 else { throw SupportTicketReadFailure.malformed }
        var previous: Int64? = before > 0 ? before : nil
        for event in page.events { guard previous.map({ event.id < $0 }) ?? true else { throw SupportTicketReadFailure.malformed }; previous = event.id }
        return page
    }
}
