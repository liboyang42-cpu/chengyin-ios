import Foundation

public struct MerchantBusinessIntent: Codable, Equatable {
    public let realm: String
    public let accountID: Int
    public let merchantID: Int
    public let target: String
    public let requestID: String
    public init(scope: MerchantBusinessScope, merchantID: Int, target: String, requestID: String) {
        realm = scope.realm; accountID = scope.accountID; self.merchantID = merchantID; self.target = target; self.requestID = requestID
    }
    public func sameTarget(as other: Self) -> Bool { realm == other.realm && accountID == other.accountID && merchantID == other.merchantID && target == other.target }
}
@MainActor public protocol MerchantBusinessIntentStore: AnyObject {
    func intents() throws -> [MerchantBusinessIntent]
    func reserve(_ intent: MerchantBusinessIntent) throws
    func complete(_ intent: MerchantBusinessIntent) throws
}
/// Persists only operation identity, never tokens, phone numbers, text drafts or QR payloads.
/// Corrupt or inaccessible data blocks dispatch; unknown operations have no time-based expiry.
@MainActor public final class MerchantBusinessFileIntentStore: MerchantBusinessIntentStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func intents() throws -> [MerchantBusinessIntent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([MerchantBusinessIntent].self, from: Data(contentsOf: url)) }
        catch { throw MerchantBusinessFailure.journal }
    }
    public func reserve(_ intent: MerchantBusinessIntent) throws {
        var rows = try intents()
        guard !rows.contains(where: { $0.sameTarget(as: intent) }) else { throw MerchantBusinessFailure.pending }
        rows.append(intent); try write(rows)
    }
    public func complete(_ intent: MerchantBusinessIntent) throws {
        var rows = try intents()
        rows.removeAll { $0 == intent }; try write(rows)
    }
    private func write(_ rows: [MerchantBusinessIntent]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(rows).write(to: url, options: .atomic)
        } catch { throw MerchantBusinessFailure.journal }
    }
}
@MainActor public final class MerchantBusinessMemoryIntentStore: MerchantBusinessIntentStore {
    private var rows: [MerchantBusinessIntent] = []
    public init() {}
    public func intents() throws -> [MerchantBusinessIntent] { rows }
    public func reserve(_ intent: MerchantBusinessIntent) throws {
        guard !rows.contains(where: { $0.sameTarget(as: intent) }) else { throw MerchantBusinessFailure.pending }; rows.append(intent)
    }
    public func complete(_ intent: MerchantBusinessIntent) throws { rows.removeAll { $0 == intent } }
}
public struct MerchantBusinessConfirmation: Equatable, Identifiable {
    public let id: UUID
    public let mutation: MerchantBusinessMutation
    public let requestID: String
    public let request: MerchantBusinessRequest
    public let scope: MerchantBusinessScope
    public let baseline: MerchantBusinessSnapshot
}
@MainActor public final class MerchantBusinessCoordinator {
    public let reader: any MerchantBusinessReading
    public let journal: any MerchantBusinessIntentStore
    public private(set) var snapshot: MerchantBusinessSnapshot?
    public private(set) var confirmation: MerchantBusinessConfirmation?
    public private(set) var receipt: MerchantBusinessReceipt?
    public private(set) var failure: MerchantBusinessFailure?
    public private(set) var failureKey: String?
    public private(set) var isBusy = false
    public private(set) var isLocked = false
    public private(set) var loadedScope: MerchantBusinessScope?
    private var generation = 0
    public init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) { self.reader = reader; self.journal = journal }
    public var isCurrent: Bool { loadedScope != nil && loadedScope == reader.scope }
    public func invalidate() {
        generation += 1; snapshot = nil; loadedScope = nil; confirmation = nil; receipt = nil; failure = nil; failureKey = nil; isBusy = false
        // Journal remains intact across refresh, navigation, logout, replacement and relaunch.
    }
    public func cancelConfirmation() { confirmation = nil }
    public func load(_ query: MerchantBusinessQuery) async {
        invalidate(); let generation = self.generation, scope = reader.scope
        isBusy = true
        defer { if generation == self.generation { isBusy = false } }
        do {
            let snapshot = try await reader.snapshot(query)
            guard generation == self.generation, scope == reader.scope, !Task.isCancelled else { return }
            self.snapshot = snapshot; loadedScope = scope
            let intents = try journal.intents()
            isLocked = intents.contains { $0.realm == scope?.realm && $0.accountID == scope?.accountID && $0.merchantID == snapshot.access.merchantID }
        } catch { if generation == self.generation, scope == reader.scope { set(error) } }
    }
    public func prepare(_ mutation: MerchantBusinessMutation) {
        confirmation = nil; receipt = nil; failure = nil; failureKey = nil
        guard isCurrent, !isBusy, let scope = loadedScope, let snapshot else { set(MerchantBusinessFailure.stale); return }
        do {
            try mutation.validate(in: snapshot.document, access: snapshot.access, roles: snapshot.roles)
            let requestID = "mb-" + UUID().uuidString.lowercased()
            let intent = MerchantBusinessIntent(scope: scope, merchantID: snapshot.access.merchantID, target: mutation.targetKey, requestID: requestID)
            guard try !journal.intents().contains(where: { $0.sameTarget(as: intent) }) else { throw MerchantBusinessFailure.pending }
            confirmation = .init(id: UUID(), mutation: mutation, requestID: requestID, request: try mutation.request(requestID: requestID), scope: scope, baseline: snapshot)
        } catch { set(error) }
    }
    public func confirm(_ review: MerchantBusinessConfirmation) async {
        guard !isBusy, confirmation == review, isCurrent, reader.scope == review.scope else { set(MerchantBusinessFailure.stale); return }
        guard reader.canExecuteSyntheticMutation else { set(MerchantBusinessFailure.disabled); return }
        confirmation = nil; isBusy = true
        let generation = self.generation
        defer { if generation == self.generation { isBusy = false } }
        // Fresh access, exact owner store and fresh target/version; no dispatch while stale.
        do {
            let latest = try await reader.snapshot(review.baseline.document.query)
            guard generation == self.generation, reader.scope == review.scope, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            guard latest == review.baseline else { throw MerchantBusinessFailure.conflict }
            try review.mutation.validate(in: latest.document, access: latest.access, roles: latest.roles)
        } catch { if generation == self.generation { set(error) }; return }
        let intent = MerchantBusinessIntent(scope: review.scope, merchantID: review.baseline.access.merchantID, target: review.mutation.targetKey, requestID: review.requestID)
        do { try journal.reserve(intent) } catch { set(error); return }
        isLocked = true
        do {
            let result = try await reader.execute(review.mutation, requestID: review.requestID, scope: review.scope)
            guard generation == self.generation, reader.scope == review.scope, !Task.isCancelled else { return }
            // Only a confirmed response from this dispatch clears its exact journal record.
            try journal.complete(intent); receipt = result; isLocked = false; snapshot = nil; loadedScope = nil
        } catch {
            // Errors received after dispatch are not proof of rollback, including 401/403/409.
            // Preflight permission/auth failures return before the journal is reserved.
            let definite = MerchantMutationFailureDisposition.provesNoDispatch(error)
            if definite { do { try journal.complete(intent) } catch { if generation == self.generation { set(error) }; return } }
            guard generation == self.generation, reader.scope == review.scope else { return }
            isLocked = !definite; set(definite ? error : MerchantBusinessFailure.unknown)
        }
    }
    private func set(_ error: Error) {
        if let failure = error as? MerchantBusinessFailure { self.failure = failure; failureKey = failure.key }
        else if error as? APIError == .notConfigured { failureKey = "auth.notConfigured" }
        else if error as? APIError == .unauthorized { failureKey = "auth.expired" }
        else if error is CancellationError { failureKey = "merchant.business.stale" }
        else { failureKey = "merchant.business.loadFailed" }
    }
}
