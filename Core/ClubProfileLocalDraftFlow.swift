import Foundation
import Combine

/// Runtime-only identity/epoch/viewer fence. Credentials are neither copied into
/// this context nor persisted. Returning to the same account still needs a fresh read.
@MainActor public struct ClubProfileLocalDraftContext {
    public let store: ClubProfileLocalDraftStore
    public let namespace: String
    public let identity: ClubReadIdentity
    public let viewerRevision: UInt64
    private let current: () -> Bool
    public init(store: ClubProfileLocalDraftStore, namespace: String, identity: ClubReadIdentity,
                viewerRevision: UInt64, current: @escaping () -> Bool) {
        self.store = store; self.namespace = namespace; self.identity = identity
        self.viewerRevision = viewerRevision; self.current = current
    }
    public var isCurrent: Bool { identity.isSignedIn && current() }
}
public struct ClubProfileLocalDraftDifference: Identifiable {
    public let id: String
    public let saved: String
    public let current: String
}

/// This owner only manages user drafts. It consumes, never changes, the original
/// writer's exact classification. An equal server read alone cannot resolve UNKNOWN.
@MainActor public final class ClubProfileLocalDraftFlow: ObservableObject {
    public enum State: Equatable {
        case inactive, unavailable, ready, offered, editing, conflict, corrupt, storageChanged
        case awaitingOriginalResult, acknowledgedNeedsReadback, saved
    }
    @Published public private(set) var state: State = .inactive
    @Published public private(set) var differences: [ClubProfileLocalDraftDifference] = []
    @Published public private(set) var mediaRequiresSelection = false
    @Published public private(set) var restored = false
    public private(set) var profile: ClubOperationsProfile?
    public private(set) var reconciledReviewID: UUID?
    private var context: ClubProfileLocalDraftContext?
    private var scope: ClubProfileLocalDraftScope?
    private var observed: ClubProfileLocalDraftSnapshot?
    private var editBase: ClubProfileLocalDraftBaseline?
    public init() {}
    public var isCurrent: Bool { context?.isCurrent == true }
    public var blocksEditing: Bool {
        switch state { case .ready, .editing, .saved: return !isCurrent; default: return true }
    }
    public var canRestore: Bool { isCurrent && state == .offered }
    public var canDiscard: Bool {
        isCurrent && observed?.record != nil && state != .corrupt && state != .storageChanged && state != .unavailable
    }
    public var hasRetainedDraft: Bool { observed?.record != nil }
    public func hasPersisted(_ value: ClubOperationsDraft) -> Bool {
        guard isCurrent, let context, let scope, let observed,
              observed.record?.form.exactlyMatches(.init(value)) == true else { return false }
        do { try context.store.verify(observed, scope: scope); return true }
        catch { fail(error); return false }
    }
    public func retire() {
        context = nil; scope = nil; observed = nil; editBase = nil; profile = nil
        differences = []; restored = false; mediaRequiresSelection = false; reconciledReviewID = nil; state = .inactive
    }
    /// Called only after a fresh original detail read. Never restores or submits.
    @discardableResult public func begin(profile: ClubOperationsProfile, context: ClubProfileLocalDraftContext?) -> Bool {
        retire()
        guard let context, context.isCurrent, let account = context.identity.accountID, profile.club.canGovern, !profile.club.viewerIdentityUnavailable,
              let scope = try? ClubProfileLocalDraftScope(namespace: context.namespace, accountID: account, clubID: profile.club.id) else {
            state = .unavailable; return false
        }
        self.context = context; self.scope = scope; self.profile = profile; editBase = .init(profile)
        do {
            let found = try context.store.read(scope)
            guard context.isCurrent else { retire(); return false }
            observed = found
            guard let record = found.record else { state = .ready; return false }
            if let attempt = record.attempt {
                if attempt.result == .acknowledged {
                    state = .acknowledgedNeedsReadback
                    return reconcile(profile)
                }
                state = .awaitingOriginalResult; compare(record.form, profile); return false
            }
            if record.baseline.matches(profile) { state = .offered }
            else { state = .conflict; compare(record.form, profile) }
        } catch { fail(error) }
        return false
    }
    public func restore() -> ClubOperationsDraft? {
        guard canRestore, let context, let scope, let observed, let profile, let record = observed.record,
              record.attempt == nil, record.baseline.matches(profile) else { return nil }
        do {
            try context.store.verify(observed, scope: scope)
            guard context.isCurrent else { retire(); return nil }
            state = .editing; restored = true; editBase = record.baseline
            let value = record.form.restoring(against: profile)
            mediaRequiresSelection = value.logo != (profile.club.logo ?? "") || value.cover != (profile.club.cover ?? "")
            return value
        } catch { fail(error); return nil }
    }
    /// Immediate synchronous persistence on every binding change and before leave.
    /// Invalid/incomplete typing is retained; submission still uses original validation.
    @discardableResult public func retryPersistence(_ value: ClubOperationsDraft) -> Bool {
        guard isCurrent, observed?.record?.attempt == nil,
              state == .unavailable || state == .storageChanged else { return false }
        return persist(value, recoveringStorage: true)
    }
    @discardableResult public func persist(_ value: ClubOperationsDraft, recoveringStorage: Bool = false) -> Bool {
        let mayRetry = recoveringStorage && isCurrent && observed?.record?.attempt == nil && (state == .unavailable || state == .storageChanged)
        guard !blocksEditing || mayRetry, let context, let scope, let observed, let profile, let editBase else { return false }
        do {
            // A URL is never supplied by a text field or recovered into an upload grant.
            // New staged references must be either the retained protected draft or
            // backed by the installed upload owner's receipt for this original profile.
            for (field, reference, original, receipt) in [
                (ClubProfileMediaField.logo, value.logo, profile.club.logo ?? "", value.logoUpload),
                (.cover, value.cover, profile.club.cover ?? "", value.coverUpload)
            ] {
                let retained = field == .logo ? observed.record?.form.logo : observed.record?.form.cover
                guard reference == original || reference == retained ||
                    (receipt?.field == field && receipt?.reference == reference && receipt?.scope.identity == context.identity &&
                     receipt?.scope.target == .club(scope.clubID) && receipt?.scope.source == profile) else {
                    throw ClubProfileLocalDraftIssue.changed
                }
            }
            let form = ClubProfileLocalDraftForm(value)
            if editBase.form.exactlyMatches(form) {
                if observed.record == nil { try context.store.verify(observed, scope: scope); return true }
                self.observed = try context.store.replace(nil, scope: scope, expected: observed)
                state = .ready
            } else {
                var record = ClubProfileLocalDraftRecord(scope: scope, profile: profile, form: form)
                record.baseline = editBase
                self.observed = try context.store.replace(record, scope: scope, expected: observed)
                state = .editing
            }
            mediaRequiresSelection = (value.logo != (profile.club.logo ?? "") && value.logoUpload == nil) ||
                (value.cover != (profile.club.cover ?? "") && value.coverUpload == nil)
            return true
        } catch { fail(error); return false }
    }
    /// Explicit local discard only. Caller must read the original source again.
    /// Never touches old/UNKNOWN writer intents, even if current fields happen to match.
    @discardableResult public func discard() -> Bool {
        guard canDiscard, let context, let scope, let observed else { return false }
        do {
            self.observed = try context.store.replace(nil, scope: scope, expected: observed)
            state = .inactive; differences = []; mediaRequiresSelection = false; restored = false; return true
        } catch { fail(error); return false }
    }
    public func verifyForReview(_ value: ClubOperationsDraft, original: ClubOperationsProfile) throws {
        guard !blocksEditing, let context, let scope, let observed, let editBase,
              editBase.matches(original), observed.record?.attempt == nil,
              observed.record?.form.exactlyMatches(.init(value)) == true else { throw ClubOperationsBlock.changed }
        do { try context.store.verify(observed, scope: scope) }
        catch { fail(error); throw ClubOperationsBlock.changed }
    }
    public func observeUnconfirmedReadback(_ current: ClubOperationsProfile) {
        guard isCurrent, current.club.id == scope?.clubID, let record = observed?.record,
              record.attempt?.result == .awaitingOriginalResult else { return }
        compare(record.form, current)
        // Equal fields are NOT an original terminal receipt; retain the unknown fence.
        state = .awaitingOriginalResult
    }
    public func compareFresh(_ current: ClubOperationsProfile) {
        guard isCurrent, let record = observed?.record else { return }
        if !record.baseline.matches(current) { state = .conflict; profile = current; compare(record.form, current) }
    }
    /// Durable fence before entering the existing confirmation chain. A crash here
    /// is deliberately unresolved, never proof of dispatch or permission to resend.
    public func beginSubmission(_ review: ClubOperationsReview) -> Bool {
        guard case .update(let draft, let original) = review.command,
              review.identity == context?.identity, review.target == .club(original.club.id),
              let context, let scope, let observed, var record = observed.record else { return false }
        do {
            try verifyForReview(draft, original: original)
            record.attempt = .init(reviewID: review.id, submitted: ClubProfileLocalDraftForm(draft).submitted(against: original), result: .awaitingOriginalResult)
            self.observed = try context.store.replace(record, scope: scope, expected: observed)
            state = .awaitingOriginalResult; return true
        } catch { fail(error); return false }
    }
    /// Synchronous observer runs after original classification, before any readback await.
    /// Failure preserves the previous pending marker and cannot claim cleanup success.
    public func receiveOriginalResult(_ result: ClubOperationsState, review: ClubOperationsReview) {
        guard isCurrent, review.identity == context?.identity, let context, let scope, let observed,
              var record = observed.record, record.attempt?.reviewID == review.id else { return }
        switch result {
        case .acknowledged:
            if record.attempt?.result == .acknowledged { state = .acknowledgedNeedsReadback; return }
            record.attempt?.result = .acknowledged
        case .notSent, .rejected: record.attempt = nil
        default: state = .awaitingOriginalResult; return
        }
        do {
            self.observed = try context.store.replace(record, scope: scope, expected: observed)
            state = record.attempt == nil ? .editing : .acknowledgedNeedsReadback
        } catch { fail(error) }
    }
    /// Exact ACK plus fresh matching fields/current role is required. Never infer a
    /// successful write from a read, and never remove another editor's newer envelope.
    @discardableResult public func reconcile(_ current: ClubOperationsProfile) -> Bool {
        guard isCurrent, let context, let scope, let observed, let record = observed.record,
              let attempt = record.attempt, attempt.result == .acknowledged,
              current.club.id == scope.clubID else { return false }
        guard record.baseline.sameRole(current), attempt.submitted.matchesReadback(current) else {
            state = .conflict; profile = current; compare(record.form, current); return false
        }
        do {
            self.observed = try context.store.replace(nil, scope: scope, expected: observed)
            profile = current; editBase = .init(current); state = .saved; differences = []; reconciledReviewID = attempt.reviewID
            mediaRequiresSelection = false; restored = false; return true
        } catch { fail(error); return false }
    }
    private func fail(_ error: Error) {
        switch error { case ClubProfileLocalDraftIssue.corrupt: state = .corrupt
        case ClubProfileLocalDraftIssue.changed: state = .storageChanged
        case ClubOperationsBlock.changed: state = .conflict
        default: state = .unavailable }
    }
    private func compare(_ local: ClubProfileLocalDraftForm, _ profile: ClubOperationsProfile) {
        let current = ClubProfileLocalDraftForm(ClubOperationsDraft(profile: profile))
        let rows: [(String, String, String)] = [
            ("name", local.name, current.name), ("clubType", local.clubType, current.clubType),
            ("activityPrefs", local.activityPrefs.joined(separator: "、"), current.activityPrefs.joined(separator: "、")),
            ("city", local.city, current.city), ("keywords", local.keywords, current.keywords),
            ("style", local.style, current.style), ("description", local.description, current.description),
            ("logo", local.logo == current.logo ? "" : "localDraft.savedImage", "localDraft.currentImage"),
            ("cover", local.cover == current.cover ? "" : "localDraft.savedImage", "localDraft.currentImage"),
            ("prioritySignupEnabled", local.prioritySignupEnabled ? "1" : "0", current.prioritySignupEnabled ? "1" : "0"),
            ("memberReservedQuota", local.memberReservedQuota, current.memberReservedQuota),
            ("joinPolicy", String(local.joinPolicy), String(current.joinPolicy))
        ]
        differences = rows.compactMap { field, saved, latest in
            if field == "logo" || field == "cover" { return saved.isEmpty ? nil : .init(id: field, saved: saved, current: latest) }
            return saved.utf8.elementsEqual(latest.utf8) ? nil : .init(id: field, saved: saved, current: latest)
        }
    }
}

/// Bound to the original writer receipt AND a subsequent source read, not copied
/// submitted data. The presentation forwards this only when its sheet returns.
public struct ClubProfileConfirmedReturn: Equatable {
    public let identity: ClubReadIdentity
    public let clubID: Int
    public let receiptID: UUID
    public init(identity: ClubReadIdentity, clubID: Int, receiptID: UUID) {
        self.identity = identity; self.clubID = clubID; self.receiptID = receiptID
    }
}
