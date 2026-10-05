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
/// A sheet owns only a candidate. It never saves/publishes. Return is bound to one loaded
/// merchant template document, one session, and the field revisions at Generate time.
@MainActor public final class MerchantTemplateAssistFlow {
    public var shopName: String
    public var prompt = ""
    public private(set) var result: MerchantTemplateAssistResult?
    public private(set) var failure: MerchantTemplateAssistFailure?
    public private(set) var busy = false
    public var onChange: (() -> Void)?
    private let coordinator: MerchantOperationsCoordinator
    private let client: (any MerchantTemplateAssistServing)?
    private let scope: UUID
    private let draftIdentity: UUID
    private let session: PublishingSession?
    private var captured: MerchantNodeTemplate?
    private var capturedEdits = MerchantTemplateAssistEdits()
    private var generation = 0
    private var closed = false
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
    public var canGenerate: Bool { isCurrent && isConfigured && !busy && (failure == nil || failure?.retryable == true) }
    public var preview: MerchantNodeTemplate? {
        guard isCurrent, let result, let captured, case .template(let latest) = coordinator.draft else { return nil }
        return result.merge(into: latest, captured: captured, edits: coordinator.templateAssistEdits, capturedEdits: capturedEdits)
    }
    public var canApply: Bool {
        guard !busy, isConfigured, result != nil, let preview, case .template(let latest) = coordinator.draft else { return false }
        return preview != latest
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
        captured = draft; capturedEdits = coordinator.templateAssistEdits; result = nil; failure = nil; busy = true; onChange?()
        do {
            let access = try await coordinator.reader.access()
            guard stamp == generation, isCurrent, !Task.isCancelled else { abandon(stamp); return }
            guard access.allows(coordinator.destination) else { throw MerchantTemplateAssistFailure.permission }
            let candidate = try await client.generate(input)
            guard stamp == generation, isCurrent, !Task.isCancelled else { abandon(stamp); return }
            guard !candidate.isEmpty else { throw MerchantTemplateAssistFailure.empty }
            result = candidate; busy = false; onChange?()
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
    /// Fresh permission read precedes returning the merged value. The caller applies this
    /// synchronously on MainActor to its existing draft, never to a replacement editor.
    public func apply() async -> MerchantNodeTemplate? {
        guard canApply else { return nil }
        let stamp = generation; busy = true; onChange?()
        do {
            let access = try await coordinator.reader.access()
            guard stamp == generation, isCurrent, !Task.isCancelled, isConfigured else { abandon(stamp); return nil }
            guard access.allows(coordinator.destination) else { throw MerchantTemplateAssistFailure.permission }
            busy = false
            guard canApply, let preview else { onChange?(); return nil }
            close(); return preview
        } catch {
            guard stamp == generation else { return nil }
            busy = false
            if !isCurrent { failure = .stale }
            else if error is CancellationError || Task.isCancelled { failure = .cancelled }
            else if error as? APIError == .unauthorized || error as? MerchantOperationsFailure == .accessDenied { failure = .permission }
            else { failure = error as? MerchantTemplateAssistFailure ?? .provider }
            result = nil; onChange?(); return nil
        }
    }
    private func abandon(_ stamp: Int) {
        guard stamp == generation else { return }
        busy = false; result = nil; failure = Task.isCancelled ? .cancelled : .stale; client?.cancel(); onChange?()
    }
    public func cancel() { generation += 1; client?.cancel(); result = nil; captured = nil; busy = false; failure = .cancelled; onChange?() }
    public func close() { cancel(); closed = true; shopName = ""; prompt = "" }
}
