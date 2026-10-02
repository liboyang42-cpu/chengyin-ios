import Foundation
import CryptoKit
import DeviceCheck
import UIKit

/// Uses only an already-enrolled, account-bound key supplied by accepted runtime
/// composition. No key creation, enrollment, credentials, or production verifier
/// is introduced. App integrity does not cryptographically prove a person walked.
@MainActor final class AppAttestStepAssertionProvider: NativeStepAssertionProviding {
    let deviceKeyID: String
    private let enabled: Bool
    private let service: DCAppAttestService
    private var generation = UUID()
    private var pending: CheckedContinuation<String, Error>?
    init(deviceKeyID: String = "", enabled: Bool = false, service: DCAppAttestService = .shared) {
        self.deviceKeyID = deviceKeyID; self.enabled = enabled; self.service = service
    }
    var supported: Bool { enabled && !deviceKeyID.isEmpty && UIDevice.current.userInterfaceIdiom == .phone && service.isSupported }
    func assertion(clientData: Data) async throws -> String {
        guard supported, !clientData.isEmpty, pending == nil else { throw NativePlatformIssue.unsupported }
        let token = generation
        let hash = Data(SHA256.hash(data: clientData))
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                service.generateAssertion(deviceKeyID, clientDataHash: hash) { [weak self] data, error in
                    Task { @MainActor in
                        guard let self, self.generation == token, let continuation = self.pending else { return }
                        self.pending = nil
                        if let error { continuation.resume(throwing: error) }
                        else if let data, !data.isEmpty { continuation.resume(returning: data.base64EncodedString()) }
                        else { continuation.resume(throwing: NativePlatformIssue.invalidContract) }
                    }
                }
            }
        }, onCancel: { [weak self] in Task { @MainActor in self?.cancel() } })
    }
    func cancel() { generation = UUID(); pending?.resume(throwing: NativePlatformIssue.interrupted); pending = nil }
}
