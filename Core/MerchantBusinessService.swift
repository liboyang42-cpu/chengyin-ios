import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Writes only execute through an explicitly injected test transport. The production initializer
/// never wires URLSession to mutation dispatch. Read adapters use the approved host configuration.
public protocol MerchantBusinessTestTransport: HTTPTransport {}
public struct MerchantBusinessService {
    private let configuration: APIConfiguration
    private let readTransport: any HTTPTransport
    private let mutationTransport: (any MerchantBusinessTestTransport)?
    public var canExecuteSyntheticMutation: Bool { mutationTransport != nil }
    public var realm: String { configuration.baseURL.absoluteString }
    public init(configuration: APIConfiguration, readTransport: any HTTPTransport, testingMutationTransport: (any MerchantBusinessTestTransport)? = nil) {
        self.configuration = configuration; self.readTransport = readTransport; mutationTransport = testingMutationTransport
    }
    public func makeRequest(_ descriptor: MerchantBusinessRequest, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var url = URLComponents(url: configuration.baseURL.appendingPathComponent(descriptor.path), resolvingAgainstBaseURL: false)!
        if !descriptor.query.isEmpty { url.queryItems = descriptor.query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let target = url.url else { throw MerchantBusinessFailure.invalid }
        let fields: [String: String]
        if case .form(let values) = descriptor.body { fields = values } else { fields = [:] }
        var request = try AuthRequestBuilder.makeFormRequest(url: target, fields: fields, token: token, includesBody: { if case .form = descriptor.body { return true }; return false }())
        if case .json(let fields) = descriptor.body {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(fields); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    private func envelope(_ descriptor: MerchantBusinessRequest, token: String, transport: any HTTPTransport) async throws -> MerchantBusinessObject {
        let request = try makeRequest(descriptor, token: token)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        // Cancellation after a mutation dispatch is not evidence that nothing happened.
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw MerchantBusinessFailure.denied }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let object = try JSONDecoder().decode(MerchantBusinessValue.self, from: data).object else { throw MerchantBusinessFailure.malformed }
        return object
    }
    static func unwrap(_ body: MerchantBusinessObject) throws -> MerchantBusinessValue {
        let code = try body.mbInt("code")
        if code == 401 { throw APIError.unauthorized }
        if code == 403 { throw MerchantBusinessFailure.denied }
        guard code == 200 else { throw MerchantBusinessFailure.rejected(code, body.mbText("msg")) }
        guard let data = body["data"], data != .null else { throw MerchantBusinessFailure.malformed }; return data
    }
    public func access(token: String) async throws -> MerchantBusinessAccess {
        let body = try await envelope(.empty("api/merchant/access/me"), token: token, transport: readTransport)
        guard let object = try Self.unwrap(body).object else { throw MerchantBusinessFailure.malformed }
        return try .init(object)
    }
    public func document(_ query: MerchantBusinessQuery, access: MerchantBusinessAccess, token: String) async throws -> MerchantBusinessDocument {
        try access.require(query.permissions)
        let body = try await envelope(query.request(), token: token, transport: readTransport)
        return try .init(query: query, payload: Self.unwrap(body))
    }
    public func execute(_ mutation: MerchantBusinessMutation, requestID: String, token: String) async throws -> MerchantBusinessReceipt {
        guard let mutationTransport else { throw MerchantBusinessFailure.disabled }
        let descriptor = try mutation.request(requestID: requestID)
        let body = try await envelope(descriptor, token: token, transport: mutationTransport)
        return try .init(mutation: mutation, message: body.mbText("msg"), data: Self.unwrap(body))
    }
    // Internal shared primitive for the separate typed redemption adapter. Never sends through reads.
    func syntheticEnvelope(_ descriptor: MerchantBusinessRequest, token: String) async throws -> MerchantBusinessObject {
        guard let mutationTransport else { throw MerchantBusinessFailure.disabled }
        return try await envelope(descriptor, token: token, transport: mutationTransport)
    }
}
