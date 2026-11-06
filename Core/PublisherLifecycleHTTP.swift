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
    private let merchantPartnerReader: (any PublicMerchantHomeReading)?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, grants: PublisherLifecycleGrants = .dormant,
                merchantPartnerReader: (any PublicMerchantHomeReading)? = nil, credentials: @escaping () -> PublishingCredentials?) {
        self.configuration = configuration; self.transport = transport; self.grants = grants; self.credentials = credentials
        self.merchantPartnerReader = merchantPartnerReader
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
        let matches = preview.lineup.filter { $0.type == type && $0.partnerID == id }
        guard matches.count == 1, let row = matches.first, row.validTerms else { throw PublisherLifecycleError.incomplete }
        let profile: ProjectEditJSON
        if type == "club" {
            // Pinned controller requires @RequestBody Club, not legacy multipart.
            profile = try await read("api/club/detail", fields: ["id": .number(Decimal(id))], json: true)
            try check(captured)
            guard profile.object?["id"]?.integer == id else { throw PublisherLifecycleError.incomplete }
        } else {
            // Cooperation order toId is the merchant OWNER MEMBER, never merchant row id.
            // The legacy public-detail grant cannot authorize public-home or resolve this identity.
            guard let reader = merchantPartnerReader, reader.isConfigured,
                  let owner = PublicMerchantOwnerID(id) else { throw PublisherLifecycleError.unavailable }
            let scope = reader.scope
            let home: PublicMerchantHome
            do { home = try await reader.home(.ownerMemberID(owner)) }
            catch {
                try check(captured)
                guard reader.isConfigured, reader.scope == scope else { throw PublisherLifecycleError.stale }
                throw error
            }
            try check(captured)
            guard reader.isConfigured, reader.scope == scope, home.memberId == id,
                  let merchantID = home.id, merchantID > 0 else { throw PublisherLifecycleError.incomplete }
            profile = .object(["id": .number(Decimal(merchantID)), "memberId": .number(Decimal(id)),
                "name": home.name.map(ProjectEditJSON.string) ?? .null,
                "description": home.description.map(ProjectEditJSON.string) ?? .null])
        }
        try check(captured)
        guard let name = profile.object?["name"]?.text, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PublisherLifecycleError.incomplete }
        return PublisherPartnerInspection(terms: row, profile: profile)
    }
    /// Source pricing lineup row name (one read per row, no terms re-check): club `api/club/detail`,
    /// merchant through the approved public merchant home read keyed by owner member id.
    public func partnerName(type: String, id: Int) async throws -> String {
        guard ["club", "merchant"].contains(type), id > 0, let captured = credentials() else { throw PublisherLifecycleError.incomplete }
        let name: String?
        if type == "club" {
            let profile = try await read("api/club/detail", fields: ["id": .number(Decimal(id))], json: true)
            try check(captured)
            guard profile.object?["id"]?.integer == id else { throw PublisherLifecycleError.incomplete }
            name = profile.object?["name"]?.text
        } else {
            guard let reader = merchantPartnerReader, reader.isConfigured, let owner = PublicMerchantOwnerID(id) else { throw PublisherLifecycleError.unavailable }
            let scope = reader.scope
            let home = try await reader.home(.ownerMemberID(owner))
            try check(captured)
            guard reader.scope == scope, home.memberId == id else { throw PublisherLifecycleError.stale }
            name = home.name
        }
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PublisherLifecycleError.incomplete }
        return name
    }
}

