import Foundation

/// Current simple-publish contract. Generated places are suggestions, never confirmed POIs.
public struct PublishingAIQuota: Equatable {
    public let remaining: Int?
    public let limit: Int?
    public let limited: Bool
    public var exhausted: Bool { limited && remaining.map { $0 <= 0 } == true }
    public init(_ value: ProjectEditJSON) throws {
        guard let body = value.object, case .bool(let limited)? = body["limited"] else { throw PublishModesError.invalidContract }
        func count(_ key: String) throws -> Int? {
            guard let raw = body[key], raw != .null else { return nil }
            guard let number = raw.integer, number >= 0 else { throw PublishModesError.invalidContract }
            return number
        }
        self.limited = limited; remaining = try count("remaining"); limit = try count("limit")
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
    public enum QuotaReadState: Equatable { case unavailable, idle, loading, fresh, stale, failed }
    public var idea = ""
    private var storedCandidate: PublishingAIThemeDraft?
    private var storedCandidateIdea: String?
    private var storedCandidateGeneration: Int?
    public var candidate: PublishingAIThemeDraft? {
        guard isCurrent else { clearCandidate(); return nil }
        return storedCandidate
    }
    public var candidateSourceIdea: String? { candidate == nil ? nil : storedCandidateIdea }
    public var candidateGeneration: Int? { candidate == nil ? nil : storedCandidateGeneration }
    public var candidateIsPrevious: Bool {
        guard candidate != nil, let storedCandidateIdea else { return false }
        return storedCandidateGeneration != generation || !storedCandidateIdea.utf8.elementsEqual(idea.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }
    public var canAcceptCandidate: Bool { candidate != nil && isCurrent && !busy }
    private var storedQuota: PublishingAIQuota?
    private var storedQuotaReadAt: Date?
    private var storedQuotaState: QuotaReadState = .idle
    public var quota: PublishingAIQuota? { isCurrent ? storedQuota : nil }
    public var quotaReadAt: Date? { isCurrent ? storedQuotaReadAt : nil }
    public var quotaReadState: QuotaReadState { isCurrent ? storedQuotaState : .unavailable }
    public var quotaIsStale: Bool { quota != nil && quotaReadState != .fresh }
    public private(set) var busy = false
    public private(set) var messageKey: String?
    public private(set) var serverMessage: String?
    public var onChange: (() -> Void)?
    private let client: (any PublishingAIDraftServing)?
    private let product: ProjectEditProduct
    private let openedSession: PublishingSession?
    private var generation = 0
    private var closed = false
    private var ownerRetired = false
    private let now: () -> Date
    private var quotaTask: Task<PublishingAIQuota, Error>?
    private var quotaTaskID: UUID?
    private var isCurrent: Bool {
        guard !closed, !ownerRetired, let openedSession else { return false }
        guard client?.session == openedSession else { ownerRetired = true; clearCandidate(); return false }
        return true
    }
    public init(client: (any PublishingAIDraftServing)?, product: ProjectEditProduct, now: @escaping () -> Date = Date.init) {
        self.client = client; self.product = product; openedSession = client?.session; self.now = now
    }
    public var canGenerate: Bool { isCurrent && !busy && quotaTask == nil && client?.canGenerate == true && !((quota?.exhausted) ?? false) }
    public var canRefreshQuota: Bool { isCurrent && !busy && quotaTask == nil && client != nil }
    public func loadQuota() async {
        guard canRefreshQuota, let client else { return }
        let stamp = generation, request = UUID()
        let task = Task<PublishingAIQuota, Error> { try Task.checkCancellation(); return try await client.quota() }
        quotaTask = task; quotaTaskID = request; storedQuotaState = .loading; onChange?()
        defer {
            if quotaTaskID == request { quotaTask = nil; quotaTaskID = nil; onChange?() }
        }
        do {
            let value = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard quotaTaskID == request, stamp == generation else { return }
            guard isCurrent else { clearQuota(); return }
            try Task.checkCancellation()
            guard !task.isCancelled else { throw CancellationError() }
            storedQuota = value; storedQuotaReadAt = now(); storedQuotaState = .fresh
        } catch {
            guard quotaTaskID == request, stamp == generation else { return }
            guard isCurrent else { clearQuota(); return }
            // Retain only the last same-session value, explicitly stale. In particular,
            // a failed refresh cannot turn a known exhausted quota into permission.
            storedQuotaState = .failed
        }
        onChange?()
    }
    public func generate() async {
        _ = candidate // Retire any previous-owner projection before considering a new request.
        guard canGenerate else { messageKey = quota?.exhausted == true ? "contextPublish.ai.exhausted" : "contextPublish.ai.unavailable"; onChange?(); return }
        let prompt = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= 300 else { messageKey = "contextPublish.ai.promptRequired"; onChange?(); return }
        guard let client else { return }
        generation += 1; let stamp = generation; busy = true; messageKey = nil; serverMessage = nil
        if storedQuota != nil { storedQuotaState = .stale }
        onChange?()
        do {
            let value = try await client.generate(idea: prompt, product: product)
            guard stamp == generation, isCurrent, client.session == openedSession, !Task.isCancelled else { return }
            // Replace value and provenance together only after a valid current response.
            storedCandidate = value; storedCandidateIdea = prompt; storedCandidateGeneration = stamp
            busy = false; onChange?(); await loadQuota()
        } catch {
            guard stamp == generation, isCurrent, client.session == openedSession else { return }
            busy = false; messageKey = "contextPublish.ai.failed"
            if case PublishModesError.rejected(let reason) = error, !reason.isEmpty { serverMessage = reason }
            onChange?()
        }
    }
    public func accept(candidateGeneration expected: Int? = nil) -> QuickPublishDraft? {
        guard canAcceptCandidate, expected == nil || expected == storedCandidateGeneration else { return nil }
        let value = candidate?.draft; close(); return value
    }
    private func clearCandidate() {
        storedCandidate = nil; storedCandidateIdea = nil; storedCandidateGeneration = nil
    }
    private func clearQuota() {
        quotaTask?.cancel(); quotaTask = nil; quotaTaskID = nil
        storedQuota = nil; storedQuotaReadAt = nil; storedQuotaState = .unavailable; onChange?()
    }
    public func close() { closed = true; generation += 1; clearQuota(); client?.cancel(); clearCandidate(); idea = ""; busy = false; serverMessage = nil; onChange?() }
}
