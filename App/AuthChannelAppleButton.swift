import SwiftUI
import AuthenticationServices
import UIKit

/// True system Apple button and authorization controller. Configuration defaults off
/// in the domain coordinator. No sign-in/account/capability is created by constructing
/// this view. Retained ticket + controller identity reject stale/duplicate callbacks.
@MainActor
struct AuthChannelAppleButton: UIViewRepresentable {
    @ObservedObject var model: AuthChannelModel
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: colorScheme == .dark ? .white : .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.signIn(_:)), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.model = model
        button.isEnabled = model.canStart && model.coordinator.appleConfigurationVerified
        button.alpha = button.isEnabled ? 1 : 0.5
    }
    static func dismantleUIView(_ button: ASAuthorizationAppleIDButton, coordinator: Coordinator) {
        coordinator.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        var model: AuthChannelModel
        private var controller: ASAuthorizationController?
        private var attempt: AuthChannelAppleAttempt?
        private var window: UIWindow?
        init(model: AuthChannelModel) { self.model = model }
        @objc func signIn(_ sender: ASAuthorizationAppleIDButton) {
            guard controller == nil, let window = sender.window,
                  let attempt = model.coordinator.beginAppleAuthorization() else { return }
            self.window = window; self.attempt = attempt
            let request = ASAuthorizationAppleIDProvider().createRequest()
            // Match the source authorization scopes. Only identityToken is exchanged;
            // no supplied email or name is persisted or added to an invented API route.
            request.requestedScopes = [.email, .fullName]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            // Set before performRequests and retained until completion/cancel.
            window ?? ASPresentationAnchor()
        }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            guard self.controller === controller, let attempt else { return }
            self.controller = nil; self.attempt = nil; window = nil
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                model.coordinator.failAppleAuthorization(attempt, issue: .appleMissingCredential)
                return
            }
            model.exchangeApple(attempt, identityToken: token)
        }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            guard self.controller === controller, let attempt else { return }
            self.controller = nil; self.attempt = nil; window = nil
            let cancelled = (error as? ASAuthorizationError)?.code == .canceled
            model.coordinator.failAppleAuthorization(attempt, issue: cancelled ? .appleIncomplete : .appleFailed)
        }
        func cancel() {
            let pending = controller
            let ticket = attempt
            controller = nil; attempt = nil
            // Invalidate the app operation before the controller's cancellation callback.
            if let ticket { model.coordinator.failAppleAuthorization(ticket, issue: .appleIncomplete) }
            pending?.cancel()
            window = nil
        }
    }
}
