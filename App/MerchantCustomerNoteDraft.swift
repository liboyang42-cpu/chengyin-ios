import SwiftUI
import CryptoKit

/// Page-local, pre-review text only. Never owns a request ID, dispatch, or retry.
@MainActor final class MerchantCustomerNoteDraft: ObservableObject {
    struct Draft: Equatable {
        var content = ""
        var correctionCancelled = false
        var hasChanges: Bool { !content.isEmpty || correctionCancelled }
    }
    private struct Source {
        let scope: MerchantBusinessScope
        let authorization: UUID?
        let snapshot: MerchantBusinessSnapshot
        let payload: Data
    }
    private weak var owner: MerchantBusinessViewModel?
    private var active = false
    private var source: Source?
    private var lease: (id: UUID, key: Int)?
    @Published private(set) var generation = UUID()
    @Published private var drafts: [Int: Draft] = [:]
    init(owner: MerchantBusinessViewModel) { self.owner = owner }
    func activate() { active = true }
    @discardableResult func retire() -> UUID? { active = false; return discard() }
    private var available: MerchantBusinessSnapshot? {
        guard active, let c = owner?.coordinator, c.isCurrent, !c.isBusy, !c.isLocked,
              c.confirmation == nil, c.receipt == nil, c.failureKey == nil,
              c.reader.isConfigured, c.reader.scope != nil, let snapshot = c.snapshot,
              case .customer = snapshot.document.query,
              snapshot.access.allows("merchant:crm:read"), snapshot.access.allows("merchant:crm:segment") else { return nil }
        return snapshot
    }
    private static func fingerprint(_ value: MerchantBusinessValue) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(value) else { return nil }
        return Data(SHA256.hash(data: bytes))
    }
    private var sourceIsCurrent: Bool {
        guard let source, let c = owner?.coordinator, let snapshot = available,
              let scope = c.reader.scope, scope == source.scope,
              scope.realm.utf8.elementsEqual(source.scope.realm.utf8),
              c.reader.authorizationGeneration == source.authorization,
              snapshot == source.snapshot, Self.fingerprint(snapshot.document.payload) == source.payload,
              snapshot.access.role.utf8.elementsEqual(source.snapshot.access.role.utf8),
              Set(snapshot.access.permissions.map { Data($0.utf8) }) == Set(source.snapshot.access.permissions.map { Data($0.utf8) }) else { return false }
        return true
    }
    var hasDrafts: Bool { sourceIsCurrent && drafts.values.contains(where: \.hasChanges) }
    func hasDraft(corrects: Int?) -> Bool { sourceIsCurrent && drafts[corrects ?? 0]?.hasChanges == true }
    func open(customer: MerchantCustomerID, corrects: Int?) -> MerchantBusinessEditorContext? {
        synchronize()
        guard let snapshot = available, snapshot.document.query == .customer(customer),
              let c = owner?.coordinator, let scope = c.reader.scope,
              let payload = Self.fingerprint(snapshot.document.payload) else { return nil }
        if let corrects {
            guard corrects > 0, snapshot.document.rows.contains(where: {
                $0.kind == .timeline && $0.fields["noteId"]?.integer == corrects &&
                ["NOTE", "NOTE_CORRECTION"].contains($0.fields.mbText("type") ?? "")
            }) else { return nil }
        }
        if source == nil { source = .init(scope: scope, authorization: c.reader.authorizationGeneration, snapshot: snapshot, payload: payload) }
        guard sourceIsCurrent else { return nil }
        let context = MerchantBusinessEditorContext(kind: .note(customer, corrects: corrects))
        let key = corrects ?? 0
        if drafts[key] == nil { drafts[key] = .init() }
        lease = (context.id, key)
        return context
    }
    func value(for editorID: UUID) -> Draft? {
        guard sourceIsCurrent, let lease, lease.id == editorID else { return nil }
        return drafts[lease.key]
    }
    func update(editorID: UUID, content: String, correctionCancelled: Bool) {
        guard sourceIsCurrent, let lease, lease.id == editorID else { return }
        drafts[lease.key] = .init(content: content, correctionCancelled: correctionCancelled)
    }
    func close(editorID: UUID) { if lease?.id == editorID { lease = nil } }
    /// Cross the existing confirmation boundary once; no local draft can resume afterward.
    @discardableResult func retireForReview(editorID: UUID) -> Bool {
        guard value(for: editorID) != nil else { return false }
        discard(); return true
    }
    @discardableResult func synchronize() -> UUID? {
        if source != nil && !sourceIsCurrent { return discard() }
        return nil
    }
    @discardableResult func discard(ifGeneration expected: UUID? = nil) -> UUID? {
        guard expected == nil || expected == generation else { return nil }
        let old = lease?.id
        source = nil; lease = nil; drafts = [:]; generation = UUID()
        return old
    }
}
