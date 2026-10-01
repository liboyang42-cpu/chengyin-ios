import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Inject an approved configuration/transport. No URL defaults, automatic requests, retries or logging.
public struct MerchantOnboardingService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    private func request(_ path: String, token: String, json: Data? = nil, multipart: Bool = false) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var result = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path),
            fields: [:], token: token, includesBody: multipart)
        if let json { result.setValue("application/json", forHTTPHeaderField: "Content-Type"); result.httpBody = json }
        return result
    }
    private struct Response: Decodable {
        let code: Int
        let msg: String?
    }
    private func read(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw APIError.malformedResponse }
        if response.code == 401 { throw APIError.unauthorized }
        guard response.code == 200 else { throw MerchantOnboardingFailure(code: response.code, message: response.msg) }
        return data
    }
    public func application(token: String) async throws -> MerchantOnboardingSnapshot {
        let data = try await read(request("api/merchant/info", token: token, multipart: true))
        struct ApplicationResponse: Decodable {
            let snapshot: MerchantOnboardingSnapshot
            enum CodingKeys: String, CodingKey { case data, applicationState }
            private struct EmptyObject: Decodable {
                let isEmpty: Bool
                init(from decoder: Decoder) throws { isEmpty = try decoder.container(keyedBy: AnyKey.self).allKeys.isEmpty }
                struct AnyKey: CodingKey {
                    var stringValue: String; var intValue: Int? { nil }
                    init?(stringValue: String) { self.stringValue = stringValue }
                    init?(intValue: Int) { return nil }
                }
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let absent: Bool
                if c.contains(.data) { absent = try c.decodeNil(forKey: .data) } else { absent = true }
                let empty = (try? c.decode(EmptyObject.self, forKey: .data).isEmpty) == true
                if (absent || empty), (try? c.decode(String.self, forKey: .applicationState)) == "NONE" {
                    snapshot = .none
                } else { snapshot = .application(try c.decode(MerchantOnboardingApplication.self, forKey: .data)) }
            }
        }
        do { return try JSONDecoder().decode(ApplicationResponse.self, from: data).snapshot }
        catch { throw APIError.malformedResponse }
    }
    /// This means registered, not government-verified identity. No national-ID collection is implemented here.
    public func identityRegistered(token: String) async throws -> Bool {
        let data = try await read(request("api/publisher/identity/status", token: token, json: Data("{}".utf8)))
        struct IdentityResponse: Decodable { let data: Identity; struct Identity: Decodable { let registered: Bool } }
        do { return try JSONDecoder().decode(IdentityResponse.self, from: data).data.registered }
        catch { throw APIError.malformedResponse }
    }
    public func submit(_ draft: MerchantOnboardingDraft, token: String) async throws {
        let prepared: URLRequest
        do { prepared = try request("api/merchant/merchant_registration", token: token, json: draft.jsonData()) }
        catch { throw MerchantOnboardingWriteError.notSent }
        _ = try await write(prepared)
    }
    /// Call only after explicit upload confirmation. The response URL is top-level, not data.url.
    public func uploadLicense(_ image: MerchantOnboardingImage, token: String) async throws -> MerchantOnboardingLicense {
        let boundary = "MerchantLicense-" + UUID().uuidString
        var prepared: URLRequest
        do { prepared = try request("api/common/uploadOSS", token: token) }
        catch { throw MerchantOnboardingWriteError.notSent }
        prepared.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"business-license.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(image.data); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); prepared.httpBody = body
        let data = try await write(prepared)
        struct Upload: Decodable { let url: String }
        do { return try MerchantOnboardingLicense(serverURL: JSONDecoder().decode(Upload.self, from: data).url) }
        catch { throw MerchantOnboardingWriteError.outcomeUnknown }
    }
    private func write(_ request: URLRequest) async throws -> Data {
        guard !Task.isCancelled else { throw MerchantOnboardingWriteError.notSent }
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch { throw MerchantOnboardingWriteError.outcomeUnknown }
        guard !Task.isCancelled else { throw MerchantOnboardingWriteError.outcomeUnknown }
        let response = try? JSONDecoder().decode(Response.self, from: data)
        if status == 401 || status == 403 {
            throw MerchantOnboardingWriteError.rejected(.init(code: status, message: response?.msg))
        }
        guard (200..<300).contains(status), let response else { throw MerchantOnboardingWriteError.outcomeUnknown }
        guard response.code == 200 else {
            throw MerchantOnboardingWriteError.rejected(.init(code: response.code, message: response.msg))
        }
        return data
    }
}
