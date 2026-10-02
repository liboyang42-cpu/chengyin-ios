import Foundation

@MainActor public final class MerchantNPCChatCoordinator {
    public let scope: MerchantNPCScope
    private let currentScope: () -> MerchantNPCScope?
    private let grants: () -> MerchantNPCGrants
    private let client: MerchantNPCHTTPClient
    public var onChange: (() -> Void)?
    public private(set) var reply: MerchantNPCReply?
    public private(set) var message: String?
    public private(set) var failure: MerchantNPCFailure?
    public private(set) var sending = false
    public private(set) var requestID: UUID?
    public private(set) var retryAt: Date?
    private var attempts = 0
    private var generation = 0
    private var active = true
    public init(scope: MerchantNPCScope, client: MerchantNPCHTTPClient, currentScope: @escaping () -> MerchantNPCScope?, grants: @escaping () -> MerchantNPCGrants) {
        self.scope = scope; self.client = client; self.currentScope = currentScope; self.grants = grants
    }
    public var isCurrent: Bool { active && currentScope() == scope }
    public var canSend: Bool { isCurrent && grants().chatAllowed && !sending && requestID == nil }
    public func send(_ text: String) async {
        guard canSend, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        message = text.trimmingCharacters(in: .whitespacesAndNewlines); requestID = UUID(); attempts = 0
        await run()
    }
    public var canRetry: Bool {
        isCurrent && grants().chatAllowed && !sending && requestID != nil && attempts < 3 && (retryAt ?? .distantPast) <= Date() && (reply?.canRetry == true || failure == .unknownOutcome)
    }
    public func retry() async { guard canRetry else { return }; await run() }
    public func abandon() { guard !sending else { return }; requestID = nil; retryAt = nil; reply = nil; message = nil; failure = nil; onChange?() }
    public func invalidate() { active = false; generation += 1; reply = nil; message = nil; requestID = nil; retryAt = nil; failure = nil; sending = false; onChange?() }
    private func run() async {
        guard isCurrent, grants().chatAllowed, let message, let requestID else { return }
        sending = true; attempts += 1; failure = nil; let stamp = generation; onChange?()
        do {
            let result = try await client.chat(message: message, requestID: requestID, scope: scope)
            guard isCurrent, generation == stamp, grants().chatAllowed, !Task.isCancelled else { invalidate(); return }
            reply = result
            retryAt = Date().addingTimeInterval(TimeInterval(max(0, result.retryAfterSeconds ?? 0)))
            if !result.canRetry { self.requestID = nil }
        } catch {
            guard isCurrent, generation == stamp, !Task.isCancelled else { invalidate(); return }
            failure = error as? MerchantNPCFailure ?? .unknownOutcome
            if failure == .malformed { failure = .unknownOutcome }
            if failure != .unknownOutcome { self.requestID = nil }
        }
        sending = false; onChange?()
    }
}

@MainActor public final class MerchantNPCResourcesCoordinator {
    public let scope: MerchantNPCScope
    private let currentScope: () -> MerchantNPCScope?
    private let grants: () -> MerchantNPCGrants
    private let client: MerchantNPCHTTPClient
    public let reader: any MerchantOperationsReading
    public var onChange: (() -> Void)?
    public private(set) var resources: MerchantAssetResources?
    public private(set) var script: MerchantNPCVoiceScript?
    public private(set) var review: MerchantNPCResourceReview?
    public private(set) var outcome: MerchantNPCResourceOutcome = .idle
    public private(set) var failure: MerchantNPCFailure?
    public private(set) var refreshing = false
    private var generation = 0
    private var active = true
    private var readScope: UUID?
    private var confirmationGeneration = 0
    private let journal: any OperationPendingJournal
    private var ownerKey: String { "merchant-npc:\(scope.namespace.utf8.count):\(scope.namespace):account:\(scope.accountID)" }
    private var targetKey: String { "resources:merchant-row:\(scope.merchantRowID.rawValue)" }
    /// Epoch/access revision are deliberately absent: login and coordinator recreation cannot erase uncertainty.
    public var hasUnresolvedWrite: Bool {
        do { return try journal.pending(ownerKey: ownerKey, targetKey: targetKey) != nil }
        catch { return true }
    }
    private var hasWriteAuthority: Bool { scope.accountID > 0 && !scope.namespace.isEmpty && isCurrent && !refreshing && readScope == reader.scope && !hasUnresolvedWrite }
    private func revokeWriteAuthority() {
        readScope = nil; script = nil; review = nil
        if outcome == .reviewed { outcome = .idle }
    }
    public init(scope: MerchantNPCScope, client: MerchantNPCHTTPClient, reader: any MerchantOperationsReading, journal: any OperationPendingJournal = OperationDefaultsJournal(defaults: .standard), currentScope: @escaping () -> MerchantNPCScope?, grants: @escaping () -> MerchantNPCGrants) {
        self.scope = scope; self.client = client; self.reader = reader; self.journal = journal; self.currentScope = currentScope; self.grants = grants
        if hasUnresolvedWrite { outcome = .unknown }
    }
    public var isCurrent: Bool { active && currentScope() == scope && reader.isAuthenticated }
    public var shouldPoll: Bool { isCurrent && (resources?.voice.voiceStatus == 1 || resources?.avatar.job?.status == "PENDING") }
    public var canEnroll: Bool { hasWriteAuthority && grants().resourceAllowed && grants().voiceCloning && script?.isUsable == true && resources?.voice.voiceStatus != 1 }
    public var canGenerate: Bool { hasWriteAuthority && grants().resourceAllowed && resources?.avatar.available == true && resources?.avatar.job?.status != "PENDING" }
    public func refresh() async {
        guard isCurrent, !refreshing, outcome != .sending else { return }
        revokeWriteAuthority()
        refreshing = true; let stamp = generation; let captured = reader.scope; onChange?()
        do {
            let access = try await reader.access()
            guard isCurrent, reader.scope == captured, generation == stamp, !Task.isCancelled else { invalidate(); return }
            guard access.identity.merchantID == scope.merchantRowID.rawValue, access.allows(.assets) else { throw MerchantNPCFailure.staleScope }
            let document = try await reader.document(.assets)
            guard isCurrent, reader.scope == captured, generation == stamp, !Task.isCancelled else { invalidate(); return }
            if case .assets(let value) = document { resources = value; failure = nil }
            else { throw MerchantNPCFailure.malformed }
            // Script availability must come from the server, never inferred from voiceStatus.
            if grants().chatAllowed {
                let value = try await client.voiceScript(scope: scope)
                guard isCurrent, reader.scope == captured, generation == stamp, !Task.isCancelled else { invalidate(); return }
                script = value
            }
            readScope = captured
        } catch {
            guard isCurrent, reader.scope == captured, generation == stamp, !Task.isCancelled else { invalidate(); return }
            // Failed refresh preserves display-only status, never write authority or a pending review.
            revokeWriteAuthority()
            failure = error as? MerchantNPCFailure ?? .unknownOutcome
        }
        refreshing = false; onChange?()
    }
    public func prepare(_ action: MerchantNPCResourceAction, ownsVoice: Bool, explicitConsent: Bool) throws {
        guard hasWriteAuthority, outcome != .unknown, outcome != .sending, explicitConsent else { throw MerchantNPCFailure.reviewRequired }
        switch action {
        case .enroll(let samples, _):
            guard canEnroll, ownsVoice, samples.count == 5, Set(samples.map(\.selectionID)).count == 5 else { throw MerchantNPCFailure.invalid }
            for (index, sample) in samples.enumerated() {
                guard sample.scope == scope, sample.kind == .voiceSample(index: index) else { throw MerchantNPCFailure.invalid }
            }
        case .revoke:
            guard grants().chatAllowed, grants().resourceOwnership, resources != nil else { throw MerchantNPCFailure.disabled }
        case .avatar(let image, let style):
            guard canGenerate, image.scope == scope, image.kind == .avatarImage, resources?.avatar.styles.contains(style) == true else { throw MerchantNPCFailure.invalid }
        }
        confirmationGeneration += 1
        review = .init(id: UUID(), scope: scope, action: action, ownsVoice: ownsVoice, explicitConsent: explicitConsent, script: script)
        outcome = .reviewed; failure = nil; onChange?()
    }
    public func discardReview() {
        // Editable consent/ownership/style changes must cancel an in-flight revalidation too.
        confirmationGeneration += 1; review = nil
        if outcome == .reviewed { outcome = .idle }
        onChange?()
    }
    public func confirm(_ id: UUID) async {
        guard let value = review, value.id == id, value.scope == scope, hasWriteAuthority, outcome == .reviewed else { return }
        let stamp = generation; let captured = reader.scope; let confirmationStamp = confirmationGeneration
        // This authoritative read revokes the old review before awaiting. No stale permission,
        // provider availability, style or script can authorize the following mutation.
        await refresh()
        guard isCurrent, reader.scope == captured, generation == stamp, !Task.isCancelled,
              hasWriteAuthority, confirmationGeneration == confirmationStamp, value.script == script else { return }
        do { try prepare(value.action, ownsVoice: value.ownsVoice, explicitConsent: value.explicitConsent) }
        catch { failure = error as? MerchantNPCFailure ?? .disabled; review = nil; outcome = .rejected; onChange?(); return }
        let record = OperationPendingRecord(ownerKey: ownerKey, targetKey: targetKey)
        do {
            guard !hasUnresolvedWrite else { throw MerchantNPCFailure.unknownOutcome }
            // Mandatory write-ahead lock. Failure/corruption stops before transport.
            try journal.write(record)
        } catch {
            review = nil; outcome = .unknown; failure = .unknownOutcome; onChange?(); return
        }
        outcome = .sending; review = nil; readScope = nil; onChange?()
        do {
            let receipt = try await client.perform(value.action, scope: scope)
            guard isCurrent, reader.scope == captured, generation == stamp, !Task.isCancelled else { invalidate(); return }
            try journal.clear(record)
            outcome = .accepted(receipt)
        } catch {
            guard isCurrent, reader.scope == captured, generation == stamp, !Task.isCancelled else { invalidate(); return }
            failure = error as? MerchantNPCFailure ?? .unknownOutcome
            let ambiguous = failure == .unknownOutcome || failure == .malformed
            if !ambiguous {
                do { try journal.clear(record) }
                catch { failure = .unknownOutcome }
            }
            outcome = ambiguous || hasUnresolvedWrite ? .unknown : .rejected
        }
        onChange?()
        await refresh()
    }
    public func invalidate() {
        active = false; generation += 1; revokeWriteAuthority(); resources = nil; refreshing = false; failure = nil
        // Never clear the durable journal on close, background, signout or epoch change.
        outcome = hasUnresolvedWrite ? .unknown : .idle; onChange?()
    }
}
