import XCTest
@testable import QuestifyCore

final class TemplateAuthoringMediaReferenceSnapshotTests: XCTestCase {
    func testCanonicalUnicodeEquivalenceDoesNotAuthorizeDifferentTextTagOrImageBytes() throws {
        let decomposed = "e\u{0301}", precomposed = "\u{00E9}"
        XCTAssertEqual(decomposed, precomposed) // Swift String equality alone is insufficient.
        XCTAssertNotEqual(Array(decomposed.utf8), Array(precomposed.utf8))
        for (stored, replacement) in [(decomposed, precomposed), (precomposed, decomposed)] {
            for field in ["text", "tag", "image"] {
                var draft = TemplateAuthoringDraft()
                let beat = TemplateStoryBeat(text: stored, tag: stored, imgs: [stored])
                draft.storyJson = String(decoding: try JSONEncoder().encode([beat.wire]), as: UTF8.self)
                var loaded = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
                if field == "text" { loaded[0].text = replacement }
                if field == "tag" { loaded[0].tag = replacement }
                if field == "image" { loaded[0].imgs[0] = replacement }
                XCTAssertThrowsError(try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: loaded))
                // The empty-editor-row fallback must perform the same exact-byte check.
                loaded.insert(.init(), at: 0)
                XCTAssertThrowsError(try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: loaded))
            }
        }
    }

    func testAcceptedUnicodeStoryInventoryPreservesActualReferenceAndOriginalJSONBytes() throws {
        let text = "e\u{0301}", tag = "\u{00E9}", references = ["asset:e\u{0301}", "asset:\u{00E9}"]
        var draft = TemplateAuthoringDraft()
        let beat = TemplateStoryBeat(text: text, tag: tag, imgs: references)
        draft.storyJson = String(decoding: try JSONEncoder().encode([beat.wire]), as: UTF8.self)
        let loaded = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: loaded)
        XCTAssertEqual(Array(try XCTUnwrap(snapshot.originalDraft.storyJson).utf8), Array(try XCTUnwrap(draft.storyJson).utf8))
        let actual = snapshot.references.suffix(2).map { Array(($0.raw ?? "").utf8) }
        XCTAssertEqual(actual, references.map { Array($0.utf8) })
        XCTAssertNotEqual(actual[0], actual[1])
    }

    func testFixedReferencesPreserveNilEmptyWhitespaceAndOpaqueHistoricalValues() throws {
        for raw in [nil, "", "  ", "relative/image.png", "asset:legacy", "https://unapproved.invalid/media?x=1"] as [String?] {
            var draft = TemplateAuthoringDraft()
            draft.questionImg = raw; draft.questionAudio = raw; draft.audioUrl = raw
            draft.storyImg = "legacy-story-image"; draft.storyText = "legacy story text"
            let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft)
            XCTAssertEqual(snapshot.originalDraft, draft)
            for field in [TemplateAuthoringMediaField.questionImage, .questionAudio, .narration] {
                let reference = try XCTUnwrap(snapshot.references.first { $0.slot.field == field })
                XCTAssertEqual(reference.raw, raw)
            }
            XCTAssertEqual(snapshot.originalDraft.storyImg, "legacy-story-image")
            XCTAssertEqual(snapshot.originalDraft.storyText, "legacy story text")
        }
    }

    func testAllChoiceLettersAndMediaKindsHaveSeparateSlotsWithExactStoredValues() throws {
        var draft = TemplateAuthoringDraft()
        let raw = "\n{\"A\":{\"img\":\" same \",\"audio\":\" same \"},\"B\":{\"img\":\"\"},\"C\":{},\"D\":{\"audio\":\"../sound\"}}\n"
        draft.questionOptionMediaJson = raw
        let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft)
        XCTAssertTrue(snapshot.supportsChoiceOptions); XCTAssertEqual(snapshot.references.count, 11)
        XCTAssertEqual(Set(snapshot.references.map { $0.slot.id }).count, 11)
        for letter in TemplateChoiceOptionMedia.Letter.allCases {
            let image = try XCTUnwrap(snapshot.references.first { $0.slot.field == .optionImage(letter) })
            let audio = try XCTUnwrap(snapshot.references.first { $0.slot.field == .optionAudio(letter) })
            XCTAssertEqual(image.raw, draft.choiceOptionMedia.text(letter, .image))
            XCTAssertEqual(audio.raw, draft.choiceOptionMedia.text(letter, .audio))
            XCTAssertNotEqual(image.slot.id, audio.slot.id)
        }
        XCTAssertEqual(snapshot.originalDraft.questionOptionMediaJson, raw)
    }

    func testUnsupportedChoiceJSONIsPreservedWithoutInventingEditableSlots() throws {
        for raw in ["unfinished{", "[]", #"{"A":{"img":"known","future":"retain"}}"#,
                    #"{"E":{"audio":"future"}}"#, String(repeating: " ", count: 65_537)] {
            var draft = TemplateAuthoringDraft(); draft.questionOptionMediaJson = raw
            let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft)
            XCTAssertFalse(snapshot.supportsChoiceOptions)
            XCTAssertEqual(snapshot.references.count, 3)
            XCTAssertEqual(snapshot.originalDraft.questionOptionMediaJson, raw)
        }
    }

    func testStoryUsesSuppliedLoadedUUIDsAndDistinctSlotsForDuplicateReferences() throws {
        var draft = TemplateAuthoringDraft()
        draft.storyJson = #"[{"text":"one","tag":"npc","imgs":[" duplicate "," duplicate "]},{"text":"two","tag":"","imgs":[" duplicate "]}]"#
        let loaded = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: loaded)
        let images = snapshot.references.filter {
            if case .storyBeatImage = $0.slot.field { return true }; return false
        }
        XCTAssertTrue(snapshot.supportsStory); XCTAssertEqual(images.count, 3)
        XCTAssertEqual(images.map(\.raw), [" duplicate ", " duplicate ", " duplicate "])
        XCTAssertEqual(images.map { $0.slot.field }, [.storyBeatImage(beatID: loaded[0].id),
            .storyBeatImage(beatID: loaded[0].id), .storyBeatImage(beatID: loaded[1].id)])
        XCTAssertEqual(Set(images.map { $0.slot.id }).count, 3)
        XCTAssertEqual(snapshot.originalDraft, draft)
    }

    func testStoryInventoryDoesNotInferIdentityWhenLoadedBeatsAreOmitted() throws {
        var draft = TemplateAuthoringDraft()
        draft.storyJson = #"[{"text":"one","tag":"","imgs":["raw"]}]"#
        let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft)
        XCTAssertTrue(snapshot.supportsStory); XCTAssertEqual(snapshot.references.count, 11)
        XCTAssertFalse(snapshot.references.contains {
            if case .storyBeatImage = $0.slot.field { return true }; return false
        })
    }

    func testReloadReallyMintsStoryUUIDsAndSnapshotSlotsAreNotDurable() throws {
        var draft = TemplateAuthoringDraft()
        draft.storyJson = #"[{"text":"one","tag":"","imgs":["raw"]}]"#
        let firstLoad = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        let secondLoad = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        XCTAssertEqual(firstLoad.map(\.wire), secondLoad.map(\.wire))
        XCTAssertNotEqual(firstLoad[0].id, secondLoad[0].id)
        let first = try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: firstLoad)
        let next = try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: secondLoad)
        XCTAssertTrue(Set(first.references.map { $0.slot.id }).isDisjoint(with: next.references.map { $0.slot.id }))
        XCTAssertEqual(first.originalDraft.storyJson, next.originalDraft.storyJson)
    }

    func testRejectsDuplicateLoadedBeatIDsAndChangedRawContent() throws {
        var draft = TemplateAuthoringDraft()
        draft.storyJson = #"[{"text":"one","tag":"","imgs":["a"]},{"text":"two","tag":"","imgs":["b"]}]"#
        let loaded = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        var duplicate = loaded; duplicate[1].id = duplicate[0].id
        XCTAssertThrowsError(try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: duplicate))
        var changed = loaded; changed[0].imgs = ["replacement"]
        XCTAssertThrowsError(try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: changed))
        XCTAssertThrowsError(try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: Array(loaded.reversed())))
        XCTAssertThrowsError(try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: []))
    }

    func testEmptyEditorRowsAreAcceptedUsingExistingSerializationRules() throws {
        var draft = TemplateAuthoringDraft()
        XCTAssertNoThrow(try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: [.init()]))
        draft.storyJson = #"[{"text":"one","tag":"","imgs":["raw"]}]"#
        var loaded = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        let keptID = loaded[0].id
        loaded.insert(.init(text: "\u{FEFF} \n", tag: "unsaved-tag"), at: 0)
        let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: loaded)
        XCTAssertEqual(snapshot.references.last?.slot.field, .storyBeatImage(beatID: keptID))
        XCTAssertEqual(snapshot.originalDraft, draft)
    }

    func testUnsupportedStoryRemainsOpaqueAndCannotReceiveLoadedBeatTargets() throws {
        for raw in ["unfinished{", "null", #"[{"text":"one","tag":"","imgs":[],"future":true}]"#,
                    #"[{"text":"one","tag":"","imgs":[42]}]"#] {
            var draft = TemplateAuthoringDraft(); draft.storyJson = raw
            let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft)
            XCTAssertFalse(snapshot.supportsStory); XCTAssertEqual(snapshot.originalDraft.storyJson, raw)
            XCTAssertThrowsError(try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: []))
        }
    }

    func testHistoricalOversizedStoryImageListIsInventoriedWithoutCappingOrRewriting() throws {
        var draft = TemplateAuthoringDraft()
        let beat = TemplateStoryBeat(text: "legacy", imgs: Array(repeating: " opaque ", count: 9))
        draft.storyJson = String(decoding: try JSONEncoder().encode([beat.wire]), as: UTF8.self)
        let loaded = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft, loadedStoryBeats: loaded)
        XCTAssertEqual(snapshot.references.count, 20)
        XCTAssertEqual(snapshot.references.suffix(9).map(\.raw), Array(repeating: " opaque ", count: 9))
        XCTAssertEqual(snapshot.originalDraft, draft)
    }

    func testInventoryDoesNotChangeDraftEncodingOrExistingWirePayload() throws {
        var draft = TemplateAuthoringDraft(title: "Local template")
        draft.validationMethod = .choice
        draft.questionImg = " historical question "; draft.questionAudio = "opaque audio"
        draft.questionOptionMediaJson = #"{"A":{"audio":" unchanged "}}"#
        draft.storyJson = "future unsupported story"; draft.audioUrl = "retained narration"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(draft)
        let payload = try TemplateAuthoringContract.payload(draft)
        let snapshot = try TemplateAuthoringMediaReferenceSnapshot(draft: draft)
        XCTAssertEqual(try encoder.encode(snapshot.originalDraft), before)
        XCTAssertEqual(try TemplateAuthoringContract.payload(snapshot.originalDraft), payload)
    }
}
