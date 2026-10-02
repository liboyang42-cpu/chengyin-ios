import Foundation

@MainActor public final class DoorEntryCoordinator {
    public private(set) var destination: DoorDestination?
    public private(set) var failure: String?
    public private(set) var pending: DoorIntent?
    private var generation = UUID()
    private var session: DoorReferralSession
    private var running = false
    private let service: any DoorReferralServing
    public init(session: DoorReferralSession, service: any DoorReferralServing) { self.session = session; self.service = service }
    public func receive(_ intent: DoorIntent) {
        generation = UUID(); pending = intent; running = false; destination = nil; failure = nil
    }
    public func updateSession(_ value: DoorReferralSession) {
        guard session != value else { return }
        generation = UUID(); running = false; destination = nil; failure = nil
        // Keep a cold link during initial restoration. Cancel an already-restored account's intent.
        if session.restored { pending = nil }
        session = value
    }
    public func cancel() { generation = UUID(); pending = nil; running = false; destination = nil; failure = nil }
    public func resolve() async {
        guard session.restored, let intent = pending, !running else { return }
        let ticket = generation; let scope = session
        running = true
        guard let code = DoorParsing.scene(intent.scene) else {
            destination = .home; pending = nil; running = false; return
        }
        var result: DoorDestination = .home
        var message: String?
        do { result = try await service.scan(code: code, session: scope).destination ?? .home
            if result == .home { message = "door.unavailable" }
        } catch DoorReferralFailure.rejected(let remote) {
            message = remote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "door.unavailable" : remote
        } catch { message = "door.unavailable" }
        guard ticket == generation, scope == session else { return }
        if Task.isCancelled { pending = nil; running = false; return }
        destination = result; failure = message; pending = nil; running = false
    }
}

public struct DoorReferralJournal: Codable, Equatable {
    public enum Status: String, Codable { case queued, attempting, bound, rejected, unknown }
    public struct Entry: Codable, Equatable {
        public let inviter: Int
        public let owner: Int?
        public var status: Status
        public init(inviter: Int, owner: Int?, status: Status = .queued) { self.inviter = inviter; self.owner = owner; self.status = status }
    }
    public var guest: Entry?
    public var accounts: [String: Entry] = [:]
    public init() {}
}

@MainActor public protocol DoorReferralStoring {
    func load() throws -> DoorReferralJournal
    /// Must atomically persist or throw. A failed save prevents network dispatch.
    func save(_ value: DoorReferralJournal) throws
}

/// Host supplies an app-private durable path; contains referral/account IDs, never credentials.
@MainActor public final class DoorReferralFileStore: DoorReferralStoring {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> DoorReferralJournal {
        guard FileManager.default.fileExists(atPath: url.path) else { return DoorReferralJournal() }
        return try JSONDecoder().decode(DoorReferralJournal.self, from: Data(contentsOf: url))
    }
    public func save(_ value: DoorReferralJournal) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

/// Serialized on MainActor with a busy fence spanning suspension. No legacy global flag.
/// Uncertain/interrupted attempts stay locked across restart: no automatic mutation retry.
@MainActor public final class DoorReferralQueue {
    private let store: any DoorReferralStoring
    private let service: any DoorReferralServing
    private let currentSession: () -> DoorReferralSession
    private var busy = false
    public init(store: any DoorReferralStoring, service: any DoorReferralServing, currentSession: @escaping () -> DoorReferralSession) {
        self.store = store; self.service = service; self.currentSession = currentSession
    }
    public func capture(_ raw: String?) throws {
        guard !busy else { throw DoorReferralFailure.busy }
        guard let inviter = DoorParsing.inviter(raw) else { throw DoorReferralFailure.invalid }
        let account = currentSession().accountID
        guard account != inviter else { throw DoorReferralFailure.invalid }
        var journal = try store.load()
        if let account {
            let key = String(account)
            if let existing = journal.accounts[key], existing.status != .queued { throw DoorReferralFailure.alreadyAttempted }
            journal.accounts[key] = .init(inviter: inviter, owner: account)
        } else { journal.guest = .init(inviter: inviter, owner: nil) }
        try store.save(journal)
    }
    /// Invoke for automatic pending replay only when separately enabled by the host.
    /// Manual binding must call this only after the user reviewed the one-time consequence.
    public func replay() async throws {
        guard !busy else { throw DoorReferralFailure.busy }
        guard service.bindingEnabled else { throw DoorReferralFailure.disabled }
        let scope = currentSession()
        guard scope.restored, let account = scope.accountID, account > 0, scope.token != nil else { throw DoorReferralFailure.invalid }
        busy = true; defer { busy = false }
        var journal = try store.load(); let key = String(account)
        if let guest = journal.guest {
            guard guest.owner == nil, guest.status == .queued else { throw DoorReferralFailure.invalid }
            if journal.accounts[key] == nil { journal.accounts[key] = .init(inviter: guest.inviter, owner: account) }
            journal.guest = nil
            try store.save(journal) // claim-before-send, including before any asynchronous operation
        }
        guard var entry = journal.accounts[key] else { return }
        guard entry.owner == account, entry.inviter > 0 else { throw DoorReferralFailure.invalid }
        guard entry.status == .queued else { throw DoorReferralFailure.alreadyAttempted }
        if entry.inviter == account { journal.accounts.removeValue(forKey: key); try store.save(journal); return }
        guard currentSession() == scope else { throw DoorReferralFailure.stale }
        try Task.checkCancellation()
        entry.status = .attempting; journal.accounts[key] = entry; try store.save(journal)
        do {
            try await service.bind(inviter: entry.inviter, session: scope)
            guard currentSession() == scope else { throw DoorReferralFailure.stale }
            entry.status = .bound
        } catch {
            // Do not mutate a replacement account's state or treat stale responses as success.
            entry.status = (error as? DoorReferralFailure).map { failure in
                if case .rejected = failure { return .rejected }; return .unknown
            } ?? .unknown
            var latest = try store.load(); latest.accounts[key] = entry; try store.save(latest)
            throw error
        }
        var latest = try store.load(); latest.accounts[key] = entry; try store.save(latest)
    }
    public func manualBind(_ raw: String) async throws {
        guard currentSession().restored, currentSession().accountID != nil else { throw DoorReferralFailure.invalid }
        try capture(raw); try await replay()
    }
}
