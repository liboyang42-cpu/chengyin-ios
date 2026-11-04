import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class NativeRpgEnvironmentAuthorClosureTests: XCTestCase {
    private let original = #" {"schemaVersion":2,"env":{"enabled":true,"authorOverride":false,"cacheMinutes":5,"provider":"original-provider"},"location":{"enabled":false},"future":{"note":"original"}} "#
    private func draft(_ raw: String? = nil) -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(); value.baseRevision = "environment-r1"
        value.preserved["journeyRules"] = .string(raw ?? original); return value
    }
    private func editor(_ value: ProjectEditDraft) throws -> NativeRpgEnvironmentAuthorDraft {
        try .init(original: value.preserved["journeyRules"])
    }
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "environment-author") }
    private func setup(scope: ProjectEditScope = .full) async -> (ProjectEditModel, Owner, ProjectEditMemoryStorage, ProjectEditSyntheticService) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), snapshot = ProjectEditSnapshot(topicID: 101, scope: scope, draft: draft())
        let service = ProjectEditSyntheticService(snapshot: snapshot)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (model, owner, storage, service)
    }
    func testMissingLegacyUnknownAndUnsupportedShapesAreNotRepaired() {
        for raw in [#"{}"#, #"{"schemaVersion":1}"#, #"{"schemaVersion":3}"#, #"{"schemaVersion":2,"env":false}"#, #"{"schemaVersion":2,"env":null}"#, #"{"schemaVersion":2,"location":[]}"#, "[]", "{"] {
            XCTAssertThrowsError(try editor(draft(raw)), raw)
        }
        XCTAssertThrowsError(try NativeRpgEnvironmentAuthorDraft(original: nil))
        XCTAssertThrowsError(try NativeRpgEnvironmentAuthorDraft(original: .null))
    }
    func testReadingMissingModulesDoesNotCreateSwitchesProviderOrFacts() throws {
        let value = draft(#"{"schemaVersion":2}"#), author = try editor(value)
        XCTAssertFalse(author.enabled); XCTAssertFalse(author.authorOverride); XCTAssertFalse(author.locationEnabled)
        XCTAssertNil(author.rules["env"]); XCTAssertNil(author.rules["location"])
        XCTAssertThrowsError(try author.applying(to: value))
        XCTAssertEqual(value.preserved["journeyRules"]?.text, #"{"schemaVersion":2}"#)
    }
    func testExplicitDeclarationHasOnlyOriginalThreeBooleanFields() throws {
        let value = draft(#"{"schemaVersion":2}"#); var author = try editor(value)
        author.configure(enabled: true, authorOverride: true, location: true)
        let reread = try editor(author.applying(to: value))
        XCTAssertEqual(reread.rules["env"], .object(["enabled": .bool(true), "authorOverride": .bool(true)]))
        XCTAssertEqual(reread.rules["location"], .object(["enabled": .bool(true)]))
        XCTAssertEqual(Set(reread.rules.keys), ["schemaVersion", "env", "location"])
        XCTAssertNil(reread.rules["env"]?.object?["provider"]); XCTAssertNil(reread.rules["env"]?.object?["weather"])
        XCTAssertNil(reread.rules["location"]?.object?["latitude"])
    }
    func testAllExplicitSwitchCombinationsDoNotInferAnotherSwitch() throws {
        let value = draft()
        for enabled in [false, true] { for allowOverride in [false, true] { for location in [false, true] {
            var author = try editor(value); author.configure(enabled: enabled, authorOverride: allowOverride, location: location)
            let reread = try editor(author.applying(to: value))
            XCTAssertEqual(reread.enabled, enabled); XCTAssertEqual(reread.authorOverride, allowOverride); XCTAssertEqual(reread.locationEnabled, location)
        } } }
    }
    func testNoOpAndChangeBackPreserveExactOriginalBytes() throws {
        let value = draft(); var author = try editor(value)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try author.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
        author.configure(enabled: false, authorOverride: true, location: true)
        author.configure(enabled: true, authorOverride: false, location: false)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try author.applying(to: value)), ProjectEditPendingMaterials.exactData(value))
    }
    func testUnknownModuleFieldsStayPreservedAndRejectApply() throws {
        for raw in [#"{"schemaVersion":2,"env":{"enabled":true,"authorOverride":false,"future":1},"location":{"enabled":false}}"#,
                    #"{"schemaVersion":2,"env":{"enabled":true,"authorOverride":false},"location":{"enabled":false,"future":1}}"#] {
            let value = draft(raw); var author = try editor(value)
            author.configure(enabled: false, authorOverride: true, location: true)
            XCTAssertThrowsError(try author.applying(to: value))
            XCTAssertTrue(author.rules["env"]?.object?["future"] == .number(1) || author.rules["location"]?.object?["future"] == .number(1))
        }
    }
    func testOriginalProviderCacheAndUnknownSiblingAreNeverChangedBySwitches() throws {
        let value = draft(); var author = try editor(value); author.configure(enabled: false, authorOverride: true, location: true)
        var changed = try author.applying(to: value); let reread = try editor(changed)
        XCTAssertEqual(reread.rules["env"]?.object?["provider"], .string("original-provider"))
        XCTAssertEqual(reread.rules["env"]?.object?["cacheMinutes"], .number(5))
        XCTAssertEqual(reread.rules["future"], author.rules["future"])
        changed.preserved["journeyRules"] = value.preserved["journeyRules"]
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(changed), ProjectEditPendingMaterials.exactData(value))
    }
    func testChangedOriginalBytesRejectEquivalentUnicodeReplacement() throws {
        let raw = "{\"schemaVersion\":2,\"future\":\"e\u{301}\"}"
        let replacement = raw.replacingOccurrences(of: "e\u{301}", with: "é")
        var author = try editor(draft(raw)); author.configure(enabled: true, authorOverride: false, location: false)
        XCTAssertThrowsError(try author.applying(to: draft(replacement)))
    }
    func testDuplicateEscapedAndUnicodeEquivalentKeysFailClosed() {
        let values = [#"{"schemaVersion":2,"schemaVersion":2}"#,
                      #"{"schemaVersion":2,"env":{"enabled":true,"enabled":false}}"#,
                      #"{"schemaVersion":2,"future":[{"x":1,"x":2}]}"#,
                      #"{"schemaVersion":2,"future":{"x":1,"\u0078":2}}"#,
                      "{\"schemaVersion\":2,\"future\":{\"é\":1,\"e\u{301}\":2}}"]
        for raw in values { XCTAssertThrowsError(try editor(draft(raw)), raw) }
    }
    func testOversizedAndExcessivelyNestedOriginalDoNotEnterEditor() {
        let large = #"{"schemaVersion":2,"future":""# + String(repeating: "a", count: 1_048_576) + #""}"#
        let nested = #"{"schemaVersion":2,"future":"# + String(repeating: "[", count: 130) + "0" + String(repeating: "]", count: 130) + "}"
        XCTAssertThrowsError(try editor(draft(large))); XCTAssertThrowsError(try editor(draft(nested)))
    }
    func testOriginalPayloadAndReadbackCarryExactRulesButWhitelistDoesNot() throws {
        let value = draft(); var author = try editor(value); author.configure(enabled: false, authorOverride: true, location: true)
        let changed = try author.applying(to: value)
        let payload = try ProjectEditContract.payload(changed, topicID: 101, scope: .full, baseline: .init(topicID: 101, scope: .full, draft: value))
        XCTAssertEqual(payload["journeyRules"], changed.preserved["journeyRules"])
        var topic = payload; topic["updateTime"] = .string("environment-r2")
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object(["editScope": .string("FULL"), "topic": .object(topic), "chapters": payload["chapters"] ?? .array([]), "tickets": payload["tickets"] ?? .array([])])])
        let reread = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 101, owner: .personal)
        XCTAssertEqual(reread.draft.preserved["journeyRules"], changed.preserved["journeyRules"])
        let limited = try ProjectEditContract.payload(changed, topicID: 101, scope: .whitelist, baseline: .init(topicID: 101, scope: .whitelist, draft: changed))
        XCTAssertNil(limited["journeyRules"])
    }
    func testOriginalLocalSaveFailureKeepsDraftAndAllowsSameReviewRetry() async throws {
        let (model, _, storage, service) = await setup(), lease = try XCTUnwrap(model.captureStarterLease())
        let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision
        var author = try editor(model.draft); author.configure(enabled: false, authorOverride: true, location: true)
        let proposed = try author.applying(to: model.draft)
        storage.failWrites = true; XCTAssertFalse(model.persistLocalChange(proposed, lease: lease))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
        XCTAssertTrue(service.submissions.isEmpty)
        storage.failWrites = false; XCTAssertTrue(model.persistLocalChange(proposed, lease: lease))
        XCTAssertFalse(try editor(model.draft).enabled); XCTAssertTrue(try editor(model.draft).locationEnabled); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testChangedAccountEpochAndNamespaceRejectOriginalSaveLease() async throws {
        for session in [try ProjectEditSession(accountID: 8, epoch: 1, storageNamespace: "environment-author"),
                        try ProjectEditSession(accountID: 7, epoch: 2, storageNamespace: "environment-author"),
                        try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "other-environment-author")] {
            let (model, owner, _, service) = await setup(), lease = try XCTUnwrap(model.captureStarterLease())
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            var author = try editor(model.draft); author.configure(enabled: false, authorOverride: true, location: true)
            let proposed = try author.applying(to: model.draft)
            owner.session = session; XCTAssertFalse(model.persistLocalChange(proposed, lease: lease))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testWhitelistAndFrozenScopesCannotCreateAuthorSaveLease() async {
        for scope in [ProjectEditScope.whitelist, .sellingFrozen] {
            let (model, _, _, service) = await setup(scope: scope)
            XCTAssertFalse(model.fullEdit); XCTAssertNil(model.captureStarterLease()); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testUIKeepsOriginalFullEditABAPreviewAndRetirementFences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/NativeRpgEnvironmentAuthorView.swift"), encoding: .utf8)
        for clause in ["scenePhase == .active && model.fullEdit && model.confirmation == nil", "model.isCurrentStarterLease(capture.lease)", "model.draftMutationRevision == capture.revision", "storageNamespace.utf8.elementsEqual", "model.coordinator.snapshot == capture.snapshot", "ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes", "ProjectEditPendingMaterials.exactData(next) == expected.bytes", "bufferRevision == expected.revision", "review?.id == expected.id", "guard model.persistLocalChange(next, lease: capture.lease) else", ".onChange(of: model.editorIncarnation)", ".onDisappear { retire() }"] {
            XCTAssertTrue(source.contains(clause), clause)
        }
        for forbidden in ["TemplateAuthoringModel", "persistStagedRpgDraft", "URLSession", "CLLocationManager", "requestWhenInUseAuthorization"] { XCTAssertFalse(source.contains(forbidden)) }
        XCTAssertTrue(source.contains("模板天气与室内配置编辑尚未接入"))
    }
    func testActualEntryHostsWithoutChangingOrSubmittingRules() async {
        let (model, _, _, service) = await setup(); let before = ProjectEditPendingMaterials.exactData(model.draft)
        let host = UIHostingController(rootView: NavigationStack { Form { NativeRpgEnvironmentAuthorEntry(model: model) } }
            .environment(\.scenePhase, .active).environment(\.dynamicTypeSize, .accessibility5))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640); host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
    }
}
