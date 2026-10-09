import XCTest
@testable import QuestifyCore

final class ProjectNodeTemplateSelectionTests: XCTestCase {
    private let session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "node-template-tests")
    private let identity = try! ProjectEditDraftIdentity(topicID: 101)
    private func source(id: Int = 42, account: Int = 7, title: String = "Selected game") throws -> ProjectStoryTemplateDraft {
        let raw: ProjectEditJSON = .object(["id": .number(Decimal(id)), "memberId": .number(Decimal(account)), "draftStatus": .number(0),
            "delFlag": .number(0), "title": .string(title), "validationMethod": .number(0), "answer": .string("private-answer-never-copied")])
        return try .decode(raw, accountID: account, requestedID: MemberPlayTemplateID(rawValue: id)!)
    }
    private func target(_ draft: ProjectEditDraft) throws -> ProjectNodeTemplateSelectionTarget {
        try .init(draft: draft, identity: identity, session: session, chapterID: draft.chapters[0].id, nodeID: draft.chapters[0].nodes[0].id)
    }
    func testNewReferenceClearsOnlyOldCacheAndDoesNotCreateAnyStoryGapOrCopyPrivateSource() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].nodes[0].localMetadata = ["templateId": .number(41), "templateName": .string("old"), "templateInfo": .object(["id": .number(41)]), "future": .string("e\u{301}")]
        let selected = try source(), next = try target(draft).applying(selected, to: draft, identity: identity, session: session)
        var expected = draft; expected.chapters[0].nodes[0].templateID = 42
        expected.chapters[0].nodes[0].localMetadata["templateId"] = .number(42)
        expected.chapters[0].nodes[0].localMetadata["templateName"] = .string(selected.row.title)
        expected.chapters[0].nodes[0].localMetadata["templateInfo"] = .object([:])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertNil(next.chapters[0].blocks)
        XCTAssertFalse(String(decoding: try XCTUnwrap(ProjectEditPendingMaterials.exactData(next)), as: UTF8.self).contains("private-answer-never-copied"))
    }
    func testSameIDIsExactNoOpAndChangedIDFillsOnlyBlankNameWithoutSynthesizingMetadata() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].nodes[0].name = "  "
        let old = ProjectEditPendingMaterials.exactData(draft)
        let same = try target(draft).applying(source(id: 41), to: draft, identity: identity, session: session)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(same), old)
        let next = try target(draft).applying(source(), to: draft, identity: identity, session: session)
        XCTAssertEqual(next.chapters[0].nodes[0].name, "Selected game"); XCTAssertTrue(next.chapters[0].nodes[0].localMetadata.isEmpty)
    }
    func testWrongOwnerMerchantScopeBranchOrStoryOnlyNodeIsRejected() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        XCTAssertThrowsError(try target(draft).applying(source(account: 8), to: draft, identity: identity, session: session))
        draft.owner = .merchant; XCTAssertThrowsError(try target(draft)); draft.owner = .personal
        draft.preserved["routeMode"] = .string("BRANCH_GRAPH"); XCTAssertThrowsError(try target(draft)); draft.preserved["routeMode"] = nil
        var block = ProjectEditBlock(kind: .node, nodeID: draft.chapters[0].nodes[0].id); block.sourceFields = ["locationRequired": .bool(false)]
        draft.chapters[0].blocks = [block]; XCTAssertThrowsError(try target(draft))
    }
    func testChangedDraftOrDuplicateNodeCannotReceivePreviouslyReviewedReference() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); let captured = try target(draft), selected = try source()
        draft.chapters[0].nodes[0].description = "changed"
        XCTAssertThrowsError(try captured.applying(selected, to: draft, identity: identity, session: session))
        draft.chapters[0].nodes.append(draft.chapters[0].nodes[0]); XCTAssertThrowsError(try target(draft))
    }
    func testAlbumRemainsAStoryInsertionAndCannotReplaceOrdinaryNodeReference() throws {
        let draft = ProjectEditSyntheticFixtures.draft(), before = ProjectEditPendingMaterials.exactData(draft)
        let config = #"{"schemaVersion":1,"album":{"enabled":true,"images":[{"url":"https://example.com/image.jpg"}]}}"#
        let raw: ProjectEditJSON = .object(["id": .number(42), "memberId": .number(7), "draftStatus": .number(0),
            "delFlag": .number(0), "title": .string("Album"), "validationMethod": .number(0), "advancedConfigJson": .string(config)])
        let album = try ProjectStoryTemplateDraft.decode(raw, accountID: 7, requestedID: MemberPlayTemplateID(rawValue: 42)!)
        guard case .album = album.content else { return XCTFail("real existing album projection") }
        XCTAssertThrowsError(try target(draft).applying(album, to: draft, identity: identity, session: session))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), before)
    }

}
