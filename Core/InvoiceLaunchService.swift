import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Narrow real-HTTP adapter. The host explicitly supplies its reviewed transport;
/// this type neither selects a deployment nor opens a backend feature switch.
@MainActor public final class InvoiceLaunchService {
    public let session: InvoiceLaunchSession
    private let transport: any HTTPTransport
    private let current: () -> InvoiceLaunchSession?
    private let enabled: () -> Bool
    private let mutationsEnabled: () -> Bool
    private let originalReceiptsEnabled: () -> Bool
    var usesOriginalReceipts: Bool { originalReceiptsEnabled() }
    private let commandReceiptsEnabled: () -> Bool
    var usesCommandReceipts: Bool { commandReceiptsEnabled() }
    private let unauthorized: () -> Void
    private var revoked = false
    public init(session: InvoiceLaunchSession, transport: any HTTPTransport,
                enabled: @escaping () -> Bool = { false },
                mutationsEnabled: @escaping () -> Bool = { false },
                originalReceiptsEnabled: @escaping () -> Bool = { false },
                commandReceiptsEnabled: @escaping () -> Bool = { false },
                current: @escaping () -> InvoiceLaunchSession?, unauthorized: @escaping () -> Void = {}) {
        self.session = session; self.transport = transport; self.enabled = enabled
        self.mutationsEnabled = mutationsEnabled; self.originalReceiptsEnabled = originalReceiptsEnabled; self.commandReceiptsEnabled = commandReceiptsEnabled; self.current = current; self.unauthorized = unauthorized
    }
    public func revoke() { revoked = true }
    func check(mutation: Bool = false) throws {
        try Task.checkCancellation()
        if current() != session { revoked = true }
        guard !revoked else { throw InvoiceLaunchIssue.staleSession }
        guard enabled(), !mutation || mutationsEnabled() else { throw InvoiceLaunchIssue.disabled }
        guard current() == session, !revoked else { revoked = true; throw InvoiceLaunchIssue.staleSession }
    }
    public func titles() async throws -> [InvoiceLaunchTitle] {
        let result: [InvoiceLaunchTitle] = try await read(.titles)
        try result.forEach { try $0.validate() }
        guard Set(result.map(\.id)).count == result.count else { throw InvoiceLaunchIssue.malformed }; return result
    }
    public func eligibleOrders() async throws -> [InvoiceLaunchOrder] {
        let result: [InvoiceLaunchOrder] = try await read(.eligibleOrders)
        try result.forEach { try $0.validate() }
        guard Set(result.map(\.orderId)).count == result.count else { throw InvoiceLaunchIssue.malformed }; return result
    }
    public func applications() async throws -> [InvoiceLaunchApplication] {
        let result: [InvoiceLaunchApplication] = try await read(.list)
        try result.forEach { try $0.validate(summary: true) }
        guard Set(result.map(\.id)).count == result.count else { throw InvoiceLaunchIssue.malformed }; return result
    }
    public func detail(id: Int64) async throws -> InvoiceLaunchApplication {
        guard id > 0 else { throw InvoiceLaunchIssue.invalid }
        let result: InvoiceLaunchApplication = try await read(.detail, body: InvoiceLaunchWire.encode(IDBody(id: id)))
        try result.validate(); guard result.id == id else { throw InvoiceLaunchIssue.malformed }; return result
    }
    public func originalApplication(requestId: String) async throws -> InvoiceLaunchApplication {
        guard InvoiceLaunchWire.requestID(requestId) else { throw InvoiceLaunchIssue.invalid }
        let result: InvoiceLaunchApplication = try await read(.originalRequest, body: InvoiceLaunchWire.encode(RequestBody(requestId: requestId)))
        try result.validate()
        guard result.requestId == requestId else { throw InvoiceLaunchIssue.malformed }
        return result
    }
    public func titleReceipt(requestId: String, targetID: Int64? = nil) async throws -> InvoiceLaunchTitleReceipt {
        guard InvoiceLaunchWire.requestID(requestId) else { throw InvoiceLaunchIssue.invalid }
        let result: InvoiceLaunchTitleReceipt = try await read(.titleRequest, body: InvoiceLaunchWire.encode(RequestBody(requestId: requestId)))
        try result.validate(request: requestId, target: targetID); return result
    }
    func saveTitleWithRequest(_ draft: InvoiceLaunchTitleDraft, requestId: String) async throws -> InvoiceLaunchTitleReceipt {
        guard InvoiceLaunchWire.requestID(requestId) else { throw InvoiceLaunchIssue.invalid }
        // Flatten the original draft, matching the controller; never persist this PII payload.
        var body = try JSONSerialization.jsonObject(with: InvoiceLaunchWire.encode(draft)) as! [String: Any]
        body["requestId"] = requestId
        do {
            let result: InvoiceLaunchTitleReceipt = try await mutation(.saveTitleRequest, body: JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
            try result.validate(request: requestId, target: draft.id); return result
        } catch { throw mutationIssue(error) }
    }
    private struct RequestBody: Encodable { let requestId: String }
    // Internal mutations force callers through the durable coordinator.
    func apply(_ command: InvoiceLaunchApply) async throws -> InvoiceLaunchApplication {
        try command.validate()
        do {
            let result: InvoiceLaunchApplication = try await mutation(.apply, body: InvoiceLaunchWire.encode(command))
            try result.validate(); guard (!usesOriginalReceipts || result.requestId == command.requestId), result.matches(command) else { throw InvoiceLaunchIssue.malformed }; return result
        } catch { throw mutationIssue(error) }
    }
    func saveTitle(_ draft: InvoiceLaunchTitleDraft) async throws -> InvoiceLaunchTitle {
        do {
            let result: InvoiceLaunchTitle = try await mutation(.saveTitle, body: InvoiceLaunchWire.encode(draft))
            try result.validate()
            guard draft.id == nil || draft.id == result.id else { throw InvoiceLaunchIssue.malformed }; return result
        } catch { throw mutationIssue(error) }
    }
    func deleteTitle(id: Int64) async throws {
        guard id > 0 else { throw InvoiceLaunchIssue.invalid }
        let _: EmptyReceipt = try await mutation(.deleteTitle, body: InvoiceLaunchWire.encode(IDBody(id: id)), permitsEmpty: true)
    }
    func cancel(id: Int64) async throws -> InvoiceLaunchApplication {
        guard id > 0 else { throw InvoiceLaunchIssue.invalid }
        do {
            let result: InvoiceLaunchApplication = try await mutation(.cancel, body: InvoiceLaunchWire.encode(IDBody(id: id)))
            try result.validate()
            guard result.id == id, result.status == .cancelled else { throw InvoiceLaunchIssue.malformed }; return result
        } catch { throw mutationIssue(error) }
    }
    /// Exact original command read. Missing/pending/rejected reads never prove non-submission.
    public func commandReceipt(requestId: String, operation: InvoiceLaunchCommandReceipt.Operation,
                               targetID: Int64) async throws -> InvoiceLaunchCommandReceipt {
        guard InvoiceLaunchWire.requestID(requestId), targetID > 0 else { throw InvoiceLaunchIssue.invalid }
        try check()
        do {
            let result: InvoiceLaunchCommandReceipt = try await executeCommand(.receipt,
                body: InvoiceLaunchWire.encode(RequestBody(requestId: requestId)))
            try result.validate(request: requestId, operation: operation, target: targetID); return result
        } catch { try check(); throw (error as? InvoiceLaunchIssue) ?? .unavailable }
    }
    /// Internal mutation: the durable coordinator owns request creation and persistence.
    func sendCommand(requestId: String, operation: InvoiceLaunchCommandReceipt.Operation,
                     targetID: Int64) async throws -> InvoiceLaunchCommandReceipt {
        guard InvoiceLaunchWire.requestID(requestId), targetID > 0 else { throw InvoiceLaunchIssue.invalid }
        try check(mutation: true)
        do {
            let route: InvoiceLaunchCommandRoute = operation == .deleteTitle ? .deleteTitle : .cancel
            let result: InvoiceLaunchCommandReceipt = try await executeCommand(route,
                body: InvoiceLaunchWire.encode(CommandBody(requestId: requestId, id: String(targetID))))
            try result.validate(request: requestId, operation: operation, target: targetID); return result
        } catch { throw mutationIssue(error) }
    }
    private struct CommandBody: Encodable { let requestId: String; let id: String }
    private struct IDBody: Encodable { let id: Int64 }
    private struct EmptyReceipt: Decodable {}
    private struct Header: Decodable { let code: Int; let errorCode: String? }
    private struct Envelope<T: Decodable>: Decodable { let data: T? }
    private func read<T: Decodable>(_ route: InvoiceLaunchRoute, body: Data = Data("{}".utf8)) async throws -> T {
        try check()
        do { return try await execute(route, body: body) }
        catch { try check(); throw (error as? InvoiceLaunchIssue) ?? .unavailable }
    }
    private func mutation<T: Decodable>(_ route: InvoiceLaunchRoute, body: Data, permitsEmpty: Bool = false) async throws -> T {
        try check(mutation: true)
        do { return try await execute(route, body: body, permitsEmpty: permitsEmpty) }
        catch { throw mutationIssue(error) }
    }
    private func mutationIssue(_ error: Error) -> InvoiceLaunchIssue {
        // Once dispatch might have happened, anything except a proven rollback is unknown.
        if case InvoiceLaunchIssue.rejected(let code) = error { return .rejected(code) }
        return .outcomeUnknown
    }
    private func execute<T: Decodable>(_ route: InvoiceLaunchRoute, body: Data, permitsEmpty: Bool = false) async throws -> T {
        try await execute(path: route.path, mutation: route.isMutation, original: route.needsOriginalReceipts,
            command: false, originalRead: route == .originalRequest || route == .titleRequest,
            body: body, permitsEmpty: permitsEmpty)
    }
    private func executeCommand<T: Decodable>(_ route: InvoiceLaunchCommandRoute, body: Data) async throws -> T {
        try await execute(path: route.path, mutation: route.isMutation, original: false,
            command: true, originalRead: route == .receipt, body: body)
    }
    private func execute<T: Decodable>(path: String, mutation: Bool, original: Bool, command: Bool,
                                      originalRead: Bool, body: Data, permitsEmpty: Bool = false) async throws -> T {
        if (original && !usesOriginalReceipts) || (command && !usesCommandReceipts) { throw InvoiceLaunchIssue.originalReadUnavailable }
        var request = URLRequest(url: session.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(session.token, forHTTPHeaderField: "Authorization")
        try check(mutation: mutation)
        let (data, status) = try await transport.send(request)
        try check(mutation: mutation)
        if (original && !usesOriginalReceipts) || (command && !usesCommandReceipts) { throw InvoiceLaunchIssue.originalReadUnavailable }
        guard data.count <= 1_048_576 else { throw InvoiceLaunchIssue.malformed }
        if status == 401 { unauthorized(); throw InvoiceLaunchIssue.unauthorized }
        guard status == 200 else { throw InvoiceLaunchIssue.unavailable }
        let header = try JSONDecoder().decode(Header.self, from: data)
        if header.code == 401 { unauthorized(); throw InvoiceLaunchIssue.unauthorized }
        if header.code != 200 {
            if originalRead { throw InvoiceLaunchIssue.outcomeUnknown }
            if let code = header.errorCode, Self.rollbacks.contains(code) { throw InvoiceLaunchIssue.rejected(code) }
            throw InvoiceLaunchIssue.unavailable
        }
        if permitsEmpty, let empty = EmptyReceipt() as? T {
            // Frozen titles/delete returns no data. An arbitrary object, array
            // or scalar is not a deletion acknowledgement, even with code 200.
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["data"] == nil || object["data"] is NSNull else { throw InvoiceLaunchIssue.malformed }
            return empty
        }
        guard let result = try JSONDecoder().decode(Envelope<T>.self, from: data).data else { throw InvoiceLaunchIssue.malformed }
        return result
    }
    // Frozen UserInvoiceException codes whose transaction is rolled back. REQUEST_REUSED
    // and REQUEST_IN_PROGRESS retain the original request; neither proves non-commit.
    private static let rollbacks: Set<String> = Set([
        "FEATURE_OFF", "ARGUMENT_INVALID", "TITLE_TYPE_INVALID", "TITLE_NAME_INVALID", "TAX_NO_INVALID",
        "TITLE_NOT_FOUND", "TITLE_LIMIT", "CRYPTO_UNAVAILABLE", "ORDERS_REQUIRED", "ORDERS_TOO_MANY",
        "ORDER_NOT_ELIGIBLE", "ORDER_ALREADY_INVOICED", "NOT_FOUND", "STATE_CONFLICT"
    ].map { "INVOICE_" + $0 })
}
