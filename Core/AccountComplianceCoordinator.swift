import Foundation

public enum ComplianceStep: Equatable { case idle, notice, blocked, verify, review, pending, freshLogin, unknown }
public enum ComplianceRoamCleanup: Equatable { case idle, serverConfirmed, trackingStopped, complete }
public struct ComplianceState {
    public var step: ComplianceStep = .idle
    public var status: ComplianceDeregistration?
    public var marketing: [ComplianceMarketingConsent] = []
    public var busy = false
    public var smsSent = false
    public var error: String?
    public var roamCleanup: ComplianceRoamCleanup = .idle
    public init() {}
}
/// Inject existing roam controller/privacy store; ordering is server readback -> stop -> clear.
@MainActor public protocol ComplianceRoamEffects: AnyObject {
    func stopTracking() async throws
    func clearMapPrivacy() async throws
    func invalidateMapPrivacyCaches()
}
@MainActor public final class AccountComplianceCoordinator {
    public private(set) var state = ComplianceState()
    public var onChange: ((ComplianceState) -> Void)?
    private let service: AccountComplianceService
    private let auth: any AuthChannelServing
    private let effects: any ComplianceRoamEffects
    private let current: () -> ComplianceSession?
    private let invalidateSession: (ComplianceSession) async -> Void
    private var generation: UInt64 = 0
    private var noticeAccepted = false
    private var requestID = UUID().uuidString
    private var reviewCode: String? // In memory only; cleared on apply, invalidation and failed SMS.
    private var retainedNPCChatData: NPCChatDataCoordinator?
    public init(service: AccountComplianceService, auth: any AuthChannelServing, effects: any ComplianceRoamEffects,
                current: @escaping () -> ComplianceSession?, invalidateSession: @escaping (ComplianceSession) async -> Void) {
        self.service = service; self.auth = auth; self.effects = effects; self.current = current; self.invalidateSession = invalidateSession
    }
    public func invalidate() { retainedNPCChatData?.invalidate(); retainedNPCChatData = nil; generation &+= 1; state = .init(); noticeAccepted = false; reviewCode = nil; requestID = UUID().uuidString; onChange?(state) }
    public func makeNPCChatDataCoordinator() -> NPCChatDataCoordinator {
        retainedNPCChatData?.invalidate()
        let value = NPCChatDataCoordinator(current: current, available: { [weak self] session in
            self?.service.canReadNPCChatData(session: session) == true
        }, read: { [weak self] session in
            guard let self else { throw NPCChatDataFailure.staleSession }
            return try await self.service.readNPCChatData(session: session)
        })
        retainedNPCChatData = value; return value
    }
    private func changed() { onChange?(state) }
    private func run(_ action: (ComplianceSession, UInt64) async throws -> Void) async {
        guard !state.busy, let session = current(), session.valid else { return }
        let stamp = generation; state.busy = true; state.error = nil; changed()
        do { try await action(session, stamp) }
        catch {
            guard current() == session, generation == stamp else { return }
            if case ComplianceFailure.rejected(let message) = error { state.error = message }
            else if error as? ComplianceFailure == .unavailable { state.error = "compliance.unavailable" }
            else if error as? ComplianceFailure == .unresolved || error as? ComplianceFailure == .readbackMismatch { state.error = "compliance.unknown" }
            else { state.error = "compliance.failed" }
        }
        guard current() == session, generation == stamp else { return }
        state.busy = false; changed()
    }
    private func fence(_ session: ComplianceSession, _ stamp: UInt64) throws {
        guard generation == stamp, current() == session else { throw ComplianceFailure.staleSession }
        try service.check(session)
    }
    public func load() async {
        await run { session, stamp in
            let result = try await self.service.status(session: session); try self.fence(session, stamp)
            self.state.status = result
            let unresolved = try self.service.unresolved("deregister", session: session)
            self.state.step = unresolved != nil && !result.pending ? .unknown : result.pending ? .pending : result.blocked ? .blocked : result.status == "NORMAL" ? .notice : .unknown
        }
    }
    public func precheckAndAgree(documentRead: Bool, explicitAgreement: Bool) async {
        guard documentRead, explicitAgreement, state.step == .notice || state.step == .blocked else { return }
        await run { session, stamp in
            let result = try await self.service.precheck(session: session); try self.fence(session, stamp)
            self.state.status = result
            guard result.eligible else { self.state.step = result.blocked ? .blocked : .unknown; return }
            _ = try await self.service.consent(.cancellation, event: .agree, requestID: self.requestID, session: session)
            try self.fence(session, stamp); self.noticeAccepted = true; self.state.step = .verify
        }
    }
    public func sendSMS(phone: String, explicitlyRequested: Bool) async {
        guard explicitlyRequested, noticeAccepted, state.step == .verify else { return }
        await run { session, stamp in
            self.state.smsSent = false; self.reviewCode = nil
            try self.service.check(session)
            try await self.auth.sendSMSCode(phone: AuthChannelInput.phone(phone))
            try self.fence(session, stamp); self.state.smsSent = true
        }
    }
    public func prepareReview(code: String) {
        guard !state.busy, noticeAccepted, state.smsSent, state.step == .verify else { return }
        do { reviewCode = try AuthChannelInput.code(code); state.step = .review; state.error = nil }
        catch { state.error = "compliance.codeRequired" }; changed()
    }
    public func backToVerification() { guard !state.busy else { return }; reviewCode = nil; state.step = .verify; changed() }
    public func apply(explicitlyConfirmed: Bool) async {
        guard explicitlyConfirmed, noticeAccepted, state.smsSent, state.step == .review, let code = reviewCode else { return }
        reviewCode = nil
        await run { session, stamp in
            do {
                let result = try await self.service.apply(smscode: code, requestID: self.requestID, session: session)
                try self.fence(session, stamp); self.state.status = result
                if result.blocked { self.state.step = .blocked; self.noticeAccepted = false; self.state.smsSent = false }
                else {
                    self.state.step = .freshLogin; self.state.busy = false; self.state.smsSent = false; self.noticeAccepted = false; self.changed()
                    // Host callback MUST compare this session before touching the existing auth controller.
                    await self.invalidateSession(session)
                }
            } catch {
                try self.fence(session, stamp)
                if try self.service.unresolved("deregister", session: session) != nil { self.state.step = .unknown }
                else { self.state.step = .verify }
                throw error
            }
        }
    }
    public func cancel(explicitlyConfirmed: Bool) async {
        guard explicitlyConfirmed, state.step == .pending else { return }
        await run { session, stamp in
            let result = try await self.service.cancel(session: session); try self.fence(session, stamp)
            self.state.status = result; self.state.step = .notice; self.noticeAccepted = false
            self.state.smsSent = false; self.requestID = UUID().uuidString
        }
    }
    public func loadMarketing() async {
        await run { session, stamp in
            let rows = try await self.service.marketing(session: session); try self.fence(session, stamp); self.state.marketing = rows
        }
    }
    public func setMarketing(_ row: ComplianceMarketingConsent, channel: ComplianceMarketingChannel, optedIn: Bool) async {
        await run { session, stamp in
            let rows = try await self.service.setMarketing(row, channel: channel, optedIn: optedIn, requestID: UUID().uuidString, session: session)
            try self.fence(session, stamp); self.state.marketing = rows // Never optimistic.
        }
    }
    public func revokeRoam(explicitlyConfirmed: Bool) async {
        guard explicitlyConfirmed else { return }
        await run { session, stamp in
            if self.state.roamCleanup == .idle {
                if try self.service.unresolved(ComplianceSubject.roamLocation.operation, session: session) != nil {
                    _ = try await self.service.reconcileConsent(.roamLocation, event: .revoke, session: session)
                } else if let latest = try await self.service.latest(.roamLocation, session: session), latest.matches(.roamLocation, event: .revoke) {
                    // After relaunch, resume local effects from authoritative consent without a duplicate write.
                } else { _ = try await self.service.consent(.roamLocation, event: .revoke, requestID: UUID().uuidString, session: session) }
                try self.fence(session, stamp); self.state.roamCleanup = .serverConfirmed
            }
            if self.state.roamCleanup == .serverConfirmed {
                try await self.effects.stopTracking(); try self.fence(session, stamp); self.state.roamCleanup = .trackingStopped
            }
            if self.state.roamCleanup == .trackingStopped {
                do { try await self.effects.clearMapPrivacy(); try self.fence(session, stamp) }
                catch { try self.fence(session, stamp); self.effects.invalidateMapPrivacyCaches(); throw error }
                self.effects.invalidateMapPrivacyCaches(); self.state.roamCleanup = .complete
            }
        }
    }
}
