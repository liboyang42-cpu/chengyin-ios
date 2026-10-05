import Foundation

/// Explicitly injected only. The application factory continues to construct the disabled adapter.
/// No default network provider, endpoint, token or live approval is created here.
@MainActor public final class TemplateAuthoringHTTPTransport: TemplateAuthoringTransport {
    private let configuration: APIConfiguration
    private let http: any HTTPTransport
    private let expectedSession: TemplateAuthoringSession
    private let credentials: () -> (session: TemplateAuthoringSession, token: String)?
    private let enabled: Bool
    public init(configuration: APIConfiguration, http: any HTTPTransport,
                session: TemplateAuthoringSession, enabled: Bool = false,
                credentials: @escaping () -> (session: TemplateAuthoringSession, token: String)?) {
        self.configuration = configuration; self.http = http; expectedSession = session
        self.enabled = enabled; self.credentials = credentials
    }
    public var authority: TemplateAuthoringAuthority { enabled ? .injectedHTTP : .disabled }
    public func send(_ descriptor: TemplateAuthoringRequest) async throws -> (Data, Int) {
        guard enabled else { throw TemplateAuthoringError.unavailable }
        guard !Task.isCancelled, let before = credentials(), before.session == expectedSession,
              AuthRequestBuilder.isValidToken(before.token) else { throw TemplateAuthoringError.changedSession }
        let request = try TemplateAuthoringWireRequestBuilder.make(descriptor, configuration: configuration, token: before.token)
        let result = try await http.send(request)
        guard !Task.isCancelled, let after = credentials(), after.session == before.session,
              after.token == before.token else { throw TemplateAuthoringError.changedSession }
        return result
    }
}
