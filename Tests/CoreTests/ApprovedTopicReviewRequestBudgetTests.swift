import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ApprovedTopicReviewRequestBudgetTests: XCTestCase {
    private let nine = "nine_prepare_fits_submit_does_not"
    private let eleven = "eleven_small_ids"
    private let maximum = "thirty_two_native_maximum"
    private func bytes(_ name: String, _ part: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ReviewRequestBudget/\(name)-\(part).json")
        return try Data(contentsOf: url)
    }
    private func fields(_ name: String, _ part: String) throws -> [String: ProjectEditJSON] {
        try JSONDecoder().decode([String: ProjectEditJSON].self, from: bytes(name, part))
    }
    private func capture(_ name: String) throws -> ApprovedTopicReviewCapture {
        let root = try fields(name, "prepare-response-data")
        return try .decode(.object(root), topicID: XCTUnwrap(root["topicId"]?.integer), observedAuditTaskID: XCTUnwrap(root["observedAuditTaskId"]?.integer))
    }
    private func session() throws -> ProjectEditSession { try .init(accountID: 7, epoch: 1, storageNamespace: "review-body-budget") }
    private func origin(_ session: ProjectEditSession, _ capture: ApprovedTopicReviewCapture) throws -> ApprovedTopicReleaseReadTarget {
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId": .number(Decimal(capture.topicID)), "auditTaskId": .number(Decimal(capture.observedAuditTaskID)), "reviewState": .string("PENDING"), "published": .bool(true), "bundledTemplateIds": .array([])]), expectedTopicID: nil)
        let pending = try ProjectEditPending(operationID: UUID(), ownerKey: session.ownerKey, identity: .init(), payload: ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full), completedTopicID: capture.topicID, serverAcknowledged: true, bundleAcknowledgment: ack)
        return try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: pending, session: session))
    }
    func testExactFormerPrepareFitsSubmitFailsCounterexampleNowFitsBothBudgets() throws {
        XCTAssertEqual(try bytes(nine, "prepare").count, 3901)
        XCTAssertEqual(try bytes(nine, "submit").count, 4105)
        let prepare = try ApprovedTopicReviewRequestBody.encode(fields(nine, "prepare"), path: ApprovedTopicReviewPath.prepare)
        let submit = try ApprovedTopicReviewRequestBody.encode(fields(nine, "submit"), path: ApprovedTopicReviewPath.submit)
        XCTAssertEqual(prepare.count, 3901); XCTAssertEqual(submit.count, 4105)
        XCTAssertLessThanOrEqual(prepare.count, 4096); XCTAssertGreaterThan(submit.count, 4096)
    }
    func testElevenAndAllThirtyTwoMaximumWidthSourcesFitFiniteWireBudget() throws {
        for (name, count, prepareBytes, submitBytes) in [(eleven, 11, 4123, 4309), (maximum, 32, 13630, 13843)] {
            let c = try capture(name), p = try ApprovedTopicReviewRequestBody.encode(fields(name, "prepare"), path: ApprovedTopicReviewPath.prepare)
            let body = try fields(name, "submit"), uuid = try XCTUnwrap(UUID(uuidString: XCTUnwrap(body["requestId"]?.text)))
            let command = ApprovedTopicReviewCommand(capture: c, requestID: uuid)
            XCTAssertEqual(c.selectedMerchantSources.count, count); XCTAssertEqual(p.count, prepareBytes)
            XCTAssertEqual(try ApprovedTopicReviewRequestBody.encode(command.fields, path: ApprovedTopicReviewPath.submit).count, submitBytes)
            XCTAssertNoThrow(try ApprovedTopicReviewRequestBody.preflight(command, capture: c))
        }
        XCTAssertEqual(ApprovedTopicReviewRequestBody.maximumSourceBodyBytes, 16384)
    }
    func testEncoderAcceptsExactLimitAndRejectsOneAdditionalByte() throws {
        let limit = ApprovedTopicReviewRequestBody.maximumSourceBodyBytes
        // Byte-encoder resource boundary only; actual shape validation is tested by the outer-route suite.
        let empty: [String: ProjectEditJSON] = ["padding": .string(""), "sourceSelections": .array([])]
        let overhead = try JSONEncoder().encode(empty).count
        let exact: [String: ProjectEditJSON] = ["padding": .string(String(repeating: "x", count: limit - overhead)), "sourceSelections": .array([])]
        XCTAssertEqual(try ApprovedTopicReviewRequestBody.encode(exact, path: ApprovedTopicReviewPath.submit).count, limit)
        XCTAssertThrowsError(try ApprovedTopicReviewRequestBody.encode(["padding": .string(String(repeating: "x", count: limit - overhead + 1)), "sourceSelections": .array([])], path: ApprovedTopicReviewPath.submit))
        XCTAssertThrowsError(try ApprovedTopicReviewRequestBody.encode(["padding": .string(String(repeating: "x", count: 1024 * 1024))], path: ApprovedTopicReviewPath.prepare))
    }
    func testSelectorAndUnrelatedRoutesKeepFourKiBBudget() throws {
        let paths = [ApprovedTopicReviewPath.prepare, ApprovedTopicReviewPath.submit, ApprovedTopicReviewPath.sources, ApprovedTopicReviewPath.status, ApprovedTopicReviewPath.current,
                     ApprovedTopicReleasePaths.prepare, ApprovedTopicReleasePublicationPath.publish, ProjectMerchantDraftPath.resolve]
        let fields: [String: ProjectEditJSON] = ["padding": .string(String(repeating: "x", count: 4096))]
        for path in paths {
            XCTAssertEqual(ApprovedTopicReviewRequestBody.maximumBytes(for: path, fields: fields), 4096)
            XCTAssertThrowsError(try ApprovedTopicReviewRequestBody.encode(fields, path: path))
        }
    }
    func testThirtyThirdAndDuplicateSourceStillRejectBeforeCaptureExists() throws {
        var root = try fields(maximum, "prepare-response-data"), summary = try XCTUnwrap(root["summary"]?.object)
        var rows = try XCTUnwrap(summary["selectedMerchantSources"]?.array); rows.append(try XCTUnwrap(rows.first))
        summary["selectedMerchantSources"] = .array(rows); root["summary"] = .object(summary)
        XCTAssertThrowsError(try ApprovedTopicReviewCapture.decode(.object(root), topicID: Int.max, observedAuditTaskID: Int.max))
        XCTAssertThrowsError(try ApprovedMerchantReviewSource.decodeSelections(.array(rows)))
        rows.removeLast(); rows[1] = rows[0]
        XCTAssertThrowsError(try ApprovedMerchantReviewSource.decodeSelections(.array(rows)))
    }
    func testCompleteCommandPreflightRejectsMismatchedCapture() throws {
        let c = try capture(maximum), different = try capture(nine)
        XCTAssertThrowsError(try ApprovedTopicReviewRequestBody.preflight(.init(capture: c), capture: different))
    }
    func testMaximumCommandPersistsAndReopensExactHistoricalReferences() throws {
        let c = try capture(maximum), s = try session(), target = try origin(s, c), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let initial = try journal.read(session: s, topicID: c.topicID)
        XCTAssertTrue(journal.canBegin(c, origin: target, expected: initial))
        let uuid = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let saved = try journal.begin(c, origin: target, expected: initial, session: s, requestID: uuid), before = storage.data
        let restored = try ApprovedTopicReviewJournal(storage: storage).read(session: s, topicID: c.topicID)
        XCTAssertEqual(restored, saved); XCTAssertEqual(storage.data, before)
        let record = try XCTUnwrap(restored.current)
        XCTAssertEqual(record.command.fields, try fields(maximum, "submit")); XCTAssertEqual(record.command.readSelectorFields.count, 6)
        XCTAssertEqual(record.command.selectedMerchantSources.count, 32)
        XCTAssertFalse(journal.canBegin(c, origin: target, expected: restored))
        XCTAssertThrowsError(try journal.begin(c, origin: target, expected: restored, session: s)); XCTAssertEqual(storage.data, before)
    }
    @MainActor private final class CountingStorage: ProjectEditDataStorage {
        var values: [String: Data] = ["unrelated-existing-intent": Data("preserve-existing-bytes".utf8)]
        var writes = 0, removals = 0
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { writes += 1; values[key] = data }
        func remove(_ key: String) throws { removals += 1; values.removeValue(forKey: key) }
    }
    func testJournalRejectsMismatchingCaptureWithZeroWritesAndUnchangedExistingBytes() throws {
        let valid = try capture(maximum), foreign = try capture(nine), s = try session(), target = try origin(s, valid)
        let storage = CountingStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let initial = try journal.read(session: s, topicID: valid.topicID), before = storage.values
        XCTAssertFalse(journal.canBegin(foreign, origin: target, expected: initial))
        XCTAssertThrowsError(try journal.begin(foreign, origin: target, expected: initial, session: s))
        XCTAssertEqual(storage.writes, 0); XCTAssertEqual(storage.removals, 0); XCTAssertEqual(storage.values, before)
        XCTAssertEqual(try journal.read(session: s, topicID: valid.topicID), initial)
    }
    @MainActor private final class Wire: HTTPTransport {
        let choices: ProjectEditJSON, capture: ProjectEditJSON
        var requests: [URLRequest] = []; var unknown = true
        init(choices: ProjectEditJSON, capture: ProjectEditJSON) { self.choices = choices; self.capture = capture }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = try XCTUnwrap(request.url?.lastPathComponent)
            let fields = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody))
            if path == "submit", unknown { unknown = false; return (Data(), 503) }
            let value: ProjectEditJSON
            if path == "sources" { value = choices }
            else if path == "prepare" { value = capture }
            else { value = ApprovedTopicReviewSynthetic.receiptFields(command: fields) }
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": value]), 200)
        }
    }
    func testRealClientFlowThirtyTwoSourcesUnknownIntentRestoresRetriesAndReadsSixFields() async throws {
        let c = try capture(maximum), s = try session(), target = try origin(s, c)
        let wire = Wire(choices: .object(try fields(maximum, "sources-response-data")), capture: .object(try fields(maximum, "prepare-response-data")))
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com")!), credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic-budget")
        let paths: Set<String> = [ApprovedTopicReviewPath.sources, ApprovedTopicReviewPath.prepare, ApprovedTopicReviewPath.submit, ApprovedTopicReviewPath.status]
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: s.storageNamespace, accountID: s.accountID, paths: paths)
        let service = ApprovedTopicReviewClient(configuration: api, approval: approval, transport: wire, currentCredentials: { credentials })
        let storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: journal, stillCurrent: { true })
        await flow.load(); guard case .selectingSources(let shown) = flow.state else { return XCTFail("Expected all 32 source groups") }
        for group in shown.choices.groups { XCTAssertTrue(flow.selectSource(try XCTUnwrap(group.confirmations.first), from: shown)) }
        XCTAssertTrue(storage.data.isEmpty); await flow.captureSources(try XCTUnwrap(flow.claimSourceCapture(shown)))
        guard case .ready(let prepared) = flow.state else { return XCTFail("32 sources must pass prepare") }
        XCTAssertEqual(prepared, c); let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared))))
        let original = try XCTUnwrap(flow.snapshot?.current); await flow.submit(claim); XCTAssertEqual(flow.state, .unconfirmed); flow.close()
        let persisted = storage.data, reopened = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: journal, stillCurrent: { true })
        await reopened.load(); XCTAssertEqual(reopened.state, .unconfirmed); XCTAssertEqual(storage.data, persisted)
        await reopened.retryExact(try XCTUnwrap(reopened.snapshot)); guard case .known = reopened.state else { return XCTFail("Exact retry must succeed") }
        await reopened.check(try XCTUnwrap(reopened.snapshot))
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["sources", "prepare", "submit", "submit", "status"])
        for request in wire.requests.filter({ $0.url!.lastPathComponent == "submit" }) {
            XCTAssertEqual(try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody)), original.command.fields)
            XCTAssertEqual(try XCTUnwrap(request.httpBody).count, 13843)
        }
        XCTAssertEqual(try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(wire.requests.last?.httpBody)), original.command.readSelectorFields)
        XCTAssertEqual(try journal.read(session: s, topicID: c.topicID).current?.command, original.command)
    }
}
