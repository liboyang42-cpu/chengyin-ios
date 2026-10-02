import Foundation

/// Captured only in memory; never logged or persisted. Token rotation fences stale callbacks.
@MainActor struct RetainedImageHostCredentials: Equatable {
    let accountID: Int
    let sessionVersion: UInt64
    let realm: String
    let namespace: String
    let token: String
    let authorizationRevision: String
    init?(accountID: Int, sessionVersion: UInt64, realm: String, namespace: String, token: String, authorizationRevision: String = "") {
        guard accountID > 0, !namespace.isEmpty, AuthRequestBuilder.isValidToken(token) else { return nil }
        self.accountID = accountID; self.sessionVersion = sessionVersion; self.realm = realm
        self.namespace = namespace; self.token = token; self.authorizationRevision = authorizationRevision
    }
}

/// Account-owned pool, not a View-render factory. Unknown uploads retain their original owner.
/// No upload grant, origin allowlist or OS permission is inferred from an authenticated session.
@MainActor final class RetainedImageContextCache {
    enum Destination: Equatable {
        case merchant(PublicMerchantRowID, MerchantImageField, templateID: Int?, newDraftID: UUID?)
        case review(PublicMerchantRowID, registrationID: Int)
    }
    private struct Key: Equatable {
        let accountID: Int
        let epoch: UUID
        let realm: String
        let namespace: String
        let destination: Destination
    }
    private struct Entry {
        let key: Key
        let ownerID: UUID
        let context: RetainedImageSelectionContext
    }
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let journal: any ImageUploadJournal
    private let pickerHost: RetainedImagePickerHost
    private let currentCredentials: () -> RetainedImageHostCredentials?
    private var entries: [Entry] = []
    private var generation = 0
    init(configuration: APIConfiguration, transport: any HTTPTransport, pickerHost: RetainedImagePickerHost,
         journal: (any ImageUploadJournal)? = nil,
         currentCredentials: @escaping () -> RetainedImageHostCredentials?) {
        self.configuration = configuration; self.transport = transport; self.pickerHost = pickerHost
        self.currentCredentials = currentCredentials; self.journal = journal ?? UnavailableImageUploadJournal()
    }
    var credentials: RetainedImageHostCredentials? {
        guard let value = currentCredentials(), value.realm == configuration.baseURL.absoluteString else { return nil }
        return value
    }
    func context(scope: RetainedImageScope, destination: Destination, ownerID: UUID,
                 isCurrent: @escaping () -> Bool) -> RetainedImageSelectionContext? {
        guard let captured = credentials, captured.accountID == scope.accountID,
              captured.realm == scope.realm, captured.namespace == scope.namespace, isCurrent() else { return nil }
        let key = Key(accountID: scope.accountID, epoch: scope.epoch, realm: scope.realm,
            namespace: captured.namespace, destination: destination)
        // An unresolved upload is a namespace/account/realm/target lock, not an epoch lock.
        // Token rotation, logout/login or reopening a new-template screen cannot evade it.
        if let unresolved = entries.first(where: {
            $0.context.uploads.locked && $0.key.accountID == key.accountID
                && $0.key.realm == key.realm && $0.key.namespace == key.namespace
                && sameUnresolvedTarget($0.key.destination, key.destination)
        }) {
            if unresolved.ownerID == ownerID, unresolved.key == key, unresolved.context.scope == scope,
               unresolved.context.currentScope() == scope { return unresolved.context }
            unresolved.context.picker.cancel(); unresolved.context.uploads.clear()
            return nil
        }
        if let existing = entries.first(where: { $0.key == key }) {
            if existing.ownerID == ownerID, existing.context.scope == scope,
               existing.context.currentScope() == scope { return existing.context }
            existing.context.picker.cancel(); existing.context.uploads.clear()
            // Reopening, draft edits or access refresh cannot unlock an ambiguous upload.
            guard !existing.context.uploads.locked else { return nil }
            entries.removeAll { $0.key == key }
        }
        let ticket = generation
        let current: () -> RetainedImageScope? = { [weak self] in
            guard let self, self.generation == ticket, self.credentials == captured, isCurrent() else { return nil }
            return scope
        }
        let uploader = RetainedImageHTTPUploader(configuration: configuration, transport: transport,
            enabled: false, approvedOrigins: [], currentScope: current,
            token: { [weak self] in self?.credentials == captured ? captured.token : nil })
        let context = RetainedImageSelectionContext(scope: scope, currentScope: current,
            picker: pickerHost.makePicker(), uploads: RetainedImageUploadCoordinator(uploader: uploader, journal: journal))
        entries.append(.init(key: key, ownerID: ownerID, context: context))
        return context
    }
    private func sameUnresolvedTarget(_ lhs: Destination, _ rhs: Destination) -> Bool {
        switch (lhs, rhs) {
        case let (.merchant(row, field, templateID, _), .merchant(otherRow, otherField, otherTemplateID, _)):
            // A nil template ID is intentionally one conservative unresolved target per merchant.
            return row == otherRow && field == otherField && templateID == otherTemplateID
        case let (.review(row, registrationID), .review(otherRow, otherRegistrationID)):
            return row == otherRow && registrationID == otherRegistrationID
        default: return false
        }
    }
    func invalidate(ownerID: UUID) {
        for entry in entries where entry.ownerID == ownerID {
            entry.context.picker.cancel(); entry.context.uploads.clear()
        }
        entries.removeAll { $0.ownerID == ownerID && !$0.context.uploads.locked }
    }
    func invalidate() {
        generation += 1
        for entry in entries { entry.context.picker.cancel(); entry.context.uploads.clear() }
        entries.removeAll { !$0.context.uploads.locked }
    }
}
