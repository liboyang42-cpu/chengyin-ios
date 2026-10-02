import Foundation

@MainActor public final class PublisherLifecycleCoordinator {
    private let client: PublisherLifecycleHTTP
    private let journal: (any OperationPendingJournal)?
    private let authority: (PublishedResource, PublishingSession) async throws -> PublisherAuthority
    private let now: () -> Date
    private var reviews: [UUID: PublisherLifecycleReview] = [:]
    private var busy = false
    private var generation = UUID()
    public init(client: PublisherLifecycleHTTP, journal: (any OperationPendingJournal)? = nil,
                now: @escaping () -> Date = Date.init,
                authority: @escaping (PublishedResource, PublishingSession) async throws -> PublisherAuthority) {
        self.client = client; self.journal = journal; self.now = now; self.authority = authority
    }
    public func invalidate() { generation = UUID(); reviews.removeAll() }
    public func prepare(_ action: PublisherLifecycleAction) async throws -> PublisherLifecycleReview {
        guard !busy, let captured = client.credentials(), let resource = action.resource else { throw PublisherLifecycleError.unavailable }
        generation = UUID(); reviews.removeAll()
        let stamp = generation
        let owner = try await authority(resource, captured.session)
        try client.check(captured)
        guard owner.resource == resource, owner.ownerAccountID == captured.session.accountID, !owner.revision.isEmpty else { throw PublisherLifecycleError.forbidden }
        var preview: PublisherPricingPreview?; var count: Int?
        switch action {
        case .pricing(let input, let price):
            let loaded = try await client.pricing(input)
            guard loaded.accepts(price), loaded.lineup.allSatisfy({ $0.validTerms }) else { throw PublisherLifecycleError.incomplete }; preview = loaded
        case .cancel(let target, let reason, let scope):
            guard target.kind != .activity || scope == nil else { throw PublisherLifecycleError.incomplete }
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PublisherLifecycleError.incomplete }
            count = try await client.paidPlayers(target, scope: scope)
        case .transfer(_, let clubID): guard clubID > 0, owner.eligibleClubIDs.contains(clubID) else { throw PublisherLifecycleError.forbidden }
        case .graduate: guard owner.beta else { throw PublisherLifecycleError.forbidden }
        }
        try client.check(captured)
        guard generation == stamp else { throw PublisherLifecycleError.stale }
        let review = PublisherLifecycleReview(id: UUID(), session: captured.session, action: action, authority: owner, preview: preview, paidPlayers: count, createdAt: now())
        reviews = [review.id: review]; return review
    }
    public func confirm(_ review: PublisherLifecycleReview, consequentialApproval: Bool) async -> PublisherLifecycleOutcome {
        guard consequentialApproval, !busy, reviews[review.id] == review,
              now().timeIntervalSince(review.createdAt) >= 0, now().timeIntervalSince(review.createdAt) <= 120,
              let credential = client.credentials(), credential.session == review.session, let journal else { return .notSent }
        let descriptor = descriptor(review.action)
        guard client.permits(descriptor.path, grant: descriptor.grant, credential: credential) else { return .notSent }
        busy = true; defer { busy = false }
        let record = OperationPendingRecord(operationID: review.id, ownerKey: review.session.storageKey, targetKey: "publisherLifecycle:\(review.authority.resource.id)")
        do {
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { return .unknown }
            let fresh = try await authority(review.authority.resource, review.session)
            try client.check(credential)
            guard fresh == review.authority else { return .notSent }
            switch review.action {
            case .pricing(let input, _): guard try await client.pricing(input) == review.preview else { return .notSent }
            case .cancel(let resource, _, let scope): guard try await client.paidPlayers(resource, scope: scope) == review.paidPlayers else { return .notSent }
            default: break
            }
            try client.check(credential)
            guard reviews[review.id] == review, now().timeIntervalSince(review.createdAt) <= 120 else { return .notSent }
            let request = try client.request(path: descriptor.path, fields: descriptor.fields, json: descriptor.json, credential: credential)
            try journal.write(record)
            guard try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record else { return .unknown }
            reviews.removeValue(forKey: review.id)
            do {
                let envelope = try await client.send(request, credential: credential)
                let newID: Int?
                if case .transfer = review.action {
                    guard let id = envelope["data"]?.object?["newTopicId"]?.integer, id > 0 else { return .unknown }; newID = id
                } else { newID = nil }
                try journal.clear(record)
                return .acknowledged(message: envelope["msg"]?.text, newTopicID: newID)
            } catch PublisherLifecycleError.rejected(let message) {
                try journal.clear(record); return .rejected(message)
            } catch { return .unknown }
        } catch { return .notSent }
    }
    private func descriptor(_ action: PublisherLifecycleAction) -> (path: String, fields: [String: ProjectEditJSON], json: Bool, grant: OperationEndpointApproval?) {
        switch action {
        case .pricing(let input, let price):
            var fields = input.fields; fields.removeValue(forKey: "subType")
            fields[input.subtype == .guided ? "guidedPrice" : "selfPrice"] = .number(price)
            return ("api/topic/pricing/confirm", fields, true, client.grants.pricing)
        case .cancel(let resource, let reason, let scope):
            var fields: [String: ProjectEditJSON] = ["id": .string(String(resource.value)), "reason": .string(reason)]
            if resource.kind == .topic, let scope, !scope.isEmpty { fields["scope"] = .string(scope) }
            return ("api/\(resource.kind.rawValue)/cancel", fields, false, client.grants.cancellationRefunds)
        case .transfer(let topicID, let clubID): return ("api/topic/transfer-to-club", ["topicId": .string(String(topicID)), "clubId": .string(String(clubID))], false, client.grants.ownership)
        case .graduate(let topicID): return ("api/topic/beta/graduate", ["topicId": .string(String(topicID))], false, client.grants.graduation)
        }
    }
}
