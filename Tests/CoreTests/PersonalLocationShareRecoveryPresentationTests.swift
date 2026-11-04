import XCTest
@testable import QuestifyCore

// Metadata-only synthetic fixtures. No coordinate provider, HTTP transport or real account is used.
@MainActor private final class RecoveryPresentationJournal: PersonalLocationShareJournaling {
    var values: [PersonalLocationSharePendingRecord] = []
    var failReads = false
    var failStopWrites = false
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
        values.removeAll { $0.id == requestKey && $0.accountId == scope.accountId }
    }
}
@MainActor private final class RecoveryPresentationFactory: PersonalLocationShareCoordinateFactory {
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
@MainActor private final class RecoveryPresentationService: PersonalLocationShareServicing {
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
@MainActor final class PersonalLocationShareRecoveryPresentationTests: XCTestCase {
    private func scope(epoch: UInt64 = 1) throws -> PersonalLocationShareScope {
        try .init(namespace: "metadata-recovery.invalid/test-only", accountId: 1, epoch: epoch)
    }
    private func coordinator(_ service: RecoveryPresentationService, _ journal: any PersonalLocationShareJournaling,
                             _ factory: RecoveryPresentationFactory? = nil) -> PersonalLocationShareCoordinator {
        .init(scope: service.scope, service: service, journal: journal, providerFactory: factory ?? RecoveryPresentationFactory(), current: { service.scope })
    }
    private func chooseAndAcknowledge(_ coordinator: PersonalLocationShareCoordinator) async {
        await coordinator.prepare(recipientId: 2)
        coordinator.chooseMode("test-exact"); coordinator.chooseDuration("test-duration")
        for disclosure in PersonalLocationShareDisclosure.allCases { coordinator.acknowledge(disclosure, accepted: true) }
    }
    func testUnreadJournalIsNotVerifiedEmpty() throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal()
        let model = coordinator(service, journal)
        XCTAssertEqual(model.journalReadState, .unread)
        XCTAssertFalse(model.originalRequestsAreVerifiedEmpty)
        XCTAssertFalse(model.canConfirm)
    }
    func testUnreadableJournalSurvivesSuccessfulOwnedAndReceivedReads() async throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal(), factory = RecoveryPresentationFactory()
        journal.failReads = true
        let model = coordinator(service, journal, factory)
        await chooseAndAcknowledge(model); await model.openManagement()
        XCTAssertEqual(model.journalReadState, .unavailable)
        XCTAssertEqual(model.ownedReadState, .loaded); XCTAssertEqual(model.receivedReadState, .loaded)
        XCTAssertTrue(model.pending.isEmpty); XCTAssertFalse(model.originalRequestsAreVerifiedEmpty)
        XCTAssertFalse(model.canConfirm); XCTAssertNil(model.makeConfirmationTicket(displayedRecipientId: 2, presentationId: UUID(), allowsFirstPermissionRequest: false))
        XCTAssertEqual(service.creates, 0); XCTAssertEqual(factory.makes, 0); XCTAssertEqual(service.publishes, 0)
        model.suspend(foreground: false, connected: false)
    }
    func testExplicitJournalRecoveryRestoresOnlyExistingEligibilityGates() async throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal(), factory = RecoveryPresentationFactory()
        let model = coordinator(service, journal, factory)
        await chooseAndAcknowledge(model); XCTAssertTrue(model.canConfirm)
        journal.failReads = true; await model.openManagement(); XCTAssertFalse(model.canConfirm)
        journal.failReads = false; await model.restoreOriginalRequests()
        XCTAssertEqual(model.journalReadState, .readable); XCTAssertTrue(model.originalRequestsAreVerifiedEmpty); XCTAssertTrue(model.canConfirm)
        XCTAssertEqual(service.creates, 0); XCTAssertEqual(factory.makes, 0)
        model.suspend(foreground: false, connected: false)
    }
    func testFailedReloadKeepsKnownOriginalMetadataVisible() async throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal()
        journal.values = [try .init(scope: service.scope, request: RecoveryPresentationService.request)]
        let model = coordinator(service, journal)
        await model.restoreOriginalRequests()
        let before = model.pending
        journal.failReads = true; await model.openManagement()
        XCTAssertEqual(model.journalReadState, .unavailable); XCTAssertEqual(model.pending, before)
        XCTAssertFalse(model.originalRequestsAreVerifiedEmpty); XCTAssertEqual(service.creates, 0)
        model.suspend(foreground: false, connected: false)
    }
    func testUnpersistedStopSurvivesReadOfOlderMetadataAndRetriesSameKey() async throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal()
        journal.values = [try .init(scope: service.scope, request: RecoveryPresentationService.request)]
        let model = coordinator(service, journal)
        await model.restoreOriginalRequests(); journal.failStopWrites = true
        await model.stop(requestKey: RecoveryPresentationService.key)
        XCTAssertTrue(model.hasUnpersistedStopIntent); XCTAssertTrue(service.revoked.isEmpty)
        await model.restoreOriginalRequests()
        XCTAssertEqual(model.pending.first?.stopRequested, true)
        XCTAssertEqual(model.requests[RecoveryPresentationService.key], .stopPending)
        XCTAssertTrue(model.hasUnpersistedStopIntent); XCTAssertFalse(model.canConfirm)
        journal.failStopWrites = false
        await model.retryStop(requestKey: RecoveryPresentationService.key)
        XCTAssertEqual(service.revoked, [RecoveryPresentationService.key]); XCTAssertEqual(service.creates, 0)
        XCTAssertTrue(model.pending.isEmpty); XCTAssertFalse(model.hasUnpersistedStopIntent)
    }
    func testNotFoundAndUnknownRevokeKeepOriginalRequestUntilTerminalReceipt() async throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal()
        journal.values = [try .init(scope: service.scope, request: RecoveryPresentationService.request)]
        let model = coordinator(service, journal)
        await model.restoreOriginalRequests()
        XCTAssertEqual(model.pending.map(\.id), [RecoveryPresentationService.key])
        service.revokeFails = true; await model.stop(requestKey: RecoveryPresentationService.key)
        await model.openManagement()
        XCTAssertEqual(model.pending.map(\.id), [RecoveryPresentationService.key]); XCTAssertEqual(model.pending.first?.stopRequested, true)
        XCTAssertFalse(model.originalRequestsAreVerifiedEmpty); XCTAssertFalse(model.canConfirm)
        service.revokeFails = false; await model.retryStop(requestKey: RecoveryPresentationService.key)
        XCTAssertTrue(model.pending.isEmpty); XCTAssertEqual(service.creates, 0)
        XCTAssertTrue(service.revoked.allSatisfy { $0 == RecoveryPresentationService.key })
        model.suspend(foreground: false, connected: false)
    }
    func testNewEpochReadsMetadataWithoutRecreatingProviderOrRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = PersonalLocationShareFileJournal(directory: directory)
        try journal.put(.init(scope: scope(), request: RecoveryPresentationService.request), scope: scope())
        let service = RecoveryPresentationService(scope: try scope(epoch: 2)), factory = RecoveryPresentationFactory()
        service.status = .active
        let model = coordinator(service, journal, factory)
        await model.openManagement()
        XCTAssertEqual(model.pending.first?.id, RecoveryPresentationService.key)
        XCTAssertEqual(model.requests[RecoveryPresentationService.key], .recoveryRequired)
        XCTAssertNil(model.publishingRequestKey); XCTAssertEqual(factory.makes, 0); XCTAssertEqual(service.creates, 0)
        XCTAssertEqual(service.queried, [RecoveryPresentationService.key])
        model.suspend(foreground: false, connected: false)
    }
    func testOwnedFailureKeepsLastReadGrantsButNeverChangesJournalEvidence() async throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal()
        service.ownedValues = [RecoveryPresentationService.grant]
        let model = coordinator(service, journal)
        await model.openManagement(); service.ownedFailure = .unknownOutcome
        await model.openManagement()
        XCTAssertEqual(model.ownedReadState, .unavailable)
        XCTAssertEqual(model.ownedGrants, [RecoveryPresentationService.grant])
        XCTAssertEqual(model.journalReadState, .readable); XCTAssertTrue(model.originalRequestsAreVerifiedEmpty)
        model.suspend(foreground: false, connected: false)
    }
    func testReceivedFailureIsIndependentFromSuccessfulOwnedAndJournal() async throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal()
        service.receivedFailure = .unknownOutcome
        let model = coordinator(service, journal)
        await model.openManagement()
        XCTAssertEqual(model.ownedReadState, .loaded); XCTAssertEqual(model.receivedReadState, .unavailable)
        XCTAssertEqual(model.journalReadState, .readable); XCTAssertTrue(model.visibleLocations.isEmpty)
    }
    func testReplacedManagementReadCannotOverwriteNewerCurrentSnapshot() async throws {
        let service = RecoveryPresentationService(scope: try scope()), journal = RecoveryPresentationJournal()
        let model = coordinator(service, journal)
        service.delayOwned = true
        let old = Task { await model.openManagement() }
        for _ in 0..<100 where service.delayedOwned == nil { await Task.yield() }
        let pending = try XCTUnwrap(service.delayedOwned)
        XCTAssertEqual(model.ownedReadState, .loading)
        service.ownedValues = [RecoveryPresentationService.grant]
        await model.openManagement()
        pending.resume(returning: .init(ownerId: 1, serverNowMs: RecoveryPresentationService.now, grants: []))
        await old.value
        XCTAssertEqual(model.ownedGrants, [RecoveryPresentationService.grant]); XCTAssertEqual(model.ownedReadState, .loaded)
        model.suspend(foreground: false, connected: false)
    }
    func testKnownDynamicSuffixesAndHTTPStatusHaveLocalizedParts() {
        let base = "暂时无法验证共享状态。不会恢复采集或显示未经验证的位置。"
        let suffixes = [
            (" 创建结果未知。保留原请求，请查询或停止；不会换新请求重试。", "createUnknown"),
            (" 服务端撤销仍待确认，请重试原请求。", "revokePending"),
            (" 本机已停止，服务端撤销待确认。保留原请求重试。", "stoppedPending"),
            (" 接收位置已隐藏。", "locationsHidden")
        ]
        for (suffix, key) in suffixes {
            let parts = PersonalLocationShareCoordinator.presentation(for: base + suffix)
            XCTAssertEqual(parts.map(\.key), ["personalLocationShare.status.37", "personalLocationShare.status." + key])
        }
        for status in [401, 403] {
            let parts = PersonalLocationShareCoordinator.presentation(for: "服务端拒绝共享访问（\(status)）。已同步停止采集并清除接收位置；需重新核验会话与授权。")
            XCTAssertEqual(parts.first?.key, "personalLocationShare.status.authorizationRejected")
            XCTAssertEqual(parts.first?.arguments, [String(status)])
        }
    }
    func testUnknownMessageIsPreservedAndNeverMappedToSuccess() {
        let message = "UNRECOGNIZED_FUTURE_LOCAL_STATUS"
        let parts = PersonalLocationShareCoordinator.presentation(for: message)
        XCTAssertNil(parts.first?.key); XCTAssertEqual(parts.first?.fallback, message)
    }
}
