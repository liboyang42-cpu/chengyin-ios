import Foundation

/// Two independently loaded own-account domains. Only audited read routes exist here.
/// Inject the app's existing ephemeral/no-redirect transport; there is no default host.
public struct CreatorContentService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func projects(query: CreatorContentQuery = .init(), token: String) async throws -> CreatorContentProjectPage {
        guard query.isValid else { throw APIError.invalidRequest }
        let data = try await post("api/project/my", fields: ["type": query.type, "state": query.state, "ownerType": query.ownerType, "pageNum": "1", "pageSize": "200"], token: token)
        return try decode(ProjectsEnvelope.self, data).data
    }
    public func center(token: String) async throws -> CreatorContentCenter {
        let data = try await post("api/creator/center", fields: [:], token: token)
        return try decode(CenterEnvelope.self, data).data
    }
    private func post(_ path: String, fields: [String: String], token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else {
            if let envelope = try? JSONDecoder().decode(StatusEnvelope.self, from: data), let message = envelope.message {
                throw CreatorContentReadFailure.rejected(code: envelope.code, message: message)
            }
            throw APIError.httpStatus(status)
        }
        let statusEnvelope = try decode(StatusEnvelope.self, data)
        if statusEnvelope.code == 401 { throw APIError.unauthorized }
        guard statusEnvelope.code == 200 else {
            throw CreatorContentReadFailure.rejected(code: statusEnvelope.code, message: statusEnvelope.message)
        }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw APIError.malformedResponse }
    }
    private struct StatusEnvelope: Decodable {
        let code: Int
        let message: String?
        enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            message = try? c.decode(String.self, forKey: .msg)
        }
    }
    private struct ProjectsEnvelope: Decodable { let data: CreatorContentProjectPage }
    private struct CenterEnvelope: Decodable { let data: CreatorContentCenter }
}
