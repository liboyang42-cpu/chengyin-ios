import Foundation
import XCTest
@testable import QuestifyCore

/// Uses the canonical editor and full original draft/envelope codecs. No replacement mapper.
final class NativeStoryWalkingAuthorOptionalTextTests: XCTestCase {
    private let keys = ["floor", "approachNote", "accessibleAlternative", "businessTime"]
    private let paths: [WritableKeyPath<NativeStoryWalkingAuthorDraft.Entrance, String>] = [
        \.floor, \.approach, \.alternative, \.businessTime
    ]
    private func entrance(_ optional: [ProjectEditJSON]) -> [String: ProjectEditJSON] {
        var row: [String: ProjectEditJSON] = ["label": .string("Original entrance"), "source": .string("Original source"),
            "longitude": .number(121), "latitude": .number(31), "datum": .string("WGS84"), "temporarilyClosed": .bool(false)]
        for (key, value) in zip(keys, optional) { row[key] = value }
        return row
    }
    private func makeDraft(row: [String: ProjectEditJSON], schema: Int = 2) throws -> ProjectEditDraft {
        var draft = ProjectEditDraft(), node = ProjectEditNode(), chapter = ProjectEditChapter()
        node.id = "original-local-node"; node.name = "Original node"; node.localMetadata["id"] = .number(22)
        chapter.id = "original-local-chapter"; chapter.nodes = [node]; draft.chapters = [chapter]
        draft.name = "Original topic"; draft.baseRevision = "original-revision"
        var declaration: [String: ProjectEditJSON] = ["nodeId": .number(22), "region": .string("CN")]
        if schema != 1 { declaration["entrance"] = .object(row) }
        let root = ProjectEditJSON.object(["schemaVersion": .number(1), "unrelated": .object(["raw": .string("  untouched\n")]),
            "walkingNavigation": .object(["schemaVersion": .number(Decimal(schema)), "authorityTTLSeconds": .number(60), "nodes": .array([.object(declaration)])])])
        draft.preserved["themeRuntimeConfig"] = .string(String(decoding: try XCTUnwrap(ProjectEditPendingMaterials.exactData(root)), as: UTF8.self))
        return draft
    }
    private func makeDraft(_ values: [ProjectEditJSON], schema: Int = 2) throws -> ProjectEditDraft {
        try makeDraft(row: entrance(values), schema: schema)
    }
    private func root(_ draft: ProjectEditDraft) throws -> [String: ProjectEditJSON] {
        let raw = try XCTUnwrap(draft.preserved["themeRuntimeConfig"]?.text)
        return try XCTUnwrap(JSONDecoder().decode(ProjectEditJSON.self, from: Data(raw.utf8)).object)
    }
    private func outputEntrance(_ draft: ProjectEditDraft) throws -> [String: ProjectEditJSON] {
        try XCTUnwrap(root(draft)["walkingNavigation"]?.object?["nodes"]?.array?.first?.object?["entrance"]?.object)
    }
    private func assertUnsupported(_ body: () throws -> NativeStoryWalkingAuthorDraft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case NativeStoryWalkingAuthorDraft.Failure.unsupported = error else { return XCTFail("Expected unsupported, got \(error)", file: file, line: line) }
        }
    }

    func testUntouchedNullEmptyNonemptyAndWhitespaceAllMixedCombinationsAreExactNoOps() throws {
        let legal: [ProjectEditJSON] = [.null, .string(""), .string("Original text"), .string(" \t\n")]
        for floor in legal { for approach in legal { for alternative in legal { for hours in legal {
            let draft = try makeDraft([floor, approach, alternative, hours]), before = ProjectEditPendingMaterials.exactData(draft)
            let editor = try NativeStoryWalkingAuthorDraft(draft: draft)
            let output = try editor.applying(to: draft)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(output), before)
            XCTAssertEqual(try outputEntrance(output), entrance([floor, approach, alternative, hours]))
        } } } }
    }
    func testEditingOtherFieldsKeepsEveryUntouchedOptionalValueAndUnrelatedRoot() throws {
        let values: [ProjectEditJSON] = [.string(""), .null, .string(" \n"), .string("Original hours")]
        let draft = try makeDraft(values)
        for change in 0..<10 {
            var editor = try NativeStoryWalkingAuthorDraft(draft: draft)
            switch change {
            case 0: editor.ttl = "90"
            case 1: editor.nodes[0].region = "GB"
            case 2: editor.nodes[0].entrance?.label = "New label"
            case 3: editor.nodes[0].entrance?.source = "New source"
            case 4: editor.nodes[0].entrance?.longitude = "122"
            case 5: editor.nodes[0].entrance?.latitude = "32"
            case 6: editor.nodes[0].entrance?.datum = "GCJ02"
            case 7: editor.nodes[0].entrance?.closed = true
            case 8: editor.nodes[0].entrance?.floor = "" // Same displayed value is not an edit.
            default: editor.nodes[0].entrance?.approach = "" // Historical null does not gain empty-string provenance.
            }
            let output = try editor.applying(to: draft), row = try outputEntrance(output)
            for (key, value) in zip(keys, values) { XCTAssertEqual(row[key], value, "change \(change), \(key)") }
            XCTAssertEqual(try root(output)["unrelated"], try root(draft)["unrelated"])
        }
    }
    func testEachExplicitlyClearedNonemptyFieldIsNullAndLeavesOtherEmptySourcesAlone() throws {
        for index in keys.indices {
            var values = Array(repeating: ProjectEditJSON.string(""), count: 4); values[index] = .string("Original nonempty")
            let draft = try makeDraft(values); var editor = try NativeStoryWalkingAuthorDraft(draft: draft)
            editor.nodes[0].entrance?[keyPath: paths[index]] = ""
            let row = try outputEntrance(editor.applying(to: draft))
            for other in keys.indices { XCTAssertEqual(row[keys[other]], other == index ? .null : .string("")) }
        }
    }
    func testOriginallyEmptyFieldEditedAndThenClearedDoesNotRestoreItsOldSourceType() throws {
        for index in keys.indices {
            let draft = try makeDraft(Array(repeating: .string(""), count: 4)); var editor = try NativeStoryWalkingAuthorDraft(draft: draft)
            editor.nodes[0].entrance?[keyPath: paths[index]] = "New explicit text"
            editor.nodes[0].entrance?[keyPath: paths[index]] = ""
            let row = try outputEntrance(editor.applying(to: draft))
            for other in keys.indices { XCTAssertEqual(row[keys[other]], other == index ? .null : .string("")) }
        }
    }
    func testEachOptionalFieldAcceptsWhitespaceAndNonemptyEditsWithoutTrimming() throws {
        for index in keys.indices { for value in [" \t\n", "New text", "e\u{301} 🙂"] {
            let draft = try makeDraft(Array(repeating: .null, count: 4)); var editor = try NativeStoryWalkingAuthorDraft(draft: draft)
            editor.nodes[0].entrance?[keyPath: paths[index]] = value
            let row = try outputEntrance(editor.applying(to: draft))
            XCTAssertEqual(row[keys[index]]?.text.map { Data($0.utf8) }, Data(value.utf8))
            for other in keys.indices where other != index { XCTAssertEqual(row[keys[other]], .null) }
        } }
    }
    func testNewEntranceAndReplacementEntranceKeepUnknownOptionalFieldsNull() throws {
        let draft = try makeDraft(Array(repeating: .string(""), count: 4)); var editor = try NativeStoryWalkingAuthorDraft(draft: draft)
        editor.nodes[0].entrance = nil
        let undeclared = try editor.applying(to: draft)
        XCTAssertEqual(try root(undeclared)["walkingNavigation"]?.object?["nodes"]?.array?.first?.object?["entrance"], .null)
        var newEntrance = NativeStoryWalkingAuthorDraft.Entrance()
        newEntrance.label = "Explicit new entrance"; newEntrance.source = "Explicit source"
        newEntrance.longitude = "121"; newEntrance.latitude = "31"; newEntrance.datum = "WGS84"; newEntrance.closed = false
        editor.nodes[0].entrance = newEntrance
        let row = try outputEntrance(editor.applying(to: draft))
        for key in keys { XCTAssertEqual(row[key], .null) }
    }
    func testFullOriginalEnvelopeEncodeRestoreReconstructsOnlyActualStoredProvenance() throws {
        let cases: [[ProjectEditJSON]] = [[.string(""), .null, .string("Original"), .string(" \t")], Array(repeating: .null, count: 4)]
        for values in cases {
            let draft = try makeDraft(values)
            let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "synthetic-walking-source")
            let original = ProjectEditEnvelope(session: session, identity: try .init(topicID: 71), draft: draft, now: Date(timeIntervalSince1970: 1))
            let bytes = try JSONEncoder().encode(original)
            let restored = try JSONDecoder().decode(ProjectEditEnvelope.self, from: bytes)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(restored), ProjectEditPendingMaterials.exactData(original))
            var editor = try NativeStoryWalkingAuthorDraft(draft: restored.draft); editor.ttl = "90"
            let changed = try editor.applying(to: restored.draft)
            let second = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(changed))
            let reopened = try NativeStoryWalkingAuthorDraft(draft: second)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try reopened.applying(to: second)), ProjectEditPendingMaterials.exactData(second))
            for (key, value) in zip(keys, values) { XCTAssertEqual(try outputEntrance(second)[key], value) }
        }
    }
    func testHistoricalNullNeverBackfillsEmptyStringsAfterOtherEditsAndReopening() throws {
        let draft = try makeDraft(Array(repeating: .null, count: 4)); var editor = try NativeStoryWalkingAuthorDraft(draft: draft)
        for path in paths { editor.nodes[0].entrance?[keyPath: path] = "" }
        editor.ttl = "90"
        let output = try editor.applying(to: draft)
        let restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(output))
        let reopened = try NativeStoryWalkingAuthorDraft(draft: restored)
        for key in keys { XCTAssertEqual(try outputEntrance(reopened.applying(to: restored))[key], .null) }
    }
    func testV1IsExactReadOnlyUntilExplicitV2Upgrade() throws {
        let draft = try makeDraft(Array(repeating: .string(""), count: 4), schema: 1)
        var editor = try NativeStoryWalkingAuthorDraft(draft: draft)
        XCTAssertEqual(editor.schema, 1)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try editor.applying(to: draft)), ProjectEditPendingMaterials.exactData(draft))
        editor.schema = 2
        let upgraded = try editor.applying(to: draft)
        let policy = try XCTUnwrap(root(upgraded)["walkingNavigation"]?.object)
        XCTAssertEqual(policy["schemaVersion"], .number(2))
        XCTAssertEqual(policy["nodes"]?.array?.first?.object?["entrance"], .null)
        XCTAssertEqual(try root(upgraded)["unrelated"], try root(draft)["unrelated"])
    }
    func testMissingExtraAndWrongTypedOptionalFieldsRemainUnsupported() throws {
        for key in keys {
            var missing = entrance(Array(repeating: .null, count: 4)); missing[key] = nil
            let absentDraft = try makeDraft(row: missing)
            assertUnsupported { try NativeStoryWalkingAuthorDraft(draft: absentDraft) }
            for value in [ProjectEditJSON.number(0), .bool(false), .array([]), .object([:])] {
                var row = entrance(Array(repeating: .null, count: 4)); row[key] = value
                let draft = try makeDraft(row: row)
                assertUnsupported { try NativeStoryWalkingAuthorDraft(draft: draft) }
            }
        }
        var extra = entrance(Array(repeating: .null, count: 4)); extra["future"] = .string("opaque")
        let draft = try makeDraft(row: extra)
        assertUnsupported { try NativeStoryWalkingAuthorDraft(draft: draft) }
        let unknown = try makeDraft(Array(repeating: .null, count: 4), schema: 3)
        assertUnsupported { try NativeStoryWalkingAuthorDraft(draft: unknown) }
    }
    func testInvalidOptionalTextStillFailsWithoutChangingTheOriginalDraft() throws {
        let limits = [100, 2000, 2000, 1000]
        for index in keys.indices { for value in ["contains\0nul", String(repeating: "x", count: limits[index] + 1)] {
            let draft = try makeDraft(Array(repeating: .string(""), count: 4)), before = ProjectEditPendingMaterials.exactData(draft)
            var editor = try NativeStoryWalkingAuthorDraft(draft: draft)
            editor.nodes[0].entrance?[keyPath: paths[index]] = value
            XCTAssertThrowsError(try editor.applying(to: draft))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), before)
        } }
    }
    func testChangedFullDraftPreimageRejectsEvenUnrelatedChanges() throws {
        let draft = try makeDraft(Array(repeating: .string(""), count: 4)), editor = try NativeStoryWalkingAuthorDraft(draft: draft)
        for change in 0..<3 {
            var changed = draft
            if change == 0 { changed.name = "Changed topic" }
            else if change == 1 { changed.chapters[0].nodes[0].localMetadata["id"] = .number(23) }
            else { changed.preserved["unrelatedDraftField"] = .null }
            let before = ProjectEditPendingMaterials.exactData(changed)
            XCTAssertThrowsError(try editor.applying(to: changed)) { error in
                guard case NativeStoryWalkingAuthorDraft.Failure.changed = error else { return XCTFail("Expected changed, got \(error)") }
            }
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(changed), before)
        }
    }
}
