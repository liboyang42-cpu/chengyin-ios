import Foundation

/// An owner-only, per-NPC-page memory scratch draft. This class has no persistence,
/// submission, model, review or publication dependency and never edits legacy knowledge.
@MainActor public final class MerchantNPCKnowledgeDraftCoordinator {
    public enum Phase: Equatable { case closed, loading, editing, saving, unavailable }
    public enum Failure: String { case contextChanged, accessDenied, unavailable }
    public struct Scope: Equatable {
        /// MerchantOperationsSessionReader rotates this on account, namespace,
        /// session epoch/token and viewer-revision changes. It contains no credential.
        public let session: UUID
        public let merchantID: Int
    }
    public private(set) var phase: Phase = .closed
    public private(set) var failure: Failure?
    public private(set) var issues: [MerchantNPCKnowledgeIssue] = []
    public private(set) var scope: Scope?
    public private(set) var draft = MerchantNPCKnowledgeDraft()
    public private(set) var savedDraft: MerchantNPCKnowledgeDraft?
    public private(set) var savedThisEdit = false
    private let reader: any MerchantOperationsReading
    private let isContextCurrent: () -> Bool
    private var generation = UUID()
    public init(reader: any MerchantOperationsReading, isContextCurrent: @escaping () -> Bool = { true }) {
        self.reader = reader; self.isContextCurrent = isContextCurrent
    }
    public var isCurrent: Bool {
        guard let scope else { return false }
        return reader.isAuthenticated && reader.scope == scope.session && isContextCurrent()
    }
    public var canEdit: Bool { phase == .editing && isCurrent }
    public var isDirty: Bool { draft != (savedDraft ?? .init()) }

    /// Reopening reads current merchant authority before exposing any retained memory.
    public func open() async {
        guard phase == .closed || phase == .unavailable else { return }
        guard reader.isAuthenticated, reader.isConfigured, isContextCurrent() else { invalidate(); return }
        let session = reader.scope
        if scope?.session != session { clearMemory() }
        let operation = UUID(); generation = operation
        phase = .loading; failure = nil; issues = []; draft = .init(); savedThisEdit = false
        do {
            let access = try await reader.access()
            guard operation == generation else { return }
            guard !Task.isCancelled, reader.scope == session, reader.isAuthenticated, isContextCurrent() else { invalidate(); return }
            guard access.identity.isOwner, access.allows(.character), let merchantID = access.identity.merchantID else {
                fail(.accessDenied); return
            }
            let fresh = Scope(session: session, merchantID: merchantID)
            if scope != fresh { clearMemory() }
            scope = fresh; draft = savedDraft ?? .init(); phase = .editing
        } catch {
            guard operation == generation else { return }
            guard reader.scope == session, reader.isAuthenticated, isContextCurrent(), !Task.isCancelled else { invalidate(); return }
            fail(.unavailable)
        }
    }
    public func edit(_ value: MerchantNPCKnowledgeDraft) {
        guard canEdit else { if !isCurrent { invalidate() }; return }
        draft = value; savedThisEdit = false; issues = []; failure = nil
    }
    /// Validates locally, then rechecks current owner/merchant. No draft text is sent
    /// by access/me; the only result is an in-memory copy, not a backend revision.
    public func saveLocally() async {
        guard canEdit, let expected = scope else { if !isCurrent { invalidate() }; return }
        issues = draft.validationIssues
        guard issues.isEmpty else { savedThisEdit = false; return }
        let value = draft, operation = UUID(); generation = operation
        phase = .saving; failure = nil; savedThisEdit = false
        do {
            let access = try await reader.access()
            guard operation == generation else { return }
            guard !Task.isCancelled, isCurrent, scope == expected else { invalidate(); return }
            guard access.identity.isOwner, access.allows(.character), access.identity.merchantID == expected.merchantID else {
                fail(.accessDenied); return
            }
            savedDraft = value; phase = .editing; savedThisEdit = true
        } catch {
            guard operation == generation else { return }
            guard isCurrent, !Task.isCancelled else { invalidate(); return }
            // A failed authority refresh hides and discards local content; it is not
            // permission to keep editing an unverified merchant snapshot.
            fail(.unavailable)
        }
    }
    /// Cancel drops unsaved edits; a validated memory copy can be reopened only
    /// inside the same still-current NPC page after a new authority read.
    public func cancel() {
        generation = UUID()
        if !isCurrent { clearMemory() }
        draft = .init(); issues = []; failure = nil; savedThisEdit = false; phase = .closed
    }
    /// The containing page calls this on disappearance, background, account/session
    /// changes or parent-document replacement. Reopening then starts empty.
    public func invalidate() {
        generation = UUID(); clearMemory(); phase = .unavailable; failure = .contextChanged
    }
    private func fail(_ value: Failure) {
        generation = UUID(); clearMemory(); phase = .unavailable; failure = value
    }
    private func clearMemory() {
        scope = nil; savedDraft = nil; draft = .init(); issues = []; savedThisEdit = false
    }
}
