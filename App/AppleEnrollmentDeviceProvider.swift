import Foundation
import CryptoKit
import DeviceCheck
import UIKit

/// DeviceCheck owns key material. Only its opaque handle and returned attestation
/// travel through this interface. No key export, Keychain private-key lookup,
/// App Attest entitlement installation, or development-environment fallback.
@MainActor final class AppleEnrollmentDeviceProvider: NativeEnrollmentDeviceProviding {
    private let enabled: Bool
    private let service: DCAppAttestService
    private var busy = false
    init(enabled: Bool = false, service: DCAppAttestService = .shared) { self.enabled = enabled; self.service = service }
    var supported: Bool { enabled && UIDevice.current.userInterfaceIdiom == .phone && service.isSupported }
    func generateKey() async throws -> String {
        guard supported, !busy else { throw NativeEnrollmentIssue.unsupported }
        busy = true; defer { busy = false }
        return try await withCheckedThrowingContinuation { continuation in
            service.generateKey { key, error in
                if let key, NativeEnrollmentWire.validKey(key) { continuation.resume(returning: key) }
                else { continuation.resume(throwing: error ?? NativeEnrollmentIssue.invalidContract) }
            }
        }
    }
    static func clientDataHash(challengeBytes: Data) throws -> Data {
        guard challengeBytes.count == 32 else { throw NativeEnrollmentIssue.invalidContract }
        return Data(SHA256.hash(data: challengeBytes))
    }
    func attest(key: String, challengeBytes: Data) async throws -> String {
        guard supported, !busy, NativeEnrollmentWire.validKey(key) else { throw NativeEnrollmentIssue.unsupported }
        let hash = try Self.clientDataHash(challengeBytes: challengeBytes)
        busy = true; defer { busy = false }
        return try await withCheckedThrowingContinuation { continuation in
            service.attestKey(key, clientDataHash: hash) { data, error in
                if let data, (1...65_536).contains(data.count) { continuation.resume(returning: data.base64EncodedString()) }
                else { continuation.resume(throwing: error ?? NativeEnrollmentIssue.invalidContract) }
            }
        }
    }
    func cancel() {
        // DeviceCheck provides no cancellation API. Do not discard a late opaque
        // handle/proof: the coordinator journals it to the original account and
        // fences every subsequent request. Nothing else is started here.
    }
}
