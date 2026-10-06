import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ApprovedTopicReleasePreparationTests: XCTestCase {
    private func body() -> [String: ProjectEditJSON] {
        let node: ProjectEditJSON = .object(["id": .number(301), "templateId": .number(41), "nodeTime": .number(30),
            "name": .string("Captured node"), "description": .string("  e\u{301}\n"), "address": .string("Captured address"),
            "longitude": .string("121.5"), "latitude": .string("31.2"), "imgUrl": .null,
            "templateTitle": .string("Captured QA"), "templateCategoryId": .number(4), "templateCategoryIds": .string("7,999"),
            "templateContentHash": .string("sha256:" + String(repeating: "b", count: 64)), "questionText": .string("Approved question?"),
            "ruleInstructions": .null, "answerPresent": .bool(true)])
        let chapter: ProjectEditJSON = .object(["id": .number(201), "name": .string("Captured chapter"), "description": .null,
            "blocks": .array([.object(["type": .string("text"), "key": .string("first"), "content": .string("Captured text\n"), "node": .null]),
                              .object(["type": .string("node"), "key": .string("second"), "content": .null, "node": node])])])
        return ["contract": .string(ApprovedTopicReleasePreparation.textCityContract), "topicId": .number(7901), "auditTaskId": .number(3301),
            "auditTaskVersion": .number(2), "auditSnapshotHash": .string(String(repeating: "c", count: 64)),
            "manifestHash": .string(String(repeating: "a", count: 64)), "headRevision": .number(0), "sourceConfigVersion": .number(1),
            "name": .string("Approved title"), "description": .null, "categoryIds": .string("7,999"),
            "currentlyApproved": .bool(true), "releaseAllocated": .bool(false), "secretValuesExcluded": .bool(true), "chapters": .array([chapter])]
    }
    private func data() throws -> Data { try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(body())]) }
    private func decode(_ body: [String: ProjectEditJSON]) throws -> ApprovedTopicReleasePreparation { try .decode(.object(body), topicID: 7901, auditTaskID: 3301) }
    private func session(_ epoch: UInt64 = 1) throws -> ProjectEditSession { try .init(accountID: 7, epoch: epoch, storageNamespace: "release-read-test") }
    private func target(_ s: ProjectEditSession) throws -> ApprovedTopicReleaseReadTarget {
        let acknowledgment = try ProjectEditBundleAcknowledgment.decode(.object(["topicId": .number(7901), "auditTaskId": .number(3301), "reviewState": .string("PENDING"), "published": .bool(true), "bundledTemplateIds": .array([.number(41)])]), expectedTopicID: nil)
        let draft = ProjectEditSyntheticFixtures.draft()
        let pending = try ProjectEditPending(operationID: UUID(), ownerKey: s.ownerKey, identity: .init(), payload: ProjectEditContract.payload(draft, topicID: nil, scope: .full), completedTopicID: 7901, serverAcknowledged: true, bundleAcknowledgment: acknowledgment)
        return try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: pending, session: s))
    }
    @MainActor private final class Wire: HTTPTransport {
        var reply: Data; var status = 200; var requests: [URLRequest] = []
        var hold = false; var started: XCTestExpectation?; var continuation: CheckedContinuation<(Data, Int), Error>?
        init(_ reply: Data) { self.reply = reply }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if hold { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
            started?.fulfill()
            return (reply, status)
        }
        func finish(status: Int = 200) { let next = continuation; continuation = nil; next?.resume(returning: (reply, status)) }
    }
    private func client(_ s: ProjectEditSession, wire: Wire, paths: Set<String>?, credentials: @escaping () -> ApprovedTopicReleaseCredentials?) throws -> ApprovedTopicReleasePreparationClient {
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try paths.map { try OperationEndpointApproval(baseURL: api.baseURL, namespace: s.storageNamespace, accountID: s.accountID, paths: $0) }
        return .init(configuration: api, approval: approval, transport: wire, currentCredentials: credentials)
    }
    func testBusinessCapabilityIsSeparateDefaultOffAndCannotAuthorizePublishOrLegacyRoutes() throws {
        let configuration = try BusinessRuntimeConfiguration(market: .china, baseURL: URL(string: "https://example.com")!, namespace: "release-read-test", accountID: 7)
        XCTAssertTrue(configuration.routes.isEmpty)
        let prepare = try BusinessRuntimeRoute.post(ApprovedTopicReleasePaths.prepare)
        XCTAssertTrue(BusinessRuntimeFeature.approvedTopicReleasePrepare.accepts(prepare))
        XCTAssertFalse(BusinessRuntimeFeature.projectRead.accepts(prepare)); XCTAssertFalse(BusinessRuntimeFeature.publishingRead.accepts(prepare))
        for path in ["api/approved-topic-release/v1/publish", "api/approved-topic-release/v1/start", "api/topic/v2/create"] {
            XCTAssertFalse(BusinessRuntimeFeature.approvedTopicReleasePrepare.accepts(try .post(path)))
        }
        XCTAssertThrowsError(try BusinessRuntimeConfiguration(market: .china, baseURL: URL(string: "https://example.com")!, namespace: "release-read-test", accountID: 7,
            routes: [.approvedTopicReleasePrepare: [try .post("api/approved-topic-release/v1/publish")]]))
    }
    func testCapturedSummaryPreservesExactTextAndOrderWithoutPrivateAnswerValues() throws {
        let value = try decode(body()); XCTAssertEqual(value.categoryIDs, "7,999"); XCTAssertEqual(value.chapters[0].blocks[0].content, "Captured text\n")
        let node = try XCTUnwrap(value.chapters[0].blocks[1].node); XCTAssertEqual(Array(try XCTUnwrap(node.description).utf8), Array("  e\u{301}\n".utf8))
        XCTAssertNil(node.imageReference); XCTAssertTrue(node.answerPresent); XCTAssertEqual(node.templateID, 41); XCTAssertEqual(node.questionText, "Approved question?")
    }
    func testWrongProfileIdentityOrApprovalFlagsFailClosed() throws {
        for (key, value) in [("contract", ProjectEditJSON.string("official-city")), ("topicId", .number(44)), ("auditTaskId", .number(22)), ("currentlyApproved", .bool(false)), ("releaseAllocated", .bool(true)), ("secretValuesExcluded", .bool(false)), ("manifestHash", .string(String(repeating: "G", count: 64))), ("headRevision", .number(-1))] {
            var valueBody = body(); valueBody[key] = value; XCTAssertThrowsError(try decode(valueBody), key)
        }
    }
    func testDuplicateNodeOrUnsupportedSecretFieldIsNotSilentlyDropped() throws {
        var value = body(), chapter = try XCTUnwrap(value["chapters"]?.array?.first?.object), blocks = try XCTUnwrap(chapter["blocks"]?.array)
        blocks.append(blocks[1]); chapter["blocks"] = .array(blocks); value["chapters"] = .array([.object(chapter)])
        XCTAssertThrowsError(try decode(value))
        value = body(); value["questionAnswer"] = .string("should-not-be-returned"); XCTAssertThrowsError(try decode(value))
    }
    func testWireBoundsPrecedeRecursiveParsingAndRejectEscapedDuplicateKeys() throws {
        for value in [String(repeating: "[", count: 20_000) + "0" + String(repeating: "]", count: 20_000),
                      #"{"code":200,"\u0063ode":401}"#, "{\"number\":" + String(repeating: "9", count: 129) + "}",
                      "{\"value\":\"" + String(repeating: "a", count: 100_000) + "\"}"] {
            XCTAssertThrowsError(try ApprovedTopicReleaseWire.envelope(Data(value.utf8)))
        }
        XCTAssertThrowsError(try ApprovedTopicReleaseWire.envelope(Data(repeating: 32, count: 4 * 1024 * 1024 + 1)))
        XCTAssertEqual(try ApprovedTopicReleaseWire.envelope(Data(#"{"value":"braces [ { ] } and \"quote\""}"#.utf8))["value"]?.text, "braces [ { ] } and \"quote\"")
    }
    func testAbsentOrLegacyApprovalCausesZeroDispatch() async throws {
        let s = try session(), credentials = try ApprovedTopicReleaseCredentials(session: s, token: "synthetic-token"), wire = try Wire(data()), t = try target(s)
        let pathSets: [Set<String>?] = [nil, ["api/topic/v2/create", "api/project/my"]]
        for paths in pathSets {
            let value = try client(s, wire: wire, paths: paths, credentials: { credentials })
            XCTAssertFalse(value.isCurrent(session: s))
            do { _ = try await value.prepare(t, session: s); XCTFail() } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExactEndpointSendsOnlyCapturedTopicAndAuditTask() async throws {
        let s = try session(), credentials = try ApprovedTopicReleaseCredentials(session: s, token: "synthetic-token"), wire = try Wire(data())
        let value = try client(s, wire: wire, paths: [ApprovedTopicReleasePaths.prepare], credentials: { credentials })
        let result = try await value.prepare(target(s), session: s); XCTAssertEqual(result.name, "Approved title")
        let request = try XCTUnwrap(wire.requests.first); XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/api/approved-topic-release/v1/prepare")
        XCTAssertEqual(try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody)), ["topicId": .number(7901), "auditTaskId": .number(3301)])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
    }
    func testActualFlowOwnsFirstHeldReadAcrossQueuedSecondLoadAndCloseBefore401() async throws {
        let s = try session(), credentials = try ApprovedTopicReleaseCredentials(session: s, token: "synthetic-token"), wire = try Wire(data())
        wire.hold = true; let started = expectation(description: "actual transport held"); wire.started = started
        let source = try client(s, wire: wire, paths: [ApprovedTopicReleasePaths.prepare], credentials: { credentials })
        let flow = try ApprovedTopicReleaseReadFlow(target: target(s), session: s, source: source, stillCurrent: { true })
        let first = Task { await flow.load() }; await fulfillment(of: [started], timeout: 3)
        await flow.load(); XCTAssertEqual(wire.requests.count, 1)
        flow.close(); wire.finish(status: 401); await first.value; XCTAssertEqual(flow.state, .closed)
    }
    func testCurrent401IsStillVisibleRatherThanAlwaysSuppressed() async throws {
        let s = try session(), credentials = try ApprovedTopicReleaseCredentials(session: s, token: "synthetic-token"), wire = try Wire(data()); wire.status = 401
        let source = try client(s, wire: wire, paths: [ApprovedTopicReleasePaths.prepare], credentials: { credentials })
        let flow = try ApprovedTopicReleaseReadFlow(target: target(s), session: s, source: source, stillCurrent: { true })
        await flow.load(); XCTAssertEqual(flow.state, .unauthorized)
    }
    func testContextChangeDuringReadRetiresOriginalFlowBeforeAnyLateFactsAreShown() async throws {
        let s = try session(); var credentials: ApprovedTopicReleaseCredentials? = try .init(session: s, token: "synthetic-token")
        let wire = try Wire(data()); wire.hold = true; let started = expectation(description: "held"); wire.started = started
        let source = try client(s, wire: wire, paths: [ApprovedTopicReleasePaths.prepare], credentials: { credentials })
        let flow = try ApprovedTopicReleaseReadFlow(target: target(s), session: s, source: source, stillCurrent: { true })
        let first = Task { await flow.load() }; await fulfillment(of: [started], timeout: 3)
        credentials = try .init(session: session(2), token: "new-synthetic-token"); wire.finish(); await first.value
        XCTAssertEqual(flow.state, .closed); XCTAssertFalse(flow.isCurrent)
        credentials = try .init(session: s, token: "synthetic-token"); await flow.load(); XCTAssertEqual(wire.requests.count, 1)
    }
    func testCallerCancellationCancelsOwnedReadAndCannotLeaveLoadingZombie() async throws {
        let s = try session(), credentials = try ApprovedTopicReleaseCredentials(session: s, token: "synthetic-token"), wire = try Wire(data())
        wire.hold = true; let started = expectation(description: "held"); wire.started = started
        let source = try client(s, wire: wire, paths: [ApprovedTopicReleasePaths.prepare], credentials: { credentials })
        let flow = try ApprovedTopicReleaseReadFlow(target: target(s), session: s, source: source, stillCurrent: { true })
        let first = Task { await flow.load() }; await fulfillment(of: [started], timeout: 3)
        first.cancel(); wire.finish(); await first.value; XCTAssertEqual(flow.state, .closed)
    }
    func testActualTemplateCategoryFieldsRemainDistinctThroughPreparedPersistence() throws {
        let prepared = try decode(body()), node = try XCTUnwrap(prepared.chapters[0].blocks[1].node)
        XCTAssertEqual(node.templateCategoryID, 4); XCTAssertEqual(node.templateCategoryIDs, "7,999")
        let restored = try ApprovedTopicReleasePreparation.decode(prepared.persistedFields, topicID: 7901, auditTaskID: 3301)
        XCTAssertEqual(restored, prepared)
        let command = ApprovedTopicReleasePublishCommand(prepared: prepared)
        XCTAssertFalse(command.fields.keys.contains("templateCategoryId")); XCTAssertFalse(command.fields.keys.contains("categoryIds"))
    }
    func testMissingLegacyCategoryAndExplicitNullStayAbsentWhileMistypedValuesReject() throws {
        func changed(_ replacement: ProjectEditJSON?) throws -> [String: ProjectEditJSON] {
            var value = body(), chapter = try XCTUnwrap(value["chapters"]?.array?.first?.object)
            var blocks = try XCTUnwrap(chapter["blocks"]?.array), block = try XCTUnwrap(blocks[1].object)
            var node = try XCTUnwrap(block["node"]?.object); node["templateCategoryId"] = replacement
            block["node"] = .object(node); blocks[1] = .object(block); chapter["blocks"] = .array(blocks); value["chapters"] = .array([.object(chapter)]); return value
        }
        let missingValues: [ProjectEditJSON?] = [nil, .null]
        for missing in missingValues {
            let node = try XCTUnwrap(decode(changed(missing)).chapters[0].blocks[1].node)
            XCTAssertNil(node.templateCategoryID); XCTAssertEqual(node.templateCategoryIDs, "7,999")
        }
        let invalidValues: [ProjectEditJSON] = [.string("4"), .number(-1), .number(Decimal(string: "4.5")!), .bool(true), .object([:]), .array([])]
        for invalid in invalidValues {
            XCTAssertThrowsError(try decode(changed(invalid)))
        }
        XCTAssertEqual(try decode(changed(.number(0))).chapters[0].blocks[1].node?.templateCategoryID, 0)
    }

    func testCurrentEmptyOrMalformedBody401UsesUnauthorizedFlowState() async throws {
        let s = try session(), credentials = try ApprovedTopicReleaseCredentials(session:s,token:"synthetic-token")
        for body in [Data(),Data([0xc3,0x28])] {
            let wire = Wire(body); wire.status = 401
            let source = try client(s,wire:wire,paths:[ApprovedTopicReleasePaths.prepare],credentials:{credentials})
            let flow = try ApprovedTopicReleaseReadFlow(target:target(s),session:s,source:source,stillCurrent:{true})
            await flow.load(); XCTAssertEqual(flow.state,.unauthorized); XCTAssertEqual(wire.requests.count,1)
        }
    }
    func testOldSessionEmptyBody401IsRejectedBeforeHTTPAuthenticationClassification() async throws {
        let s = try session(); var credentials: ApprovedTopicReleaseCredentials? = try .init(session:s,token:"synthetic-token")
        let wire = Wire(Data()); wire.hold = true; let started = expectation(description:"empty 401 held for old session"); wire.started = started
        let source = try client(s,wire:wire,paths:[ApprovedTopicReleasePaths.prepare],credentials:{credentials}), original = try target(s)
        let task = Task { try await source.prepare(original,session:s) }; await fulfillment(of:[started],timeout:3)
        let fresh = try ApprovedTopicReleaseCredentials(session:session(2),token:"new-synthetic-token"); credentials = fresh
        wire.finish(status:401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError,.changedContext); XCTAssertNotEqual(error as? APIError,.unauthorized) }
        XCTAssertEqual(credentials,fresh); XCTAssertEqual(wire.requests.count,1)
    }

}
