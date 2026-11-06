import XCTest
@testable import QuestifyCore

// Metadata-only synthetic fixtures. No coordinate provider, HTTP transport or real account is used.
@MainActor private final class TerminalStopRecoveryJournal: PersonalLocationShareJournaling {
    var values: [PersonalLocationSharePendingRecord] = []
    var failReads = false
    var failStopWrites = false
    var failRemovals = false
    func records(scope: PersonalLocationShareScope) throws -> [PersonalLocationSharePendingRecord] {
        if failReads { throw PersonalLocationShareFailure.journalUnavailable }
        return values.filter { $0.namespace == scope.namespace && $0.accountId == scope.accountId }
    }
    func put(_ record: PersonalLocationSharePendingRecord, scope: PersonalLocationShareScope) throws {
        if failStopWrites && record.stopRequested { throw PersonalLocationShareFailure.journalUnavailable }
        try record.validate(scope: scope)
        values.removeAll { $0.id == record.id }; values.append(record)
    }
    func remove(requestKey: String, scope: PersonalLocationShareScope) throws {
        if failRemovals { throw PersonalLocationShareFailure.journalUnavailable }
        values.removeAll { $0.id == requestKey && $0.accountId == scope.accountId }
    }
}
@MainActor private final class TerminalStopRecoveryFactory: PersonalLocationShareCoordinateFactory {
    let isSynthetic = true
    var makes = 0
    func canCreate(scope: PersonalLocationShareScope) -> Bool { true }
    func confirmationPurpose(scope: PersonalLocationShareScope) -> PersonalLocationShareCaptureApproval? {
        try? .init(scope: scope, approvalReference: "SYNTHETIC_NOT_APPROVAL", usageDescription: "Synthetic metadata-only test")
    }
    func make(binding: PersonalLocationShareCaptureBinding, isCurrent: @escaping () -> Bool) throws -> any PersonalLocationShareCoordinateProviding {
        makes += 1
        throw PersonalLocationShareFailure.providerUnavailable
    }
}
@MainActor private final class TerminalStopRecoveryService: PersonalLocationShareServicing {
    let scope: PersonalLocationShareScope
    let isSynthetic = true
    static let now: Int64 = 1_800_000_000_000
    static let key = "10000000-0000-4000-8000-000000000001"
    static let digest = String(repeating: "a", count: 64)
    var creates = 0, publishes = 0, owns = 0, receives = 0
    var queried: [String] = [], revoked: [String] = []
    var ownedFailure: PersonalLocationShareFailure?
    var receivedFailure: PersonalLocationShareFailure?
    var status: PersonalLocationShareStatus = .notFound
    var revokeFails = false
    var ownedValues: [PersonalLocationShareGrant] = []
    var delayedOwned: CheckedContinuation<PersonalLocationShareOwned, Error>?
    var delayOwned = false
    init(scope: PersonalLocationShareScope) { self.scope = scope }
    static var policy: PersonalLocationSharePolicy {
        .init(policyId: "METADATA_TEST", version: 1, digest: digest, approvalRef: "SYNTHETIC_NOT_APPROVAL", foregroundOnly: true,
            requiresRecipientAcceptance: false,
            modeChoices: [.init(id: "test-exact", mode: .exact, datum: "WGS84", latitudeStep: nil, longitudeStep: nil)],
            durationChoices: [.init(id: "test-duration", seconds: 120)],
            refreshAfterMs: 20_000, staleAfterMs: 30_000, displayLeaseMs: 40_000, ownerLeaseMs: 60_000)
    }
    static var request: PersonalLocationShareCreate {
        .init(requestKey: key, recipientId: 2, policyId: "METADATA_TEST", policyVersion: 1, policyDigest: digest,
            modeChoiceId: "test-exact", durationChoiceId: "test-duration", foregroundOnly: true,
            acknowledgedDisclosures: PersonalLocationShareDisclosure.allCases)
    }
    static var grant: PersonalLocationShareGrant {
        .init(grantId: "10000000-0000-4000-8000-000000000002", requestKey: key, ownerId: 1, recipientId: 2,
            policyId: "METADATA_TEST", policyVersion: 1, policyDigest: digest, modeChoiceId: "test-exact", mode: .exact,
            durationChoiceId: "test-duration", createdAtMs: now, expiresAtMs: now + 120_000,
            ownerLeaseUntilMs: now + 60_000, version: 1, watermark: 1, status: .active, reason: nil)
    }
    func context(recipientId: Int64) async throws -> PersonalLocationShareContext {
        .init(ownerId: scope.accountId, recipientId: recipientId, eligible: true, unavailableReason: nil, policy: Self.policy)
    }
    func create(_ request: PersonalLocationShareCreate) async throws -> PersonalLocationShareReceipt {
        creates += 1; throw PersonalLocationShareFailure.unknownOutcome
    }
    func requestStatus(requestKey: String) async throws -> PersonalLocationShareReceipt {
        queried.append(requestKey)
        return .init(requestKey: requestKey, known: status != .notFound, state: status,
            requestHash: status == .notFound ? nil : "original-metadata-hash", grant: status == .active ? Self.grant : nil,
            serverNowMs: Self.now, watermark: 1)
    }
    func revoke(requestKey: String) async throws -> PersonalLocationShareReceipt {
        revoked.append(requestKey)
        if revokeFails { throw PersonalLocationShareFailure.unknownOutcome }
        return .init(requestKey: requestKey, known: true, state: .stopped, requestHash: "original-metadata-hash", grant: nil,
            serverNowMs: Self.now, watermark: 2)
    }
    func owned() async throws -> PersonalLocationShareOwned {
        owns += 1
        if let ownedFailure { throw ownedFailure }
        if delayOwned { delayOwned = false; return try await withCheckedThrowingContinuation { delayedOwned = $0 } }
        return .init(ownerId: scope.accountId, serverNowMs: Self.now, grants: ownedValues)
    }
    func received() async throws -> PersonalLocationShareSnapshot {
        receives += 1
        if let receivedFailure { throw receivedFailure }
        return .init(recipientId: scope.accountId, serverNowMs: Self.now, cursor: 0,
            displayLeaseUntilMs: Self.now + 40_000, refreshAfterMs: 20_000, staleAfterMs: 30_000,
            policyId: "METADATA_TEST", policyVersion: 1, policyDigest: Self.digest, entries: [])
    }
    func events(cursor: Int64) async throws -> PersonalLocationShareEventBatch {
        .init(recipientId: scope.accountId, serverNowMs: Self.now, cursor: cursor, resetRequired: false, refreshAfterMs: 20_000, events: [])
    }
    func publish(grantId: String, observation: PersonalLocationSharePublish, synthetic: Bool) async throws -> PersonalLocationSharePublished {
        publishes += 1; throw PersonalLocationShareFailure.providerUnavailable
    }
}

@MainActor final class PersonalLocationShareTerminalStopRecoveryTests: XCTestCase {
    private func make() throws -> (PersonalLocationShareCoordinator, TerminalStopRecoveryService, TerminalStopRecoveryJournal, TerminalStopRecoveryFactory) {
        let scope = try PersonalLocationShareScope(namespace: "terminal-recovery.invalid/test-only", accountId: 1, epoch: 1)
        let service = TerminalStopRecoveryService(scope: scope)
        let journal = TerminalStopRecoveryJournal(), factory = TerminalStopRecoveryFactory()
        journal.values = [try .init(scope: scope, request: TerminalStopRecoveryService.request)]
        let model = PersonalLocationShareCoordinator(scope: scope, service: service, journal: journal,
            providerFactory: factory, current: { scope })
        return (model, service, journal, factory)
    }
    private func failedStop(_ model: PersonalLocationShareCoordinator, _ journal: TerminalStopRecoveryJournal) async {
        await model.restoreOriginalRequests()
        journal.failStopWrites = true
        await model.stop(requestKey: TerminalStopRecoveryService.key)
        XCTAssertTrue(model.hasUnpersistedStopIntent)
        XCTAssertFalse(model.originalRequestsAreVerifiedEmpty)
    }
    func testAuthoritativeTerminalReadbackClearsOnlyResolvedFailedStopAfterDurableRemoval() async throws {
        let (model, service, journal, factory) = try make()
        await failedStop(model, journal)
        XCTAssertTrue(service.revoked.isEmpty)
        service.status = .stopped
        await model.readback(requestKey: TerminalStopRecoveryService.key)
        XCTAssertTrue(model.pending.isEmpty)
        XCTAssertTrue(journal.values.isEmpty)
        XCTAssertFalse(model.hasUnpersistedStopIntent)
        XCTAssertTrue(model.originalRequestsAreVerifiedEmpty)
        XCTAssertEqual(model.requests[TerminalStopRecoveryService.key], .stopped)
        XCTAssertNil(model.publishingRequestKey)
        XCTAssertEqual(factory.makes, 0); XCTAssertEqual(service.creates, 0); XCTAssertEqual(service.publishes, 0)
        // Resolving a stopped request is not permission to start: explicit policy/choices/consent remain required.
        XCTAssertFalse(model.canConfirm)
        await model.restoreOriginalRequests()
        XCTAssertFalse(model.hasUnpersistedStopIntent)
        XCTAssertTrue(model.originalRequestsAreVerifiedEmpty)
    }
    func testFailedTerminalRemovalRetainsPendingAndUnpersistedStopUntilRemovalSucceeds() async throws {
        let (model, service, journal, _) = try make()
        await failedStop(model, journal)
        journal.failRemovals = true; service.status = .stopped
        await model.readback(requestKey: TerminalStopRecoveryService.key)
        XCTAssertEqual(model.pending.map(\.id), [TerminalStopRecoveryService.key])
        XCTAssertTrue(model.hasUnpersistedStopIntent)
        XCTAssertFalse(model.originalRequestsAreVerifiedEmpty)
        XCTAssertFalse(model.canConfirm)
        journal.failRemovals = false
        await model.readback(requestKey: TerminalStopRecoveryService.key)
        XCTAssertFalse(model.hasUnpersistedStopIntent)
        XCTAssertTrue(model.pending.isEmpty)
    }
    func testNotFoundIsNotTerminalAndCannotClearFailedStopIntent() async throws {
        let (model, service, journal, factory) = try make()
        await failedStop(model, journal)
        journal.failStopWrites = false; service.status = .notFound
        await model.readback(requestKey: TerminalStopRecoveryService.key)
        XCTAssertTrue(model.hasUnpersistedStopIntent)
        XCTAssertEqual(model.pending.map(\.id), [TerminalStopRecoveryService.key])
        XCTAssertFalse(model.originalRequestsAreVerifiedEmpty)
        XCTAssertFalse(model.canConfirm)
        XCTAssertEqual(factory.makes, 0); XCTAssertEqual(service.creates, 0)
    }
    func testResolvingOneTerminalRequestDoesNotClearAnotherFailedStop() async throws {
        let (model, service, journal, _) = try make()
        let other = PersonalLocationShareCreate(requestKey: "10000000-0000-4000-8000-000000000099", recipientId: 3,
            policyId: "METADATA_TEST", policyVersion: 1, policyDigest: TerminalStopRecoveryService.digest,
            modeChoiceId: "test-exact", durationChoiceId: "test-duration", foregroundOnly: true,
            acknowledgedDisclosures: PersonalLocationShareDisclosure.allCases)
        journal.values.append(try .init(scope: service.scope, request: other))
        await failedStop(model, journal)
        await model.stop(requestKey: other.requestKey)
        service.status = .stopped
        await model.readback(requestKey: TerminalStopRecoveryService.key)
        XCTAssertTrue(model.hasUnpersistedStopIntent)
        XCTAssertEqual(model.pending.map(\.id), [other.requestKey])
        XCTAssertFalse(model.originalRequestsAreVerifiedEmpty)
        XCTAssertFalse(model.canConfirm)
        await model.readback(requestKey: other.requestKey)
        XCTAssertFalse(model.hasUnpersistedStopIntent)
        XCTAssertTrue(model.pending.isEmpty)
    }
    func testChangedAccountCannotConsumeLateTerminalStateOrUnlockOriginalStop() async throws {
        let scope = try PersonalLocationShareScope(namespace: "terminal-recovery.invalid/test-only", accountId: 1, epoch: 1)
        var current: PersonalLocationShareScope? = scope
        let service = TerminalStopRecoveryService(scope: scope), journal = TerminalStopRecoveryJournal()
        journal.values = [try .init(scope: scope, request: TerminalStopRecoveryService.request)]
        let model = PersonalLocationShareCoordinator(scope: scope, service: service, journal: journal, current: { current })
        await failedStop(model, journal)
        let priorQueries = service.queried
        current = try .init(namespace: scope.namespace, accountId: 3, epoch: 2)
        service.status = .stopped
        await model.readback(requestKey: TerminalStopRecoveryService.key)
        XCTAssertEqual(service.queried, priorQueries)
        XCTAssertTrue(model.hasUnpersistedStopIntent)
        XCTAssertEqual(model.pending.map(\.id), [TerminalStopRecoveryService.key])
        XCTAssertFalse(model.canConfirm)
    }
}
