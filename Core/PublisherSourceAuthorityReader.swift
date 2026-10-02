import Foundation

/// Fresh authority composition over existing audited readers. Own no transport, grant,
/// cache, guessed server revision or local-role permission. One call always refetches.
@MainActor public final class PublisherSourceAuthorityReader {
    private let topics: any TopicReading
    private let clubs: any ClubReading
    private let activityDetail: (Int) async throws -> ActivityDetailAccess
    private let currentSession: () -> PublishingSession?

    public init(topics: any TopicReading, clubs: any ClubReading,
                activityDetail: @escaping (Int) async throws -> ActivityDetailAccess,
                currentSession: @escaping () -> PublishingSession?) {
        self.topics = topics; self.clubs = clubs
        self.activityDetail = activityDetail; self.currentSession = currentSession
    }

    public func freshAuthority(_ resource: PublishedResource, session: PublishingSession) async throws -> PublisherAuthority {
        try check(session)
        switch resource.kind {
        case .topic:
            guard topics.isConfigured, !topics.isOfflineExample, clubs.isClubConfigured,
                  clubs.clubIdentity.accountID == session.accountID else { throw PublisherLifecycleError.unavailable }
            let topicScope = topics.scope, clubIdentity = clubs.clubIdentity
            let detail = try await topics.topicDetail(id: resource.value)
            try check(session)
            guard topics.scope == topicScope, clubs.clubIdentity == clubIdentity else { throw PublisherLifecycleError.stale }
            guard detail.id == resource.value, let source = detail.publisherAuthoritySource,
                  source.resourceID == resource.value else { throw PublisherLifecycleError.unavailable }
            guard source.viewerIsOwner else { throw PublisherLifecycleError.forbidden }
            // Source picker is /api/club/my, not the public directory. Failure never becomes [].
            let owned = try await clubs.clubOwned()
            try check(session)
            guard topics.scope == topicScope, clubs.clubIdentity == clubIdentity else { throw PublisherLifecycleError.stale }
            var eligible: [ClubRecord] = []
            var seen = Set<Int>()
            for candidate in owned {
                guard seen.insert(candidate.id).inserted else { throw PublisherLifecycleError.unavailable }
                let fresh = try await clubs.clubDetail(id: candidate.id)
                try check(session)
                guard topics.scope == topicScope, clubs.clubIdentity == clubIdentity else { throw PublisherLifecycleError.stale }
                guard fresh.id == candidate.id else { throw PublisherLifecycleError.unavailable }
                // An administrator is not the leader. No cooperation invitation is inferred.
                if fresh.isOwner { eligible.append(fresh) }
            }
            let clubFacts: [ProjectEditJSON] = eligible.sorted { $0.id < $1.id }.map { club in
                .object(["id": .number(Decimal(club.id)), "isOwner": .bool(true), "name": .string(club.name)])
            }
            return PublisherAuthority(resource: resource, ownerAccountID: session.accountID,
                revision: try fingerprint(resource: resource, facts: source.stableFacts, clubs: clubFacts),
                beta: source.beta, eligibleClubIDs: Set(eligible.map(\.id)))
        case .activity:
            let access = try await activityDetail(resource.value)
            try check(session)
            guard case .allowed(let detail) = access,
                  detail.summary.id == resource.value, let source = detail.publisherAuthoritySource,
                  source.resourceID == resource.value else { throw PublisherLifecycleError.unavailable }
            guard source.ownerAccountID == session.accountID, detail.hostMemberID == session.accountID else { throw PublisherLifecycleError.forbidden }
            return PublisherAuthority(resource: resource, ownerAccountID: source.ownerAccountID,
                revision: try fingerprint(resource: resource, facts: source.stableFacts, clubs: []), beta: false)
        case .template: throw PublisherLifecycleError.unavailable
        }
    }
    private func check(_ session: PublishingSession) throws {
        try Task.checkCancellation()
        guard session.accountID > 0, currentSession() == session else { throw PublisherLifecycleError.stale }
    }
    private func fingerprint(resource: PublishedResource, facts: ProjectEditJSON, clubs: [ProjectEditJSON]) throws -> String {
        let value = ProjectEditJSON.object([
            "schema": .string("publisher-source-v1"), "resource": .string(resource.id),
            "detail": facts, "eligibleClubs": .array(clubs)
        ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // Canonical bytes are collision-free evidence, not an invented backend version.
        // Keep only inside the transient review; never analytics, display or persistence.
        return try encoder.encode(value).base64EncodedString()
    }
}
