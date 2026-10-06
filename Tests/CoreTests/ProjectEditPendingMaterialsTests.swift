import XCTest
@testable import QuestifyCore

/// Native ports of the five material projection/arrangement source cases, plus raw/local boundaries.
/// Authored Swift tests; actual Swift execution is pending Apple/Swift CI.
final class ProjectEditPendingMaterialsTests: XCTestCase {
    private func material() -> ProjectEditPendingMaterial {
        var node = ProjectEditNode(); node.id = "material-1"; node.name = "  River e\u{301}\n"; node.description = "Raw\t"
        node.address = "Boardwalk"; node.longitude = "121.48"; node.latitude = "31.23"; node.imgUrl = "fixture:image"
        node.nodeTime = 45; node.templateID = 7
        node.localMetadata = ["templateInfo": .object(["title": .string("Quiz")]), "templateName": .string("Quiz"),
            "showTemplate": .bool(true), "hookText": .string("Look up"), "cardHookLong": .string("Along the river"),
            "fragmentText": .string("Old city"), "businessTime": .string("09:00"), "subtitle": .string("Detail"),
            "future": .object(["kept": .array([.null, .string("e\u{301}")])])]
        return .init(node: node, kind: .place)
    }
    private func draft(_ product: ProjectEditProduct, story: String = "") -> ProjectEditDraft {
        var draft = ProjectEditDraft(product: product), chapter = ProjectEditChapter()
        chapter.id = "chapter-1"; chapter.description = story; draft.chapters = [chapter]; draft.pendingMaterials = [material()]; return draft
    }
    func testMaterialProjectionKeepsEveryGameplayFieldAndUnknownRawMetadata() throws {
        let original = material(), data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ProjectEditPendingMaterial.self, from: data)
        XCTAssertEqual(restored, original); XCTAssertEqual(restored.kind, .place)
        XCTAssertEqual(restored.node.nodeTime, 45); XCTAssertEqual(restored.node.templateID, 7)
        XCTAssertEqual(restored.node.localMetadata["hookText"], .string("Look up")); XCTAssertEqual(restored.node.localMetadata, original.node.localMetadata)
        XCTAssertEqual(Array(restored.node.name.utf8), Array(original.node.name.utf8))
    }
    func testMaterialToFreeChapterKeepsLocalIDGameplayAndUsesExistingNodeOrder() throws {
        var source = draft(.freeExplore), existing = ProjectEditNode(); existing.name = "Earlier"; source.chapters[0].nodes = [existing]
        let result = try ProjectEditPendingMaterials.arranging("material-1", into: "chapter-1", in: source)
        XCTAssertEqual(result.chapters[0].nodes.map(\.id), [existing.id, "material-1"])
        XCTAssertEqual(result.chapters[0].nodes.last, material().node); XCTAssertEqual(result.pendingMaterials, [])
        XCTAssertEqual(source.pendingMaterials?.count, 1); XCTAssertEqual(source.chapters[0].nodes.count, 1)
    }
    func testAddressWithoutCoordinatesRemainsPending() {
        var source = draft(.freeExplore); source.pendingMaterials?[0].node.longitude = ""; source.pendingMaterials?[0].node.latitude = ""
        XCTAssertThrowsError(try ProjectEditPendingMaterials.arranging("material-1", into: "chapter-1", in: source))
        XCTAssertTrue(source.chapters[0].nodes.isEmpty); XCTAssertEqual(source.pendingMaterials?.count, 1)
    }
    func testCityBlankStoryCannotArrangeMaterialAtAnyGap() throws {
        let source = try ProjectEditPendingMaterials.materializingStory(chapterID: "chapter-1", in: draft(.city))
        XCTAssertThrowsError(try ProjectEditPendingMaterials.arranging("material-1", into: "chapter-1", expectedBlocks: source.chapters[0].blocks?.map(\.id), in: source))
        XCTAssertTrue(source.chapters[0].nodes.isEmpty); XCTAssertEqual(source.pendingMaterials?.count, 1)
    }
    func testReadyCityMaterialRequiresExplicitCurrentStoryGap() throws {
        var source = try ProjectEditPendingMaterials.materializingStory(chapterID: "chapter-1", in: draft(.city, story: "Real story"))
        source.chapters[0].blocks?.append(.init(kind: .text, content: "After"))
        let blocks = try XCTUnwrap(source.chapters[0].blocks), next = try ProjectEditPendingMaterials.arranging("material-1", into: "chapter-1", before: blocks[1].id, expectedBlocks: blocks.map(\.id), in: source)
        XCTAssertEqual(next.chapters[0].blocks?.map(\.kind), [.text, .node, .text])
        XCTAssertEqual(next.chapters[0].blocks?[1].nodeID, "material-1"); XCTAssertEqual(next.pendingMaterials, [])
        XCTAssertThrowsError(try ProjectEditPendingMaterials.arranging("material-1", into: "chapter-1", expectedBlocks: [], in: source))
    }
    func testOptionalLocalCollectionSupportsOldEnvelopeAndNeverEntersPublishPayload() throws {
        var source = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        let legacy = try JSONEncoder().encode(source)
        XCTAssertNil(try JSONDecoder().decode(ProjectEditDraft.self, from: legacy).pendingMaterials)
        let original = source
        let before = try ProjectEditContract.payload(source, topicID: nil, scope: .full)
        source.pendingMaterials = [material()]
        let after = try ProjectEditContract.payload(source, topicID: nil, scope: .full)
        XCTAssertEqual(after, before); XCTAssertNil(after["pendingMaterials"])
        XCTAssertFalse(source.whitelistLockedFieldsEqual(to: original))
    }
    func testCopyForOtherModeRemovesOnlyServerIDsAndRetainsPendingRawMetadata() throws {
        var source = draft(.freeExplore); source.pendingMaterials?[0].node.localMetadata["id"] = .number(77)
        let copy = try ProjectDraftModeCopy.copy(source, to: .city)
        XCTAssertNil(copy.pendingMaterials?[0].node.localMetadata["id"])
        XCTAssertEqual(copy.pendingMaterials?[0].node.localMetadata["future"], source.pendingMaterials?[0].node.localMetadata["future"])
        XCTAssertEqual(copy.pendingMaterials?[0].id, source.pendingMaterials?[0].id)
        XCTAssertEqual(source.pendingMaterials?[0].node.localMetadata["id"], .number(77))
    }
    func testExplicitEditKeepsKindAndZeroDurationAndRejectsDuplicateIDsOrOpeningTargets() throws {
        let source = draft(.freeExplore); var node = material().node; node.nodeTime = 0; node.name = "Edited"
        let changed = try ProjectEditPendingMaterials.saving(node, replacing: node.id, in: source)
        XCTAssertEqual(changed.pendingMaterials?[0].kind, .place); XCTAssertEqual(changed.pendingMaterials?[0].node.nodeTime, 0)
        XCTAssertThrowsError(try ProjectEditPendingMaterials.saving(node, in: source))
        var opening = source; opening.chapters[0].preserved["opening"] = .bool(true)
        XCTAssertThrowsError(try ProjectEditPendingMaterials.arranging(node.id, into: "chapter-1", in: opening))
        var duplicate = source; duplicate.pendingMaterials?.append(material())
        XCTAssertThrowsError(try ProjectEditPendingMaterials.removing(node.id, from: duplicate))
    }
    @MainActor func testVersionedEnvelopeReadsHistoricalDraftButFencesMaterialSchemaFromOldReaders() throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "pending-version"), identity = try ProjectEditDraftIdentity()
        let storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage)
        let old = ProjectEditDraft(product: .freeExplore)
        try store.save(old, session: session, identity: identity)
        guard case .ready(let legacy) = store.load(session: session, identity: identity, baseline: old) else { return XCTFail("Historical draft must load") }
        XCTAssertEqual(legacy.version, 1); XCTAssertNil(legacy.draft.pendingMaterials)
        var next = old; next.pendingMaterials = [material()]
        try store.save(next, session: session, identity: identity)
        guard case .ready(let current) = store.load(session: session, identity: identity, baseline: old) else { return XCTFail("Material envelope must load") }
        XCTAssertEqual(current.version, 2); XCTAssertEqual(current.draft.pendingMaterials, next.pendingMaterials)
        let key = try XCTUnwrap(storage.data.first { entry in
            guard let object = (try? JSONSerialization.jsonObject(with: entry.value)) as? [String: Any] else { return false }
            return object["draft"] != nil
        }?.key)
        let currentData = try XCTUnwrap(storage.data[key])
        var unsupported = try XCTUnwrap(try JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        unsupported["version"] = 3; let bytes = try JSONSerialization.data(withJSONObject: unsupported); storage.data[key] = bytes
        guard case .incompatible = store.load(session: session, identity: identity, baseline: old) else { return XCTFail("Unknown schema cannot be rewritten") }
        XCTAssertEqual(storage.data[key], bytes)
        unsupported["version"] = 1; let unmarked = try JSONSerialization.data(withJSONObject: unsupported); storage.data[key] = unmarked
        guard case .incompatible = store.load(session: session, identity: identity, baseline: old) else { return XCTFail("Materials require their explicit envelope version") }
        XCTAssertEqual(storage.data[key], unmarked)
    }

    @MainActor func testMaterialEnvelopeRejectsForeignOwnerDraftAndModeWithoutDeletingBytes() throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "pending-owner"), identity = try ProjectEditDraftIdentity()
        let storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage)
        let source = draft(.freeExplore); try store.save(source, session: session, identity: identity)
        let key = try XCTUnwrap(storage.data.first { entry in
            guard let object = (try? JSONSerialization.jsonObject(with: entry.value)) as? [String: Any] else { return false }
            return object["draft"] != nil
        }?.key)
        let data = try XCTUnwrap(storage.data[key]), original = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for fault in ["account", "identity", "mode", "owner"] {
            var changed = original
            if fault == "account" { changed["accountID"] = 902 }
            else if fault == "identity" { changed["identity"] = ["draftUUID": UUID().uuidString] }
            else {
                var draft = try XCTUnwrap(changed["draft"] as? [String: Any])
                if fault == "mode" { draft["product"] = 1 } else { draft["owner"] = "MERCHANT" }
                changed["draft"] = draft
            }
            let bytes = try JSONSerialization.data(withJSONObject: changed); storage.data[key] = bytes
            let result = store.load(session: session, identity: identity, baseline: source)
            if fault == "account" { guard case .memberMismatch = result else { return XCTFail("Must reject foreign account") } }
            else { guard case .incompatible = result else { return XCTFail("Must reject changed local identity/mode/owner") } }
            XCTAssertEqual(storage.data[key], bytes)
        }
    }

}
