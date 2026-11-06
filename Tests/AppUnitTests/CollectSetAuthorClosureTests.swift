import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class CollectSetAuthorClosureTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "collect-set-author") }
    private func draft() -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft()
        value.chapters[0].nodes[0].localMetadata["id"] = .number(31)
        value.baseRevision = "original-r1"
        return value
    }
    private func setup(scope: ProjectEditScope = .full) async -> (ProjectEditModel, Owner, ProjectEditMemoryStorage, ProjectEditSyntheticService) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), snapshot = ProjectEditSnapshot(topicID: 101, scope: scope, draft: draft())
        let service = ProjectEditSyntheticService(snapshot: snapshot)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (model, owner, storage, service)
    }
    private var set: CollectSetAuthorDefinition { .init(key: "set-1", title: "Original set", nodeIds: [31]) }
    func testReadingAbsentConfigurationDoesNotCreateDefaultsOrMutateDraft() throws {
        let value = draft(); let before = ProjectEditPendingMaterials.exactData(value)
        XCTAssertTrue(try CollectSetAuthoring.definitions(in: value).isEmpty)
        XCTAssertNil(value.preserved["routeGraphJson"])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(value), before)
    }
    func testNoOpPreservesEveryUnrelatedGraphByte() throws {
        var value = draft()
        let raw = #"{ "unknown": {"number":1e100,"escaped":"a\\b"}, "collectSets" : [] }"#
        value.preserved["routeGraphJson"] = .string(raw)
        let changed = try CollectSetAuthoring.applying([], to: value)
        XCTAssertEqual(changed.preserved["routeGraphJson"]?.text, raw)
        XCTAssertEqual(try CollectSetAuthoring.definitions(in: changed), [])
    }
    func testSetsRoundTripUsingOnlyOriginalSavedNodeIDs() throws {
        let value = draft(), changed = try CollectSetAuthoring.applying([set], to: value)
        XCTAssertEqual(try CollectSetAuthoring.definitions(in: changed), [set])
        XCTAssertEqual(changed.chapters, value.chapters)
        XCTAssertEqual(changed.tickets, value.tickets)
        XCTAssertEqual(changed.owner, value.owner)
        XCTAssertEqual(changed.baseRevision, value.baseRevision)
    }
    func testForeignMissingNegativeAndDuplicateNodeReferencesReject() {
        for nodes in [[999], [], [-1], [31, 31]] {
            XCTAssertThrowsError(try CollectSetAuthoring.applying([.init(key: "set", title: "Set", nodeIds: nodes)], to: draft()))
        }
        var duplicate = draft(); duplicate.chapters[0].nodes.append(duplicate.chapters[0].nodes[0])
        XCTAssertThrowsError(try CollectSetAuthoring.applying([set], to: duplicate))
    }
    func testInvalidKeysTitlesDuplicateSetsAndCapacityReject() {
        for entry in [CollectSetAuthorDefinition(key: "bad key", title: "Set", nodeIds: [31]),
                      .init(key: "ok", title: "  \n", nodeIds: [31]),
                      .init(key: "ok", title: String(repeating: "x", count: 121), nodeIds: [31])] {
            XCTAssertThrowsError(try CollectSetAuthoring.applying([entry], to: draft()))
        }
        XCTAssertThrowsError(try CollectSetAuthoring.applying([set, set], to: draft()))
        let tooMany = (0..<65).map { CollectSetAuthorDefinition(key: "s-\($0)", title: "Set", nodeIds: [31]) }
        XCTAssertThrowsError(try CollectSetAuthoring.applying(tooMany, to: draft()))
    }
    func testUnknownSetFieldsAndDuplicateJSONKeysNeverGetDropped() {
        for raw in [#"{"collectSets":[{"key":"set","title":"Set","nodeIds":[31],"future":1}]}"#,
                    #"{"collectSets":[],"collectSets":[]}"#,
                    #"{"future":{"x":1,"x":2},"collectSets":[]}"#] {
            var value = draft(); value.preserved["routeGraphJson"] = .string(raw)
            XCTAssertThrowsError(try CollectSetAuthoring.definitions(in: value))
            XCTAssertEqual(value.preserved["routeGraphJson"]?.text, raw)
        }
    }
    func testMalformedNonObjectAndOversizedGraphRemainUnsupported() {
        for raw in ["{", "[]", String(repeating: " ", count: 262_145)] {
            var value = draft(); value.preserved["routeGraphJson"] = .string(raw)
            XCTAssertThrowsError(try CollectSetAuthoring.applying([set], to: value))
            XCTAssertEqual(value.preserved["routeGraphJson"]?.text, raw)
        }
        var value = draft(); value.preserved["routeGraphJson"] = .object([:])
        XCTAssertThrowsError(try CollectSetAuthoring.applying([set], to: value))
    }
    func testOnlyCollectionDefinitionAndAbsentRouteModeChange() throws {
        let original = draft(); var changed = try CollectSetAuthoring.applying([set], to: original)
        XCTAssertEqual(changed.preserved["routeMode"], .string("LINEAR"))
        changed.preserved["routeGraphJson"] = original.preserved["routeGraphJson"]
        changed.preserved["routeMode"] = original.preserved["routeMode"]
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(changed), ProjectEditPendingMaterials.exactData(original))
        var branch = original; branch.preserved["routeMode"] = .string("BRANCH_GRAPH")
        XCTAssertEqual(try CollectSetAuthoring.applying([set], to: branch).preserved["routeMode"], .string("BRANCH_GRAPH"))
    }
    func testOriginalPayloadAndReadbackCarryTheSameGraphWithoutNewWriter() throws {
        let original = draft(), updated = try CollectSetAuthoring.applying([set], to: original)
        let payload = try ProjectEditContract.payload(updated, topicID: 101, scope: .full, baseline: .init(topicID: 101, scope: .full, draft: original))
        XCTAssertEqual(payload["routeGraphJson"], updated.preserved["routeGraphJson"])
        var topic = payload; topic["updateTime"] = .string("original-r2")
        let response: ProjectEditJSON = .object(["code": .number(200), "data": .object([
            "editScope": .string("FULL"), "topic": .object(topic),
            "chapters": payload["chapters"] ?? .array([]), "tickets": payload["tickets"] ?? .array([])])])
        let readback = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(response), expectedTopicID: 101, owner: .personal)
        XCTAssertEqual(readback.draft.preserved["routeGraphJson"], updated.preserved["routeGraphJson"])
        XCTAssertEqual(try CollectSetAuthoring.definitions(in: readback.draft), [set])
    }
    func testWhitelistPayloadDoesNotTransmitTheConfiguration() throws {
        let value = try CollectSetAuthoring.applying([set], to: draft())
        let payload = try ProjectEditContract.payload(value, topicID: 101, scope: .whitelist,
            baseline: .init(topicID: 101, scope: .whitelist, draft: value))
        XCTAssertNil(payload["routeGraphJson"]); XCTAssertNil(payload["routeMode"])
    }
    func testExistingLocalPersistenceDoesNotSubmitOrPublish() async throws {
        let (model, _, storage, service) = await setup()
        XCTAssertTrue(model.fullEdit)
        model.draft = try CollectSetAuthoring.applying([set], to: model.draft); model.changed()
        XCTAssertTrue(model.saveLocalForExit())
        XCTAssertFalse(storage.data.isEmpty); XCTAssertTrue(service.submissions.isEmpty)
        XCTAssertEqual(try CollectSetAuthoring.definitions(in: model.draft), [set])
    }
    func testStorageFailureNeverClaimsSaveAndNeverSubmits() async throws {
        let (model, _, storage, service) = await setup()
        model.draft = try CollectSetAuthoring.applying([set], to: model.draft); model.changed()
        storage.failWrites = true
        XCTAssertFalse(model.saveLocalForExit()); XCTAssertTrue(service.submissions.isEmpty)
        XCTAssertEqual(try CollectSetAuthoring.definitions(in: model.draft), [set])
    }
    func testOriginalModelRejectsAccountEpochAndWhitelistAuthority() async {
        let (restricted, _, _, _) = await setup(scope: .whitelist); XCTAssertFalse(restricted.fullEdit)
        for account in [7, 8] {
            let (model, owner, _, service) = await setup()
            owner.session = try? .init(accountID: account, epoch: 2, storageNamespace: "collect-set-author")
            XCTAssertFalse(model.fullEdit); XCTAssertFalse(model.saveLocalForExit()); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testOwnerUIKeepsOriginalABAExactBytesAndLifecycleFences() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/CollectSetAuthorView.swift"), encoding: .utf8)
        for clause in ["capture.incarnation == model.editorIncarnation", "capture.revision == model.draftMutationRevision",
                       "ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes", "model.confirmation == nil",
                       "phase == .active", "editToken == token", ".onDisappear { retire() }", "guard model.saveLocalForExit() else"] {
            XCTAssertTrue(source.contains(clause), clause)
        }
        XCTAssertFalse(source.contains("URLSession")); XCTAssertFalse(source.contains("coordinator.submit"))
    }
    func testRealEntryAndStatelessHelpersRenderWithoutSendingRequests() async {
        let (model, _, _, service) = await setup()
        let host = UIHostingController(rootView: NavigationStack {
            Form {
                CollectSetAuthorEntry(model: model)
                NativeAuthorNotice(text: Text(String(repeating: "Original notice ", count: 12)), tone: .attention)
                NativeAuthorLoading(text: Text("Original loading state"))
            }.nativeAuthorSurface()
        }.environment(\.dynamicTypeSize, .accessibility5))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view); XCTAssertTrue(service.submissions.isEmpty)
    }
}
