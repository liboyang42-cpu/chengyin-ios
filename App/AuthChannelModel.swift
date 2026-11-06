import SwiftUI

/// Form-only memory. No defaults, analytics or Keychain access; the host owns session
/// persistence via AuthChannelCoordinator.commitLogin. Retain the coordinator in host.
@MainActor
final class AuthChannelModel: ObservableObject {
    @Published private(set) var state: AuthChannelState
    @Published private(set) var isScheduled = false
    @Published var phone = ""
    @Published var code = ""
    let coordinator: AuthChannelCoordinator
    private let presentation: AuthChannelPresentation
    private var task: Task<Void, Never>?
    private var taskIdentity: UUID?

    init(coordinator: AuthChannelCoordinator) {
        self.coordinator = coordinator
        presentation = coordinator.beginPresentation()
        state = coordinator.state
        coordinator.onStateChange = { [weak self] in
            guard let self, self.coordinator.ownsPresentation(self.presentation) else { return }
            self.state = self.coordinator.state
        }
    }
    var canStart: Bool { coordinator.ownsPresentation(presentation) && !isScheduled && coordinator.canStart }
    func sendCode() {
        guard canStart, let intent = coordinator.captureIntent(for: .sendingSMS) else { return }
        let value = phone
        schedule { [coordinator] in
            await coordinator.sendSMSCode(phone: value, intent: intent)
        }
    }
    func signIn() {
        guard canStart, let intent = coordinator.captureIntent(for: .phoneLogin) else { return }
        let phoneValue = phone, codeValue = code
        code = ""
        schedule { [coordinator] in
            await coordinator.loginWithPhone(phone: phoneValue, code: codeValue, intent: intent)
        }
    }
    func exchangeApple(_ attempt: AuthChannelAppleAttempt, identityToken: String) {
        guard coordinator.ownsPresentation(presentation), coordinator.canCompleteAppleAuthorization(attempt) else { return }
        // Native Apple authorization already captures its session/generation synchronously.
        schedule { [coordinator] in
            await coordinator.completeAppleAuthorization(attempt, identityToken: identityToken)
        }
    }
    private func schedule(_ operation: @escaping @MainActor () async -> Void) {
        task?.cancel()
        let identity = UUID()
        taskIdentity = identity
        isScheduled = true
        task = Task { [weak self] in
            guard let self, self.taskIdentity == identity else { return }
            defer {
                // An old completion must not clear the replacement form's queued work.
                if self.taskIdentity == identity {
                    self.task = nil; self.taskIdentity = nil; self.isScheduled = false
                }
            }
            guard self.coordinator.ownsPresentation(self.presentation), !Task.isCancelled else { return }
            await operation()
        }
    }
    func clear() {
        taskIdentity = nil
        task?.cancel(); task = nil; isScheduled = false
        coordinator.cancel(presentation: presentation); code = ""; phone = ""
    }
    func phoneChanged() {
        code = ""
        guard coordinator.ownsPresentation(presentation) else { return }
        coordinator.resetPhoneFeedback()
    }
}
