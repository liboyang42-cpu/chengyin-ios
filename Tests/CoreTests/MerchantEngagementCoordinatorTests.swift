import XCTest
@testable import QuestifyCore

@MainActor private final class EngagementSessionHolder {
    var value: MerchantBusinessSession? = try? .init(accountID:99001,epoch:1,token:"synthetic-token")
}
@MainActor private final class ContactRecorder: MerchantContactDelivering {
    var count = 0
    var value: String?
    func deliverSynthetic(phone: String, purpose: MerchantContactPurpose) async throws { count += 1; value = phone }
}
@MainActor final class MerchantEngagementCoordinatorTests: XCTestCase {
    private func setup(enabled: Bool = true) throws -> (EngagementRecordingTransport, EngagementSessionHolder, MerchantBusinessMemoryIntentStore, MerchantExportMemoryRecoveryStore, MerchantEngagementSessionReader, MerchantEngagementCoordinator) {
        let fake = EngagementRecordingTransport(), holder = EngagementSessionHolder(), journal = MerchantBusinessMemoryIntentStore(), recovery = MerchantExportMemoryRecoveryStore()
        let service = try MerchantEngagementService(configuration:.init(baseURL:URL(string:"https://example.com")!),readTransport:fake,testingActionTransport:enabled ? fake : nil)
        let reader = MerchantEngagementSessionReader(service:service,session:{ holder.value })
        return (fake,holder,journal,recovery,reader,MerchantEngagementCoordinator(reader:reader,journal:journal,exportRecovery:recovery))
    }
    private var save: MerchantEngagementCommand { .saveSegment(name:"Example segment",filter:.init()) }
    func testReviewFetchesAudienceAndFreezeCancelsWithoutMutation() async throws {
        let (fake,_,_,_,_,coordinator) = try setup()
        await coordinator.prepare(.createCampaign(try .init(segmentID:71001,channel:.inApp,couponID:nil,title:"Example",content:"Message")))
        XCTAssertEqual(coordinator.review?.proof.audience?.counts["deliverableCount"],4); coordinator.cancelReview()
        let requests = await fake.requests
        XCTAssertFalse(requests.contains { $0.url?.path == "/api/merchant/crm/campaigns" && $0.httpMethod == "POST" })
    }
    func testDefaultGateBlocksBeforePersistentIntentOrWrite() async throws {
        let (fake,_,journal,_,_,coordinator) = try setup(enabled:false)
        await coordinator.prepare(save); let frozen = try XCTUnwrap(coordinator.review); await coordinator.confirm(frozen)
        XCTAssertEqual(coordinator.failure,.disabled); XCTAssertTrue(try journal.intents().isEmpty)
        let requests = await fake.requests; XCTAssertTrue(requests.allSatisfy { $0.url?.path.hasSuffix("access/me") == true })
    }
    func testSuccessfulCampaignCreationNeverAutomaticallyDispatches() async throws {
        let (fake,_,_,_,_,coordinator) = try setup()
        await coordinator.prepare(.createCampaign(try .init(segmentID:71001,channel:.inApp,couponID:nil,title:"Example",content:"Message")))
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
        guard let receipt = coordinator.receipt, case .campaignCreated = receipt else { return XCTFail() }
        let requests = await fake.requests; XCTAssertFalse(requests.contains { $0.url?.path.hasSuffix("/dispatch") == true })
    }
    func testAudienceChangeBeforeConfirmationBlocksCampaignCreation() async throws {
        let (fake,_,journal,_,_,coordinator) = try setup()
        await coordinator.prepare(.createCampaign(try .init(segmentID:71001,channel:.inApp,couponID:nil,title:"Example",content:"Message")))
        let frozen = try XCTUnwrap(coordinator.review)
        await fake.setResponse("/api/merchant/crm/campaigns/preview",#"{"totalCount":8,"recipientLimit":200,"consentedCount":6,"frequencyLimitedCount":1,"deliverableCount":5}"#)
        await coordinator.confirm(frozen); XCTAssertEqual(coordinator.failure,.conflict); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testChangedStoreWithinSameSessionBlocksFrozenReview() async throws {
        let (fake,_,journal,_,_,coordinator) = try setup(); await coordinator.prepare(save); let frozen = try XCTUnwrap(coordinator.review)
        await fake.setAccess(MerchantEngagementSyntheticFixtures.access.replacingOccurrences(of:"\"id\":710",with:"\"id\":711"))
        await coordinator.confirm(frozen); XCTAssertEqual(coordinator.failure,.conflict); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testSessionEpochChangeBlocksReview() async throws {
        let (_,holder,_,_,_,coordinator) = try setup(); await coordinator.prepare(save); let frozen = try XCTUnwrap(coordinator.review)
        holder.value = try .init(accountID:99001,epoch:2,token:"synthetic-token")
        await coordinator.confirm(frozen); XCTAssertEqual(coordinator.failure,.stale)
    }
    func testUnknownMutationLockSurvivesCoordinatorRecreation() async throws {
        let (fake,_,journal,recovery,reader,coordinator) = try setup(); await coordinator.prepare(save); let frozen = try XCTUnwrap(coordinator.review)
        await fake.setUnknown("/api/merchant/crm/segments"); await coordinator.confirm(frozen)
        XCTAssertTrue(coordinator.locked); XCTAssertEqual(try journal.intents().count,1)
        let reopened = MerchantEngagementCoordinator(reader:reader,journal:journal,exportRecovery:recovery)
        await reopened.prepare(save); XCTAssertNil(reopened.review); XCTAssertEqual(reopened.failure,.pending)
    }
    func testDuplicateConfirmationCannotCreateSecondSegment() async throws {
        let (fake,_,_,_,_,coordinator) = try setup(); await coordinator.prepare(save); let frozen = try XCTUnwrap(coordinator.review)
        await coordinator.confirm(frozen); await coordinator.confirm(frozen)
        let requests = await fake.requests; XCTAssertEqual(requests.filter { $0.url?.path == "/api/merchant/crm/segments" && $0.httpMethod == "POST" }.count,1)
    }
    func testExportStatusProgressionKeepsCreationToken() async throws {
        let (_,_,_,_,_,coordinator) = try setup(); await coordinator.prepare(.createExport(.init())); await coordinator.confirm(try XCTUnwrap(coordinator.review))
        XCTAssertEqual(coordinator.exportTicket?.task.status,"PENDING")
        await coordinator.refreshExport(); XCTAssertEqual(coordinator.exportTicket?.task.status,"SUCCESS"); XCTAssertTrue(coordinator.exportTicket?.canDownload == true)
    }
    func testMalformedExportStatusPreservesLastFrameAndToken() async throws {
        let (fake,_,_,_,_,coordinator) = try setup(); await coordinator.prepare(.createExport(.init())); await coordinator.confirm(try XCTUnwrap(coordinator.review))
        await fake.setResponse("/api/merchant/crm/exports/74001/status",#"{"id":74001,"status":"SUCCESS"}"#)
        await coordinator.refreshExport(); XCTAssertEqual(coordinator.exportTicket?.task.status,"PENDING"); XCTAssertEqual(coordinator.failure,.malformed)
    }
    func testExportRecoveryNeverPersistsCredential() async throws {
        let (_,_,journal,recovery,reader,coordinator) = try setup(); await coordinator.prepare(.createExport(.init())); await coordinator.confirm(try XCTUnwrap(coordinator.review))
        let records = try recovery.read(); let raw = String(decoding:try JSONEncoder().encode(records),as:UTF8.self)
        XCTAssertFalse(raw.contains("downloadToken")); XCTAssertFalse(raw.contains("synthetic-download-token"))
        let reopened = MerchantEngagementCoordinator(reader:reader,journal:journal,exportRecovery:recovery); await reopened.refreshExport()
        XCTAssertEqual(reopened.exportTicket?.task.status,"SUCCESS"); XCTAssertFalse(reopened.exportTicket?.canDownload == true)
    }
    func testRunningExportPreventsDuplicateCreation() async throws {
        let (fake,_,_,_,_,coordinator) = try setup(); await coordinator.prepare(.createExport(.init())); await coordinator.confirm(try XCTUnwrap(coordinator.review))
        await fake.setResponse("/api/merchant/crm/exports/74001/status",#"{"id":74001,"status":"RUNNING"}"#)
        await coordinator.prepare(.createExport(.init())); XCTAssertNil(coordinator.review); XCTAssertEqual(coordinator.failure,.pending)
    }
    func testContactIsConsumedOnceAndNotReusedForSecondAction() async throws {
        let (_,_,_,_,_,coordinator) = try setup(); await coordinator.prepare(.contact(try .init(61001),.copy)); await coordinator.confirm(try XCTUnwrap(coordinator.review))
        let recorder = ContactRecorder(); try await coordinator.consumeContact(using:recorder)
        XCTAssertEqual(recorder.count,1); XCTAssertNil(coordinator.receipt)
        do { try await coordinator.consumeContact(using:recorder); XCTFail() } catch { XCTAssertEqual(error as? MerchantBusinessFailure,.disabled) }
    }
    func testContactSessionSwitchPreventsDeviceDisclosure() async throws {
        let (_,holder,_,_,_,coordinator) = try setup(); await coordinator.prepare(.contact(try .init(61001),.copy)); await coordinator.confirm(try XCTUnwrap(coordinator.review))
        holder.value = nil; let recorder = ContactRecorder()
        do { try await coordinator.consumeContact(using:recorder); XCTFail() } catch { XCTAssertEqual(recorder.count,0) }
    }
    func testInactiveAccountCanReviewInvitationWithoutInventingStore() async throws {
        let (fake,_,_,_,_,coordinator) = try setup(); await fake.setAccess(#"{"active":false,"permissions":[]}"#)
        await coordinator.prepare(.acceptInvitation(try .init(token:"synthetic-invitation-token")))
        XCTAssertNotNil(coordinator.review); XCTAssertNil(coordinator.review?.proof.access.merchantID)
    }
    func testExportFileRecoveryRejectsCorruption() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }; try Data("bad-json".utf8).write(to:url)
        XCTAssertThrowsError(try MerchantExportFileRecoveryStore(url:url).read())
    }
}
@MainActor private final class PendingEvidencePicker: MerchantEvidenceSelecting {
    var continuation: CheckedContinuation<MerchantEvidenceSelection?,Error>?
    private var started: CheckedContinuation<Void,Never>?
    func waitUntilStarted() async { if continuation != nil { return }; await withCheckedContinuation { started = $0 } }
    func choose() async throws -> MerchantEvidenceSelection? {
        try await withCheckedThrowingContinuation { continuation = $0; started?.resume(); started = nil }
    }
}
@MainActor final class MerchantEvidenceSelectionTests: XCTestCase {
    func testClearingSelectionDiscardsLateProviderCompletion() async throws {
        let picker = PendingEvidencePicker(), coordinator = MerchantEvidenceSelectionCoordinator()
        let task = Task { try await coordinator.select(using:picker) }; await picker.waitUntilStarted()
        coordinator.clear()
        let selection = try MerchantEvidenceSelection.importing(Data([137,80,78,71,13,10,26,10,0]))
        picker.continuation?.resume(returning:selection); try await task.value
        XCTAssertNil(coordinator.selected); XCTAssertFalse(coordinator.isSelecting)
    }
    func testCancelledPickerDoesNotProduceEvidenceKey() async throws {
        let picker = PendingEvidencePicker(), coordinator = MerchantEvidenceSelectionCoordinator()
        let task = Task { try await coordinator.select(using:picker) }; await picker.waitUntilStarted(); picker.continuation?.resume(returning:nil); try await task.value
        XCTAssertNil(coordinator.selected)
    }
    func testInviteContinuationRequiresNewExplicitReviewAndCanBeCleared() throws {
        let route = try MerchantOperatorInviteRoute(path:"/merchant/team",queryItems:[.init(name:"invite",value:"synthetic-invitation-token")])
        let continuation = MerchantOperatorInviteContinuation(route:route)
        XCTAssertNoThrow(try continuation.commandForExplicitReview()); continuation.cancelOrConsume()
        XCTAssertThrowsError(try continuation.commandForExplicitReview())
    }
}
