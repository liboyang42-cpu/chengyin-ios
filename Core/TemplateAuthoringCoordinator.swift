import Foundation

public struct TemplateAuthoringReview: Equatable, Identifiable {
    public let id: UUID
    public let request: TemplateAuthoringRequest
    public let draft: TemplateAuthoringDraft?
    public let title: String
    fileprivate let session: TemplateAuthoringSession
    fileprivate let identity: TemplateAuthoringIdentity
    fileprivate let generation: Int
}
/// The host retains this coordinator and supplies a fresh session after account, role,
/// token or regional changes. A fresh review is required for every mutation.
@MainActor public final class TemplateAuthoringCoordinator {
    public enum State: Equatable { case idle, editing, reviewing, submitting, simulated, acknowledged, uncertain, blocked }
    private let adapter: TemplateAuthoringAdapter
    private let store: TemplateAuthoringLocalStore
    private let currentSession: () -> TemplateAuthoringSession?
    private var captured: TemplateAuthoringSession?
    private var generation = 0
    public private(set) var state: State = .idle
    public private(set) var identity = TemplateAuthoringIdentity()
    public private(set) var draft = TemplateAuthoringDraft()
    public private(set) var restore: TemplateAuthoringRestore = .missing
    public private(set) var review: TemplateAuthoringReview?
    public private(set) var pending: TemplateAuthoringPending?
    public private(set) var rows: [DiscoveryPlayTemplate] = []
    public private(set) var messageKey: String?
    public private(set) var shelfReview: TemplateOwnShelfReview?
    public private(set) var shelfPending: TemplateOwnShelfPending?
    public private(set) var shelfBusy = false
    public private(set) var shelfBlocked = false
    public private(set) var shelfMessageKey: String?
    private var shelfGeneration = 0
    public var shelfLocked: Bool { shelfBusy || shelfBlocked || shelfPending != nil }
    public lazy var shelfReader = TemplateOwnShelfReader(adapter: adapter, currentSession: currentSession)
    public var session: TemplateAuthoringSession? { currentSession() }
    public var savedDraft: TemplateAuthoringSavedDraft? {
        guard state == .acknowledged, let session = captured, currentSession() == session,
              let pending, pending.identity == identity, let saved = pending.savedDraft, saved.matches(pending, session: session) else { return nil }
        return saved
    }
    /// Explicit user action only. Keep the old acknowledged receipt/journal; unknown locks never reset.
    @discardableResult public func beginNewDraft(after saved: TemplateAuthoringSavedDraft) -> Bool {
        guard savedDraft == saved, let session = captured, currentSession() == session else { return false }
        let stamp = generation
        do {
            guard try store.active(session: session) == identity, let pending,
                  try store.pending(session: session, identity: identity) == pending else { throw TemplateAuthoringError.storageUnavailable }
            let next = TemplateAuthoringIdentity(), empty = TemplateAuthoringDraft()
            try store.save(empty, session: session, identity: next)
            guard try store.active(session: session) == next,
                  case .ready(let verified) = store.load(session: session, identity: next),
                  ProjectEditPendingMaterials.exactData(verified.draft) == ProjectEditPendingMaterials.exactData(empty) else { throw TemplateAuthoringError.storageUnavailable }
            guard active(session, stamp) else { throw TemplateAuthoringError.changedSession }
            identity = next; draft = empty; self.pending = nil; review = nil; restore = .missing
            generation += 1; state = .editing; messageKey = nil; return true
        } catch { state = .blocked; messageKey = "templateAuthor.storageFailed"; return false }
    }
    public var canRead: Bool { adapter.canRead }
    public var canSubmit: Bool { adapter.canSubmit }
    public var canSimulate: Bool { adapter.canSimulate }
    public var locked: Bool { pending != nil || [.submitting, .uncertain, .simulated, .acknowledged, .blocked].contains(state) }
    public init(adapter: TemplateAuthoringAdapter? = nil, store: TemplateAuthoringLocalStore, currentSession: @escaping () -> TemplateAuthoringSession?) {
        self.adapter = adapter ?? .init(); self.store = store; self.currentSession = currentSession
    }
    public func synchronizeSession() {
        guard captured != currentSession() else { return }
        generation += 1; captured = currentSession(); state = .idle; identity = .init(); draft = .init()
        review = nil; pending = nil; rows = []; restore = .missing; messageKey = nil
        shelfGeneration += 1; shelfReview = nil; shelfPending = nil; shelfBusy = false; shelfBlocked = false; shelfMessageKey = nil
    }
    private func active(_ session: TemplateAuthoringSession, _ stamp: Int) -> Bool { currentSession() == session && captured == session && generation == stamp && !Task.isCancelled }
    public func open(seed: TemplateAuthoringDraft? = nil) {
        synchronizeSession()
        guard let session = captured else { messageKey = "templateAuthor.signIn"; return }
        guard state == .idle else { return }
        do {
            if let prior = try store.active(session: session) { identity = prior }
            restore = store.load(session: session, identity: identity)
            pending = try store.pending(session: session, identity: identity)
            if let pending {
                state = pending.terminal ? (pending.acknowledged == true ? .acknowledged : .simulated) : .uncertain
                messageKey = pending.terminal ? (pending.acknowledged == true ? "templateAuthor.acknowledged" : "templateAuthor.simulated") : "templateAuthor.uncertain"; return
            }
            if let seed { guard seed.id == nil else { throw TemplateAuthoringError.unavailable }; draft = seed }
            state = .editing
        } catch { state = .blocked; messageKey = "templateAuthor.storageFailed" }
    }
    public func restoreDraft() {
        synchronizeSession(); guard !locked, case .ready(let envelope) = restore else { return }
        draft = envelope.draft; restore = .missing; review = nil; state = .editing
    }
    public func discardLocal() {
        synchronizeSession(); guard let session = captured, !locked else { return }
        do { try store.discard(session: session, identity: identity); restore = .missing; draft = .init(); review = nil; generation += 1; state = .editing }
        catch { messageKey = "templateAuthor.storageFailed" }
    }
    public func change(_ next: TemplateAuthoringDraft) {
        synchronizeSession(); guard captured != nil, !locked, restore == .missing, next.id == nil else { return }
        draft = next; generation += 1; review = nil; state = .editing; messageKey = nil
    }
    public func saveLocal() {
        synchronizeSession(); guard let session = captured, !locked, restore == .missing else { return }
        do { try store.save(draft, session: session, identity: identity); messageKey = "templateAuthor.localSaved" }
        catch { messageKey = "templateAuthor.storageFailed" }
    }
    public func prepare(_ intent: TemplateAuthoringIntent) {
        synchronizeSession(); guard let session = captured, !locked, restore == .missing else { return }
        do {
            let request = try TemplateAuthoringContract.request(draft, intent: intent)
            review = .init(id: UUID(), request: request, draft: draft, title: draft.title, session: session, identity: identity, generation: generation)
            state = .reviewing; messageKey = canSimulate ? "templateAuthor.fixtureNotice" : canSubmit ? "templateAuthor.httpReview" : "templateAuthor.unavailable"
        } catch { messageKey = "templateAuthor.invalid" }
    }
    public func cancelReview() { review = nil; if state == .reviewing { state = .editing } }
    public func leaveScreen() { generation += 1; shelfGeneration += 1; shelfReview = nil; review = nil; if state == .reviewing { state = .editing } }
    public func confirm(_ value: TemplateAuthoringReview) async {
        synchronizeSession()
        guard !locked, review == value, value.session == currentSession(), value.identity == identity, value.generation == generation, value.draft == draft else { return }
        guard canSubmit else { cancelReview(); messageKey = "templateAuthor.unavailable"; return }
        let session = value.session; generation += 1; let stamp = generation; review = nil
        do {
            if let existing = try store.pending(session: session, identity: identity) { pending = existing; state = .uncertain; messageKey = "templateAuthor.uncertain"; return }
            // Both active pointer and full intent must survive before the transport is called.
            try store.save(draft, session: session, identity: identity)
            let intent = TemplateAuthoringPending(operationID: value.id, ownerKey: session.ownerKey, identity: identity, request: value.request, createdAt: Date())
            try store.savePending(intent, session: session)
            guard active(session, stamp) else {
                // Preserve the durable lock without restoring old-owner state into a new session.
                if currentSession() == session, captured == session, identity == value.identity {
                    pending = intent; state = .uncertain; messageKey = "templateAuthor.uncertain"
                }
                return
            }
            pending = intent; state = .submitting
            let submission = await adapter.submitWithReceipt(value.request)
            let outcome = submission.outcome
            guard active(session, stamp) else { return }
            switch outcome {
            case .simulated, .acknowledged:
                var terminal = intent; terminal.terminal = true; terminal.acknowledged = outcome == .acknowledged
                if outcome == .acknowledged, let id = submission.savedMemberTemplateID {
                    terminal.savedDraft = try .init(operationID: value.id, ownerKey: session.ownerKey, identity: identity, memberTemplateID: id, request: value.request)
                }
                try store.savePending(terminal, session: session); pending = terminal
                state = outcome == .acknowledged ? .acknowledged : .simulated; messageKey = outcome == .acknowledged ? "templateAuthor.acknowledged" : "templateAuthor.simulated"
            case .notSent, .unauthorized, .rejected:
                try store.clearPending(session: session, identity: identity); pending = nil; state = .editing
                switch outcome { case .unauthorized: messageKey = "templateAuthor.signIn"; case .rejected(let error): messageKey = error.messageKey; default: messageKey = "templateAuthor.unavailable" }
            case .uncertain: state = .uncertain; messageKey = "templateAuthor.uncertain"
            }
        } catch {
            guard active(session, stamp) else { return }
            state = pending == nil ? .blocked : .uncertain; messageKey = pending == nil ? "templateAuthor.storageFailed" : "templateAuthor.uncertain"
        }
    }
    public func loadMine() async {
        synchronizeSession(); guard let session = captured else { shelfMessageKey = "templateAuthor.signIn"; return }
        guard !shelfBusy else { return }
        shelfGeneration += 1; let stamp = shelfGeneration; shelfReview = nil
        do {
            shelfPending = try store.shelfPending(session: session)
            let result = try await adapter.listMine()
            guard shelfActive(session, stamp) else { return }
            try validateShelfRows(result); rows = result; shelfBlocked = false
            if let pending = shelfPending {
                if pending.matchesAcknowledgedReadback(result) {
                    try store.clearShelfPending(session: session); shelfPending = nil
                    shelfMessageKey = "templateAuthor.shelf.verified"
                } else { shelfMessageKey = "templateAuthor.shelf.unknown" }
            } else { shelfMessageKey = result.isEmpty ? "templateAuthor.shelf.empty" : nil }
        } catch {
            guard shelfActive(session, stamp) else { return }
            rows = []; shelfBlocked = true; shelfMessageKey = "templateAuthor.listUnavailable"
        }
    }
    private func shelfActive(_ session: TemplateAuthoringSession, _ stamp: Int) -> Bool {
        currentSession() == session && captured == session && shelfGeneration == stamp && !Task.isCancelled
    }
    private func validateShelfRows(_ values: [DiscoveryPlayTemplate]) throws {
        guard values.count <= 100, values.allSatisfy({ $0.id > 0 }), Set(values.map(\.id)).count == values.count else { throw TemplateAuthoringError.invalidContract }
    }
    public func prepareShelf(templateID: Int, action: TemplateOwnShelfAction) {
        synchronizeSession(); guard let session = captured, !shelfLocked,
            let row = rows.first(where: { $0.id == templateID }) else { return }
        do {
            shelfPending = try store.shelfPending(session: session)
            guard shelfPending == nil else { shelfMessageKey = "templateAuthor.shelf.unknown"; return }
            shelfReview = try .init(row: row, action: action, session: session, generation: shelfGeneration)
        } catch { shelfBlocked = true; shelfMessageKey = "templateAuthor.storageFailed" }
    }
    public func cancelShelfReview() { shelfReview = nil }
    public func leaveShelfScreen() { shelfGeneration += 1; shelfReview = nil; shelfBusy = false }
    public func confirmShelf(_ value: TemplateOwnShelfReview) async {
        synchronizeSession()
        guard !shelfLocked, shelfReview == value, value.session == captured,
              value.generation == shelfGeneration, canSubmit else { return }
        let session = value.session; let stamp = shelfGeneration
        shelfReview = nil; shelfBusy = true
        defer { if shelfGeneration == stamp { shelfBusy = false } }
        do {
            // Re-read the exact shelf immediately before dispatch. Never trust a stale row.
            let fresh = try await adapter.listMine()
            guard shelfActive(session, stamp) else { return }
            try validateShelfRows(fresh); rows = fresh
            guard fresh.first(where: { $0.id == value.templateID.rawValue }) == value.baseline else {
                shelfMessageKey = "templateAuthor.shelf.stale"; return
            }
            guard try store.shelfPending(session: session) == nil else {
                shelfPending = try store.shelfPending(session: session); shelfMessageKey = "templateAuthor.shelf.unknown"; return
            }
            var intent = TemplateOwnShelfPending(review: value)
            try store.saveShelfPending(intent, session: session); shelfPending = intent
            let outcome = await adapter.submit(value.request)
            guard shelfActive(session, stamp) else { return }
            switch outcome {
            case .simulated:
                // Synthetic fixtures never claim a real library change or deletion.
                try store.clearShelfPending(session: session); shelfPending = nil
                shelfMessageKey = "templateAuthor.simulated"
            case .acknowledged:
                intent.acknowledged = true
                try store.saveShelfPending(intent, session: session); shelfPending = intent
                let readback = try await adapter.listMine()
                guard shelfActive(session, stamp) else { return }
                try validateShelfRows(readback); rows = readback
                if intent.matchesAcknowledgedReadback(readback) {
                    try store.clearShelfPending(session: session); shelfPending = nil
                    shelfMessageKey = "templateAuthor.shelf.verified"
                } else { shelfMessageKey = "templateAuthor.shelf.unknown" }
            case .notSent, .unauthorized, .rejected:
                try store.clearShelfPending(session: session); shelfPending = nil
                switch outcome {
                case .unauthorized: shelfMessageKey = "templateAuthor.signIn"
                case .rejected(let error): shelfMessageKey = error.messageKey
                default: shelfMessageKey = "templateAuthor.unavailable"
                }
            case .uncertain: shelfMessageKey = "templateAuthor.shelf.unknown"
            }
        } catch {
            guard shelfActive(session, stamp) else { return }
            shelfBlocked = shelfPending == nil
            shelfMessageKey = shelfPending == nil ? "templateAuthor.shelf.preflightFailed" : "templateAuthor.shelf.unknown"
        }
    }
    // No source operation-receipt or reconciliation contract exists. Never clear an
    // uncertain mutation merely because /my-list contains a matching title.
}
