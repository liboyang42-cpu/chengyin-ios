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
    var isDurable: Bool { get }
    func intents() throws -> [MerchantBusinessIntent]
    func reserve(_ intent: MerchantBusinessIntent) throws
    func complete(_ intent: MerchantBusinessIntent) throws
}
public extension MerchantBusinessIntentStore { var isDurable: Bool { false } }
/// Persists only operation identity, never tokens, phone numbers, text drafts or QR payloads.
/// Corrupt or inaccessible data blocks dispatch; unknown operations have no time-based expiry.
@MainActor public final class MerchantBusinessFileIntentStore: MerchantBusinessIntentStore {
    public let isDurable = true
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
    public let authorizationGeneration: UUID?
    public let journalRealm: String
    public let mutation: MerchantBusinessMutation
    public let requestID: String
    public let request: MerchantBusinessRequest
    public let scope: MerchantBusinessScope
    public let baseline: MerchantBusinessSnapshot
}
/// A prepared review alone cannot authorize production dispatch. Only this file's
/// coordinator can mint a one-shot ticket after the durable reservation and fences.
@MainActor public final class MerchantBusinessDispatchAuthorization {
    private let review: MerchantBusinessConfirmation
    private var consumed = false
    private let validity: () throws -> Void
    fileprivate init(_ review: MerchantBusinessConfirmation, check: @escaping () throws -> Void) { self.review = review; validity = check }
    func consume(_ review: MerchantBusinessConfirmation) throws {
        guard !consumed, self.review == review else { throw MerchantBusinessFailure.stale }
        consumed = true; try validity()
    }
    func validate(_ mutation: MerchantBusinessMutation, merchantID: Int) throws {
        guard consumed, review.mutation == mutation, review.baseline.access.merchantID == merchantID else { throw MerchantBusinessFailure.stale }
        try validity()
    }
}
@MainActor public final class MerchantBusinessCoordinator {
    public let reader: any MerchantBusinessReading
    public let journal: any MerchantBusinessIntentStore
    public private(set) var snapshot: MerchantBusinessSnapshot?
    public private(set) var confirmation: MerchantBusinessConfirmation?
    public private(set) var receipt: MerchantBusinessReceipt?
    public private(set) var operatorInvitation: MerchantOperatorInvitationPresentation?
    public private(set) var failure: MerchantBusinessFailure?
    public private(set) var failureKey: String?
    public private(set) var isBusy = false
    public private(set) var isLocked = false
    public private(set) var loadedScope: MerchantBusinessScope?
    private var generation = 0
    private var confirmationGeneration = 0
    public init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) { self.reader = reader; self.journal = journal }
    public var isCurrent: Bool { loadedScope != nil && loadedScope == reader.scope }
    public func invalidate() {
        operatorInvitation?.retire(); operatorInvitation = nil
        generation += 1; snapshot = nil; loadedScope = nil; confirmation = nil; receipt = nil; failure = nil; failureKey = nil; isBusy = false
        // Journal remains intact across refresh, navigation, logout, replacement and relaunch.
    }
    public func cancelConfirmation() { confirmationGeneration += 1; confirmation = nil }
    public func load(_ query: MerchantBusinessQuery) async {
        invalidate(); let generation = self.generation, scope = reader.scope
        isBusy = true
        defer { if generation == self.generation { isBusy = false } }
        do {
            let snapshot = try await reader.snapshot(query)
            guard generation == self.generation, scope == reader.scope, !Task.isCancelled else { return }
            self.snapshot = snapshot; loadedScope = scope
            let intents = try journal.intents()
            isLocked = intents.contains { $0.realm == (reader.journalRealm ?? scope?.realm) && $0.accountID == scope?.accountID && $0.merchantID == snapshot.access.merchantID }
        } catch { if generation == self.generation, scope == reader.scope { set(error) } }
    }
    public func prepare(_ mutation: MerchantBusinessMutation) {
        operatorInvitation?.retire(); operatorInvitation = nil
        confirmationGeneration += 1
        confirmation = nil; receipt = nil; failure = nil; failureKey = nil
        guard isCurrent, !isBusy, let scope = loadedScope, let snapshot else { set(MerchantBusinessFailure.stale); return }
        do {
            try mutation.validate(in: snapshot.document, access: snapshot.access, roles: snapshot.roles)
            let requestID = "mb-" + UUID().uuidString.lowercased()
            let journalScope = MerchantBusinessScope(realm: reader.journalRealm ?? scope.realm, accountID: scope.accountID, epoch: scope.epoch)
            let intent = MerchantBusinessIntent(scope: journalScope, merchantID: snapshot.access.merchantID, target: mutation.targetKey, requestID: requestID)
            guard try !journal.intents().contains(where: { $0.sameTarget(as: intent) }) else { throw MerchantBusinessFailure.pending }
            confirmation = .init(id: UUID(), authorizationGeneration: reader.authorizationGeneration, journalRealm: journalScope.realm, mutation: mutation, requestID: requestID, request: try mutation.request(requestID: requestID), scope: scope, baseline: snapshot)
        } catch { set(error) }
    }
    public func confirm(_ review: MerchantBusinessConfirmation) async {
        guard !isBusy, confirmation == review, isCurrent, reader.scope == review.scope else { set(MerchantBusinessFailure.stale); return }
        guard reader.canExecute(review.mutation, merchantID: review.baseline.access.merchantID), reader.canExecuteSyntheticMutation || journal.isDurable else { set(MerchantBusinessFailure.disabled); return }
        confirmation = nil; isBusy = true
        let generation = self.generation, confirmationGeneration = self.confirmationGeneration
        defer { if generation == self.generation { isBusy = false } }
        // Fresh access, exact owner store and fresh target/version; no dispatch while stale.
        do {
            let latest = try await reader.snapshot(review.baseline.document.query)
            guard generation == self.generation, confirmationGeneration == self.confirmationGeneration, reader.scope == review.scope, reader.authorizationGeneration == review.authorizationGeneration, !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            guard latest == review.baseline else { throw MerchantBusinessFailure.conflict }
            try review.mutation.validate(in: latest.document, access: latest.access, roles: latest.roles)
        } catch { if generation == self.generation { set(error) }; return }
        let journalScope = MerchantBusinessScope(realm: review.journalRealm, accountID: review.scope.accountID, epoch: review.scope.epoch)
        let intent = MerchantBusinessIntent(scope: journalScope, merchantID: review.baseline.access.merchantID, target: review.mutation.targetKey, requestID: review.requestID)
        do { try journal.reserve(intent) } catch { set(error); return }
        isLocked = true
        // A journal implementation may reenter. Check cancellation and the exact review
        // again after reservation, then propagate the fence through final fresh reads.
        do {
            func check() throws {
                guard generation == self.generation, confirmationGeneration == self.confirmationGeneration,
                      reader.scope == review.scope, reader.authorizationGeneration == review.authorizationGeneration,
                      !Task.isCancelled else { throw MerchantBusinessFailure.stale }
            }
            try check()
            let result = try await reader.execute(review, authorization: MerchantBusinessDispatchAuthorization(review, check: check), check: check)
            guard generation == self.generation, confirmationGeneration == self.confirmationGeneration, reader.scope == review.scope, reader.authorizationGeneration == review.authorizationGeneration, !Task.isCancelled else { return }
            // Only a confirmed response from this dispatch clears its exact journal record.
            try journal.complete(intent); receipt = result; isLocked = false; snapshot = nil; loadedScope = nil
            if case .inviteOperator = review.mutation {
                operatorInvitation = .init(receipt: result, review: review)
            }
        } catch {
            // Errors received after dispatch are not proof of rollback, including 401/403/409.
            // Preflight permission/auth failures return before the journal is reserved.
            let definite = MerchantMutationFailureDisposition.provesNoDispatch(error)
            if definite { do { try journal.complete(intent) } catch { if generation == self.generation { set(error) }; return } }
            guard generation == self.generation, reader.scope == review.scope else { return }
            isLocked = !definite; set(definite ? error : MerchantBusinessFailure.unknown)
        }
    }
    public func operatorInvitationCode(id: UUID, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String? {
        guard let presentation = operatorInvitation, presentation.id == id else { return nil }
        return presentation.revealedCode(reader: reader, receipt: receipt, now: now, uptime: uptime)
    }
    public func operatorInvitationIsCurrent(id: UUID, now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let presentation = operatorInvitation, presentation.id == id else { return false }
        return presentation.isCurrent(reader: reader, receipt: receipt, now: now, uptime: uptime)
    }
    public func operatorInvitationAccessMatches(id: UUID, access: MerchantBusinessAccess) -> Bool {
        guard let presentation = operatorInvitation, presentation.id == id, presentation.matches(receipt) else { return false }
        return presentation.matchesAccess(access)
    }
    public func retireOperatorInvitation(id: UUID) {
        guard let presentation = operatorInvitation, presentation.id == id else { return }
        let ownsReceipt = presentation.matches(receipt)
        presentation.retire(); operatorInvitation = nil
        // Also remove the original raw response, but never a newer/different receipt.
        if ownsReceipt { receipt = nil }
    }
    private func set(_ error: Error) {
        if let failure = error as? MerchantBusinessFailure { self.failure = failure; failureKey = failure.key }
        else if error as? APIError == .notConfigured { failureKey = "auth.notConfigured" }
        else if error as? APIError == .unauthorized { failureKey = "auth.expired" }
        else if error is CancellationError { failureKey = "merchant.business.stale" }
        else { failureKey = "merchant.business.loadFailed" }
    }
}
