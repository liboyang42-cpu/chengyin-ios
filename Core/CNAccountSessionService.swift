import Foundation

/// Existing CN session reads/revocation are independent of the password-entry channel.
/// This is not a US fallback: US requires its separately gated protected-proof contract.
public struct CNAccountSessionService {
    public let storageScope: RegionalSessionStorageScope
    private let auth: AuthService

    public init(configuration: RegionalConfiguration, storageScope: RegionalSessionStorageScope,
                transport: any HTTPTransport) throws {
        guard configuration.market == .china, storageScope.matches(configuration: configuration),
              let api = configuration.apiConfiguration,
              configuration.availability(of: .usernamePassword) == .available ||
                configuration.availability(of: .domesticChinaPhone) == .available else {
            throw APIError.notConfigured
        }
        self.storageScope = storageScope
        auth = AuthService(configuration: api, transport: transport)
    }

    /// Audited Flutter AuthApi.userInfo: bodyless POST, raw Authorization, appUser envelope.
    public func currentAccount(token: String) async throws -> Account {
        try Task.checkCancellation()
        let account = try await auth.currentAccount(token: token)
        try Task.checkCancellation()
        return account
    }

    /// Best-effort remote revocation after the caller has already closed the local session.
    public func logout(token: String) async throws {
        try Task.checkCancellation()
        try await auth.logout(token: token)
        try Task.checkCancellation()
    }
}
