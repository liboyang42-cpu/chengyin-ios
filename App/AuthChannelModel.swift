import SwiftUI

/// Form-only memory. No defaults, analytics or Keychain access; the host owns session
/// persistence via AuthChannelCoordinator.commitLogin. Retain the coordinator in host.
@MainActor
final class AuthChannelModel: ObservableObject {
    @Published private(set) var state: AuthChannelState
    @Published var phone = ""
    @Published var code = ""
    let coordinator: AuthChannelCoordinator
    private var task: Task<Void, Never>?

    init(coordinator: AuthChannelCoordinator) {
        self.coordinator = coordinator
        state = coordinator.state
        coordinator.onStateChange = { [weak self] in
            guard let self else { return }
            self.state = self.coordinator.state
        }
    }
    var canStart: Bool { coordinator.canStart }
    func sendCode() {
        guard canStart else { return }
        let value = phone
        task = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.sendSMSCode(phone: value)
        }
    }
    func signIn() {
        guard canStart else { return }
        let phoneValue = phone, codeValue = code
        code = ""
        task = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.loginWithPhone(phone: phoneValue, code: codeValue)
        }
    }
    func exchangeApple(_ attempt: AuthChannelAppleAttempt, identityToken: String) {
        task = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.completeAppleAuthorization(attempt, identityToken: identityToken)
        }
    }
    func clear() {
        task?.cancel(); task = nil
        coordinator.cancel(); code = ""; phone = ""
    }
    func phoneChanged() {
        code = ""
        coordinator.resetPhoneFeedback()
    }
}
