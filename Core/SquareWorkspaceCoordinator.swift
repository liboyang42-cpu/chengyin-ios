import Foundation
import Observation

public struct SquareWorkspaceReview: Equatable {
    public let id: UUID
    public let session: SquareWorkspaceSession
    public let draft: SquareWorkspaceDraft
    public let lane: SquareWorkspaceLane
    public let guideline: SquareWorkspaceGuideline?
    public let original: SquareWorkspacePost?
}
/// Default has no service and all grants off. Opening or editing never uploads, accepts terms, or posts.
@MainActor @Observable public final class SquareWorkspaceCoordinator {
    public private(set) var session: SquareWorkspaceSession
    public private(set) var local: [SquareWorkspaceLocalEntry] = []
    public private(set) var server: [SquareWorkspacePost] = []
    public private(set) var nextCursor: Int?
    public private(set) var hasMore = false
    public private(set) var review: SquareWorkspaceReview?
    public private(set) var busy = false
    public private(set) var status = "squareWorkspace.offline"
    public private(set) var lastPost: SquareWorkspacePost?
    public let grants: SquareWorkspaceGrants
    private let store: SquareWorkspaceStore
    private let service: SquareWorkspaceService?
    private let currentSession: () -> SquareWorkspaceSession?
    private let token: () -> String?
    private var usedReviews: Set<UUID> = []
    public init(session: SquareWorkspaceSession, store: SquareWorkspaceStore, service: SquareWorkspaceService? = nil,
                grants: SquareWorkspaceGrants = .init(), currentSession: @escaping () -> SquareWorkspaceSession?, token: @escaping () -> String? = { nil }) {
        self.session = session; self.store = store; self.service = service; self.grants = grants; self.currentSession = currentSession; self.token = token
    }
    private func check(_ expected: SquareWorkspaceSession) throws {
        guard expected == session, currentSession() == expected else {
            local = []; server = []; review = nil; lastPost = nil; status = "squareWorkspace.sessionChanged"
            throw SquareWorkspaceFailure.sessionChanged
        }
        try Task.checkCancellation()
    }
    private func connection() throws -> (SquareWorkspaceService, String) {
        try check(session)
        guard grants.live, let service, let token = token() else { throw SquareWorkspaceFailure.disabled }
        let captured = session
        return (service.scoped { [weak self] in guard let self else { throw SquareWorkspaceFailure.sessionChanged }; try self.check(captured) }, token)
    }
    public func refreshLocal() throws { try check(session); local = try store.entries(session: session) }
    public func saveLocal(_ draft: SquareWorkspaceDraft, lane: SquareWorkspaceLane) throws {
        try check(session)
        let previous = try store.entries(session: session).first { $0.id == draft.id }
        guard previous?.pending != true else { throw SquareWorkspaceFailure.pending }
        try store.save(.init(draft: draft, lane: lane, pending: false, receipt: previous?.receipt, updatedAt: Date()), session: session)
        try refreshLocal(); review = nil; status = "squareWorkspace.savedLocal"
    }
    public func discard(_ entry: SquareWorkspaceLocalEntry) throws { try check(session); try store.discard(workflowID: entry.id, session: session); try refreshLocal() }
    /// Old local envelopes already persist the selected endpoint lane. Rebind an
    /// unqualified edit only through that lane's fresh owner read, never an ID crosswalk.
    public func resume(_ entry: SquareWorkspaceLocalEntry) async throws -> SquareWorkspaceDraft {
        guard !busy else { throw SquareWorkspaceFailure.pending }
        busy = true; defer { busy = false }
        try check(session)
        guard try store.entries(session: session).first(where: { $0.id == entry.id }) == entry else { throw SquareWorkspaceFailure.staleReview }
        guard let postID = entry.draft.postID else { return entry.draft }
        if let sourceLane = entry.draft.sourceLane {
            guard sourceLane == entry.lane else { throw SquareWorkspaceFailure.invalid }
            if sourceLane != .legacy || entry.draft.legacySourceDigest != nil { return entry.draft }
        }
        guard !entry.pending, entry.receipt == nil else { throw SquareWorkspaceFailure.pending }
        let (api, token) = try connection()
        let post = try await api.detail(postID: postID, lane: entry.lane, token: token)
        try check(session)
        guard post.authorID == session.accountID else { throw SquareWorkspaceFailure.ownerRequired }
        var updated = entry
        if entry.lane == .communityV1 {
            guard post.version == entry.draft.expectedVersion, post.lifecycle == entry.draft.sourceLifecycle else { throw SquareWorkspaceFailure.staleReview }
        }
        updated.draft.sourceLane = post.lane
        updated.draft.expectedVersion = post.version; updated.draft.sourceLifecycle = post.lifecycle
        updated.draft.legacySourceDigest = post.lane == .legacy ? post.sourceDigest : nil
        // Preserve body, media, reference, workflow and pending metadata exactly.
        guard try store.entries(session: session).first(where: { $0.id == entry.id }) == entry else { throw SquareWorkspaceFailure.staleReview }
        try store.save(updated, session: session); try refreshLocal(); review = nil
        return updated.draft
    }
    public func cancelReview() { review = nil }
    public func loadServer(more: Bool = false) async throws {
        guard !busy else { throw SquareWorkspaceFailure.pending }
        let (api, token) = try connection(); busy = true; defer { busy = false }
        if more && (!hasMore || nextCursor == nil) { throw SquareWorkspaceFailure.invalid }
        let cursor = more ? nextCursor : nil
        let page = try await api.drafts(cursor: cursor, token: token); try check(session)
        guard page.items.allSatisfy({ $0.authorID == session.accountID }) else { throw SquareWorkspaceFailure.ownerRequired }
        if more { server += page.items.filter { item in !server.contains(where: { $0.id == item.id }) } } else { server = page.items }
        hasMore = page.hasMore && page.nextCursor != nil && page.nextCursor != cursor; nextCursor = page.nextCursor
    }
    /// Edit hydration is a fresh owner-scoped detail, never the lossy public feed projection.
    public func editableDraft(postID: Int, lane: SquareWorkspaceLane = .communityV1) async throws -> SquareWorkspaceDraft {
        let (api, token) = try connection()
        let post = try await api.detail(postID: postID, lane: lane, token: token)
        try check(session)
        guard post.id == postID, post.authorID == session.accountID else { throw SquareWorkspaceFailure.ownerRequired }
        return try post.editableDraft(lane: lane)
    }
    public func referenceOptions(type: String) async throws -> [SquareWorkspaceOption] {
        let (api, token) = try connection(); let value = try await api.options(type: type, token: token); try check(session); return value
    }
    public func revisions(postID: Int) async throws -> Data {
        let (api, token) = try connection(); let post = try await api.detail(postID: postID, token: token)
        guard post.authorID == session.accountID else { throw SquareWorkspaceFailure.ownerRequired }
        return try await api.revisions(postID: postID, token: token)
    }
    public func upload(bytes: Data, mimeType: String, lane: SquareWorkspaceLane, workflowID: String, explicitIntent: Bool) async throws -> SquareWorkspaceMedia {
        guard explicitIntent, grants.media, !busy else { throw SquareWorkspaceFailure.disabled }
        let (api, token) = try connection(); busy = true; defer { busy = false }
        let markerID = "media-upload-" + workflowID
        guard !(try store.entries(session: session)).contains(where: { $0.id == markerID && $0.pending }) else { throw SquareWorkspaceFailure.pending }
        let marker = SquareWorkspaceDraft(workflowID: markerID)
        try pending(marker, lane: lane)
        do {
            let media = try await api.upload(bytes: bytes, mimeType: mimeType, communityProof: lane == .communityV1, token: token)
            try check(session)
            try store.save(.init(draft: marker, lane: lane, pending: false, receipt: nil, updatedAt: Date()), session: session)
            review = nil; return media
        } catch { status = "squareWorkspace.unknown"; throw error }
    }
    public func prepare(_ draft: SquareWorkspaceDraft, lane: SquareWorkspaceLane) async throws -> SquareWorkspaceReview {
        guard !busy else { throw SquareWorkspaceFailure.pending }
        try draft.validate(publishing: true, lane: lane)
        guard !(try store.entries(session: session)).contains(where: { $0.id == draft.id && ($0.pending || $0.receipt != nil) }) else { throw SquareWorkspaceFailure.pending }
        let (api, token) = try connection(); busy = true; defer { busy = false }; review = nil
        let guideline = lane == .communityV1 ? try await api.guideline(token: token) : nil
        let original: SquareWorkspacePost?
        if let id = draft.postID {
            original = try await api.detail(postID: id, lane: lane, token: token)
            guard original?.authorID == session.accountID, original?.version == draft.expectedVersion, original?.lifecycle == draft.sourceLifecycle else { throw SquareWorkspaceFailure.staleReview }
            if lane == .legacy {
                guard original?.sourceDigest == draft.legacySourceDigest else { throw SquareWorkspaceFailure.staleReview }
            }
        } else { original = nil }
        try check(session)
        let result = SquareWorkspaceReview(id: UUID(), session: session, draft: draft, lane: lane, guideline: guideline, original: original)
        review = result; return result
    }
    private func pending(_ draft: SquareWorkspaceDraft, lane: SquareWorkspaceLane, receipt: String? = nil) throws {
        try store.save(.init(draft: draft, lane: lane, pending: true, receipt: receipt, updatedAt: Date()), session: session)
    }
    public func confirm(_ value: SquareWorkspaceReview, unchangedDraft: SquareWorkspaceDraft, acceptCurrentGuideline: Bool) async throws {
        guard !busy, review == value, value.draft == unchangedDraft, !usedReviews.contains(value.id) else { throw SquareWorkspaceFailure.staleReview }
        try check(value.session)
        if value.lane == .communityV1 { guard grants.legal, acceptCurrentGuideline else { throw SquareWorkspaceFailure.disabled } }
        let (api, token) = try connection(); busy = true; defer { busy = false }; review = nil
        if let guideline = value.guideline { guard try await api.guideline(token: token) == guideline else { throw SquareWorkspaceFailure.staleReview } }
        if let original = value.original { guard try await api.detail(postID: original.id, lane: value.lane, token: token) == original else { throw SquareWorkspaceFailure.staleReview } }
        try check(value.session); try pending(value.draft, lane: value.lane); usedReviews.insert(value.id)
        do {
            if value.lane == .legacy {
                try await api.legacyPublish(draft: value.draft, token: token)
                if let id = value.draft.postID {
                    let fresh = try await api.detail(postID: id, lane: .legacy, token: token)
                    guard fresh.authorID == session.accountID else { throw SquareWorkspaceFailure.unknown }
                    lastPost = fresh
                }
                try check(value.session); status = "squareWorkspace.acknowledged"
            } else {
                let guidelineID = value.guideline!.id
                try await api.acknowledge(guidelineID: guidelineID, workflowID: value.draft.workflowID, token: token)
                let saved = try await api.upsert(draft: value.draft, guidelineID: guidelineID, publishing: true, token: token)
                guard saved.authorID == session.accountID, value.draft.postID == nil || saved.id == value.draft.postID else { throw SquareWorkspaceFailure.unknown }
                let submitted = saved.lifecycle == "DRAFT" ? try await api.publish(post: saved, workflowID: value.draft.workflowID, token: token) : saved
                lastPost = try await api.detail(postID: submitted.id, token: token); try check(value.session)
                guard lastPost?.authorID == session.accountID else { throw SquareWorkspaceFailure.unknown }
                status = "squareWorkspace.readback"
            }
            try pending(value.draft, lane: value.lane, receipt: status); try refreshLocal()
        } catch { status = "squareWorkspace.unknown"; throw error }
    }
    public func saveServer(_ draft: SquareWorkspaceDraft) async throws {
        guard !busy else { throw SquareWorkspaceFailure.pending }
        try draft.validate(publishing: false, lane: .communityV1)
        if draft.postID != nil && draft.sourceLifecycle != "DRAFT" { try saveLocal(draft, lane: .communityV1); return }
        guard !(try store.entries(session: session)).contains(where: { $0.id == draft.id && ($0.pending || $0.receipt != nil) }) else { throw SquareWorkspaceFailure.pending }
        let (api, token) = try connection(); busy = true; defer { busy = false }
        let guideline = try await api.guideline(token: token)
        if let id = draft.postID {
            let original = try await api.detail(postID: id, token: token)
            guard original.authorID == session.accountID, original.version == draft.expectedVersion, original.lifecycle == "DRAFT" else { throw SquareWorkspaceFailure.staleReview }
        }
        try draft.validate(publishing: false, lane: .communityV1); try check(session); try pending(draft, lane: .communityV1)
        do {
            let saved = try await api.upsert(draft: draft, guidelineID: guideline.id, publishing: false, token: token)
            guard draft.postID == nil || saved.id == draft.postID else { throw SquareWorkspaceFailure.unknown }
            let fresh = try await api.detail(postID: saved.id, token: token)
            guard fresh.authorID == session.accountID, fresh.lifecycle == "DRAFT" else { throw SquareWorkspaceFailure.unknown }
            let updated = try fresh.editableDraft()
            // A completed server save ends the old workflow. Resume the fresh server projection
            // with a new workflow so media-index registration keys cannot bind a different image.
            guard draft.media.isEmpty || (updated.media.count == draft.media.count && updated.media.allSatisfy({ $0.existingMediaID != nil })) else { throw SquareWorkspaceFailure.unknown }
            try store.save(.init(draft: draft, lane: .communityV1, pending: false, receipt: "squareWorkspace.savedServer", updatedAt: Date()), session: session)
            try store.save(.init(draft: updated, lane: .communityV1, pending: false, receipt: nil, updatedAt: Date()), session: session)
            lastPost = fresh; try refreshLocal(); status = "squareWorkspace.savedServer"
        } catch { status = "squareWorkspace.unknown"; throw error }
    }
    public func withdrawLocation(reviewed: SquareWorkspacePost, explicitIntent: Bool) async throws {
        guard explicitIntent, !busy else { throw SquareWorkspaceFailure.disabled }
        guard reviewed.lane == .communityV1 else { throw SquareWorkspaceFailure.invalid }
        let (api, token) = try connection(); busy = true; defer { busy = false }
        let fresh = try await api.detail(postID: reviewed.id, token: token)
        guard fresh == reviewed, fresh.authorID == session.accountID else { throw SquareWorkspaceFailure.staleReview }
        let key = "location-withdraw-\(reviewed.id)"
        guard !(try store.entries(session: session)).contains(where: { $0.id == key && $0.pending }) else { throw SquareWorkspaceFailure.pending }
        let marker = SquareWorkspaceDraft(workflowID: key, postID: reviewed.id, expectedVersion: reviewed.version, sourceLifecycle: reviewed.lifecycle)
        try pending(marker, lane: .communityV1)
        try await api.withdrawLocation(post: fresh, requestID: "location-withdraw-\(Int(Date().timeIntervalSince1970 * 1_000_000))-0", token: token)
        lastPost = try await api.detail(postID: fresh.id, token: token); try check(session)
        // Keep the write lock until a host displays/reconciles the fresh server location state.
        status = "squareWorkspace.readback"
    }
}
