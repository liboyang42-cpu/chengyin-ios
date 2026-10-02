import Foundation
import Observation
import CryptoKit

@MainActor @Observable public final class ClubOwnerRefundCoordinator {
    private struct Entry { let identity: ClubReadIdentity; let authorization: UUID?; var status = ClubOwnerRefundStatus() }
    private let access: any ClubOwnerRefundAccess
    private let locks: any ClubOwnerRefundLocking
    private let now: () -> Date
    private var entries: [String: Entry] = [:]
    private var pending: [String: ClubOwnerRefundReview] = [:]
    private var owners: [String: UUID] = [:]
    private var generations: [String: UUID] = [:]
    private var parentKeys: [String: String] = [:]
    public var identity: ClubReadIdentity? { access.identity }
    public var canDispatchOffline: Bool { access.canDispatchOffline }
    public var canDispatch: Bool { access.canDispatch }
    public init(access: any ClubOwnerRefundAccess, locks: any ClubOwnerRefundLocking, now: @escaping () -> Date = Date.init) {
        self.access = access; self.locks = locks; self.now = now
    }
    private func key(_ target: ClubOwnerRefundTarget, identity: ClubReadIdentity, namespace: String) throws -> String {
        guard let accountID = identity.accountID, accountID > 0, !namespace.isEmpty else { throw ClubOwnerRefundFailure.signedOut }
        // Epoch deliberately absent from durable lock identity, present in every review/receipt guard.
        return String(decoding: try JSONEncoder().encode([namespace, String(accountID), String(target.clubID), String(target.registrationID)]), as: UTF8.self)
    }
    private func relatedKeys(_ evidence: ClubOwnerRefundEvidence, identity: ClubReadIdentity, namespace: String) throws -> [String] {
        let registration = try key(evidence.target, identity: identity, namespace: namespace)
        // The checkin contract's orderNo is parent_order_no. Hash exact nonblank bytes;
        // never group by a guessed/display-normalized order number or persist raw order text.
        // Backend StringUtils uses Java String.trim(), which removes only UTF-16
        // units <= U+0020. Broader Unicode trimming would erase a real parent key.
        guard let orderNo = evidence.orderNo, orderNo.utf16.contains(where: { $0 > 0x20 }) else {
            // Missing later data cannot erase a parent binding already proven in this session.
            if let known = parentKeys[registration] { return [registration, known] }
            return [registration]
        }
        guard let accountID = identity.accountID else { throw ClubOwnerRefundFailure.signedOut }
        let tuple = try JSONEncoder().encode([namespace, String(accountID), "parent-order", orderNo])
        let digest = SHA256.hash(data: tuple).map { String(format: "%02x", $0) }.joined()
        let parent = "club-owner-refund-parent:" + digest
        if let known = parentKeys[registration], known != parent, try locks.contains(known) { throw ClubOwnerRefundFailure.locked }
        parentKeys[registration] = parent
        return [registration, parent]
    }
    private func locked(_ registration: String) throws -> Bool {
        if try locks.contains(registration) { return true }
        if let parent = parentKeys[registration] { return try locks.contains(parent) }
        return false
    }
    private func mutate(_ key: String, _ body: (inout ClubOwnerRefundStatus) -> Void) {
        guard var entry = entries[key] else { return }; body(&entry.status); entries[key] = entry
    }
    public func state(_ target: ClubOwnerRefundTarget) -> ClubOwnerRefundStatus {
        guard let identity else { return .init(phase: .notSent, failure: .signedOut) }
        do {
            let key = try key(target, identity: identity, namespace: access.namespace)
            if let entry = entries[key], entry.identity == identity, entry.authorization == access.authorizationGeneration {
                if [.idle, .notSent].contains(entry.status.phase), try locked(key) { return .init(phase: .outcomeUnknown) }
                return entry.status
            }
            return try locked(key) ? .init(phase: .outcomeUnknown) : .init()
        } catch { return .init(phase: .notSent, failure: .storage) }
    }
    private func current(_ identity: ClubReadIdentity, _ namespace: String, _ key: String, _ generation: UUID) -> Bool {
        access.identity == identity && access.namespace == namespace && entries[key]?.authorization == access.authorizationGeneration && generations[key] == generation && !Task.isCancelled
    }
    private func issue(_ error: Error) -> ClubOwnerRefundFailure {
        if let issue = error as? ClubOwnerRefundFailure { return issue }
        if error as? ClubGovernanceFailure == .signedOut { return .signedOut }
        if error as? ClubGovernanceFailure == .forbidden { return .ineligible }
        return .unknown
    }
    public func prepare(_ target: ClubOwnerRefundTarget, ownerID: UUID) async throws -> ClubOwnerRefundReview {
        guard let identity else { throw ClubOwnerRefundFailure.signedOut }
        let namespace = access.namespace, key = try key(target, identity: identity, namespace: access.namespace)
        guard !state(target).inFlight, pending[key] == nil else { throw ClubOwnerRefundFailure.busy }
        guard !(try locked(key)) else { throw ClubOwnerRefundFailure.locked }
        let generation = UUID(); generations[key] = generation; owners[key] = ownerID
        entries[key] = .init(identity: identity, authorization: access.authorizationGeneration, status: .init(phase: .preparing))
        do {
            let evidence = try await access.evidence(target)
            guard current(identity, namespace, key, generation) else { throw ClubOwnerRefundFailure.stale }
            guard evidence.target == target else { throw ClubOwnerRefundFailure.stale }
            _ = try relatedKeys(evidence, identity: identity, namespace: namespace)
            guard !(try locked(key)) else { throw ClubOwnerRefundFailure.locked }
            guard evidence.eligible else { throw ClubOwnerRefundFailure.ineligible }
            let review = ClubOwnerRefundReview(identity: identity, namespace: namespace, evidence: evidence, createdAt: now(), ownerID: ownerID)
            pending[key] = review; mutate(key) { $0.phase = .reviewing }; return review
        } catch {
            if generations[key] == generation { mutate(key) { $0.phase = issue(error) == .locked ? .outcomeUnknown : .notSent; $0.failure = issue(error) }; owners[key] = nil }
            throw error
        }
    }
    public func cancel(_ review: ClubOwnerRefundReview) {
        guard let key = try? key(review.evidence.target, identity: review.identity, namespace: review.namespace), pending[key] == review else { return }
        generations[key] = UUID(); pending[key] = nil; owners[key] = nil
        mutate(key) { $0 = .init(phase: .notSent) }
    }
    public func leave(ownerID: UUID) {
        for key in Array(owners.keys) where owners[key] == ownerID {
            guard let phase = entries[key]?.status.phase, [.preparing, .reviewing, .preflighting].contains(phase) else { continue }
            generations[key] = UUID(); pending[key] = nil; owners[key] = nil
            mutate(key) { $0 = .init(phase: .notSent, failure: .stale) }
        }
    }
    public func confirm(_ review: ClubOwnerRefundReview) async {
        let target = review.evidence.target
        guard let key = try? key(target, identity: review.identity, namespace: review.namespace), pending[key] == review else { return }
        guard entries[key]?.status.phase == .reviewing else { return }
        guard canDispatch else { cancel(review); mutate(key) { $0.failure = .disabled }; return }
        guard let generation = generations[key], current(review.identity, review.namespace, key, generation),
              now().timeIntervalSince(review.createdAt) >= 0, now().timeIntervalSince(review.createdAt) <= 120 else { cancel(review); return }
        mutate(key) { $0.phase = .preflighting; $0.failure = nil }
        do {
            let fresh = try await access.evidence(target)
            guard current(review.identity, review.namespace, key, generation), pending[key] == review,
                  fresh == review.evidence, fresh.eligible else { throw ClubOwnerRefundFailure.stale }
            let keys = try relatedKeys(fresh, identity: review.identity, namespace: review.namespace)
            for candidate in keys { guard !(try locks.contains(candidate)) else { throw ClubOwnerRefundFailure.locked } }
            // Registration first, then parent. If the second exclusive acquisition fails,
            // the first stays locked; never roll back a partial acquisition into a retry.
            for candidate in keys { try locks.acquire(candidate) }
            // Acquisition is injectable: cancellation or an account change may occur inside it.
            // Keep every acquired lock, but do not enter send without the review still owning this generation.
            guard current(review.identity, review.namespace, key, generation), pending[key] == review else { throw ClubOwnerRefundFailure.stale }
        } catch {
            pending[key] = nil; owners[key] = nil
            if generations[key] == generation { mutate(key) { $0.phase = .notSent; $0.failure = issue(error) } }
            return
        }
        pending[key] = nil; owners[key] = nil
        mutate(key) { $0.phase = .submitting }
        do {
            let receipt = try await access.send(review)
            guard current(review.identity, review.namespace, key, generation) else { throw ClubOwnerRefundFailure.unknown }
            mutate(key) { $0.receipt = receipt; $0.phase = receipt.manualReview ? .manualReview : .acknowledged }
        } catch {
            // Once send has been entered, every failure retains both durable locks.
            mutate(key) { $0.phase = .outcomeUnknown; $0.failure = issue(error) }
        }
        // Only a read. A return or failed read never dispatches a second cancellation.
        if access.identity == review.identity, access.namespace == review.namespace { await reconcile(target) }
    }
    public func reconcile(_ target: ClubOwnerRefundTarget) async {
        guard let identity else { return }
        let namespace = access.namespace
        guard let key = try? key(target, identity: identity, namespace: namespace) else { return }
        if entries[key]?.identity != identity || entries[key]?.authorization != access.authorizationGeneration {
            entries[key] = .init(identity: identity, authorization: access.authorizationGeneration, status: state(target))
        }
        guard entries[key]?.status.inFlight != true else { return }
        let generation = UUID(); generations[key] = generation
        mutate(key) { $0.readbackLoading = true; $0.readbackUnavailable = false; $0.readback = nil }
        defer { if generations[key] == generation { mutate(key) { $0.readbackLoading = false } } }
        do {
            let evidence = try await access.evidence(target)
            guard current(identity, namespace, key, generation), evidence.target == target else { return }
            _ = try relatedKeys(evidence, identity: identity, namespace: namespace)
            let hasLock = try locked(key)
            mutate(key) {
                if hasLock, [.idle, .notSent].contains($0.phase) { $0.phase = .outcomeUnknown }
                $0.readback = evidence; $0.readbackLoading = false
                // REFUNDED confirms only the record's status. Cash/points evidence remains separate.
                if evidence.status == "REFUNDED" { $0.phase = .refundRecorded }
            }
        } catch {
            guard current(identity, namespace, key, generation) else { return }
            mutate(key) { $0.readbackLoading = false; $0.readbackUnavailable = true }
        }
    }
}
