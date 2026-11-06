import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class NativeRpgPassiveRulesAuthorClosureTests: XCTestCase {
    private let original = #" {"schemaVersion":2,"checkEnabled":true,"role":{"enabled":true,"skills":[{"key":"observe","attributeKey":"counter.obs","category":"OBS"},{"key":"run","attributeKey":"counter.phy","category":"PHY"}],"future":"keep"},"passive":{"enabled":true,"base":10},"tiers":{"easy":{"dc":10,"damage":1},"medium":{"dc":13,"damage":2},"hard":{"dc":16,"damage":3}},"future":{"note":"original"}} "#
    private func draft(_ raw: String? = nil) -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(); value.baseRevision = "passive-r1"
        value.preserved["journeyRules"] = .string(raw ?? original); return value
    }
    private func editor(_ value: ProjectEditDraft) throws -> NativeRpgPassiveRulesDraft { try .init(original: value.preserved["journeyRules"]) }
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "passive-author") }
    private func setup(scope: ProjectEditScope = .full) async -> (ProjectEditModel, Owner, ProjectEditMemoryStorage, ProjectEditSyntheticService) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), snapshot = ProjectEditSnapshot(topicID: 101, scope: scope, draft: draft())
        let service = ProjectEditSyntheticService(snapshot: snapshot)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (model, owner, storage, service)
    }
    func testMissingLegacyUnknownAndUnsupportedModuleShapesAreRejected() {
        for raw in [#"{}"#, #"{"schemaVersion":1}"#, #"{"schemaVersion":3}"#, #"{"schemaVersion":2,"passive":false}"#, #"{"schemaVersion":2,"tiers":null}"#, "[]", "{"] { XCTAssertThrowsError(try editor(draft(raw)), raw) }
        XCTAssertThrowsError(try NativeRpgPassiveRulesDraft(original: nil))
    }
    func testReadingMissingModulesDoesNotInventBaseChecksRoleOrDCs() throws {
        let author = try editor(draft(#"{"schemaVersion":2}"#))
        XCTAssertNil(author.base); XCTAssertFalse(author.enabled); XCTAssertFalse(author.checksEnabled); XCTAssertFalse(author.roleEnabled); XCTAssertTrue(author.skills.isEmpty)
        XCTAssertNil(author.rules["passive"]); XCTAssertNil(author.rules["tiers"]); XCTAssertNil(author.rules["role"])
        XCTAssertFalse(author.issues.isEmpty); XCTAssertThrowsError(try author.serialized())
    }
    func testExplicitFormalBaseAndDCsDoNotEnableOtherModules() throws {
        let value = draft(#"{"schemaVersion":2}"#); var author = try editor(value)
        author.useFormalBase(); author.useFormalDCs()
        XCTAssertEqual(author.base, 10); XCTAssertFalse(author.enabled); XCTAssertFalse(author.checksEnabled); XCTAssertFalse(author.roleEnabled)
        XCTAssertEqual([author.dc("easy"), author.dc("medium"), author.dc("hard")], ["10", "13", "16"])
        XCTAssertTrue(author.issues.isEmpty)
        let changed = try editor(author.applying(to: value))
        XCTAssertNil(changed.rules["role"]); XCTAssertNil(changed.rules["checkEnabled"])
        XCTAssertEqual(Set(changed.rules.keys), ["schemaVersion", "passive", "tiers"])
    }
    func testEnabledPassiveRequiresExistingCheckRoleAndActualOBSSkill() throws {
        let values = [original.replacingOccurrences(of: #""checkEnabled":true"#, with: #""checkEnabled":false"#),
                      original.replacingOccurrences(of: #""role":{"enabled":true"#, with: #""role":{"enabled":false"#),
                      original.replacingOccurrences(of: #""category":"OBS""#, with: #""category":"PHY""#)]
        for raw in values {
            var author = try editor(draft(raw)); author.enabled(true)
            XCTAssertFalse(author.issues.isEmpty); XCTAssertThrowsError(try author.serialized())
            let source = try editor(draft(raw)); XCTAssertEqual(author.rules["role"], source.rules["role"]); XCTAssertEqual(author.rules["checkEnabled"], source.rules["checkEnabled"])
        }
    }
    func testOnlyOriginalOBSSkillsAreDisplayedAndNotCreated() throws {
        let author = try editor(draft())
        XCTAssertEqual(author.skills.count, 1); XCTAssertEqual(author.skills.first?.object?["key"], .string("observe"))
        XCTAssertEqual(author.skills.first?.object?["attributeKey"], .string("counter.obs"))
        XCTAssertEqual(author.rules["role"]?.object?["skills"]?.array?.count, 2)
    }
    func testOriginalBaseBoundsAreStrictAndExplicitResetIsTen() throws {
        for value in [-1, 1_000_001] {
            var author = try editor(draft(original.replacingOccurrences(of: #""base":10"#, with: "\"base\":\(value)")))
            XCTAssertFalse(author.issues.isEmpty); XCTAssertThrowsError(try author.serialized())
            author.useFormalBase(); XCTAssertEqual(author.base, 10); XCTAssertTrue(author.issues.isEmpty)
        }
    }
    func testDCBoundsIntegerAndIncreasingOrderRemainStrict() throws {
        for (tier, text) in [("easy", "4"), ("hard", "26"), ("medium", "10"), ("medium", "16"), ("medium", "13.5"), ("medium", "013"), ("medium", "13\n")] {
            var author = try editor(draft()); author.dc(tier, text)
            XCTAssertFalse(author.issues.isEmpty, text); XCTAssertThrowsError(try author.serialized())
        }
        var edge = try editor(draft()); edge.dc("easy", "5"); edge.dc("hard", "25"); XCTAssertTrue(edge.issues.isEmpty)
    }
    func testUnknownTierRequestCannotCreateOrModifyFields() throws {
        var author = try editor(draft()); let before = author
        author.dc("unknown", "20"); XCTAssertEqual(author, before)
    }
    func testUnknownModuleFieldsAreRetainedAndRejectedNotDeleted() throws {
        let values = [original.replacingOccurrences(of: #""base":10"#, with: #""base":10,"future":1"#),
                      original.replacingOccurrences(of: #""damage":1"#, with: #""damage":1,"future":1"#),
                      original.replacingOccurrences(of: #""tiers":{"easy""#, with: #""tiers":{"future":{},"easy""#)]
        for raw in values {
            var author = try editor(draft(raw)); author.useFormalBase(); author.useFormalDCs()
            XCTAssertFalse(author.issues.isEmpty); XCTAssertThrowsError(try author.serialized())
            XCTAssertTrue(author.rules["passive"]?.object?["future"] != nil || author.rules["tiers"]?.object?["future"] != nil || author.rules["tiers"]?.object?["easy"]?.object?["future"] != nil)
        }
    }
    func testNoOpAndChangeBackPreserveExactOriginalBytes() throws {
        let value = draft(); var author = try editor(value)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try author.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
        author.dc("medium", "14"); author.dc("medium", "13")
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try author.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
    }
    func testEditsPreserveOriginalRoleDamageAndUnknownSiblings() throws {
        let value = draft(); var author = try editor(value); author.dc("medium", "14")
        var changed = try author.applying(to: value); let reread = try editor(changed), source = try editor(value)
        XCTAssertEqual(reread.rules["role"], source.rules["role"]); XCTAssertEqual(reread.rules["future"], source.rules["future"])
        for tier in ["easy", "medium", "hard"] { XCTAssertEqual(reread.rules["tiers"]?.object?[tier]?.object?["damage"], source.rules["tiers"]?.object?[tier]?.object?["damage"]) }
        changed.preserved["journeyRules"] = value.preserved["journeyRules"]
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(changed), ProjectEditPendingMaterials.exactData(value))
    }
    func testChangedOriginalBytesRejectEquivalentUnicodeReplacement() throws {
        let raw = original.replacingOccurrences(of: "original", with: "e\u{301}")
        var author = try editor(draft(raw)); author.dc("medium", "14")
        XCTAssertThrowsError(try author.applying(to: draft(raw.replacingOccurrences(of: "e\u{301}", with: "é"))))
    }
    func testDuplicateEscapedUnicodeEquivalentAndOversizedInputFailClosed() {
        let values = [#"{"schemaVersion":2,"schemaVersion":2}"#, #"{"schemaVersion":2,"tiers":{"easy":{"dc":10,"dc":11}}}"#,
                      #"{"schemaVersion":2,"future":[{"x":1,"\u0078":2}]}"#,
                      "{\"schemaVersion\":2,\"future\":{\"é\":1,\"e\u{301}\":2}}", String(repeating: " ", count: 1_048_577)]
        for raw in values { XCTAssertThrowsError(try editor(draft(raw)), raw.prefix(100).description) }
    }
    func testOriginalPayloadReadbackAndWhitelistRetainContract() throws {
        let value = draft(); var author = try editor(value); author.dc("medium", "14"); let changed = try author.applying(to: value)
        let payload = try ProjectEditContract.payload(changed, topicID: 101, scope: .full, baseline: .init(topicID: 101, scope: .full, draft: value))
        XCTAssertEqual(payload["journeyRules"], changed.preserved["journeyRules"])
        var topic = payload; topic["updateTime"] = .string("passive-r2")
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object(["editScope": .string("FULL"), "topic": .object(topic), "chapters": payload["chapters"] ?? .array([]), "tickets": payload["tickets"] ?? .array([])])])
        let reread = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 101, owner: .personal)
        XCTAssertEqual(reread.draft.preserved["journeyRules"], changed.preserved["journeyRules"])
        let limited = try ProjectEditContract.payload(changed, topicID: 101, scope: .whitelist, baseline: .init(topicID: 101, scope: .whitelist, draft: changed))
        XCTAssertNil(limited["journeyRules"])
    }
    func testOriginalLocalSaveFailureKeepsDraftAndSameLeaseCanRetry() async throws {
        let (model, _, storage, service) = await setup(), lease = try XCTUnwrap(model.captureStarterLease())
        let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision
        var author = try editor(model.draft); author.dc("medium", "14"); let proposed = try author.applying(to: model.draft)
        storage.failWrites = true; XCTAssertFalse(model.persistLocalChange(proposed, lease: lease))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
        storage.failWrites = false; XCTAssertTrue(model.persistLocalChange(proposed, lease: lease)); XCTAssertEqual(try editor(model.draft).dc("medium"), "14")
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testChangedAccountEpochNamespaceAndRestrictedScopeCannotUseOriginalLease() async throws {
        for session in [try ProjectEditSession(accountID: 8, epoch: 1, storageNamespace: "passive-author"), try ProjectEditSession(accountID: 7, epoch: 2, storageNamespace: "passive-author"), try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "other-passive-author")] {
            let (model, owner, _, service) = await setup(), lease = try XCTUnwrap(model.captureStarterLease())
            var author = try editor(model.draft); author.dc("medium", "14"); let proposed = try author.applying(to: model.draft)
            let before = ProjectEditPendingMaterials.exactData(model.draft); owner.session = session
            XCTAssertFalse(model.persistLocalChange(proposed, lease: lease)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
        }
        for scope in [ProjectEditScope.whitelist, .sellingFrozen] { let (model, _, _, _) = await setup(scope: scope); XCTAssertFalse(model.fullEdit); XCTAssertNil(model.captureStarterLease()) }
    }
    func testOriginalUIKeepsFullEditABAExactReviewAndRetirementFences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/NativeRpgPassiveRulesAuthorView.swift"), encoding: .utf8)
        for clause in ["scenePhase == .active && model.fullEdit && model.confirmation == nil", "model.isCurrentStarterLease(capture.lease)", "model.draftMutationRevision == capture.revision", "storageNamespace.utf8.elementsEqual", "model.coordinator.snapshot == capture.snapshot", "ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes", "ProjectEditPendingMaterials.exactData(next) == expected.bytes", "bufferRevision == expected.revision", "review?.id == expected.id", "guard model.persistLocalChange(next, lease: capture.lease) else", ".onChange(of: model.editorIncarnation)", ".onDisappear { retire() }"] { XCTAssertTrue(source.contains(clause), clause) }
        for forbidden in ["URLSession", "OperationEndpointApproval", "coordinator.submit", "persistStagedRpgDraft"] { XCTAssertFalse(source.contains(forbidden)) }
    }
    func testActualEntryHostsWithoutChangingOrSubmittingPassiveRules() async {
        let (model, _, _, service) = await setup(); let before = ProjectEditPendingMaterials.exactData(model.draft)
        let host = UIHostingController(rootView: NavigationStack { Form { NativeRpgPassiveRulesAuthorEntry(model: model) } }.environment(\.scenePhase, .active).environment(\.dynamicTypeSize, .accessibility5))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
    }
}
