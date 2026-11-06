import Foundation
import XCTest
@testable import Questify

@MainActor final class ProjectCloudDraftReviewFlowTests: XCTestCase {
    private final class Owner {
        var session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "cloud-draft-model")
    }
    private final class Wire: HTTPTransport {
        var paths: [String] = []
        var loseResponse = false
        var original: ProjectEditRequestContract.Submit?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            paths.append(request.url!.path)
            if request.url!.path == "/api/publish/home" {
                return (Data(#"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":3}}}"#.utf8), 200)
            }
            if request.url!.path == "/api/topic/edit-requests/submit" {
                original = try JSONDecoder().decode(ProjectEditRequestContract.Submit.self, from: XCTUnwrap(request.httpBody))
                if loseResponse { throw URLError(.timedOut) }
            } else { XCTAssertEqual(request.url!.path, "/api/topic/edit-requests/read") }
            let sent = try XCTUnwrap(original)
            let body: [String: Any] = ["protocolVersion": sent.protocolVersion, "requestId": sent.requestId,
                "originalPath": sent.originalPath, "payloadSHA256": sent.payloadSHA256, "state": "COMMITTED",
                "postProcessing": "NOT_RECONCILED", "originalResult": 71]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": body]), 200)
        }
    }
    private func model(_ owner: Owner, _ wire: Wire, _ store: ProjectEditLocalStore, draft: ProjectEditDraft, readOnly: Bool = false) throws -> ProjectEditModel {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://cloud-model.test")!)
        let paths: Set<String> = readOnly ? [ProjectEditRequestContract.readPath] : ["api/topic/create", ProjectEditRequestContract.submitPath, ProjectEditRequestContract.readPath]
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: owner.session.storageNamespace, accountID: 7, paths: paths)
        let service = ProjectEditHTTPService(configuration: configuration, transport: wire, owner: .personal, approval: approval, store: store, currentCredentials: { try? .init(session: owner.session, token: "fixture-only") })
        return .init(coordinator: .init(initial: .init(draft: draft), service: service, store: store, currentSession: { owner.session }))
    }
    func testLocalSaveDoesNotBecomeCloudSaveOrSendARequest() async throws {
        let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let editor = try model(owner, wire, store, draft: ProjectEditSyntheticFixtures.draft(product: .freeExplore))
        await editor.load(); editor.saveLocal()
        XCTAssertTrue(wire.paths.isEmpty); XCTAssertNil(editor.coordinator.pending)
        XCTAssertFalse(editor.coordinator.savedCloudDraft); XCTAssertNil(editor.submittedHandoff)
        XCTAssertNil(editor.confirmation)
    }
    func testIntentChangeInvalidatesOldSheetAndKeepsNewImmutableCloudPayload() async throws {
        let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let editor = try model(owner, wire, store, draft: ProjectEditSyntheticFixtures.draft(product: .freeExplore))
        await editor.load(); editor.review(); let ordinary = try XCTUnwrap(editor.confirmation)
        editor.review(intent: .saveCloudDraft); let cloud = try XCTUnwrap(editor.confirmation)
        XCTAssertNotEqual(ordinary.id, cloud.id); XCTAssertEqual(cloud.intent, .saveCloudDraft)
        XCTAssertNil(ordinary.payload["saveDraft"]); XCTAssertEqual(cloud.payload["saveDraft"], .number(1))
        XCTAssertFalse(editor.reviewIsCurrent(ordinary)); XCTAssertTrue(editor.reviewIsCurrent(cloud))
        await editor.submit(ordinary); editor.cancelReview(ordinary)
        XCTAssertTrue(wire.paths.isEmpty); XCTAssertEqual(editor.confirmation?.id, cloud.id)
    }
    func testIncompleteCloudSaveUsesOriginalReviewAndDoesNotOpenPublicationHandoff() async throws {
        let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        var draft = ProjectEditDraft(product: .freeExplore); draft.name = "Not yet publishable"
        let editor = try model(owner, wire, store, draft: draft)
        await editor.load(); editor.review(); XCTAssertNil(editor.confirmation)
        editor.review(intent: .saveCloudDraft); let cloud = try XCTUnwrap(editor.confirmation)
        XCTAssertTrue(editor.reviewIsCurrent(cloud)); XCTAssertTrue(editor.reviewLocalSaveConfirmed)
        await editor.submit(cloud)
        XCTAssertTrue(editor.coordinator.savedCloudDraft); XCTAssertEqual(editor.coordinator.pending?.completedTopicID, 71)
        XCTAssertNil(editor.submittedHandoff); XCTAssertFalse(editor.canReview)
        XCTAssertEqual(wire.paths.filter { $0.contains("/submit") }.count, 1)
    }
    func testRestartReadRecoversCloudSaveWithoutAutomaticSubmitOrPublicationHandoff() async throws {
        let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        let editor = try model(owner, wire, store, draft: draft); await editor.load()
        wire.loseResponse = true; editor.review(intent: .saveCloudDraft); await editor.submit(try XCTUnwrap(editor.confirmation))
        XCTAssertTrue(editor.coordinator.isLocked); let original = try XCTUnwrap(editor.coordinator.pending)
        owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: owner.session.storageNamespace)
        let reentered = try model(owner, wire, store, draft: draft, readOnly: true), paths = wire.paths
        await reentered.load(); XCTAssertEqual(wire.paths, paths); XCTAssertTrue(reentered.coordinator.isLocked)
        await reentered.check()
        XCTAssertTrue(reentered.coordinator.savedCloudDraft); XCTAssertNil(reentered.submittedHandoff)
        XCTAssertEqual(reentered.coordinator.pending?.operationID, original.operationID)
        XCTAssertEqual(wire.paths.last, "/api/topic/edit-requests/read")
        XCTAssertEqual(wire.paths.filter { $0.contains("/submit") }.count, 1)
    }
    func testCloudReviewCannotDispatchAfterAccountOrRawDraftChange() async throws {
        for change in ["account", "draft"] {
            let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
            let editor = try model(owner, wire, store, draft: ProjectEditSyntheticFixtures.draft(product: .freeExplore))
            await editor.load(); editor.review(intent: .saveCloudDraft); let cloud = try XCTUnwrap(editor.confirmation)
            if change == "account" { owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: owner.session.storageNamespace) }
            else { editor.draft.name += " changed" }
            XCTAssertFalse(editor.reviewIsCurrent(cloud)); await editor.submit(cloud)
            XCTAssertTrue(wire.paths.isEmpty); XCTAssertNil(editor.submittedHandoff)
        }
    }
}
