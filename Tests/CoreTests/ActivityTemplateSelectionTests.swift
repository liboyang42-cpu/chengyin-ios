import XCTest
import Foundation
@testable import QuestifyCore

final class ActivityTemplateSelectionTests: XCTestCase {
    private let session = PublishingSession(namespace: "template-choice-test", accountID: 7, epoch: UUID(), role: "club", region: .china)
    private func row(_ config: ProjectEditJSON? = nil, id: Int = 17) throws -> ActivityTemplateChoice {
        var value: [String: ProjectEditJSON] = ["id": .number(Decimal(id)), "title": .string("原文 e\u{301}"), "future": .string("untouched")]
        value["advancedConfigJson"] = config; return try .init(.object(value))
    }
    func testOrdinaryAndAbsentAdvancedConfigurationAreEligible() throws {
        for config in [nil, ProjectEditJSON.null, .string(""), .string("{}"), .object(["futureGame": .object(["enabled": .bool(true)])])] {
            XCTAssertEqual(try row(config).availability, .available)
        }
    }
    func testEnabledAlbumRejectedFromActivityButRawBytesPreserved() throws {
        let raw = "{\"album\":{\"enabled\":true,\"images\":[{\"url\":\"fixture://image\"}]},\"unknown\":\"保留\"}"
        let value = try row(.string(raw)); XCTAssertEqual(value.availability, .albumOnly)
        XCTAssertEqual(value.raw["advancedConfigJson"], .string(raw)); XCTAssertEqual(value.raw["future"], .string("untouched"))
    }
    func testExplicitDisabledAlbumAllowsOtherActualGameplay() throws {
        XCTAssertEqual(try row(.object(["album": .object(["enabled": .bool(false)])])).availability, .available)
        XCTAssertEqual(try row(.string("{\"album\":{\"enabled\":false},\"timer\":{\"enabled\":true}}" )).availability, .available)
    }
    func testMalformedUnknownAlbumTypesAreNotSilentlyOrdinary() throws {
        for raw in ["{", "[]", "{\"album\":true}", "{\"album\":{\"enabled\":1}}", "{\"album\":{\"enabled\":\"false\"}}"] {
            XCTAssertEqual(try row(.string(raw)).availability, .unsupported)
        }
    }
    func testDuplicateAndEscapedAliasNestedKeysUseExistingValidator() throws {
        for raw in [#"{"album":{"enabled":true,"enabled":false}}"#, #"{"album":{"enabled":true,"\u0065nabled":false}}"#] {
            XCTAssertEqual(try row(.string(raw)).availability, .unsupported)
        }
    }
    func testPageRejectsDuplicateIdentityAndMalformedRows() throws {
        let fields = try row().raw
        XCTAssertThrowsError(try ActivityTemplateChoice.page(.object(["rows": .array([.object(fields), .object(fields)])])))
        XCTAssertThrowsError(try ActivityTemplateChoice.page(.object(["rows": .array([.null])])))
        XCTAssertThrowsError(try ActivityTemplateChoice.page(.array([])))
    }
    func testTitleAndPositiveIdentityRequiredWithoutOwnerInference() throws {
        XCTAssertThrowsError(try row(id: 0)); XCTAssertThrowsError(try ActivityTemplateChoice(.object(["id": .number(9), "title": .string("")])))
        let value = try ActivityTemplateChoice(.object(["id": .number(9), "title": .string("Quoted"), "memberId": .number(99)]))
        XCTAssertEqual(value.availability, .available)
    }
    func testExplicitApplyOnlyChangesTemplateReference() throws {
        var draft = ActivityPublishDraft(); draft.name = "Unsaved e\u{301}"; draft.description = "完整稿"; draft.coverURL = "fixture://cover?verbatim=1"
        draft.addressName = "Raw place"; draft.start = "Unvalidated input"; draft.end = "Still editing"
        let id = UUID(), target = try ActivityTemplateSelectionTarget(session: session, draftID: id, draft: draft)
        var next = try target.applying(row(), session: session, draftID: id, draft: draft)
        XCTAssertEqual(next.playTemplateID?.rawValue, 17); next.playTemplateID = draft.playTemplateID
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(draft))
    }
    func testOldTargetCannotChangeNewDraftID() throws {
        let draft = ActivityPublishDraft(), target = try ActivityTemplateSelectionTarget(session: session, draftID: UUID(), draft: draft)
        XCTAssertThrowsError(try target.applying(row(), session: session, draftID: UUID(), draft: draft))
    }
    func testChangedAccountEpochOrUnsavedBytesRejectApply() throws {
        var draft = ActivityPublishDraft(); let id = UUID(), target = try ActivityTemplateSelectionTarget(session: session, draftID: id, draft: draft)
        let changed = PublishingSession(namespace: session.namespace, accountID: 7, epoch: UUID(), role: "club", region: .china)
        XCTAssertThrowsError(try target.applying(row(), session: changed, draftID: id, draft: draft))
        draft.description = "Changed"; XCTAssertThrowsError(try target.applying(row(), session: session, draftID: id, draft: draft))
    }
    func testAlbumAndUnsupportedRowsNeverApplyEvenWithExactTarget() throws {
        let draft = ActivityPublishDraft(), id = UUID(), target = try ActivityTemplateSelectionTarget(session: session, draftID: id, draft: draft)
        XCTAssertThrowsError(try target.applying(row(.string("{\"album\":{\"enabled\":true}}")), session: session, draftID: id, draft: draft))
        XCTAssertThrowsError(try target.applying(row(.string("malformed")), session: session, draftID: id, draft: draft))
    }
    func testSearchUsesExistingQuotedListReadContract() {
        let request = PublishingRead.templates(keyword: "  exact name  ", scope: "").request
        XCTAssertEqual(request.path, "api/template/my-list"); XCTAssertEqual(request.fields["is_quote"], .string("1"))
        XCTAssertEqual(request.fields["keyword"], .string("exact name")); XCTAssertEqual(request.encoding, .form)
    }
}
