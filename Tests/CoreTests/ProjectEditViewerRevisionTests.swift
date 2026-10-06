import XCTest
@testable import QuestifyCore

@MainActor final class ProjectEditViewerRevisionTests: XCTestCase {
    func testViewerRevisionFencesRuntimeWhileKeepingExactHistoricalOwnerEnvelope() throws {
        let original = try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"source"), newer = try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"source",viewerRevision:2)
        XCTAssertNotEqual(original,newer); XCTAssertEqual(original.ownerKey,newer.ownerKey)
        let draft = ProjectEditSyntheticFixtures.draft(), id = try ProjectEditDraftIdentity(), now = Date(timeIntervalSince1970:42), encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let a = try encoder.encode(ProjectEditEnvelope(session:original,identity:id,draft:draft,now:now)), b = try encoder.encode(ProjectEditEnvelope(session:newer,identity:id,draft:draft,now:now))
        XCTAssertEqual(a,b); XCTAssertFalse(String(decoding:b,as:UTF8.self).contains("viewerRevision"))
        let storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage:storage); try store.save(draft,session:original,identity:id)
        guard case .ready(let restored) = store.load(session:newer,identity:id,baseline:draft) else { return XCTFail("Same owner's local draft must remain restorable") }
        XCTAssertEqual(restored.draft,draft)
    }
    func testStaleConfirmationCannotSubmitAfterUnobservedViewerABA() async throws {
        var current = try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"source",viewerRevision:1)
        let service = ProjectEditSyntheticService(), store = ProjectEditLocalStore(storage:ProjectEditMemoryStorage()), draft = ProjectEditSyntheticFixtures.draft()
        let coordinator = ProjectEditCoordinator(initial:.init(draft:draft),service:service,store:store,currentSession:{current})
        await coordinator.load(); coordinator.prepare(draft); let old = try XCTUnwrap(coordinator.confirmation)
        current = try .init(accountID:7,epoch:1,storageNamespace:"source",viewerRevision:3)
        await coordinator.confirm(old); XCTAssertTrue(service.submissions.isEmpty); XCTAssertNil(coordinator.confirmation)
        await coordinator.load(); coordinator.prepare(draft); await coordinator.confirm(try XCTUnwrap(coordinator.confirmation)); XCTAssertEqual(service.submissions.count,1)
    }
    func testProjectGrantGenerationChangesRuntimeSessionButNeverDurableOwnerOrEnvelope() throws {
        let a = try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"source",viewerRevision:2,configurationRevision:3)
        let b = try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"source",viewerRevision:2,configurationRevision:5)
        XCTAssertNotEqual(a,b); XCTAssertEqual(a.ownerKey,b.ownerKey)
        let draft = ProjectEditSyntheticFixtures.draft(), identity = try ProjectEditDraftIdentity(), now = Date(timeIntervalSince1970:42)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let old = try encoder.encode(ProjectEditEnvelope(session:a,identity:identity,draft:draft,now:now)), new = try encoder.encode(ProjectEditEnvelope(session:b,identity:identity,draft:draft,now:now))
        XCTAssertEqual(old,new); XCTAssertFalse(String(decoding:new,as:UTF8.self).contains("configurationRevision"))
    }

}
