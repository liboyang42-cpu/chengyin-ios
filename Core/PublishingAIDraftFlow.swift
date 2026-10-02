import Foundation

/// Current simple-publish contract. Generated places are suggestions, never confirmed POIs.
public struct PublishingAIQuota: Equatable {
    public let remaining: Int?
    public let limited: Bool
    public var exhausted: Bool { limited && remaining.map { $0 <= 0 } == true }
    public init(_ value: ProjectEditJSON) throws {
        guard let body = value.object, case .bool(let limited)? = body["limited"] else { throw PublishModesError.invalidContract }
        self.limited = limited; remaining = body["remaining"]?.integer
        guard !limited || remaining != nil else { throw PublishModesError.invalidContract }
    }
}
public struct PublishingAIThemeDraft: Equatable {
    public let draft: QuickPublishDraft
    public let traceID: String?
    public let remaining: Int?
    public init(_ value: ProjectEditJSON, product: ProjectEditProduct) throws {
        guard let body = value.object else { throw PublishModesError.invalidContract }
        var draft = try QuickPublishDraft.parseAI(body); draft.product = product
        draft.subtitle = body["draft"]?.object?["subtitle"]?.text
        draft.aiTraceID = body["traceId"]?.text
        self.draft = draft; traceID = draft.aiTraceID; remaining = body["remainingQuota"]?.integer
    }
}
@MainActor public protocol PublishingAIDraftServing: AnyObject {
    var session: PublishingSession? { get }
    var canGenerate: Bool { get }
    func quota() async throws -> PublishingAIQuota
    func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft
    func cancel()
}
/// Typed adapter over the existing exact-path clients. No approval is inferred from a role.
/// Production passes no adapter; an integration must independently approve its reads/provider.
@MainActor public final class PublishingAIDraftClient: PublishingAIDraftServing {
    private let reads: PublishingService
    private let assistance: PublishingAuxiliaryService
    private var review: PublishingAuxiliaryReview?
    public init(reads: PublishingService, assistance: PublishingAuxiliaryService) {
        self.reads = reads; self.assistance = assistance
    }
    public var session: PublishingSession? { reads.currentSession }
    public var canGenerate: Bool { assistance.themeConfigured && session?.region == .china }
    public func quota() async throws -> PublishingAIQuota {
        guard let session else { throw PublishModesError.changedSession }
        return try PublishingAIQuota(await reads.read(.aiQuota, session: session))
    }
    public func generate(idea: String, product: ProjectEditProduct) async throws -> PublishingAIThemeDraft {
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty, idea.count <= 300, canGenerate, let session else { throw PublishModesError.unavailable }
        let value = try assistance.prepare(.themeForProduct(idea: idea, product: product), session: session)
        review = value
        let result = await assistance.confirm(value)
        guard review == value, self.session == session else { throw PublishModesError.changedSession }
        review = nil
        switch result {
        case .acknowledged(let data): return try PublishingAIThemeDraft(data, product: product)
        case .rejected(let reason), .unavailable(let reason): throw PublishModesError.rejected(reason)
        case .notSent: throw PublishModesError.unavailable
        case .unknown: throw PublishModesError.uncertain
        }
    }
    public func cancel() { if let review { assistance.cancel(review) }; review = nil }
}
/// A sheet edits its own candidate; only Use Draft returns a value to the caller.
@MainActor public final class PublishingAIDraftFlow {
    public var idea = ""
    public private(set) var candidate: PublishingAIThemeDraft?
    public private(set) var quota: PublishingAIQuota?
    public private(set) var busy = false
    public private(set) var messageKey: String?
    public private(set) var serverMessage: String?
    public var onChange: (() -> Void)?
    private let client: (any PublishingAIDraftServing)?
    private let product: ProjectEditProduct
    private let openedSession: PublishingSession?
    private var generation = 0
    private var closed = false
    public init(client: (any PublishingAIDraftServing)?, product: ProjectEditProduct) {
        self.client = client; self.product = product; openedSession = client?.session
    }
    public var canGenerate: Bool { !closed && !busy && client?.canGenerate == true && client?.session == openedSession && !((quota?.exhausted) ?? false) }
    public func loadQuota() async {
        guard let client, !closed, client.session == openedSession else { return }
        let stamp = generation
        do { let value = try await client.quota(); guard stamp == generation, !closed, client.session == openedSession else { return }; quota = value; onChange?() }
        catch { /* Quota failure must not block manual publishing or invent a zero allowance. */ }
    }
    public func generate() async {
        guard canGenerate else { messageKey = quota?.exhausted == true ? "contextPublish.ai.exhausted" : "contextPublish.ai.unavailable"; onChange?(); return }
        let prompt = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= 300 else { messageKey = "contextPublish.ai.promptRequired"; onChange?(); return }
        guard let client else { return }
        generation += 1; let stamp = generation; busy = true; candidate = nil; messageKey = nil; serverMessage = nil; onChange?()
        do {
            let value = try await client.generate(idea: prompt, product: product)
            guard stamp == generation, !closed, client.session == openedSession, !Task.isCancelled else { return }
            candidate = value; busy = false; onChange?(); await loadQuota()
        } catch {
            guard stamp == generation, !closed, client.session == openedSession else { return }
            busy = false; messageKey = "contextPublish.ai.failed"
            if case PublishModesError.rejected(let reason) = error, !reason.isEmpty { serverMessage = reason }
            onChange?()
        }
    }
    public func accept() -> QuickPublishDraft? {
        guard !closed, !busy, client?.session == openedSession else { return nil }
        let value = candidate?.draft; close(); return value
    }
    public func close() { closed = true; generation += 1; client?.cancel(); candidate = nil; idea = ""; busy = false; serverMessage = nil; onChange?() }
}
