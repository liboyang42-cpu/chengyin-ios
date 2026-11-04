import Foundation

/// Retain one reader for one existing runtime context. Construction does not grant
/// endpoint access: L2/L1 must supply the already-gated transport, or leave service nil.
/// This reader neither adopts another account nor persists or exposes credentials.
@MainActor public final class RegistrationSupplementalSessionReader {
    private let service: RegistrationSupplementalReadService?
    private let captured: RuntimeDependencyContext?
    private let current: () -> RuntimeDependencyContext?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void

    public init(service: RegistrationSupplementalReadService?, captured: RuntimeDependencyContext?,
                current: @escaping () -> RuntimeDependencyContext?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.service = service
        self.captured = captured
        self.current = current
        self.onUnauthorized = onUnauthorized
    }

    public func paymentReadiness() async throws -> RegistrationPaymentReadinessSnapshot {
        try await read { service, context in
            try await service.paymentReadiness(token: context.session.token)
        }
    }

    public func joinedRegistration() async throws -> OrderLifecycleDetail? {
        try await read { service, context in
            try await service.joinedRegistration(accountID: context.session.accountID, token: context.session.token)
        }
    }

    public func countsByDate(scope: RegistrationCountScope) async throws -> [RegistrationDailyCount] {
        try await read { service, context in
            try await service.countsByDate(scope: scope, token: context.session.token)
        }
    }

    private func check() throws -> (RegistrationSupplementalReadService, RuntimeDependencyContext) {
        try Task.checkCancellation()
        guard let captured else { throw APIError.unauthorized }
        guard current() == captured else { throw CancellationError() }
        guard let service, service.configuration.baseURL == captured.baseURL else { throw APIError.notConfigured }
        return (service, captured)
    }

    private func read<Value>(_ operation: (RegistrationSupplementalReadService, RuntimeDependencyContext) async throws -> Value) async throws -> Value {
        let (service, context) = try check()
        do {
            let value = try await operation(service, context)
            _ = try check()
            return value
        } catch {
            // Recheck failure responses too; an old 401 cannot expire a replacement login.
            _ = try check()
            if error as? APIError == .unauthorized { onUnauthorized(context) }
            throw error
        }
    }
}
