import AuthenticationServices
import Foundation
import UIKit

/// Isolated native adapter. Production is hard-off; constructing it never starts Apple.
/// No email/full-name scopes, provider subject lookup, account linking, or persistence.
@MainActor
final class USAppleNativeAuthorizer: NSObject, USAppleAuthorizing,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    weak var presentationWindow: UIWindow?
    private var retainedWindow: UIWindow?
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<USAppleCredential, Error>?
    private var attemptID: UUID?

    func authorize(_ request: USAppleAuthorizationRequest) async throws -> USAppleCredential {
        guard USAppleProductionGate.enabled else { throw USAppleError.unavailable }
        try Task.checkCancellation()
        guard controller == nil, continuation == nil, let window = presentationWindow,
              window.windowScene != nil else { throw USAppleClientError.authorizationFailed }
        guard request.nonce.utf8.count == 64,
              request.nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              USAppleValidation.isRandomValue(request.state) else { throw USAppleError.invalidRequest }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                guard !Task.isCancelled else { pending.resume(throwing: CancellationError()); return }
                let appleRequest = ASAuthorizationAppleIDProvider().createRequest()
                appleRequest.requestedScopes = []
                appleRequest.nonce = request.nonce
                appleRequest.state = request.state
                let controller = ASAuthorizationController(authorizationRequests: [appleRequest])
                self.controller = controller; continuation = pending; attemptID = id; retainedWindow = window
                controller.delegate = self; controller.presentationContextProvider = self
                controller.performRequests()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.attemptID == id else { return }
                self.cancel()
            }
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // A real window is retained before performRequests; stale controllers never complete an attempt.
        guard self.controller === controller else { return ASPresentationAnchor() }
        return retainedWindow ?? ASPresentationAnchor()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard self.controller === controller else { return }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let bytes = credential.identityToken, bytes.count <= 16_384,
              let token = String(data: bytes, encoding: .utf8), USAppleValidation.isToken(token) else {
            complete(.failure(USAppleError.invalidIdentity)); return
        }
        complete(.success(USAppleCredential(identityToken: token, state: credential.state)))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard self.controller === controller else { return }
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        if cancelled { complete(.failure(CancellationError())) }
        else { complete(.failure(USAppleClientError.authorizationFailed)) }
    }
    private func complete(_ result: Result<USAppleCredential, Error>) {
        let pending = continuation
        // Invalidate BEFORE resuming; duplicate/late callbacks cannot resume a second time.
        continuation = nil; controller = nil; attemptID = nil; retainedWindow = nil
        pending?.resume(with: result)
    }
    func cancel() {
        let pendingController = controller
        complete(.failure(CancellationError()))
        pendingController?.cancel()
        presentationWindow = nil
    }
}
