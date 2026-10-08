import SwiftUI

/// Presentation identity only; it never grants merchant authority.
struct MerchantBusinessAccessLoadKey: Hashable {
    let readerIdentity: ObjectIdentifier
    let scope: MerchantBusinessScope?
    let authorizationGeneration: UUID?
    let configured: Bool

    @MainActor init(reader: any MerchantBusinessReading) {
        readerIdentity = ObjectIdentifier(reader)
        scope = reader.scope
        authorizationGeneration = reader.authorizationGeneration
        configured = reader.isConfigured
    }
}

/// Each visible home appearance gets a one-use token. A retired callback cannot
/// reactivate this token, even after the account context changes away and back.
@MainActor final class MerchantBusinessAccessAppearance {
    let id = UUID()
    fileprivate var started = false
    fileprivate var retired = false
}

struct MerchantBusinessAccessRequest: Equatable {
    let id: UUID
    let appearanceID: UUID
    let context: MerchantBusinessAccessLoadKey
}

/// The retained original reader and journal prevent old routes being rebound to
/// replacement dependencies. A route survives leaving Home, not a context change.
struct MerchantBusinessHomeRoute: Hashable {
    enum Target: Hashable { case query(MerchantBusinessQuery), scan, cityNode }
    let target: Target
    let context: MerchantBusinessAccessLoadKey
    let reader: any MerchantBusinessReading
    let journal: any MerchantBusinessIntentStore
    private let journalIdentity: ObjectIdentifier

    @MainActor init(target: Target, reader: any MerchantBusinessReading,
                    journal: any MerchantBusinessIntentStore) {
        self.target = target; self.reader = reader; self.journal = journal
        context = .init(reader: reader); journalIdentity = ObjectIdentifier(journal)
    }
    @MainActor func isCurrent(reader: any MerchantBusinessReading,
                              journal: any MerchantBusinessIntentStore) -> Bool {
        self.reader === reader && self.journal === journal &&
            context == MerchantBusinessAccessLoadKey(reader: reader)
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.target == rhs.target && lhs.context == rhs.context && lhs.journalIdentity == rhs.journalIdentity
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(target); hasher.combine(context); hasher.combine(journalIdentity)
    }
}

/// Owns only the home access read. Admission is synchronous and appearance-bound;
/// SwiftUI's single .task consumes its ticket. Late callers cannot claim ownership.
@MainActor final class MerchantBusinessAccessModel: ObservableObject {
    @Published private var accessValue: MerchantBusinessAccess?
    @Published private var issueKey: String?
    @Published private var loading = false
    @Published private(set) var request: MerchantBusinessAccessRequest?
    private var owner: (any MerchantBusinessReading)?
    private var context: MerchantBusinessAccessLoadKey?
    private var appearance: MerchantBusinessAccessAppearance?
    private var claimedRequestID: UUID?
    private var pending: Task<Void, Never>?

    deinit { pending?.cancel() }

    func access(for reader: any MerchantBusinessReading) -> MerchantBusinessAccess? {
        isCurrent(reader) ? accessValue : nil
    }
    func issue(for reader: any MerchantBusinessReading) -> String? {
        isCurrent(reader) ? issueKey : nil
    }
    func isLoading(for reader: any MerchantBusinessReading) -> Bool {
        isCurrent(reader) && loading
    }
    func isActive(appearance expected: MerchantBusinessAccessAppearance) -> Bool {
        appearance === expected && !expected.retired
    }
    private func isCurrent(_ reader: any MerchantBusinessReading) -> Bool {
        appearance?.retired == false && owner === reader && context == MerchantBusinessAccessLoadKey(reader: reader)
    }

    /// Called only by the synchronous current Home appearance event. Never called
    /// from refresh/task callbacks, which may be queued after this appearance ends.
    func begin(reader: any MerchantBusinessReading, appearance next: MerchantBusinessAccessAppearance) {
        guard !Task.isCancelled, !next.started, !next.retired else { return }
        if let appearance { end(appearance: appearance) }
        next.started = true; appearance = next
        owner = reader; context = .init(reader: reader)
        refresh(reader: reader, appearance: next, context: .init(reader: reader))
    }

    /// Old button/pull-refresh callbacks have only this admission path. The token,
    /// captured key and live dependency must all still match before any mutation.
    func refresh(reader: any MerchantBusinessReading, appearance expected: MerchantBusinessAccessAppearance,
                 context captured: MerchantBusinessAccessLoadKey) {
        guard !Task.isCancelled, appearance === expected, !expected.retired,
              isCurrent(reader), context == captured else { return }
        cancelRead()
        accessValue = nil; issueKey = nil; loading = false
        guard captured.configured else { issueKey = "auth.notConfigured"; return }
        guard captured.scope != nil else { issueKey = "merchant.signIn"; return }
        request = .init(id: UUID(), appearanceID: expected.id, context: captured)
    }

    func end(appearance expected: MerchantBusinessAccessAppearance) {
        expected.retired = true
        guard appearance === expected else { return }
        cancelRead()
        accessValue = nil; issueKey = nil; loading = false
        context = nil; owner = nil; appearance = nil
    }

    private func cancelRead() {
        request = nil; claimedRequestID = nil
        pending?.cancel(); pending = nil
    }

    func load(reader: any MerchantBusinessReading, request captured: MerchantBusinessAccessRequest) async {
        // This check MUST precede all shared mutations. A cancelled old caller can
        // enter after the replacement request has already started.
        guard !Task.isCancelled else { return }
        guard request == captured, appearance?.id == captured.appearanceID,
              isCurrent(reader), context == captured.context, claimedRequestID == nil else { return }
        claimedRequestID = captured.id; loading = true
        let task = Task<Void, Never> { [weak self] in
            do {
                try Task.checkCancellation()
                let value = try await reader.access()
                self?.finish(.success(value), reader: reader, request: captured)
            } catch {
                self?.finish(.failure(error), reader: reader, request: captured)
            }
        }
        pending = task
        await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private func finish(_ result: Result<MerchantBusinessAccess, Error>,
                        reader: any MerchantBusinessReading, request captured: MerchantBusinessAccessRequest) {
        // Success, failure and cleanup use exactly the same ownership fence.
        guard request == captured, claimedRequestID == captured.id,
              appearance?.id == captured.appearanceID, owner === reader else { return }
        guard !Task.isCancelled, isCurrent(reader) else {
            // A context change can complete this read before Home receives its
            // onChange. Clear the read, but keep the visible appearance available
            // for that event to replace. Only the view lifecycle retires it.
            cancelRead()
            accessValue = nil; issueKey = nil; loading = false
            return
        }
        pending = nil; loading = false
        switch result {
        case .success(let value): accessValue = value; issueKey = nil
        case .failure(let error):
            accessValue = nil
            issueKey = (error as? MerchantBusinessFailure)?.key ??
                (reader.isConfigured ? "merchant.business.loadFailed" : "auth.notConfigured")
        }
    }
}
