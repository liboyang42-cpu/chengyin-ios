import XCTest
@testable import QuestifyCore

final class ProjectTeamConfigurationTests: XCTestCase {
    func testUnrelatedNameEditRetainsExistingEnabledTeamAndMaximumInActualPayload() throws {
        for mode in [1, 2] { for maximum in 2...4 {
            let original = try readback(mode: .number(Decimal(mode)), maximum: .number(Decimal(maximum)))
            var draft = original; draft.name += " revised"
            let payload = try ProjectEditContract.payload(draft, topicID: 71, scope: .full, baseline: .init(topicID: 71, draft: original))
            XCTAssertEqual(payload["teamMode"], .number(Decimal(mode)))
            XCTAssertEqual(payload["teamMaxMembers"], .number(Decimal(maximum)))
            XCTAssertEqual(draft.preserved, original.preserved)
        } }
    }
    func testBothProductsRetainKnownSettingsWithoutProductNormalization() throws {
        for product in ProjectEditProduct.allCases {
            var draft = ProjectEditSyntheticFixtures.draft(product: product)
            draft.preserved["teamMode"] = .number(2); draft.preserved["teamMaxMembers"] = .number(3)
            let payload = try ProjectEditContract.payload(draft, topicID: nil, scope: .full)
            XCTAssertEqual(payload["teamMode"], .number(2)); XCTAssertEqual(payload["teamMaxMembers"], .number(3))
        }
    }
    func testMissingNullAndMixedShapesRoundTripAndNoOpExactly() throws {
        for mode in [nil, ProjectEditJSON.null, .number(0)] { for maximum in [nil, ProjectEditJSON.null, .number(4)] {
            let draft = try readback(mode: mode, maximum: maximum)
            XCTAssertEqual(draft.preserved["teamMode"], mode); XCTAssertEqual(draft.preserved["teamMaxMembers"], maximum)
            let before = ProjectEditPendingMaterials.exactData(draft)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try ProjectTeamConfiguration(draft: draft).applying(to: draft)), before)
            let wire = try ProjectEditContract.payload(draft, topicID: 71, scope: .full)
            XCTAssertEqual(wire["teamMode"], mode); XCTAssertEqual(wire["teamMaxMembers"], maximum)
        } }
    }
    func testExplicitChangeTouchesOnlyTheChangedTeamField() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.preserved["opaqueFuture"] = .object(["e\u{301}": .string("keep")])
        var buffer = ProjectTeamConfiguration(draft: draft); buffer.selectMode(.afterRegistration)
        var expected = draft; expected.preserved["teamMode"] = .number(2)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try buffer.applying(to: draft)), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertNil(try buffer.applying(to: draft).preserved["teamMaxMembers"])
    }
    func testCapacityChangeAndOffModeDoNotRewriteEachOtherOrTickets() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.preserved["teamMode"] = .number(1); draft.preserved["teamMaxMembers"] = .number(2)
        var buffer = ProjectTeamConfiguration(draft: draft); buffer.selectMaximum(3)
        let changed = try buffer.applying(to: draft); XCTAssertEqual(changed.preserved["teamMode"], .number(1)); XCTAssertEqual(changed.tickets, draft.tickets)
        var off = ProjectTeamConfiguration(draft: changed); off.selectMode(.off)
        XCTAssertEqual(try off.applying(to: changed).preserved["teamMaxMembers"], .number(3))
    }
    func testChangeThenReturnToOriginalPreservesMissingAndNull() throws {
        for raw in [nil, ProjectEditJSON.null] {
            let draft = try readback(mode: raw, maximum: raw); var buffer = ProjectTeamConfiguration(draft: draft)
            buffer.selectMode(.atRegistration); buffer.selectMode(.off); buffer.selectMaximum(2); buffer.selectMaximum(4)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try buffer.applying(to: draft)), ProjectEditPendingMaterials.exactData(draft))
        }
    }
    func testUnknownValuesTypesAndOutOfBoundsAreRetainedAndBlockFullPayload() throws {
        let values: [ProjectEditJSON] = [.string("1"), .bool(true), .number(-1), .number(5), .number(1.5), .array([]), .object(["future": .number(1)])]
        for key in ProjectTeamConfiguration.fields { for raw in values {
            var draft = ProjectEditSyntheticFixtures.draft(); draft.preserved[key] = raw
            let before = ProjectEditPendingMaterials.exactData(draft); var buffer = ProjectTeamConfiguration(draft: draft)
            XCTAssertTrue(buffer.readOnly); buffer.selectMode(.off); buffer.selectMaximum(4)
            XCTAssertThrowsError(try buffer.applying(to: draft)); XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: nil, scope: .full))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), before)
            let restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(draft)); XCTAssertEqual(restored.preserved[key], raw)
        } }
    }
    func testInvalidCapacitySelectionIsRejectedWithoutMutation() throws {
        let draft = ProjectEditSyntheticFixtures.draft(); var buffer = ProjectTeamConfiguration(draft: draft)
        for value in [Int.min, 0, 1, 5, Int.max] { buffer.selectMaximum(value); XCTAssertEqual(buffer.maximum, 4) }
        XCTAssertEqual(try buffer.applying(to: draft), draft)
    }
    func testWhitelistPayloadRemainsTheExactOldShapeEvenForUnknownSettings() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.preserved["teamMode"] = .string("future")
        let payload = try ProjectEditContract.payload(draft, topicID: 71, scope: .whitelist)
        XCTAssertEqual(Set(payload.keys), Set(ProjectEditContract.whitelist + ["id"]))
        for field in ProjectTeamConfiguration.fields { XCTAssertNil(payload[field]) }
    }
    func testNonCityExplicitEditsAreRejectedButDraftIsPreserved() throws {
        let draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore); var buffer = ProjectTeamConfiguration(draft: draft); buffer.selectMode(.atRegistration)
        XCTAssertThrowsError(try buffer.applying(to: draft))
    }
    func testStaleAndCanonicalEquivalentDraftBytesRejectApply() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.name = "e\u{301}"; var buffer = ProjectTeamConfiguration(draft: draft); buffer.selectMode(.atRegistration)
        draft.name = "é"; XCTAssertThrowsError(try buffer.applying(to: draft))
    }
    func testOldLocalEnvelopeCannotEraseFreshSavedTeamSettings() throws {
        var fresh = ProjectEditSyntheticFixtures.draft(); fresh.preserved["teamMode"] = .number(1); fresh.preserved["teamMaxMembers"] = .number(3)
        let baseline = ProjectEditSnapshot(topicID: 71, draft: fresh)
        for key in ProjectTeamConfiguration.fields {
            var old = fresh; old.preserved.removeValue(forKey: key); let before = ProjectEditPendingMaterials.exactData(old)
            XCTAssertTrue(ProjectTeamConfiguration(draft: old, baseline: baseline).readOnly)
            XCTAssertThrowsError(try ProjectEditContract.payload(old, topicID: 71, scope: .full, baseline: baseline))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(old), before)
        }
    }
    @MainActor func testPreparedReviewFreezesBothSettingsWithoutSubmitting() async throws {
        let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "team-config")
        var draft = ProjectEditSyntheticFixtures.draft(); draft.preserved["teamMode"] = .number(1); draft.preserved["teamMaxMembers"] = .number(2)
        let initial = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: .init(draft: draft))
        let coordinator = ProjectEditCoordinator(initial: initial, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session })
        await coordinator.load(); draft.name += " revision"; coordinator.prepare(draft)
        let review = try XCTUnwrap(coordinator.confirmation)
        XCTAssertEqual(review.payload["teamMode"], .number(1)); XCTAssertEqual(review.payload["teamMaxMembers"], .number(2)); XCTAssertTrue(service.submissions.isEmpty)
    }
    private func readback(mode: ProjectEditJSON?, maximum: ProjectEditJSON?) throws -> ProjectEditDraft {
        var topic: [String: ProjectEditJSON] = ["id": .number(71), "productType": .number(1), "name": .string("Fixture route"),
            "description": .string("Fixture story"), "imgUrl": .string("fixture://cover"), "categoryIds": .string("7"),
            "updateTime": .string("r1"), "startDate": .string("2030-05-01"), "endDate": .string("2030-05-30")]
        topic["teamMode"] = mode; topic["teamMaxMembers"] = maximum
        let node: ProjectEditJSON = .object(["id": .number(2), "name": .string("Fixture stop"), "longitude": .string("121"), "latitude": .string("31")])
        let chapter: ProjectEditJSON = .object(["id": .number(1), "description": .string("Fixture chapter"), "cmsTopicNodeList": .array([node])])
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object(["editScope": .string("FULL"), "topic": .object(topic), "chapters": .array([chapter]), "tickets": .array([])])])
        return try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 71, owner: .personal).draft
    }
}
