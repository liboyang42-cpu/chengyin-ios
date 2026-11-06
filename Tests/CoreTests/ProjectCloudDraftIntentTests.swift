import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Memory-only original HTTP transport. These tests never use a live writer.
@MainActor final class ProjectCloudDraftIntentTests: XCTestCase {
    private final class Owner {
        var session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "cloud-draft-intent")
    }
    private final class Wire: HTTPTransport {
        var paths: [String] = []
        var reply: (URLRequest) throws -> Data = { _ in throw URLError(.timedOut) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            paths.append(request.url!.path)
            if request.url!.path == "/api/publish/home" {
                return (Data(#"{"code":200,"data":{"permission":{"canProPublish":false},"quota":{"themesRemaining":0}}}"#.utf8), 200)
            }
            return (try reply(request), 200)
        }
    }
    private func incomplete(_ product: ProjectEditProduct = .freeExplore) -> ProjectEditDraft {
        var draft = ProjectEditDraft(product: product); draft.name = "Unfinished cloud draft"
        draft.publishToCreative = true; return draft
    }
    private func api(_ owner: Owner, _ store: ProjectEditLocalStore, _ wire: Wire, readOnly: Bool = false) throws -> ProjectEditHTTPService {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://cloud-draft.test")!)
        let paths: Set<String> = readOnly ? [ProjectEditRequestContract.readPath] :
            ["api/topic/create", ProjectEditStoryContract.createPath, ProjectEditStoryContract.updatePath, ProjectEditRequestContract.submitPath, ProjectEditRequestContract.readPath]
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: owner.session.storageNamespace, accountID: 7, paths: paths)
        return .init(configuration: configuration, transport: wire, owner: .personal, approval: approval, store: store,
                     currentCredentials: { try? .init(session: owner.session, token: "fixture-only") })
    }
    func testIncompleteCloudSaveIsDistinctFromLocalSaveAndPublication() throws {
        for product in [ProjectEditProduct.city, .freeExplore] {
            let draft = incomplete(product)
            XCTAssertFalse(ProjectEditSubmissionIntent.ordinary.issues(draft, scope: .full, baseline: nil).isEmpty)
            let payload = try ProjectEditContract.payload(draft, topicID: nil, scope: .full, intent: .saveCloudDraft)
            XCTAssertEqual(payload["saveDraft"], .number(1)); XCTAssertEqual(payload["publishToCreative"], .number(0))
            XCTAssertNil(payload["startDate"]); XCTAssertNil(payload["endDate"]); XCTAssertNil(payload["recruitDeadline"])
            XCTAssertEqual(payload["chapters"], .array([])); XCTAssertEqual(payload["tickets"], .array([]))
            XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: nil, scope: .full))
            XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: nil, scope: .full, intent: .submitServerDraft))
        }
    }
    func testOrdinaryPayloadAndLocalPendingMaterialOmissionRemainUnchanged() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        let before = try ProjectEditContract.payload(draft, topicID: nil, scope: .full)
        draft.pendingMaterials = [.init(node: draft.chapters[0].nodes[0])]
        XCTAssertEqual(try ProjectEditContract.payload(draft, topicID: nil, scope: .full), before)
        XCTAssertNil(before["saveDraft"]); XCTAssertNil(before["pendingMaterials"])
        XCTAssertEqual(ProjectEditSubmissionIntent.from(payload: before), .ordinary)
    }
    func testIncompleteSaveNeverRelaxesProvidedDatesCategoriesReferencesOrNumbers() throws {
        for field in ["name", "date", "category", "node", "ticket", "reference"] {
            var draft = incomplete()
            switch field {
            case "name": draft.name = " "
            case "date": draft.startDate = "2030-02-31"
            case "category": draft.categoryIDs = [0]
            case "node":
                var chapter = ProjectEditChapter(); var node = ProjectEditNode(); node.longitude = "181"; node.latitude = "0"; chapter.nodes = [node]; draft.chapters = [chapter]
            case "ticket": var ticket = ProjectEditTicket(); ticket.name = "Bad price"; ticket.price = "-1"; draft.tickets = [ticket]
            default:
                var chapter = ProjectEditChapter(); chapter.blocks = [.init(kind: .node, nodeID: "missing")]; draft.chapters = [chapter]
            }
            XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: nil, scope: .full, intent: .saveCloudDraft), field)
        }
    }
    func testExistingDraftRequiresExplicitServerFactAndFullScope() throws {
        let draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        for fact in [nil, false, true] as [Bool?] {
            for scope in [ProjectEditScope.full, .whitelist, .sellingFrozen] {
                let baseline = ProjectEditSnapshot(topicID: 71, scope: scope, draft: draft, isServerDraft: fact)
                for intent in [ProjectEditSubmissionIntent.saveCloudDraft, .submitServerDraft] {
                    if fact == true && scope == .full {
                        let payload = try ProjectEditContract.payload(draft, topicID: 71, scope: scope, baseline: baseline, intent: intent)
                        XCTAssertEqual(try ProjectEditStoryContract.path(payload: payload, baseline: baseline), ProjectEditStoryContract.updatePath)
                        XCTAssertEqual(payload["saveDraft"], intent == .saveCloudDraft ? .number(1) : .number(0))
                    } else { XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: 71, scope: scope, baseline: baseline, intent: intent)) }
                }
            }
        }
    }
    func testServerDraftSubmitStillRequiresCompletenessAndExistingDatesCannotBeErased() throws {
        let draft = incomplete(), baseline = ProjectEditSnapshot(topicID: 71, draft: draft, isServerDraft: true)
        XCTAssertNoThrow(try ProjectEditContract.payload(draft, topicID: 71, scope: .full, baseline: baseline, intent: .saveCloudDraft))
        XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: 71, scope: .full, baseline: baseline, intent: .submitServerDraft))
        var dated = baseline; dated.draft.startDate = "2030-05-01"
        XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: 71, scope: .full, baseline: dated, intent: .saveCloudDraft))
    }
    func testMalformedSaveFlagsOrCreativeBroadcastCannotPassWireValidation() throws {
        let payload = try ProjectEditContract.payload(incomplete(), topicID: nil, scope: .full, intent: .saveCloudDraft)
        for flag in [ProjectEditJSON.bool(true), .string("1"), .number(2), .null, .number(0)] {
            var changed = payload; changed["saveDraft"] = flag
            XCTAssertThrowsError(try ProjectEditStoryContract.validatePayload(changed))
        }
        var changed = payload; changed["publishToCreative"] = .number(1)
        XCTAssertThrowsError(try ProjectEditStoryContract.validatePayload(changed))
    }
    func testDraftFactHydrationIsBooleanOnlyAndLegacySnapshotDecodesWithoutIt() throws {
        let base: [String: ProjectEditJSON] = ["topic": .object(["id": .number(71), "productType": .number(2), "updateTime": .string("r1")]), "editScope": .string("FULL"), "chapters": .array([]), "tickets": .array([])]
        func decode(_ fact: ProjectEditJSON?) throws -> ProjectEditSnapshot {
            var body = base; body["isDraft"] = fact
            return try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": .object(body)]), expectedTopicID: 71, owner: .personal)
        }
        XCTAssertNil(try decode(nil).isServerDraft); XCTAssertNil(try decode(.null).isServerDraft)
        XCTAssertEqual(try decode(.bool(true)).isServerDraft, true); XCTAssertEqual(try decode(.bool(false)).isServerDraft, false)
        for value in [ProjectEditJSON.number(1), .string("true"), .object([:])] { XCTAssertThrowsError(try decode(value)) }
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ProjectEditSnapshot(draft: incomplete()))) as! [String: Any]
        encoded.removeValue(forKey: "isServerDraft")
        XCTAssertNil(try JSONDecoder().decode(ProjectEditSnapshot.self, from: JSONSerialization.data(withJSONObject: encoded)).isServerDraft)
    }
    func testCloudSaveCannotClaimAContradictoryOriginalV2Result() throws {
        let owner = Owner(), draft = incomplete(.city)
        let payload = try ProjectEditContract.payload(draft, topicID: nil, scope: .full, intent: .saveCloudDraft)
        var pending = ProjectEditPending(operationID: UUID(), ownerKey: owner.session.ownerKey, identity: try .init(), payload: payload, baseline: .init(draft: draft))
        let sent = try ProjectEditRequestContract.Submit(operationID: pending.operationID, originalPath: ProjectEditStoryContract.createPath, payload: payload)
        pending.serverRequest = sent
        for state in ["DRAFT", "PENDING", "ESCALATED", "NOT_REQUIRED"] {
            for published in [false, true] {
                let raw: ProjectEditJSON = .object(["topicId": .number(71), "reviewState": .string(state), "published": .bool(published), "auditTaskId": .number(11), "bundledTemplateIds": .array([])])
                let response = try projectOriginalTestReceipt(sent, original: raw)
                let outcome = ProjectEditHTTPService.decodeRequestReceipt(response, status: 200, operation: pending)
                if state == "DRAFT" && !published { if case .committedReceipt = outcome {} else { XCTFail("Exact original cloud draft fact was lost") } }
                else { XCTAssertEqual(outcome, .unknown) }
            }
        }
    }
    func testSubmitServerDraftCannotUseAStillDraftOriginalReceipt() throws {
        let owner = Owner(), draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        let baseline = ProjectEditSnapshot(topicID: 71, draft: draft, isServerDraft: true)
        let payload = try ProjectEditContract.payload(draft, topicID: 71, scope: .full, baseline: baseline, intent: .submitServerDraft)
        var pending = ProjectEditPending(operationID: UUID(), ownerKey: owner.session.ownerKey, identity: try .init(topicID: 71), payload: payload, baseline: baseline)
        let sent = try ProjectEditRequestContract.Submit(operationID: pending.operationID, originalPath: ProjectEditStoryContract.updatePath, payload: payload)
        pending.serverRequest = sent
        let raw: ProjectEditJSON = .object(["topicId": .number(71), "reviewState": .string("DRAFT"), "published": .bool(false), "bundledTemplateIds": .array([])])
        XCTAssertEqual(ProjectEditHTTPService.decodeRequestReceipt(try projectOriginalTestReceipt(sent, original: raw), status: 200, operation: pending), .unknown)
    }
    func testCloudEnvelopeIsDurableBeforeWriterEvenWhenOnlineQuotaIsZero() async throws {
        let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), draft = incomplete()
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: try api(owner, store, wire), store: store, currentSession: { owner.session })
        wire.reply = { request in
            XCTAssertEqual(request.url?.path, "/api/topic/edit-requests/submit")
            let sent = try JSONDecoder().decode(ProjectEditRequestContract.Submit.self, from: XCTUnwrap(request.httpBody))
            let identity = try XCTUnwrap(store.activeIdentity(session: owner.session, product: draft.product, owner: draft.owner))
            let durable = try XCTUnwrap(store.pending(session: owner.session, identity: identity))
            XCTAssertEqual(durable.serverRequest, sent); XCTAssertEqual(durable.dispatchStarted, true)
            XCTAssertEqual(try projectOriginalTestPayload(request)["saveDraft"], .number(1))
            return try projectOriginalTestReceipt(sent)
        }
        await coordinator.load(); coordinator.prepare(draft, intent: .saveCloudDraft)
        let review = try XCTUnwrap(coordinator.confirmation); XCTAssertEqual(review.intent, .saveCloudDraft)
        await coordinator.confirm(review)
        XCTAssertTrue(coordinator.savedCloudDraft); XCTAssertEqual(coordinator.state, .acknowledged)
        XCTAssertEqual(wire.paths.filter { $0.contains("/submit") }.count, 1)
        XCTAssertFalse(wire.paths.contains("/api/topic/create"))
    }
    func testLostResponseRestartUsesOnlyOriginalReadAndRetainsCloudFactOnLaterFailure() async throws {
        let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), draft = incomplete()
        let first = ProjectEditCoordinator(initial: .init(draft: draft), service: try api(owner, store, wire), store: store, currentSession: { owner.session })
        await first.load(); first.prepare(draft, intent: .saveCloudDraft); await first.confirm(try XCTUnwrap(first.confirmation))
        XCTAssertEqual(first.state, .unknown); XCTAssertFalse(first.savedCloudDraft)
        let pending = try XCTUnwrap(first.pending), sent = try XCTUnwrap(pending.serverRequest)
        owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: owner.session.storageNamespace)
        let restarted = ProjectEditCoordinator(initial: .init(draft: draft), service: try api(owner, store, wire, readOnly: true), store: store, currentSession: { owner.session })
        let writes = wire.paths.filter { $0.contains("/submit") }.count
        await restarted.load(); XCTAssertTrue(restarted.isLocked); XCTAssertFalse(restarted.savedCloudDraft)
        wire.reply = { request in XCTAssertEqual(request.url?.path, "/api/topic/edit-requests/read"); return try projectOriginalTestReceipt(sent) }
        await restarted.checkOutcome(); XCTAssertTrue(restarted.savedCloudDraft); XCTAssertEqual(restarted.pending?.completedTopicID, 71)
        wire.reply = { _ in throw URLError(.notConnectedToInternet) }
        await restarted.checkOutcome(); XCTAssertTrue(restarted.savedCloudDraft); XCTAssertEqual(restarted.state, .acknowledged)
        XCTAssertEqual(wire.paths.filter { $0.contains("/submit") }.count, writes)
        XCTAssertEqual(restarted.pending?.serverRequest, sent)
    }
    func testCloudReceiptIsHiddenAfterAccountSwitchAndOldDurableRecordRemains() async throws {
        let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), draft = incomplete()
        wire.reply = { request in try projectOriginalTestReceipt(JSONDecoder().decode(ProjectEditRequestContract.Submit.self, from: XCTUnwrap(request.httpBody))) }
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: try api(owner, store, wire), store: store, currentSession: { owner.session })
        await coordinator.load(); coordinator.prepare(draft, intent: .saveCloudDraft); await coordinator.confirm(try XCTUnwrap(coordinator.confirmation))
        let oldSession = owner.session, pending = try XCTUnwrap(coordinator.pending); XCTAssertTrue(coordinator.savedCloudDraft)
        owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: oldSession.storageNamespace)
        XCTAssertFalse(coordinator.savedCloudDraft); coordinator.synchronizeSession(); XCTAssertNil(coordinator.pending)
        XCTAssertEqual(try store.pending(session: oldSession, identity: pending.identity), pending)
    }
}
