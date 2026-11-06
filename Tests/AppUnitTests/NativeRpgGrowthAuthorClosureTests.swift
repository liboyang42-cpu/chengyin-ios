import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class NativeRpgGrowthAuthorClosureTests: XCTestCase {
    private let original = #" {"schemaVersion":2,"role":{"enabled":true,"future":"keep"},"growth":{"enabled":true,"maxLevel":3,"skillPointsPerLevel":1,"xpThresholds":[100,250]},"future":{"note":"original"}} "#
    private func draft(_ raw: String? = nil) -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(); value.baseRevision = "growth-r1"
        value.preserved["journeyRules"] = .string(raw ?? original); return value
    }
    private func editor(_ value: ProjectEditDraft) throws -> NativeRpgGrowthAuthorDraft { try .init(original: value.preserved["journeyRules"]) }
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "growth-author") }
    private func setup(scope: ProjectEditScope = .full) async -> (ProjectEditModel, NativeRpgGrowthAuthorController, Owner, ProjectEditMemoryStorage, ProjectEditSyntheticService) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), snapshot = ProjectEditSnapshot(topicID: 101, scope: scope, draft: draft())
        let service = ProjectEditSyntheticService(snapshot: snapshot)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (model, .init(project: model), owner, storage, service)
    }
    func testMissingLegacyUnknownAndUnsupportedRulesAreNotInvented() {
        for raw in [#"{}"#, #"{"schemaVersion":1}"#, #"{"schemaVersion":3}"#, #"{"schemaVersion":2,"growth":false}"#, #"{"schemaVersion":2,"growth":null}"#, "[]", "{"] { XCTAssertThrowsError(try editor(draft(raw)), raw) }
        XCTAssertThrowsError(try NativeRpgGrowthAuthorDraft(original: nil))
    }
    func testReadingMissingGrowthPreservesAbsenceAndExactOriginalBytes() throws {
        let value = draft(#" {"schemaVersion":2} "#), author = try editor(value)
        XCTAssertFalse(author.roleEnabled); XCTAssertFalse(author.changed); XCTAssertNil(author.growth)
        XCTAssertEqual(try author.serialized(), value.preserved["journeyRules"])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try author.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
    }
    func testFormalCurveIsExplicitAndDoesNotEnableGrowthOrRole() throws {
        let value = draft(#"{"schemaVersion":2}"#); var author = try editor(value); author.useFormalCurve()
        XCTAssertFalse(author.roleEnabled); XCTAssertEqual(author.growth?["enabled"], .bool(false))
        XCTAssertEqual(author.growth?["maxLevel"], .number(10)); XCTAssertEqual(author.growth?["skillPointsPerLevel"], .number(1))
        XCTAssertEqual(author.growth?["xpThresholds"]?.array?.compactMap(\.integer), [100,250,450,700,1000,1350,1750,2200,2700])
        let changed = try author.applying(to: value)
        let parsed = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(try XCTUnwrap(changed.preserved["journeyRules"]?.text).utf8))
        XCTAssertNil(parsed.object?["role"])
    }
    func testEnablingGrowthRequiresOriginalRoleWithoutCreatingIt() throws {
        let value = draft(#"{"schemaVersion":2,"role":{"enabled":false}}"#); var author = try editor(value)
        author.useFormalCurve(); author.set("enabled", .bool(true)); XCTAssertThrowsError(try author.serialized())
        XCTAssertFalse(author.roleEnabled)
    }
    func testOriginalLevelAndSkillPointBoundsRemainStrict() throws {
        for number in [0, 21] { var author = try editor(draft()); author.set("maxLevel", .number(Decimal(number))); XCTAssertThrowsError(try author.serialized()) }
        for number in [-1, 1_000_001] { var author = try editor(draft()); author.set("skillPointsPerLevel", .number(Decimal(number))); XCTAssertThrowsError(try author.serialized()) }
        var edge = try editor(draft()); edge.set("maxLevel", .number(20)); edge.set("skillPointsPerLevel", .number(1_000_000))
        edge.set("xpThresholds", .array((1...19).map { .number(Decimal($0)) })); XCTAssertNoThrow(try edge.serialized())
    }
    func testThresholdCountIntegerOrderingAndUpperBoundAreEnforced() throws {
        let samples: [[ProjectEditJSON]] = [[.number(0), .number(250)], [.number(100), .number(100)], [.number(100)], [.number(100), .number(1_000_000_001)], [.number(100), .string("250")]]
        for rows in samples {
            var author = try editor(draft()); author.set("xpThresholds", .array(rows)); XCTAssertThrowsError(try author.serialized())
        }
    }
    func testFormalFeatSubsetDoesNotAcceptUnknownOrDuplicateValues() throws {
        for feats in [["brisk", "brisk"], ["unknown"]] {
            var author = try editor(draft()); author.set("feats", .array(feats.map(ProjectEditJSON.string))); XCTAssertThrowsError(try author.serialized())
        }
        var author = try editor(draft()); author.set("feats", .array([.string("brisk"), .string("keen_eye")]))
        XCTAssertNoThrow(try author.serialized())
    }
    func testUnknownGrowthFieldsArePreservedRatherThanDeletedToPassValidation() throws {
        let raw = #"{"schemaVersion":2,"growth":{"enabled":false,"maxLevel":3,"skillPointsPerLevel":1,"xpThresholds":[100,250],"future":1}}"#
        var author = try editor(draft(raw)); author.set("skillPointsPerLevel", .number(2))
        XCTAssertEqual(author.growth?["future"], .number(1)); XCTAssertThrowsError(try author.serialized())
    }
    func testChangeBackIsExactNoOpAndRealChangesTouchOnlyRules() throws {
        let value = draft(); var author = try editor(value)
        author.set("skillPointsPerLevel", .number(2)); author.set("skillPointsPerLevel", .number(1))
        XCTAssertFalse(author.changed); XCTAssertEqual(ProjectEditPendingMaterials.exactData(try author.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
        author.set("skillPointsPerLevel", .number(2)); var changed = try author.applying(to: value)
        let fields = try JSONDecoder().decode(ProjectEditJSON.self, from: Data(try XCTUnwrap(changed.preserved["journeyRules"]?.text).utf8)).object
        XCTAssertEqual(fields?["role"]?.object?["future"], .string("keep")); XCTAssertEqual(fields?["future"]?.object?["note"], .string("original"))
        changed.preserved["journeyRules"] = value.preserved["journeyRules"]
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(changed), ProjectEditPendingMaterials.exactData(value))
    }
    func testExactSourceBytesRejectCanonicallyEquivalentReplacement() throws {
        let raw = "{\"schemaVersion\":2,\"note\":\"e\u{301}\"}"
        var author = try editor(draft(raw)); author.useFormalCurve()
        XCTAssertThrowsError(try author.applying(to: draft(raw.replacingOccurrences(of: "e\u{301}", with: "é"))))
    }
    func testDuplicateEscapedEquivalentAndOversizedSourcesFailClosed() {
        let values = [#"{"schemaVersion":2,"schemaVersion":2}"#, #"{"schemaVersion":2,"future":[{"x":1,"\u0078":2}]}"#,
                      "{\"schemaVersion\":2,\"future\":{\"é\":1,\"e\u{301}\":2}}", String(repeating: " ", count: 1_048_577)]
        for raw in values { XCTAssertThrowsError(try editor(draft(raw)), raw.prefix(100).description) }
    }
    func testOriginalNumericFunctionsKeepIncompleteInputAndRejectNonIntegerSpellings() {
        for text in ["", "01", "+1", "1.5", "1e3", " 2", "2 ", "2\n", "\n2", "∞"] {
            XCTAssertEqual(NativeAuthorNumericInput.numberInput(text), .string(text))
            XCTAssertEqual(NativeAuthorNumericInput.display(.string(text)), text)
        }
        XCTAssertEqual(NativeAuthorNumericInput.numberInput("-3"), .number(-3)); XCTAssertEqual(NativeAuthorNumericInput.numberInput("250"), .number(250))
        XCTAssertEqual(NativeAuthorNumericInput.display(.number(250)), "250"); XCTAssertEqual(NativeAuthorNumericInput.display(nil), "")
    }
    func testOriginalPayloadReadbackAndWhitelistRemainUnchanged() throws {
        let value = draft(); var author = try editor(value); author.set("skillPointsPerLevel", .number(2)); let changed = try author.applying(to: value)
        let payload = try ProjectEditContract.payload(changed, topicID: 101, scope: .full, baseline: .init(topicID: 101, scope: .full, draft: value))
        XCTAssertEqual(payload["journeyRules"], changed.preserved["journeyRules"])
        var topic = payload; topic["updateTime"] = .string("growth-r2")
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object(["editScope": .string("FULL"), "topic": .object(topic), "chapters": payload["chapters"] ?? .array([]), "tickets": payload["tickets"] ?? .array([])])])
        let reread = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 101, owner: .personal)
        XCTAssertEqual(reread.draft.preserved["journeyRules"], changed.preserved["journeyRules"])
        let limited = try ProjectEditContract.payload(changed, topicID: 101, scope: .whitelist, baseline: .init(topicID: 101, scope: .whitelist, draft: changed))
        XCTAssertNil(limited["journeyRules"])
    }
    func testControllerRequiresActiveFullEditBeforeOpening() async {
        let (_, author, _, _, service) = await setup(); author.open(); XCTAssertNil(author.editor)
        author.setSceneActive(true); author.open(); XCTAssertNotNil(author.editor); XCTAssertTrue(author.isCurrent); XCTAssertTrue(service.submissions.isEmpty)
        for scope in [ProjectEditScope.whitelist, .sellingFrozen] {
            let (_, limited, _, _, _) = await setup(scope: scope); limited.setSceneActive(true); limited.open(); XCTAssertNil(limited.editor)
        }
    }
    func testActualControllerSaveFailureRetainsSameReviewAndRetriesOriginalStore() async throws {
        let (model, author, _, storage, service) = await setup(); author.setSceneActive(true); author.open()
        let id = try XCTUnwrap(author.editorID), before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision
        author.mutate(editorID: id) { $0.set("skillPointsPerLevel", .number(2)) }; author.preview(editorID: id)
        let review = try XCTUnwrap(author.review); storage.failWrites = true; author.apply(review)
        XCTAssertTrue(author.saveUnconfirmed); XCTAssertEqual(author.review?.id, review.id); XCTAssertTrue(author.isCurrent)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
        XCTAssertTrue(service.submissions.isEmpty)
        storage.failWrites = false; author.apply(review)
        XCTAssertNil(author.editor); XCTAssertNil(author.review); XCTAssertEqual(try editor(model.draft).growth?["skillPointsPerLevel"], .number(2))
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testActualControllerRejectsReviewAfterFurtherBufferEdit() async throws {
        let (model, author, _, storage, service) = await setup(); author.setSceneActive(true); author.open()
        let id = try XCTUnwrap(author.editorID), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        author.mutate(editorID: id) { $0.set("skillPointsPerLevel", .number(2)) }; author.preview(editorID: id); let old = try XCTUnwrap(author.review)
        author.mutate(editorID: id) { $0.set("skillPointsPerLevel", .number(3)) }; author.apply(old)
        XCTAssertNil(author.review); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.data, saved); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testThresholdBindingCannotWriteAfterRowStructureChanges() async throws {
        let (_, author, _, _, _) = await setup(); author.setSceneActive(true); author.open(); let id = try XCTUnwrap(author.editorID)
        let old = author.threshold(1); author.mutate(editorID: id, changesThresholds: true) { $0.removeLastThreshold() }
        author.mutate(editorID: id, changesThresholds: true) { $0.addThreshold() }; let before = author.editor
        old.wrappedValue = "999"; XCTAssertEqual(author.editor, before); XCTAssertEqual(old.wrappedValue, "")
    }
    func testOldEditorBindingCannotMutateAReopenedEditor() async throws {
        let (_, author, _, _, _) = await setup(); author.setSceneActive(true); author.open(); let id = try XCTUnwrap(author.editorID), old = author.number("maxLevel")
        author.close(editorID: id); author.open(); let before = author.editor
        XCTAssertNotEqual(author.editorID, id); old.wrappedValue = "20"; XCTAssertEqual(author.editor, before)
    }
    func testBackgroundRetiresControllerAndOldReviewCannotSave() async throws {
        let (model, author, _, storage, _) = await setup(); author.setSceneActive(true); author.open(); let id = try XCTUnwrap(author.editorID)
        author.mutate(editorID: id) { $0.set("skillPointsPerLevel", .number(2)) }; author.preview(editorID: id); let old = try XCTUnwrap(author.review)
        let before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        author.setSceneActive(false); author.apply(old)
        XCTAssertNil(author.editor); XCTAssertNil(author.review); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.data, saved)
    }
    func testSameByteProjectReplacementInvalidatesCaptureBeforeOldReviewSave() async throws {
        let (model, author, _, storage, _) = await setup(); author.setSceneActive(true); author.open(); let id = try XCTUnwrap(author.editorID)
        author.mutate(editorID: id) { $0.set("skillPointsPerLevel", .number(2)) }; author.preview(editorID: id); let old = try XCTUnwrap(author.review)
        let snapshot = model.draft, saved = storage.data; model.draft = snapshot
        XCTAssertFalse(author.isCurrent); author.apply(old); author.retireIfInvalid()
        XCTAssertNil(author.editor); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(snapshot)); XCTAssertEqual(storage.data, saved)
    }
    func testAccountEpochAndNamespaceChangesPreventActualControllerSave() async throws {
        for session in [try ProjectEditSession(accountID: 8, epoch: 1, storageNamespace: "growth-author"), try ProjectEditSession(accountID: 7, epoch: 2, storageNamespace: "growth-author"), try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "other-growth-author")] {
            let (model, author, owner, storage, service) = await setup(); author.setSceneActive(true); author.open(); let id = try XCTUnwrap(author.editorID)
            author.mutate(editorID: id) { $0.set("skillPointsPerLevel", .number(2)) }; author.preview(editorID: id); let old = try XCTUnwrap(author.review)
            let before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data; owner.session = session
            XCTAssertFalse(author.isCurrent); author.apply(old); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.data, saved); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testNoOpControllerReviewDoesNotAttemptLocalSaveOrSubmit() async throws {
        let (model, author, _, storage, service) = await setup(); author.setSceneActive(true); author.open(); let id = try XCTUnwrap(author.editorID)
        author.preview(editorID: id); let review = try XCTUnwrap(author.review), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        storage.failWrites = true; author.apply(review)
        XCTAssertNil(author.editor); XCTAssertFalse(author.saveUnconfirmed); XCTAssertEqual(storage.data, saved)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testActualEntryHostsWithoutChangingOrSubmittingGrowthRules() async {
        let (model, _, _, _, service) = await setup(); let before = ProjectEditPendingMaterials.exactData(model.draft)
        let host = UIHostingController(rootView: NavigationStack { Form { NativeRpgGrowthAuthorEntrySection(model: model) } }.environment(\.scenePhase, .active).environment(\.dynamicTypeSize, .accessibility5))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
    }
}
