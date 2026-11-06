import SwiftUI

/// Explicit read-only recovery on the existing login form, never a new login/SMS route.
@MainActor struct SessionRestorationRetrySection: View {
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var attempt: SessionRestorationRetryAttempt?
    @State private var task: Task<Void, Never>?

    var body: some View {
        Group {
            if session.sessionRestorationRetry.isAvailable || session.sessionRestorationRetry.pending != nil {
                Section {
                    Button {
                        guard let next = session.prepareSessionRestorationRetry() else { return }
                        attempt = next
                        task = Task { await session.retrySessionRestoration(next) }
                    } label: {
                        HStack {
                            Text("auth.restore.retry", tableName: "SessionRestorationRetry")
                            Spacer()
                            if session.sessionRestorationRetry.pending != nil { ProgressView() }
                        }
                    }
                    .disabled(!session.canRetrySessionRestoration)
                    .accessibilityIdentifier("auth.restore.retry")
                    Text("auth.restore.explanation", tableName: "SessionRestorationRetry")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onDisappear { cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
    }
    private func cancel() {
        task?.cancel(); task = nil
        if let attempt { session.cancelSessionRestorationRetry(attempt) }
        attempt = nil
    }
}

/// Re-reading a scoped Keychain item does not alter its access controls or prompt
/// for new authority. Malformed/missing credentials and configuration stay closed.
enum SessionRestorationRetryPolicy {
    static func permits(_ error: Error) -> Bool {
        if error is CancellationError || error is URLError { return true }
        if let storage = error as? KeychainTokenStore.StoreError {
            if case .status = storage { return true }
            return false
        }
        if let api = error as? APIError, case .httpStatus(let status) = api {
            return status == 408 || status == 429 || (500...599).contains(status)
        }
        return false
    }
}
