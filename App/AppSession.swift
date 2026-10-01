import Foundation
import Combine

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var isWorking = false
    @Published private(set) var errorKey: String?
    private var epoch = SessionEpoch()
    private let vault = KeychainTokenStore()
    private let service: AuthService?
    private var token: String?
    private var didBootstrap = false
    private let restoreBlockedKey = "session.preventRestore"
    var isConfigured: Bool { service != nil }

    init() {
        if let value=Bundle.main.object(forInfoDictionaryKey:"QuestifyAPIBaseURL") as? String,
           let url=URL(string:value), let configuration=try? APIConfiguration(baseURL:url) {
            service=AuthService(configuration:configuration,transport:URLSessionTransport())
        } else { service=nil }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap=true
        guard let service else { return }
        if UserDefaults.standard.bool(forKey:restoreBlockedKey) {
            try? vault.clear()
            return
        }
        let operation=epoch.advance()
        isWorking=true
        defer { if epoch.isCurrent(operation) { isWorking=false } }
        do {
            guard let saved=try vault.read() else { return }
            let restored=try await service.currentAccount(token:saved)
            guard epoch.isCurrent(operation) else { return }
            token=saved;account=restored
        } catch {
            guard epoch.isCurrent(operation) else { return }
            if error as? APIError == .unauthorized {
                UserDefaults.standard.set(true,forKey:restoreBlockedKey)
                try? vault.clear()
            }
            // Offline or server failure never silently deletes a valid saved credential.
            errorKey=Self.messageKey(for:error)
        }
    }

    func login(username:String,password:String) async {
        guard !isWorking else { return }
        guard let service else { errorKey="auth.notConfigured";return }
        let operation=epoch.advance()
        isWorking=true;errorKey=nil
        defer { if epoch.isCurrent(operation) { isWorking=false } }
        do {
            let result=try await service.login(username:username,password:password)
            guard epoch.isCurrent(operation) else { return }
            try vault.write(result.token)
            UserDefaults.standard.set(false,forKey:restoreBlockedKey)
            token=result.token;account=result.account
        } catch {
            guard epoch.isCurrent(operation) else { return }
            errorKey=Self.messageKey(for:error)
        }
    }

    func cancelPendingLogin() {
        epoch.advance();isWorking=false;errorKey=nil
    }

    func logout() async {
        let oldToken=token
        epoch.advance()
        // Persist a non-secret tombstone before deletion. A Keychain failure cannot
        // silently restore a logged-out account at the next cold start.
        UserDefaults.standard.set(true,forKey:restoreBlockedKey)
        token=nil;account=nil;isWorking=false;errorKey=nil
        do { try vault.clear() } catch { errorKey="auth.storageError" }
        if let service, let oldToken {
            // Captured old credential only. Completion cannot mutate a newer login.
            try? await service.logout(token:oldToken)
        }
    }

    private static func messageKey(for error:Error) -> String {
        if error is KeychainTokenStore.StoreError { return "auth.storageError" }
        switch error as? APIError {
        case .notConfigured, .invalidConfiguration: return "auth.notConfigured"
        case .unauthorized: return "auth.expired"
        case .invalidRequest: return "auth.invalidInput"
        case .malformedResponse: return "auth.invalidResponse"
        case .businessCode: return "auth.loginRejected"
        default: return "auth.networkError"
        }
    }
}
