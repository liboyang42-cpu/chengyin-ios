import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent endpoint grants. A read grant cannot authorize any consequence.
public struct PublisherLifecycleGrants {
    public let reads: OperationEndpointApproval?
    public let pricing: OperationEndpointApproval?
    public let cancellationRefunds: OperationEndpointApproval?
    public let ownership: OperationEndpointApproval?
    public let graduation: OperationEndpointApproval?
    public let creatorApplication: OperationEndpointApproval?
    public init(reads: OperationEndpointApproval? = nil, pricing: OperationEndpointApproval? = nil,
                cancellationRefunds: OperationEndpointApproval? = nil, ownership: OperationEndpointApproval? = nil,
                graduation: OperationEndpointApproval? = nil, creatorApplication: OperationEndpointApproval? = nil) {
        self.reads = reads; self.pricing = pricing; self.cancellationRefunds = cancellationRefunds
        self.ownership = ownership; self.graduation = graduation; self.creatorApplication = creatorApplication
    }
    public static var dormant: Self { .init() }
}
@MainActor public final class PublisherLifecycleHTTP {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    let credentials: () -> PublishingCredentials?
    let grants: PublisherLifecycleGrants
    public init(configuration: APIConfiguration, transport: any HTTPTransport, grants: PublisherLifecycleGrants = .dormant,
                credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.grants = grants; self.credentials = credentials
    }
    public var session: PublishingSession? { credentials()?.session }
    func check(_ captured: PublishingCredentials) throws {
        try Task.checkCancellation()
        guard credentials() == captured else { throw PublisherLifecycleError.stale }
    }
    func permits(_ path: String, grant: OperationEndpointApproval?, credential: PublishingCredentials) -> Bool {
        grant?.allows(configuration: configuration, namespace: credential.session.namespace, accountID: credential.session.accountID, path: path) == true
    }
    func request(path: String, fields: [String: ProjectEditJSON], json: Bool, credential: PublishingCredentials) throws -> URLRequest {
        if json { return try OperationAdapterHTTP.json(configuration: configuration, path: path, body: JSONEncoder().encode(fields), token: credential.token) }
        var form: [String: String] = [:]
        for (key, value) in fields { guard let text = PublisherValue.raw(value) else { throw PublisherLifecycleError.incomplete }; form[key] = text }
        // Source uses Dio FormData, i.e. multipart, not URL encoding.
        let boundary = "Publisher-" + UUID().uuidString
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: credential.token, includesBody: false)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        for key in form.keys.sorted() {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(form[key]!)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8)); request.httpBody = body
        return request
    }
    func send(_ request: URLRequest, credential: PublishingCredentials) async throws -> [String: ProjectEditJSON] {
        try check(credential)
        let (data, status) = try await transport.send(request)
        try check(credential)
        if status == 401 { throw APIError.unauthorized }
        let envelope = try OperationAdapterHTTP.envelope(data)
        if envelope["code"]?.integer == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let code = envelope["code"]?.integer else { throw APIError.malformedResponse }
        guard code == 200 else { throw PublisherLifecycleError.rejected(envelope["msg"]?.text ?? "") }
        return envelope
    }
    func read(_ path: String, fields: [String: ProjectEditJSON], json: Bool = false) async throws -> ProjectEditJSON {
        let paths: Set<String> = ["api/topic/pricing/preview", "api/topic/cancel_preview", "api/activity/cancel_preview", "api/topic/xp-budget", "api/club/detail", "api/merchant/public-detail"]
        guard paths.contains(path), let credential = credentials(), permits(path, grant: grants.reads, credential: credential) else { throw PublisherLifecycleError.unavailable }
        return try await send(request(path: path, fields: fields, json: json, credential: credential), credential: credential)["data"] ?? .null
    }
    public func pricing(_ input: PublisherPricingInput) async throws -> PublisherPricingPreview {
        try PublisherPricingPreview(await read("api/topic/pricing/preview", fields: input.fields, json: true))
    }
    public func paidPlayers(_ resource: PublishedResource, scope: String? = nil) async throws -> Int {
        guard resource.kind == .topic || resource.kind == .activity else { throw PublisherLifecycleError.forbidden }
        var fields: [String: ProjectEditJSON] = ["id": .string(String(resource.value))]
        if let scope, !scope.isEmpty { fields["scope"] = .string(scope) }
        let data = try await read("api/\(resource.kind.rawValue)/cancel_preview", fields: fields)
        guard let number = PublisherValue.integer(data.object?["paidPlayers"]), number >= 0 else { throw PublisherLifecycleError.incomplete }
        return number
    }
    public func budget(topicID: Int) async throws -> PublisherXPBudget {
        guard topicID > 0 else { throw PublisherLifecycleError.incomplete }
        return try PublisherXPBudget(await read("api/topic/xp-budget", fields: ["topic_id": .string(String(topicID))]))
    }
    public func partner(topicID: Int, type: String, id: Int) async throws -> PublisherPartnerInspection {
        guard ["club", "merchant"].contains(type), id > 0, let captured = credentials() else { throw PublisherLifecycleError.incomplete }
        let preview = try await pricing(PublisherPricingInput(topicID: topicID, subtype: .selfPlay))
        try check(captured)
        guard let row = preview.lineup.first(where: { $0.type == type && $0.partnerID == id }), row.validTerms else { throw PublisherLifecycleError.incomplete }
        let profile = try await read(type == "club" ? "api/club/detail" : "api/merchant/public-detail", fields: ["id": type == "club" ? .string(String(id)) : .number(Decimal(id))], json: type == "merchant")
        try check(captured)
        guard let name = profile.object?["name"]?.text, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PublisherLifecycleError.incomplete }
        return PublisherPartnerInspection(terms: row, profile: profile)
    }
}
