import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MerchantEngagementService {
    private let configuration: APIConfiguration
    private let reads: any HTTPTransport
    private let actions: (any MerchantBusinessTestTransport)?
    public var realm: String { configuration.baseURL.absoluteString }
    public var isSyntheticEnabled: Bool { actions != nil }
    public init(configuration: APIConfiguration, readTransport: any HTTPTransport, testingActionTransport: (any MerchantBusinessTestTransport)? = nil) {
        self.configuration = configuration; reads = readTransport; actions = testingActionTransport
    }
    public func request(_ descriptor: MerchantEngagementRequest, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(descriptor.path), fields: [:], token: token, includesBody: false)
        request.httpMethod = descriptor.method
        if let fields = descriptor.fields {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            request.httpBody = try encoder.encode(fields); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    private func send(_ descriptor: MerchantEngagementRequest, token: String, transport: any HTTPTransport) async throws -> MerchantBusinessValue {
        let request = try request(descriptor, token: token); try Task.checkCancellation()
        let (bytes, status) = try await transport.send(request)
        if status == 401 { throw APIError.unauthorized }; if status == 403 { throw MerchantBusinessFailure.denied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let object = try JSONDecoder().decode(MerchantBusinessValue.self, from: bytes).object else { throw MerchantBusinessFailure.malformed }
        return try MerchantBusinessService.unwrap(object)
    }
    public func access(token: String) async throws -> MerchantEngagementAccess {
        let value = try await send(.post("api/merchant/access/me", nil), token: token, transport: reads)
        guard let fields = value.object else { throw MerchantBusinessFailure.malformed }; return try .init(fields)
    }
    public func read(_ query: MerchantEngagementQuery, access: MerchantEngagementAccess, token: String) async throws -> MerchantEngagementPayload {
        try access.require(query.permissions)
        if case .campaignPreview(_, .coupon) = query { try access.require(["merchant:coupon:manage"]) }
        let value = try await send(query.request(), token: token, transport: reads)
        return try .init(query: query, value: value)
    }
    /// Actual URLRequest execution, only through a deliberately injected test transport.
    /// Request IDs are included only where source specifies them.
    public func execute(_ command: MerchantEngagementCommand, requestID: String, access: MerchantEngagementAccess, token: String) async throws -> MerchantEngagementReceipt {
        guard let actions else { throw MerchantBusinessFailure.disabled }
        if case .acceptInvitation = command {} else { try access.require(command.permissions) }
        if case .downloadExport(let ticket, _, let merchantID) = command { guard access.merchantID == merchantID else { throw MerchantBusinessFailure.denied }; return .exportDownloaded(taskID: ticket.task.id, bytes: try await downloadSynthetic(ticket, token: token)) }
        if case .uploadEvidence(let refund, let selection, _, let merchantID) = command {
            guard let identity = access.identity, identity.merchantID == merchantID else { throw MerchantBusinessFailure.denied }
            let adapter = MerchantAftercareEvidenceAdapter(configuration: configuration, testingTransport: actions)
            let receipt = try await adapter.uploadSynthetic(bytes: selection.bytes, filename: selection.filename, mimeType: selection.mimeType, access: identity, token: token)
            return .evidenceUploaded(refundID: refund, selectionID: selection.id, receipt)
        }
        let value = try await send(command.request(requestID: requestID), token: token, transport: actions)
        return try .init(command: command, value: value)
    }
    public func refund(_ id: MerchantRefundID, access: MerchantEngagementAccess, token: String) async throws -> MerchantBusinessDocument {
        guard let identity = access.identity else { throw MerchantBusinessFailure.denied }
        return try await MerchantBusinessService(configuration: configuration, readTransport: reads).document(.refund(id), access: identity, token: token)
    }
    public func downloadSynthetic(_ ticket: MerchantExportTicket, token: String) async throws -> Data {
        guard let actions else { throw MerchantBusinessFailure.disabled }
        guard ticket.canDownload, let downloadToken = ticket.downloadToken else { throw MerchantBusinessFailure.invalid }
        var request = try request(.get("api/merchant/crm/exports/\(ticket.task.id)/download"), token: token)
        request.setValue(downloadToken, forHTTPHeaderField: "X-CRM-Export-Token")
        // Never put the export credential in a query string, route, file name or log.
        try Task.checkCancellation()
        let (bytes, status) = try await actions.send(request)
        if status == 401 { throw APIError.unauthorized }; if status == 403 { throw MerchantBusinessFailure.denied }
        guard (200..<300).contains(status), !bytes.isEmpty else { throw MerchantBusinessFailure.malformed }
        // Source returns XLSX. Reject a JSON/HTML error body masquerading as a download.
        guard bytes.starts(with: [0x50, 0x4b, 0x03, 0x04]) else { throw MerchantBusinessFailure.malformed }
        return bytes
    }
}
