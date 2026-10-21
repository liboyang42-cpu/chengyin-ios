import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One owner-scoped surface for 时光胶囊 / 探索目标 / 导出探索记录.
/// `pendingCapsule` / `pendingGoal` mirror the mini-program clients' in-memory unconfirmed request:
/// they survive leaving and reopening a page in the same session and vanish on any identity change.
@MainActor public protocol RoamPrivateToolsServing: AnyObject {
    var identity: RoamExperienceIdentity? { get }
    var isConfigured: Bool { get }
    /// Writes need their own reviewed approval; reads can be live while writes stay disabled.
    var allowsWrites: Bool { get }
    var isOfflineExample: Bool { get }
    var now: Date { get }
    var pendingCapsule: RoamCapsuleDraft? { get set }
    var pendingGoal: RoamGoalDraft? { get set }
    var unresolvedCapsuleRequestID: String? { get }
    var unresolvedGoalRequestID: String? { get }
    var pendingJournalBlocked: Bool { get }
    var confirmedCancelledGoals: Set<String> { get set }
    func capsules(beforeID: String?) async throws -> RoamCapsulePage
    func capsule(id: String) async throws -> RoamCapsule
    func capsuleReceipt(requestID: String) async throws -> RoamCapsule
    func createCapsule(_ draft: RoamCapsuleDraft) async throws -> RoamCapsule
    func deleteCapsule(id: String) async throws -> RoamCapsule
    func goals(beforeID: String?) async throws -> RoamGoalPage
    func goal(id: String) async throws -> RoamExplorationGoal
    func goalReceipt(requestID: String) async throws -> RoamExplorationGoal
    func createGoal(_ draft: RoamGoalDraft) async throws -> RoamExplorationGoal
    func cancelGoal(id: String) async throws -> RoamExplorationGoal
    func prepareExport(_ request: RoamExportRequest) async throws -> RoamExportCheckpoint
    func exportPage(_ checkpoint: RoamExportCheckpoint) async throws -> RoamExportChunk
}

public extension RoamPrivateToolsServing {
    /// Request ID of an unconfirmed create, including one restored from the pending
    /// journal after a restart (where the original draft itself is gone for good).
    var unresolvedCapsuleRequestID: String? { pendingCapsule?.requestID }
    var unresolvedGoalRequestID: String? { pendingGoal?.requestID }
    /// True when durable pending state could not be read, so writes must fail closed.
    var pendingJournalBlocked: Bool { false }
}

/// Exact archive paths. Reads and writes are approved separately; nothing outside these sets is ever sent.
public enum RoamPrivateToolsRoute {
    public static let capsuleList = "api/capsules/list", capsuleDetail = "api/capsules/detail", capsuleReceipt = "api/capsules/receipt"
    public static let capsuleCreate = "api/capsules/create", capsuleDelete = "api/capsules/delete"
    public static let goalList = "api/exploration-goals/list", goalDetail = "api/exploration-goals/detail", goalReceipt = "api/exploration-goals/receipt"
    public static let goalCreate = "api/exploration-goals/create", goalCancel = "api/exploration-goals/cancel"
    public static let exportPrepare = "api/personal-exploration-export/prepare", exportPage = "api/personal-exploration-export/page"
    public static let reads: Set<String> = [capsuleList, capsuleDetail, capsuleReceipt, goalList, goalDetail, goalReceipt, exportPrepare, exportPage]
    public static let writes: Set<String> = [capsuleCreate, capsuleDelete, goalCreate, goalCancel]
}

/// Source-backed HTTP calls with the mini-program's content types and outcome classes.
public struct RoamPrivateToolsService {
    public let deployment: URL
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        deployment = configuration.baseURL; self.transport = transport
    }
    enum Body { case none, form([String: String]), json(Data) }

    func send(_ path: String, method: String, query: [String: String] = [:], body: Body = .none, token: String) async throws -> RoamPrivateEnvelope {
        guard AuthRequestBuilder.isValidToken(token), RoamPrivateToolsRoute.reads.contains(path) || RoamPrivateToolsRoute.writes.contains(path) else { throw APIError.invalidRequest }
        guard var parts = URLComponents(url: deployment.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        if !query.isEmpty { parts.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) } }
        guard let url = parts.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch body {
        case .none: break
        case .form(let fields):
            var encoder = URLComponents(); encoder.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
            request.httpBody = Data((encoder.percentEncodedQuery ?? "").utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        case .json(let data):
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        let envelope = try RoamPrivateEnvelope.parse(data)
        if envelope.code == 401 { throw APIError.unauthorized }
        return envelope
    }
    private func read(_ path: String, method: String = "GET", query: [String: String] = [:], body: Body = .none, token: String) async throws -> RoamPrivateEnvelope {
        let envelope = try await send(path, method: method, query: query, body: body, token: token)
        guard envelope.code == 200 else { throw APIError.businessCode(envelope.code) }
        guard envelope.hasData else { throw APIError.malformedResponse }
        return envelope
    }
    /// After dispatch only an explicit refusal (`rejectedCodes`) proves nothing was applied.
    private func write(_ path: String, body: Body, rejectedCodes: Set<Int>, token: String) async throws -> RoamPrivateEnvelope {
        try Task.checkCancellation()
        let envelope: RoamPrivateEnvelope
        do { envelope = try await send(path, method: "POST", body: body, token: token) }
        catch APIError.invalidRequest { throw RoamPrivateWriteError.invalidDraft }
        catch APIError.unauthorized { throw APIError.unauthorized }
        catch { throw RoamPrivateWriteError.outcomeUnknown }
        if rejectedCodes.contains(envelope.code) { throw RoamPrivateWriteError.rejected(envelope.message) }
        guard envelope.code == 200, envelope.hasData else { throw RoamPrivateWriteError.outcomeUnknown }
        return envelope
    }

    // MARK: capsules
    public func capsules(beforeID: String?, token: String) async throws -> RoamCapsulePage {
        if let beforeID { guard RoamPrivateRequestID.isCanonicalID(beforeID) else { throw APIError.invalidRequest } }
        var query = ["limit": String(RoamCapsulePage.limit)]; query["beforeId"] = beforeID
        return try RoamCapsulePage.decode(await read(RoamPrivateToolsRoute.capsuleList, query: query, token: token))
    }
    public func capsule(id: String, token: String) async throws -> RoamCapsule {
        guard RoamPrivateRequestID.isCanonicalID(id) else { throw APIError.invalidRequest }
        let value = try RoamCapsule.decode(await read(RoamPrivateToolsRoute.capsuleDetail, query: ["id": id], token: token))
        guard value.id == id else { throw APIError.malformedResponse }
        return value
    }
    public func capsuleReceipt(requestID: String, token: String) async throws -> RoamCapsule {
        guard RoamPrivateRequestID.isValid(requestID) else { throw APIError.invalidRequest }
        return try RoamCapsule.decode(await read(RoamPrivateToolsRoute.capsuleReceipt, query: ["requestId": requestID], token: token))
    }
    /// 400 is a refusal; 409 (request ID reused for other content) and anything else stay unconfirmed.
    public func createCapsule(_ draft: RoamCapsuleDraft, now: Date, token: String) async throws -> RoamCapsule {
        try draft.validate(now: now)
        let envelope = try await write(RoamPrivateToolsRoute.capsuleCreate, body: .json(draft.json), rejectedCodes: [400], token: token)
        do { return try RoamCapsule.decode(envelope) } catch { throw RoamPrivateWriteError.outcomeUnknown }
    }
    public func deleteCapsule(id: String, token: String) async throws -> RoamCapsule {
        guard RoamPrivateRequestID.isCanonicalID(id) else { throw RoamPrivateWriteError.invalidDraft }
        let envelope = try await write(RoamPrivateToolsRoute.capsuleDelete, body: .form(["id": id]), rejectedCodes: [400], token: token)
        guard let value = try? RoamCapsule.decode(envelope), value.id == id, value.state == .deleted else { throw RoamPrivateWriteError.outcomeUnknown }
        return value
    }

    // MARK: goals
    public func goals(beforeID: String?, confirmedCancelled: Set<String> = [], token: String) async throws -> RoamGoalPage {
        if let beforeID { guard RoamPrivateRequestID.isCanonicalID(beforeID) else { throw APIError.invalidRequest } }
        var query = ["limit": String(RoamGoalPage.limit)]; query["beforeId"] = beforeID
        return try RoamGoalPage.decode(await read(RoamPrivateToolsRoute.goalList, query: query, token: token), confirmedCancelled: confirmedCancelled)
    }
    public func goal(id: String, confirmedCancelled: Set<String> = [], token: String) async throws -> RoamExplorationGoal {
        guard RoamPrivateRequestID.isCanonicalID(id) else { throw APIError.invalidRequest }
        let value = try RoamExplorationGoal.decode(await read(RoamPrivateToolsRoute.goalDetail, query: ["id": id], token: token), confirmedCancelled: confirmedCancelled)
        guard value.id == id else { throw APIError.malformedResponse }
        return value
    }
    /// A receipt must echo the original request; `draft` (when known) must match field by field.
    public func goalReceipt(requestID: String, draft: RoamGoalDraft?, confirmedCancelled: Set<String> = [], token: String) async throws -> RoamExplorationGoal {
        guard RoamPrivateRequestID.isValid(requestID) else { throw APIError.invalidRequest }
        let value = try RoamExplorationGoal.decode(await read(RoamPrivateToolsRoute.goalReceipt, query: ["requestId": requestID], token: token), confirmedCancelled: confirmedCancelled)
        guard value.requestID == requestID, draft.map(value.matches) ?? true else { throw APIError.malformedResponse }
        return value
    }
    /// 400 and 409 are refusals for goals (the archive client's REJECTED set).
    public func createGoal(_ draft: RoamGoalDraft, now: Date, confirmedCancelled: Set<String> = [], token: String) async throws -> RoamExplorationGoal {
        try draft.validate(now: now)
        let envelope = try await write(RoamPrivateToolsRoute.goalCreate, body: .json(draft.json), rejectedCodes: [400, 409], token: token)
        guard let value = try? RoamExplorationGoal.decode(envelope, confirmedCancelled: confirmedCancelled), value.matches(draft) else { throw RoamPrivateWriteError.outcomeUnknown }
        return value
    }
    public func cancelGoal(id: String, token: String) async throws -> RoamExplorationGoal {
        guard RoamPrivateRequestID.isCanonicalID(id) else { throw RoamPrivateWriteError.invalidDraft }
        let envelope = try await write(RoamPrivateToolsRoute.goalCancel, body: .form(["id": id]), rejectedCodes: [400, 409], token: token)
        guard let value = try? RoamExplorationGoal.decode(envelope), value.id == id, value.state == .cancelled else { throw RoamPrivateWriteError.outcomeUnknown }
        return value
    }

    // MARK: export (POST reads that never change records)
    public func prepareExport(_ request: RoamExportRequest, token: String) async throws -> RoamExportCheckpoint {
        try request.validate()
        return try RoamExportCheckpoint.prepared(await read(RoamPrivateToolsRoute.exportPrepare, method: "POST", body: .json(request.json), token: token), request: request)
    }
    public func exportPage(_ checkpoint: RoamExportCheckpoint, token: String) async throws -> RoamExportChunk {
        guard let cursor = checkpoint.cursor, !checkpoint.complete, !checkpoint.changed else { throw APIError.invalidRequest }
        let body = Data(RoamOrderedJSON.Value.object([("cursor", .string(cursor))]).text.utf8)
        return try RoamExportChunk.decode(await read(RoamPrivateToolsRoute.exportPage, method: "POST", body: .json(body), token: token), original: checkpoint)
    }
}

/// Independently reviewed owner-only approval. Production composition supplies none today, so every
/// call fails closed as not configured; the composition transport also refuses these paths.
@MainActor public final class RoamPrivateToolsAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        guard context.market == .china, context.role == "player", context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token),
              approval.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              approval.accountID == context.session.accountID,
              !approval.paths.isEmpty, approval.paths.isSubset(of: Self.universe) else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    /// 那年今日 / 月度回顾 reads, the private-tool reads and the private-tool writes; nothing else.
    public static let universe = Set(RoamPassportToolsService.paths).union(RoamPrivateToolsRoute.reads).union(RoamPrivateToolsRoute.writes)
    public func allows(_ paths: Set<String>) -> Bool { !isRevoked && paths.isSubset(of: endpoints.paths) }
    public var allowsWrites: Bool { allows(RoamPrivateToolsRoute.writes) }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool { !isRevoked && ContentDraftContextFence.matches(context, current) }
}

/// Session-scoped reader: binds every call to the current account/epoch/token and its approval,
/// rechecks after the response, and clears pending requests when the identity changes.
@MainActor public final class RoamPrivateToolsSessionReader: RoamPrivateToolsServing {
    private let service: RoamPrivateToolsService?
    private let current: () -> RuntimeDependencyContext?
    private let selectAccess: (RuntimeDependencyContext) -> RoamPrivateToolsAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var bound: RuntimeDependencyContext?
    private var storedCapsule: RoamCapsuleDraft?
    private var storedGoal: RoamGoalDraft?
    private var storedCancelled: Set<String> = []
    private let journal: RoamPrivatePendingJournal?
    private var restoredCapsuleRequestID: String?
    private var restoredGoalRequestID: String?
    private var journalScope: RoamHistoryScope?
    public private(set) var pendingJournalBlocked = false
    public init(service: RoamPrivateToolsService?, current: @escaping () -> RuntimeDependencyContext?,
                access: @escaping (RuntimeDependencyContext) -> RoamPrivateToolsAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in },
                journal: RoamPrivatePendingJournal? = .live()) {
        self.service = service; self.current = current; selectAccess = access; self.onUnauthorized = onUnauthorized
        self.journal = journal
    }
    private func synchronize() -> RuntimeDependencyContext? {
        let context = current()
        let same: Bool
        if let context, let bound { same = ContentDraftContextFence.matches(bound, context) } else { same = context == nil && bound == nil }
        if !same { bound = context; storedCapsule = nil; storedGoal = nil; storedCancelled = [] }
        refreshJournal(for: context)
        return context
    }
    private func scope(for context: RuntimeDependencyContext?) -> RoamHistoryScope? {
        guard let context else { return nil }
        return try? RoamHistoryScope(market: context.market.rawValue, deployment: context.baseURL,
                                     accountID: context.session.accountID, namespace: context.session.namespace)
    }
    /// Reload the durable locks for the bound scope. Corrupt or unreadable journal bytes
    /// fail closed: no restored ID is trusted and every create is refused before dispatch.
    private func refreshJournal(for context: RuntimeDependencyContext?) {
        let currentScope = scope(for: context)
        guard currentScope != journalScope || currentScope == nil else { return }
        journalScope = currentScope
        restoredCapsuleRequestID = nil; restoredGoalRequestID = nil; pendingJournalBlocked = false
        guard let journal, let currentScope else { return }
        do {
            restoredCapsuleRequestID = try journal.entry(kind: .capsuleCreate, scope: currentScope)?.requestID
            restoredGoalRequestID = try journal.entry(kind: .goalCreate, scope: currentScope)?.requestID
        } catch {
            restoredCapsuleRequestID = nil; restoredGoalRequestID = nil; pendingJournalBlocked = true
        }
    }
    public var unresolvedCapsuleRequestID: String? {
        _ = synchronize()
        return storedCapsule?.requestID ?? restoredCapsuleRequestID
    }
    public var unresolvedGoalRequestID: String? {
        _ = synchronize()
        return storedGoal?.requestID ?? restoredGoalRequestID
    }
    /// Make the minimal identity durable before dispatch. A save failure, a corrupt
    /// journal or a slot held by a different request all stop the write here, so no
    /// request is ever sent without its restart-surviving lock already in place.
    private func persistBeforeDispatch(kind: RoamPrivatePendingKind, requestID: String) throws {
        guard let context = synchronize(), let ownerScope = scope(for: context) else { throw APIError.unauthorized }
        guard !pendingJournalBlocked else { throw RoamPrivatePendingJournalError.corrupted }
        let restored = kind == .capsuleCreate ? restoredCapsuleRequestID : restoredGoalRequestID
        if let restored, restored != requestID { throw RoamPrivateWriteError.pendingMismatch }
        guard let journal else { throw RoamPrivatePendingJournalError.unavailable }
        let alreadyHeld = restored == requestID
        do { try journal.record(kind: kind, requestID: requestID, scope: ownerScope, now: now) }
        catch let error as RoamPrivatePendingJournalError where error == .locked { throw RoamPrivateWriteError.pendingMismatch }
        // A lock that already survived an earlier attempt cannot be cleared by a later refusal.
        if alreadyHeld { try? journal.requireReceipt(kind: kind, requestID: requestID, scope: ownerScope) }
        if kind == .capsuleCreate { restoredCapsuleRequestID = requestID } else { restoredGoalRequestID = requestID }
    }
    /// UNKNOWN means the attempt may already have landed. Remember that on disk
    /// before any later refusal is allowed to look like proof it did not.
    private func noteReceiptRequired(kind: RoamPrivatePendingKind, requestID: String) {
        guard let context = synchronize(), let ownerScope = scope(for: context), let journal else { return }
        try? journal.requireReceipt(kind: kind, requestID: requestID, scope: ownerScope)
    }
    private func durableReceiptRequired(kind: RoamPrivatePendingKind, requestID: String) -> Bool {
        guard let context = synchronize(), let ownerScope = scope(for: context), let journal,
              let entry = try? journal.entry(kind: kind, scope: ownerScope) else { return false }
        return entry.requestID == requestID && entry.receiptRequired
    }
    /// Confirmation-only cleanup. A failed removal keeps the restored lock (fail closed);
    /// the next successful receipt readback retries the removal.
    private func clearAfterConfirmation(kind: RoamPrivatePendingKind, requestID: String) {
        guard let context = synchronize(), let ownerScope = scope(for: context), let journal else { return }
        do {
            try journal.clear(kind: kind, requestID: requestID, scope: ownerScope)
            if kind == .capsuleCreate { restoredCapsuleRequestID = nil } else { restoredGoalRequestID = nil }
        } catch {
            if kind == .capsuleCreate { restoredCapsuleRequestID = requestID } else { restoredGoalRequestID = requestID }
        }
    }
    public var identity: RoamExperienceIdentity? {
        guard let context = synchronize(), let scope = try? RoamHistoryScope(market: context.market.rawValue, deployment: context.baseURL,
              accountID: context.session.accountID, namespace: context.session.namespace) else { return nil }
        return .init(scope: scope, epoch: context.session.epoch)
    }
    private func approved() -> (RuntimeDependencyContext, RoamPrivateToolsAccess, RoamPrivateToolsService)? {
        guard let context = synchronize(), let service, let access = selectAccess(context), access.matches(context),
              access.allows(RoamPrivateToolsRoute.reads),
              service.deployment.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) else { return nil }
        return (context, access, service)
    }
    public var isConfigured: Bool { approved() != nil }
    public var allowsWrites: Bool { approved()?.1.allowsWrites == true }
    public var isOfflineExample: Bool { false }
    public var now: Date { Date() }
    public var pendingCapsule: RoamCapsuleDraft? {
        get { _ = synchronize(); return storedCapsule }
        set { _ = synchronize(); storedCapsule = newValue }
    }
    public var pendingGoal: RoamGoalDraft? {
        get { _ = synchronize(); return storedGoal }
        set { _ = synchronize(); storedGoal = newValue }
    }
    public var confirmedCancelledGoals: Set<String> {
        get { _ = synchronize(); return storedCancelled }
        set { _ = synchronize(); storedCancelled = newValue }
    }
    private func run<T>(write: Bool = false, _ body: (RoamPrivateToolsService, String) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard let context = current() else { throw APIError.unauthorized }
        guard let approval = approved() else { throw APIError.notConfigured }
        let (captured, access, service) = approval
        if write { guard access.allowsWrites else { throw RoamPrivateWriteError.writesDisabled } }
        func valid() -> Bool {
            guard let fresh = current(), ContentDraftContextFence.matches(captured, fresh), ContentDraftContextFence.matches(context, fresh) else { return false }
            return approved()?.1 === access
        }
        do {
            let value = try await body(service, captured.session.token)
            guard valid() else { if write { throw RoamPrivateWriteError.changedContext }; throw CancellationError() }
            return value
        } catch {
            guard valid() else { if write { throw RoamPrivateWriteError.changedContext }; throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(captured) }
            throw error
        }
    }
    public func capsules(beforeID: String?) async throws -> RoamCapsulePage { try await run { try await $0.capsules(beforeID: beforeID, token: $1) } }
    public func capsule(id: String) async throws -> RoamCapsule { try await run { try await $0.capsule(id: id, token: $1) } }
    public func capsuleReceipt(requestID: String) async throws -> RoamCapsule {
        let value = try await run { try await $0.capsuleReceipt(requestID: requestID, token: $1) }
        // Only a receipt that actually came back releases the durable lock.
        if unresolvedCapsuleRequestID == requestID { clearAfterConfirmation(kind: .capsuleCreate, requestID: requestID) }
        return value
    }
    public func createCapsule(_ draft: RoamCapsuleDraft) async throws -> RoamCapsule {
        guard approved() != nil else { throw APIError.notConfigured }
        try persistBeforeDispatch(kind: .capsuleCreate, requestID: draft.requestID)
        let at = now
        do {
            let value = try await run(write: true) { try await $0.createCapsule(draft, now: at, token: $1) }
            clearAfterConfirmation(kind: .capsuleCreate, requestID: draft.requestID)
            return value
        } catch {
            if (error as? RoamPrivateWriteError) == .outcomeUnknown {
                noteReceiptRequired(kind: .capsuleCreate, requestID: draft.requestID)
            }
            releaseLockIfRefused(error, kind: .capsuleCreate, requestID: draft.requestID)
            throw error
        }
    }
    /// A refusal of a never-uncertain attempt proves nothing was applied, so the lock is released.
    /// Once the same request has been UNKNOWN, only an authoritative receipt may clear it:
    /// a later rejection of the retry does not prove the first attempt failed.
    private func releaseLockIfRefused(_ error: Error, kind: RoamPrivatePendingKind, requestID: String) {
        let releasesLock: Bool
        if let write = error as? RoamPrivateWriteError {
            switch write {
            case .rejected, .writesDisabled, .invalidDraft: releasesLock = true
            default: releasesLock = false
            }
        } else { releasesLock = (error as? APIError) == .notConfigured }
        if releasesLock, !durableReceiptRequired(kind: kind, requestID: requestID) {
            clearAfterConfirmation(kind: kind, requestID: requestID)
        }
    }
    public func deleteCapsule(id: String) async throws -> RoamCapsule { try await run(write: true) { try await $0.deleteCapsule(id: id, token: $1) } }
    public func goals(beforeID: String?) async throws -> RoamGoalPage {
        let cancelled = confirmedCancelledGoals
        return try await run { try await $0.goals(beforeID: beforeID, confirmedCancelled: cancelled, token: $1) }
    }
    public func goal(id: String) async throws -> RoamExplorationGoal {
        let cancelled = confirmedCancelledGoals
        return try await run { try await $0.goal(id: id, confirmedCancelled: cancelled, token: $1) }
    }
    public func goalReceipt(requestID: String) async throws -> RoamExplorationGoal {
        let cancelled = confirmedCancelledGoals, draft = pendingGoal.flatMap { $0.requestID == requestID ? $0 : nil }
        let value = try await run { try await $0.goalReceipt(requestID: requestID, draft: draft, confirmedCancelled: cancelled, token: $1) }
        if unresolvedGoalRequestID == requestID { clearAfterConfirmation(kind: .goalCreate, requestID: requestID) }
        return value
    }
    public func createGoal(_ draft: RoamGoalDraft) async throws -> RoamExplorationGoal {
        guard approved() != nil else { throw APIError.notConfigured }
        try persistBeforeDispatch(kind: .goalCreate, requestID: draft.requestID)
        let at = now, cancelled = confirmedCancelledGoals
        do {
            let value = try await run(write: true) { try await $0.createGoal(draft, now: at, confirmedCancelled: cancelled, token: $1) }
            clearAfterConfirmation(kind: .goalCreate, requestID: draft.requestID)
            return value
        } catch {
            if (error as? RoamPrivateWriteError) == .outcomeUnknown {
                noteReceiptRequired(kind: .goalCreate, requestID: draft.requestID)
            }
            releaseLockIfRefused(error, kind: .goalCreate, requestID: draft.requestID)
            throw error
        }
    }
    public func cancelGoal(id: String) async throws -> RoamExplorationGoal {
        let value = try await run(write: true) { try await $0.cancelGoal(id: id, token: $1) }
        confirmedCancelledGoals.insert(id)
        return value
    }
    public func prepareExport(_ request: RoamExportRequest) async throws -> RoamExportCheckpoint { try await run { try await $0.prepareExport(request, token: $1) } }
    public func exportPage(_ checkpoint: RoamExportCheckpoint) async throws -> RoamExportChunk { try await run { try await $0.exportPage(checkpoint, token: $1) } }
}

/// Session-scoped 那年今日 / 月度回顾 reader with the same approval fence. Without an approval it reports
/// not configured, which the views show honestly.
@MainActor public final class RoamPassportToolsSessionReader: RoamPassportToolsReading {
    private enum ApprovalToken {
        case privateAccess(RoamPrivateToolsAccess)
        case readAccess(RoamPassportToolsReadAccess)
        func isSame(as other: ApprovalToken) -> Bool {
            switch (self, other) {
            case (.privateAccess(let lhs), .privateAccess(let rhs)): return lhs === rhs
            case (.readAccess(let lhs), .readAccess(let rhs)): return lhs === rhs
            default: return false
            }
        }
    }
    private let service: RoamPassportToolsService?
    private let currentSession: (() -> RoamExperienceSession?)?
    private let current: () -> RuntimeDependencyContext?
    private let selectAccess: (RuntimeDependencyContext) -> RoamPrivateToolsAccess?
    private let selectReadAccess: (RuntimeDependencyContext) -> RoamPassportToolsReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private let onUnauthorizedSession: (RoamExperienceSession) -> Void
    public init(service: RoamPassportToolsService?, current: @escaping () -> RuntimeDependencyContext?,
                access: @escaping (RuntimeDependencyContext) -> RoamPrivateToolsAccess?,
                readAccess: @escaping (RuntimeDependencyContext) -> RoamPassportToolsReadAccess? = { _ in nil },
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.service = service; self.currentSession = nil; self.current = current
        self.selectAccess = access; self.selectReadAccess = readAccess
        self.onUnauthorized = onUnauthorized; self.onUnauthorizedSession = { _ in }
    }
    public init(configuration: APIConfiguration?, transport: any HTTPTransport,
                currentSession: @escaping () -> RoamExperienceSession?,
                current: @escaping () -> RuntimeDependencyContext?,
                access: @escaping (RuntimeDependencyContext) -> RoamPassportToolsReadAccess?,
                onUnauthorized: @escaping (RoamExperienceSession) -> Void = { _ in }) {
        self.service = configuration.map { RoamPassportToolsService(configuration: $0, transport: transport) }
        self.currentSession = currentSession; self.current = current
        self.selectAccess = { _ in nil }; self.selectReadAccess = access
        self.onUnauthorized = { _ in }; self.onUnauthorizedSession = onUnauthorized
    }
    public var identity: RoamExperienceIdentity? {
        if let currentSession { return currentSession()?.identity }
        guard let context = current(), let scope = try? RoamHistoryScope(market: context.market.rawValue, deployment: context.baseURL,
              accountID: context.session.accountID, namespace: context.session.namespace) else { return nil }
        return .init(scope: scope, epoch: context.session.epoch)
    }
    private func approved() -> (RuntimeDependencyContext, ApprovalToken, RoamPassportToolsService)? {
        if let currentSession, currentSession() == nil { return nil }
        guard let context = current(), let service,
              service.deployment.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) else { return nil }
        if let access = selectAccess(context), access.matches(context), access.allows(Set(RoamPassportToolsService.paths)) {
            return (context, .privateAccess(access), service)
        }
        if let readAccess = selectReadAccess(context), readAccess.matches(context),
           readAccess.endpoints.paths == Set(RoamPassportToolsService.paths) {
            return (context, .readAccess(readAccess), service)
        }
        return nil
    }
    public var isConfigured: Bool { approved() != nil }
    public var isOfflineExample: Bool { false }
    private func run<T>(_ body: (RoamPassportToolsService, String) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let capturedSession: RoamExperienceSession?
        if let currentSession {
            guard let session = currentSession() else { throw APIError.unauthorized }
            capturedSession = session
        } else {
            capturedSession = nil
        }
        guard current() != nil else { throw APIError.unauthorized }
        guard let approval = approved() else { throw APIError.notConfigured }
        let (captured, accessToken, service) = approval
        let token = capturedSession?.mutationToken ?? captured.session.token
        func valid() -> Bool {
            guard !Task.isCancelled else { return false }
            if let currentSession, currentSession() != capturedSession { return false }
            guard let fresh = current(), ContentDraftContextFence.matches(captured, fresh),
                  let currentApproval = approved() else { return false }
            return currentApproval.1.isSame(as: accessToken)
        }
        do {
            let value = try await body(service, token)
            guard valid() else { throw CancellationError() }
            return value
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized {
                onUnauthorized(captured)
                if let capturedSession { onUnauthorizedSession(capturedSession) }
            }
            throw error
        }
    }
    public func anniversary(_ query: RoamAnniversaryQuery, boundary: RoamAnniversaryMemory?) async throws -> RoamAnniversaryPage {
        try await run { try await $0.anniversary(query, boundary: boundary, token: $1) }
    }
    public func monthlyRecap(_ query: RoamMonthlyRecapQuery) async throws -> RoamMonthlyRecapPage {
        try await run { try await $0.monthlyRecap(query, token: $1) }
    }
}
