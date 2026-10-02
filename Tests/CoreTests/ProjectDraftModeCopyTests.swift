import XCTest
@testable import QuestifyCore

@MainActor final class ProjectDraftModeCopyTests: XCTestCase {
    func testCopyPreservesSourceAndSwitchesTicketWireMode() throws {
        var source = ProjectEditSyntheticFixtures.draft(); source.preserved["publishMode"] = .string("ai_simple")
        let copy = try ProjectDraftModeCopy.copy(source, to: .freeExplore)
        XCTAssertEqual(source.product, .city); XCTAssertEqual(copy.product, .freeExplore)
        XCTAssertEqual(source.preserved["publishMode"], .string("ai_simple"))
        XCTAssertEqual(copy.preserved["publishMode"], .string("pro"))
        XCTAssertEqual(copy.chapters, source.chapters); XCTAssertEqual(copy.tickets, source.tickets)
        let body = try ProjectEditContract.payload(copy, topicID: nil, scope: .full)
        XCTAssertEqual(body["tickets"]?.array?.first?.object?["mode"], .number(2)); XCTAssertNil(body["id"])
    }
    func testMerchantAndSameModeCannotCopy() {
        var source = ProjectEditSyntheticFixtures.draft(); source.owner = .merchant
        XCTAssertThrowsError(try ProjectDraftModeCopy.copy(source, to: .freeExplore))
        source.owner = .personal; XCTAssertThrowsError(try ProjectDraftModeCopy.copy(source, to: .city))
    }
    func testCoordinatorUsesIndependentIdentityAndPreservesOriginal() async throws {
        let session = try ProjectEditSession(accountID: 1, epoch: 1, storageNamespace: "fixture")
        let storage = ProjectEditMemoryStorage(), draft = ProjectEditSyntheticFixtures.draft()
        let root = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditDisabledService(), store: .init(storage: storage), currentSession: { session })
        await root.load(); let originalID = root.identity
        let child = try root.copyForMode(draft, to: .freeExplore); await child.load()
        XCTAssertNotEqual(child.identity, originalID); XCTAssertNil(child.identity?.topicID)
        XCTAssertEqual(root.snapshot?.draft, draft); XCTAssertEqual(child.snapshot?.draft.product, .freeExplore)
        XCTAssertFalse(child.canSubmit); XCTAssertFalse(storage.data.isEmpty)
    }
    func testCopiedDraftDoesNotCrossAccountEpoch() async throws {
        var session = try ProjectEditSession(accountID: 1, epoch: 1, storageNamespace: "fixture")
        let draft = ProjectEditSyntheticFixtures.draft()
        let root = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditDisabledService(), store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session })
        await root.load(); let child = try root.copyForMode(draft, to: .freeExplore)
        session = try ProjectEditSession(accountID: 2, epoch: 2, storageNamespace: "fixture")
        await child.load(); XCTAssertNil(child.snapshot); XCTAssertEqual(child.state, .blocked)
    }
    func testLocalSimulationNeverCreatesPublicationHandoff() async throws {
        let session = try ProjectEditSession(accountID: 1, epoch: 1, storageNamespace: "fixture")
        let draft = ProjectEditSyntheticFixtures.draft()
        let root = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session })
        await root.load(); root.prepare(draft); await root.confirm(try XCTUnwrap(root.confirmation))
        XCTAssertEqual(root.state, .simulated)
        XCTAssertNil(PublishingSubmissionHandoff(pending: root.pending, draft: draft))
    }
}
