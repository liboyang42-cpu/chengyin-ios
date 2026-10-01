import AuthenticationServices
import SwiftUI
import UIKit

/// Standalone integration surface, deliberately not added to the root/session/project.
/// The host must localize state.issue.localizationKey using the supplied bilingual JSON.
@MainActor
final class USAppleSignInModel: ObservableObject {
    @Published private(set) var state: USAppleState
    let coordinator: USAppleCoordinator
    private let authorizer: USAppleNativeAuthorizer
    private var task: Task<Void, Never>?
    private var taskID = UUID()
    init(deployment: USAppleDeployment, service: (any USAppleServing)?,
         currentSession: @escaping () -> USAppleSessionSnapshot,
         verifyCurrentAccount: @escaping (String) async throws -> USAppleVerifiedCurrentAccount,
         commitLogin: @escaping (LoginResult, USAppleSessionSnapshot) throws -> Bool) {
        let authorizer = USAppleNativeAuthorizer()
        self.authorizer = authorizer
        coordinator = USAppleCoordinator(deployment: deployment, service: service, authorizer: authorizer,
            currentSession: currentSession, verifyCurrentAccount: verifyCurrentAccount, commitLogin: commitLogin)
        state = coordinator.state
        coordinator.onStateChange = { [weak self] in
            guard let self else { return }
            self.state = self.coordinator.state
        }
    }
    func start(in window: UIWindow) {
        guard coordinator.canStart, task == nil else { return }
        authorizer.presentationWindow = window
        let id = UUID(); taskID = id
        task = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.signIn()
            if self.taskID == id { self.task = nil }
        }
    }
    /// Also call on host session/realm changes and when leaving the sign-in surface.
    func cancel() {
        taskID = UUID(); coordinator.cancel(); task?.cancel(); task = nil
    }
    func becameActive() { coordinator.expireIfNeeded() }
}

@MainActor
struct USAppleSignInButton: UIViewRepresentable {
    @ObservedObject var model: USAppleSignInModel
    @Environment(\.colorScheme) private var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: colorScheme == .dark ? .white : .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.signIn(_:)), for: .touchUpInside)
        button.accessibilityIdentifier = "usApple.signIn"
        button.isEnabled = model.coordinator.canStart
        return button
    }
    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.model = model
        button.isEnabled = model.coordinator.canStart
        button.alpha = button.isEnabled ? 1 : 0.5
    }
    static func dismantleUIView(_ button: ASAuthorizationAppleIDButton, coordinator: Coordinator) {
        coordinator.model.cancel()
    }
    @MainActor
    final class Coordinator: NSObject {
        var model: USAppleSignInModel
        init(model: USAppleSignInModel) { self.model = model }
        @objc func signIn(_ sender: ASAuthorizationAppleIDButton) {
            guard let window = sender.window else { return }
            model.start(in: window)
        }
    }
}
