import XCTest
@testable import QuestifyCore

final class ProjectClubLeadTests: XCTestCase {
    func testNewDraftUsesVisibleSourceDefaultAndKnownExistingValuesStayExact() throws {
        let newDraft = ProjectEditSyntheticFixtures.draft()
        XCTAssertEqual(newDraft.preserved["openClubPool"], .number(1))
        XCTAssertEqual(try ProjectEditContract.payload(newDraft, topicID: nil, scope: .full)["openClubPool"], .number(1))
        for value in [0, 1] {
            let draft = try readback(raw: .number(Decimal(value)))
            XCTAssertEqual(ProjectClubLead.isSelected(draft), value == 1)
            XCTAssertEqual(try ProjectEditContract.payload(draft, topicID: 71, scope: .full)["openClubPool"], .number(Decimal(value)))
        }
    }
    func testMissingAndNullReadbackAndOldLocalEnvelopeNeverOptIn() throws {
        for raw in [nil, ProjectEditJSON.null] {
            let draft = try readback(raw: raw)
            XCTAssertEqual(draft.preserved["openClubPool"], raw)
            XCTAssertFalse(ProjectClubLead.isSelected(draft))
            XCTAssertEqual(try ProjectClubLead.wireValue(draft), .number(0))
            XCTAssertEqual(try ProjectClubLead.applying(false, to: draft), draft)
            let restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(draft))
            XCTAssertEqual(restored.preserved["openClubPool"], raw)
            XCTAssertEqual(try ProjectClubLead.wireValue(restored), .number(0))
        }
        var legacy = ProjectEditSyntheticFixtures.draft(); legacy.preserved.removeValue(forKey: "openClubPool")
        let restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(restored.preserved["openClubPool"]); XCTAssertFalse(ProjectClubLead.isSelected(restored))
    }
    func testToggleTouchesOnlyKnownSettingAndNoOpPreservesExactDraft() throws {
        var original = ProjectEditSyntheticFixtures.draft()
        original.preserved["future"] = .object(["opaque": .array([.string("retain"), .number(4)])])
        original.baseRevision = "exact-revision"
        var expected = original; expected.preserved["openClubPool"] = .number(0)
        let changed = try ProjectClubLead.applying(false, to: original)
        XCTAssertEqual(changed, expected)
        XCTAssertEqual(try ProjectClubLead.applying(false, to: changed), changed)
        XCTAssertEqual(try ProjectClubLead.applying(true, to: changed), original)
    }
    func testUnknownValuesRemainReadOnlyAndBlockFullBeforeEligibilityNormalization() throws {
        for raw in [ProjectEditJSON.bool(true), .string("1"), .number(2), .number(-1), .number(0.5), .array([.number(1)]), .object(["future": .bool(true)])] {
            for ineligible in [false, true] {
                var draft = try readback(raw: raw)
                if ineligible { draft.product = .freeExplore; draft.recruitDeadline = "2030-04-01"; draft.clubID = 9 }
                let before = draft
                XCTAssertFalse(ProjectClubLead.supportsEditing(draft))
                XCTAssertThrowsError(try ProjectClubLead.applying(false, to: draft))
                XCTAssertThrowsError(try ProjectClubLead.wireValue(draft))
                XCTAssertThrowsError(try ProjectEditContract.payload(draft, topicID: 71, scope: .full))
                XCTAssertTrue(ProjectEditValidation.issues(draft).contains { $0.key == "projectClubLead.unsupported" })
                XCTAssertEqual(draft, before)
                XCTAssertEqual(try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(draft)), before)
            }
        }
    }
    func testSourceEligibilityNormalizesKnownValueWithoutErasingLocalPreference() throws {
        for product in ProjectEditProduct.allCases {
            for clubID in [nil, 9] as [Int?] {
                var draft = ProjectEditSyntheticFixtures.draft(product: product); draft.clubID = clubID
                let eligible = product == .city && clubID == nil
                XCTAssertEqual(ProjectClubLead.isEligible(draft), eligible)
                XCTAssertEqual(try ProjectEditContract.payload(draft, topicID: nil, scope: .full)["openClubPool"], .number(eligible ? 1 : 0))
                XCTAssertEqual(draft.preserved["openClubPool"], .number(1))
                if !eligible { XCTAssertThrowsError(try ProjectClubLead.applying(false, to: draft)) }
            }
        }
    }
    func testWhitelistExcludesSettingEvenForUnsupportedSourceAndDetectsLocalMutation() throws {
        var draft = try readback(raw: .object(["future": .string("keep")]))
        let before = draft
        let wire = try ProjectEditContract.payload(draft, topicID: 71, scope: .whitelist)
        XCTAssertEqual(Set(wire.keys), Set(ProjectEditContract.whitelist + ["id"]))
        XCTAssertNil(wire["openClubPool"])
        XCTAssertFalse(ProjectEditValidation.issues(draft, scope: .whitelist).contains { $0.id == "clubLead" })
        draft.name += " rename"; XCTAssertTrue(draft.whitelistLockedFieldsEqual(to: before))
        draft.preserved["openClubPool"] = .number(0); XCTAssertFalse(draft.whitelistLockedFieldsEqual(to: before))
    }
    @MainActor func testPreparedPayloadFreezesNewDefaultAndChangedChoice() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "club-lead-review")
        let draft = ProjectEditSyntheticFixtures.draft()
        let service = ProjectEditSyntheticService(snapshot: .init(draft: draft))
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: service,
            store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session })
        await coordinator.load(); coordinator.prepare(draft)
        let first = try XCTUnwrap(coordinator.confirmation)
        XCTAssertEqual(first.payload["openClubPool"], .number(1))
        let next = try ProjectClubLead.applying(false, to: draft); coordinator.prepare(next)
        XCTAssertEqual(coordinator.confirmation?.payload["openClubPool"], .number(0))
        XCTAssertEqual(first.payload["openClubPool"], .number(1)); XCTAssertTrue(service.submissions.isEmpty)
    }
    private func readback(raw: ProjectEditJSON?) throws -> ProjectEditDraft {
        var topic: [String: ProjectEditJSON] = ["id": .number(71), "productType": .number(1), "name": .string("Fixture route"),
            "description": .string("Fixture story"), "imgUrl": .string("fixture://cover"), "categoryIds": .string("7"),
            "updateTime": .string("r1"), "startDate": .string("2030-05-01"), "endDate": .string("2030-05-30")]
        topic["openClubPool"] = raw
        let node: ProjectEditJSON = .object(["id": .number(2), "name": .string("Fixture stop"), "longitude": .string("121"), "latitude": .string("31")])
        let chapter: ProjectEditJSON = .object(["id": .number(1), "description": .string("Fixture chapter"), "cmsTopicNodeList": .array([node])])
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object(["editScope": .string("FULL"), "topic": .object(topic), "chapters": .array([chapter]), "tickets": .array([])])])
        return try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 71, owner: .personal).draft
    }
}
