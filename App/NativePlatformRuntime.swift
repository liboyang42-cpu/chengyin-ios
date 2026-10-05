import SwiftUI
import CryptoKit

/// Independent release/legal acceptance, never inferred from an OS permission,
/// API response, Info.plist flag or language. Shipped dependency remains nil.
struct NativePlatformAcceptance {
    var enrollment: NativeEnrollmentAcceptance? = nil
    var stepsEnabled = false
    var localRemindersEnabled = false
    var purposeVersion: String = ""
    var legalReviewed = false
    var privacyNoticeURL: URL?
    var enrolledAppAttestKeyID: String?
    var validPurpose: Bool {
        legalReviewed && !purposeVersion.isEmpty && privacyNoticeURL?.scheme == "https" && privacyNoticeURL?.host?.isEmpty == false
    }
}
private struct NativePlatformRuntimeKey: EnvironmentKey { static let defaultValue: NativePlatformRuntime? = nil }
extension EnvironmentValues {
    var nativePlatformRuntime: NativePlatformRuntime? {
        get { self[NativePlatformRuntimeKey.self] }
        set { self[NativePlatformRuntimeKey.self] = newValue }
    }
}

/// Session-owned runtime installed at the ordinary journey host. SwiftUI's
/// environment carries it through both navigation and chapter-inline bodies.
@MainActor final class NativePlatformRuntime {
    let enrollment: NativeEnrollmentCoordinator?
    let owner: PlayExperienceSession
    let ownerKey: String
    let acceptance: NativePlatformAcceptance
    let service: any NativePlatformServing
    private let current: () -> PlayExperienceSession?
    private let makePedometer: () -> any NativePedometerProviding
    private let assertion: any NativeStepAssertionProviding
    private let reminders: any NativeLocalReminderProviding
    private var steps: [Int: NativeStepCoordinator] = [:]
    private var windows: [String: NativeLocalReminderCoordinator] = [:]
    private var windowScopes: [String: (Int, Int, Int)] = [:]
    init(owner: PlayExperienceSession, acceptance: NativePlatformAcceptance, service: any NativePlatformServing,
         current: @escaping () -> PlayExperienceSession?,
         makePedometer: @escaping () -> any NativePedometerProviding,
         assertion: any NativeStepAssertionProviding, reminders: any NativeLocalReminderProviding, enrollment: NativeEnrollmentCoordinator? = nil) {
        self.owner = owner; self.acceptance = acceptance; self.service = service; self.current = current
        self.makePedometer = makePedometer; self.reminders = reminders; self.enrollment = enrollment
        if let enrollment { self.assertion = EnrolledNativeStepAssertionProvider(enrollment: enrollment, enabled: acceptance.stepsEnabled) }
        else { self.assertion = assertion }
        ownerKey = SHA256.hash(data: Data("\(owner.namespace)|\(owner.accountID)|\(owner.epoch)|\(owner.token)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var isCurrent: Bool { current() == owner }
    func stepModel(for sessionID: Int) -> NativeStepCoordinator? {
        guard isCurrent, acceptance.validPurpose, acceptance.stepsEnabled else { return nil }
        if let value = steps[sessionID] { return value }
        let value = NativeStepCoordinator(owner: owner, service: service, pedometer: makePedometer(), assertion: assertion, current: current)
        steps[sessionID] = value; return value
    }
    func reminderModel(activityID: Int, topicID: Int, nodeID: Int) -> NativeLocalReminderCoordinator? {
        guard isCurrent, acceptance.validPurpose, acceptance.localRemindersEnabled,
              activityID >= 0, topicID > 0, nodeID > 0 else { return nil }
        let scope = "\(activityID).\(topicID).\(nodeID)"
        windowScopes[scope] = (activityID, topicID, nodeID)
        if let value = windows[scope] { return value }
        let id = AppleLocalReminderProvider.prefix + ownerKey + "." + scope
        let value = NativeLocalReminderCoordinator(identifier: id, owner: ownerKey, provider: reminders, current: { [weak self] in self?.isCurrent == true })
        windows[scope] = value; return value
    }
    func suspendMotion() { enrollment?.suspend(); steps.values.forEach { $0.interrupt() } }
    func clockChanged() {
        steps.values.forEach { $0.interrupt(.clockChanged) }
        windows.values.forEach { $0.clockChanged() }
        reminders.cancelAllOwned(owner: ownerKey)
    }
    func invalidate() {
        enrollment?.invalidate()
        steps.values.forEach { $0.invalidate() }; steps.removeAll()
        windows.values.forEach { $0.invalidate() }; windows.removeAll(); windowScopes.removeAll()
        assertion.cancel(); reminders.cancelAllOwned(owner: ownerKey)
    }
    /// Runs on foreground without asking for permission; removes stale requests
    /// restored from another authenticated owner/epoch after process restart.
    func reconcileOwnedRequests() async {
        let pending = await reminders.pending()
        guard isCurrent else { return }
        for item in pending where item.owner != ownerKey { reminders.cancel(identifier: item.identifier) }
        for (id, scope) in windowScopes {
            guard isCurrent else { return }
            let fresh = try? await service.timeWindow(activityID: scope.0, topicID: scope.1, nodeID: scope.2)
            guard isCurrent else { return }
            await windows[id]?.refresh(fresh)
        }
    }
}
