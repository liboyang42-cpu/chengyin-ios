import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Separate source reader; an absent dedicated grant is not publishing authority.
@MainActor public final class ProjectAuthorInputReader: NativeRuntimeStructureAuthorReading {
    private let context: RuntimeDependencyContext
    private let session: ProjectEditSession
    private let routes: Set<BusinessRuntimeRoute>
    private let transport: any HTTPTransport
    private let current: () -> Bool
    private var retired = false
    private var generation = UUID()
    private var receipt: NativeRuntimeStructureAuthorInputs?
    public init(context: RuntimeDependencyContext, session: ProjectEditSession,
                routes: Set<BusinessRuntimeRoute>, transport: any HTTPTransport,
                current: @escaping () -> Bool = { false }) throws {
        let allowed: Set<BusinessRuntimeRoute> = [try ProjectAuthorInputReadRoute.support.businessRoute,
            try ProjectAuthorInputReadRoute.template(1).businessRoute]
        guard context.market == .china, context.session.accountID == session.accountID,
              context.session.epoch == session.epoch, context.session.namespace == session.storageNamespace,
              !routes.isEmpty, routes.isSubset(of: allowed) else { throw ProjectEditError.notConfigured }
        self.context = context; self.session = session; self.routes = routes; self.transport = transport; self.current = current
    }
    private var isCurrent: Bool {
        guard !retired, current() else { retired = true; receipt = nil; return false }; return true
    }
    public func runtimeStructureInputsAreCurrent(_ inputs: NativeRuntimeStructureAuthorInputs, session: ProjectEditSession) -> Bool {
        isCurrent && self.session == session && receipt == inputs
    }
    public func runtimeStructureInputs(draft: ProjectEditDraft, session: ProjectEditSession) async throws -> NativeRuntimeStructureAuthorInputs {
        guard isCurrent, self.session == session, draft.owner == .personal else { throw ProjectEditError.notConfigured }
        let ids = Set(draft.chapters.flatMap(\.nodes).compactMap(\.templateID).filter { $0 > 0 })
        let supportRoute = try ProjectAuthorInputReadRoute.support.businessRoute
        let templateRoute = try ProjectAuthorInputReadRoute.template(1).businessRoute
        guard routes.contains(supportRoute), ids.isEmpty || routes.contains(templateRoute) else { throw ProjectEditError.notConfigured }
        generation = UUID(); let stamp = generation; receipt = nil
        func read(_ request: URLRequest) async throws -> [String: ProjectEditJSON] {
            try Task.checkCancellation()
            guard self.isCurrent, self.generation == stamp,
                  let route = ProjectAuthorInputReadRoute(request: request, baseURL: context.baseURL),
                  routes.contains(try route.businessRoute), request.value(forHTTPHeaderField: "Authorization") == context.session.token else { throw ProjectEditError.changedSession }
            // Final local check immediately precedes the independently scoped factory transport.
            let (data, status) = try await transport.send(request)
            guard self.isCurrent, self.generation == stamp else { throw ProjectEditError.changedSession }
            try Task.checkCancellation()
            guard data.count <= 1_048_576 else { throw ProjectEditError.invalidContract }
            if status == 401 || status == 403 {
                self.retired = true; self.receipt = nil; throw APIError.unauthorized
            }
            let envelope = try ApprovedTopicReleaseWire.envelope(data)
            if envelope["code"]?.integer == 401 || envelope["code"]?.integer == 403 {
                self.retired = true; self.receipt = nil; throw APIError.unauthorized
            }
            guard (200..<300).contains(status), envelope["code"]?.integer == 200,
                  let value = envelope["data"]?.object else { throw ProjectEditError.invalidContract }
            return value
        }
        var request = URLRequest(url: context.baseURL.appendingPathComponent(NativeRuntimeStructureAuthorInputs.supportPath))
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.timeoutInterval = 30
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let matrix = try await read(request)
        var templates: [Int: [String: ProjectEditJSON]] = [:]
        for id in ids.sorted() {
            var request = try AuthRequestBuilder.makeFormRequest(url: context.baseURL.appendingPathComponent(NativeRuntimeStructureAuthorInputs.templatePath),
                fields: ["id": String(id), "scope": ProjectEditOwner.personal.rawValue], token: context.session.token)
            request.httpShouldHandleCookies = false
            let value = try await read(request)
            guard value["id"]?.integer == id, value["memberId"]?.integer == session.accountID,
                  value["canEdit"] == .bool(true), value["delFlag"] == nil || value["delFlag"] == .number(0),
                  value["advancedConfigJson"] == nil || value["advancedConfigJson"] == .null || value["advancedConfigJson"]?.text != nil else { throw ProjectEditError.invalidContract }
            templates[id] = value.filter { ["id", "validationMethod", "advancedConfigJson", "updateTime", "createTime"].contains($0.key) }
        }
        let inputs = try NativeRuntimeStructureAuthorInputs(matrix: matrix, templates: templates)
        guard isCurrent, generation == stamp else { throw ProjectEditError.changedSession }
        receipt = inputs; return inputs
    }
}

/// Decorates, never replaces, the original draft writer and durable recovery owner.
@MainActor public final class ProjectAuthorInputService: ProjectEditServing, NativeRuntimeStructureAuthorReading {
    private let original: any ProjectEditServing
    private let reader: ProjectAuthorInputReader?
    public init(original: any ProjectEditServing, reader: ProjectAuthorInputReader?) { self.original = original; self.reader = reader }
    public var authority: ProjectEditServiceAuthority { original.authority }
    public var supportsRequestReadback: Bool { original.supportsRequestReadback }
    public var supportsRequestRetry: Bool { original.supportsRequestRetry }
    public var supportsPostProcessingResume: Bool { original.supportsPostProcessingResume }
    public func terminalReceipt(operation: ProjectEditPending, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? { try await original.terminalReceipt(operation: operation, session: session) }
    public func retrySameRequest(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome { await original.retrySameRequest(operation, session: session) }
    public func resumePostProcessing(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome { await original.resumePostProcessing(operation, session: session) }
    public func preflight(topicID: Int?, session: ProjectEditSession) async throws -> ProjectEditPreflight { try await original.preflight(topicID: topicID, session: session) }
    public func submit(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome { await original.submit(operation, session: session) }
    public func terminalReceipt(operationID: UUID, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? { try await original.terminalReceipt(operationID: operationID, session: session) }
    public func runtimeStructureInputs(draft: ProjectEditDraft, session: ProjectEditSession) async throws -> NativeRuntimeStructureAuthorInputs {
        guard let reader else { throw ProjectEditError.notConfigured }; return try await reader.runtimeStructureInputs(draft: draft, session: session)
    }
    public func runtimeStructureInputsAreCurrent(_ inputs: NativeRuntimeStructureAuthorInputs, session: ProjectEditSession) -> Bool { reader?.runtimeStructureInputsAreCurrent(inputs, session: session) == true }
}
