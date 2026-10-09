import XCTest
@testable import QuestifyCore

final class ProjectStoryVariableInsertionTests: XCTestCase {
    private let config = #"{"schemaVersion":1,"profile":{"enabled":true,"questions":[{"key":"name","label":"Your name","kind":"text"},{"key":"Role_2","label":"Role","kind":"text"}]}}"#
    private func draft(_ raw: String? = nil) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].id = "chapter"
        var block = ProjectEditBlock(kind: .text, content: "  é e\u{301} 👩🏽‍🚀 {old|fallback} {unclosed \n")
        block.id = "text"; block.sourceFields = ["unknown": .string("e\u{301}"), "when": .object(["op": .string("HAS_TAG"), "value": .string("tag.first")])]
        draft.chapters[0].blocks = [block]; draft.chapters[0].nodes[0].templateID = 41
        draft.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "advancedConfigJson": .string(raw ?? config)])
        return draft
    }
    private func snapshot(_ draft: ProjectEditDraft) -> ProjectStoryVariableInsertion { .init(draft: draft, chapterID: "chapter", blockID: "text") }
    func testOnlyDeclaredProfileKeysInSourceOrderAndNoDIYOrCheckAlias() {
        let original = draft(#"{"schemaVersion":1,"profile":{"enabled":true,"questions":[{"key":"role","label":"{literal label}","kind":"text"}]},"diyName":{"enabled":true},"check":{"enabled":true}}"#)
        let captured = snapshot(original)
        XCTAssertNil(captured.reason); XCTAssertEqual(captured.variables.map(\.key), ["role"])
        XCTAssertEqual(captured.variables[0].label, "{literal label}"); XCTAssertEqual(captured.variables[0].token, "{role}")
    }
    func testAppendPreservesEveryExistingLiteralByteAndAllOtherFields() throws {
        let original = draft(), captured = snapshot(original), next = try captured.applying(appending: "name", to: original)
        var expected = original; expected.chapters[0].blocks![0].content += "{name}"
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(Array(next.chapters[0].blocks![0].content.utf8.dropLast(6)), Array(original.chapters[0].blocks![0].content.utf8))
    }
    func testNoSelectionIsExactNoOpAndUnknownOrNonASCIIKeyNeverAppends() throws {
        let original = draft(), captured = snapshot(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try captured.applying(appending: nil, to: original)), ProjectEditPendingMaterials.exactData(original))
        for key in ["notDeclared", "Name", " name", "name|fallback", "name}", "KEY", "e\u{301}"] {
            XCTAssertThrowsError(try captured.applying(appending: key, to: original))
        }
    }
    func testEmittedTokensUseExistingNativeRendererAndPreserveMissingFallbackSemantics() throws {
        var original = draft(); original.chapters[0].blocks![0].content = "Hello "
        let next = try snapshot(original).applying(appending: "name", to: original), text = next.chapters[0].blocks![0].content
        XCTAssertEqual(ChapterStoryProjection.substitute(text, variables: ["name": .string("Ada")]), "Hello Ada")
        XCTAssertEqual(ChapterStoryProjection.substitute(text, variables: [:]), text)
        XCTAssertEqual(ChapterStoryProjection.substitute("{name|traveler}", variables: [:]), "traveler")
        XCTAssertEqual(ChapterStoryProjection.substitute("{name}", variables: ["name": .string("{Role_2}")]), "{Role_2}")
    }
    func testOnlyExactASCIIUntrimmedOneToSixteenCharacterKeysAreEligible() {
        for key in ["é", "e\u{301}", "KEY", " name", "name ", "_name", "1name", "a.b", "a|b", "abcdefghijklmnopq", ""] {
            let raw = #"{"schemaVersion":1,"profile":{"enabled":true,"questions":[{"key":""# + key + #"","label":"Name"}]}}"#
            XCTAssertEqual(snapshot(draft(raw)).reason, .declarations, key)
        }
        for key in ["a", "KEY", "abcdefghijklmnop", "A_01"] {
            let raw = #"{"schemaVersion":1,"profile":{"enabled":true,"questions":[{"key":""# + key + #"","label":"Name"}]}}"#
            XCTAssertEqual(snapshot(draft(raw)).variables.map(\.key), [key])
        }
    }
    func testDuplicateDeclaredKeysAcrossQuestionsAndNodesAreReadOnly() {
        var duplicate = draft(); duplicate.chapters[0].nodes.append(duplicate.chapters[0].nodes[0])
        XCTAssertEqual(snapshot(duplicate).reason, .declarations)
        XCTAssertEqual(snapshot(draft(config.replacingOccurrences(of: "Role_2", with: "name"))).reason, .declarations)
        let differentCase = snapshot(draft(config.replacingOccurrences(of: "Role_2", with: "Name")))
        XCTAssertEqual(differentCase.variables.map(\.key), ["name", "Name"])
    }
    func testMalformedRawOrDuplicateJSONKeysNeverCollapseIntoADeclaration() {
        for raw in ["[1]", "{", config.replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":2"#),
                    config.replacingOccurrences(of: #""key":"name""#, with: #""key":"other","k\u0065y":"name""#),
                    config.replacingOccurrences(of: #""enabled":true"#, with: #""enabled":"true""#),
                    config.replacingOccurrences(of: #""label":"Your name""#, with: #""label":null"#)] {
            XCTAssertEqual(snapshot(draft(raw)).reason, .declarations)
        }
        var objectForm = draft(); objectForm.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "advancedConfigJson": .object(["schemaVersion": .number(1)])])
        XCTAssertEqual(snapshot(objectForm).reason, .declarations)
    }
    func testMissingDisabledOrUnrelatedAdvancedModulesProvideNoInventedKeys() {
        for raw in ["", #"{"schemaVersion":1}"#, #"{"schemaVersion":1,"profile":{"enabled":false}}"#, #"{"schemaVersion":1,"diyName":{"enabled":true}}"#] {
            let captured = snapshot(draft(raw)); XCTAssertNil(captured.reason); XCTAssertTrue(captured.variables.isEmpty)
        }
    }
    func testSameTemplateIDIsRequiredAndUnknownSnapshotsRemainUnchanged() {
        for kind in ["missing", "wrong", "noTemplate"] {
            var original = draft()
            if kind == "missing" { original.chapters[0].nodes[0].localMetadata = [:] }
            else if kind == "wrong" { original.chapters[0].nodes[0].templateID = 42 }
            else { original.chapters[0].nodes[0].templateID = nil }
            let before = ProjectEditPendingMaterials.exactData(original), captured = snapshot(original)
            XCTAssertEqual(captured.reason, .declarations); XCTAssertThrowsError(try captured.applying(appending: "name", to: original))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(original), before)
        }
    }
    func testDuplicateAndCanonicalAliasedChapterOrBlockIdentityCannotResolve() {
        for kind in ["chapter", "block", "canonical"] {
            var original = draft()
            if kind == "chapter" { original.chapters.append(original.chapters[0]) }
            else if kind == "block" { original.chapters[0].blocks!.append(original.chapters[0].blocks![0]) }
            else { original.chapters[0].blocks![0].id = "é" }
            let captured = kind == "canonical" ? ProjectStoryVariableInsertion(draft: original, chapterID: "chapter", blockID: "e\u{301}") : snapshot(original)
            XCTAssertEqual(captured.reason, .identity)
        }
    }
    func testNarrativeNonTextEmptyAndUnknownSchemaBlocksAreUnavailable() {
        for kind in ["narrative", "voice", "empty", "schema", "unknownBeat"] {
            var original = draft()
            switch kind {
            case "narrative": original.chapters[0].blocks![0].sourceFields?["beat"] = .string("brief")
            case "voice": original.chapters[0].blocks![0].kind = .voice
            case "empty": original.chapters[0].blocks![0].content = " \n"
            case "schema": original.chapters[0].schemaVersion = 2
            default: original.chapters[0].blocks![0].sourceFields?["beat"] = .number(1)
            }
            XCTAssertEqual(snapshot(original).reason, .unsupported)
        }
    }
    func testAnyChangedDraftOrDeclarationRejectsOldSnapshot() {
        let original = draft(), captured = snapshot(original)
        for kind in ["content", "template", "deleted", "order", "unrelated"] {
            var changed = original
            switch kind {
            case "content": changed.chapters[0].blocks![0].content += "!"
            case "template": changed.chapters[0].nodes[0].templateID = 42
            case "deleted": changed.chapters[0].blocks = []
            case "order": changed.chapters[0].blocks!.insert(.init(kind: .text, content: "New"), at: 0)
            default: changed.chapters[0].name += "!"
            }
            XCTAssertFalse(captured.isCurrent(in: changed)); XCTAssertThrowsError(try captured.applying(appending: "name", to: changed))
        }
    }
    func testServerUTF16LengthBoundaryRejectsOversizeAppendWithoutTruncation() throws {
        for prefix in [String(repeating: "a", count: 4994), String(repeating: "😀", count: 2497)] {
            var original = draft(); original.chapters[0].blocks![0].content = prefix
            let captured = snapshot(original); XCTAssertTrue(captured.canAppend("name")); XCTAssertFalse(captured.canAppend("Role_2"))
            let next = try captured.applying(appending: "name", to: original); XCTAssertEqual(next.chapters[0].blocks![0].content.utf16.count, 5000)
            XCTAssertThrowsError(try captured.applying(appending: "Role_2", to: original))
        }
        var original = draft(); original.chapters[0].blocks![0].content = String(repeating: "a", count: 5000)
        XCTAssertFalse(snapshot(original).canAppend("name")); XCTAssertThrowsError(try snapshot(original).applying(appending: "name", to: original))
        original.chapters[0].blocks![0].content += "a"; XCTAssertEqual(snapshot(original).reason, .unsupported)
    }

    func testExistingV2PayloadCarriesOnlyTextTokenAndNotTemplateConfiguration() throws {
        var original = draft(); original.preserved["publishMode"] = .string("pro"); original.chapters[0].blocks![0].sourceFields = nil
        let next = try snapshot(original).applying(appending: "name", to: original)
        let payload = try ProjectEditContract.payload(next, topicID: nil, scope: .full)
        let chapter = try XCTUnwrap(payload["chapters"]?.array?.first?.object), block = try XCTUnwrap(chapter["blocks"]?.array?.first?.object)
        XCTAssertEqual(block["content"], .string(original.chapters[0].blocks![0].content + "{name}"))
        let node = try XCTUnwrap(chapter["nodes"]?.array?.first?.object)
        XCTAssertNil(node["templateInfo"]); XCTAssertNil(node["advancedConfigJson"]); XCTAssertEqual(node["templateId"], .number(41))
    }

}
