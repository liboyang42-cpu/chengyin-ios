import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

/// Prevent following redirects with credentials. Authentication APIs must respond directly.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.malformedResponse }
        return (data, http.statusCode)
    }
}

public struct AuthService {
    private let builder: AuthRequestBuilder
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        builder = AuthRequestBuilder(configuration: configuration)
        self.transport = transport
    }
    private struct Envelope: Decodable {
        let code: Int
        let token: String?
        let data: Account?
        let appUser: Account?
    }
    private func execute(_ endpoint: AuthEndpoint, fields: [String: String] = [:], token: String? = nil) async throws -> Envelope {
        let request = try builder.make(endpoint, fields: fields, token: token)
        let (data, status) = try await transport.send(request)
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw APIError.malformedResponse }
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        return envelope
    }
    public func login(username: String, password: String) async throws -> LoginResult {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { throw APIError.invalidRequest }
        let response = try await execute(.password, fields: ["username":username,"password":password])
        guard let token=response.token, AuthRequestBuilder.isValidToken(token),
              let account=response.data, account.id > 0 else { throw APIError.malformedResponse }
        return LoginResult(token: token, account: account)
    }
    public func currentAccount(token: String) async throws -> Account {
        let response = try await execute(.userInfo, token: token)
        guard let account = response.appUser, account.id > 0 else { throw APIError.malformedResponse }
        return account
    }
    public func logout(token: String) async throws { _ = try await execute(.logout, token: token) }
}
