import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProfileEditService: ProfileEditServing {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    private func request(_ path: String, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token, includesBody: false)
    }
    private struct Response: Decodable { let code: Int; let msg: String? }
    public func read(token: String) async throws -> ProfileEditSnapshot {
        var request = try request("api/user/info", token: token)
        let boundary = "ProfileRead-" + UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("--\(boundary)--\r\n".utf8)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        let envelope = try? JSONDecoder().decode(Response.self, from: data)
        guard (200..<300).contains(status), envelope?.code == 200 else {
            throw ProfileReadFailure(httpStatus: status, code: envelope?.code, message: envelope?.msg)
        }
        struct Detail: Decodable { let data: ProfileEditSnapshot }
        do { return try JSONDecoder().decode(Detail.self, from: data).data }
        catch { throw APIError.malformedResponse }
    }
    public func save(_ payload: ProfileEditPayload, token: String) async throws {
        var prepared: URLRequest
        do {
            prepared = try request("api/user/update", token: token)
            prepared.setValue("application/json", forHTTPHeaderField: "Content-Type")
            prepared.httpBody = try JSONEncoder().encode(payload)
            try Task.checkCancellation()
        } catch { throw ProfileEditWriteError.notSent }
        let data: Data, status: Int
        do { (data, status) = try await transport.send(prepared) }
        catch { throw ProfileEditWriteError.outcomeUnknown }
        guard !Task.isCancelled else { throw ProfileEditWriteError.outcomeUnknown }
        let envelope = try? JSONDecoder().decode(Response.self, from: data)
        if status == 401 || status == 403 {
            throw ProfileEditWriteError.rejected(.init(httpStatus: status, code: envelope?.code, message: envelope?.msg))
        }
        guard (200..<300).contains(status), let envelope else { throw ProfileEditWriteError.outcomeUnknown }
        guard envelope.code == 200 else {
            throw ProfileEditWriteError.rejected(.init(code: envelope.code, message: envelope.msg))
        }
    }
}
