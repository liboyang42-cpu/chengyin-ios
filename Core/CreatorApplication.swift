import Foundation

public struct CreatorApplicationDraft: Equatable {
    public let creatorName: String; public let bio: String?; public let avatarURL: String?
    public init(creatorName: String, bio: String? = nil, avatarURL: String? = nil) throws {
        let name = creatorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PublisherLifecycleError.incomplete }
        self.creatorName = name; self.bio = bio; self.avatarURL = avatarURL
    }
    var fields: [String: ProjectEditJSON] {
        var value: [String: ProjectEditJSON] = ["creatorName": .string(creatorName)]
        if let bio, !bio.isEmpty { value["bio"] = .string(bio) }
        if let avatarURL, !avatarURL.isEmpty { value["avatarUrl"] = .string(avatarURL) }
        return value
    }
}
public struct CreatorApplicationReview: Equatable, Identifiable {
    public let id: UUID; public let draft: CreatorApplicationDraft; public let session: PublishingSession
    let readerScope: UUID; let createdAt: Date
}
public enum CreatorApplicationOutcome: Equatable {
    case submitted(CreatorContentCenter?), notSaved, notSent, unknown, rejected(String)
}
@MainActor public final class CreatorApplicationCoordinator {
    private let client: PublisherLifecycleHTTP
    private let reader: any CreatorContentReading
    private let journal: (any OperationPendingJournal)?
    private let now: () -> Date
    private var review: CreatorApplicationReview?
    private var busy = false
    private var generation = UUID()
    public init(client: PublisherLifecycleHTTP, reader: any CreatorContentReading,
                journal: (any OperationPendingJournal)? = nil, now: @escaping () -> Date = Date.init) {
        self.client = client; self.reader = reader; self.journal = journal; self.now = now
    }
    public func invalidate() { generation = UUID(); review = nil }
    public func prepare(_ draft: CreatorApplicationDraft) async throws -> CreatorApplicationReview {
        guard !busy, let credential = client.credentials(), reader.isAuthenticated else { throw PublisherLifecycleError.unavailable }
        generation = UUID(); review = nil
        let stamp = generation
        let scope = reader.scope
        let center = try await reader.center()
        try client.check(credential)
        // Any existing profile, including rejected, is explicitly ineligible.
        guard generation == stamp, reader.scope == scope, center.status == .notApplied else { throw PublisherLifecycleError.forbidden }
        let result = CreatorApplicationReview(id: UUID(), draft: draft, session: credential.session, readerScope: scope, createdAt: now())
        review = result; return result
    }
    public func confirm(_ reviewed: CreatorApplicationReview, approved: Bool) async -> CreatorApplicationOutcome {
        let path = "api/creator/apply"
        guard approved, !busy, review == reviewed, now().timeIntervalSince(reviewed.createdAt) >= 0,
              now().timeIntervalSince(reviewed.createdAt) <= 120, let credential = client.credentials(), credential.session == reviewed.session,
              let journal, client.permits(path, grant: client.grants.creatorApplication, credential: credential) else { return .notSent }
        busy = true; defer { busy = false }
        let record = OperationPendingRecord(operationID: reviewed.id, ownerKey: reviewed.session.storageKey, targetKey: "creatorApplication:first")
        do {
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { return .unknown }
            let center = try await reader.center()
            try client.check(credential)
            guard review == reviewed, reader.scope == reviewed.readerScope, center.status == .notApplied,
                  now().timeIntervalSince(reviewed.createdAt) <= 120 else { return .notSent }
            let request = try client.request(path: path, fields: reviewed.draft.fields, json: false, credential: credential)
            try journal.write(record)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { return .unknown }
            review = nil
            do {
                let envelope = try await client.send(request, credential: credential)
                // Do not coerce strings or booleans into successful affected-row counts.
                guard let count = PublisherValue.number(envelope["data"]), !count.isNaN, count >= 0 else { return .unknown }
                try journal.clear(record)
                guard count > 0 else { return .notSaved }
                let updated = try? await reader.center()
                try client.check(credential)
                guard reader.scope == reviewed.readerScope else { return .unknown }
                return .submitted(updated)
            } catch PublisherLifecycleError.rejected(let message) {
                try journal.clear(record); return .rejected(message)
            } catch { return .unknown }
        } catch { return .notSent }
    }
}
