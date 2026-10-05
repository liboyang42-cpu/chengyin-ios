import Foundation

@MainActor public protocol OfficialActionAccess: AnyObject {
    var identity: OfficialActionIdentity? { get }
    var enabled: Bool { get }
    func snapshot(for command: OfficialActionCommand) async throws -> OfficialActionSnapshot
    func send(_ command: OfficialActionCommand) async throws -> OfficialActionReceipt
}
/// Minted only after durable insertion; production dispatch rechecks the exact
/// review, current generation/session, cancellation and persisted lock.
@MainActor final class OfficialActionDispatchAuthorization {
    let review: OfficialActionReview
    private let valid: () throws -> Bool
    fileprivate init(review: OfficialActionReview, valid: @escaping () throws -> Bool) { self.review = review; self.valid = valid }
    func validate() throws {
        try Task.checkCancellation()
        guard try valid() else { throw OfficialActionFailure.stale }
    }
}
@MainActor public protocol OfficialActionLockStore {
    func contains(_ key: String) throws -> Bool
    func insert(_ key: String) throws
    func remove(_ key: String) throws
}
/// Metadata only, no draft, names, location, reason, token, or recipient list on disk.
/// Inject an app-private URL. Corrupt/unreadable files fail closed. Never erase on sign-out.
@MainActor public final class OfficialActionFileLocks: OfficialActionLockStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    private func load() throws -> Set<String> {
        if !FileManager.default.fileExists(atPath: url.path) { return [] }
        do { return try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url)) }
        catch { throw OfficialActionFailure.storage }
    }
    public func contains(_ key: String) throws -> Bool { try load().contains(key) }
    public func insert(_ key: String) throws { var values = try load(); values.insert(key); try save(values) }
    public func remove(_ key: String) throws { var values = try load(); values.remove(key); try save(values) }
    private func save(_ values: Set<String>) throws {
        do { try JSONEncoder().encode(values).write(to: url, options: .atomic) }
        catch { throw OfficialActionFailure.storage }
    }
}
public struct OfficialActionReview: Identifiable, Equatable {
    public let id: UUID
    public let command: OfficialActionCommand
    public let snapshot: OfficialActionSnapshot
    public let body: Data?
    fileprivate init(command: OfficialActionCommand, snapshot: OfficialActionSnapshot) throws {
        id = UUID(); self.command = command; self.snapshot = snapshot; body = try command.payload()
    }
}
public enum OfficialActionState: Equatable { case idle, reviewing, checking, submitting, acknowledged, rejected, unknown }
@MainActor public final class OfficialActionCoordinator {
    private let access: any OfficialActionAccess
    private let locks: any OfficialActionLockStore
    private let now: () -> Date
    private var pending: OfficialActionReview?
    private var generation = UUID()
    private var busy = false
    private var verifiedReadback: OfficialActionReadback?
    private var readbackIdentity: OfficialActionIdentity?
    public var readback: OfficialActionReadback? { access.identity == readbackIdentity ? verifiedReadback : nil }
    public private(set) var state: OfficialActionState = .idle
    public var identity: OfficialActionIdentity? { access.identity }
    public var enabled: Bool { access.enabled }
    public init(access: any OfficialActionAccess, locks: any OfficialActionLockStore, now: @escaping () -> Date = Date.init) {
        self.access = access; self.locks = locks; self.now = now
    }
    private func key(_ command: OfficialActionCommand, _ identity: OfficialActionIdentity) -> String {
        // JSON tuple prevents delimiter collisions. Epoch deliberately excluded across relaunch/relogin.
        let parts = [identity.namespace, String(identity.accountID), command.scope]
        return String(decoding: (try? JSONEncoder().encode(parts)) ?? Data(), as: UTF8.self)
    }
    public func cancelReview() { generation = UUID(); pending = nil; if !busy { state = .idle } }
    public func prepare(_ command: OfficialActionCommand) async throws -> OfficialActionReview {
        guard !busy else { throw OfficialActionFailure.busy }
        guard let identity = access.identity else { throw OfficialActionFailure.forbidden }
        guard !(try locks.contains(key(command, identity))) else { throw OfficialActionFailure.locked }
        busy = true; defer { busy = false }
        generation = UUID(); let revision = generation; pending = nil; verifiedReadback = nil; readbackIdentity = nil; state = .checking
        let snapshot = try await access.snapshot(for: command)
        try snapshot.validate(command, now: now())
        guard identity == access.identity, identity == snapshot.identity, generation == revision, !Task.isCancelled else { throw OfficialActionFailure.stale }
        let review = try OfficialActionReview(command: command, snapshot: snapshot)
        pending = review; state = .reviewing; return review
    }
    public func confirm(_ review: OfficialActionReview) async throws -> OfficialActionReceipt {
        guard access.enabled else { throw OfficialActionFailure.disabled }
        guard !busy else { throw OfficialActionFailure.busy }
        guard pending == review, access.identity == review.snapshot.identity else { throw OfficialActionFailure.stale }
        let lock = key(review.command, review.snapshot.identity)
        guard !(try locks.contains(lock)) else { throw OfficialActionFailure.locked }
        busy = true; defer { busy = false }; state = .checking
        let revision = generation
        do {
            let fresh = try await access.snapshot(for: review.command)
            try fresh.validate(review.command, now: now())
            guard fresh == review.snapshot, pending == review, revision == generation,
                  access.identity == review.snapshot.identity, access.enabled, !Task.isCancelled else { throw OfficialActionFailure.stale }
            guard !(try locks.contains(lock)) else { throw OfficialActionFailure.locked }
            try locks.insert(lock) // Durable BEFORE any dispatch; failure means zero requests.
        } catch { pending = nil; state = .rejected; throw error }
        pending = nil; state = .submitting
        do {
            let receipt: OfficialActionReceipt
            if let protected = access as? any OfficialActionProtectedAccess {
                let authorization = OfficialActionDispatchAuthorization(review: review, valid: { [weak self] in
                    guard let self else { return false }
                    guard self.generation == revision, self.access.identity == review.snapshot.identity,
                          self.access.enabled, self.state == .submitting else { return false }
                    return try self.locks.contains(lock)
                })
                receipt = try await protected.send(review.command, authorization: authorization)
                verifiedReadback = protected.readback; readbackIdentity = review.snapshot.identity
            } else { receipt = try await access.send(review.command) }
            guard access.identity == review.snapshot.identity, revision == generation, !Task.isCancelled else { throw OfficialActionFailure.unknown }
            guard Self.matches(receipt, command: review.command) else { throw OfficialActionFailure.unknown }
            switch receipt {
            case .published, .broadcastSubmitted, .invitesIssued: try locks.remove(lock)
            default:
                // Proven signup can unlock later event actions. Increment-only completion
                // and filtered-out parties stay locked: absence cannot prove an outcome.
                if case .signup(let id) = review.command, let readback, case .event(let event) = readback,
                   event.id == id, event.signed == true { try locks.remove(lock) }
            }
            state = .acknowledged
            // Other participation/party acknowledgments remain locked without independent reconciliation.
            // Acknowledgment is never attendance, eligibility, delivery, or reward proof.
            return receipt
        } catch {
            if case OfficialActionFailure.rejected = error {
                do { try locks.remove(lock); state = .rejected } catch { state = .unknown }
            } else { state = .unknown }
            throw error
        }
    }
    private static func matches(_ receipt: OfficialActionReceipt, command: OfficialActionCommand) -> Bool {
        switch (command, receipt) {
        case (.publish, .published(let id)), (.broadcast, .broadcastSubmitted(let id)): return id > 0
        case (.inviteMerchants, .invitesIssued(let ids)): return !ids.isEmpty && ids.allSatisfy { $0 > 0 } && Set(ids).count == ids.count
        case (.arrival, .arrival): return true
        case (.signup, .acknowledged), (.complete, .acknowledged), (.respond, .acknowledged): return true
        default: return false
        }
    }

}
