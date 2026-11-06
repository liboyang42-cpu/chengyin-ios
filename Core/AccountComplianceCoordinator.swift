import Foundation

public enum ComplianceStep: Equatable { case idle, notice, blocked, verify, verificationUnavailable, review, pending, completed, freshLogin, unknown }
public enum ComplianceRoamCleanup: Equatable { case idle, serverConfirmed, trackingStopped, complete }
public struct ComplianceState {
    public var step: ComplianceStep = .idle
    public var status: ComplianceDeregistration?
    public var localCancellationConsent: AccountDeregistrationConsentReadState = .unread
    public var originalApplication: AccountDeregistrationOriginalReceipt?
    public var originalApplicationRequestID: String?
    public var marketing: [ComplianceMarketingConsent] = []
    public var marketingUnresolved: Set<String> = []
    public var marketingLoaded = false
    public var marketingCurrentConfirmed = false
    public var marketingOriginalResults: [MerchantMarketingConsentOriginalReceipt] = []
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
/// Original screen and queued intent identity, not an approval or a persisted request.
public struct AccountDeregistrationPresentation: Equatable {
    fileprivate let id = UUID()
    fileprivate let session: ComplianceSession?
    fileprivate let issuance: UUID?
}
public struct AccountDeregistrationIntent {
    fileprivate let generation: UInt64
    fileprivate let session: ComplianceSession
    fileprivate let issuance: UUID?
}
public struct AccountMarketingPresentation: Equatable {
    fileprivate let id = UUID()
    fileprivate let session: ComplianceSession?
    fileprivate let issuance: UUID?
}
public struct AccountMarketingReadIntent {
    fileprivate let generation: UInt64
    fileprivate let session: ComplianceSession
    fileprivate let issuance: UUID?
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
    private var marketingPresentation: AccountMarketingPresentation?
    private var marketingPresentationActive = false
    private var marketingRunning = false
    private var marketingSession: ComplianceSession?
    private var marketingRevision = UUID()
    public var marketingOriginalRevision: UUID? { service.marketingOriginalRevision }
    private var deregistrationPresentation: AccountDeregistrationPresentation?
    private var deregistrationPresentationActive = false
    public var deregistrationOriginalRevision: UUID? { service.deregistrationOriginalRevision }
    private var reviewSession: ComplianceSession?
    private var reviewIssuance: UUID?
    private var noticeAccepted = false
    private var requestID = UUID().uuidString.lowercased()
    private var reviewCode: String? // In memory only; cleared on apply, invalidation and failed SMS.
    private var retainedNPCChatData: NPCChatDataCoordinator?
    /// Dormant: nil keeps NPC log deletion OFF; the service also needs its own endpoint approval.
    public var npcChatLogDeletion: NPCChatLogDeletionService?
    public init(service: AccountComplianceService, auth: any AuthChannelServing, effects: any ComplianceRoamEffects,
                current: @escaping () -> ComplianceSession?, invalidateSession: @escaping (ComplianceSession) async -> Void) {
        self.service = service; self.auth = auth; self.effects = effects; self.current = current; self.invalidateSession = invalidateSession
    }
    public func invalidate() { marketingPresentation = nil; marketingPresentationActive = false; marketingRunning = false; marketingSession = nil; marketingRevision = UUID(); deregistrationPresentation = nil; deregistrationPresentationActive = false; retainedNPCChatData?.invalidate(); retainedNPCChatData = nil; generation &+= 1; state = .init(); noticeAccepted = false; reviewSession = nil; reviewIssuance = nil; reviewCode = nil; requestID = UUID().uuidString.lowercased(); onChange?(state) }
    public func beginDeregistrationPresentation() -> AccountDeregistrationPresentation {
        invalidate()
        let value = AccountDeregistrationPresentation(session: current(), issuance: service.deregistrationOriginalRevision)
        deregistrationPresentation = value; deregistrationPresentationActive = true
        return value
    }
    public func ownsDeregistrationPresentation(_ value: AccountDeregistrationPresentation) -> Bool {
        deregistrationPresentation == value && deregistrationPresentationActive &&
            current() == value.session && service.deregistrationOriginalRevision == value.issuance
    }
    public func pauseDeregistrationPresentation(_ value: AccountDeregistrationPresentation) {
        guard deregistrationPresentation == value else { return }
        invalidate(); deregistrationPresentation = value
    }
    public func resumeDeregistrationPresentation(_ value: AccountDeregistrationPresentation) -> Bool {
        guard deregistrationPresentation == value, current() == value.session,
              service.deregistrationOriginalRevision == value.issuance else { return false }
        deregistrationPresentationActive = true; return true
    }
    public func captureDeregistrationIntent(_ value: AccountDeregistrationPresentation) -> AccountDeregistrationIntent? {
        guard ownsDeregistrationPresentation(value), let session = current(), session.valid else { return nil }
        return AccountDeregistrationIntent(generation: generation, session: session, issuance: service.deregistrationOriginalRevision)
    }
    public func isCurrentDeregistrationIntent(_ intent: AccountDeregistrationIntent) -> Bool {
        !Task.isCancelled && generation == intent.generation && current() == intent.session &&
            service.deregistrationOriginalRevision == intent.issuance
    }
    private func acceptsDeregistrationIntent(_ intent: AccountDeregistrationIntent?) -> Bool {
        !Task.isCancelled && (intent.map(isCurrentDeregistrationIntent) ?? true)
    }
    public func beginMarketingPresentation() -> AccountMarketingPresentation {
        invalidate() // The shared coordinator has one current screen owner, across destinations.
        let value = AccountMarketingPresentation(session: current(), issuance: service.marketingOriginalRevision)
        marketingPresentation = value; marketingPresentationActive = true; return value
    }
    public func ownsMarketingPresentation(_ value: AccountMarketingPresentation) -> Bool {
        marketingPresentation == value && marketingPresentationActive && current() == value.session &&
            service.marketingOriginalRevision == value.issuance
    }
    public func pauseMarketingPresentation(_ value: AccountMarketingPresentation) {
        guard marketingPresentation == value else { return }
        invalidate(); marketingPresentation = value
    }
    public func resumeMarketingPresentation(_ value: AccountMarketingPresentation) -> Bool {
        guard marketingPresentation == value, current() == value.session,
              service.marketingOriginalRevision == value.issuance else { return false }
        marketingPresentationActive = true; return true
    }
    public func captureMarketingRead(_ value: AccountMarketingPresentation) -> AccountMarketingReadIntent? {
        guard ownsMarketingPresentation(value), let session = current(), session.valid else { return nil }
        return AccountMarketingReadIntent(generation: generation, session: session, issuance: service.marketingOriginalRevision)
    }
    public func isCurrentMarketingRead(_ intent: AccountMarketingReadIntent) -> Bool {
        !Task.isCancelled && generation == intent.generation && current() == intent.session &&
            service.marketingOriginalRevision == intent.issuance
    }
    /// Revoking marketing authority must retire its screen without cancelling a new C08 owner.
    public func retireMarketingSource() {
        guard marketingPresentation != nil || marketingRunning || marketingSession != nil else { return }
        invalidate()
    }
    public func makeNPCChatDataCoordinator() -> NPCChatDataCoordinator {
        retainedNPCChatData?.invalidate()
        var deleteLogs: ((ComplianceSession) async throws -> NPCChatLogDeletionOutcome)?
        if npcChatLogDeletion != nil {
            deleteLogs = { [weak self] session in
                guard let deletion = self?.npcChatLogDeletion else { throw NPCChatDataFailure.unavailable }
                return try await deletion.delete(session: session)
            }
        }
        let value = NPCChatDataCoordinator(current: current, available: { [weak self] session in
            self?.service.canReadNPCChatData(session: session) == true
        }, read: { [weak self] session in
            guard let self else { throw NPCChatDataFailure.staleSession }
            return try await self.service.readNPCChatData(session: session)
        }, deletionAvailable: { [weak self] session in
            self?.npcChatLogDeletion?.canDelete(session: session) == true
        }, deleteLogs: deleteLogs)
        retainedNPCChatData = value; return value
    }
    private func changed() { onChange?(state) }
    private func run(deregistration: Bool = false, _ action: (ComplianceSession, UInt64) async throws -> Void) async {
        guard (!deregistration || !Task.isCancelled), !state.busy, let session = current(), session.valid else { return }
        let stamp = generation; let issuance = service.deregistrationOriginalRevision
        state.busy = true; state.error = nil; changed()
        do { try await action(session, stamp) }
        catch {
            if deregistration, generation == stamp, current() != session { invalidate(); return }
            guard current() == session, generation == stamp else { return }
            if deregistration, error as? ComplianceFailure == .staleSession { invalidate(); return }
            guard !deregistration || service.deregistrationOriginalRevision == issuance else { invalidate(); return }
            if deregistration {
                state.localCancellationConsent = (try? service.readDeregistrationConsent(session: session)) ?? .unread
                if !state.localCancellationConsent.allowsNewConsent {
                    noticeAccepted = false; state.smsSent = false; reviewCode = nil; reviewSession = nil
                }
            }
            if deregistration && (error as? APIError == .unauthorized || error as? MerchantBusinessFailure == .denied) {
                state.status = nil; state.originalApplication = nil; reviewCode = nil; reviewSession = nil
                noticeAccepted = false; state.smsSent = false; state.step = .unknown; state.localCancellationConsent = .unread
            }
            if case ComplianceFailure.rejected(let message) = error { state.error = message }
            else if error as? ComplianceFailure == .unavailable { state.error = "compliance.unavailable" }
            else if error as? ComplianceFailure == .unresolved || error as? ComplianceFailure == .readbackMismatch { state.error = "compliance.unknown" }
            else { state.error = "compliance.failed" }
        }
        if deregistration, generation == stamp, current() != session { invalidate(); return }
        guard current() == session, generation == stamp else { return }
        guard !deregistration || service.deregistrationOriginalRevision == issuance else { invalidate(); return }
        state.busy = false; changed()
    }
    private func runMarketing(_ action: (ComplianceSession, UInt64) async throws -> Void) async {
        guard !Task.isCancelled, !state.busy, let session = current(), session.valid else { return }
        let stamp = generation, issuance = service.marketingOriginalRevision
        marketingRunning = true; state.busy = true; state.error = nil; changed()
        do { try await action(session, stamp) }
        catch {
            guard generation == stamp else { return }
            guard current() == session, service.marketingOriginalRevision == issuance,
                  !(error is CancellationError), error as? ComplianceFailure != .staleSession else { invalidate(); return }
            if error as? APIError == .unauthorized || error as? MerchantBusinessFailure == .denied {
                state.marketing = []; state.marketingLoaded = false; state.marketingOriginalResults = []
                state.marketingUnresolved = []; marketingSession = nil; marketingRevision = UUID()
            }
            if case ComplianceFailure.rejected(let message) = error { state.error = message }
            else if error as? ComplianceFailure == .unavailable { state.error = "compliance.unavailable" }
            else if error as? ComplianceFailure == .unresolved || error as? ComplianceFailure == .readbackMismatch { state.error = "compliance.unknown" }
            else { state.error = "compliance.failed" }
        }
        guard generation == stamp else { return }
        guard current() == session, service.marketingOriginalRevision == issuance, !Task.isCancelled else { invalidate(); return }
        marketingRunning = false; state.busy = false; changed()
    }
    private func marketingFence(_ session: ComplianceSession, _ stamp: UInt64, issuance: UUID?) throws {
        try fence(session, stamp)
        guard service.marketingOriginalRevision == issuance else { throw ComplianceFailure.staleSession }
    }
    private func fence(_ session: ComplianceSession, _ stamp: UInt64) throws {
        guard generation == stamp, current() == session else { throw ComplianceFailure.staleSession }
        try service.check(session)
    }
    private func deregistrationFence(_ session: ComplianceSession, _ stamp: UInt64, issuance: UUID?) throws {
        try fence(session, stamp)
        guard service.deregistrationOriginalRevision == issuance else { throw ComplianceFailure.staleSession }
    }
    public func load(intent: AccountDeregistrationIntent? = nil) async {
        guard acceptsDeregistrationIntent(intent), !state.busy else { return }
        generation &+= 1
        reviewCode = nil; reviewSession = nil; reviewIssuance = nil; noticeAccepted = false; state.smsSent = false
        state.status = nil; state.originalApplication = nil; state.originalApplicationRequestID = nil; state.step = .unknown
        state.localCancellationConsent = .unread
        let issuance = service.deregistrationOriginalRevision
        await run(deregistration: true) { session, stamp in
            self.state.localCancellationConsent = try self.service.readDeregistrationConsent(session: session)
            self.changed()
            self.state.originalApplicationRequestID = try self.service.unresolved("deregister", session: session)?.requestID
            let original = try await self.service.recoverOriginalApplication(session: session,
                whileCurrent: { self.generation == stamp && self.current() == session })
            try self.deregistrationFence(session, stamp, issuance: issuance); self.state.originalApplication = original
            if let original, !original.settled { self.state.step = .unknown; return }
            if let original, original.settled && !original.accepted { self.requestID = UUID().uuidString.lowercased() }
            let result = try await self.service.recoverDeregistrationStatus(session: session,
                whileCurrent: { self.generation == stamp && self.current() == session }); try self.deregistrationFence(session, stamp, issuance: issuance)
            self.state.status = result
            let application = try self.service.unresolved("deregister", session: session)
            let cancellation = try self.service.unresolved("deregisterCancel", session: session)
            if cancellation != nil { self.state.step = .unknown }
            else if result.pending, application?.epoch == session.epoch { self.state.step = .freshLogin }
            else if result.completed { self.state.step = .completed }
            else if application != nil, !result.pending { self.state.step = .unknown }
            else { self.state.step = result.pending ? .pending : result.completed ? .completed : result.blocked ? .blocked : result.startable ? .notice : .unknown }
        }
    }
    public func precheckAndAgree(documentRead: Bool, explicitAgreement: Bool, expectedConsentVersion: String? = nil, intent: AccountDeregistrationIntent? = nil) async {
        guard acceptsDeregistrationIntent(intent), documentRead, explicitAgreement, state.localCancellationConsent.allowsNewConsent,
              state.step == .notice || state.step == .blocked else { return }
        let issuance = service.deregistrationOriginalRevision
        await run(deregistration: true) { session, stamp in
            self.state.localCancellationConsent = try self.service.readDeregistrationConsent(session: session)
            guard self.state.localCancellationConsent.allowsNewConsent else { throw ComplianceFailure.unresolved }
            let result = try await self.service.precheck(session: session); try self.deregistrationFence(session, stamp, issuance: issuance)
            self.state.status = result
            guard let impact = result.impact, impact.valid(for: session.accountID), impact.confirmable else { self.state.step = .blocked; return }
            guard result.eligible else { self.state.step = result.blocked ? .blocked : .unknown; return }
            // No consent is recorded when this device cannot complete the server's verification method.
            guard result.verificationAvailableOnThisDevice else { self.state.step = .verificationUnavailable; return }
            do {
                _ = try await self.service.consent(.cancellation, event: .agree, requestID: self.requestID, session: session,
                    expectedConsentVersion: expectedConsentVersion,
                    whileCurrent: { self.generation == stamp && self.current() == session })
                try self.deregistrationFence(session, stamp, issuance: issuance)
                self.state.localCancellationConsent = try self.service.readDeregistrationConsent(session: session)
                guard self.state.localCancellationConsent.allowsNewConsent else { throw ComplianceFailure.unresolved }
                self.noticeAccepted = true; self.state.step = .verify
            } catch {
                try self.deregistrationFence(session, stamp, issuance: issuance)
                self.noticeAccepted = false; self.state.smsSent = false
                self.state.localCancellationConsent = try self.service.readDeregistrationConsent(session: session)
                throw error
            }
        }
    }
    public func sendSMS(phone: String, explicitlyRequested: Bool, intent: AccountDeregistrationIntent? = nil) async {
        guard acceptsDeregistrationIntent(intent), explicitlyRequested, noticeAccepted, state.localCancellationConsent.allowsNewConsent, state.step == .verify else { return }
        let issuance = service.deregistrationOriginalRevision
        await run(deregistration: true) { session, stamp in
            self.state.smsSent = false; self.reviewCode = nil
            try self.deregistrationFence(session, stamp, issuance: issuance)
            self.state.localCancellationConsent = try self.service.readDeregistrationConsent(session: session)
            guard self.state.localCancellationConsent.allowsNewConsent else { throw ComplianceFailure.unresolved }
            try await self.auth.sendSMSCode(phone: AuthChannelInput.phone(phone))
            try self.deregistrationFence(session, stamp, issuance: issuance); self.state.smsSent = true
        }
    }
    public func prepareReview(code: String) {
        guard !state.busy, noticeAccepted, state.localCancellationConsent.allowsNewConsent, state.smsSent, state.step == .verify else { return }
        do { reviewCode = try AuthChannelInput.code(code); reviewSession = current(); reviewIssuance = service.deregistrationOriginalRevision; state.step = .review; state.error = nil }
        catch { state.error = "compliance.codeRequired" }; changed()
    }
    public func backToVerification() { guard !state.busy else { return }; reviewCode = nil; state.step = .verify; changed() }
    public func apply(explicitlyConfirmed: Bool, intent: AccountDeregistrationIntent? = nil) async {
        guard acceptsDeregistrationIntent(intent), explicitlyConfirmed, noticeAccepted, state.localCancellationConsent.allowsNewConsent, state.smsSent, state.step == .review, let code = reviewCode, reviewSession == current(), reviewIssuance == service.deregistrationOriginalRevision else { return }
        reviewCode = nil
        let issuance = service.deregistrationOriginalRevision
        await run(deregistration: true) { session, stamp in
            do {
                let result = try await self.service.apply(smscode: code, requestID: self.requestID, session: session, impact: self.state.status?.impact,
                    whileCurrent: { self.generation == stamp && self.current() == session })
                try self.deregistrationFence(session, stamp, issuance: issuance); self.state.status = result
                if result.blocked { self.state.step = .blocked; self.noticeAccepted = false; self.state.smsSent = false }
                else if result.pending {
                    self.state.step = .freshLogin; self.state.busy = false; self.state.smsSent = false; self.noticeAccepted = false; self.changed()
                    // Host callback MUST compare this session before touching the existing auth controller.
                    await self.invalidateSession(session)
                } else { self.state.step = .unknown }
            } catch {
                try self.deregistrationFence(session, stamp, issuance: issuance)
                self.state.localCancellationConsent = try self.service.readDeregistrationConsent(session: session)
                if !self.state.localCancellationConsent.allowsNewConsent {
                    self.state.step = .unknown; self.noticeAccepted = false; self.state.smsSent = false
                    throw error
                }
                self.state.originalApplicationRequestID = try self.service.unresolved("deregister", session: session)?.requestID
                if self.state.originalApplicationRequestID != nil { self.state.step = .unknown }
                else {
                    self.state.step = .notice; self.noticeAccepted = false; self.state.smsSent = false
                    self.requestID = UUID().uuidString.lowercased()
                }
                throw error
            }
        }
    }
    public func cancel(explicitlyConfirmed: Bool, intent: AccountDeregistrationIntent? = nil) async {
        guard acceptsDeregistrationIntent(intent), explicitlyConfirmed, state.step == .pending else { return }
        let issuance = service.deregistrationOriginalRevision
        await run(deregistration: true) { session, stamp in
            do {
                let result = try await self.service.cancel(session: session,
                    whileCurrent: { self.generation == stamp && self.current() == session }); try self.deregistrationFence(session, stamp, issuance: issuance)
                self.state.status = result; self.state.step = .notice; self.noticeAccepted = false
                self.state.smsSent = false; self.requestID = UUID().uuidString.lowercased()
            } catch {
                try self.deregistrationFence(session, stamp, issuance: issuance)
                if try self.service.unresolved("deregisterCancel", session: session) != nil { self.state.step = .unknown }
                throw error
            }
        }
    }
    public func loadMarketing(intent: AccountMarketingReadIntent? = nil) async {
        guard !Task.isCancelled, !state.busy, intent.map(isCurrentMarketingRead) ?? true else { return }
        generation &+= 1
        let issuance = service.marketingOriginalRevision
        await runMarketing { session, stamp in
            self.marketingRevision = UUID(); self.marketingSession = nil
            self.state.marketingLoaded = false; self.state.marketingCurrentConfirmed = false; self.state.marketing = []; self.state.marketingOriginalResults = []
            let snapshot = try await self.service.recoverMarketing(session: session,
                whileCurrent: { self.generation == stamp && self.current() == session && self.service.marketingOriginalRevision == issuance })
            try self.marketingFence(session, stamp, issuance: issuance)
            self.state.marketing = snapshot.rows; self.state.marketingUnresolved = snapshot.unresolvedOperations
            self.marketingSession = session
            self.state.marketingLoaded = snapshot.currentAvailable; self.state.marketingCurrentConfirmed = false
            self.state.marketingOriginalResults = snapshot.originalResults
        }
    }
    public func reviewMarketing(_ row: ComplianceMarketingConsent, channel: ComplianceMarketingChannel, optedIn: Bool) -> ComplianceMarketingReview? {
        guard !Task.isCancelled, !state.busy, state.marketingLoaded, let session = marketingSession, current() == session,
              state.marketing.contains(row), row.value(channel) != optedIn,
              !state.marketingUnresolved.contains(row.operation(channel)),
              service.canChangeMarketing(row, channel: channel, optedIn: optedIn, session: session) else { return nil }
        return .init(row: row, channel: channel, optedIn: optedIn, session: session, revision: marketingRevision, issuance: service.marketingOriginalRevision)
    }
    public func setMarketing(_ review: ComplianceMarketingReview, explicitlyConfirmed: Bool = false) async {
        guard !Task.isCancelled, explicitlyConfirmed, !state.busy, state.marketingLoaded,
              service.marketingOriginalRevision == review.issuance,
              current() == review.session, marketingSession == review.session, marketingRevision == review.revision,
              state.marketing.contains(review.row), review.row.value(review.channel) != review.optedIn,
              !state.marketingUnresolved.contains(review.row.operation(review.channel)) else { return }
        // Consume this review before suspension. Delayed/double confirmation cannot reuse it.
        let submittedRevision = UUID(); marketingRevision = submittedRevision
        let row = review.row; let channel = review.channel; let optedIn = review.optedIn
        let issuance = review.issuance
        await runMarketing { session, stamp in
            guard session == review.session, self.marketingRevision == submittedRevision else { throw ComplianceFailure.staleSession }
            self.state.marketingCurrentConfirmed = false
            do {
                let snapshot = try await self.service.setMarketing(row, channel: channel, optedIn: optedIn, requestID: UUID().uuidString, session: session,
                    whileCurrent: { self.generation == stamp && self.current() == session && self.service.marketingOriginalRevision == issuance })
                try self.marketingFence(session, stamp, issuance: issuance)
                self.state.marketing = snapshot.rows; self.state.marketingLoaded = snapshot.currentAvailable
                self.state.marketingOriginalResults = snapshot.originalResults
                self.state.marketingUnresolved = try self.service.pendingMarketingOperations(session: session)
                self.state.marketingCurrentConfirmed = false
            } catch {
                try self.marketingFence(session, stamp, issuance: issuance)
                self.state.marketing=[];self.state.marketingLoaded=false;self.state.marketingOriginalResults=[]
                do { self.state.marketingUnresolved = try self.service.pendingMarketingOperations(session: session) }
                catch { self.state.marketingLoaded = false; throw error }
                if self.state.marketingUnresolved.contains(row.operation(channel)) { throw ComplianceFailure.unresolved }
                throw error
            }
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
