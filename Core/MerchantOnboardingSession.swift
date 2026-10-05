import Foundation

/// Credentials never enter form state, logs or persistence. Epoch changes on every login/logout.
public struct MerchantOnboardingSession: Equatable {
    public let identity: ProfileReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}

@MainActor
public protocol MerchantOnboardingServing: AnyObject {
    var isConfigured: Bool { get }
    var identity: ProfileReadIdentity? { get }
    func application(expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingSnapshot
    func identityRegistered(expectedIdentity: ProfileReadIdentity) async throws -> Bool
    func uploadLicense(_ image: MerchantOnboardingImage, expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingLicense
    func submit(_ draft: MerchantOnboardingDraft, expectedIdentity: ProfileReadIdentity) async throws
}

@MainActor
public final class MerchantOnboardingSessionAdapter: MerchantOnboardingServing {
    private let service: MerchantOnboardingService?
    private let currentSession: () -> MerchantOnboardingSession?
    private let onUnauthorized: (MerchantOnboardingSession) -> Void
    public var isConfigured: Bool { service != nil }
    public var identity: ProfileReadIdentity? { currentSession()?.identity }
    public init(service: MerchantOnboardingService?, currentSession: @escaping () -> MerchantOnboardingSession?,
                onUnauthorized: @escaping (MerchantOnboardingSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func application(expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingSnapshot {
        try await read(expectedIdentity) { service, token in try await service.application(token: token) }
    }
    public func identityRegistered(expectedIdentity: ProfileReadIdentity) async throws -> Bool {
        try await read(expectedIdentity) { service, token in try await service.identityRegistered(token: token) }
    }
    public func uploadLicense(_ image: MerchantOnboardingImage, expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingLicense {
        try await write(expectedIdentity) { service, token in try await service.uploadLicense(image, token: token) }
    }
    public func submit(_ draft: MerchantOnboardingDraft, expectedIdentity: ProfileReadIdentity) async throws {
        try await write(expectedIdentity) { service, token in try await service.submit(draft, token: token) }
    }
    private func read<Value>(_ expected: ProfileReadIdentity,
                             operation: (MerchantOnboardingService, String) async throws -> Value) async throws -> Value {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = currentSession(), snapshot.identity == expected else { throw APIError.unauthorized }
        try Task.checkCancellation()
        do {
            let value = try await operation(service, snapshot.token)
            guard !Task.isCancelled, currentSession() == snapshot else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentSession() == snapshot else { throw CancellationError() }
            if error as? APIError == .unauthorized || (error as? MerchantOnboardingFailure)?.isUnauthorized == true {
                onUnauthorized(snapshot)
            }
            throw error
        }
    }
    private func write<Value>(_ expected: ProfileReadIdentity,
                              operation: (MerchantOnboardingService, String) async throws -> Value) async throws -> Value {
        guard let service, let snapshot = currentSession(), snapshot.identity == expected,
              !Task.isCancelled else { throw MerchantOnboardingWriteError.notSent }
        do {
            let value = try await operation(service, snapshot.token)
            guard !Task.isCancelled, currentSession() == snapshot else { throw MerchantOnboardingWriteError.outcomeUnknown }
            return value
        } catch {
            guard currentSession() == snapshot else { throw MerchantOnboardingWriteError.outcomeUnknown }
            if let writeError = error as? MerchantOnboardingWriteError,
               case .rejected(let failure) = writeError, failure.isUnauthorized {
                onUnauthorized(snapshot)
            }
            throw error
        }
    }
}
