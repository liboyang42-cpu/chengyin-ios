import Foundation

/// Read-only recovery of a durable review intent. The frozen manage endpoint exposes
/// current state, not request identity; finding a row must never complete the journal.
@MainActor public final class MerchantReviewReplyRecovery {
    public struct Pending: Equatable, Identifiable {
        public let intent: MerchantBusinessIntent
        public let reviewID: Int
        public var id: String { intent.requestID }
        init?(_ intent: MerchantBusinessIntent) {
            guard intent.target.hasPrefix("review:"),
                  let value = Int(intent.target.dropFirst(7)), value > 0,
                  intent.target == "review:\(value)", !intent.requestID.isEmpty else { return nil }
            self.intent = intent; reviewID = value
        }
    }
    public enum Result: Equatable {
        case current(MerchantBusinessRecord)
        case notInLoadedPages(hasMore: Bool)
    }
    private let reader: any MerchantBusinessReading
    private let journal: any MerchantBusinessIntentStore
    private var generation = 0
    private var context: MerchantBusinessScope?
    private var authorization: UUID?
    private var realm: String?
    private var access: MerchantBusinessAccess?
    private var selected: Pending?
    private var nextPage = 1
    private var lastResult: Result?
    private var busy = false
    public private(set) var failure: MerchantBusinessFailure?
    public var isBusy: Bool { busy }
    public var result: Result? {
        guard let selected, valid(selected), (try? contains(selected)) == true else { return nil }
        return lastResult
    }
    public init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) {
        self.reader = reader; self.journal = journal
    }
    /// Current store must come from the host's fresh server access snapshot.
    public func pending(access: MerchantBusinessAccess) throws -> [Pending] {
        guard reader.isConfigured, let scope = reader.scope else { throw MerchantBusinessFailure.stale }
        let realm = reader.journalRealm ?? scope.realm
        let rows = try journal.intents().filter {
            $0.realm == realm && $0.accountID == scope.accountID && $0.merchantID == access.merchantID
        }.compactMap(Pending.init)
        guard Set(rows.map(\.id)).count == rows.count, Set(rows.map(\.reviewID)).count == rows.count else {
            throw MerchantBusinessFailure.journal
        }
        return rows
    }
    public func invalidate() {
        generation += 1; lastResult = nil; selected = nil; access = nil
        context = nil; authorization = nil; realm = nil; nextPage = 1; busy = false; failure = nil
    }
    /// Each user action reads at most five pages. Continue is explicit and never a write.
    /// Refresh restarts at page one because rows may move between pages.
    public func refresh(_ pending: Pending, access: MerchantBusinessAccess) async {
        invalidate()
        context = reader.scope; authorization = reader.authorizationGeneration
        realm = reader.journalRealm ?? context?.realm; self.access = access; selected = pending
        await scan()
    }
    public func loadMore() async {
        guard !busy, case .notInLoadedPages(hasMore: true) = result else { return }
        await scan()
    }
    private func valid(_ pending: Pending) -> Bool {
        guard reader.isConfigured, let context, context == reader.scope,
              authorization == reader.authorizationGeneration,
              realm == (reader.journalRealm ?? context.realm),
              pending.intent.realm == realm, pending.intent.accountID == context.accountID,
              pending.intent.merchantID == access?.merchantID else { return false }
        return true
    }
    private func contains(_ pending: Pending) throws -> Bool {
        try journal.intents().contains(pending.intent)
    }
    private func scan() async {
        guard !busy, let selected, valid(selected) else { failure = .stale; return }
        busy = true; failure = nil; lastResult = nil
        let generation = self.generation
        defer { if generation == self.generation { busy = false } }
        do {
            for _ in 0..<5 {
                try Task.checkCancellation()
                guard valid(selected), try contains(selected) else { throw MerchantBusinessFailure.stale }
                let page = nextPage
                let snapshot = try await reader.snapshot(.reviews(page: page), isCurrent: {
                    generation == self.generation && self.valid(selected)
                })
                guard generation == self.generation else { return }
                try Task.checkCancellation()
                guard valid(selected), try contains(selected), snapshot.access == access,
                      snapshot.document.query == .reviews(page: page) else { throw MerchantBusinessFailure.stale }
                let matches = snapshot.document.rows.filter { $0.kind == .review && $0.id == String(selected.reviewID) }
                guard matches.count <= 1 else { throw MerchantBusinessFailure.malformed }
                if let row = matches.first {
                    lastResult = .current(row); return
                }
                if !snapshot.document.hasMore {
                    lastResult = .notInLoadedPages(hasMore: false); return
                }
                guard nextPage < Int.max / 50 else { throw MerchantBusinessFailure.malformed }
                nextPage += 1
            }
            lastResult = .notInLoadedPages(hasMore: true)
        } catch {
            guard generation == self.generation else { return }
            lastResult = nil
            failure = error as? MerchantBusinessFailure ?? .stale
        }
    }
}
