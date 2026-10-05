import Foundation

/// Normal merchant factory. The account supplies credentials; access/me supplies the merchant row.
@MainActor final class MerchantRetainedImageHost {
    private let cache: RetainedImageContextCache
    init(cache: RetainedImageContextCache) { self.cache = cache }
    func document(reader: any MerchantOperationsReading, destination: MerchantOperationsDestination) -> MerchantRetainedImageDocumentOwner {
        MerchantRetainedImageDocumentOwner(cache: cache, reader: reader, destination: destination)
    }
}

/// One owner per document model, retained across SwiftUI renders. Every draft/access refresh
/// invalidates outstanding image work. UUID fences are local, not fabricated server revisions.
@MainActor final class MerchantRetainedImageDocumentOwner {
    private let cache: RetainedImageContextCache
    private let reader: any MerchantOperationsReading
    private let destination: MerchantOperationsDestination
    private let ownerID = UUID()
    private let newDraftID = UUID()
    private var capturedCredentials: RetainedImageHostCredentials?
    private var access: MerchantOperationsAccess?
    private var loadedScope: UUID?
    private var accessRevision = UUID()
    private var draftRevision = UUID()
    private var capturedDraft: MerchantOperationsDraft?
    private var generation = 0
    init(cache: RetainedImageContextCache, reader: any MerchantOperationsReading, destination: MerchantOperationsDestination) {
        self.cache = cache; self.reader = reader; self.destination = destination
    }
    func refresh(coordinator: MerchantOperationsCoordinator) async {
        invalidate()
        let ticket = generation, scope = reader.scope
        guard coordinator.isCurrent, let draft = coordinator.draft, draft.destination == destination,
              reader.isAuthenticated, !reader.isOfflineExample, let credentials = cache.credentials else { return }
        do {
            let value = try await reader.access()
            guard !Task.isCancelled, ticket == generation, cache.credentials == credentials, reader.scope == scope, coordinator.isCurrent,
                  coordinator.draft == draft, value.allows(destination),
                  value.identity.merchantID.flatMap(PublicMerchantRowID.init) != nil else { return }
            capturedCredentials = credentials; access = value; loadedScope = scope; accessRevision = UUID(); draftRevision = UUID(); capturedDraft = draft
        } catch { if ticket == generation { invalidate() } }
    }
    var galleryBatchAccessFence: UUID? { access == nil ? nil : accessRevision }
    func validatesGalleryBatchScope(_ scope: RetainedImageScope, coordinator: MerchantOperationsCoordinator) -> Bool {
        guard destination == .gallery, let credentials = cache.credentials, credentials == capturedCredentials,
              let access, let loadedScope, let draft = coordinator.draft,
              coordinator.isCurrent, !coordinator.isBusy, !coordinator.isLocked, coordinator.confirmation == nil,
              reader.isAuthenticated, reader.scope == loadedScope, access.allows(.gallery),
              draft == capturedDraft, matches(field: .gallery, draft: draft),
              let row = access.identity.merchantID.flatMap(PublicMerchantRowID.init) else { return false }
        return scope.accountID == credentials.accountID && scope.epoch == loadedScope && scope.realm == credentials.realm
            && scope.namespace == credentials.namespace && scope.accessRevision == draftRevision && scope.resourceID == nil
            && scope.destination == .merchant(merchantRowID: row.rawValue, field: .gallery)
    }

    func draftChanged(_ draft: MerchantOperationsDraft?) {
        guard draft != capturedDraft else { return }
        cache.invalidate(ownerID: ownerID); draftRevision = UUID(); capturedDraft = draft
    }
    func invalidate() {
        generation += 1; capturedCredentials = nil; access = nil; loadedScope = nil; capturedDraft = nil
        accessRevision = UUID(); draftRevision = UUID(); cache.invalidate(ownerID: ownerID)
    }
    func context(field: MerchantImageField, coordinator: MerchantOperationsCoordinator) -> RetainedImageSelectionContext? {
        guard let credentials = cache.credentials, credentials == capturedCredentials, let access, let loadedScope,
              coordinator.isCurrent, !coordinator.isBusy, !coordinator.isLocked, coordinator.confirmation == nil,
              reader.scope == loadedScope, reader.isAuthenticated, access.allows(destination),
              let row = access.identity.merchantID.flatMap(PublicMerchantRowID.init),
              let draft = coordinator.draft, draft == capturedDraft, matches(field: field, draft: draft) else { return nil }
        let resourceID: Int?
        if case .template(let value) = draft { resourceID = value.id } else { resourceID = nil }
        let accessTicket = accessRevision, draftTicket = draftRevision, ticket = generation
        // Both revisions are checked in the callback; draftTicket is the proof's nonnil local fence.
        guard let scope = try? RetainedImageScope(accountID: credentials.accountID, epoch: loadedScope,
            realm: credentials.realm, destination: .merchant(merchantRowID: row.rawValue, field: field),
            accessRevision: draftTicket, resourceID: resourceID, namespace: credentials.namespace) else { return nil }
        return cache.context(scope: scope,
            destination: .merchant(row, field, templateID: resourceID, newDraftID: field == .imgUrl && resourceID == nil ? newDraftID : nil),
            ownerID: ownerID, isCurrent: { [weak self, weak coordinator] in
                guard let self, let coordinator else { return false }
                return self.generation == ticket && self.accessRevision == accessTicket && self.draftRevision == draftTicket
                    && self.access == access && self.loadedScope == loadedScope && self.reader.scope == loadedScope
                    && self.reader.isAuthenticated && coordinator.isCurrent && !coordinator.isLocked
                    && !coordinator.isBusy && coordinator.confirmation == nil
                    && coordinator.draft == draft && coordinator.destination == self.destination
                    && self.matches(field: field, draft: draft)
            })
    }
    private func matches(field: MerchantImageField, draft: MerchantOperationsDraft) -> Bool {
        guard draft.destination == destination else { return false }
        switch (field, draft, destination) {
        case (.logo, .profile(let value), .profile): return value.id == access?.identity.merchantID
        case (.coverImage, .decor, .decor), (.gallery, .gallery, .gallery), (.avatar, .character, .character): return true
        case (.imgUrl, .template(let value), .template(let id)): return value.id == id && (id == nil || id! > 0)
        default: return false
        }
    }
}
