import Foundation

struct NativeEnrollmentAcceptance {
    var enabled = false
    var keyCreationEnabled = false
    var revocationEnabled = false
    var appID = ""
    var environment = "production"
    var signingAndDistributionReviewed = false
    var isValid: Bool {
        enabled && signingAndDistributionReviewed && environment == "production" && appID.count <= 255 &&
        appID.range(of: "^[A-Za-z0-9]+\\.[A-Za-z0-9.-]+$", options: .regularExpression) != nil
    }
    var requiredPaths: Set<String> {
        guard enabled else { return [] }
        var result: Set<String> = [NativeEnrollmentService.statusPath]
        if keyCreationEnabled { result.formUnion([NativeEnrollmentService.challengePath, NativeEnrollmentService.enrollPath]) }
        if revocationEnabled { result.insert(NativeEnrollmentService.revokePath) }
        return result
    }
}
@MainActor enum NativeEnrollmentComposition {
    static func make(owner: PlayExperienceSession, api: APIConfiguration, transport: any HTTPTransport,
                     approval: NativePlatformAcceptance, current: @escaping () -> PlayExperienceSession?) -> NativeEnrollmentCoordinator? {
        guard approval.validPurpose, let policy = approval.enrollment, policy.isValid,
              let scope = try? NativeEnrollmentScope(namespace: owner.namespace, accountID: owner.accountID, appID: policy.appID, environment: policy.environment) else { return nil }
        let service = NativeEnrollmentService(api: api, transport: transport, scope: scope, owner: owner,
            enabled: policy.enabled, enrollmentEnabled: policy.keyCreationEnabled, revocationEnabled: policy.revocationEnabled, current: current)
        return NativeEnrollmentCoordinator(scope: scope, store: NativeEnrollmentKeychainStore(), service: service,
            device: AppleEnrollmentDeviceProvider(enabled: policy.keyCreationEnabled), enabled: policy.enabled,
            creationAllowed: policy.keyCreationEnabled, revocationAllowed: policy.revocationEnabled, current: { current() == owner })
    }
}

/// A freshly read ACTIVE server binding selects the stored opaque key handle.
/// Local journal state alone never authorizes a step assertion.
@MainActor final class EnrolledNativeStepAssertionProvider: NativeStepAssertionProviding {
    private let enrollment: NativeEnrollmentCoordinator
    private let enabled: Bool
    private var provider: AppAttestStepAssertionProvider?
    init(enrollment: NativeEnrollmentCoordinator, enabled: Bool = false) { self.enrollment = enrollment; self.enabled = enabled }
    var deviceKeyID: String { enrollment.activeKeyID ?? "" }
    var supported: Bool {
        guard enabled, !deviceKeyID.isEmpty else { return false }
        return AppAttestStepAssertionProvider(deviceKeyID: deviceKeyID, enabled: true).supported
    }
    func assertion(clientData: Data) async throws -> String {
        guard supported else { throw NativePlatformIssue.disabled }
        let key = deviceKeyID
        let provider = AppAttestStepAssertionProvider(deviceKeyID: key, enabled: true); self.provider = provider
        let result = try await provider.assertion(clientData: clientData)
        guard enrollment.activeKeyID == key else { throw NativePlatformIssue.staleSession }; return result
    }
    func cancel() { provider?.cancel(); provider = nil }
}
