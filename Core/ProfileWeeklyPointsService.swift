import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProfileWeeklyPointsService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func read(token: String) async throws -> ProfileWeeklyPoints {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent(ProfileWeeklyPointsReadRoute.path),
            fields: [:], token: token, includesBody: false)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard data.count <= 16 * 1024 else { throw APIError.malformedResponse }
        let envelope = try? JSONDecoder().decode(Status.self, from: data)
        if status == 401 || envelope?.code == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let envelope else { throw APIError.malformedResponse }
        guard envelope.code == 200 else { throw ProfileReadFailure(code: envelope.code, message: nil) }
        do { return try JSONDecoder().decode(Payload.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
    private struct Status: Decodable { let code: Int }
    private struct Payload: Decodable { let data: ProfileWeeklyPoints }
}
