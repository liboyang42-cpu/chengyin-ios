import Foundation

public struct MerchantOperationsSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public let storageNamespace: String
    public var ownerKey: String { "\(storageNamespace.utf8.count):\(storageNamespace):\(accountID)" }
    public init(accountID: Int, epoch: UInt64, token: String, storageNamespace: String = "") throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token; self.storageNamespace = storageNamespace
    }
}
@MainActor public protocol MerchantOperationsReading: AnyObject {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    var canSave: Bool { get }
    func hasPending(_ destination: MerchantOperationsDestination) -> Bool
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws
    func access() async throws -> MerchantOperationsAccess
    func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument
    /// Only the DEBUG synthetic reader implements this. Live readers always reject it.
    func saveExample(_ draft: MerchantOperationsDraft) async throws
}
@MainActor public final class MerchantOperationsSessionReader: MerchantOperationsReading {
    private let service: MerchantOperationsService?
    private let currentSession: () -> MerchantOperationsSession?
    private let onUnauthorized: (MerchantOperationsSession) -> Void
    private var snapshot: MerchantOperationsSession?
    private var stamp = UUID()
    private let approval: OperationEndpointApproval?
    private let journal: (any OperationPendingJournal)?
    public var canSave: Bool { service != nil && approval != nil && journal != nil }
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentSession()
        if current != snapshot { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: MerchantOperationsService?, currentSession: @escaping () -> MerchantOperationsSession?, approval: OperationEndpointApproval? = nil, journal: (any OperationPendingJournal)? = nil, onUnauthorized: @escaping (MerchantOperationsSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized; snapshot = currentSession(); self.approval = approval; self.journal = journal
    }
    public func access() async throws -> MerchantOperationsAccess { try await read { try await $0.access(token: $1) } }
    public func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument {
        let expected = currentSession()
        return try await read { service, token in
            let access = try await service.access(token: token)
            guard !Task.isCancelled, expected == currentSession() else { throw CancellationError() }
            return try await service.document(destination, access: access, token: token)
        }
    }
    public func saveExample(_ draft: MerchantOperationsDraft) async throws { throw MerchantOperationsFailure.liveWritesDisabled }
    public func hasPending(_ destination: MerchantOperationsDestination) -> Bool {
        guard let session = currentSession(), let journal else { return false }
        do { return try journal.pending(ownerKey: session.ownerKey, targetKey: destination.pendingTarget) != nil }
        catch { return true }
    }
    public func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws {
        guard let session = currentSession(), let service, let approval, let journal else { throw MerchantOperationsFailure.liveWritesDisabled }
        _ = try await service.save(draft, token: session.token, approval: approval, namespace: session.storageNamespace,
                                   accountID: session.accountID, baseline: baseline, journal: journal) {
            try Task.checkCancellation()
            guard self.currentSession() == session else { throw CancellationError() }
        }
    }
    private func read<Value>(_ operation: (MerchantOperationsService, String) async throws -> Value) async throws -> Value {
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service else { throw APIError.notConfigured }
        let captured = scope
        try Task.checkCancellation()
        do {
            let value = try await operation(service, session.token)
            guard !Task.isCancelled, currentSession() == session, captured == scope else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentSession() == session, captured == scope else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}

public struct MerchantOperationsConfirmation: Identifiable, Equatable {
    public let id: UUID
    public let draft: MerchantOperationsDraft
    fileprivate let baseline: MerchantOperationsDraft
    fileprivate let scope: UUID
}
/// Unknown writes remain locked; approved readers restore their minimal durable replay lock.
@MainActor public final class MerchantOperationsCoordinator {
    public let reader: any MerchantOperationsReading
    public let destination: MerchantOperationsDestination
    public private(set) var document: MerchantOperationsDocument?
    public private(set) var baseline: MerchantOperationsDraft?
    public private(set) var draft: MerchantOperationsDraft?
    public private(set) var confirmation: MerchantOperationsConfirmation?
    public private(set) var issue: MerchantOperationsIssue?
    public private(set) var isBusy = false
    public private(set) var isLocked = false
    public private(set) var exampleSaved = false
    public private(set) var loadedScope: UUID?
    private var generation = 0
    public init(reader: any MerchantOperationsReading, destination: MerchantOperationsDestination) { self.reader = reader; self.destination = destination }
    public var isDirty: Bool { draft != baseline }
    public var isCurrent: Bool { loadedScope == reader.scope && reader.isAuthenticated }
    public var canReview: Bool { isCurrent && !isBusy && !isLocked && isDirty && draft?.blocker == nil }
    public func invalidate() {
        generation += 1; document = nil; baseline = nil; draft = nil; confirmation = nil
        issue = nil; exampleSaved = false; loadedScope = nil; isBusy = false
        // An unknown operation is not proof of failure, even across account changes.
    }
    public func edit(_ value: MerchantOperationsDraft) {
        guard isCurrent, !isBusy, !isLocked, value.destination == destination else { return }
        draft = value; confirmation = nil; issue = nil; exampleSaved = false
    }
    public func discardChanges() { draft = baseline; confirmation = nil; issue = nil; exampleSaved = false }
    public func cancelConfirmation() { confirmation = nil }
    public func leaveScreen() { invalidate() }
    public func load() async {
        guard !isBusy else { return }
        invalidate(); let operation = generation, scope = reader.scope
        guard reader.isConfigured else { loadedScope = scope; issue = .key("auth.notConfigured"); return }
        guard reader.isAuthenticated else { loadedScope = scope; issue = .key("merchant.operations.signedOut"); return }
        isBusy = true
        defer { if generation == operation { isBusy = false } }
        do {
            let result = try await reader.document(destination)
            guard !Task.isCancelled, operation == generation, reader.scope == scope, reader.isAuthenticated else { return }
            document = result; loadedScope = scope; isLocked = reader.hasPending(destination)
            if case .draft(let value) = result { baseline = value; draft = value }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), operation == generation, reader.scope == scope else { return }
            loadedScope = scope; issue = .init(error)
        }
    }
    public func prepare() {
        guard canReview, let draft, let baseline, let loadedScope else { return }
        do { _ = try draft.previews() }
        catch { issue = .key("merchant.operations.invalidDraft"); return }
        confirmation = .init(id: UUID(), draft: draft, baseline: baseline, scope: loadedScope)
    }
    public func confirm(_ value: MerchantOperationsConfirmation) async {
        guard canReview, confirmation == value, reader.scope == value.scope else { return }
        confirmation = nil
        guard reader.canSave else { issue = .key("merchant.operations.liveDisabled"); return }
        isBusy = true; let operation = generation
        defer { if operation == generation { isBusy = false } }
        do {
            let latest = try await reader.document(destination)
            guard !Task.isCancelled, operation == generation, reader.scope == value.scope, reader.isAuthenticated else { return }
            guard latest == .draft(value.baseline) else {
                issue = .key("merchant.operations.conflict"); return
            }
        } catch {
            guard !Task.isCancelled, operation == generation, reader.scope == value.scope else { return }
            issue = .init(error); return
        }
        isLocked = true
        do {
            try await reader.saveReviewed(value.draft, baseline: value.baseline)
            guard !Task.isCancelled, operation == generation, reader.scope == value.scope, reader.isAuthenticated else { return }
            isLocked = false; baseline = value.draft; draft = value.draft; document = .draft(value.draft); exampleSaved = reader.isOfflineExample; issue = reader.isOfflineExample ? nil : .key("merchant.operations.acknowledged")
        } catch {
            if error as? MerchantOperationsFailure == .notSent { isLocked = false }
            if let failure = error as? MerchantOperationsFailure, case .rejected = failure { isLocked = false }
            guard !Task.isCancelled, operation == generation, reader.scope == value.scope else { return }
            if let failure = error as? MerchantOperationsFailure, case .partial = failure { issue = .key("merchant.operations.partialOutcome") }
            else { issue = isLocked ? .key("merchant.operations.unknownOutcome") : .init(error) }
        }
    }
}

public extension MerchantOperationsReading {
    var canSave: Bool { isOfflineExample }
    func hasPending(_ destination: MerchantOperationsDestination) -> Bool { false }
    func saveReviewed(_ draft: MerchantOperationsDraft, baseline: MerchantOperationsDraft) async throws { try await saveExample(draft) }
}
