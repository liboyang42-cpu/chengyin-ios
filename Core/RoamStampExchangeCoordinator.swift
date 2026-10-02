import Foundation

public struct RoamStampExchangeDraft: Codable, Equatable {
    public let pictureURL: String
    public let caption: String
    public let idempotencyKey: String
    public init(pictureURL: String, caption: String, idempotencyKey: String) throws {
        _ = try RoamExperienceMutation.createStamp(pictureURL: pictureURL, caption: caption, idempotencyKey: idempotencyKey).fields()
        self.pictureURL = pictureURL; self.caption = caption; self.idempotencyKey = idempotencyKey
    }
}
public enum RoamStampJournalPhase: String, Codable { case prepared, createPending, created, exchangePending, finished }
public struct RoamStampJournalEntry: Codable, Equatable {
    public let scope: RoamHistoryScope
    public let draft: RoamStampExchangeDraft
    public var phase: RoamStampJournalPhase
    public var createdID: Int?
    public init(scope: RoamHistoryScope, draft: RoamStampExchangeDraft) { self.scope = scope; self.draft = draft; phase = .prepared; createdID = nil }
}
/// Implement with protected atomic storage before enabling a real workflow. The included adapter uses
/// the same device-only Keychain boundary as history; no secret or photo bytes are persisted.
@MainActor public final class RoamStampExchangeJournal {
    private let storage: any RoamHistoryDataStoring
    public init(storage: any RoamHistoryDataStoring) { self.storage = storage }
    private func key(_ scope: RoamHistoryScope) -> String { "stamp-exchange-" + scope.storageKey }
    public func load(scope: RoamHistoryScope) throws -> RoamStampJournalEntry? {
        guard let data = try storage.read(key: key(scope)) else { return nil }
        guard data.count <= 100_000,
              let entry = try? JSONDecoder().decode(RoamStampJournalEntry.self, from: data), entry.scope == scope else { throw RoamExperienceFailure.historyUnreadable }
        _ = try RoamExperienceMutation.createStamp(pictureURL: entry.draft.pictureURL, caption: entry.draft.caption, idempotencyKey: entry.draft.idempotencyKey).fields()
        if entry.phase == .created || entry.phase == .exchangePending || entry.phase == .finished {
            guard (entry.createdID ?? 0) > 0 else { throw APIError.malformedResponse }
        } else if entry.createdID != nil { throw APIError.malformedResponse }
        return entry
    }
    public func save(_ entry: RoamStampJournalEntry) throws { try storage.write(JSONEncoder().encode(entry), key: key(entry.scope)) }
}
/// Unmounted, injectable workflow. A new immutable draft can replace a journal only after the old
/// workflow is finished. A retry after uncertain creation reuses its exact key/payload; exchange
/// retries reuse the persisted givenStampId. The source explicitly documents both as idempotent.
@MainActor public final class RoamStampExchangeCoordinator {
    public enum Phase: Equatable { case idle, working, saved, exchanged, noExchange, retryRequired, journalFailure, unavailable }
    public private(set) var phase: Phase = .idle
    public private(set) var receipt: RoamStampExchangeReceipt?
    public private(set) var error: Error?
    private let executor: any RoamExperienceMutationExecuting
    private let journal: RoamStampExchangeJournal
    private let currentIdentity: () -> RoamExperienceIdentity?
    private var generation = 0
    public init(executor: any RoamExperienceMutationExecuting, journal: RoamStampExchangeJournal, currentIdentity: @escaping () -> RoamExperienceIdentity?) {
        self.executor = executor; self.journal = journal; self.currentIdentity = currentIdentity
    }
    public func reset() { generation += 1; phase = .idle; receipt = nil; error = nil }
    public func submitOrRetry(_ draft: RoamStampExchangeDraft) async {
        guard phase != .working else { return }
        guard executor.isAvailable else { phase = .unavailable; return }
        guard let identity = currentIdentity() else { error = APIError.unauthorized; phase = .retryRequired; return }
        generation += 1; let ticket = generation
        phase = .working; error = nil; receipt = nil
        defer {
            if ticket == generation && (Task.isCancelled || currentIdentity() != identity) {
                phase = .idle; receipt = nil; error = nil
            }
        }
        var persisted = false
        do {
            var entry: RoamStampJournalEntry
            if let previous = try journal.load(scope: identity.scope), previous.phase != .finished {
                guard previous.draft == draft else { throw APIError.invalidRequest }; entry = previous
            } else if let previous = try journal.load(scope: identity.scope), previous.draft == draft {
                // Durable completion is not replayed merely because a view/coordinator was recreated.
                phase = .saved; return
            } else { entry = RoamStampJournalEntry(scope: identity.scope, draft: draft) }
            guard currentIdentity() == identity else { throw CancellationError() }
            if entry.createdID == nil {
                entry.phase = .createPending; try journal.save(entry); persisted = true
                let data = try await executor.execute(.createStamp(pictureURL: draft.pictureURL, caption: draft.caption, idempotencyKey: draft.idempotencyKey))
                guard ticket == generation, !Task.isCancelled, currentIdentity() == identity else { return }
                let created = try RoamMutationReceiptDecoder.value(RoamStampCreatedReceipt.self, from: data)
                entry.createdID = created.id; entry.phase = .created; persisted = false
                try journal.save(entry); persisted = true
            }
            guard let createdID = entry.createdID else { throw APIError.malformedResponse }
            entry.phase = .exchangePending; persisted = false; try journal.save(entry); persisted = true
            let data = try await executor.execute(.exchangeStamp(givenStampID: createdID))
            guard ticket == generation, !Task.isCancelled, currentIdentity() == identity else { return }
            let result = try RoamMutationReceiptDecoder.value(RoamStampExchangeReceipt.self, from: data)
            entry.phase = .finished; persisted = false; try journal.save(entry); persisted = true
            receipt = result; phase = result.exchanged ? .exchanged : .noExchange
        } catch {
            guard ticket == generation, !Task.isCancelled, currentIdentity() == identity else { return }
            self.error = error; phase = persisted ? .retryRequired : .journalFailure
        }
    }
}
