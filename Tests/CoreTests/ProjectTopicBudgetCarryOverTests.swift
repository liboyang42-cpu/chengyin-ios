import XCTest
@testable import QuestifyCore

final class ProjectTopicBudgetCarryOverTests: XCTestCase {
    private func baseline(_ raw: ProjectEditJSON? = .number(7777), product: ProjectEditProduct = .city) -> ProjectEditSnapshot {
        var draft = ProjectEditSyntheticFixtures.draft(product: product); draft.baseRevision = "saved-r1"; draft.preserved["xpBudget"] = raw
        return .init(topicID: 71, draft: draft)
    }
    func testAuthoritativeReadbackRetainsBudgetAndUnrelatedEditCarriesItExactly() throws {
        let original = try readback(.number(7777)); var draft = original.draft; draft.name += " updated"
        XCTAssertEqual(draft.preserved["xpBudget"], .number(7777))
        XCTAssertEqual(try ProjectEditContract.payload(draft, topicID: 71, scope: .full, baseline: original)["xpBudget"], .number(7777))
    }
    func testBothProductsAndInt32BoundaryRetainUnchangedSavedBudget() throws {
        for product in ProjectEditProduct.allCases { for number in [1, 3000, 7777, Int(Int32.max)] {
            let original = baseline(.number(Decimal(number)), product: product); var draft = original.draft; draft.description += " revised"
            XCTAssertEqual(try ProjectEditContract.payload(draft, topicID: 71, scope: .full, baseline: original)["xpBudget"], .number(Decimal(number)))
        } }
    }
    func testMissingAndNullExistingValuesStayDistinctAndUnchanged() throws {
        for raw in [nil, ProjectEditJSON.null] {
            let original = try readback(raw), before = ProjectEditPendingMaterials.exactData(original.draft)
            XCTAssertEqual(original.draft.preserved["xpBudget"], raw)
            XCTAssertEqual(try ProjectEditContract.payload(original.draft, topicID: 71, scope: .full, baseline: original)["xpBudget"], raw)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(original.draft), before)
        }
        var absent = baseline(nil).draft; absent.preserved["xpBudget"] = .null
        XCTAssertFalse(ProjectTopicBudgetCarryOver.allows(absent, topicID: 71, baseline: baseline(nil)))
    }
    func testBudgetChangesMissingOldLocalAndExplicitNullCannotResetSavedValue() throws {
        let original = baseline()
        for raw in [nil, ProjectEditJSON.null, .number(3000), .number(7778)] {
            var draft = original.draft; draft.preserved["xpBudget"] = raw
            let before = ProjectEditPendingMaterials.exactData(draft)
            XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: 71, scope: .full, baseline: original))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), before)
        }
    }
    func testPositiveBudgetRequiresAnExistingMatchingFullBaseline() throws {
        let original = baseline()
        XCTAssertFalse(ProjectTopicBudgetCarryOver.allows(original.draft, topicID: 71, baseline: nil))
        for other in [ProjectEditSnapshot(topicID: 72, draft: original.draft), .init(draft: original.draft), .init(topicID: 71, scope: .whitelist, draft: original.draft)] {
            XCTAssertFalse(ProjectTopicBudgetCarryOver.allows(original.draft, topicID: 71, baseline: other))
        }
        XCTAssertFalse(ProjectTopicBudgetCarryOver.allows(original.draft, topicID: 0, baseline: original))
    }
    func testOwnerProductAndExactRevisionMismatchRejectCarryOver() {
        let original = baseline()
        for field in ["owner", "product", "revision"] {
            var draft = original.draft
            switch field { case "owner": draft.owner = .merchant; case "product": draft.product = .freeExplore; default: draft.baseRevision += " changed" }
            XCTAssertFalse(ProjectTopicBudgetCarryOver.allows(draft, topicID: 71, baseline: original))
        }
        var composed = original; composed.draft.baseRevision = "é"
        var decomposed = composed.draft; decomposed.baseRevision = "e\u{301}"
        XCTAssertFalse(ProjectTopicBudgetCarryOver.allows(decomposed, topicID: 71, baseline: composed))
    }
    func testEmptyRevisionDoesNotProveSavedBudgetOwnership() {
        var original = baseline(); original.draft.baseRevision = ""
        XCTAssertFalse(ProjectTopicBudgetCarryOver.allows(original.draft, topicID: 71, baseline: original))
    }
    func testUnknownNonpositiveFractionalAndOverflowRemainRawAndBlocked() throws {
        let values: [ProjectEditJSON] = [.bool(true), .string("7777"), .number(0), .number(-1), .number(1.5), .number(Decimal(Int64(Int32.max) + 1)), .array([]), .object(["future": .number(2)])]
        for raw in values {
            let original = try readback(raw); let before = ProjectEditPendingMaterials.exactData(original.draft)
            XCTAssertEqual(original.draft.preserved["xpBudget"], raw)
            XCTAssertThrowsError(try ProjectEditContract.payload(original.draft, topicID: 71, scope: .full, baseline: original))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(original.draft), before)
        }
    }
    func testOldLocalEnvelopeCannotHideUnknownFreshBudget() throws {
        let original = baseline(.string("future")); var draft = original.draft; draft.preserved.removeValue(forKey: "xpBudget")
        XCTAssertFalse(ProjectTopicBudgetCarryOver.allows(draft, topicID: 71, baseline: original))
    }
    func testNewDraftKeepsDefaultBehaviorAndCannotImportCustomBudget() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        XCTAssertNil(try ProjectEditContract.payload(draft, topicID: nil, scope: .full)["xpBudget"])
        draft.preserved["xpBudget"] = .null
        XCTAssertNil(try ProjectEditContract.payload(draft, topicID: nil, scope: .full)["xpBudget"])
        draft.preserved["xpBudget"] = .number(7777)
        XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: nil, scope: .full, baseline: .init(draft: draft)))
    }
    func testWhitelistKeepsOriginalShapeRegardlessOfBudgetRawValue() throws {
        let original = baseline(.string("future")), payload = try ProjectEditContract.payload(original.draft, topicID: 71, scope: .whitelist, baseline: original)
        XCTAssertEqual(Set(payload.keys), Set(ProjectEditContract.whitelist + ["id"])); XCTAssertNil(payload["xpBudget"])
    }
    func testLocalEnvelopeRoundTripPreservesSavedBudgetAndOtherFields() throws {
        let original = baseline(), data = try JSONEncoder().encode(original.draft)
        let restored = try JSONDecoder().decode(ProjectEditDraft.self, from: data)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(restored), ProjectEditPendingMaterials.exactData(original.draft))
        XCTAssertTrue(ProjectTopicBudgetCarryOver.allows(restored, topicID: 71, baseline: original))
    }
    @MainActor func testActualPreparedReviewFreezesSavedBudgetWithoutRewardOrSubmitActions() async throws {
        let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "saved-budget"), original = baseline()
        let service = ProjectEditSyntheticService(snapshot: original)
        let coordinator = ProjectEditCoordinator(initial: original, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session })
        await coordinator.load(); var changed = original.draft; changed.name += " revised"; coordinator.prepare(changed)
        let review = try XCTUnwrap(coordinator.confirmation); XCTAssertEqual(review.payload["xpBudget"], .number(7777)); XCTAssertTrue(service.submissions.isEmpty)
        changed.preserved.removeValue(forKey: "xpBudget"); coordinator.prepare(changed); XCTAssertNil(coordinator.confirmation)
    }
    private func readback(_ raw: ProjectEditJSON?) throws -> ProjectEditSnapshot {
        var topic: [String: ProjectEditJSON] = ["id": .number(71), "productType": .number(1), "name": .string("Fixture route"),
            "description": .string("Fixture story"), "imgUrl": .string("fixture://cover"), "categoryIds": .string("7"),
            "updateTime": .string("r1"), "startDate": .string("2030-05-01"), "endDate": .string("2030-05-30")]
        topic["xpBudget"] = raw
        let node: ProjectEditJSON = .object(["id": .number(2), "name": .string("Fixture stop"), "longitude": .string("121"), "latitude": .string("31")])
        let chapter: ProjectEditJSON = .object(["id": .number(1), "description": .string("Fixture chapter"), "cmsTopicNodeList": .array([node])])
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object(["editScope": .string("FULL"), "topic": .object(topic), "chapters": .array([chapter]), "tickets": .array([])])])
        return try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 71, owner: .personal)
    }
}
