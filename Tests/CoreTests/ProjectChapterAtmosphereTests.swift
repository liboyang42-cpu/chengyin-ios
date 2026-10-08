import XCTest
@testable import QuestifyCore

final class ProjectChapterAtmosphereTests: XCTestCase {
    func testExactFivePresetsAndSolidSourceColors() {
        XCTAssertEqual(ProjectChapterAtmosphere.allCases.map(\.rawValue), ["DEFAULT", "BLUE", "RED", "YELLOW", "WHITE"])
        XCTAssertEqual(ProjectChapterAtmosphere.allCases.map(\.backgroundRGB), [0x0A0A0A, 0x14294F, 0x4E1C24, 0x4E4114, 0xF5F6F8])
        XCTAssertEqual(ProjectChapterAtmosphere.allCases.map(\.foregroundRGB), [0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0x111318])
        XCTAssertNil(ProjectChapterAtmosphere(rawValue: "#14294F"))
    }
    func testKnownAliasesAreReadWithoutMutatingStoredBytes() throws {
        let examples: [(String, ProjectChapterAtmosphere)] = [
            ("NIGHT", .blue), ("ARCHIVE", .yellow), ("NEON", .red), ("MOSS", .black),
            ("\u{FEFF} blue \n", .blue), ("white", .white), ("", .black), ("   ", .black)
        ]
        for (raw, expected) in examples {
            var chapter = ProjectEditChapter(); chapter.preserved["atmospherePreset"] = .string(raw)
            let before = ProjectEditPendingMaterials.exactData(chapter)
            XCTAssertEqual(ProjectChapterAtmosphere.selected(in: chapter), expected, raw)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(chapter), before)
            let restored = try JSONDecoder().decode(ProjectEditChapter.self, from: JSONEncoder().encode(chapter))
            XCTAssertEqual(restored.preserved["atmospherePreset"], .string(raw))
        }
    }
    func testMissingAndNullUseReadOnlyDefaultWithoutCreatingAStoredValue() {
        for raw: ProjectEditJSON? in [nil, .null] {
            var chapter = ProjectEditChapter(); chapter.preserved["atmospherePreset"] = raw
            let before = chapter
            XCTAssertEqual(ProjectChapterAtmosphere.selected(in: chapter), .black)
            XCTAssertEqual(chapter, before)
        }
    }
    func testUnknownValuesArePreservedUntilExplicitKnownSelection() {
        for raw in [ProjectEditJSON.string("FUTURE"), .string("\u{0085}BLUE"), .string("#14294F"),
                    .number(1), .bool(true), .array([.string("BLUE")]), .object(["future": .string("BLUE")])] {
            var chapter = ProjectEditChapter(); chapter.preserved["atmospherePreset"] = raw
            let before = chapter
            XCTAssertNil(ProjectChapterAtmosphere.selected(in: chapter))
            XCTAssertFalse(ProjectChapterAtmosphere.canSubmit(chapter))
            var expected = chapter; expected.preserved["atmospherePreset"] = .string("RED")
            XCTAssertEqual(ProjectChapterAtmosphere.red.applying(to: chapter), expected)
            XCTAssertEqual(chapter, before)
        }
    }
    func testExplicitSelectionChangesOnlyAtmosphereAndKeepsStoryAndOpaqueFields() throws {
        var chapter = ProjectEditSyntheticFixtures.draft().chapters[0]
        chapter.preserved["atmospherePreset"] = .string("NIGHT")
        chapter.preserved["future"] = .object(["unrelated": .array([.null, .bool(true)])])
        chapter.preserved["audioUrl"] = .string("fixture:unchanged-audio")
        chapter.blocks = [.init(kind: .text, content: "  e\u{301}\n\nExact story.  "), .init(kind: .node, nodeID: chapter.nodes[0].id)]
        for preset in ProjectChapterAtmosphere.allCases {
            var expected = chapter; expected.preserved["atmospherePreset"] = .string(preset.rawValue)
            let actual = preset.applying(to: chapter)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(actual), ProjectEditPendingMaterials.exactData(expected))
            XCTAssertEqual(try JSONDecoder().decode(ProjectEditChapter.self, from: JSONEncoder().encode(actual)), actual)
        }
        XCTAssertEqual(chapter.preserved["atmospherePreset"], .string("NIGHT"))
    }
    func testSelectedValueFlowsThroughExistingCreateUpdateAndWhitelistContracts() throws {
        for preset in ProjectChapterAtmosphere.allCases {
            var draft = ProjectEditSyntheticFixtures.draft()
            draft.chapters[0] = preset.applying(to: draft.chapters[0])
            let restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(draft))
            for topicID: Int? in [nil, 71] {
                let payload = try ProjectEditContract.payload(restored, topicID: topicID, scope: .full)
                XCTAssertEqual(payload["chapters"]?.array?.first?.object?["atmospherePreset"], .string(preset.rawValue))
                XCTAssertNil(payload["atmospherePreset"])
            }
            XCTAssertNil(try ProjectEditContract.payload(restored, topicID: 71, scope: .whitelist)["chapters"])
        }
    }
    func testReadbackUsesExistingCanonicalAndAliasProjectionWithoutNewEndpoint() throws {
        for (raw, expected) in [("BLUE", "BLUE"), ("NIGHT", "BLUE"), ("ARCHIVE", "YELLOW"), ("NEON", "RED"), ("MOSS", "DEFAULT")] {
            let data = try ProjectEditRemoteFixtures.detail(product: .city)
            var envelope = try JSONDecoder().decode([String: ProjectEditJSON].self, from: data)
            var body = try XCTUnwrap(envelope["data"]?.object)
            var rows = try XCTUnwrap(body["chapters"]?.array)
            var first = try XCTUnwrap(rows[0].object)
            first["atmospherePreset"] = .string(raw); rows[0] = .object(first)
            body["chapters"] = .array(rows); envelope["data"] = .object(body)
            let snapshot = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(envelope), expectedTopicID: 71, owner: .personal)
            XCTAssertEqual(snapshot.draft.chapters[0].preserved["atmospherePreset"], .string(expected))
            XCTAssertEqual(ProjectChapterAtmosphere.selected(in: snapshot.draft.chapters[0])?.rawValue, expected)
        }
    }
    func testSubmissionSupportMatchesBackendTrimAndDoesNotRewriteOriginalFields() {
        for raw in [ProjectEditJSON.string(" BLUE \n"), .string("\u{0000}night\u{001F}"), .null] {
            var chapter = ProjectEditChapter(); chapter.preserved["atmospherePreset"] = raw
            XCTAssertTrue(ProjectChapterAtmosphere.canSubmit(chapter))
            XCTAssertEqual(chapter.preserved["atmospherePreset"], raw)
        }
        for raw in ["", "   ", "\u{FEFF}BLUE", "\u{00A0}BLUE", "BLUE future"] {
            var chapter = ProjectEditChapter(); chapter.preserved["atmospherePreset"] = .string(raw)
            XCTAssertFalse(ProjectChapterAtmosphere.canSubmit(chapter), raw)
        }
    }
    func testUnknownRemoteValueSurvivesDraftRestoreButRequiresExplicitChoiceBeforePayload() throws {
        for raw in [ProjectEditJSON.string("FUTURE"), .object(["version": .number(2), "palette": .string("MIDNIGHT")]), .number(7)] {
            var envelope = try JSONDecoder().decode([String: ProjectEditJSON].self, from: ProjectEditRemoteFixtures.detail(product: .city))
            var body = try XCTUnwrap(envelope["data"]?.object)
            var rows = try XCTUnwrap(body["chapters"]?.array)
            var chapter = try XCTUnwrap(rows[0].object)
            chapter["atmospherePreset"] = raw; rows[0] = .object(chapter)
            body["chapters"] = .array(rows); envelope["data"] = .object(body)
            let snapshot = try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(envelope), expectedTopicID: 71, owner: .personal)
            XCTAssertEqual(snapshot.draft.chapters[0].preserved["atmospherePreset"], raw)
            var restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(snapshot.draft))
            XCTAssertEqual(restored.chapters[0].preserved["atmospherePreset"], raw)
            XCTAssertNil(ProjectChapterAtmosphere.selected(in: restored.chapters[0]))
            XCTAssertThrowsError(try ProjectEditContract.payload(restored, topicID: 71, scope: .full))
            // Whitelist cannot mutate chapters and remains available for permitted metadata edits.
            XCTAssertNil(try ProjectEditContract.payload(restored, topicID: 71, scope: .whitelist)["chapters"])
            restored.chapters[0] = ProjectChapterAtmosphere.white.applying(to: restored.chapters[0])
            XCTAssertEqual(try ProjectEditContract.payload(restored, topicID: 71, scope: .full)["chapters"]?.array?.first?.object?["atmospherePreset"], .string("WHITE"))
        }
    }
    func testRemoteUnsupportedWhitespaceIsNotSilentlyLegalizedByDisplayNormalization() throws {
        for raw in ["", " \t\r\n", "\u{FEFF}BLUE", "\u{00A0}BLUE", "NIGHT\u{00A0}"] {
            let snapshot = try readback(.string(raw))
            XCTAssertEqual(snapshot.draft.chapters[0].preserved["atmospherePreset"], .string(raw))
            var restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(snapshot.draft))
            XCTAssertEqual(restored.chapters[0].preserved["atmospherePreset"], .string(raw))
            XCTAssertFalse(ProjectChapterAtmosphere.canSubmit(restored.chapters[0]))
            XCTAssertThrowsError(try ProjectEditContract.payload(restored, topicID: 71, scope: .full))
            restored.chapters[0] = ProjectChapterAtmosphere.blue.applying(to: restored.chapters[0])
            XCTAssertEqual(try ProjectEditContract.payload(restored, topicID: 71, scope: .full)["chapters"]?.array?.first?.object?["atmospherePreset"], .string("BLUE"))
        }
    }
    func testRemoteSupportedASCIIWhitespaceAliasesAndDefaultsKeepExistingContract() throws {
        let examples: [(ProjectEditJSON?, String)] = [
            (.string(" \tblue\r\n"), "BLUE"), (.string("\tnight\n"), "BLUE"),
            (.string(" ARCHIVE "), "YELLOW"), (.string("\rNEON\t"), "RED"),
            (.string(" moss\n"), "DEFAULT"), (nil, "DEFAULT"), (.null, "DEFAULT")
        ]
        for (raw, expected) in examples {
            let snapshot = try readback(raw)
            let restored = try JSONDecoder().decode(ProjectEditDraft.self, from: JSONEncoder().encode(snapshot.draft))
            XCTAssertEqual(restored.chapters[0].preserved["atmospherePreset"], .string(expected))
            XCTAssertTrue(ProjectChapterAtmosphere.canSubmit(restored.chapters[0]))
            XCTAssertEqual(try ProjectEditContract.payload(restored, topicID: 71, scope: .full)["chapters"]?.array?.first?.object?["atmospherePreset"], .string(expected))
        }
        // Java trim accepts these controls, while the JS display trim does not.
        // Preserve the accepted bytes rather than inventing a different preset.
        let controlValue = "\u{0000}NIGHT\u{001F}"
        let control = try readback(.string(controlValue)).draft
        XCTAssertEqual(control.chapters[0].preserved["atmospherePreset"], .string(controlValue))
        XCTAssertTrue(ProjectChapterAtmosphere.canSubmit(control.chapters[0]))
        XCTAssertEqual(try ProjectEditContract.payload(control, topicID: 71, scope: .full)["chapters"]?.array?.first?.object?["atmospherePreset"], .string(controlValue))
    }
    private func readback(_ raw: ProjectEditJSON?) throws -> ProjectEditSnapshot {
        var envelope = try JSONDecoder().decode([String: ProjectEditJSON].self, from: ProjectEditRemoteFixtures.detail(product: .city))
        var body = try XCTUnwrap(envelope["data"]?.object)
        var chapter = try XCTUnwrap(body["chapters"]?.array?.first?.object)
        chapter["atmospherePreset"] = raw
        body["chapters"] = .array([.object(chapter)]); envelope["data"] = .object(body)
        return try ProjectEditContract.decodeEditDetail(JSONEncoder().encode(envelope), expectedTopicID: 71, owner: .personal)
    }
}
