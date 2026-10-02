import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ProjectEditStoryContractTests: XCTestCase {
    private func payload(_ draft: ProjectEditDraft = ProjectEditSyntheticFixtures.draft(), id: Int? = nil) throws -> [String: ProjectEditJSON] {
        try ProjectEditContract.payload(draft, topicID: id, scope: .full)
    }
    private func changeChapter(_ payload: [String: ProjectEditJSON], _ change: (inout [String: ProjectEditJSON]) -> Void) throws -> [String: ProjectEditJSON] {
        var payload = payload, chapters = try XCTUnwrap(payload["chapters"]?.array), chapter = try XCTUnwrap(chapters[0].object)
        change(&chapter); chapters[0] = .object(chapter); payload["chapters"] = .array(chapters); return payload
    }
    func testConditionalRoutesKeepPlainLegacyAndStoryV2Separate() throws {
        let city = try payload()
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: city, baseline: nil), "api/topic/v2/create")
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload(id: 71), baseline: nil), "api/topic/v2/update")
        var free = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload(free), baseline: nil), "api/topic/create")
        free.preserved["publishMode"] = .string("simple")
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload(free, id: 71), baseline: nil), "api/topic/update")
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: ["publishMode": .string("ai_simple"), "productType": .number(1)], baseline: nil), "api/topic/create")
    }
    func testLegacyBlocksCannotBeDispatchedOrSilentlyFlattened() throws {
        var free = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        free.chapters[0].blocks = [.init(kind: .text, content: "Keep this")]
        XCTAssertThrowsError(try payload(free))
        XCTAssertThrowsError(try ProjectEditStoryContract.path(payload: ["publishMode": .string("simple"), "chapters": .array([.object(["blocks": .array([])])])], baseline: nil))
    }
    func testCityMaterializesDescriptionAndEveryNodeWithStableKeys() throws {
        let draft = ProjectEditSyntheticFixtures.draft(), a = try payload(draft), b = try payload(draft)
        XCTAssertEqual(a, b)
        let chapter = try XCTUnwrap(a["chapters"]?.array?.first?.object), blocks = try XCTUnwrap(chapter["blocks"]?.array)
        XCTAssertEqual(chapter["schemaVersion"], .number(1)); XCTAssertEqual(chapter["required"], .number(1))
        XCTAssertEqual(blocks.count, 2); XCTAssertEqual(blocks[0].object?["key"], .string("legacy-text"))
        XCTAssertEqual(blocks[1].object?["nodeIndex"], .number(0))
        XCTAssertNoThrow(try ProjectEditStoryContract.validatePayload(a))
    }
    func testFreeExploreOpeningAndEndingUseV2WithNoPlaceRequirement() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        var opening = ProjectEditChapter(); opening.description = "Opening"; opening.preserved["opening"] = .bool(true)
        var ending = ProjectEditChapter(); ending.description = "Finish"; ending.preserved["ending"] = .object(["fallback": .bool(true)])
        draft.chapters.insert(opening, at: 0); draft.chapters.append(ending)
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload(draft), baseline: nil), "api/topic/v2/create")
        draft.chapters.swapAt(0, 1); XCTAssertThrowsError(try payload(draft))
    }
    func testOpeningStoryGameNeedsTemplateAndNoCoordinates() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        let id = draft.chapters[0].nodes[0].id
        var block = ProjectEditBlock(kind: .node, nodeID: id); block.sourceFields = ["locationRequired": .bool(false)]
        draft.chapters[0].blocks = [.init(kind: .text, content: "Opening"), block]
        draft.chapters[0].preserved["opening"] = .bool(true)
        draft.chapters[0].nodes[0].longitude = ""; draft.chapters[0].nodes[0].latitude = ""
        XCTAssertNoThrow(try payload(draft))
        draft.chapters[0].nodes[0].templateID = nil; XCTAssertThrowsError(try payload(draft))
        draft.chapters[0].nodes[0].templateID = 41; draft.chapters[0].nodes[0].longitude = "121"
        XCTAssertThrowsError(try payload(draft))
    }
    func testExactlyOneFallbackAndEndingRestrictions() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        var ending = ProjectEditChapter(); ending.description = "Finish"; ending.preserved["ending"] = .object(["fallback": .bool(true)])
        draft.chapters.append(ending); XCTAssertNoThrow(try payload(draft))
        draft.chapters.append(ending); XCTAssertThrowsError(try payload(draft))
        draft.chapters.removeLast(); draft.chapters[1].preserved["recruitEnabled"] = .number(1)
        XCTAssertThrowsError(try payload(draft))
    }
    func testSchemaRequiredCountAndLimitsFailClosed() throws {
        let base = try payload()
        for (key, value) in [("schemaVersion", ProjectEditJSON.number(2)), ("required", .number(0)), ("blocks", .null)] {
            XCTAssertThrowsError(try ProjectEditStoryContract.validatePayload(changeChapter(base) { $0[key] = value }))
        }
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].schemaVersion = 2; XCTAssertThrowsError(try payload(draft))
        draft.chapters[0].schemaVersion = 1; draft.chapters[0].required = 0; XCTAssertThrowsError(try payload(draft))
        draft.chapters[0].required = 1; draft.chapters[0].description = String(repeating: "x", count: 5001)
        XCTAssertThrowsError(try payload(draft))
        draft.chapters[0].description = "Story"; draft.chapters[0].blocks = (0..<200).map { _ in .init(kind: .text, content: "x") }
        // Materializing the existing node would become the 201st block.
        XCTAssertThrowsError(try payload(draft))
    }
    func testWireReferenceCompletenessBoundsDuplicatesAndKeyUniqueness() throws {
        let base = try payload()
        for invalid in [ProjectEditJSON.number(-1), .number(1), .number(Decimal(string: "0.5")!)] {
            let changed = try changeChapter(base) { c in
                var blocks = c["blocks"]!.array!, row = blocks[1].object!; row["nodeIndex"] = invalid; blocks[1] = .object(row); c["blocks"] = .array(blocks)
            }
            XCTAssertThrowsError(try ProjectEditStoryContract.validatePayload(changed))
        }
        XCTAssertThrowsError(try ProjectEditStoryContract.validatePayload(changeChapter(base) { c in c["blocks"] = .array([c["blocks"]!.array![0]]) }))
        XCTAssertThrowsError(try ProjectEditStoryContract.validatePayload(changeChapter(base) { c in
            var blocks = c["blocks"]!.array!; blocks.append(blocks[1]); c["blocks"] = .array(blocks)
        }))
    }
    func testConditionalTextIsPreservedAndExcludedFromProjection() throws {
        var draft = ProjectEditSyntheticFixtures.draft(), conditional = ProjectEditBlock(kind: .text, content: "Secret")
        conditional.sourceFields = ["who": .string("Narrator"), "level": .number(2), "when": .object(["op": .string("HAS_TAG"), "value": .string("tag.clue")])]
        draft.chapters[0].blocks = [.init(kind: .text, content: "Public"), conditional, .init(kind: .node, nodeID: draft.chapters[0].nodes[0].id)]
        let chapter = try XCTUnwrap(payload(draft)["chapters"]?.array?.first?.object)
        XCTAssertEqual(chapter["description"], .string("Public")); XCTAssertEqual(chapter["blocks"]?.array?[1].object?["when"], conditional.sourceFields?["when"])
        draft.chapters[0].blocks?[1].sourceFields?["when"] = .object(["op": .string("ANYTHING"), "value": .string("tag.clue")])
        XCTAssertThrowsError(try payload(draft))
    }
    func testWhitelistedBodyUsesBoundSnapshotWithoutAddingStructuralFields() throws {
        let baseline = ProjectEditSyntheticFixtures.snapshot(scope: .whitelist)
        let body = try ProjectEditContract.payload(baseline.draft, topicID: baseline.topicID, scope: baseline.scope)
        XCTAssertEqual(Set(body.keys), Set(ProjectEditContract.whitelist + ["id"]))
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: body, baseline: baseline), "api/topic/v2/update")
        var wrong = body; wrong["id"] = .number(72)
        XCTAssertThrowsError(try ProjectEditStoryContract.path(payload: wrong, baseline: baseline))
        wrong = body; wrong["configVersion"] = .number(1)
        XCTAssertThrowsError(try ProjectEditStoryContract.path(payload: wrong, baseline: baseline))
    }
    func testConfigVersionIsNeverFabricatedOrCoerced() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        XCTAssertNil(try payload(draft)["configVersion"])
        draft.preserved["configVersion"] = .number(7); draft.preserved["routeMode"] = .string("LINEAR")
        XCTAssertEqual(try payload(draft, id: 71)["configVersion"], .number(7))
        draft.preserved["configVersion"] = .string("7"); XCTAssertThrowsError(try payload(draft, id: 71))
        draft.preserved["configVersion"] = .number(0); XCTAssertThrowsError(try payload(draft, id: 71))
    }
    private let detail = #"{"code":200,"data":{"editScope":"FULL","openingChapterId":11,"collaboratorIds":[9],"topic":{"id":71,"productType":1,"name":"Route","description":"Story","imgUrl":"fixture://cover","categoryIds":"7","updateTime":"r1","startDate":"2030-05-01","endDate":"2030-05-30","publishMode":"pro","configVersion":7,"routeMode":"LINEAR"},"chapters":[{"id":11,"name":"Opening","description":"Story","cmsTopicNodeList":[],"blocks":[{"type":"text","key":"stable-key","content":"Story","who":"Narrator","level":1}]}],"tickets":[]}}"#
    func testDetailPreservesVersionChapterIDsStableBlockKeysAndTopLevelCollaborators() throws {
        let value = try ProjectEditContract.decodeEditDetail(Data(detail.utf8), expectedTopicID: 71, owner: .personal)
        XCTAssertEqual(value.draft.preserved["configVersion"], .number(7)); XCTAssertEqual(value.draft.collaboratorIDs, [9])
        XCTAssertEqual(value.draft.chapters[0].preserved["opening"], .bool(true))
        XCTAssertEqual(value.draft.chapters[0].blocks?[0].id, "stable-key")
        XCTAssertEqual(value.draft.chapters[0].blocks?[0].sourceFields?["who"], .string("Narrator"))
        let body = try payload(value.draft, id: 71)
        XCTAssertEqual(body["chapters"]?.array?.first?.object?["id"], .number(11))
        var changed = value.draft; changed.preserved["configVersion"] = .number(8)
        XCTAssertNotEqual(value, ProjectEditSnapshot(topicID: 71, scope: .full, draft: changed))
    }
    func testUnsupportedReadbackFailsInsteadOfLosingNarrativeFields() throws {
        for extra in [",\"beat\":\"enter\"", ",\"futureFlag\":true"] {
            let raw = detail.replacingOccurrences(of: "\"key\":\"stable-key\"", with: "\"key\":\"stable-key\"" + extra)
            XCTAssertThrowsError(try ProjectEditContract.decodeEditDetail(Data(raw.utf8), expectedTopicID: 71, owner: .personal))
        }
        let raw = detail.replacingOccurrences(of: "\"type\":\"text\"", with: "\"type\":\"dream\"")
        XCTAssertThrowsError(try ProjectEditContract.decodeEditDetail(Data(raw.utf8), expectedTopicID: 71, owner: .personal))
    }
    func testKnownLegacyReadProjectionRemainsLegacyWithoutDiscardingEdits() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        draft.chapters[0].preserved["_nativeStoredStoryFlow"] = .bool(false)
        draft.chapters[0].blocks = [.init(kind: .text, content: draft.chapters[0].description), .init(kind: .node, nodeID: draft.chapters[0].nodes[0].id)]
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload(draft), baseline: nil), "api/topic/create")
        draft.chapters[0].blocks?[0].content = "Changed story that legacy would lose"
        XCTAssertThrowsError(try payload(draft))
        // Backend explicitly compiles V2 free-explore blocks; persisted flow is never downgraded.
        draft.chapters[0].preserved["_nativeStoredStoryFlow"] = .bool(true)
        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload(draft), baseline: nil), "api/topic/v2/create")
    }
    func testCorruptStoredFlowCannotBeReplacedWithServerFallbackProjection() throws {
        let raw = detail.replacingOccurrences(of: "\"name\":\"Opening\"", with: "\"blocksJson\":\"broken\",\"name\":\"Opening\"")
        XCTAssertThrowsError(try ProjectEditContract.decodeEditDetail(Data(raw.utf8), expectedTopicID: 71, owner: .personal))
    }
    func testSourceFieldsRemainOptionalForOldLocalDrafts() throws {
        let data = try JSONEncoder().encode(ProjectEditBlock(kind: .text, content: "Old"))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); raw.removeValue(forKey: "sourceFields")
        let decoded = try JSONDecoder().decode(ProjectEditBlock.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(decoded.sourceFields); XCTAssertEqual(decoded.content, "Old")
    }
    func testBundleAcknowledgmentSeparatesPublishedFromReviewState() throws {
        let raw = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(#"{"topicId":71,"auditTaskId":301,"reviewState":"PENDING","published":true,"bundledTemplateIds":[41]}"#.utf8))
        let value = try ProjectEditBundleAcknowledgment.decode(raw, expectedTopicID: 71)
        XCTAssertTrue(value.published); XCTAssertEqual(value.reviewState, "PENDING"); XCTAssertEqual(value.auditTaskID, 301)
        XCTAssertThrowsError(try ProjectEditBundleAcknowledgment.decode(raw, expectedTopicID: 72))
        XCTAssertThrowsError(try ProjectEditBundleAcknowledgment.decode(.number(71), expectedTopicID: nil))
        var body = raw.object!; body["published"] = .number(1)
        XCTAssertThrowsError(try ProjectEditBundleAcknowledgment.decode(.object(body), expectedTopicID: nil))
        body = raw.object!; body["auditTaskId"] = .null
        XCTAssertThrowsError(try ProjectEditBundleAcknowledgment.decode(.object(body), expectedTopicID: nil))
        body = raw.object!; body["reviewState"] = .string("APPROVED")
        XCTAssertThrowsError(try ProjectEditBundleAcknowledgment.decode(.object(body), expectedTopicID: nil))
    }
}

private final class StoryContractTransport: HTTPTransport {
    var replies: [String]; var requests: [URLRequest] = []; var afterRead: (() -> Void)?
    init(_ replies: [String] = []) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path == "/api/publish/home" || request.url?.path == "/api/topic/edit-detail" { afterRead?() }
        guard !replies.isEmpty else { throw URLError(.networkConnectionLost) }
        return (Data(replies.removeFirst().utf8), 200)
    }
}
@MainActor final class ProjectEditStoryDispatchTests: XCTestCase {
    private let capability = #"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":2}}}"#
    private func session() throws -> ProjectEditSession { try .init(accountID: 7, epoch: 1, storageNamespace: "fixture") }
    private func operation(_ s: ProjectEditSession) throws -> ProjectEditPending {
        try .init(operationID: UUID(), ownerKey: s.ownerKey, identity: .init(), payload: ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full))
    }
    private func service(_ s: ProjectEditSession, _ transport: StoryContractTransport, _ store: ProjectEditLocalStore, paths: Set<String>, credentials: @escaping () -> ProjectEditCredentials?) throws -> ProjectEditHTTPService {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: s.storageNamespace, accountID: s.accountID, paths: paths)
        return ProjectEditHTTPService(configuration: configuration, transport: transport, owner: .personal, approval: approval, store: store, currentCredentials: credentials)
    }
    func testLegacyGrantDoesNotAuthorizeV2AndDefaultRemainsZeroDispatch() async throws {
        let s = try session(), c = try ProjectEditCredentials(session: s, token: "token"), t = StoryContractTransport(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), op = try operation(s)
        try store.savePending(op, session: s)
        let legacy = try service(s, t, store, paths: ["api/topic/create"], credentials: { c })
        let result = await legacy.submit(op, session: s)
        XCTAssertEqual(result, .notSent); XCTAssertTrue(t.requests.isEmpty)
    }
    func testUnknownV2CannotReplayEvenWhenGrantOrRouteVersionChanges() async throws {
        let s = try session(), c = try ProjectEditCredentials(session: s, token: "token"), t = StoryContractTransport([capability]), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), op = try operation(s)
        try store.savePending(op, session: s)
        let first = try service(s, t, store, paths: ["api/topic/v2/create"], credentials: { c })
        let result = await first.submit(op, session: s); XCTAssertEqual(result, .unknown)
        let recreated = try service(s, t, store, paths: ["api/topic/create"], credentials: { c })
        let second = await recreated.submit(op, session: s); XCTAssertEqual(second, .unknown)
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/publish/home", "/api/topic/v2/create"])
        XCTAssertEqual(try store.pending(session: s, identity: op.identity)?.dispatchStarted, true)
    }
    func testInvalidSchemaPreventsMarkerAndMutationAfterFreshAuthorityRead() async throws {
        let s = try session(), c = try ProjectEditCredentials(session: s, token: "token"), t = StoryContractTransport([capability]), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        var payload = try ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full)
        var chapters = payload["chapters"]!.array!, chapter = chapters[0].object!
        chapter["schemaVersion"] = .number(99); chapters[0] = .object(chapter); payload["chapters"] = .array(chapters)
        let op = try ProjectEditPending(operationID: UUID(), ownerKey: s.ownerKey, identity: .init(), payload: payload)
        try store.savePending(op, session: s)
        let adapter = try service(s, t, store, paths: ["api/topic/v2/create"], credentials: { c })
        let result = await adapter.submit(op, session: s)
        XCTAssertEqual(result, .notSent); XCTAssertEqual(t.requests.count, 1)
        XCTAssertNotEqual(try store.pending(session: s, identity: op.identity)?.dispatchStarted, true)
    }
    func testConfigVersionChangeWithSameTimestampStopsWhitelistUpdate() async throws {
        let json = #"{"code":200,"data":{"editScope":"WHITELIST","topic":{"id":71,"productType":1,"name":"Route","description":"Story","imgUrl":"fixture://cover","categoryIds":"7","updateTime":"same","configVersion":7},"chapters":[],"tickets":[]}}"#
        let s = try session(), c = try ProjectEditCredentials(session: s, token: "token"), t = StoryContractTransport([json.replacingOccurrences(of: "\"configVersion\":7", with: "\"configVersion\":8")]), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let baseline = try ProjectEditContract.decodeEditDetail(Data(json.utf8), expectedTopicID: 71, owner: .personal)
        let op = try ProjectEditPending(operationID: UUID(), ownerKey: s.ownerKey, identity: .init(topicID: 71), payload: ProjectEditContract.payload(baseline.draft, topicID: 71, scope: .whitelist), baseline: baseline)
        try store.savePending(op, session: s)
        let adapter = try service(s, t, store, paths: ["api/topic/v2/update"], credentials: { c })
        let result = await adapter.submit(op, session: s)
        XCTAssertEqual(result, .notSent); XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/topic/edit-detail"])
        XCTAssertNotEqual(try store.pending(session: s, identity: op.identity)?.dispatchStarted, true)
    }
    func testChangedSessionDuringFreshReadPreventsV2Write() async throws {
        let s = try session(), t = StoryContractTransport([capability]), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), op = try operation(s)
        var c: ProjectEditCredentials? = try .init(session: s, token: "token"); try store.savePending(op, session: s)
        t.afterRead = { c = nil }
        let adapter = try service(s, t, store, paths: ["api/topic/v2/create"], credentials: { c })
        let result = await adapter.submit(op, session: s)
        XCTAssertEqual(result, .notSent); XCTAssertEqual(t.requests.count, 1)
        XCTAssertNotEqual(try store.pending(session: s, identity: op.identity)?.dispatchStarted, true)
    }
}
