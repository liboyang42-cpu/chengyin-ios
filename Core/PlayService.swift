import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PlayFailure: Error, Equatable {
    public let httpStatus: Int?
    public let code: Int?
    public let message: String?
    public var isUnauthorized: Bool { httpStatus == 401 || code == 401 }
    /// HTTP 402 is a transport error. Only a successful HTTP envelope's business 402
    /// means a missing/expired self-play pass; never infer a purchase or payment result.
    public var needsPass: Bool { httpStatus == nil && code == 402 }
    public init(httpStatus: Int? = nil, code: Int? = nil, message: String? = nil) {
        self.httpStatus = httpStatus; self.code = code; self.message = message
    }
}

/// No host, credentials, background timer, automatic retry, media or location access.
/// Sources: play_api.dart fetchNodes/fetchTopicNodes/fetchRouteState/submitAnswer.
/// Inject the app's ephemeral no-redirect transport. Tests use fake transports only.
public struct PlayService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func nodes(scope: PlaySessionScope, token: String) async throws -> PlayNodesResult {
        let result: PlayNodesResult = try await execute(readRequest("api/play/nodes", scope: scope, token: token))
        if case .topic(let id) = scope, let returnedID = result.topicID, returnedID != id { throw APIError.malformedResponse }
        return result
    }
    public func routeState(scope: PlaySessionScope, token: String) async throws -> PlayRouteState {
        try await execute(readRequest("api/play/route-state", scope: scope, token: token))
    }
    /// Only an explicitly entered answer on a currently eligible linear node is allowed.
    /// Does not send guessed outcomeCode, targetNodeId, GPS or QR proof. A successful
    /// receipt must be followed by an authoritative nodes read, never local completion.
    public func answer(snapshot: PlaySnapshot, nodeID: Int, answer: String, token: String) async throws -> PlayAnswerReceipt {
        try snapshot.validateAnswer(nodeID: nodeID, answer: answer)
        var request = try baseRequest("api/play/answer", token: token)
        request.httpMethod = "POST"
        var fields = snapshot.scope.fields
        fields["nodeId"] = String(nodeID); fields["answer"] = answer
        // Flutter FormData is multipart/form-data, not application/x-www-form-urlencoded.
        // Fresh boundary excludes user text so it cannot terminate a submitted part.
        var boundary = "QuestifyPlay-" + UUID().uuidString
        while fields.values.contains(where: { $0.contains(boundary) }) { boundary = "QuestifyPlay-" + UUID().uuidString }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let parts = fields.sorted(by: { $0.key < $1.key }).map {
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"\($0.key)\"\r\n\r\n\($0.value)\r\n"
        }.joined() + "--\(boundary)--\r\n"
        request.httpBody = Data(parts.utf8)
        let receipt: PlayAnswerReceipt = try await execute(request)
        guard receipt.nodeID == nodeID else { throw APIError.malformedResponse }
        return receipt
    }
    private func readRequest(_ path: String, scope: PlaySessionScope, token: String) throws -> URLRequest {
        guard scope.isValid else { throw APIError.invalidRequest }
        var request = try baseRequest(path, token: token)
        guard var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        url.queryItems = scope.fields.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let finalURL = url.url else { throw APIError.invalidRequest }
        request.url = finalURL; request.httpMethod = "GET"
        return request
    }
    private func baseRequest(_ path: String, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    private func execute<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(status) else {
            let body = try? JSONDecoder().decode(FailureEnvelope.self, from: data)
            throw PlayFailure(httpStatus: status, code: body?.code, message: body?.message)
        }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: data).data }
        catch let failure as PlayFailure { throw failure }
        catch { throw APIError.malformedResponse }
    }
    private struct FailureEnvelope: Decodable {
        let code: Int?
        let message: String?
        private enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try? c.playInt(.code); message = try? c.decodeIfPresent(String.self, forKey: .msg)
        }
    }
    private struct Envelope<Value: Decodable>: Decodable {
        let data: Value
        private enum CodingKeys: String, CodingKey { case code, msg, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let code = try? c.playInt(.code)
            guard code == 200 else { throw PlayFailure(code: code, message: try? c.decodeIfPresent(String.self, forKey: .msg)) }
            data = try c.decode(Value.self, forKey: .data)
        }
    }
}
