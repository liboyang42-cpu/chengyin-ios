import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Deployment approvals are deliberately distinct types. Neither is inferred from owning a paid
/// version, an installed component, body-read approval or the user's ordinary login.
public struct WorkshopPaidProfessionalReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0, WorkshopPaidInstallWire.text(context.role, 64), expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopPaidProfessionalIssue.invalid }
        self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ other: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(context, other) && WorkshopPaidInstallWire.same(context.session.role, other.session.role) && now < expiresAt
    }
}
public struct WorkshopPaidProfessionalWriteApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0, WorkshopPaidInstallWire.text(context.role, 64), expiresAt.timeIntervalSince1970.isFinite else { throw WorkshopPaidProfessionalIssue.invalid }
        self.context = context; self.expiresAt = expiresAt
    }
    public func matches(_ other: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(context, other) && WorkshopPaidInstallWire.same(context.session.role, other.session.role) && now < expiresAt
    }
}
@MainActor public final class WorkshopPaidProfessionalLifetime {
    private let current: () -> Bool
    private var revoked = false
    public init(current: @escaping () -> Bool) { self.current = current }
    public func revoke() { revoked = true }
    public func check() throws { guard !revoked, current() else { throw WorkshopPaidProfessionalIssue.staleAction }; try Task.checkCancellation() }
}
@MainActor public final class WorkshopPaidProfessionalConfirmation {
    public enum Purpose: Equatable { case create, cancel }
    public let command: WorkshopPaidProfessionalCommand
    let purpose: Purpose
    let lifetime: WorkshopPaidProfessionalLifetime
    private var consumed = false
    init(command: WorkshopPaidProfessionalCommand, lifetime: WorkshopPaidProfessionalLifetime, purpose: Purpose) { self.command = command; self.lifetime = lifetime; self.purpose = purpose }
    func consume() throws { try lifetime.check(); guard !consumed else { throw WorkshopPaidProfessionalIssue.staleAction }; consumed = true }
}
/// Mutations never use ordinary HTTPTransport.send, even if a read route is approved.
@MainActor public protocol WorkshopPaidProfessionalMutationTransport: AnyObject {
    func sendWorkshopPaidProfessional(_ request: URLRequest, authorization: WorkshopPaidProfessionalDispatchAuthorization) async throws -> (Data, Int)
}
@MainActor public final class WorkshopPaidProfessionalDispatchAuthorization {
    public let context: RuntimeDependencyContext
    public let approvalRevision: UUID
    private let body: Data
    private let route: WorkshopPaidProfessionalRequest.Route
    private let lifetime: WorkshopPaidProfessionalLifetime
    private let checkCurrent: () throws -> Void
    private var consumed = false
    init(context: RuntimeDependencyContext, revision: UUID, body: Data, route: WorkshopPaidProfessionalRequest.Route, lifetime: WorkshopPaidProfessionalLifetime, checkCurrent: @escaping () throws -> Void) {
        self.context = context; approvalRevision = revision; self.body = body; self.route = route; self.lifetime = lifetime; self.checkCurrent = checkCurrent
    }
    public func validate() throws { try lifetime.check(); try checkCurrent() }
    public func consume(_ request: URLRequest, context: RuntimeDependencyContext, revision: UUID) throws {
        try validate()
        guard !consumed, ContentDraftContextFence.matches(self.context, context), WorkshopPaidInstallWire.same(self.context.session.role, context.session.role), revision == approvalRevision,
              (route == .submit || route == .cancel), WorkshopPaidProfessionalRequest.accepts(request, baseURL: context.baseURL) == route, request.httpBody == body,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(context.session.token.utf8) == true else { throw WorkshopPaidProfessionalIssue.staleAction }
        consumed = true
    }
}
@MainActor public protocol WorkshopPaidProfessionalServing {
    func requireWrite(lifetime: WorkshopPaidProfessionalLifetime) throws
    func targets(licenseId: String, before: Int64?, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidProfessionalTargets
    func target(licenseId: String, topicId: Int64, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidProfessionalTarget
    func history(command: WorkshopPaidProfessionalCommand, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidProfessionalOperation
    func submit(_ confirmation: WorkshopPaidProfessionalConfirmation) async throws -> WorkshopPaidProfessionalOperation
    func cancel(_ confirmation: WorkshopPaidProfessionalConfirmation) async throws -> WorkshopPaidProfessionalOperation
    func operations(licenseId: String, before: String?, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidProfessionalOperationHistory
}
@MainActor public final class WorkshopPaidProfessionalService: WorkshopPaidProfessionalServing {
    private let api: APIConfiguration, lease: ContentDraftSessionLease
    private let transport: any HTTPTransport
    private let readApproval: WorkshopPaidProfessionalReadApproval?
    private let writeApproval: WorkshopPaidProfessionalWriteApproval?
    private let currentReadApproval: () -> WorkshopPaidProfessionalReadApproval?
    private let currentWriteApproval: () -> WorkshopPaidProfessionalWriteApproval?
    private let now: () -> Date
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(api: APIConfiguration, transport: any HTTPTransport, lease: ContentDraftSessionLease,
                readApproval: WorkshopPaidProfessionalReadApproval? = nil, currentReadApproval: @escaping () -> WorkshopPaidProfessionalReadApproval? = { nil },
                writeApproval: WorkshopPaidProfessionalWriteApproval? = nil, currentWriteApproval: @escaping () -> WorkshopPaidProfessionalWriteApproval? = { nil },
                now: @escaping () -> Date = Date.init, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.api = api; self.transport = transport; self.lease = lease
        self.readApproval = readApproval; self.currentReadApproval = currentReadApproval
        self.writeApproval = writeApproval; self.currentWriteApproval = currentWriteApproval
        self.now = now; self.onUnauthorized = onUnauthorized
    }
    private func check(_ lifetime: WorkshopPaidProfessionalLifetime, write: Bool) throws {
        try lifetime.check(); guard lease.isCurrent else { throw WorkshopPaidProfessionalIssue.staleSession }
        guard WorkshopPaidInstallWire.same(api.baseURL.absoluteString, lease.context.baseURL.absoluteString) else { throw WorkshopPaidProfessionalIssue.disabled }
        if write {
            guard let initial = writeApproval, let current = currentWriteApproval(), initial.revision == current.revision,
                  initial.matches(lease.context, now: now()), current.matches(lease.context, now: now()) else { throw WorkshopPaidProfessionalIssue.disabled }
        } else {
            guard let initial = readApproval, let current = currentReadApproval(), initial.revision == current.revision,
                  initial.matches(lease.context, now: now()), current.matches(lease.context, now: now()) else { throw WorkshopPaidProfessionalIssue.disabled }
        }
        guard lease.isCurrent else { throw WorkshopPaidProfessionalIssue.staleSession }; try lifetime.check()
    }
    public func requireWrite(lifetime: WorkshopPaidProfessionalLifetime) throws {
        try check(lifetime, write: true)
        guard transport is any WorkshopPaidProfessionalMutationTransport else { throw WorkshopPaidProfessionalIssue.disabled }
    }
    public func targets(licenseId: String, before: Int64?, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidProfessionalTargets {
        guard WorkshopPurchasedWire.license(licenseId), before == nil || before! > 0 else { throw WorkshopPaidProfessionalIssue.invalid }
        let value: WorkshopPaidProfessionalTargets = try await call(.targets, body: WorkshopPaidProfessionalRequest.encoded(ListBody(licenseId: licenseId, beforeTopicId: before)), lifetime: lifetime)
        guard value.licenseId == licenseId, before == nil || value.items.allSatisfy({ $0.topicId < before! }) else { throw WorkshopPaidProfessionalIssue.malformed }; return value
    }
    public func target(licenseId: String, topicId: Int64, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidProfessionalTarget {
        guard WorkshopPurchasedWire.license(licenseId), topicId > 0 else { throw WorkshopPaidProfessionalIssue.invalid }
        let value: WorkshopPaidProfessionalTarget = try await call(.target, body: WorkshopPaidProfessionalRequest.encoded(TargetBody(licenseId: licenseId, topicId: topicId)), lifetime: lifetime)
        guard value.topicId == topicId else { throw WorkshopPaidProfessionalIssue.malformed }; return value
    }
    public func history(command: WorkshopPaidProfessionalCommand, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidProfessionalOperation {
        let value: WorkshopPaidProfessionalOperation = try await call(.status, body: WorkshopPaidProfessionalRequest.encoded(StatusBody(requestId: command.requestId)), lifetime: lifetime)
        guard value.matches(command) else { throw WorkshopPaidProfessionalIssue.malformed }; return value
    }
    public func operations(licenseId: String, before: String?, lifetime: WorkshopPaidProfessionalLifetime) async throws -> WorkshopPaidProfessionalOperationHistory {
        guard WorkshopPurchasedWire.license(licenseId), before == nil || WorkshopPurchasedWire.hash(before!) else { throw WorkshopPaidProfessionalIssue.invalid }
        let page: WorkshopPaidProfessionalOperationHistory = try await call(.operations, body: WorkshopPaidProfessionalRequest.encoded(OperationListBody(licenseId: licenseId, beforeOperationKey: before)), lifetime: lifetime)
        guard page.licenseId == licenseId, before == nil || page.items.allSatisfy({ $0.operationKey < before! }),
              before == nil || page.nextBeforeOperationKey == nil || page.nextBeforeOperationKey! < before! else { throw WorkshopPaidProfessionalIssue.malformed }
        return page
    }
    public func submit(_ confirmation: WorkshopPaidProfessionalConfirmation) async throws -> WorkshopPaidProfessionalOperation {
        guard confirmation.purpose == .create else { throw WorkshopPaidProfessionalIssue.invalid }
        return try await mutate(confirmation, route: .submit)
    }
    public func cancel(_ confirmation: WorkshopPaidProfessionalConfirmation) async throws -> WorkshopPaidProfessionalOperation {
        guard confirmation.purpose == .cancel else { throw WorkshopPaidProfessionalIssue.invalid }
        return try await mutate(confirmation, route: .cancel)
    }
    private func mutate(_ confirmation: WorkshopPaidProfessionalConfirmation, route: WorkshopPaidProfessionalRequest.Route) async throws -> WorkshopPaidProfessionalOperation {
        let lifetime = confirmation.lifetime, command = confirmation.command
        try check(lifetime, write: true)
        guard transport is any WorkshopPaidProfessionalMutationTransport else { throw WorkshopPaidProfessionalIssue.disabled }
        try confirmation.consume()
        do {
            let operation: WorkshopPaidProfessionalOperation = try await call(route, body: command.wireData(), lifetime: lifetime)
            guard operation.matches(command), operation.state.terminal else { throw WorkshopPaidProfessionalIssue.malformed }
            return operation
        } catch {
            try check(lifetime, write: true)
            if let issue = error as? WorkshopPaidProfessionalIssue, issue == .unauthorized { throw issue }
            throw WorkshopPaidProfessionalIssue.outcomeUnknown
        }
    }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let data: T? }
    private struct Code: Decodable { let code: Int }
    private func call<T: Decodable>(_ route: WorkshopPaidProfessionalRequest.Route, body: Data, lifetime: WorkshopPaidProfessionalLifetime) async throws -> T {
        let write = route == .submit || route == .cancel
        try check(lifetime, write: write)
        var request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent(route.path), fields: [:], token: lease.context.session.token, includesBody: false)
        request.httpBody = body; request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type"); request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        guard WorkshopPaidProfessionalRequest.accepts(request, baseURL: api.baseURL) == route else { throw WorkshopPaidProfessionalIssue.invalid }
        do {
            let data: Data, status: Int
            try check(lifetime, write: write)
            if route == .submit || route == .cancel {
                guard let mutation = transport as? any WorkshopPaidProfessionalMutationTransport, let writeApproval else { throw WorkshopPaidProfessionalIssue.disabled }
                let authorization = WorkshopPaidProfessionalDispatchAuthorization(context: lease.context, revision: writeApproval.revision, body: body, route: route, lifetime: lifetime) { [weak self] in
                    guard let self else { throw WorkshopPaidProfessionalIssue.staleSession }; try self.check(lifetime, write: true)
                }
                (data, status) = try await mutation.sendWorkshopPaidProfessional(request, authorization: authorization)
            } else { (data, status) = try await transport.send(request) }
            try check(lifetime, write: write)
            if status == 401 { try check(lifetime, write: write); onUnauthorized(lease.context); throw WorkshopPaidProfessionalIssue.unauthorized }
            let code = (200..<300).contains(status) ? try decode(Code.self, data).code : status
            if code == 401 { try check(lifetime, write: write); onUnauthorized(lease.context); throw WorkshopPaidProfessionalIssue.unauthorized }
            guard (200..<300).contains(status), code == 200, let value = try decode(Envelope<T>.self, data).data else { throw WorkshopPaidProfessionalIssue.unavailable }
            try check(lifetime, write: write); return value
        } catch { try check(lifetime, write: write); throw (error as? WorkshopPaidProfessionalIssue) ?? .unavailable }
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try WorkshopPaidInstallWire.decode(type, data: data, maximum: 524_288) }
        catch { throw WorkshopPaidProfessionalIssue.malformed }
    }
}
private struct ListBody: Codable { let licenseId: String; let beforeTopicId: Int64? }
private struct TargetBody: Codable { let licenseId: String; let topicId: Int64 }
private struct OperationListBody: Codable { let licenseId: String; let beforeOperationKey: String? }
private struct StatusBody: Codable { let requestId: String }
public enum WorkshopPaidProfessionalRequest {
    public enum Route: CaseIterable, Equatable {
        case targets, target, submit, status, cancel, operations
        public var path: String {
            switch self {
            case .targets: return "api/workshop/purchased/professional-targets/list"
            case .target: return "api/workshop/purchased/professional-targets/detail"
            case .submit: return "api/workshop/purchased/professional-operations/submit"
            case .status: return "api/workshop/purchased/professional-operations/status"
            case .cancel: return "api/workshop/purchased/professional-operations/cancel"
            case .operations: return "api/workshop/purchased/professional-operations/history"
            }
        }
    }
    fileprivate static func encoded<T: Encodable>(_ value: T) throws -> Data { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return try e.encode(value) }
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Route? {
        guard let url = request.url, let route = Route.allCases.first(where: { url.absoluteString == baseURL.appendingPathComponent($0.path).absoluteString }),
              url.query == nil, url.fragment == nil, request.httpMethod == "POST", request.httpBodyStream == nil, request.value(forHTTPHeaderField: "Transfer-Encoding") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json; charset=utf-8", let data = request.httpBody, (2...((route == .submit || route == .cancel) ? 4_096 : 512)).contains(data.count),
              request.value(forHTTPHeaderField: "Content-Length") == String(data.count), request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store", request.value(forHTTPHeaderField: "Pragma") == "no-cache" else { return nil }
        switch route {
        case .targets:
            guard let value = try? WorkshopPaidInstallWire.decode(ListBody.self, data: data, maximum: 512), WorkshopPurchasedWire.license(value.licenseId),
                  value.beforeTopicId == nil || value.beforeTopicId! > 0, (try? encoded(value)) == data else { return nil }
        case .target:
            guard let value = try? WorkshopPaidInstallWire.decode(TargetBody.self, data: data, maximum: 512), WorkshopPurchasedWire.license(value.licenseId), value.topicId > 0, (try? encoded(value)) == data else { return nil }
        case .status:
            guard let value = try? WorkshopPaidInstallWire.decode(StatusBody.self, data: data, maximum: 512), WorkshopPaidInstallWire.requestID(value.requestId), (try? encoded(value)) == data else { return nil }
        case .operations:
            guard let value = try? WorkshopPaidInstallWire.decode(OperationListBody.self, data: data, maximum: 512), WorkshopPurchasedWire.license(value.licenseId),
                  value.beforeOperationKey == nil || WorkshopPurchasedWire.hash(value.beforeOperationKey!), (try? encoded(value)) == data else { return nil }
        case .submit, .cancel:
            guard let value = try? WorkshopPaidInstallWire.decode(WorkshopPaidProfessionalCommand.self, data: data, maximum: 4_096), (try? value.wireData()) == data else { return nil }
        }
        return route
    }
}
