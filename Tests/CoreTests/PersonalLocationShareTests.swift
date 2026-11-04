import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Examples only. These values are NOT production policy or approved defaults.
private enum PSFixture {
    static let now: Int64 = 1_800_000_000_000
    static let key = "00000000-0000-4000-8000-000000000001"
    static let grantId = "00000000-0000-4000-8000-000000000002"
    static let digest = String(repeating: "a", count: 64)
    static func scope(_ account: Int64 = 1, epoch: UInt64 = 1) throws -> PersonalLocationShareScope {
        try .init(namespace: "synthetic.invalid/test-only", accountId: account, epoch: epoch)
    }
    static func policy(acceptance: Bool = false, seconds: Int64 = 120) -> PersonalLocationSharePolicy {
        .init(policyId: "TEST_ONLY", version: 1, digest: digest, approvalRef: "TEST_NOT_APPROVAL", foregroundOnly: true,
            requiresRecipientAcceptance: acceptance,
            modeChoices: [.init(id: "test-exact", mode: .exact, datum: "WGS84", latitudeStep: nil, longitudeStep: nil)],
            durationChoices: [.init(id: "test-duration", seconds: seconds)],
            refreshAfterMs: 20_000, staleAfterMs: 30_000, displayLeaseMs: 40_000, ownerLeaseMs: 60_000)
    }
    static func request(key: String = PSFixture.key) -> PersonalLocationShareCreate {
        .init(requestKey: key, recipientId: 2, policyId: "TEST_ONLY", policyVersion: 1, policyDigest: digest,
            modeChoiceId: "test-exact", durationChoiceId: "test-duration", foregroundOnly: true,
            acknowledgedDisclosures: PersonalLocationShareDisclosure.allCases)
    }
    static func grant(key: String = PSFixture.key, owner: Int64 = 1, recipient: Int64 = 2,
                      version: Int64 = 1, watermark: Int64 = 1) -> PersonalLocationShareGrant {
        .init(grantId: grantId, requestKey: key, ownerId: owner, recipientId: recipient, policyId: "TEST_ONLY",
            policyVersion: 1, policyDigest: digest, modeChoiceId: "test-exact", mode: .exact,
            durationChoiceId: "test-duration", createdAtMs: now, expiresAtMs: now + 120_000,
            ownerLeaseUntilMs: now + 60_000, version: version, watermark: watermark, status: .active, reason: nil)
    }
    static func snapshot(owner: Int64 = 1, recipient: Int64 = 2, cursor: Int64 = 1,
                         watermark: Int64 = 1, empty: Bool = false, refreshAfterMs: Int64 = 20_000) -> PersonalLocationShareSnapshot {
        let g = grant(owner: owner, recipient: recipient, watermark: watermark)
        let observation = PersonalLocationShareObservation(grantId: grantId, ownerId: owner, recipientId: recipient,
            sequence: 1, observedAtMs: now, datum: "WGS84", mode: .exact, latitude: 0, longitude: 0,
            stale: false, version: 1, watermark: watermark)
        return .init(recipientId: recipient, serverNowMs: now, cursor: cursor, displayLeaseUntilMs: now + 40_000,
            refreshAfterMs: refreshAfterMs, staleAfterMs: 30_000, policyId: "TEST_ONLY", policyVersion: 1,
            policyDigest: digest, entries: empty ? [] : [.init(grant: g, observation: observation)])
    }
    static func active(_ request: PersonalLocationShareCreate) -> PersonalLocationShareReceipt {
        .init(requestKey: request.requestKey, known: true, state: .active, requestHash: "opaque-server-test-hash",
            grant: grant(key: request.requestKey), serverNowMs: now, watermark: 1)
    }
}
@MainActor private final class PSTransportSpy: PersonalLocationShareTransport {
    var count = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1; throw PersonalLocationShareFailure.unknownOutcome
    }
}
@MainActor private final class PSHTTPResponseTransport: PersonalLocationShareTransport {
    var status = 403
    var body = Data()
    var count = 0
    var beforeReturn: (() -> Void)?
    var urlOverride: URL?
    var thrownError: Error?
    var delays = false
    var suspended: CheckedContinuation<Void, Never>?
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        if delays { await withCheckedContinuation { suspended = $0 } }
        beforeReturn?()
        if let thrownError { throw thrownError }
        return (body, HTTPURLResponse(url: urlOverride ?? request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
@MainActor private final class PSJournal: PersonalLocationShareJournaling {
    var values: [PersonalLocationSharePendingRecord] = []
    var failed = false
    var failStopWrites = false
    func records(scope: PersonalLocationShareScope) throws -> [PersonalLocationSharePendingRecord] {
        if failed { throw PersonalLocationShareFailure.journalUnavailable }
        return values.filter { $0.namespace == scope.namespace && $0.accountId == scope.accountId }
    }
    func put(_ record: PersonalLocationSharePendingRecord, scope: PersonalLocationShareScope) throws {
        if failStopWrites && record.stopRequested { throw PersonalLocationShareFailure.journalUnavailable }
        if failed { throw PersonalLocationShareFailure.journalUnavailable }
        try record.validate(scope: scope); values.removeAll { $0.id == record.id }; values.append(record)
    }
    func remove(requestKey: String, scope: PersonalLocationShareScope) throws { values.removeAll { $0.id == requestKey && $0.accountId == scope.accountId } }
}
@MainActor private final class PSProvider: PersonalLocationShareCoordinateProviding, PersonalLocationShareCoordinateFactory {
    let isSynthetic = true
    var makes = 0
    var purposeReference = "TEST_NOT_APPROVAL"
    var binding: PersonalLocationShareCaptureBinding?
    func canCreate(scope: PersonalLocationShareScope) -> Bool { true }
    func confirmationPurpose(scope: PersonalLocationShareScope) -> PersonalLocationShareCaptureApproval? {
        try? .init(scope: scope, approvalReference: purposeReference, usageDescription: "TEST ONLY personal sharing")
    }
    func make(binding: PersonalLocationShareCaptureBinding, isCurrent: @escaping () -> Bool) throws -> any PersonalLocationShareCoordinateProviding {
        guard isCurrent() else { throw PersonalLocationShareFailure.staleSession }
        makes += 1; self.binding = binding; return self
    }
    var sampleError: PersonalLocationShareFailure?
    var samples = 0
    var stops = 0
    func sample() async throws -> PersonalLocationShareSample {
        samples += 1; if let sampleError { throw sampleError }; return .init(observedAtMs: PSFixture.now, datum: "WGS84", latitude: 0, longitude: 0, sourceId: "synthetic-test-only", systemAccuracy: .full)
    }
    func stop() { stops += 1 }
}
@MainActor private final class PSService: PersonalLocationShareServicing {
    let scope: PersonalLocationShareScope
    let isSynthetic = true
    var createCalls = 0, readCalls = 0, publishCalls = 0, revokeCalls = 0
    var failures: [PersonalLocationShareOperation: PersonalLocationShareFailure] = [:]
    var policy = PSFixture.policy()
    var snapshotRefresh: Int64 = 20_000
    var delayNextReceived = false, delayNextEvents = false
    var suspendedReceived: CheckedContinuation<PersonalLocationShareSnapshot, Error>?
    var suspendedEvents: CheckedContinuation<PersonalLocationShareEventBatch, Error>?
    var delayedEventsReturned = false
    var revokeRequestHash: String?
    var onEvents: (() -> Void)?
    var createReceipt: ((PersonalLocationShareCreate) -> PersonalLocationShareReceipt)?
    var capturedRequest: PersonalLocationShareCreate?
    var suspendedCreate: CheckedContinuation<PersonalLocationShareReceipt, Error>?
    var delayCreate = false
    var unknownCreate = false
    var unknownRevoke = false
    var ownedValues: [PersonalLocationShareGrant] = []
    var delayRevoke = false
    var suspendedRevoke: CheckedContinuation<PersonalLocationShareReceipt, Error>?
    var onRevoke: (() -> Void)?
    init(scope: PersonalLocationShareScope) { self.scope = scope }
    func context(recipientId: Int64) async throws -> PersonalLocationShareContext {
        if let error = failures[.context] { throw error }
        return .init(ownerId: scope.accountId, recipientId: recipientId, eligible: true, unavailableReason: nil, policy: policy)
    }
    func create(_ request: PersonalLocationShareCreate) async throws -> PersonalLocationShareReceipt {
        createCalls += 1; capturedRequest = request
        if let error = failures[.create] { throw error }
        if unknownCreate { throw PersonalLocationShareFailure.unknownOutcome }
        if delayCreate { return try await withCheckedThrowingContinuation { suspendedCreate = $0 } }
        return createReceipt?(request) ?? PSFixture.active(request)
    }
    func requestStatus(requestKey: String) async throws -> PersonalLocationShareReceipt {
        readCalls += 1
        if let error = failures[.requestStatus] { throw error }
        return .init(requestKey: requestKey, known: false, state: .notFound, requestHash: nil, grant: nil, serverNowMs: PSFixture.now, watermark: 0)
    }
    func revoke(requestKey: String) async throws -> PersonalLocationShareReceipt {
        revokeCalls += 1; onRevoke?()
        if let error = failures[.revoke] { throw error }
        if delayRevoke { return try await withCheckedThrowingContinuation { suspendedRevoke = $0 } }
        if unknownRevoke { throw PersonalLocationShareFailure.unknownOutcome }
        return .init(requestKey: requestKey, known: true, state: .stopped, requestHash: revokeRequestHash, grant: nil, serverNowMs: PSFixture.now, watermark: 2)
    }
    func owned() async throws -> PersonalLocationShareOwned {
        if let error = failures[.owned] { throw error }
        return .init(ownerId: scope.accountId, serverNowMs: PSFixture.now, grants: ownedValues)
    }
    func received() async throws -> PersonalLocationShareSnapshot {
        if delayNextReceived {
            delayNextReceived = false
            return try await withCheckedThrowingContinuation { suspendedReceived = $0 }
        }
        if let error = failures[.received] { throw error }
        return PSFixture.snapshot(owner: 2, recipient: scope.accountId, refreshAfterMs: snapshotRefresh)
    }
    func events(cursor: Int64) async throws -> PersonalLocationShareEventBatch {
        if delayNextEvents {
            delayNextEvents = false
            defer { delayedEventsReturned = true }
            return try await withCheckedThrowingContinuation { suspendedEvents = $0 }
        }
        onEvents?()
        if let error = failures[.events] { throw error }
        return .init(recipientId: scope.accountId, serverNowMs: PSFixture.now, cursor: cursor, resetRequired: false, refreshAfterMs: 20_000, events: [])
    }
    func publish(grantId: String, observation: PersonalLocationSharePublish, synthetic: Bool) async throws -> PersonalLocationSharePublished {
        publishCalls += 1
        if let error = failures[.publish] { throw error }
        return .init(grantId: grantId, sequence: observation.sequence, version: 2, watermark: 2, observedAtMs: observation.observedAtMs, ownerLeaseUntilMs: PSFixture.now + 60_000)
    }
}

@MainActor final class PersonalLocationShareTests: XCTestCase {
    func testNilApprovalsBlockEveryHTTPReadAndWriteBeforeTransport() async throws {
        let scope = try PSFixture.scope(); let spy = PSTransportSpy()
        let service = PersonalLocationShareHTTPService(baseURL: URL(string: "https://synthetic.invalid/")!, scope: scope,
            transport: spy, current: { scope }, token: { "test-only-not-a-real-token" })
        do { _ = try await service.context(recipientId: 2); XCTFail("read allowed") } catch { XCTAssertEqual(error as? PersonalLocationShareFailure, .unapprovedRead) }
        do { _ = try await service.create(PSFixture.request()); XCTFail("write allowed") } catch { XCTAssertEqual(error as? PersonalLocationShareFailure, .unapprovedWrite) }
        do { _ = try await service.owned(); XCTFail("owned allowed") } catch {}
        do { _ = try await service.received(); XCTFail("received allowed") } catch {}
        do { _ = try await service.events(cursor: 0); XCTFail("events allowed") } catch {}
        do { _ = try await service.requestStatus(requestKey: PSFixture.key); XCTFail("recovery allowed") } catch {}
        do { _ = try await service.revoke(requestKey: PSFixture.key); XCTFail("revoke allowed") } catch {}
        XCTAssertEqual(spy.count, 0)
    }
    func testSyntheticObservationsCannotUseRealHTTPService() async throws {
        let scope = try PSFixture.scope(); let spy = PSTransportSpy()
        let service = PersonalLocationShareHTTPService(baseURL: URL(string: "https://synthetic.invalid/")!, scope: scope,
            transport: spy, current: { scope }, token: { "test-only" })
        let observation = PersonalLocationSharePublish(sequence: 1, observedAtMs: PSFixture.now, datum: "WGS84", latitude: 0, longitude: 0, foreground: true)
        do { _ = try await service.publish(grantId: PSFixture.grantId, observation: observation, synthetic: true); XCTFail() }
        catch { XCTAssertEqual(error as? PersonalLocationShareFailure, .syntheticTransportForbidden) }
        XCTAssertEqual(spy.count, 0)
    }
    func testAcceptanceRequirementFailsClosedAndDistanceIsNotDecodable() throws {
        XCTAssertThrowsError(try PSFixture.policy(acceptance: true).validate())
        XCTAssertThrowsError(try JSONDecoder().decode(PersonalLocationShareMode.self, from: Data("\"DISTANCE_ONLY\"".utf8)))
        XCTAssertNoThrow(try PSFixture.policy().validate())
    }
    func testJournalSurvivesEpochButNeverCrossesAccountAndContainsNoLocations() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = PersonalLocationShareFileJournal(directory: folder); let scope = try PSFixture.scope()
        var record = try PersonalLocationSharePendingRecord(scope: scope, request: PSFixture.request())
        try journal.put(record, scope: scope); record.stopRequested = true; try journal.put(record, scope: scope)
        XCTAssertEqual(try journal.records(scope: PSFixture.scope(epoch: 2)).first?.id, PSFixture.key)
        XCTAssertTrue(try journal.records(scope: PSFixture.scope(3)).isEmpty)
        let data = try JSONEncoder().encode(record); let text = String(decoding: data, as: UTF8.self)
        for forbidden in ["latitude", "longitude", "token", "observation", "sourceId"] { XCTAssertFalse(text.contains(forbidden)) }
        var rewind = record; rewind.stopRequested = false
        XCTAssertThrowsError(try journal.put(rewind, scope: scope))
    }
    func testReceiverTombstoneRejectsInFlightAndFutureResurrection() throws {
        var receiver = PersonalLocationShareReceiverProjection(recipientId: 2)
        var ticket = receiver.beginRead(); XCTAssertTrue(try receiver.apply(PSFixture.snapshot(), ticket: ticket, uptime: 100))
        ticket = receiver.beginRead()
        let batch = PersonalLocationShareEventBatch(recipientId: 2, serverNowMs: PSFixture.now, cursor: 2, resetRequired: false,
            refreshAfterMs: 20_000, events: [.init(grantId: PSFixture.grantId, version: 2, watermark: 2, kind: .invalidated)])
        XCTAssertTrue(try receiver.apply(batch)); XCTAssertTrue(receiver.visible.isEmpty)
        XCTAssertFalse(try receiver.apply(PSFixture.snapshot(), ticket: ticket, uptime: 101))
        ticket = receiver.beginRead()
        XCTAssertTrue(try receiver.apply(PSFixture.snapshot(cursor: 3, watermark: 3), ticket: ticket, uptime: 102))
        XCTAssertTrue(receiver.visible.isEmpty)
    }
    func testReceiverRejectsIdentityChangeAndWrongRecipient() throws {
        var receiver = PersonalLocationShareReceiverProjection(recipientId: 2)
        var ticket = receiver.beginRead(); _ = try receiver.apply(PSFixture.snapshot(), ticket: ticket, uptime: 100)
        ticket = receiver.beginRead(); XCTAssertThrowsError(try receiver.apply(PSFixture.snapshot(owner: 3, cursor: 2, watermark: 2), ticket: ticket, uptime: 101))
        XCTAssertTrue(receiver.visible.isEmpty)
        ticket = receiver.beginRead(); XCTAssertThrowsError(try receiver.apply(PSFixture.snapshot(recipient: 4), ticket: ticket, uptime: 102))
    }
    func testLeaseAndStaleUseMonotonicRequestStartNotWallClockOrResponseArrival() throws {
        var receiver = PersonalLocationShareReceiverProjection(recipientId: 2)
        let ticket = receiver.beginRead(); _ = try receiver.apply(PSFixture.snapshot(), ticket: ticket, uptime: 100)
        let item = try XCTUnwrap(receiver.visible.values.first)
        XCTAssertEqual(item.deadlineUptime, 140)
        XCTAssertFalse(item.isStale(at: 129)); XCTAssertTrue(item.isStale(at: 130))
        receiver.expire(at: 140); XCTAssertTrue(receiver.visible.isEmpty)
    }
    func testSnapshotIsReplacementAndResetClearsBeforeNextRead() throws {
        var receiver = PersonalLocationShareReceiverProjection(recipientId: 2)
        var ticket = receiver.beginRead(); _ = try receiver.apply(PSFixture.snapshot(), ticket: ticket, uptime: 100)
        ticket = receiver.beginRead(); _ = try receiver.apply(PSFixture.snapshot(cursor: 2, empty: true), ticket: ticket, uptime: 101)
        XCTAssertTrue(receiver.visible.isEmpty)
        let reset = PersonalLocationShareEventBatch(recipientId: 2, serverNowMs: PSFixture.now, cursor: 3, resetRequired: true, refreshAfterMs: 20_000, events: [])
        XCTAssertTrue(try receiver.apply(reset)); XCTAssertTrue(receiver.visible.isEmpty)
    }
    func testServerCursorResetMayMoveBackwardButStillClears() throws {
        var receiver = PersonalLocationShareReceiverProjection(recipientId: 2)
        let ticket = receiver.beginRead(); _ = try receiver.apply(PSFixture.snapshot(cursor: 9), ticket: ticket, uptime: 100)
        let reset = PersonalLocationShareEventBatch(recipientId: 2, serverNowMs: PSFixture.now, cursor: 1,
            resetRequired: true, refreshAfterMs: 20_000, events: [])
        XCTAssertTrue(try receiver.apply(reset)); XCTAssertTrue(receiver.visible.isEmpty); XCTAssertEqual(receiver.cursor, 1)
    }
    func testClearRejectsPreviouslyIssuedTicketAfterDisconnect() throws {
        var receiver = PersonalLocationShareReceiverProjection(recipientId: 2)
        let ticket = receiver.beginRead(); receiver.clear()
        XCTAssertFalse(try receiver.apply(PSFixture.snapshot(), ticket: ticket, uptime: 100))
        XCTAssertTrue(receiver.visible.isEmpty)
    }
    private func confirm(_ coordinator: PersonalLocationShareCoordinator, firstPermission: Bool = false) async {
        guard let recipient = coordinator.recipientId,
              let ticket = coordinator.makeConfirmationTicket(displayedRecipientId: recipient, presentationId: UUID(),
                allowsFirstPermissionRequest: firstPermission) else { return }
        await coordinator.confirmStart(ticket: ticket).value
    }
    private func configured(service: PSService, journal: PSJournal, provider: PSProvider, uptime: @escaping () -> TimeInterval = { 100 }) async -> PersonalLocationShareCoordinator {
        let scope = service.scope
        let coordinator = PersonalLocationShareCoordinator(scope: scope, service: service, journal: journal,
            providerFactory: provider, current: { scope }, uptime: uptime)
        await coordinator.prepare(recipientId: 2)
        coordinator.chooseMode("test-exact"); coordinator.chooseDuration("test-duration")
        for item in PersonalLocationShareDisclosure.allCases { coordinator.acknowledge(item, accepted: true) }
        return coordinator
    }
    func testUnknownCreateRestoresOriginalKeyReadOnlyAndBlocksFreshCreate() async throws {
        let service = PSService(scope: try PSFixture.scope()); service.unknownCreate = true
        let journal = PSJournal(); let provider = PSProvider()
        let coordinator = await configured(service: service, journal: journal, provider: provider)
        await confirm(coordinator); let key = try XCTUnwrap(journal.values.first?.id)
        XCTAssertEqual(service.createCalls, 1); XCTAssertEqual(provider.samples, 0)
        let recovered = PersonalLocationShareCoordinator(scope: service.scope, service: service, journal: journal,
            providerFactory: provider, current: { service.scope })
        await recovered.restoreOriginalRequests()
        XCTAssertEqual(recovered.pending.first?.id, key); XCTAssertFalse(recovered.canConfirm)
        XCTAssertEqual(service.createCalls, 1); XCTAssertEqual(service.publishCalls, 0)
    }
    func testStopBeforeCreateReplyWinsAndOriginalKeyIsRevoked() async throws {
        let service = PSService(scope: try PSFixture.scope()); service.delayCreate = true
        let journal = PSJournal(); let provider = PSProvider()
        let coordinator = await configured(service: service, journal: journal, provider: provider)
        let create = Task { await confirm(coordinator) }
        for _ in 0..<100 where service.suspendedCreate == nil { await Task.yield() }
        let request = try XCTUnwrap(service.capturedRequest)
        service.onRevoke = { XCTAssertEqual(provider.makes, 0); XCTAssertEqual(journal.values.first?.id, request.requestKey); XCTAssertEqual(journal.values.first?.stopRequested, true) }
        await coordinator.stop(requestKey: request.requestKey)
        service.suspendedCreate?.resume(returning: PSFixture.active(request)); service.suspendedCreate = nil
        await create.value
        XCTAssertEqual(service.revokeCalls, 1); XCTAssertEqual(service.publishCalls, 0)
        XCTAssertNil(coordinator.publishingRequestKey); XCTAssertTrue(journal.values.isEmpty)
    }
    func testUnknownStopPersistsIntentAndBackgroundClearsImmediately() async throws {
        let service = PSService(scope: try PSFixture.scope()); service.unknownCreate = true; service.unknownRevoke = true
        let journal = PSJournal(); let provider = PSProvider()
        let coordinator = await configured(service: service, journal: journal, provider: provider)
        await confirm(coordinator); let key = try XCTUnwrap(journal.values.first?.id)
        await coordinator.stop(requestKey: key)
        XCTAssertEqual(coordinator.requests[key], .stopPending); XCTAssertEqual(journal.values.first?.stopRequested, true)
        coordinator.suspend(foreground: false, connected: false)
        XCTAssertTrue(coordinator.visibleLocations.isEmpty); XCTAssertNil(coordinator.publishingRequestKey)
        XCTAssertEqual(journal.values.first?.id, key)
    }
    func testSessionChangesWhileCreateIsAwaitingNeverPublishOrLoseOriginalIntent() async throws {
        let service = PSService(scope: try PSFixture.scope()); service.delayCreate = true
        let journal = PSJournal(); let provider = PSProvider()
        let coordinator = await configured(service: service, journal: journal, provider: provider)
        let task = Task { await confirm(coordinator) }
        for _ in 0..<100 where service.suspendedCreate == nil { await Task.yield() }
        let request = try XCTUnwrap(service.capturedRequest)
        coordinator.suspend(foreground: false, connected: false)
        service.suspendedCreate?.resume(returning: PSFixture.active(request)); service.suspendedCreate = nil
        await task.value
        XCTAssertEqual(service.publishCalls, 0); XCTAssertEqual(provider.samples, 0)
        XCTAssertEqual(journal.values.first?.id, request.requestKey)
        XCTAssertEqual(journal.values.first?.stopRequested, true)
    }
    func testJournalFailureAndMissingProviderNeverCreate() async throws {
        let service = PSService(scope: try PSFixture.scope()); let journal = PSJournal(); journal.failed = true
        let provider = PSProvider(); let coordinator = await configured(service: service, journal: journal, provider: provider)
        XCTAssertFalse(coordinator.canConfirm); await confirm(coordinator); XCTAssertEqual(service.createCalls, 0)
        let missingProvider = PersonalLocationShareCoordinator(scope: service.scope, service: service, journal: PSJournal(), current: { service.scope })
        await missingProvider.prepare(recipientId: 2); XCTAssertFalse(missingProvider.providerIsConnected); XCTAssertFalse(missingProvider.canConfirm)
    }
    func testFactoryOnlyReceivesConfirmedLiveGrantAndExplicitPermissionCapability() async throws {
        let service = PSService(scope: try PSFixture.scope()); let provider = PSProvider()
        let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
        XCTAssertEqual(provider.makes, 0); XCTAssertTrue(coordinator.canConfirm)
        await confirm(coordinator, firstPermission: true)
        XCTAssertEqual(provider.makes, 1)
        XCTAssertEqual(provider.binding?.scope, service.scope)
        XCTAssertEqual(provider.binding?.grant.requestKey, service.capturedRequest?.requestKey)
        XCTAssertEqual(provider.binding?.allowsFirstPermissionRequest, true)
        coordinator.suspend(foreground: false, connected: false)
        XCTAssertGreaterThan(provider.stops, 0); XCTAssertNil(coordinator.publishingRequestKey)
    }

    func testOwnedOnlyStopJournalFailureCannotBeReopenedBySuccessfulRead() async throws {
        let service = PSService(scope: try PSFixture.scope()); service.ownedValues = [PSFixture.grant()]
        let journal = PSJournal(); let provider = PSProvider()
        let coordinator = await configured(service: service, journal: journal, provider: provider)
        await coordinator.openManagement(); journal.failStopWrites = true
        await coordinator.stop(requestKey: PSFixture.key)
        XCTAssertTrue(coordinator.pending.isEmpty); XCTAssertEqual(service.revokeCalls, 0)
        XCTAssertTrue(coordinator.message.contains("停止意图未能安全保存"))
        await coordinator.restoreOriginalRequests() // Read succeeds, but never erases a failed stop write.
        coordinator.chooseMode("test-exact"); coordinator.chooseDuration("test-duration")
        for item in PersonalLocationShareDisclosure.allCases { coordinator.acknowledge(item, accepted: true) }
        XCTAssertFalse(coordinator.canConfirm); await confirm(coordinator); XCTAssertEqual(service.createCalls, 0)
    }
    func testPublisherPermissionFailureIsVisibleBeforeHangingRevokeCompletes() async throws {
        let service = PSService(scope: try PSFixture.scope()); service.delayRevoke = true
        let provider = PSProvider(); provider.sampleError = .existingLocationPermissionRequired
        let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
        await confirm(coordinator)
        for _ in 0..<100 where service.suspendedRevoke == nil { await Task.yield() }
        XCTAssertTrue(coordinator.message.contains("不会绕过拒绝或受限状态"))
        XCTAssertNil(coordinator.publishingRequestKey); XCTAssertGreaterThan(provider.stops, 0)
        let key = try XCTUnwrap(service.capturedRequest?.requestKey)
        service.suspendedRevoke?.resume(returning: .init(requestKey: key, known: true, state: .stopped,
            requestHash: nil, grant: nil, serverNowMs: PSFixture.now, watermark: 2))
        service.suspendedRevoke = nil
    }
    func testPublisherMustNotOverwriteStopJournalFailureWithPermissionMessage() async throws {
        let service = PSService(scope: try PSFixture.scope()); let journal = PSJournal(); journal.failStopWrites = true
        let provider = PSProvider(); provider.sampleError = .reducedAccuracyUnavailable
        let coordinator = await configured(service: service, journal: journal, provider: provider)
        await confirm(coordinator)
        for _ in 0..<100 where provider.stops == 0 { await Task.yield() }
        XCTAssertTrue(coordinator.message.contains("停止意图未能安全保存"))
        XCTAssertFalse(coordinator.canConfirm); XCTAssertEqual(service.revokeCalls, 0)
    }

    private func ticket(_ coordinator: PersonalLocationShareCoordinator, recipient: Int64 = 2, presentation: UUID = UUID(), permission: Bool = false) throws -> PersonalLocationShareConfirmationTicket {
        try XCTUnwrap(coordinator.makeConfirmationTicket(displayedRecipientId: recipient, presentationId: presentation,
            allowsFirstPermissionRequest: permission))
    }
    func testTicketRequiresTheRecipientActuallyDisplayedByItsEntry() async throws {
        let service = PSService(scope: try PSFixture.scope())
        let coordinator = await configured(service: service, journal: PSJournal(), provider: PSProvider())
        XCTAssertNil(coordinator.makeConfirmationTicket(displayedRecipientId: 3, presentationId: UUID(), allowsFirstPermissionRequest: true))
        XCTAssertEqual(service.createCalls, 0)
        let value = try ticket(coordinator, permission: true)
        XCTAssertEqual(value.recipientId, 2); XCTAssertEqual(value.duration.seconds, 120)
        XCTAssertEqual(value.scope, service.scope); XCTAssertTrue(value.allowsFirstPermissionRequest)
    }
    func testOldDialogCannotConsumeAnotherRecipientOrNewPolicyContext() async throws {
        let service = PSService(scope: try PSFixture.scope()); let provider = PSProvider()
        let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
        let old = try ticket(coordinator)
        await coordinator.prepare(recipientId: 3)
        coordinator.chooseMode("test-exact"); coordinator.chooseDuration("test-duration")
        for item in PersonalLocationShareDisclosure.allCases { coordinator.acknowledge(item, accepted: true) }
        let replacement = try ticket(coordinator, recipient: 3)
        await coordinator.confirmStart(ticket: old).value
        XCTAssertEqual(service.createCalls, 0); XCTAssertEqual(provider.makes, 0)
        XCTAssertTrue(coordinator.confirmationIsCurrent(replacement))
    }
    func testChoiceAcknowledgementPurposeAndPresentationChangesInvalidateTicket() async throws {
        for change in 0..<6 {
            let service = PSService(scope: try PSFixture.scope()); let provider = PSProvider()
            let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
            let value = try ticket(coordinator)
            switch change {
            case 0: coordinator.chooseMode("test-exact")
            case 1: coordinator.chooseDuration("test-duration")
            case 2: coordinator.acknowledge(.audience, accepted: false)
            case 3: provider.purposeReference = "CHANGED_TEST_PURPOSE"
            case 4: coordinator.cancelConfirmationTicket(value)
            default: coordinator.confirmationEntryDisappeared(presentationId: value.presentationId)
            }
            XCTAssertFalse(coordinator.confirmationIsCurrent(value))
            if change < 3 { for item in PersonalLocationShareDisclosure.allCases { coordinator.acknowledge(item, accepted: true) } }
            await coordinator.confirmStart(ticket: value).value
            XCTAssertEqual(service.createCalls, 0); XCTAssertEqual(provider.makes, 0)
        }
    }
    func testTicketCannotBeReplayedOrTransferredToAnotherCoordinator() async throws {
        let service = PSService(scope: try PSFixture.scope()); let provider = PSProvider()
        let original = await configured(service: service, journal: PSJournal(), provider: provider)
        let value = try ticket(original)
        let other = await configured(service: service, journal: PSJournal(), provider: PSProvider())
        await other.confirmStart(ticket: value).value; XCTAssertEqual(service.createCalls, 0)
        let start = original.confirmStart(ticket: value)
        original.cancelConfirmationTicket(value) // Dialog dismissal cannot undo the already-consumed button action.
        await start.value; await original.confirmStart(ticket: value).value
        XCTAssertEqual(service.createCalls, 1); XCTAssertEqual(provider.makes, 1)
        original.suspend(foreground: false, connected: false)
    }
    func testExpiredTicketNeverCreatesAndUsesOnlySelectedDurationForTimeout() async throws {
        var now: TimeInterval = 100
        let service = PSService(scope: try PSFixture.scope())
        let coordinator = await configured(service: service, journal: PSJournal(), provider: PSProvider(), uptime: { now })
        let value = try ticket(coordinator)
        XCTAssertEqual(value.localDeadlineUptime, 220)
        now = 220; await coordinator.confirmStart(ticket: value).value; XCTAssertEqual(service.createCalls, 0)
    }
    func testCreateReplyAfterDifferentEntryOrDisappearNeverStartsSource() async throws {
        for disappear in [false, true] {
            let service = PSService(scope: try PSFixture.scope()); service.delayCreate = true
            let provider = PSProvider(); let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
            let value = try ticket(coordinator); let start = coordinator.confirmStart(ticket: value)
            for _ in 0..<100 where service.suspendedCreate == nil { await Task.yield() }
            if disappear { coordinator.confirmationEntryDisappeared(presentationId: value.presentationId) }
            else { await coordinator.prepare(recipientId: 3) }
            let request = try XCTUnwrap(service.capturedRequest)
            service.suspendedCreate?.resume(returning: PSFixture.active(request)); service.suspendedCreate = nil
            await start.value
            XCTAssertEqual(provider.makes, 0); XCTAssertEqual(service.publishCalls, 0); XCTAssertEqual(service.revokeCalls, 1)
            XCTAssertEqual(request.recipientId, 2)
        }
    }
    private func alteredGrant(_ source: PersonalLocationShareGrant, expiresAt: Int64, durationId: String? = nil) -> PersonalLocationShareGrant {
        .init(grantId: source.grantId, requestKey: source.requestKey, ownerId: source.ownerId, recipientId: source.recipientId,
            policyId: source.policyId, policyVersion: source.policyVersion, policyDigest: source.policyDigest,
            modeChoiceId: source.modeChoiceId, mode: source.mode, durationChoiceId: durationId ?? source.durationChoiceId,
            createdAtMs: source.createdAtMs, expiresAtMs: expiresAt, ownerLeaseUntilMs: min(source.ownerLeaseUntilMs, expiresAt),
            version: source.version, watermark: source.watermark, status: source.status, reason: source.reason)
    }
    func testNumericGrantDurationCannotExceedFrozenChoiceEvenWithMatchingId() async throws {
        let service = PSService(scope: try PSFixture.scope())
        let coordinator = await configured(service: service, journal: PSJournal(), provider: PSProvider())
        let value = try ticket(coordinator), grant = PSFixture.grant()
        XCTAssertThrowsError(try PersonalLocationShareCoordinator.confirmedDeadline(
            grant: alteredGrant(grant, expiresAt: PSFixture.now + 3_600_000), ticket: value, serverNowMs: PSFixture.now, requestStarted: 100))
        XCTAssertThrowsError(try PersonalLocationShareCoordinator.confirmedDeadline(
            grant: alteredGrant(grant, expiresAt: PSFixture.now + 60_000, durationId: "wrong"), ticket: value, serverNowMs: PSFixture.now, requestStarted: 100))
        XCTAssertEqual(try PersonalLocationShareCoordinator.confirmedDeadline(grant: grant, ticket: value, serverNowMs: PSFixture.now, requestStarted: 110), 220)
        XCTAssertEqual(try PersonalLocationShareCoordinator.confirmedDeadline(grant: alteredGrant(grant, expiresAt: PSFixture.now + 30_000), ticket: value, serverNowMs: PSFixture.now, requestStarted: 110), 140, accuracy: 0.000001)
        XCTAssertThrowsError(try PersonalLocationShareCoordinator.confirmedDeadline(grant: grant, ticket: value, serverNowMs: PSFixture.now, requestStarted: 221))
    }
    func testAuthorizationFailureInEveryCoordinatorReadMutationPathRetiresState() async throws {
        for operation in [PersonalLocationShareOperation.context, .create, .requestStatus, .revoke, .owned, .received, .publish] {
            let service = PSService(scope: try PSFixture.scope()); let provider = PSProvider(); let journal = PSJournal()
            let coordinator = await configured(service: service, journal: journal, provider: provider)
            if operation == .requestStatus || operation == .revoke {
                service.unknownCreate = true; await confirm(coordinator)
            }
            service.failures[operation] = .authorizationRejected(status: 403, errorCode: "RELATION_UNAVAILABLE")
            switch operation {
            case .context: await coordinator.prepare(recipientId: 2)
            case .create, .publish: await confirm(coordinator)
            case .requestStatus: await coordinator.readback(requestKey: try XCTUnwrap(journal.values.first?.id))
            case .revoke: await coordinator.stop(requestKey: try XCTUnwrap(journal.values.first?.id))
            case .owned: await coordinator.openManagement()
            case .received: await coordinator.refreshReceived()
            default: break
            }
            for _ in 0..<100 where !coordinator.authorizationBlocked { await Task.yield() }
            XCTAssertTrue(coordinator.authorizationBlocked, operation.rawValue)
            XCTAssertNil(coordinator.publishingRequestKey); XCTAssertTrue(coordinator.visibleLocations.isEmpty)
            coordinator.resume(foreground: true, connected: true); XCTAssertFalse(coordinator.canConfirm)
        }
    }
    func testServiceUnavailableAndMalformedCreateStayOnOriginalUnknownKey() async throws {
        for failure in [PersonalLocationShareFailure.server("POLICY_UNAVAILABLE"), .unknownOutcome] {
            let service = PSService(scope: try PSFixture.scope()); service.failures[.create] = failure
            let journal = PSJournal(), provider = PSProvider()
            let coordinator = await configured(service: service, journal: journal, provider: provider)
            await confirm(coordinator); let key = try XCTUnwrap(journal.values.first?.id)
            await confirm(coordinator); await coordinator.restoreOriginalRequests()
            XCTAssertEqual(journal.values.first?.id, key); XCTAssertEqual(service.createCalls, 1)
            XCTAssertEqual(provider.makes, 0); XCTAssertFalse(coordinator.canConfirm)
        }
    }

    func testPolicySecondsChangingBehindSameChoiceIdRequiresNewConfirmation() async throws {
        let service = PSService(scope: try PSFixture.scope())
        let coordinator = await configured(service: service, journal: PSJournal(), provider: PSProvider())
        let old = try ticket(coordinator)
        service.policy = PSFixture.policy(seconds: 600)
        await coordinator.prepare(recipientId: 2)
        coordinator.chooseMode("test-exact"); coordinator.chooseDuration("test-duration")
        for item in PersonalLocationShareDisclosure.allCases { coordinator.acknowledge(item, accepted: true) }
        let updated = try ticket(coordinator)
        XCTAssertEqual(updated.duration.id, old.duration.id); XCTAssertNotEqual(updated.duration.seconds, old.duration.seconds)
        await coordinator.confirmStart(ticket: old).value; XCTAssertEqual(service.createCalls, 0)
    }
    func testEventsAuthorizationFailureStopsAnAlreadyActivePublisherAndClearsReceiver() async throws {
        let service = PSService(scope: try PSFixture.scope()); service.snapshotRefresh = 1 // Synthetic test scheduling only.
        let provider = PSProvider(); let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
        await confirm(coordinator)
        service.failures[.events] = .authorizationRejected(status: 401, errorCode: "SESSION_INVALID")
        let receivedEvent = expectation(description: "fake events denial")
        service.onEvents = { receivedEvent.fulfill() }
        await coordinator.refreshReceived(); XCTAssertFalse(coordinator.visibleLocations.isEmpty)
        await fulfillment(of: [receivedEvent], timeout: 1)
        XCTAssertTrue(coordinator.authorizationBlocked); XCTAssertNil(coordinator.publishingRequestKey)
        XCTAssertTrue(coordinator.visibleLocations.isEmpty); XCTAssertGreaterThan(provider.stops, 0)
    }
    private var operations: [PersonalLocationShareOperation] { [.context, .create, .requestStatus, .revoke, .owned, .received, .events, .publish] }
    private func approvedHTTP(_ transport: PSHTTPResponseTransport, current: (() -> PersonalLocationShareScope?)? = nil,
                              token: @escaping () -> String? = { "SYNTHETIC_NOT_CREDENTIAL" },
                              isCurrentService: @escaping () -> Bool = { true }, authorizationGeneration: @escaping () -> UInt64 = { 0 },
                              denied: @escaping (PersonalLocationShareFailure) -> Void = { _ in }) throws -> PersonalLocationShareHTTPService {
        let scope = try PSFixture.scope(), base = URL(string: "https://synthetic.invalid/")!
        let approval = try PersonalLocationShareEndpointApproval(origin: base, approvalReference: "TEST_NOT_APPROVAL", operations: Set(operations))
        return PersonalLocationShareHTTPService(baseURL: base, scope: scope, transport: transport,
            current: current ?? { scope }, token: token, readApproval: { approval }, writeApproval: { approval }, isCurrentService: isCurrentService,
            authorizationGeneration: authorizationGeneration, onAuthorizationFailure: denied)
    }
    private func call(_ service: PersonalLocationShareHTTPService, operation: PersonalLocationShareOperation) async throws {
        switch operation {
        case .context: _ = try await service.context(recipientId: 2)
        case .create: _ = try await service.create(PSFixture.request())
        case .requestStatus: _ = try await service.requestStatus(requestKey: PSFixture.key)
        case .revoke: _ = try await service.revoke(requestKey: PSFixture.key)
        case .owned: _ = try await service.owned()
        case .received: _ = try await service.received()
        case .events: _ = try await service.events(cursor: 0)
        case .publish: _ = try await service.publish(grantId: PSFixture.grantId,
            observation: .init(sequence: 1, observedAtMs: PSFixture.now, datum: "WGS84", latitude: 0, longitude: 0, foreground: true), synthetic: false)
        }
    }
    func testEveryHTTPRouteReports401403SynchronouslyEvenWithMalformedBody() async throws {
        for operation in operations { for status in [401, 403] { for malformed in [false, true] {
            let transport = PSHTTPResponseTransport(); transport.status = status
            transport.body = Data((malformed ? "not JSON" : "{\"code\":\(status),\"errorCode\":\"RELATION_UNAVAILABLE\",\"msg\":\"UNTRUSTED_TEXT\"}").utf8)
            var callbacks = 0
            let service = try approvedHTTP(transport, denied: { _ in callbacks += 1 })
            do { try await call(service, operation: operation); XCTFail("auth denial accepted") }
            catch {
                XCTAssertEqual(callbacks, 1, operation.rawValue)
                XCTAssertEqual(error as? PersonalLocationShareFailure, .authorizationRejected(status: status, errorCode: malformed ? nil : "RELATION_UNAVAILABLE"))
            }
            XCTAssertEqual(transport.count, 1)
        } } }
    }
    func testHTTP503MachineCodeAndBadJSONNeverInventSuccess() async throws {
        for operation in operations { for status in [200, 503] {
            let transport = PSHTTPResponseTransport(); transport.status = status; transport.body = Data("{bad JSON".utf8)
            var callbacks = 0; let service = try approvedHTTP(transport, denied: { _ in callbacks += 1 })
            do { try await call(service, operation: operation); XCTFail("bad body accepted") }
            catch { XCTAssertEqual(error as? PersonalLocationShareFailure, .unknownOutcome) }
            XCTAssertEqual(callbacks, 0)
        } }
        let transport = PSHTTPResponseTransport(); transport.status = 503
        transport.body = Data("{\"code\":503,\"errorCode\":\"POLICY_UNAVAILABLE\",\"msg\":\"not for UI\"}".utf8)
        let service = try approvedHTTP(transport)
        do { _ = try await service.create(PSFixture.request()); XCTFail("503 accepted") }
        catch { XCTAssertEqual(error as? PersonalLocationShareFailure, .server("POLICY_UNAVAILABLE")) }
    }
    func testAuthRejectionWinsCancellationButCannotInvalidateNewScopeOrToken() async throws {
        let transport = PSHTTPResponseTransport(); transport.status = 401
        transport.beforeReturn = { withUnsafeCurrentTask { $0?.cancel() } }
        var callbacks = 0; let service = try approvedHTTP(transport, denied: { _ in callbacks += 1 })
        let task = Task { () -> PersonalLocationShareFailure? in
            do { _ = try await service.received(); return nil } catch { return error as? PersonalLocationShareFailure }
        }
        let result = await task.value
        XCTAssertEqual(result, .authorizationRejected(status: 401, errorCode: nil)); XCTAssertEqual(callbacks, 1)
        for changeToken in [false, true] {
            var scope: PersonalLocationShareScope? = try PSFixture.scope(); var token = "SYNTHETIC_NOT_CREDENTIAL"
            let stale = PSHTTPResponseTransport(); stale.status = 403
            let newScope = try PSFixture.scope(epoch: 2)
            stale.beforeReturn = { if changeToken { token = "REPLACED_SYNTHETIC" } else { scope = newScope } }
            var staleCallbacks = 0
            let staleService = try approvedHTTP(stale, current: { scope }, token: { token }, denied: { _ in staleCallbacks += 1 })
            do { _ = try await staleService.received(); XCTFail("stale reply accepted") }
            catch { XCTAssertEqual(error as? PersonalLocationShareFailure, .staleSession) }
            XCTAssertEqual(staleCallbacks, 0)
        }
    }
    func testAuthCallbackImmediatelyClearsActiveSourceAndReceivedLocations() async throws {
        let fakeService = PSService(scope: try PSFixture.scope()), provider = PSProvider()
        let coordinator = await configured(service: fakeService, journal: PSJournal(), provider: provider)
        await confirm(coordinator); await coordinator.refreshReceived()
        XCTAssertFalse(coordinator.visibleLocations.isEmpty)
        let transport = PSHTTPResponseTransport(); transport.status = 403; transport.body = Data("bad body".utf8)
        var synchronousRetirement = false
        let service = try approvedHTTP(transport, denied: { error in
            coordinator.authorizationRejected(error)
            synchronousRetirement = coordinator.visibleLocations.isEmpty && coordinator.publishingRequestKey == nil && provider.stops > 0
        })
        do { _ = try await service.received(); XCTFail("403 accepted") } catch {}
        XCTAssertTrue(synchronousRetirement); XCTAssertTrue(coordinator.authorizationBlocked)
    }

    func testLateAuthFromReplacedServiceOrLifecycleCannotInvalidateNewLease() async throws {
        for status in [401, 403, 503] { for lifecycleOnly in [false, true] { for malformed in [false, true] {
            let oldLease = UUID(); var currentLease = oldLease; var generation: UInt64 = 4
            var newLeaseStops = 0
            let transport = PSHTTPResponseTransport(); transport.status = status
            transport.body = Data((malformed ? "bad body" : "{\"code\":\(status),\"errorCode\":\"POLICY_UNAVAILABLE\"}").utf8)
            transport.beforeReturn = { if lifecycleOnly { generation += 1 } else { currentLease = UUID() } }
            let service = try approvedHTTP(transport, isCurrentService: { currentLease == oldLease },
                authorizationGeneration: { generation }, denied: { _ in newLeaseStops += 1 })
            do { _ = try await service.received(); XCTFail("retired request denial was applied") }
            catch { XCTAssertEqual(error as? PersonalLocationShareFailure, lifecycleOnly ? .retiredResponse : .staleSession) }
            XCTAssertEqual(newLeaseStops, 0)
        } } }
    }

    func testOverlongCreateReceiptNeverConstructsProviderAndStopsOriginalKey() async throws {
        let service = PSService(scope: try PSFixture.scope()), provider = PSProvider(), journal = PSJournal()
        service.createReceipt = { request in
            let base = PSFixture.active(request)
            return .init(requestKey: request.requestKey, known: true, state: .active, requestHash: base.requestHash,
                grant: self.alteredGrant(base.grant!, expiresAt: PSFixture.now + 3_600_000), serverNowMs: PSFixture.now, watermark: 1)
        }
        let coordinator = await configured(service: service, journal: journal, provider: provider)
        await confirm(coordinator)
        XCTAssertEqual(service.createCalls, 1); XCTAssertEqual(service.revokeCalls, 1)
        XCTAssertEqual(provider.makes, 0); XCTAssertEqual(provider.samples, 0); XCTAssertEqual(service.publishCalls, 0)
        XCTAssertTrue(journal.values.isEmpty || journal.values.allSatisfy(\.stopRequested))
    }
    func testKnownPolicy503FromReadAlsoStopsExistingPublicationWithoutFreshPOST() async throws {
        let service = PSService(scope: try PSFixture.scope()), provider = PSProvider(), journal = PSJournal()
        let coordinator = await configured(service: service, journal: journal, provider: provider)
        await confirm(coordinator); await coordinator.refreshReceived()
        service.failures[.received] = .server("POLICY_UNAVAILABLE")
        await coordinator.refreshReceived()
        XCTAssertNil(coordinator.publishingRequestKey); XCTAssertTrue(coordinator.visibleLocations.isEmpty)
        XCTAssertGreaterThan(provider.stops, 0); XCTAssertTrue(journal.values.allSatisfy(\.stopRequested))
        XCTAssertTrue(coordinator.connected); XCTAssertFalse(coordinator.authorizationBlocked)
        let key = try XCTUnwrap(journal.values.first?.id), reads = service.readCalls
        await coordinator.readback(requestKey: key); XCTAssertEqual(service.readCalls, reads + 1)
        await coordinator.retryStop(requestKey: key); XCTAssertEqual(service.revokeCalls, 1)
        await confirm(coordinator); XCTAssertEqual(service.createCalls, 1)
    }

    func testRetiredDenialCannotClearCurrentReceiverOrStopCurrentPublisher() async throws {
        let service = PSService(scope: try PSFixture.scope()), provider = PSProvider()
        let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
        await confirm(coordinator); await coordinator.refreshReceived()
        let key = try XCTUnwrap(coordinator.publishingRequestKey), stops = provider.stops
        XCTAssertFalse(coordinator.visibleLocations.isEmpty)
        service.failures[.received] = .retiredResponse
        await coordinator.refreshReceived()
        XCTAssertEqual(coordinator.publishingRequestKey, key); XCTAssertEqual(provider.stops, stops)
        XCTAssertFalse(coordinator.visibleLocations.isEmpty); XCTAssertFalse(coordinator.authorizationBlocked)
        coordinator.suspend(foreground: false, connected: false)
    }

    func testSelectedDurationRoundingNeverAddsAnotherSecond() throws {
        let seconds = Int64.max / 1000
        let end = try XCTUnwrap(PersonalLocationShareCoordinator.selectedDeadline(start: 0, seconds: seconds))
        XCTAssertLessThanOrEqual(Int64(end), seconds)
        XCTAssertNil(PersonalLocationShareCoordinator.selectedDeadline(start: .infinity, seconds: 120))
        XCTAssertNil(PersonalLocationShareCoordinator.selectedDeadline(start: 100, seconds: 0))
    }

    func testRetiredTransportRepliesAndThrowsWinOverCancellationBeforeBodyHandling() async throws {
        for kind in 0..<4 {
            var revision: UInt64 = 1, callbacks = 0
            let transport = PSHTTPResponseTransport(); transport.status = kind == 1 ? 503 : 200
            transport.body = Data("{bad JSON".utf8)
            if kind == 2 { transport.thrownError = CancellationError() }
            if kind == 3 { transport.thrownError = URLError(.networkConnectionLost) }
            transport.beforeReturn = { revision += 1; withUnsafeCurrentTask { $0?.cancel() } }
            let service = try approvedHTTP(transport, authorizationGeneration: { revision }, denied: { _ in callbacks += 1 })
            let result = await Task { () -> PersonalLocationShareFailure? in
                do { _ = try await service.events(cursor: 0); return nil }
                catch { return error as? PersonalLocationShareFailure }
            }.value
            XCTAssertEqual(result, .retiredResponse); XCTAssertEqual(callbacks, 0)
        }
    }
    func testReplacedSnapshotReadCannotClearNewSnapshotWithinSamePublicationLease() async throws {
        let failures: [Error] = [CancellationError(), URLError(.networkConnectionLost), PersonalLocationShareFailure.server("POLICY_UNAVAILABLE")]
        for failure in failures {
            let service = PSService(scope: try PSFixture.scope()), provider = PSProvider()
            let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
            await confirm(coordinator); service.delayNextReceived = true
            let old = Task { await coordinator.refreshReceived() }
            for _ in 0..<100 where service.suspendedReceived == nil { await Task.yield() }
            let suspended = try XCTUnwrap(service.suspendedReceived), revision = coordinator.authorizationGeneration
            await coordinator.refreshReceived()
            let key = try XCTUnwrap(coordinator.publishingRequestKey), stops = provider.stops
            XCTAssertFalse(coordinator.visibleLocations.isEmpty)
            suspended.resume(throwing: failure); service.suspendedReceived = nil
            await old.value
            XCTAssertEqual(coordinator.authorizationGeneration, revision)
            XCTAssertEqual(coordinator.publishingRequestKey, key); XCTAssertEqual(provider.stops, stops)
            XCTAssertFalse(coordinator.visibleLocations.isEmpty)
            coordinator.suspend(foreground: false, connected: false)
        }
    }
    func testReplacedCancelledPollCannotClearSnapshotOrStopPublisherWithinSameLease() async throws {
        let failures: [Error] = [CancellationError(), URLError(.networkConnectionLost), PersonalLocationShareFailure.server("POLICY_UNAVAILABLE")]
        for failure in failures {
            let service = PSService(scope: try PSFixture.scope()), provider = PSProvider()
            service.snapshotRefresh = 1; service.delayNextEvents = true // Test-only scheduling.
            let coordinator = await configured(service: service, journal: PSJournal(), provider: provider)
            await confirm(coordinator); await coordinator.refreshReceived()
            for _ in 0..<100 where service.suspendedEvents == nil { try await Task.sleep(nanoseconds: 1_000_000) }
            let suspended = try XCTUnwrap(service.suspendedEvents), revision = coordinator.authorizationGeneration
            await coordinator.refreshReceived() // Installs a new snapshot/poll and cancels the suspended old poll.
            let key = try XCTUnwrap(coordinator.publishingRequestKey), stops = provider.stops
            suspended.resume(throwing: failure); service.suspendedEvents = nil
            for _ in 0..<100 where !service.delayedEventsReturned { await Task.yield() }
            XCTAssertTrue(service.delayedEventsReturned)
            XCTAssertEqual(coordinator.authorizationGeneration, revision)
            XCTAssertEqual(coordinator.publishingRequestKey, key); XCTAssertEqual(provider.stops, stops)
            XCTAssertFalse(coordinator.visibleLocations.isEmpty)
            coordinator.suspend(foreground: false, connected: false)
        }
    }
    func testStopAStartBRetiresOldCancelledHTTPResponseAndTransportError() async throws {
        for kind in 0..<4 {
            let fake = PSService(scope: try PSFixture.scope()), provider = PSProvider()
            fake.revokeRequestHash = "opaque-server-test-hash"
            let coordinator = await configured(service: fake, journal: PSJournal(), provider: provider)
            await confirm(coordinator)
            let original = try XCTUnwrap(coordinator.publishingRequestKey)
            let transport = PSHTTPResponseTransport(); transport.delays = true; transport.status = kind == 1 ? 503 : 200
            transport.body = Data("{\"code\":503,\"errorCode\":\"POLICY_UNAVAILABLE\"}".utf8)
            if kind == 2 { transport.thrownError = CancellationError() }
            if kind == 3 { transport.thrownError = URLError(.networkConnectionLost) }
            let http = try approvedHTTP(transport, authorizationGeneration: { coordinator.authorizationGeneration },
                denied: { coordinator.authorizationRejected($0) })
            let old = Task { () -> PersonalLocationShareFailure? in
                do { _ = try await http.received(); return nil } catch { return error as? PersonalLocationShareFailure }
            }
            for _ in 0..<100 where transport.suspended == nil { await Task.yield() }
            let continuation = try XCTUnwrap(transport.suspended)
            await coordinator.stop(requestKey: original); await confirm(coordinator); await coordinator.refreshReceived()
            let replacement = try XCTUnwrap(coordinator.publishingRequestKey), stops = provider.stops
            XCTAssertNotEqual(replacement, original); XCTAssertFalse(coordinator.visibleLocations.isEmpty)
            old.cancel(); continuation.resume(); transport.suspended = nil
            let error = await old.value; XCTAssertEqual(error, .retiredResponse)
            XCTAssertEqual(coordinator.publishingRequestKey, replacement); XCTAssertEqual(provider.stops, stops)
            XCTAssertFalse(coordinator.visibleLocations.isEmpty); XCTAssertFalse(coordinator.authorizationBlocked)
            coordinator.suspend(foreground: false, connected: false)
        }
    }

}
