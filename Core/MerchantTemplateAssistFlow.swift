import Foundation

@MainActor public protocol MerchantTemplateAssistServing: AnyObject {
    var session: PublishingSession? { get }
    var canGenerate: Bool { get }
    func generate(_ input: MerchantTemplateAssistInput) async throws -> MerchantTemplateAssistResult
    func cancel()
}
@MainActor public final class MerchantTemplateAssistClient: MerchantTemplateAssistServing {
    private let service: PublishingAuxiliaryService
    private var review: PublishingAuxiliaryReview?
    public init(service: PublishingAuxiliaryService) { self.service = service }
    public var session: PublishingSession? { service.templateSession }
    public var canGenerate: Bool { service.templateConfigured }
    public func generate(_ input: MerchantTemplateAssistInput) async throws -> MerchantTemplateAssistResult {
        guard review == nil, canGenerate, let session else { throw MerchantTemplateAssistFailure.disabled }
        let value = try service.prepare(input.assistance, session: session); review = value
        let outcome = await service.confirm(value)
        guard !Task.isCancelled, review == value else { throw MerchantTemplateAssistFailure.cancelled }
        review = nil
        guard self.session == session else { throw MerchantTemplateAssistFailure.stale }
        switch outcome {
        case .acknowledged(let data): return try MerchantTemplateAssistResult(data)
        case .rejected(let message): throw MerchantTemplateAssistFailure.rejection(message)
        case .unavailable: throw MerchantTemplateAssistFailure.provider
        case .notSent: throw MerchantTemplateAssistFailure.disabled
        case .unknown: throw MerchantTemplateAssistFailure.unknown
        }
    }
    public func cancel() { if let review { service.cancel(review) }; review = nil }
}
/// A sheet reviews one candidate field at a time. It never saves/publishes.
/// Explicit local commits stay bound to the loaded document, session and field revisions.
@MainActor public final class MerchantTemplateAssistFlow {
    public var shopName: String
    public var prompt = ""
    public private(set) var result: MerchantTemplateAssistResult?
    public private(set) var review: MerchantTemplateSuggestionReview?
    public private(set) var failure: MerchantTemplateAssistFailure?
    public private(set) var busy = false
    public var onChange: (() -> Void)?
    private let coordinator: MerchantOperationsCoordinator
    private let client: (any MerchantTemplateAssistServing)?
    private let scope: UUID
    private let draftIdentity: UUID
    private let session: PublishingSession?
    private var capturedEdits = MerchantTemplateAssistEdits()
    private var generation = 0
    private var closed = false
    private var permissionRead: Task<MerchantOperationsAccess, Error>?
    private var permissionReadID: UUID?
    public init(coordinator: MerchantOperationsCoordinator, client: (any MerchantTemplateAssistServing)?) {
        self.coordinator = coordinator; self.client = client; scope = coordinator.reader.scope
        draftIdentity = coordinator.draftIdentity; session = client?.session
        if case .template(let value) = coordinator.draft { shopName = value.title } else { shopName = "" }
    }
    public var isConfigured: Bool { client?.canGenerate == true }
    private var isCurrent: Bool {
        !closed && coordinator.isCurrent && coordinator.reader.scope == scope && coordinator.draftIdentity == draftIdentity &&
        client?.session == session && !coordinator.isBusy && !coordinator.isLocked && coordinator.confirmation == nil
    }
    public var canGenerate: Bool { isCurrent && isConfigured && !busy && result == nil && (failure == nil || failure?.retryable == true) }
    public var visibleReview: MerchantTemplateSuggestionReview? { isCurrent ? review : nil }
    public func canEditSuggestion(_ action: MerchantTemplateSuggestionReview.Action) -> Bool {
        guard !busy, isCurrent, isConfigured, let review, case .template(let current) = coordinator.draft else { return false }
        return review.canEditCopy(action, current: current, edits: coordinator.templateAssistEdits)
    }
    public func prepareSuggestionEdit(_ action: MerchantTemplateSuggestionReview.Action) -> MerchantTemplateSuggestionEdit? {
        guard canEditSuggestion(action), let review, case .template(let current) = coordinator.draft else { return nil }
        return review.prepareCopyEdit(action, current: current, edits: coordinator.templateAssistEdits)
    }
    public func canSaveSuggestionEdit(_ edit: MerchantTemplateSuggestionEdit) -> Bool {
        guard canEditSuggestion(edit.action), edit.issue == nil, edit.isChanged,
              let value = review?.suggestion(for: edit.action) else { return false }
        return value.proposed.utf8.elementsEqual(edit.capturedProposal.utf8)
    }
    @discardableResult public func saveSuggestionEdit(_ edit: MerchantTemplateSuggestionEdit) -> Bool {
        guard canSaveSuggestionEdit(edit), case .template(let current) = coordinator.draft,
              review?.saveCopyEdit(edit, current: current, edits: coordinator.templateAssistEdits) == true else { return false }
        // The later, separate Accept action still rereads merchant permission and
        // validates the original draft/field revisions through change(_:_:).
        onChange?(); return true
    }
    public func canChange(_ action: MerchantTemplateSuggestionReview.Action, change: MerchantTemplateSuggestionReview.Change) -> Bool {
        guard !busy, isCurrent, isConfigured, let review, case .template(let current) = coordinator.draft else { return false }
        return review.proposedDraft(action, change: change, current: current, edits: coordinator.templateAssistEdits) != nil
    }
    public var canAcceptAny: Bool {
        guard let review = visibleReview else { return false }
        return review.suggestions.contains { canChange(review.action(for: $0), change: .accept) }
    }
    public func canReject(_ action: MerchantTemplateSuggestionReview.Action) -> Bool {
        !busy && isCurrent && review?.canReject(action) == true
    }
    public func reject(_ action: MerchantTemplateSuggestionReview.Action) {
        guard canReject(action) else { return }
        _ = review?.reject(action); onChange?()
    }
    public func generate() async {
        guard !busy else { return }
        guard canGenerate, let client, case .template(let draft) = coordinator.draft else {
            failure = isCurrent ? .disabled : .stale; onChange?(); return
        }
        let input: MerchantTemplateAssistInput
        do { input = try .init(shopName: shopName, prompt: prompt, method: draft.method) }
        catch { failure = error as? MerchantTemplateAssistFailure ?? .malformed; onChange?(); return }
        generation += 1; let stamp = generation
        capturedEdits = coordinator.templateAssistEdits; result = nil; review = nil; failure = nil; busy = true; onChange?()
        do {
            let access = try await readAccess()
            guard stamp == generation, isCurrent, !Task.isCancelled else { abandon(stamp); return }
            guard access.allows(coordinator.destination) else { throw MerchantTemplateAssistFailure.permission }
            let candidate = try await client.generate(input)
            guard stamp == generation, isCurrent, !Task.isCancelled else { abandon(stamp); return }
            guard !candidate.isEmpty else { throw MerchantTemplateAssistFailure.empty }
            result = candidate
            review = .init(result: candidate, captured: draft, edits: capturedEdits)
            busy = false; onChange?()
        } catch {
            guard stamp == generation else { return }
            busy = false
            if !isCurrent { failure = .stale }
            else if error is CancellationError || Task.isCancelled { failure = .cancelled }
            else if error as? APIError == .unauthorized || error as? MerchantOperationsFailure == .accessDenied { failure = .permission }
            else { failure = error as? MerchantTemplateAssistFailure ?? .provider }
            onChange?()
        }
    }
    /// Each explicit field change rereads permission, then commits atomically on MainActor.
    /// No whole-result apply, save/publish or await occurs after the final field/owner checks.
    @discardableResult public func change(_ action: MerchantTemplateSuggestionReview.Action,
                                          _ change: MerchantTemplateSuggestionReview.Change) async -> Bool {
        guard canChange(action, change: change) else { return false }
        let stamp = generation; busy = true; onChange?()
        do {
            let access = try await readAccess()
            guard stamp == generation, isCurrent, !Task.isCancelled, isConfigured else { abandon(stamp); return false }
            guard access.allows(coordinator.destination) else { throw MerchantTemplateAssistFailure.permission }
            busy = false
            guard let review, case .template(let current) = coordinator.draft,
                  let next = review.proposedDraft(action, change: change, current: current, edits: coordinator.templateAssistEdits) else { onChange?(); return false }
            coordinator.edit(.template(next))
            guard coordinator.draft == .template(next) else { onChange?(); return false }
            self.review?.recordCommit(action, change: change, edits: coordinator.templateAssistEdits)
            onChange?(); return true
        } catch {
            guard stamp == generation else { return false }
            busy = false
            if !isCurrent { failure = .stale }
            else if error is CancellationError || Task.isCancelled { failure = .cancelled }
            else if error as? APIError == .unauthorized || error as? MerchantOperationsFailure == .accessDenied { failure = .permission }
            else { failure = error as? MerchantTemplateAssistFailure ?? .provider }
            result = nil; review = nil; onChange?(); return false
        }
    }
    private func abandon(_ stamp: Int) {
        guard stamp == generation else { return }
        busy = false; result = nil; review = nil; failure = Task.isCancelled ? .cancelled : .stale; client?.cancel(); onChange?()
    }
    /// Own the task that executes SessionReader.access itself. Canceling only a sheet's
    /// latest task is insufficient: a second queued button may replace that handle.
    /// Cancellation must reach the reader before it processes an old 401 callback.
    private func readAccess() async throws -> MerchantOperationsAccess {
        try Task.checkCancellation()
        let reader = coordinator.reader, id = UUID()
        let task = Task { @MainActor in
            try Task.checkCancellation()
            return try await reader.access()
        }
        permissionRead = task; permissionReadID = id
        defer {
            if permissionReadID == id { permissionRead = nil; permissionReadID = nil }
        }
        let access = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        guard permissionReadID == id else { throw CancellationError() }
        return access
    }
    private func cancelPermissionRead() {
        permissionRead?.cancel(); permissionRead = nil; permissionReadID = nil
    }
    public func cancel() { generation += 1; cancelPermissionRead(); client?.cancel(); result = nil; review = nil; busy = false; failure = .cancelled; onChange?() }
    public func close() { cancel(); closed = true; shopName = ""; prompt = "" }
}
