import XCTest
@testable import QuestifyCore

final class ProjectEditTests: XCTestCase {
    private func session(_ account: Int = 901, epoch: UInt64 = 1, scope: String = "fixture-cn") throws -> ProjectEditSession { try .init(accountID: account, epoch: epoch, storageNamespace: scope) }
    func testMissingAndFreePriceAreDifferent() {
        var d = ProjectEditSyntheticFixtures.draft(); d.tickets[0].price = ""
        XCTAssertTrue(ProjectEditValidation.issues(d).contains { $0.key == "projectEdit.validation.price" })
        d.tickets[0].price = "0"; XCTAssertTrue(ProjectEditValidation.issues(d).isEmpty)
        d.tickets[0].price = "-1"; XCTAssertFalse(ProjectEditValidation.issues(d).isEmpty)
        d.tickets[0].price = "NaN"; XCTAssertFalse(ProjectEditValidation.issues(d).isEmpty)
    }
    func testCityRequiresRealStoryBeforeAddingNode() throws {
        var c = ProjectEditChapter()
        for value in ["", " ", "暂无描述", "暂无", "无"] { c.description = value; XCTAssertThrowsError(try c.addNode(product: .city)) }
        c.description = "A real beginning"; try c.addNode(product: .city); XCTAssertEqual(c.nodes.count, 1)
        c.description = ""; try c.addNode(product: .freeExplore); XCTAssertEqual(c.nodes.count, 2)
    }
    func testCoordinateBoundsAndZeroSentinel() {
        var n = ProjectEditNode()
        for pair in [("0", "1"), ("1", "0"), ("181", "10"), ("1", "91"), ("nan", "2"), ("inf", "2")] {
            n.longitude = pair.0; n.latitude = pair.1; XCTAssertFalse(n.hasUsableCoordinates)
        }
        n.longitude = "-73.8"; n.latitude = "40.5"; XCTAssertTrue(n.hasUsableCoordinates)
    }
    func testStrictDatesDoNotUseDeviceZoneOrAppendTwice() {
        XCTAssertEqual(ProjectEditValidation.dateTime("2030-05-01", endOfDay: true), "2030-05-01 23:59:59")
        XCTAssertEqual(ProjectEditValidation.dateTime("2030-05-01T10:15"), "2030-05-01 10:15:00")
        XCTAssertEqual(ProjectEditValidation.dateTime("2030-05-01 10:15:12", endOfDay: true), "2030-05-01 10:15:12")
        XCTAssertNil(ProjectEditValidation.dateTime("2030-02-30")); XCTAssertNil(ProjectEditValidation.dateTime("2030-05-01T10:15Z"))
    }
    func testCityTicketOrderingAndMeetingPoint() {
        var d = ProjectEditSyntheticFixtures.draft(); d.tickets[0].endTime = d.tickets[0].startTime; d.tickets[0].meetingPoint = ""
        let keys = ProjectEditValidation.issues(d).map(\.key)
        XCTAssertTrue(keys.contains("projectEdit.validation.dateOrder")); XCTAssertTrue(keys.contains("projectEdit.validation.meeting"))
    }
    func testFreeExploreAlwaysRequiresRecruitDeadline() {
        var d = ProjectEditSyntheticFixtures.draft(product: .freeExplore); d.recruitDeadline = ""; d.openMerchantPool = false
        XCTAssertTrue(ProjectEditValidation.issues(d).contains { $0.key == "projectEdit.validation.deadline" })
    }
    func testFullPayloadSourceNormalizationAndOwnerScope() throws {
        var d = ProjectEditSyntheticFixtures.draft(); d.owner = .merchant; d.openMerchantPool = true; d.categoryIDs = [7, 9]
        let p = try ProjectEditContract.payload(d, topicID: nil, scope: .full)
        XCTAssertEqual(p["categoryIds"], .string("7,9")); XCTAssertEqual(p["scope"], .string("MERCHANT"))
        XCTAssertEqual(p["openClubPool"], .number(0)); XCTAssertEqual(p["publishToCreative"], .number(1))
        XCTAssertNil(p["recruitDeadline"])
        XCTAssertEqual(p["tickets"]?.array?.first?.object?["mode"], .number(1))
        XCTAssertEqual(try ProjectEditContract.payload(d, topicID: 1, scope: .full)["publishToCreative"], .number(0))
    }
    func testWhitelistHasOnlySourceFieldsAndID() throws {
        let p = try ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: 71, scope: .whitelist)
        XCTAssertEqual(Set(p.keys), Set(ProjectEditContract.whitelist + ["id"]))
        XCTAssertNil(p["chapters"]); XCTAssertNil(p["tickets"]); XCTAssertNil(p["startDate"])
    }
    func testReplacementCarryOverRetainsContractualChapterFields() throws {
        var d = ProjectEditSyntheticFixtures.draft()
        let values: [String: ProjectEditJSON] = ["categoryId": .number(9), "maxMerchant": .number(2), "perkMinValue": .string("001.20"), "allowedValidationMethods": .string("1,4"), "maxNodeXp": .number(99), "calculatedDistance": .number(Decimal(string: "1.25")!), "imgArr": .string("a,b"), "audioUrl": .string("preserved")]
        d.chapters[0].preserved.merge(values) { _, new in new }
        let p = try ProjectEditContract.payload(d, topicID: 71, scope: .full)["chapters"]?.array?.first?.object
        for (key, value) in values { XCTAssertEqual(p?[key], value) }
    }
    func testStoryBlocksProjectNodeOrderAndSkipEmptyAudio() throws {
        var d = ProjectEditSyntheticFixtures.draft(); var second = d.chapters[0].nodes[0]; second.id = "second"; second.name = "Second"
        let first = d.chapters[0].nodes[0]; d.chapters[0].nodes.append(second)
        d.chapters[0].blocks = [.init(kind: .text, content: "Opening"), .init(kind: .node, nodeID: second.id), .init(kind: .text, content: "Later"), .init(kind: .node, nodeID: first.id), .init(kind: .audio)]
        let c = try XCTUnwrap(ProjectEditContract.payload(d, topicID: nil, scope: .full)["chapters"]?.array?.first?.object)
        XCTAssertEqual(c["description"], .string("Opening")); XCTAssertEqual(c["nodes"]?.array?.first?.object?["name"], .string("Second"))
        XCTAssertEqual(c["blocks"]?.array?.count, 4)
    }
    func testBrokenOrDuplicateReferencesFailClosedRatherThanDiscardStory() {
        var d = ProjectEditSyntheticFixtures.draft()
        d.chapters[0].blocks = [.init(kind: .text, content: "Opening"), .init(kind: .node, nodeID: "missing")]
        XCTAssertThrowsError(try ProjectEditContract.payload(d, topicID: nil, scope: .full))
        let id = d.chapters[0].nodes[0].id
        d.chapters[0].blocks = [.init(kind: .text, content: "Opening"), .init(kind: .node, nodeID: id), .init(kind: .node, nodeID: id)]
        XCTAssertThrowsError(try ProjectEditContract.payload(d, topicID: nil, scope: .full))
    }
    func testRemovingNodeAlsoRemovesItsStoryReference() {
        var c = ProjectEditSyntheticFixtures.draft().chapters[0]; let id = c.nodes[0].id
        c.blocks = [.init(kind: .text, content: "Opening"), .init(kind: .node, nodeID: id)]
        c.removeNode(id: id); XCTAssertTrue(c.nodes.isEmpty); XCTAssertEqual(c.blocks?.count, 1)
    }
    @MainActor func testLocalDraftRoundTripAndRevisionConflict() throws {
        let storage = ProjectEditMemoryStorage(); let store = ProjectEditLocalStore(storage: storage); let s = try session(); let id = try ProjectEditDraftIdentity(topicID: 71)
        var d = ProjectEditSyntheticFixtures.draft(); d.baseRevision = "one"
        try store.save(d, session: s, identity: id)
        guard case .ready(let envelope) = store.load(session: s, identity: id, baseline: d) else { return XCTFail("Expected restore") }
        XCTAssertEqual(envelope.draft, d)
        d.baseRevision = "two"
        guard case .revisionConflict = store.load(session: s, identity: id, baseline: d) else { return XCTFail("Expected revision conflict") }
    }
    @MainActor func testEnvelopeOwnerAndNamespaceAreCheckedBeyondBucketKey() throws {
        let storage = ProjectEditMemoryStorage(); let store = ProjectEditLocalStore(storage: storage); let s = try session(); let id = try ProjectEditDraftIdentity(topicID: 71)
        let d = ProjectEditSyntheticFixtures.draft(); try store.save(d, session: s, identity: id)
        let key = try XCTUnwrap(storage.data.keys.first)
        storage.data[key] = try JSONEncoder().encode(ProjectEditEnvelope(session: session(902), identity: id, draft: d))
        guard case .memberMismatch = store.load(session: s, identity: id, baseline: d) else { return XCTFail("Leaked another account") }
    }
    @MainActor func testActiveDraftPointersSeparateMarketsProductsAndOwnerScopes() throws {
        let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()); let s = try session(); let id = try ProjectEditDraftIdentity()
        try store.save(ProjectEditSyntheticFixtures.draft(), session: s, identity: id)
        XCTAssertEqual(try store.activeIdentity(session: s, product: .city, owner: .personal), id)
        XCTAssertNil(try store.activeIdentity(session: session(scope: "fixture-us"), product: .city, owner: .personal))
        XCTAssertNil(try store.activeIdentity(session: s, product: .freeExplore, owner: .personal))
        XCTAssertNil(try store.activeIdentity(session: s, product: .city, owner: .merchant))
    }
    @MainActor func testDisabledServiceAllowsLocalReviewButNoSubmit() async throws {
        let d = ProjectEditSyntheticFixtures.draft(); let s = try session()
        let c = ProjectEditCoordinator(initial: .init(draft: d), service: ProjectEditDisabledService(), store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); c.prepare(d); let review = try XCTUnwrap(c.confirmation); await c.confirm(review)
        XCTAssertFalse(c.canSimulate); XCTAssertEqual(c.messageKey, "projectEdit.unconfigured"); XCTAssertNil(c.pending)
    }
    @MainActor func testConfirmationFreezesPayloadAndCannotBeRepeated() async throws {
        let service = ProjectEditSyntheticService(); let s = try session(); var d = ProjectEditSyntheticFixtures.draft()
        let c = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); c.prepare(d); let review = try XCTUnwrap(c.confirmation); d.name = "Later edit"
        await c.confirm(review); await c.confirm(review)
        XCTAssertEqual(service.submissions.count, 1); XCTAssertNotEqual(service.submissions[0].payload["name"], .string(d.name)); XCTAssertEqual(c.state, .simulated)
        c.prepare(d); XCTAssertNil(c.confirmation)
    }
    @MainActor func testCancelledReviewNeverSubmits() async throws {
        let service = ProjectEditSyntheticService(); let s = try session(); let d = ProjectEditSyntheticFixtures.draft()
        let c = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); c.prepare(d); let review = try XCTUnwrap(c.confirmation); c.cancelReview(); await c.confirm(review)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    @MainActor func testChangedSessionInvalidatesOldConfirmation() async throws {
        let service = ProjectEditSyntheticService(); var s: ProjectEditSession? = try session(); let d = ProjectEditSyntheticFixtures.draft()
        let c = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); c.prepare(d); let review = try XCTUnwrap(c.confirmation); s = try session(epoch: 2); await c.confirm(review)
        XCTAssertTrue(service.submissions.isEmpty); XCTAssertNil(c.snapshot)
    }
    @MainActor func testSessionChangeDuringPreflightNeverSubmits() async throws {
        let service = ProjectEditSyntheticService(); var s: ProjectEditSession? = try session(); let d = ProjectEditSyntheticFixtures.draft()
        let c = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); c.prepare(d); let review = try XCTUnwrap(c.confirmation)
        service.beforePreflight = { s = nil }; await c.confirm(review); XCTAssertTrue(service.submissions.isEmpty)
    }
    @MainActor func testUnknownOutcomeSurvivesNewCoordinatorAndReauthentication() async throws {
        let service = ProjectEditSyntheticService(scenario: .unknown); let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()); var s: ProjectEditSession? = try session(); let d = ProjectEditSyntheticFixtures.draft()
        func make() -> ProjectEditCoordinator { .init(initial: .init(draft: d), service: service, store: store, currentSession: { s }) }
        let c = make(); await c.load(); c.saveLocal(d); c.prepare(d); await c.confirm(try XCTUnwrap(c.confirmation))
        XCTAssertTrue(c.isLocked); c.leaveScreen(); s = try session(epoch: 2)
        let reopened = make(); await reopened.load(); XCTAssertTrue(reopened.isLocked)
        await reopened.checkOutcome(); XCTAssertTrue(reopened.isLocked); reopened.prepare(d); XCTAssertNil(reopened.confirmation)
        XCTAssertEqual(service.submissions.count, 1)
    }
    @MainActor func testPersistenceFailurePreventsEvenSyntheticSubmit() async throws {
        let storage = ProjectEditMemoryStorage(); let service = ProjectEditSyntheticService(); let s = try session(); let d = ProjectEditSyntheticFixtures.draft()
        let c = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: .init(storage: storage), currentSession: { s })
        await c.load(); c.prepare(d); storage.failWrites = true; await c.confirm(try XCTUnwrap(c.confirmation))
        XCTAssertTrue(service.submissions.isEmpty); XCTAssertEqual(c.state, .blocked)
    }
    @MainActor func testRevisionChangeAfterReviewRequiresReload() async throws {
        let service = ProjectEditSyntheticService(); let s = try session()
        let c = ProjectEditCoordinator(initial: service.snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); c.prepare(try XCTUnwrap(c.snapshot?.draft)); let review = try XCTUnwrap(c.confirmation)
        service.snapshot.draft.baseRevision = "newer"; await c.confirm(review)
        XCTAssertTrue(service.submissions.isEmpty); XCTAssertEqual(c.messageKey, "projectEdit.revisionConflict")
    }
    @MainActor func testWhitelistCannotSneakInStructuralChangeThroughRestoreOrPrepare() async throws {
        let snapshot = ProjectEditSyntheticFixtures.snapshot(scope: .whitelist); let service = ProjectEditSyntheticService(snapshot: snapshot); let s = try session()
        let c = ProjectEditCoordinator(initial: snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); var d = snapshot.draft; d.tickets[0].price = "5"; c.prepare(d)
        XCTAssertNil(c.confirmation); XCTAssertEqual(c.messageKey, "projectEdit.lockedFields")
    }
    @MainActor func testQuotaZeroBlocksButNilIsUnlimited() async throws {
        let service = ProjectEditSyntheticService(); let s = try session(); let d = ProjectEditSyntheticFixtures.draft()
        let c = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); c.prepare(d); service.capability = .init(canProPublish: true, remaining: 0)
        await c.confirm(try XCTUnwrap(c.confirmation)); XCTAssertTrue(service.submissions.isEmpty)
        XCTAssertTrue(ProjectEditCapability(canProPublish: true, remaining: nil).allowsCreate)
    }
    @MainActor func testDefinitiveRejectionClearsLockButNeverClaimsSuccess() async throws {
        let service = ProjectEditSyntheticService(scenario: .rejected); let s = try session(); let d = ProjectEditSyntheticFixtures.draft()
        let c = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await c.load(); c.prepare(d); await c.confirm(try XCTUnwrap(c.confirmation))
        XCTAssertFalse(c.isLocked); XCTAssertEqual(c.state, .rejected)
    }
    func testEditDetailNormalizesSourceFieldsAndNodeReferences() throws {
        let data = Data(#"{"code":200,"data":{"editScope":"FULL","topic":{"id":71,"productType":1,"name":"Route","description":"Description","categoryIds":"7,9","updateTime":"r1","merchantStatus":1},"chapters":[{"id":11,"name":"One","description":"Opening","atmospherePreset":"NIGHT","allowedValidationMethods":"1,4","maxNodeXp":12,"cmsTopicNodeList":[{"id":22,"name":"Stop","longitude":"121","latitude":"31"}],"blocks":[{"type":"text","content":"Opening"},{"type":"node","nodeId":22}]}],"tickets":[{"name":"Free","price":0,"totalInventory":15}]}}"#.utf8)
        let value = try ProjectEditContract.decodeEditDetail(data, expectedTopicID: 71, owner: .merchant)
        XCTAssertEqual(value.scope, .full); XCTAssertEqual(value.draft.owner, .merchant); XCTAssertFalse(value.draft.publishToCreative)
        XCTAssertEqual(value.draft.categoryIDs, [7, 9]); XCTAssertTrue(value.draft.openMerchantPool)
        XCTAssertEqual(value.draft.chapters[0].preserved["atmospherePreset"], .string("BLUE"))
        XCTAssertEqual(value.draft.chapters[0].blocks?[1].nodeID, value.draft.chapters[0].nodes[0].id)
        XCTAssertEqual(value.draft.tickets[0].price, "0"); XCTAssertEqual(value.draft.tickets[0].totalStock, "15")
    }
    func testUnknownEditScopeAndWrongTopicAreRejected() {
        let data = Data(#"{"code":200,"data":{"editScope":"NEW_SCOPE","topic":{"id":71,"productType":1,"updateTime":"r1"},"chapters":[],"tickets":[]}}"#.utf8)
        XCTAssertThrowsError(try ProjectEditContract.decodeEditDetail(data, expectedTopicID: 71, owner: .personal))
        let validScope = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "NEW_SCOPE", with: "FULL").utf8)
        XCTAssertThrowsError(try ProjectEditContract.decodeEditDetail(validScope, expectedTopicID: 72, owner: .personal))
    }
    func testIndependentEditDetailDecodesHaveEqualStableTicketIdentities() throws {
        let data = projectTicketIdentityFixture()
        let first = try ProjectEditContract.decodeEditDetail(data, expectedTopicID: 71, owner: .personal)
        let second = try ProjectEditContract.decodeEditDetail(data, expectedTopicID: 71, owner: .personal)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.draft.tickets.map(\.id), ["topic-71-ticket-index-0", "topic-71-ticket-index-1"])
        // Identical content does not collapse two source rows into one editor binding.
        XCTAssertEqual(first.draft.tickets[0].name, first.draft.tickets[1].name)
        XCTAssertNotEqual(first.draft.tickets[0].id, first.draft.tickets[1].id)
    }
    func testDecodedTicketIdentityIsTopicScopedAndAbsentFromWirePayload() throws {
        let first = try ProjectEditContract.decodeEditDetail(projectTicketIdentityFixture(), expectedTopicID: 71, owner: .personal)
        let otherData = Data(String(decoding: projectTicketIdentityFixture(), as: UTF8.self)
            .replacingOccurrences(of: "\"id\":71", with: "\"id\":72").utf8)
        let other = try ProjectEditContract.decodeEditDetail(otherData, expectedTopicID: 72, owner: .personal)
        XCTAssertNotEqual(first.draft.tickets[0].id, other.draft.tickets[0].id)
        let payload = try ProjectEditContract.payload(first.draft, topicID: 71, scope: .full)
        for ticket in try XCTUnwrap(payload["tickets"]?.array) {
            XCTAssertNil(ticket.object?["id"])
            XCTAssertFalse(String(describing: ticket).contains("ticket-index"))
        }
    }
    @MainActor func testUnchangedFreshlyDecodedPreflightAllowsReviewedEdit() async throws {
        let service = ProjectTicketDecodingService(data: projectTicketIdentityFixture())
        let initial = try ProjectEditContract.decodeEditDetail(service.data, expectedTopicID: 71, owner: .personal)
        let s = try session()
        let coordinator = ProjectEditCoordinator(initial: initial, service: service,
            store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await coordinator.load()
        var draft = try XCTUnwrap(coordinator.snapshot?.draft); draft.name = "Reviewed route rename"
        coordinator.prepare(draft)
        let review = try XCTUnwrap(coordinator.confirmation)
        await coordinator.confirm(review)
        XCTAssertEqual(service.preflightCount, 2)
        XCTAssertEqual(service.submissions.count, 1)
        XCTAssertEqual(service.submissions.first?.payload["name"], .string("Reviewed route rename"))
        XCTAssertEqual(coordinator.state, .simulated)
    }
    @MainActor func testFreshTicketChangeStillRejectsReviewedEditWithSameRevision() async throws {
        let service = ProjectTicketDecodingService(data: projectTicketIdentityFixture())
        let initial = try ProjectEditContract.decodeEditDetail(service.data, expectedTopicID: 71, owner: .personal)
        let s = try session()
        let coordinator = ProjectEditCoordinator(initial: initial, service: service,
            store: .init(storage: ProjectEditMemoryStorage()), currentSession: { s })
        await coordinator.load()
        var draft = try XCTUnwrap(coordinator.snapshot?.draft); draft.name = "Reviewed route rename"
        coordinator.prepare(draft)
        let review = try XCTUnwrap(coordinator.confirmation)
        service.data = Data(String(decoding: service.data, as: UTF8.self).replacingOccurrences(of: "\"price\":0", with: "\"price\":3").utf8)
        await coordinator.confirm(review)
        XCTAssertEqual(service.preflightCount, 2)
        XCTAssertTrue(service.submissions.isEmpty)
        XCTAssertEqual(coordinator.state, .blocked)
        XCTAssertEqual(coordinator.messageKey, "projectEdit.revisionConflict")
    }
    @MainActor func testGuestCanReviewInMemoryButCannotPersistOrSubmit() async throws {
        let storage = ProjectEditMemoryStorage(); let service = ProjectEditSyntheticService()
        let c = ProjectEditCoordinator(initial: .init(draft: .init()), service: service, store: .init(storage: storage), currentSession: { nil })
        await c.load(); let d = ProjectEditSyntheticFixtures.draft(); c.saveLocal(d); c.prepare(d)
        await c.confirm(try XCTUnwrap(c.confirmation))
        XCTAssertTrue(storage.data.isEmpty); XCTAssertTrue(service.submissions.isEmpty); XCTAssertNil(c.identity)
    }
    @MainActor func testIntentDiscoverableAcrossReopenWithoutUIAutosave() async throws {
        let service = ProjectEditSyntheticService(scenario: .unknown); let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()); let s = try session(); let d = ProjectEditSyntheticFixtures.draft()
        let first = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: store, currentSession: { s })
        await first.load(); first.prepare(d); await first.confirm(try XCTUnwrap(first.confirmation))
        let second = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: store, currentSession: { s })
        await second.load(); XCTAssertTrue(second.isLocked); XCTAssertEqual(first.identity, second.identity)
    }
    @MainActor func testCompletedReceiptPreventsSameDraftReplayAfterReopen() async throws {
        let service = ProjectEditSyntheticService(); let store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()); let s = try session(); let d = ProjectEditSyntheticFixtures.draft()
        let first = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: store, currentSession: { s })
        await first.load(); first.prepare(d); await first.confirm(try XCTUnwrap(first.confirmation))
        let second = ProjectEditCoordinator(initial: .init(draft: d), service: service, store: store, currentSession: { s })
        await second.load(); second.prepare(d); XCTAssertEqual(second.state, .simulated); XCTAssertNil(second.confirmation)
        XCTAssertEqual(service.submissions.count, 1)
    }

}

private func projectTicketIdentityFixture() -> Data {
    Data(#"{"code":200,"data":{"editScope":"FULL","topic":{"id":71,"productType":1,"name":"Route","description":"Description","imgUrl":"fixture://cover","categoryIds":"7","updateTime":"r1","startDate":"2030-05-01","endDate":"2030-05-30"},"chapters":[{"id":11,"name":"Opening","description":"An actual fixture story","cmsTopicNodeList":[{"id":22,"name":"Stop","longitude":"121","latitude":"31"}]}],"tickets":[{"name":"Same source title","price":0,"totalInventory":15,"startTime":"2030-05-02 10:00","endTime":"2030-05-02 12:00","meetingPoint":"Fixture meeting place"},{"name":"Same source title","price":0,"totalInventory":15,"startTime":"2030-05-02 10:00","endTime":"2030-05-02 12:00","meetingPoint":"Fixture meeting place"}]}}"#.utf8)
}

/// Decodes fresh bytes on every preflight, rather than returning one retained snapshot.
@MainActor private final class ProjectTicketDecodingService: ProjectEditServing {
    var data: Data
    var authority: ProjectEditServiceAuthority { .synthetic }
    private(set) var preflightCount = 0
    private(set) var submissions: [ProjectEditPending] = []
    init(data: Data) { self.data = data }
    func preflight(topicID: Int?, session: ProjectEditSession) async throws -> ProjectEditPreflight {
        preflightCount += 1
        let snapshot = try ProjectEditContract.decodeEditDetail(data, expectedTopicID: 71, owner: .personal)
        return .init(capability: .init(canProPublish: true, remaining: nil), snapshot: snapshot)
    }
    func submit(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome {
        submissions.append(operation)
        return .simulatedReceipt(operationID: operation.operationID, topicID: 71)
    }
    func terminalReceipt(operationID: UUID, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? { nil }
}
