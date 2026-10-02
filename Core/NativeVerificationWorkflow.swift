import Foundation
import Observation

/// Only display metadata is public. QR bytes are memory-only, never Codable or journaled.
public struct NativeVerificationReview: Equatable, Identifiable {
    public let id: UUID
    public let kind: MerchantRedemptionContext.Kind
    public let merchantID: Int
    public let merchantName: String?
    public let choiceName: String?
    public let expiresAt: Date
    fileprivate let context: MerchantRedemptionContext
    fileprivate let scope: MerchantBusinessScope
    fileprivate let choice: MerchantRedemptionChoice.Target?
}
/// Composes existing exact redemption adapters and durable coarse target locks. Production
/// defaults remain disabled; a separately approved verification transport can supply dispatch.
@MainActor @Observable public final class NativeVerificationWorkflow {
    public enum Phase: String { case idle, loading, reviewing, submitting, choosing, result, unknown, disabled }
    public private(set) var phase: Phase = .idle
    public private(set) var review: NativeVerificationReview?
    public private(set) var result: MerchantRedemptionResult?
    public private(set) var issueKey: String?
    public private(set) var access: MerchantBusinessAccess?
    public private(set) var needsReadback = false
    public private(set) var loadedScope: MerchantBusinessScope?
    private let reader: any MerchantBusinessReading
    private let journal: any MerchantBusinessIntentStore
    private let redemption: MerchantRedemptionCoordinator?
    private let now: () -> Date
    private var context: MerchantRedemptionContext?
    private var generation: UInt64 = 0
    public var scope: MerchantBusinessScope? { reader.scope }
    public var current: Bool { loadedScope != nil && loadedScope == reader.scope }
    public var canCapture: Bool { current && !needsReadback && [.idle, .result, .disabled].contains(phase) && access?.allows("merchant:verify") == true }
    public var canConfirm: Bool { current && phase == .reviewing && review != nil && reader.canExecuteVerificationMutation && redemption != nil }
    public var canDispatch: Bool { reader.canExecuteVerificationMutation && redemption != nil }
    public init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore,
                redemption: MerchantRedemptionCoordinator?, now: @escaping () -> Date = Date.init) {
        self.reader = reader; self.journal = journal; self.redemption = redemption; self.now = now
    }
    public func activate() async {
        deactivate()
        generation &+= 1; let generation = generation, scope = reader.scope
        phase = .loading
        do {
            guard let scope else { throw APIError.unauthorized }
            let access = try await reader.access()
            guard self.generation == generation, reader.scope == scope, !Task.isCancelled else { return }
            try access.require(["merchant:verify"])
            self.access = access; loadedScope = scope
            needsReadback = try hasJournalLock(scope: scope, merchantID: access.merchantID)
            phase = needsReadback ? .unknown : .idle
        } catch {
            guard self.generation == generation, reader.scope == scope, !Task.isCancelled else { return }
            issueKey = key(error); phase = .idle
        }
    }
    public func prepare(raw: String) async {
        guard canCapture else { return }
        let capturedScope = reader.scope, capturedGeneration = generation
        phase = .loading; issueKey = nil; result = nil; context = nil; review = nil
        do {
            let parsed = try MerchantRedemptionContext.parse(raw)
            guard let capturedScope else { throw APIError.unauthorized }
            let fresh = try await reader.access()
            guard capturedGeneration == generation, capturedScope == reader.scope, !Task.isCancelled else { return }
            try fresh.require(["merchant:verify"])
            guard access?.merchantID == fresh.merchantID else { throw MerchantBusinessFailure.stale }
            needsReadback = try hasJournalLock(scope: capturedScope, merchantID: fresh.merchantID)
            guard !needsReadback else { phase = .unknown; return }
            access = fresh; context = parsed
            review = .init(id: UUID(), kind: parsed.kind, merchantID: fresh.merchantID, merchantName: fresh.name,
                choiceName: nil, expiresAt: now().addingTimeInterval(60), context: parsed, scope: capturedScope, choice: nil)
            phase = .reviewing
        } catch {
            guard capturedGeneration == generation, capturedScope == reader.scope, !Task.isCancelled else { return }
            issueKey = key(error); phase = .idle
        }
    }
    public func prepareChoice(_ target: MerchantRedemptionChoice.Target) {
        guard current, phase == .choosing, !needsReadback, let result, let context, let access, let scope,
              let choice = result.choices.first(where: { $0.target == target }) else { return }
        review = .init(id: UUID(), kind: context.kind, merchantID: access.merchantID, merchantName: access.name,
            choiceName: choice.name ?? choice.id, expiresAt: now().addingTimeInterval(60), context: context, scope: scope, choice: target)
        phase = .reviewing
    }
    public func cancelReview() {
        guard phase == .reviewing else { return }
        let wasChoice = review?.choice != nil
        review = nil; issueKey = nil
        if wasChoice { phase = .choosing }
        else { context = nil; phase = .idle }
    }
    public func confirm(_ value: NativeVerificationReview) async {
        guard current, review == value, value.scope == reader.scope, !needsReadback else { return }
        guard now() < value.expiresAt else { review = nil; issueKey = "verification.reviewExpired"; phase = value.choice == nil ? .idle : .choosing; if value.choice == nil { context = nil }; return }
        guard canDispatch, let redemption else { review = nil; phase = .disabled; issueKey = "verification.dispatchDisabled"; return }
        let capturedGeneration = generation
        review = nil; phase = .submitting; issueKey = nil
        do {
            if let choice = value.choice { try await redemption.choose(choice) }
            else { try await redemption.begin(value.context, expectedMerchantID: value.merchantID) }
            guard capturedGeneration == generation, value.scope == reader.scope, !Task.isCancelled else { return }
            guard let result = redemption.result else { throw MerchantBusinessFailure.unknown }
            self.result = result
            needsReadback = try hasJournalLock(scope: value.scope, merchantID: value.merchantID)
            phase = needsReadback ? .unknown : result.outcome == .needsChoice ? .choosing : .result
            if result.outcome != .needsChoice { context = nil }
        } catch {
            guard capturedGeneration == generation, value.scope == reader.scope, !Task.isCancelled else { return }
            needsReadback = (try? hasJournalLock(scope: value.scope, merchantID: value.merchantID)) ?? true
            phase = needsReadback ? .unknown : .result
            issueKey = key(error)
            if !needsReadback { context = nil }
        }
    }
    public func cancelChoice() { guard phase != .submitting else { return }; redemption?.cancelChoice(); context = nil; result = nil; review = nil; phase = needsReadback ? .unknown : .idle }
    public func deactivate() {
        generation &+= 1; redemption?.cancelChoice(); context = nil; review = nil; result = nil; access = nil
        loadedScope = nil; issueKey = nil; needsReadback = false; phase = .idle
        // Durable intent is deliberately untouched. A later ledger read cannot clear it.
    }
    private func hasJournalLock(scope: MerchantBusinessScope, merchantID: Int) throws -> Bool {
        try journal.intents().contains { $0.realm == scope.realm && $0.accountID == scope.accountID && $0.merchantID == merchantID && $0.target == "redemption" }
    }
    private func key(_ error: Error) -> String {
        if error as? APIError == .unauthorized { return "verification.login" }
        if error as? APIError == .notConfigured { return "verification.notConfigured" }
        if let failure = error as? MerchantBusinessFailure { return failure.key }
        if error as? MerchantRedemptionFailure == .unsupported { return "verification.unsupported" }
        return "verification.failed"
    }
}
