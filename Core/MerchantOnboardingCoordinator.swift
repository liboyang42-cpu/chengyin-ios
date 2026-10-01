import Foundation

public enum MerchantOnboardingLoad: Equatable {
    case idle, loading, loaded(MerchantOnboardingSnapshot), unavailable
}
public enum MerchantOnboardingIdentityGate: Equatable { case unchecked, checking, registered, required, unavailable }
public enum MerchantOnboardingSubmission: Equatable {
    case idle, awaitingConfirmation, checking, submitting, acknowledged, outcomeUnknown, notSent
    case rejected(MerchantOnboardingFailure)
    public var isLocked: Bool {
        switch self {
        case .awaitingConfirmation, .checking, .submitting, .acknowledged, .outcomeUnknown: return true
        default: return false
        }
    }
}
public struct MerchantOnboardingConfirmation: Equatable {
    public let id: UUID
    public let identity: ProfileReadIdentity
    public let draft: MerchantOnboardingDraft
    fileprivate init(identity: ProfileReadIdentity, draft: MerchantOnboardingDraft) {
        id = UUID(); self.identity = identity; self.draft = draft
    }
}
public enum MerchantOnboardingBlock: Error, Equatable {
    case unavailable, accountChanged, busy, invalidDraft, statusRequired, identityRequired, invalidConfirmation
}

/// Retain for the session owner's lifetime, not the screen's. PII-free unresolved-operation
/// locks survive navigation and same-account relogin in memory; drafts/readbacks never do.
/// No disk storage, automatic resend, polling, optimistic approval or role elevation.
@MainActor
public final class MerchantOnboardingCoordinator {
    private let server: any MerchantOnboardingServing
    private var loadedIdentity: ProfileReadIdentity?
    private var generation: UInt64 = 0
    private var pending: MerchantOnboardingConfirmation?
    private var locks: [Int: MerchantOnboardingSubmission] = [:]
    public private(set) var loadState: MerchantOnboardingLoad = .idle
    public private(set) var identityGate: MerchantOnboardingIdentityGate = .unchecked
    public private(set) var submission: MerchantOnboardingSubmission = .idle
    public private(set) var isUploading = false
    public var identity: ProfileReadIdentity? { server.identity }
    public var isConfigured: Bool { server.isConfigured }
    public init(server: any MerchantOnboardingServing) { self.server = server }

    public func synchronizeSession() {
        guard loadedIdentity != identity else { return }
        generation &+= 1; pending = nil; loadState = .idle; identityGate = .unchecked; isUploading = false
        loadedIdentity = identity
        submission = identity.flatMap { locks[$0.accountID] } ?? .idle
    }
    public func load() async {
        synchronizeSession()
        guard server.isConfigured, let identity else { loadState = .unavailable; return }
        guard submission != .checking && submission != .submitting && !isUploading else { return }
        if submission == .acknowledged, locks[identity.accountID] == nil { submission = .idle }
        generation &+= 1
        if identityGate == .checking { identityGate = .unchecked }
        let request = generation
        loadState = .loading
        do {
            let value = try await server.application(expectedIdentity: identity)
            guard self.identity == identity, generation == request, !Task.isCancelled else { return }
            loadState = .loaded(value)
            if submission == .acknowledged, case .application(let application) = value, !application.canReapply {
                // A definitive non-editable server state resolves an acknowledged dispatch.
                // Keep the acknowledgement visible now; a later read can expose a newly rejected application.
                // Unknown outcomes never pass through this branch and never lose their resend lock.
                locks[identity.accountID] = nil
            }
        } catch {
            guard self.identity == identity, generation == request else { return }
            loadState = .unavailable
        }
    }
    public func checkIdentity() async {
        synchronizeSession()
        guard let identity, identityGate != .checking else { return }
        let request = generation
        identityGate = .checking
        do {
            let registered = try await server.identityRegistered(expectedIdentity: identity)
            guard self.identity == identity, generation == request, !Task.isCancelled else { return }
            identityGate = registered ? .registered : .required
        } catch {
            guard self.identity == identity, generation == request else { return }
            identityGate = .unavailable
        }
    }
    private func permits(_ draft: MerchantOnboardingDraft, snapshot: MerchantOnboardingSnapshot) -> Bool {
        switch snapshot {
        case .none: return draft.id == nil
        case .application(let application): return application.canReapply && draft.id == application.id
        }
    }
    /// Only called by the explicit upload action. Selection alone never uploads.
    public func uploadLicense(_ image: MerchantOnboardingImage, expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingLicense {
        synchronizeSession()
        guard server.isConfigured else { throw MerchantOnboardingBlock.unavailable }
        guard identity == expectedIdentity else { throw MerchantOnboardingBlock.accountChanged }
        guard !submission.isLocked, !isUploading else { throw MerchantOnboardingBlock.busy }
        guard identityGate == .registered else { throw MerchantOnboardingBlock.identityRequired }
        guard case .loaded(let snapshot) = loadState else { throw MerchantOnboardingBlock.statusRequired }
        if case .application(let application) = snapshot, !application.canReapply { throw MerchantOnboardingBlock.statusRequired }
        let request = generation
        isUploading = true
        defer { if identity == expectedIdentity, generation == request { isUploading = false } }
        let result = try await server.uploadLicense(image, expectedIdentity: expectedIdentity)
        guard identity == expectedIdentity, generation == request, !Task.isCancelled else { throw MerchantOnboardingWriteError.outcomeUnknown }
        return result
    }
    public func prepare(_ draft: MerchantOnboardingDraft) throws -> MerchantOnboardingConfirmation {
        synchronizeSession()
        guard server.isConfigured, let identity else { throw MerchantOnboardingBlock.unavailable }
        guard !submission.isLocked, !isUploading else { throw MerchantOnboardingBlock.busy }
        guard draft.blocker() == nil else { throw MerchantOnboardingBlock.invalidDraft }
        guard identityGate == .registered else { throw MerchantOnboardingBlock.identityRequired }
        guard case .loaded(let snapshot) = loadState, permits(draft, snapshot: snapshot) else {
            throw MerchantOnboardingBlock.statusRequired
        }
        let confirmation = MerchantOnboardingConfirmation(identity: identity, draft: draft)
        pending = confirmation; submission = .awaitingConfirmation
        return confirmation
    }
    public func cancel(_ confirmation: MerchantOnboardingConfirmation) {
        guard pending?.id == confirmation.id, submission == .awaitingConfirmation else { return }
        pending = nil; submission = .idle
    }
    /// A frozen confirmed form; repeated taps and changed server eligibility send nothing.
    public func confirm(_ confirmation: MerchantOnboardingConfirmation) async {
        synchronizeSession()
        guard pending == confirmation, submission == .awaitingConfirmation, identity == confirmation.identity else { return }
        let account = confirmation.identity.accountID
        guard !Task.isCancelled else { pending = nil; submission = .notSent; return }
        submission = .checking
        do {
            let latest = try await server.application(expectedIdentity: confirmation.identity)
            guard identity == confirmation.identity, pending?.id == confirmation.id else { return }
            guard !Task.isCancelled else { pending = nil; submission = .notSent; return }
            loadState = .loaded(latest)
            guard permits(confirmation.draft, snapshot: latest) else { pending = nil; submission = .notSent; return }
            let registered = try await server.identityRegistered(expectedIdentity: confirmation.identity)
            guard identity == confirmation.identity, pending?.id == confirmation.id else { return }
            guard !Task.isCancelled else { pending = nil; submission = .notSent; return }
            identityGate = registered ? .registered : .required
            guard registered else { pending = nil; submission = .notSent; return }
        } catch {
            guard identity == confirmation.identity, pending?.id == confirmation.id else { return }
            pending = nil; submission = .notSent; loadState = .unavailable; return
        }
        // Establish the lock BEFORE awaiting a mutation. Dismissal cannot cancel a server write.
        submission = .submitting; locks[account] = .outcomeUnknown
        do {
            try await server.submit(confirmation.draft, expectedIdentity: confirmation.identity)
            locks[account] = .acknowledged
            guard identity == confirmation.identity, pending?.id == confirmation.id, !Task.isCancelled else { return }
            pending = nil; submission = .acknowledged
            // Exactly one status read, never pretend a code=200 means approval or activation.
            await load()
        } catch {
            let next: MerchantOnboardingSubmission
            switch error as? MerchantOnboardingWriteError {
            case .notSent: next = .notSent; locks[account] = nil
            case .rejected(let failure): next = .rejected(failure); locks[account] = nil
            default: next = .outcomeUnknown; locks[account] = .outcomeUnknown
            }
            guard identity == confirmation.identity, pending?.id == confirmation.id else { return }
            pending = nil; submission = next
            // Unknown outcomes require an explicit status check, never an automatic retry.
        }
    }
    public func leaveScreen() {
        generation &+= 1; pending = nil; loadState = .idle; identityGate = .unchecked; isUploading = false
        if submission == .submitting, let loadedIdentity { locks[loadedIdentity.accountID] = .outcomeUnknown }
        submission = identity.flatMap { locks[$0.accountID] } ?? .idle
    }
}
