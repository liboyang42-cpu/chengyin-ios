import Foundation

/// Separate token capsule: existing MessageActionSession intentionally keeps token fileprivate.
public struct IMExpandedSession: Equatable {
    public let identity: MessagingReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token
    }
}
@MainActor public protocol IMSentReading: AnyObject {
    func readSent(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage?
}
@MainActor public protocol IMExpandedWriting: AnyObject {
    var identity: MessagingReadIdentity? { get }
    var isConfigured: Bool { get }
    var canWriteOrdinaryRead: Bool { get }
    var canReadOrdinaryReadReceipt: Bool { get }
    var canReadOrdinaryReadState: Bool { get }
    func performOrdinaryRead(_ intent: OrdinaryIMReadIntent) async throws -> OrdinaryIMReadReceipt
    func recoverOrdinaryRead(_ intent: OrdinaryIMReadIntent) async throws -> OrdinaryIMReadReceipt
    func readOrdinaryRead(scope: IMScope) async throws -> OrdinaryIMReadCurrent
    var canWriteOrdinaryMute: Bool { get }
    var canReadOrdinaryMuteReceipt: Bool { get }
    var canReadOrdinaryMuteState: Bool { get }
    func performOrdinaryMute(_ intent: OrdinaryIMMuteIntent) async throws -> OrdinaryIMMuteReceipt
    func recoverOrdinaryMute(_ intent: OrdinaryIMMuteIntent) async throws -> OrdinaryIMMuteReceipt
    func readOrdinaryMute(scope: IMScope) async throws -> OrdinaryIMMuteCurrent
    var canSendOrdinaryImage: Bool { get }
    var canUploadOrdinaryImage: Bool { get }
    var canRecoverImageUpload: Bool { get }
    func recoverImageUpload(requestID: UUID, sourceSHA256: String, expectedIdentity: MessagingReadIdentity) async throws -> OrdinaryIMImageUploadResult
    var canRecoverOrdinaryImage: Bool { get }
    func recoverOrdinaryImage(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> OrdinaryIMSendReceiptResult
    var canSendVoice: Bool { get }
    var canSendFile: Bool { get }
    var canSendVideo: Bool { get }
    var canRecoverVoice: Bool { get }
    var canRecoverFile: Bool { get }
    var canRecoverVideo: Bool { get }
    func recoverVoice(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage?
    func recoverFile(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage?
    func recoverVideo(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage?
    var canReadRouteShareSource: Bool { get }
    var canSendRoute: Bool { get }
    var canRecoverRoute: Bool { get }
    func routeShareSource(topicID:Int,expectedIdentity:MessagingReadIdentity) async throws -> IMRouteShareSource
    func recoverRoute(_ intent:IMOutgoingIntent,expectedIdentity:MessagingReadIdentity) async throws -> MessagingMessage?
    var canSendStaticLocation: Bool { get }
    var canRecoverStaticLocation: Bool { get }
    func recoverStaticLocation(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage?
    func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt
    func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL
}
public extension IMExpandedWriting {
    var canWriteOrdinaryRead: Bool { false }
    var canReadOrdinaryReadReceipt: Bool { false }
    var canReadOrdinaryReadState: Bool { false }
    func performOrdinaryRead(_ intent: OrdinaryIMReadIntent) async throws -> OrdinaryIMReadReceipt { throw APIError.notConfigured }
    func recoverOrdinaryRead(_ intent: OrdinaryIMReadIntent) async throws -> OrdinaryIMReadReceipt { throw APIError.notConfigured }
    func readOrdinaryRead(scope: IMScope) async throws -> OrdinaryIMReadCurrent { throw APIError.notConfigured }
    var canWriteOrdinaryMute: Bool { false }
    var canReadOrdinaryMuteReceipt: Bool { false }
    var canReadOrdinaryMuteState: Bool { false }
    func performOrdinaryMute(_ intent: OrdinaryIMMuteIntent) async throws -> OrdinaryIMMuteReceipt { throw APIError.notConfigured }
    func recoverOrdinaryMute(_ intent: OrdinaryIMMuteIntent) async throws -> OrdinaryIMMuteReceipt { throw APIError.notConfigured }
    func readOrdinaryMute(scope: IMScope) async throws -> OrdinaryIMMuteCurrent { throw APIError.notConfigured }
    var canSendOrdinaryImage: Bool { false }
    var canUploadOrdinaryImage: Bool { isConfigured }
    var canRecoverImageUpload: Bool { false }
    func recoverImageUpload(requestID: UUID, sourceSHA256: String, expectedIdentity: MessagingReadIdentity) async throws -> OrdinaryIMImageUploadResult { throw APIError.notConfigured }
    var canRecoverOrdinaryImage: Bool { false }
    func recoverOrdinaryImage(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> OrdinaryIMSendReceiptResult { throw APIError.notConfigured }
    var canSendVoice: Bool { false }
    var canSendFile: Bool { false }
    var canSendVideo: Bool { false }
    var canRecoverVoice: Bool { false }
    var canRecoverFile: Bool { false }
    var canRecoverVideo: Bool { false }
    func recoverVoice(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? { throw APIError.notConfigured }
    func recoverFile(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? { throw APIError.notConfigured }
    func recoverVideo(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? { throw APIError.notConfigured }
    var canReadRouteShareSource: Bool { false }
    var canSendRoute: Bool { false }
    var canRecoverRoute: Bool { false }
    func routeShareSource(topicID:Int,expectedIdentity:MessagingReadIdentity) async throws -> IMRouteShareSource { throw APIError.notConfigured }
    func recoverRoute(_ intent:IMOutgoingIntent,expectedIdentity:MessagingReadIdentity) async throws -> MessagingMessage? { throw APIError.notConfigured }
    var canSendStaticLocation: Bool { false }
    var canRecoverStaticLocation: Bool { false }
    func recoverStaticLocation(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? { throw APIError.notConfigured }
}
@MainActor public final class IMExpandedWriter: IMExpandedWriting, IMSentReading {
    private let service: IMExpandedService?
    private let session: () -> IMExpandedSession?
    private let onUnauthorized: (IMExpandedSession) -> Void
    public var identity: MessagingReadIdentity? { session()?.identity }
    public var isConfigured: Bool { service?.isConfigured == true }
    public var canWriteOrdinaryRead: Bool { service?.canWriteOrdinaryRead == true && identity != nil }
    public var canReadOrdinaryReadReceipt: Bool { service?.ordinaryReadReceiptEnabled == true && identity != nil }
    public var canReadOrdinaryReadState: Bool { service?.ordinaryReadStateEnabled == true && identity != nil }
    public func performOrdinaryRead(_ intent: OrdinaryIMReadIntent) async throws -> OrdinaryIMReadReceipt {
        try await withOrdinaryMuteSession(intent.scope) { service, token in try await service.performOrdinaryRead(intent, token: token) }
    }
    public func recoverOrdinaryRead(_ intent: OrdinaryIMReadIntent) async throws -> OrdinaryIMReadReceipt {
        try await withOrdinaryMuteSession(intent.scope) { service, token in try await service.recoverOrdinaryRead(intent, token: token) }
    }
    public func readOrdinaryRead(scope: IMScope) async throws -> OrdinaryIMReadCurrent {
        try await withOrdinaryMuteSession(scope) { service, token in try await service.readOrdinaryRead(scope: scope, token: token) }
    }
    public var canWriteOrdinaryMute: Bool { service?.canWriteOrdinaryMute == true && identity != nil }
    public var canReadOrdinaryMuteReceipt: Bool { service?.ordinaryMuteReceiptEnabled == true && identity != nil }
    public var canReadOrdinaryMuteState: Bool { service?.ordinaryMuteStateEnabled == true && identity != nil }
    public func performOrdinaryMute(_ intent: OrdinaryIMMuteIntent) async throws -> OrdinaryIMMuteReceipt {
        try await withOrdinaryMuteSession(intent.scope) { service, token in try await service.performOrdinaryMute(intent, token: token) }
    }
    public func recoverOrdinaryMute(_ intent: OrdinaryIMMuteIntent) async throws -> OrdinaryIMMuteReceipt {
        try await withOrdinaryMuteSession(intent.scope) { service, token in try await service.recoverOrdinaryMute(intent, token: token) }
    }
    public func readOrdinaryMute(scope: IMScope) async throws -> OrdinaryIMMuteCurrent {
        try await withOrdinaryMuteSession(scope) { service, token in try await service.readOrdinaryMute(scope: scope, token: token) }
    }
    private func withOrdinaryMuteSession<T>(_ scope: IMScope, operation: (IMExpandedService, String) async throws -> T) async throws -> T {
        guard let service, let snapshot = session(), snapshot.identity == scope.identity, !Task.isCancelled else { throw APIError.unauthorized }
        do {
            let value = try await operation(service, snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }; return value
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }; throw error
        }
    }
    public var canSendOrdinaryImage: Bool { service?.canSendOrdinaryImage == true && identity != nil }
    public var canUploadOrdinaryImage: Bool { service?.canUploadOrdinaryImage == true && identity != nil }
    public var canRecoverImageUpload: Bool { service?.imageUploadReceiptEnabled == true && identity != nil }
    public func recoverImageUpload(requestID: UUID, sourceSHA256: String, expectedIdentity: MessagingReadIdentity) async throws -> OrdinaryIMImageUploadResult {
        guard let service, let snapshot = session(), snapshot.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            let result = try await service.recoverImageUpload(requestID: requestID, sourceSHA256: sourceSHA256, token: snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }; return result
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }; throw error
        }
    }
    public var canRecoverOrdinaryImage: Bool { service?.ordinaryReceiptEnabled == true && identity != nil }
    public func recoverOrdinaryImage(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> OrdinaryIMSendReceiptResult {
        guard let service, let snapshot = session(), snapshot.identity == expectedIdentity,
              intent.scope.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            let result = try await service.recoverOrdinaryImage(intent, token: snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            return result
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
    public var canReadRouteShareSource:Bool { service?.routeShareReadEnabled == true }
    public var canSendRoute:Bool { service?.routeSendEnabled == true }
    public var canRecoverRoute:Bool { service?.routeReceiptEnabled == true }
    public func routeShareSource(topicID:Int,expectedIdentity:MessagingReadIdentity) async throws -> IMRouteShareSource {
        guard let service,let snapshot=session(),snapshot.identity==expectedIdentity else { throw APIError.unauthorized }
        do {
            let source=try await service.routeShareSource(topicID:topicID,token:snapshot.token)
            guard session()==snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope };return source
        } catch {
            guard session()==snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) };throw error
        }
    }
    public func recoverRoute(_ intent:IMOutgoingIntent,expectedIdentity:MessagingReadIdentity) async throws -> MessagingMessage? {
        guard let service,let snapshot=session(),snapshot.identity==expectedIdentity,intent.scope.identity==expectedIdentity else { throw APIError.unauthorized }
        do {
            let receipt=try await service.recoverRoute(intent,token:snapshot.token)
            guard session()==snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope };return receipt
        } catch {
            guard session()==snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) };throw error
        }
    }
    public var canSendStaticLocation: Bool { isConfigured && service?.staticLocationEnabled == true }
    public var canRecoverStaticLocation: Bool { service?.staticLocationReceiptEnabled == true }
    public func recoverStaticLocation(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? {
        guard let service,let snapshot=session(),snapshot.identity == expectedIdentity,
              intent.scope.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            let result=try await service.recoverStaticLocation(intent,token:snapshot.token)
            guard session() == snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope };return result
        } catch {
            guard session() == snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
    public var canSendVoice: Bool { isConfigured && service?.voiceSendEnabled == true }
    public var canSendFile: Bool { isConfigured && service?.fileSendEnabled == true }
    public var canSendVideo: Bool { isConfigured && service?.videoSendEnabled == true }
    public var canRecoverVoice: Bool { service?.voiceReceiptEnabled == true }
    public var canRecoverFile: Bool { service?.fileReceiptEnabled == true }
    public var canRecoverVideo: Bool { service?.videoReceiptEnabled == true }
    public func recoverVoice(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? {
        guard let service,let snapshot=session(),snapshot.identity == expectedIdentity,
              intent.scope.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            let result=try await service.recoverVoice(intent,token:snapshot.token)
            guard session() == snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope };return result
        } catch {
            guard session() == snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
    public func recoverFile(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? {
        guard let service,let snapshot=session(),snapshot.identity == expectedIdentity,
              intent.scope.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            let result=try await service.recoverFile(intent,token:snapshot.token)
            guard session() == snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope };return result
        } catch {
            guard session() == snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
    public func recoverVideo(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? {
        guard let service,let snapshot=session(),snapshot.identity == expectedIdentity,
              intent.scope.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            let result=try await service.recoverVideo(intent,token:snapshot.token)
            guard session() == snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope };return result
        } catch {
            guard session() == snapshot,!Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }

    public init(service: IMExpandedService? = nil, session: @escaping () -> IMExpandedSession?, onUnauthorized: @escaping (IMExpandedSession) -> Void = { _ in }) { self.service = service; self.session = session; self.onUnauthorized = onUnauthorized }
    public func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = session(), snapshot.identity == expectedIdentity else { throw APIError.unauthorized }
        if case .send(let intent) = mutation, intent.scope.identity != expectedIdentity { throw IMCapabilityGap.staleScope }
        do {
            let result = try await service.perform(mutation, token: snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if case .read = mutation, case .read = result { NativePushAttemptReader.signalOriginalReadCommitted() }
            return result
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
    public func readSent(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = session(), snapshot.identity == expectedIdentity, intent.scope.identity == expectedIdentity else { throw APIError.unauthorized }
        let message = try await service.readSent(intent, token: snapshot.token)
        guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
        return message
    }
    public func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL {
        guard let service else { throw APIError.notConfigured }
        guard let snapshot = session(), snapshot.identity == expectedIdentity, selection.scope.identity == expectedIdentity else { throw APIError.unauthorized }
        do {
            let result = try await service.upload(selection, consent: consent, token: snapshot.token)
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }; return result
        } catch {
            guard session() == snapshot, !Task.isCancelled else { throw IMCapabilityGap.staleScope }
            if (error as? MessagingReadFailure)?.isUnauthorized == true { onUnauthorized(snapshot) }
            throw error
        }
    }
}
public enum IMReviewState: Equatable { case idle, reviewing(IMMutation), submitting(IMMutation), acknowledged(IMMutationReceipt), outcomeUnknown(IMMutation), rejected(IMMutation), closed }
/// One immutable reviewed mutation per owner. Unknown sends cannot be edited/replaced;
/// retries preserve the exact ID and bytes. No task starts on initialization or dismissal.
@MainActor public final class IMExpandedCoordinator {
    public let scope: IMScope
    public let writer: any IMExpandedWriting
    private var state: IMReviewState = .idle
    private var ordinaryReceiptGeneration = UUID()
    private var ordinaryReceiptInFlight = false
    public private(set) var ordinaryReceiptState: OrdinaryIMReceiptReadState = .idle
    private var ordinaryReadSelected = false
    private var ordinaryReadGeneration = UUID()
    private var ordinaryReadBusy = false
    private var storedOrdinaryReadCurrent: OrdinaryIMReadCurrent?
    public private(set) var ordinaryReadRecoveryState: OrdinaryIMReadRecoveryState = .idle
    public var ordinaryReadCurrent: OrdinaryIMReadCurrent? { isCurrent ? storedOrdinaryReadCurrent : nil }
    public var ordinaryReadRequest: OrdinaryIMReadRequest? { guard isCurrent, let recovery else { return nil }; return try? recovery.ordinaryReadRequest() }
    public var pendingOrdinaryRead: Bool {
        guard isCurrent else { return false }
        switch state { case .outcomeUnknown(.read), .rejected(.read): return true; default: return false }
    }
    public var canReviewOrdinaryRead: Bool { isCurrent && recovery != nil && !ordinaryReadBusy && writer.canWriteOrdinaryRead && writer.canReadOrdinaryReadReceipt && writer.canReadOrdinaryReadState }
    @discardableResult public func reviewOrdinaryRead() -> Bool {
        guard canReviewOrdinaryRead, review(.read(conversationID: scope.conversationID)) else { return false }
        ordinaryReadSelected = true; ordinaryReadRecoveryState = .idle; onChange?(); return true
    }
    public var canReadOrdinaryRead: Bool {
        guard isCurrent, !ordinaryReadBusy, recovery != nil, writer.canReadOrdinaryReadReceipt || writer.canReadOrdinaryReadState else { return false }
        if case .submitting = state { return false }; return true
    }
    public var canRetryOrdinaryRead: Bool { canReadOrdinaryRead && writer.canWriteOrdinaryRead && writer.canReadOrdinaryReadReceipt && pendingOrdinaryRead && ordinaryReadRequest != nil && ordinaryReadRecoveryState == .notFound && ordinaryReadCurrent != nil }
    public func invalidateOrdinaryRead() {
        ordinaryReadGeneration = UUID(); storedOrdinaryReadCurrent = nil; ordinaryReadRecoveryState = .idle
        // The journal lease still owns any in-flight operation until its completion.
    }
    /// Foreground/reentry are receipt + current-state GETs only; zero unread is never proof.
    public func recoverOrdinaryRead(stillAuthorized: () -> Bool = { true }) async {
        guard canReadOrdinaryRead, stillAuthorized(), !Task.isCancelled, let recovery, let lease = recovery.beginOperation() else { return }
        let ticket = ordinaryReadGeneration; ordinaryReadBusy = true; storedOrdinaryReadCurrent = nil
        ordinaryReadRecoveryState = .reading; onChange?()
        defer { recovery.endOperation(lease); ordinaryReadBusy = false; onChange?() }
        func current() -> Bool { isCurrent && ordinaryReadGeneration == ticket && !Task.isCancelled && stillAuthorized() }
        do {
            if pendingOrdinaryRead {
                let mutation = IMMutation.read(conversationID: scope.conversationID)
                guard try recovery.restore(current: scope) == mutation else { throw APIError.invalidRequest }
                if let original = try recovery.ordinaryReadRequest(), writer.canReadOrdinaryReadReceipt {
                    let result = try await writer.recoverOrdinaryRead(try .init(scope: scope, original: original))
                    guard current() else { return }
                    switch result {
                    case .applied:
                        try recovery.settleOrdinaryRead(mutation, original: original)
                        state = .acknowledged(.read); ordinaryReadRecoveryState = .applied
                        NativePushAttemptReader.signalOriginalReadCommitted()
                    case .pending: ordinaryReadRecoveryState = .pending
                    case .notFound: ordinaryReadRecoveryState = .notFound
                    }
                } else { ordinaryReadRecoveryState = try recovery.ordinaryReadRequest() == nil ? .legacyUnknown : .unavailable }
            } else { ordinaryReadRecoveryState = .ready }
        } catch { if current() { ordinaryReadRecoveryState = .unknown } }
        guard current(), writer.canReadOrdinaryReadState else { return }
        do {
            let value = try await writer.readOrdinaryRead(scope: scope)
            guard current() else { return }; try value.validate(scope: scope); storedOrdinaryReadCurrent = value
        } catch { if current() { storedOrdinaryReadCurrent = nil; if ordinaryReadRecoveryState == .ready { ordinaryReadRecoveryState = .unavailable } } }
    }
    public func retryOrdinaryReadConfirmed(_ original: OrdinaryIMReadRequest, stillAuthorized: () -> Bool = { true }) async {
        guard canRetryOrdinaryRead, ordinaryReadRequest == original, stillAuthorized() else { return }
        await recoverOrdinaryRead(stillAuthorized: stillAuthorized)
        guard canRetryOrdinaryRead, ordinaryReadRequest == original, stillAuthorized(), !Task.isCancelled else { return }
        await dispatchOrdinaryRead(original: original, stillAuthorized: stillAuthorized)
    }
    private func dispatchOrdinaryRead(original retry: OrdinaryIMReadRequest? = nil, stillAuthorized: () -> Bool) async {
        guard canReviewOrdinaryRead, stillAuthorized(), !Task.isCancelled, let recovery, let lease = recovery.beginOperation() else { return }
        let mutation = IMMutation.read(conversationID: scope.conversationID), ticket = ordinaryReadGeneration
        ordinaryReadBusy = true; storedOrdinaryReadCurrent = nil; state = .submitting(mutation); onChange?()
        defer { recovery.endOperation(lease); ordinaryReadBusy = false; onChange?() }
        func current() -> Bool { isCurrent && ordinaryReadGeneration == ticket && !Task.isCancelled && stillAuthorized() }
        do {
            // Freeze once after explicit confirmation. Every replay keeps this original cursor.
            let currentState = try await writer.readOrdinaryRead(scope: scope)
            guard current() else { throw CancellationError() }; try currentState.validate(scope: scope)
            let original: OrdinaryIMReadRequest
            if let retry {
                guard try recovery.restore(current: scope) == mutation, try recovery.ordinaryReadRequest() == retry else { throw APIError.invalidRequest }
                original = retry
            } else {
                guard try recovery.restore(current: scope) == nil, let cursor = currentState.latestVisibleID else { throw APIError.invalidRequest }
                original = try .init(requestID: UUID().uuidString.lowercased(), readTo: cursor)
            }
            try recovery.saveOrdinaryReadBeforeDispatch(mutation, original: original)
            guard current() else { throw CancellationError() }
            let intent = try OrdinaryIMReadIntent(scope: scope, original: original)
            let outcome = try await writer.performOrdinaryRead(intent)
            guard current() else { throw CancellationError() }
            guard outcome == .applied else {
                state = .outcomeUnknown(mutation); ordinaryReadRecoveryState = outcome == .pending ? .pending : .notFound; return
            }
            // Accept only the immutable original-writer receipt, never current unread equality.
            try recovery.settleOrdinaryRead(mutation, original: original)
            state = .acknowledged(.read); ordinaryReadRecoveryState = .applied
            NativePushAttemptReader.signalOriginalReadCommitted()
            let fresh = try? await writer.readOrdinaryRead(scope: scope)
            if current() { storedOrdinaryReadCurrent = fresh }
        } catch {
            // If preflight never produced a persisted request there was no write to recover.
            do { state = try recovery.restore(current: scope) == nil ? .idle : .outcomeUnknown(mutation) }
            catch { state = .closed }
            if current() { ordinaryReadRecoveryState = .unknown }
        }
    }
    private var ordinaryMuteSelected = false
    private var ordinaryMuteGeneration = UUID()
    private var ordinaryMuteBusy = false
    private var storedOrdinaryMuteCurrent: OrdinaryIMMuteCurrent?
    public private(set) var ordinaryMuteRecoveryState: OrdinaryIMMuteRecoveryState = .idle
    public var ordinaryMuteCurrent: OrdinaryIMMuteCurrent? { isCurrent ? storedOrdinaryMuteCurrent : nil }
    public var canReadOrdinaryMute: Bool { isCurrent && !ordinaryMuteBusy && (writer.canReadOrdinaryMuteReceipt || writer.canReadOrdinaryMuteState) }
    public var ordinaryMuteRequestID: String? { guard isCurrent, let recovery else { return nil }; return try? recovery.ordinaryMuteRequestID() }
    public var pendingOrdinaryMute: Bool? {
        switch state { case .outcomeUnknown(.mute(_, let muted)), .rejected(.mute(_, let muted)): return muted; default: return nil }
    }
    public var canRetryOrdinaryMute: Bool { canReadOrdinaryMute && writer.canWriteOrdinaryMute && writer.canReadOrdinaryMuteReceipt && ordinaryMuteRequestID != nil && pendingOrdinaryMute != nil && ordinaryMuteRecoveryState == .notFound && ordinaryMuteCurrent != nil }
    public func invalidateOrdinaryMuteRead() {
        ordinaryMuteGeneration = UUID(); ordinaryMuteBusy = false; storedOrdinaryMuteCurrent = nil
        ordinaryMuteRecoveryState = .idle
    }
    @discardableResult public func reviewOrdinaryMute(_ muted: Bool) -> Bool {
        guard writer.canWriteOrdinaryMute, writer.canReadOrdinaryMuteReceipt, writer.canReadOrdinaryMuteState, recovery != nil, review(.mute(conversationID: scope.conversationID, muted: muted)) else { return false }
        ordinaryMuteSelected = true; ordinaryMuteRecoveryState = .idle; onChange?(); return true
    }
    /// Appearance, restart and legacy UNKNOWN only read. Equality of current state is never a receipt.
    public func recoverOrdinaryMute(stillAuthorized: () -> Bool = { true }) async {
        guard canReadOrdinaryMute, stillAuthorized(), !Task.isCancelled, let recovery, let lease = recovery.beginOperation() else { return }
        let ticket = ordinaryMuteGeneration; ordinaryMuteBusy = true; storedOrdinaryMuteCurrent = nil
        ordinaryMuteRecoveryState = .reading; onChange?()
        defer { recovery.endOperation(lease); if ordinaryMuteGeneration == ticket { ordinaryMuteBusy = false; onChange?() } }
        func current() -> Bool { isCurrent && ordinaryMuteGeneration == ticket && !Task.isCancelled && stillAuthorized() }
        do {
            if let muted = pendingOrdinaryMute {
                let mutation = IMMutation.mute(conversationID: scope.conversationID, muted: muted)
                guard try recovery.restore(current: scope) == mutation else { throw APIError.invalidRequest }
                if let request = try recovery.ordinaryMuteRequestID(), writer.canReadOrdinaryMuteReceipt {
                    let intent = try OrdinaryIMMuteIntent(scope: scope, requestID: request, muted: muted)
                    let result = try await writer.recoverOrdinaryMute(intent)
                    guard current() else { return }
                    switch result {
                    case .applied:
                        try recovery.settleOrdinaryMute(mutation, requestID: request); state = .acknowledged(.muted(muted)); ordinaryMuteRecoveryState = .applied
                        NotificationCenter.default.post(name: NativeChannelNotificationCoordinator.originalUnreadPolicyCommitted, object: nil)
                    case .pending: ordinaryMuteRecoveryState = .pending
                    case .notFound: ordinaryMuteRecoveryState = .notFound
                    }
                } else { ordinaryMuteRecoveryState = try recovery.ordinaryMuteRequestID() == nil ? .legacyUnknown : .unavailable }
            } else { ordinaryMuteRecoveryState = .ready }
        } catch { if current() { ordinaryMuteRecoveryState = .unknown } }
        guard current(), writer.canReadOrdinaryMuteState else { return }
        do {
            let value = try await writer.readOrdinaryMute(scope: scope)
            guard current() else { return }; try value.validate(scope: scope); storedOrdinaryMuteCurrent = value
        } catch { if current() { storedOrdinaryMuteCurrent = nil; if ordinaryMuteRecoveryState == .ready { ordinaryMuteRecoveryState = .unavailable } } }
    }
    public func retryOrdinaryMuteConfirmed(requestID: String, stillAuthorized: () -> Bool = { true }) async {
        guard canRetryOrdinaryMute, ordinaryMuteRequestID == requestID, let muted = pendingOrdinaryMute, stillAuthorized() else { return }
        await recoverOrdinaryMute(stillAuthorized: stillAuthorized)
        guard canRetryOrdinaryMute, ordinaryMuteRequestID == requestID, pendingOrdinaryMute == muted, stillAuthorized(), !Task.isCancelled else { return }
        ordinaryMuteSelected = true
        await dispatch(.mute(conversationID: scope.conversationID, muted: muted), requiresExisting: true, stillAuthorized: stillAuthorized)
    }
    public var pendingOrdinaryImage: IMOutgoingIntent? {
        guard isCurrent else { return nil }
        switch state {
        case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
            if case .image = intent.payload { return intent }; return nil
        default: return nil
        }
    }
    public var canRecoverOrdinaryImage: Bool {
        isCurrent && writer.canRecoverOrdinaryImage && !ordinaryReceiptInFlight && pendingOrdinaryImage != nil
    }
    public var canRetryOrdinaryImage: Bool {
        canRecoverOrdinaryImage && writer.canSendOrdinaryImage && ordinaryReceiptState == .notFound
    }
    private var routeReviewToken=UUID()
    public private(set) var selectedRouteShareSource:IMRouteShareSource?
    public private(set) var routeShareUnavailable=false
    public func reviewRoute(topicID:Int) async {
        guard isCurrent,writer.canSendRoute,writer.canReadRouteShareSource else { return }
        switch state { case .idle,.acknowledged: break;default:return }
        let previous=state
        let token=UUID();routeReviewToken=token;selectedRouteShareSource=nil;routeShareUnavailable=false;onChange?()
        do {
            let source=try await writer.routeShareSource(topicID:topicID,expectedIdentity:scope.identity)
            guard isCurrent,!Task.isCancelled,routeReviewToken==token,state==previous else { return }
            selectedRouteShareSource=source
            _ = review(.send(try IMOutgoingIntent(scope:scope,payload:.route(topicID:source.topicID))))
        } catch { if isCurrent,routeReviewToken==token { routeShareUnavailable=true;selectedRouteShareSource=nil;onChange?() } }
    }

    private let recovery: IMExpandedRecoveryJournal?
    private let stillCurrent: () -> Bool
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { stillCurrent() && writer.identity == scope.identity }
    public var visibleState: IMReviewState { isCurrent ? state : .idle }
    public var usesOriginalRecovery: Bool { recovery != nil }
    public init(scope: IMScope, writer: any IMExpandedWriting, recovery: IMExpandedRecoveryJournal? = nil,
                stillCurrent: @escaping () -> Bool = { true }) {
        self.scope = scope; self.writer = writer; self.recovery = recovery; self.stillCurrent = stillCurrent
        if let recovery {
            do { if let mutation = try recovery.restore(current: scope) { state = .outcomeUnknown(mutation) } }
            catch { state = .closed }
        }
    }
    @discardableResult public func review(_ mutation: IMMutation) -> Bool {
        guard isCurrent, writer.isConfigured, !ordinaryReceiptInFlight, !ordinaryMuteBusy, !ordinaryReadBusy else { return false }
        switch state { case .submitting, .outcomeUnknown, .closed: return false; default: break }
        if recovery != nil, case .rejected = state { return false }
        guard mutation.conversationID == nil || mutation.conversationID == scope.conversationID else { return false }
        if case .send(let intent) = mutation, intent.scope != scope { return false }
        if recovery != nil, case .send(let intent)=mutation,case .image=intent.payload,!writer.canSendOrdinaryImage { return false }
        if case .send(let intent)=mutation,case .staticLocation=intent.payload,!writer.canSendStaticLocation { return false }
        if case .send(let intent)=mutation,case .voice=intent.payload,!writer.canSendVoice { return false }
        if case .send(let intent)=mutation,case .file=intent.payload,!writer.canSendFile { return false }
        if case .send(let intent)=mutation,case .video=intent.payload,!writer.canSendVideo { return false }
        if case .send(let intent)=mutation,case .route(let topic)=intent.payload,
           (recovery != nil || writer.canReadRouteShareSource),
           (!writer.canSendRoute || selectedRouteShareSource?.topicID != topic) { return false }
        if case .acknowledged = state, let recovery,
           (try? recovery.hasPendingSend()) != false { return false }
        if case .send = mutation, let recovery, (try? recovery.permitsNewSend()) != true { return false }
        ordinaryReadSelected = false
        ordinaryMuteSelected = false
        state = .reviewing(mutation); onChange?(); return true
    }
    public func cancelReview() {
        routeReviewToken=UUID();selectedRouteShareSource=nil;routeShareUnavailable=false
        if case .reviewing = state { state = .idle;onChange?() }
    }
    public func confirm(stillAuthorized: () -> Bool = { true }) async {
        guard case .reviewing(let mutation) = state, stillAuthorized() else { return }
        if case .read = mutation, ordinaryReadSelected { await dispatchOrdinaryRead(stillAuthorized: stillAuthorized); return }
        await dispatch(mutation, stillAuthorized: stillAuthorized)
    }
    public var canRecoverRoute:Bool {
        guard isCurrent,writer.canRecoverRoute else { return false }
        if case .outcomeUnknown(.send(let intent))=state,case .route=intent.payload { return true };return false
    }
    public func recoverRoute() async {
        guard canRecoverRoute,case .outcomeUnknown(.send(let intent))=state else { return }
        let mutation=IMMutation.send(intent);let operation:UUID?
        if let recovery { guard let value=recovery.beginOperation() else{return};operation=value } else { operation=nil }
        defer { if let operation { recovery?.endOperation(operation) } }
        state = .submitting(mutation);onChange?()
        do {
            let receipt=try await writer.recoverRoute(intent,expectedIdentity:scope.identity)
            guard isCurrent,!Task.isCancelled,let receipt else { state = .outcomeUnknown(mutation);onChange?();return }
            try recovery?.settle(mutation);state = .acknowledged(.sent(receipt))
        } catch { state = .outcomeUnknown(mutation) }
        onChange?()
    }
    public func finishRouteResult() {
        guard isCurrent,case .acknowledged(.sent(let message))=state,message.card?.kind == .route else { return }
        state = .idle;selectedRouteShareSource=nil;onChange?()
    }
    public func finishVoiceResult() {
        guard isCurrent,case .acknowledged(.sent(let message))=state, IMVoiceReference.read(message) != nil else { return }
        state = .idle;onChange?()
    }
    public func finishFileResult() {
        guard isCurrent,case .acknowledged(.sent(let message))=state, IMFileReference.read(message) != nil else { return }
        state = .idle;onChange?()
    }
    public func finishVideoResult() {
        guard isCurrent,case .acknowledged(.sent(let message))=state, IMVideoReference.read(message) != nil else { return }
        state = .idle;onChange?()
    }
    public func finishStaticLocationResult() {
        guard isCurrent,case .acknowledged(.sent(let message))=state,
              IMStaticLocation.read(message) != nil else { return }
        state = .idle;onChange?()
    }
    public var canRecoverStaticLocation: Bool {
        guard isCurrent,writer.canRecoverStaticLocation else { return false }
        if case .outcomeUnknown(.send(let intent))=state,case .staticLocation=intent.payload { return true }
        return false
    }
    public func recoverStaticLocation() async {
        guard canRecoverStaticLocation,case .outcomeUnknown(.send(let intent))=state else { return }
        let mutation=IMMutation.send(intent)
        let operation: UUID?
        if let recovery { guard let value=recovery.beginOperation() else { return };operation=value } else { operation=nil }
        defer { if let operation { recovery?.endOperation(operation) } }
        state = .submitting(mutation);onChange?()
        do {
            let receipt=try await writer.recoverStaticLocation(intent,expectedIdentity:scope.identity)
            guard isCurrent,!Task.isCancelled,let receipt else { state = .outcomeUnknown(mutation);onChange?();return }
            try recovery?.settle(mutation);state = .acknowledged(.sent(receipt))
        } catch { state = .outcomeUnknown(mutation) }
        onChange?()
    }
    public var canRecoverVoice: Bool {
        guard isCurrent,writer.canRecoverVoice else { return false }
        switch state {
        case .outcomeUnknown(.send(let intent)), .rejected(.send(let intent)):
            if case .voice = intent.payload { return true }; return false
        default: return false
        }
    }
    public var canRecoverFile: Bool {
        guard isCurrent,writer.canRecoverFile else { return false }
        if case .outcomeUnknown(.send(let intent))=state,case .file=intent.payload { return true }
        return false
    }
    public var canRecoverVideo: Bool {
        guard isCurrent,writer.canRecoverVideo else { return false }
        if case .outcomeUnknown(.send(let intent))=state,case .video=intent.payload { return true }
        return false
    }
    public func recoverVoice() async {
        guard canRecoverVoice else { return }
        let intent: IMOutgoingIntent
        switch state {
        case .outcomeUnknown(.send(let pending)), .rejected(.send(let pending)): intent = pending
        default: return
        }
        let mutation=IMMutation.send(intent)
        let operation: UUID?
        if let recovery { guard let value=recovery.beginOperation() else { return };operation=value } else { operation=nil }
        defer { if let operation { recovery?.endOperation(operation) } }
        state = .submitting(mutation);onChange?()
        do {
            let receipt=try await writer.recoverVoice(intent,expectedIdentity:scope.identity)
            guard isCurrent,!Task.isCancelled,let receipt else { state = .outcomeUnknown(mutation);onChange?();return }
            try recovery?.settle(mutation);state = .acknowledged(.sent(receipt))
        } catch { state = .outcomeUnknown(mutation) }
        onChange?()
    }
    public func recoverFile() async {
        guard canRecoverFile,case .outcomeUnknown(.send(let intent))=state else { return }
        let mutation=IMMutation.send(intent)
        let operation: UUID?
        if let recovery { guard let value=recovery.beginOperation() else { return };operation=value } else { operation=nil }
        defer { if let operation { recovery?.endOperation(operation) } }
        state = .submitting(mutation);onChange?()
        do {
            let receipt=try await writer.recoverFile(intent,expectedIdentity:scope.identity)
            guard isCurrent,!Task.isCancelled,let receipt else { state = .outcomeUnknown(mutation);onChange?();return }
            try recovery?.settle(mutation);state = .acknowledged(.sent(receipt))
        } catch { state = .outcomeUnknown(mutation) }
        onChange?()
    }
    public func recoverVideo() async {
        guard canRecoverVideo,case .outcomeUnknown(.send(let intent))=state else { return }
        let mutation=IMMutation.send(intent)
        let operation: UUID?
        if let recovery { guard let value=recovery.beginOperation() else { return };operation=value } else { operation=nil }
        defer { if let operation { recovery?.endOperation(operation) } }
        state = .submitting(mutation);onChange?()
        do {
            let receipt=try await writer.recoverVideo(intent,expectedIdentity:scope.identity)
            guard isCurrent,!Task.isCancelled,let receipt else { state = .outcomeUnknown(mutation);onChange?();return }
            try recovery?.settle(mutation);state = .acknowledged(.sent(receipt))
        } catch { state = .outcomeUnknown(mutation) }
        onChange?()
    }
    /// Ordinary image checks never upload or send. Reload and retry lookup share the
    /// existing owner/journal operation lock; NOT_FOUND does not settle the journal.
    @discardableResult public func recoverOrdinaryImage(stillAuthorized: () -> Bool = { true }) async -> OrdinaryIMSendReceiptResult? {
        guard canRecoverOrdinaryImage, stillAuthorized(), !Task.isCancelled,
              let intent = pendingOrdinaryImage else { return nil }
        let mutation = IMMutation.send(intent), operation: UUID?
        if let recovery { guard let value = recovery.beginOperation() else { return nil }; operation = value }
        else { operation = nil }
        let generation = UUID(); ordinaryReceiptGeneration = generation; ordinaryReceiptInFlight = true
        ordinaryReceiptState = .reading; onChange?()
        defer {
            ordinaryReceiptInFlight = false
            if ordinaryReceiptGeneration == generation, ordinaryReceiptState == .reading { ordinaryReceiptState = .unknown }
            if let operation { recovery?.endOperation(operation) }
            onChange?()
        }
        do {
            if let recovery {
                guard try recovery.restore(current: scope) == mutation else { throw NativeChannelTextJournalError.pendingIntent }
            }
            let result = try await writer.recoverOrdinaryImage(intent, expectedIdentity: scope.identity)
            guard isCurrent, !Task.isCancelled, ordinaryReceiptGeneration == generation,
                  stillAuthorized(), pendingOrdinaryImage == intent else { return nil }
            switch result {
            case .found(let message):
                // Preserve the original image request until an independent original history read.
                state = .acknowledged(.sent(message)); ordinaryReceiptState = .idle
            case .notFound: ordinaryReceiptState = .notFound
            }
            onChange?(); return result
        } catch {
            if ordinaryReceiptGeneration == generation {
                ordinaryReceiptState = .unknown
                if isCurrent, stillAuthorized(), let failure = error as? MessagingReadFailure,
                   OrdinaryIMSendReceipt.revokesRead(failure) { state = .closed }
                onChange?()
            }
            return nil
        }
    }
    /// Read-only restoration of this owner's sole original send request, not a second ledger.
    public func retainedOrdinaryImage() throws -> IMOutgoingIntent? {
        guard isCurrent else { throw APIError.notConfigured }
        if let pending = pendingOrdinaryImage { return pending }
        guard let recovery, case .send(let intent)? = try recovery.restore(current: scope),
              case .image = intent.payload else { return nil }
        return intent
    }
    /// Caller supplies the freshly independently read original history row. No send ACK can call this.
    public func finishOrdinaryImage(_ intent: IMOutgoingIntent, visible: MessagingMessage) throws {
        guard isCurrent, intent.scope == scope, case .image(let url) = intent.payload,
              visible.isPayloadVisible, visible.type == 2, visible.senderID == scope.identity.accountID,
              visible.conversationID == scope.conversationID, visible.content == url.absoluteString,
              case .acknowledged(.sent(let receipt)) = state, receipt.id == visible.id,
              try retainedOrdinaryImage() == intent else { throw APIError.malformedResponse }
        try recovery?.settle(.send(intent)); state = .idle; ordinaryReceiptState = .idle; onChange?()
    }
    public func invalidateOrdinaryImageRecovery() {
        ordinaryReceiptGeneration = UUID(); ordinaryReceiptState = .unknown; onChange?()
    }
    public func retryOrdinaryImageConfirmed(clientMessageID: String, stillAuthorized: () -> Bool = { true }) async {
        guard canRetryOrdinaryImage, stillAuthorized(), let intent = pendingOrdinaryImage,
              intent.clientMessageID == clientMessageID else { return }
        let result = await recoverOrdinaryImage(stillAuthorized: stillAuthorized)
        guard result == .notFound, isCurrent, !Task.isCancelled, stillAuthorized(),
              pendingOrdinaryImage == intent else { return }
        await dispatch(.send(intent), requiresExisting: true, stillAuthorized: stillAuthorized)
    }
    public func retryUnchanged() async {
        if recovery == nil {
            let pending: IMMutation
            switch state { case .outcomeUnknown(let value), .rejected(let value): pending = value; default: return }
            if case .send(let intent) = pending {
                switch intent.payload {
                case .voice, .file, .video, .staticLocation: break
                default: await retryLegacyUnchanged(); return
                }
            } else { await retryLegacyUnchanged(); return }
        }
        if recovery != nil, pendingOrdinaryRead { await recoverOrdinaryRead(); return }
        // A legacy mute lacks an immutable key; generic retry must never manufacture one or replay it.
        if recovery != nil, pendingOrdinaryMute != nil { await recoverOrdinaryMute(); return }
        // The legacy generic retry cannot bypass original-image recovery/confirmation.
        if recovery != nil, pendingOrdinaryImage != nil { _ = await recoverOrdinaryImage(); return }
        switch state { case .outcomeUnknown(let mutation), .rejected(let mutation): await dispatch(mutation); default: return }
    }
    private func retryLegacyUnchanged() async {
        switch state {
        case .outcomeUnknown(let mutation):
            if case .send(let intent) = mutation, let identity = writer.identity, identity == scope.identity,
               let reader = writer as? IMSentReading {
                do {
                    if let message = try await reader.readSent(intent, expectedIdentity: identity) {
                        guard message.senderID == identity.accountID else {
                            state = .outcomeUnknown(mutation); onChange?(); return
                        }
                        state = .acknowledged(.sent(message)); onChange?(); return
                    }
                } catch {
                    state = .outcomeUnknown(mutation); onChange?(); return
                }
            }
            await dispatch(mutation)
        case .rejected(let mutation):
            await dispatch(mutation)
        default:
            return
        }
    }
    private func dispatch(_ mutation: IMMutation, requiresExisting: Bool = false,
                          stillAuthorized: () -> Bool = { true }) async {
        guard isCurrent, writer.isConfigured, !Task.isCancelled, stillAuthorized(), !ordinaryReceiptInFlight, !ordinaryMuteBusy else { return }
        // Ordinary read may never fall back to a cursorless latest-read writer.
        if case .read = mutation, ordinaryReadSelected { await recoverOrdinaryRead(stillAuthorized: stillAuthorized); return }
        let operation: UUID?
        let originalACK: Bool
        if case .readCursor = mutation { originalACK = true } else { originalACK = false }
        if let recovery, !originalACK {
            guard let acquired = recovery.beginOperation() else { return }
            operation = acquired
            do {
                if requiresExisting {
                    guard try recovery.restore(current: scope) == mutation else { throw NativeChannelTextJournalError.pendingIntent }
                }
                try recovery.saveBeforeDispatch(mutation, ordinaryMute: ordinaryMuteSelected)
            }
            catch { recovery.endOperation(acquired); state = .closed; onChange?(); return }
        } else { operation = nil }
        defer { if let operation { recovery?.endOperation(operation) } }
        if case .send(let intent) = mutation, case .image = intent.payload { ordinaryReceiptState = .unknown }
        state = .submitting(mutation); onChange?()
        do {
            let receipt: IMMutationReceipt
            var confirmedOrdinaryMuteRequestID: String?
            if case .mute(_, let muted) = mutation, ordinaryMuteSelected {
                guard let requestID = try recovery?.ordinaryMuteRequestID(), stillAuthorized() else { throw APIError.invalidRequest }
                let intent = try OrdinaryIMMuteIntent(scope: scope, requestID: requestID, muted: muted)
                // A fresh original current read fences a revoked/hidden/nonordinary target before the writer.
                let current = try await writer.readOrdinaryMute(scope: scope)
                try current.validate(scope: scope)
                guard isCurrent, !Task.isCancelled, stillAuthorized(), try recovery?.ordinaryMuteRequestID() == requestID else { throw IMCapabilityGap.staleScope }
                let result = try await writer.performOrdinaryMute(intent)
                guard result == .applied else { state = .outcomeUnknown(mutation); ordinaryMuteRecoveryState = result == .pending ? .pending : .notFound; onChange?(); return }
                confirmedOrdinaryMuteRequestID = requestID; receipt = .muted(muted)
            } else { receipt = try await writer.perform(mutation, expectedIdentity: scope.identity) }
            guard isCurrent, !Task.isCancelled, stillAuthorized() else { state = .outcomeUnknown(mutation); onChange?(); return }
            if recovery != nil, case .send(let intent) = mutation, case .image = intent.payload {
                guard writer.canRecoverOrdinaryImage,
                      case .found(let original) = try await writer.recoverOrdinaryImage(intent, expectedIdentity: scope.identity),
                      case .sent(let acknowledged) = receipt, original == acknowledged,
                      isCurrent, !Task.isCancelled, stillAuthorized() else { state = .outcomeUnknown(mutation); onChange?(); return }
            }
            if case .send(let intent) = mutation, case .image = intent.payload { /* Original image journal is settled by visible readback. */ }
            else if case .mute = mutation, ordinaryMuteSelected {
                guard let recovery, let requestID = confirmedOrdinaryMuteRequestID else { throw APIError.invalidRequest }
                try recovery.settleOrdinaryMute(mutation, requestID: requestID)
            } else if !originalACK { try recovery?.settle(mutation) }
            state = .acknowledged(receipt)
            if case .mute = mutation, ordinaryMuteSelected {
                ordinaryMuteRecoveryState = .applied; storedOrdinaryMuteCurrent = nil
                NotificationCenter.default.post(name: NativeChannelNotificationCoordinator.originalUnreadPolicyCommitted, object: nil)
                if writer.canReadOrdinaryMuteState {
                    let ticket = ordinaryMuteGeneration
                    let current = try? await writer.readOrdinaryMute(scope: scope)
                    if isCurrent, !Task.isCancelled, stillAuthorized(), ordinaryMuteGeneration == ticket { storedOrdinaryMuteCurrent = current }
                }
            }
        } catch {
            if isCurrent, let failure = error as? MessagingReadFailure, failure.httpStatus == nil, failure.isClosed { state = .closed }
            else if isCurrent, let failure = error as? MessagingReadFailure, failure.httpStatus == nil, let code = failure.code, [400,401,403,404].contains(code) { state = .rejected(mutation) }
            else { state = .outcomeUnknown(mutation) }
        }
        onChange?()
    }
}
/// Source uses explicit latest-page refresh, not realtime. Generation protects against old
/// completions across conversation, account epoch, cancellation and repeated refreshes.
public struct IMRefreshGate: Equatable {
    public private(set) var scope: IMScope?
    public private(set) var generation: UInt64 = 0
    public private(set) var loading = false
    public init() {}
    public mutating func begin(_ scope: IMScope) -> UInt64 { generation &+= 1; self.scope = scope; loading = true; return generation }
    public mutating func finish(_ generation: UInt64, scope: IMScope) -> Bool {
        guard self.generation == generation, self.scope == scope, loading else { return false }; loading = false; return true
    }
    public mutating func cancel() { generation &+= 1; scope = nil; loading = false }
}

@MainActor public final class IMConversationStarter {
    public let identity: MessagingReadIdentity
    public let writer: any IMExpandedWriting
    private var state: IMReviewState = .idle
    public var onChange: (() -> Void)?
    public var visibleState: IMReviewState { writer.identity == identity ? state : .idle }
    public init(identity: MessagingReadIdentity, writer: any IMExpandedWriting) { self.identity = identity; self.writer = writer }
    public func cancelReview() { if case .reviewing = state { state = .idle; onChange?() } }
    public func review(targetMemberID: Int) {
        guard writer.identity == identity, writer.isConfigured, targetMemberID > 0 else { return }
        switch state { case .submitting, .outcomeUnknown: return; default: break }
        state = .reviewing(.start(targetMemberID: targetMemberID)); onChange?()
    }
    public func confirm() async {
        guard writer.identity == identity, case .reviewing(let mutation) = state else { return }
        state = .submitting(mutation); onChange?()
        do {
            let receipt = try await writer.perform(mutation, expectedIdentity: identity)
            guard writer.identity == identity, !Task.isCancelled else { state = .outcomeUnknown(mutation); onChange?(); return }
            state = .acknowledged(receipt)
        } catch { state = .outcomeUnknown(mutation) }
        onChange?()
    }
    public func retryUnchanged() async {
        guard writer.identity == identity, case .outcomeUnknown(let mutation) = state else { return }
        state = .reviewing(mutation); await confirm()
    }
}
