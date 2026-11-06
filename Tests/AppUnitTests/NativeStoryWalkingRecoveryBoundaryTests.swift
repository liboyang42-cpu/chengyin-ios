import Foundation
import XCTest
@testable import Questify

/// Recovery regressions require the separately reviewed shared contract proposal.
@MainActor final class NativeStoryWalkingRecoveryBoundaryTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "walking-recovery-test")
    }
    private func setup() async -> (ProjectEditModel, Owner, ProjectEditMemoryStorage, ProjectEditSyntheticService) {
        let owner = Owner(), storage = ProjectEditMemoryStorage()
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.preserved["themeRuntimeConfig"] = .string(#"{"schemaVersion":1,"walkingNavigation":{"schemaVersion":2,"authorityTTLSeconds":60,"nodes":[]}}"#)
        let snapshot = ProjectEditSnapshot(topicID: 101, scope: .full, draft: draft)
        let service = ProjectEditSyntheticService(snapshot: snapshot)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service,
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load()
        return (model, owner, storage, service)
    }
    func testRecoveredDraftUsesOriginalLocalPersistenceWithoutSubmitting() async throws {
        let (model, owner, _, service) = await setup()
        defer { withExtendedLifetime(owner) {} }
        let lease = try XCTUnwrap(model.captureStarterLease())
        var editor = try NativeStoryWalkingAuthorDraft(draft: model.draft)
        editor.ttl = "90"
        let next = try editor.applying(to: model.draft)
        XCTAssertTrue(model.persistLocalChange(next, lease: lease))
        XCTAssertEqual(try NativeStoryWalkingAuthorDraft(draft: model.draft).ttl, "90")
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testFailedLocalWriteKeepsOriginalDraftAndExplicitRetryUsesSameLease() async throws {
        let (model, owner, storage, service) = await setup()
        defer { withExtendedLifetime(owner) {} }
        let lease = try XCTUnwrap(model.captureStarterLease())
        let before = ProjectEditPendingMaterials.exactData(model.draft)
        var editor = try NativeStoryWalkingAuthorDraft(draft: model.draft)
        editor.ttl = "90"
        let next = try editor.applying(to: model.draft)
        storage.failWrites = true
        XCTAssertFalse(model.persistLocalChange(next, lease: lease))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertTrue(service.submissions.isEmpty)
        storage.failWrites = false
        XCTAssertTrue(model.persistLocalChange(next, lease: lease))
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testRetiredLeaseCannotApplyRecoveredWalkingDraft() async throws {
        let (model, owner, storage, service) = await setup()
        defer { withExtendedLifetime(owner) {} }
        let lease = try XCTUnwrap(model.captureStarterLease())
        var editor = try NativeStoryWalkingAuthorDraft(draft: model.draft)
        editor.ttl = "90"
        let next = try editor.applying(to: model.draft)
        let before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        model.invalidateStarterLease()
        XCTAssertFalse(model.persistLocalChange(next, lease: lease))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertEqual(storage.data, saved)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testRestoredServerContractCarriesTheExactFullWalkingField() async throws {
        let (model, owner, _, service) = await setup()
        defer { withExtendedLifetime(owner) {} }
        let baseline = ProjectEditSnapshot(topicID: 101, scope: .full, draft: model.draft)
        let payload = try ProjectEditContract.payload(model.draft, topicID: 101, scope: .full, baseline: baseline)
        XCTAssertNotNil(model.draft.preserved["themeRuntimeConfig"])
        XCTAssertEqual(payload["themeRuntimeConfig"], model.draft.preserved["themeRuntimeConfig"])
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testAuthoritativeTopLevelCarrierWinsAndPreservesExactBytes() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        let original = " {\"schemaVersion\":1,\"future\":{\"note\":\" untouched \"}} "
        try ProjectEditStoryContract.restoreMetadata(&draft, body: ["themeRuntimeConfig": .string(original)],
            topic: ["themeRuntimeConfigJson": .string("fallback must not win")])
        XCTAssertEqual(draft.preserved["themeRuntimeConfig"], .string(original))
    }
    func testAuthoritativeNullDoesNotFallBackToStaleTopicField() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.preserved["themeRuntimeConfig"] = .string("old")
        try ProjectEditStoryContract.restoreMetadata(&draft, body: ["themeRuntimeConfig": .null],
            topic: ["themeRuntimeConfigJson": .string("stale")])
        XCTAssertNil(draft.preserved["themeRuntimeConfig"])
    }
    func testMalformedAuthoritativeCarrierFailsWithoutUsingFallback() {
        var draft = ProjectEditSyntheticFixtures.draft()
        XCTAssertThrowsError(try ProjectEditStoryContract.restoreMetadata(&draft,
            body: ["themeRuntimeConfig": .object([:])], topic: ["themeRuntimeConfigJson": .string("fallback")]))
    }
}
