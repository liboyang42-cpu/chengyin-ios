import SwiftUI

@MainActor struct ProjectMerchantDraftContext {
    let model: ProjectEditModel
    let node: Binding<ProjectEditNode>
    let sourceID: String
    let nodeRevision: () -> Int
    let isCurrent: () -> Bool
    var id: String { "\(model.editorIncarnation):\(sourceID)" }
    struct Target: Equatable {
        let lease: ProjectEditStarterController.Lease
        let sourceID: String
        let draftBytes: Data
        let nodeBytes: Data
        let draftRevision: Int
        let nodeRevision: Int
    }
    func capture() -> Target? {
        guard isCurrent(), let lease = model.captureStarterLease(),
              let draft = ProjectEditPendingMaterials.exactData(model.draft),
              let node = ProjectEditPendingMaterials.exactData(node.wrappedValue) else { return nil }
        return .init(lease: lease, sourceID: sourceID, draftBytes: draft, nodeBytes: node,
                     draftRevision: model.draftMutationRevision, nodeRevision: nodeRevision())
    }
}

@MainActor final class ProjectMerchantDraftController: ObservableObject {
    struct Review: Identifiable {
        let id = UUID()
        let target: ProjectMerchantDraftContext.Target
        let original: ProjectEditNode
        let readerID: UUID
    }
    struct Selection: Identifiable {
        let id = UUID()
        let choice: ProjectMerchantDraftChoice
        let pageGeneration: UUID
        let merchantRowID: Int
    }
    enum State: Equatable { case idle, loading, ready, resolving, failed, unauthorized, forbidden, changed }
    let context: ProjectMerchantDraftContext
    @Published private(set) var review: Review?
    @Published private(set) var rows: [ProjectMerchantDraftRow] = []
    @Published private(set) var selection: Selection?
    @Published private(set) var state: State = .idle
    @Published private(set) var nextBeforeSourceID: Int?
    private var merchantRowID: Int?
    private var pageGeneration = UUID()
    private var requestID: UUID?
    private var request: Task<Void, Never>?
    init(context: ProjectMerchantDraftContext) { self.context = context }
    var available: Bool {
        guard let target = context.capture(), let source = context.model.coordinator.merchantDraftSource else { return false }
        return source.isCurrent(session: target.lease.session)
    }
    func isCurrent(_ original: Review) -> Bool {
        guard review?.id == original.id, context.capture() == original.target,
              let source = context.model.coordinator.merchantDraftSource, source.identity == original.readerID else { return false }
        return source.isCurrent(session: original.target.lease.session)
    }
    func open() {
        guard available, let target = context.capture(), let source = context.model.coordinator.merchantDraftSource else { return }
        if let review, isCurrent(review) { return }
        retireRequest(); clearRows(); state = .idle
        review = .init(target: target, original: context.node.wrappedValue, readerID: source.identity)
    }
    func cancel(_ original: Review) {
        guard review?.id == original.id else { return }
        retireRequest(); clearRows(); review = nil; state = .idle
    }
    private func retireRequest() { request?.cancel(); request = nil; requestID = nil }
    private func clearRows() { rows = []; selection = nil; nextBeforeSourceID = nil; merchantRowID = nil; pageGeneration = UUID() }
    @discardableResult func refresh(_ original: Review) -> Task<Void, Never>? {
        guard isCurrent(original), state != .resolving else { return nil }
        retireRequest(); clearRows(); return load(original, before: nil)
    }
    @discardableResult func loadMore(_ original: Review) -> Task<Void, Never>? {
        guard isCurrent(original), state == .ready, let nextBeforeSourceID else { return nil }
        return load(original, before: nextBeforeSourceID)
    }
    private func load(_ original: Review, before: Int?) -> Task<Void, Never>? {
        guard isCurrent(original), let source = context.model.coordinator.merchantDraftSource else { return nil }
        let stamp = UUID(); requestID = stamp; state = .loading; selection = nil
        request = Task { [weak self] in
            do {
                let page = try await source.list(beforeSourceID: before, session: original.target.lease.session)
                guard let self, !Task.isCancelled, self.requestID == stamp, self.isCurrent(original) else { return }
                guard page.ownerMemberID == original.target.lease.session.accountID,
                      self.merchantRowID == nil || self.merchantRowID == page.merchantRowID,
                      before == nil || self.nextBeforeSourceID == before else { throw ProjectMerchantDraftError.changedContext }
                let sourceIDs = Set(self.rows.map(\.sourceID)), templateIDs = Set(self.rows.map(\.memberTemplateID))
                guard page.rows.count <= ProjectMerchantDraftPage.pageSize,
                      Set(page.rows.map(\.sourceID)).count == page.rows.count,
                      Set(page.rows.map(\.memberTemplateID)).count == page.rows.count,
                      page.rows.allSatisfy({ !sourceIDs.contains($0.sourceID) && !templateIDs.contains($0.memberTemplateID) }) else { throw ProjectMerchantDraftError.invalidResponse }
                self.rows += page.rows; self.merchantRowID = page.merchantRowID; self.nextBeforeSourceID = page.nextBeforeSourceID
                self.pageGeneration = UUID(); self.state = .ready
            } catch {
                guard let self, !Task.isCancelled, self.requestID == stamp, self.isCurrent(original) else { return }
                // No partial page or stale selections remain actionable after an error.
                self.clearRows(); self.state = Self.failure(error)
            }
            guard let self, self.requestID == stamp else { return }; self.request = nil; self.requestID = nil
        }
        return request
    }
    func select(_ row: ProjectMerchantDraftRow, review original: Review) {
        guard isCurrent(original), state == .ready, rows.contains(row), let choice = row.choice, let merchantRowID else { return }
        selection = .init(choice: choice, pageGeneration: pageGeneration, merchantRowID: merchantRowID)
    }
    @discardableResult func apply(_ captured: Selection, review original: Review) -> Task<Void, Never>? {
        guard isCurrent(original), state == .ready, selection?.id == captured.id,
              captured.pageGeneration == pageGeneration, merchantRowID == captured.merchantRowID,
              let source = context.model.coordinator.merchantDraftSource else { return nil }
        // Claim before launching work. Repeated taps cannot start a second resolve.
        let stamp = UUID(); requestID = stamp; state = .resolving
        request = Task { [weak self] in
            do {
                let resolved = try await source.resolve(captured.choice, merchantRowID: captured.merchantRowID, session: original.target.lease.session)
                guard let self, !Task.isCancelled, self.requestID == stamp, self.isCurrent(original),
                      self.selection?.id == captured.id else { return }
                guard resolved.ownerMemberID == original.target.lease.session.accountID,
                      resolved.merchantRowID == captured.merchantRowID, resolved.choice == captured.choice else { throw ProjectMerchantDraftError.sourceChanged }
                let updated = resolved.applying(to: original.original)
                self.cancel(original); self.context.node.wrappedValue = updated
            } catch {
                guard let self, !Task.isCancelled, self.requestID == stamp, self.isCurrent(original) else { return }
                self.clearRows(); self.state = Self.failure(error)
            }
            guard let self, self.requestID == stamp else { return }; self.request = nil; self.requestID = nil
        }
        return request
    }
    private static func failure(_ error: Error) -> State {
        if error as? APIError == .unauthorized { return .unauthorized }
        switch error as? ProjectMerchantDraftError {
        case .forbidden: return .forbidden
        case .sourceChanged, .changedContext: return .changed
        default: return .failed
        }
    }
    func presentation(_ original: Review?) -> Binding<Review?> {
        Binding(get: { self.review?.id == original?.id ? self.review : nil }, set: { next in
            guard next == nil, let original else { return }; self.cancel(original)
        })
    }
}
