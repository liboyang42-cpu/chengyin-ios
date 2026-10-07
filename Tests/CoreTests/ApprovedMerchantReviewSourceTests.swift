import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ApprovedMerchantReviewSourceTests: XCTestCase {
    private func session(_ account: Int = 7, epoch: UInt64 = 1) throws -> ProjectEditSession { try .init(accountID: account, epoch: epoch, storageNamespace: "merchant-review-sources") }
    private func origin(_ s: ProjectEditSession) throws -> ApprovedTopicReleaseReadTarget {
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId": .number(7901), "auditTaskId": .number(3301), "reviewState": .string("PENDING"), "published": .bool(true), "bundledTemplateIds": .array([.number(73)])]), expectedTopicID: nil)
        let pending = try ProjectEditPending(operationID: UUID(), ownerKey: s.ownerKey, identity: .init(), payload: ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full), completedTopicID: 7901, serverAcknowledged: true, bundleAcknowledgment: ack)
        return try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: pending, session: s))
    }
    private static func selection(_ confirmation: Int = 92) -> ProjectEditJSON {
        .object(["memberTemplateId": .number(73), "source": .object(["kind": .string("MERCHANT_AI_TEMPLATE_SOURCE_V1"), "sourceId": .number(91), "sourceVersion": .number(1), "contentHash": .string(String(repeating: "a", count: 64))]), "merchantConfirmation": .object(["kind": .string("MERCHANT_STORE_FACTS_CONFIRMATION_V1"), "sourceId": .number(Decimal(confirmation)), "sourceVersion": .number(1), "contentHash": .string(String(repeating: "b", count: 64))])])
    }
    private static func choices() -> ProjectEditJSON {
        .object(["contract": .string("questify.topic-release.merchant-source-choices.v1"), "templateIdNamespace": .string("CMS_MEMBER_TEMPLATE"), "currentness": .string("CONFIRMED_HISTORICAL_INPUTS"), "ownerMemberId": .number(7), "topicId": .number(7901), "observedAuditTaskId": .number(3301), "observedAuditTaskVersion": .number(0), "sourceConfigVersion": .number(1), "approvalProof": .bool(false), "publicationAuthority": .bool(false), "sources": .array([.object(["memberTemplateId": .number(73), "hasOlderConfirmations": .bool(false), "confirmations": .array([.object(["selection": selection(), "templateTitle": .string("Synthetic shop draft"), "templateContentHash": .string(String(repeating: "c", count: 64)), "confirmedAtEpochMillis": .number(1700000000000)])])])])])
    }
    private static func capture(_ selected: ProjectEditJSON? = nil) -> ProjectEditJSON {
        var root = ApprovedTopicReviewSynthetic.captureFields().object!, summary = root["summary"]!.object!
        summary["selectedMerchantSources"] = selected ?? .array([selection()]); root["summary"] = .object(summary); return .object(root)
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], status = 200, unknownSubmit = false, held = false
        var started: XCTestExpectation?, continuation: CheckedContinuation<(Data, Int), Error>?
        var choices = ApprovedMerchantReviewSourceTests.choices()
        var prepared: ProjectEditJSON?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if held { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
            let fields = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody)), path = request.url!.path
            if path.hasSuffix("/sources") { return try reply(choices) }
            if path.hasSuffix("/prepare") { return try reply(prepared ?? ApprovedMerchantReviewSourceTests.capture(fields["sourceSelections"])) }
            if path.hasSuffix("/submit"), unknownSubmit { return (Data(), 500) }
            let receipt = ApprovedTopicReviewSynthetic.receiptFields(command: fields)
            if path.hasSuffix("/current") { return try reply(ApprovedTopicReviewSynthetic.observationFields(receipt: receipt)) }
            return try reply(receipt)
        }
        func reply(_ data: ProjectEditJSON) throws -> (Data, Int) { (try JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(status)), "data": data]), status) }
        func finish401() { let old = continuation; continuation = nil; old?.resume(returning: (Data(), 401)) }
    }
    private func client(_ s: ProjectEditSession, _ wire: Wire, paths: Set<String>? = nil, current: @escaping () -> ApprovedTopicReviewCredentials?) throws -> ApprovedTopicReviewClient {
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com/native")!), approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: s.storageNamespace, accountID: s.accountID, paths: paths ?? [ApprovedTopicReviewPath.sources, ApprovedTopicReviewPath.prepare, ApprovedTopicReviewPath.submit, ApprovedTopicReviewPath.status, ApprovedTopicReviewPath.current])
        return .init(configuration: api, approval: approval, transport: wire, currentCredentials: current)
    }
    private func readySelection(_ flow: ApprovedTopicReviewFlow) async throws -> ApprovedTopicReviewFlow.SourceSelectionPresentation {
        await flow.load(); guard case .selectingSources(let value) = flow.state else { throw ApprovedTopicReleaseError.invalidResponse }; return value
    }
    private func captureSelected(_ flow: ApprovedTopicReviewFlow, _ shown: ApprovedTopicReviewFlow.SourceSelectionPresentation) async throws -> ApprovedTopicReviewCapture {
        XCTAssertTrue(flow.selectSource(try XCTUnwrap(shown.choices.groups.first?.confirmations.first), from: shown)); let claim = try XCTUnwrap(flow.claimSourceCapture(shown)); await flow.captureSources(claim)
        guard case .ready(let capture) = flow.state else { throw ApprovedTopicReleaseError.invalidResponse }; return capture
    }
    func testExactSourceCommandPersistsSevenFieldsAndReadsOnlySixAfterReopen() async throws {
        let s = try session(), target = try origin(s), wire = Wire(), credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"), service = try client(s, wire, current: { credentials }), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage)
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: journal, stillCurrent: { true }), shown = try await readySelection(flow)
        XCTAssertTrue(storage.data.isEmpty); XCTAssertFalse(flow.canCaptureSources(shown))
        let capture = try await captureSelected(flow, shown); XCTAssertEqual(capture.selectedMerchantSources.count, 1)
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(capture)))), original = try XCTUnwrap(flow.snapshot?.current)
        XCTAssertEqual(original.command.fields.count, 7); XCTAssertEqual(original.command.readSelectorFields.count, 6)
        wire.unknownSubmit = true; await flow.submit(claim); XCTAssertEqual(flow.state, .unconfirmed); flow.close()
        let before = storage.data, reopened = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: journal, stillCurrent: { true }); await reopened.load()
        XCTAssertEqual(reopened.state, .unconfirmed); XCTAssertEqual(wire.requests.count, 3); XCTAssertEqual(storage.data, before)
        await reopened.check(try XCTUnwrap(reopened.snapshot)); guard case .known = reopened.state else { return XCTFail() }
        await reopened.observeCurrent(try XCTUnwrap(reopened.snapshot))
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["sources", "prepare", "submit", "status", "current"])
        for request in wire.requests.suffix(2) { XCTAssertEqual(try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody)), original.command.readSelectorFields) }
        XCTAssertEqual(try journal.read(session: s, topicID: 7901).current?.command.selectedMerchantSources, original.command.selectedMerchantSources)
    }
    func testQueuedSourceCaptureAfterCloseNeverDispatches() async throws {
        let s = try session(), target = try origin(s), wire = Wire(), credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"), service = try client(s, wire, current: { credentials })
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: ProjectEditMemoryStorage()), stillCurrent: { true }), shown = try await readySelection(flow)
        XCTAssertTrue(flow.selectSource(shown.choices.groups[0].confirmations[0], from: shown)); let claim = try XCTUnwrap(flow.claimSourceCapture(shown)); flow.close(); await flow.captureSources(claim)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(flow.state, .closed)
    }
    func testIdenticalReloadDoesNotReviveOldSelectionOrCaptureControls() async throws {
        let s = try session(), target = try origin(s), wire = Wire(), credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"), service = try client(s, wire, current: { credentials })
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: ProjectEditMemoryStorage()), stillCurrent: { true }), old = try await readySelection(flow), fresh = try await readySelection(flow)
        XCTAssertEqual(old.choices, fresh.choices); XCTAssertNotEqual(old.id, fresh.id)
        XCTAssertFalse(flow.selectSource(old.choices.groups[0].confirmations[0], from: old)); XCTAssertNil(flow.claimSourceCapture(old)); XCTAssertTrue(flow.selectedSources.isEmpty)
        _ = try await captureSelected(flow, fresh); XCTAssertEqual(wire.requests.count, 3)
    }
    func testHeldSource401AfterAccountABACannotMutateReturnedSession() async throws {
        let s = try session(), target = try origin(s), wire = Wire(); wire.held = true; wire.started = expectation(description: "actual source transport")
        var credentials: ApprovedTopicReviewCredentials? = try .init(session: s, token: "synthetic")
        let service = try client(s, wire, current: { credentials }), flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: ProjectEditMemoryStorage()), stillCurrent: { true })
        let task = Task { await flow.load() }; await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2)
        credentials = try .init(session: session(8, epoch: 2), token: "synthetic-B"); credentials = try .init(session: session(7, epoch: 3), token: "synthetic-A-new"); wire.finish401(); await task.value
        XCTAssertEqual(flow.state, .closed); XCTAssertEqual(credentials?.session.accountID, 7); XCTAssertEqual(credentials?.session.epoch, 3)
    }
    func testPrepareCannotReplaceExplicitlyChosenRefsWithAnotherWellFormedConfirmation() async throws {
        let s = try session(), target = try origin(s), wire = Wire(); wire.prepared = Self.capture(.array([Self.selection(99)]))
        let credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"), service = try client(s, wire, current: { credentials }), storage = ProjectEditMemoryStorage()
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: storage), stillCurrent: { true }), shown = try await readySelection(flow)
        XCTAssertTrue(flow.selectSource(shown.choices.groups[0].confirmations[0], from: shown)); await flow.captureSources(try XCTUnwrap(flow.claimSourceCapture(shown)))
        XCTAssertEqual(flow.state, .failed(.invalidResponse)); XCTAssertTrue(storage.data.isEmpty); XCTAssertEqual(wire.requests.count, 2)
    }
    func testSourceDiscoveryGrantCannotBeBorrowedFromPrepareOrPublish() async throws {
        let s = try session(), target = try origin(s), wire = Wire(), credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic")
        let sets: [Set<String>] = [[ApprovedTopicReviewPath.prepare], [ApprovedTopicReleasePublicationPath.publish], []]
        for paths in sets {
            let service = try client(s, wire, paths: paths, current: { credentials }); XCTAssertFalse(service.canReadSources(session: s))
            do { _ = try await service.sources(target, session: s); XCTFail() } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testSourceChoicesRejectOwnerClaimsUnknownFieldsAndW18Kinds() throws {
        let s = try session(), target = try origin(s)
        for (key, value) in [("ownerMemberId", ProjectEditJSON.number(8)), ("publicationAuthority", .bool(true)), ("approvalProof", .bool(true)), ("extra", .bool(false))] {
            var root = try XCTUnwrap(Self.choices().object); root[key] = value
            XCTAssertThrowsError(try ApprovedMerchantReviewChoices.decode(.object(root), origin: target, session: s))
        }
        var value = try XCTUnwrap(Self.selection().object), source = try XCTUnwrap(value["source"]?.object); source["kind"] = .string("W18_PAID_CMS_SOURCE_V1"); value["source"] = .object(source)
        XCTAssertThrowsError(try ApprovedMerchantReviewSource.decode(.object(value)))
        XCTAssertThrowsError(try ApprovedMerchantReviewSource.decodeSelections(.array([Self.selection(), Self.selection()])))
        XCTAssertThrowsError(try ApprovedMerchantReviewSource.decodeSelections(.array(Array(repeating: Self.selection(), count: 33))))
    }
    func testCaptureCannotCarrySourceForAnUnrelatedCmsNode() throws {
        var selected = try XCTUnwrap(Self.selection().object); selected["memberTemplateId"] = .number(999)
        XCTAssertThrowsError(try ApprovedTopicReviewCapture.decode(Self.capture(.array([.object(selected)])), topicID: 7901, observedAuditTaskID: 3301))
    }
    func testChangingOnlyJournalCommandReferencesFailsWithoutErasingOriginalBytes() throws {
        let s = try session(), target = try origin(s), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage: storage), capture = try ApprovedTopicReviewCapture.decode(Self.capture(), topicID: 7901, observedAuditTaskID: 3301)
        _ = try journal.begin(capture, origin: target, expected: journal.read(session: s, topicID: 7901), session: s)
        let key = try XCTUnwrap(storage.data.keys.first); var root = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(storage.data[key])), records = try XCTUnwrap(root["records"]?.array), row = try XCTUnwrap(records[0].object), command = try XCTUnwrap(row["command"]?.object)
        command["sourceSelections"] = .array([Self.selection(99)]); row["command"] = .object(command); records[0] = .object(row); root["records"] = .array(records); storage.data[key] = try JSONEncoder().encode(root); let before = storage.data
        XCTAssertThrowsError(try journal.read(session: s, topicID: 7901)); XCTAssertEqual(storage.data, before)
    }
    func testPersistenceFailureBeforeReviewClaimCannotSendSelectedSourceCommand() async throws {
        let s = try session(), target = try origin(s), wire = Wire(), credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"), service = try client(s, wire, current: { credentials }), storage = ProjectEditMemoryStorage(), flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: storage), stillCurrent: { true })
        let shown = try await readySelection(flow), capture = try await captureSelected(flow, shown), confirmation = try XCTUnwrap(flow.review(capture)); storage.failWrites = true
        XCTAssertNil(flow.claim(confirmation)); XCTAssertEqual(wire.requests.count, 2); XCTAssertTrue(storage.data.isEmpty)
    }

    func testCurrentSource401ShowsUnauthorizedWhileRetainingNoInventedRequest() async throws {
        let s = try session(), target = try origin(s), wire = Wire(); wire.held = true; wire.started = expectation(description:"current source request")
        let credentials = try ApprovedTopicReviewCredentials(session:s,token:"synthetic"), service = try client(s,wire,current:{credentials}), storage = ProjectEditMemoryStorage(), flow = ApprovedTopicReviewFlow(origin:target,session:s,source:service,journal:.init(storage:storage),stillCurrent:{true})
        let task = Task { await flow.load() }; await fulfillment(of:[try XCTUnwrap(wire.started)],timeout:2); wire.finish401(); await task.value
        XCTAssertEqual(flow.state,.unauthorized); XCTAssertTrue(storage.data.isEmpty); XCTAssertEqual(wire.requests.count,1)
    }
    func testPreparedTaskVersionChangeRequiresFreshSourceSelectionWithoutSavingCommand() async throws {
        let s = try session(), target = try origin(s), wire = Wire(); var prepared = try XCTUnwrap(Self.capture().object); prepared["observedAuditTaskVersion"] = .number(1); wire.prepared = .object(prepared)
        let credentials = try ApprovedTopicReviewCredentials(session:s,token:"synthetic"), service = try client(s,wire,current:{credentials}), storage = ProjectEditMemoryStorage(), flow = ApprovedTopicReviewFlow(origin:target,session:s,source:service,journal:.init(storage:storage),stillCurrent:{true})
        let shown = try await readySelection(flow); XCTAssertTrue(flow.selectSource(shown.choices.groups[0].confirmations[0],from:shown)); await flow.captureSources(try XCTUnwrap(flow.claimSourceCapture(shown)))
        XCTAssertEqual(flow.state,.failed(.changedReview)); XCTAssertTrue(storage.data.isEmpty); XCTAssertEqual(wire.requests.count,2)
    }


    func testExactActualBackendHttpGoldenDecodesWithoutInventingApproval() throws {
        let url = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/MerchantReviewSources/choices.json")
        let envelope = try JSONDecoder().decode([String:ProjectEditJSON].self,from:Data(contentsOf:url)), fields = try XCTUnwrap(envelope["data"]), row = try XCTUnwrap(fields.object)
        let topic = try XCTUnwrap(row["topicId"]?.integer), task = try XCTUnwrap(row["observedAuditTaskId"]?.integer), s = try session()
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId":.number(Decimal(topic)),"auditTaskId":.number(Decimal(task)),"reviewState":.string("PENDING"),"published":.bool(true),"bundledTemplateIds":.array([.number(1)])]),expectedTopicID:nil)
        let pending = try ProjectEditPending(operationID:UUID(),ownerKey:s.ownerKey,identity:.init(),payload:ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(),topicID:nil,scope:.full),completedTopicID:topic,serverAcknowledged:true,bundleAcknowledgment:ack)
        let target = try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending:pending,session:s)), decoded = try ApprovedMerchantReviewChoices.decode(fields,origin:target,session:s)
        XCTAssertEqual(decoded.groups.count,1); XCTAssertEqual(decoded.groups[0].memberTemplateID,1); XCTAssertEqual(decoded.groups[0].confirmations.count,1)
        XCTAssertEqual(decoded.groups[0].confirmations[0].selection.source.kind,"MERCHANT_AI_TEMPLATE_SOURCE_V1"); XCTAssertEqual(row["publicationAuthority"],.bool(false))
    }

}
