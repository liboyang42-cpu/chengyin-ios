import XCTest
@testable import QuestifyCore

final class TemplateAuthoringStoryTests: XCTestCase {
    func testSourceSummaryTrimsDropsBlankTextAndKeepsOrderAndFullText() throws {
        var draft = TemplateAuthoringDraft(title: "Story"); draft.storyEnabled = true
        draft.storyText = "legacy text kept locally"
        try draft.setStory([.init(text: "  First \n", tag: "a"), .init(text: " \n", imgs: ["inert-ref"]), .init(text: " Second "), .init(tag: "tag-only")])
        XCTAssertEqual(try draft.preparedStoryText(), "First\nSecond")
        XCTAssertEqual(draft.storyText, "legacy text kept locally")
        let beats = try draft.storyBeats()
        XCTAssertEqual(beats.count, 3); XCTAssertEqual(beats[0].text, "  First \n")
        let before = draft, payload = try TemplateAuthoringContract.payload(draft)
        XCTAssertEqual(payload["storyText"], .string("First\nSecond")); XCTAssertEqual(payload["storyJson"], .string(draft.storyJson!))
        XCTAssertNil(payload["storyTimelineEdited"]); XCTAssertEqual(draft, before)
    }
    func testExactECMAScriptTrimWhitespaceSet() {
        for scalar in [0x0009, 0x000B, 0x000C, 0x000D, 0x0020, 0x00A0, 0x1680, 0x2000, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF] {
            let padding = String(UnicodeScalar(scalar)!)
            XCTAssertEqual(TemplateAuthoringStory.sourceTrim(padding + "x" + padding), "x")
        }
        for padding in ["\u{0085}", "\u{200B}"] { XCTAssertEqual(TemplateAuthoringStory.sourceTrim(padding + "x" + padding), padding + "x" + padding) }
    }
    func testSummaryUsesUTF16UnitsRatherThanGraphemes() throws {
        XCTAssertEqual(try TemplateAuthoringStory.summary([.init(text: String(repeating: "x", count: 501))]), String(repeating: "x", count: 500))
        let emoji = String(repeating: "😀", count: 250)
        XCTAssertEqual(try TemplateAuthoringStory.summary([.init(text: emoji + "more")]), emoji)
        let combining = String(repeating: "e\u{301}", count: 251)
        XCTAssertEqual(try TemplateAuthoringStory.summary([.init(text: combining)]).utf16.count, 500)
    }
    func testSplitSurrogateBlocksRequestWithoutCorruptingFullText() throws {
        var draft = TemplateAuthoringDraft(title: "Story"); draft.storyEnabled = true
        let full = String(repeating: "x", count: 499) + "😀tail"
        try draft.setStory([.init(text: full)])
        let before = draft
        XCTAssertThrowsError(try draft.preparedStoryText()) { XCTAssertEqual($0 as? TemplateAuthoringStory.Issue, .summarySurrogateBoundary) }
        XCTAssertEqual(draft.storyProjectionIssue, "templateStory.summaryBoundary")
        XCTAssertTrue(draft.publishIssues.contains("templateStory.summaryBoundary"))
        XCTAssertThrowsError(try TemplateAuthoringContract.request(draft, intent: .saveDraft))
        XCTAssertEqual(try draft.storyBeats().first?.text, full); XCTAssertEqual(draft, before)
    }
    func testNewSeventhImageIsRejectedAtomically() throws {
        var draft = TemplateAuthoringDraft(); draft.storyText = "preserved"
        try draft.setStory([.init(text: "Beat", imgs: (1...6).map(String.init))])
        let before = draft
        XCTAssertThrowsError(try draft.setStory([.init(text: "Changed", imgs: (1...7).map(String.init))])) {
            XCTAssertEqual($0 as? TemplateAuthoringStory.Issue, .imageLimit)
        }
        XCTAssertEqual(draft, before)
    }
    func testHistoricalOversizedImageListIsKeptAndCanBeReducedNotExpandedOrDuplicated() throws {
        var draft = TemplateAuthoringDraft()
        let refs = (1...8).map(String.init)
        draft.storyJson = String(decoding: try JSONEncoder().encode([TemplateStoryBeat(text: "Old", imgs: refs).wire]), as: UTF8.self)
        var beats = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson)
        beats[0].text = "Edited"; try draft.setStory(beats)
        XCTAssertEqual(try draft.storyBeats()[0].imgs, refs)
        beats[0].imgs.remove(at: 3); try draft.setStory(beats)
        XCTAssertEqual(try draft.storyBeats()[0].imgs.count, 7)
        let before = draft
        var expanded = beats; expanded[0].imgs.append("new")
        XCTAssertThrowsError(try draft.setStory(expanded)); XCTAssertEqual(draft, before)
        XCTAssertThrowsError(try draft.setStory(beats + beats)); XCTAssertEqual(draft, before)
        beats[0].imgs.removeLast(); try draft.setStory(beats)
        XCTAssertEqual(try draft.storyBeats()[0].imgs.count, 6)
    }
    func testReorderedOverlappingHistoricalImageListsEachRetainTheirOwnAllowance() throws {
        let longer = TemplateStoryBeat(text: "Eight", imgs: (1...8).map(String.init))
        let shorter = TemplateStoryBeat(text: "Seven", imgs: (1...7).map(String.init))
        XCTAssertNoThrow(try TemplateAuthoringStory.validateImageEdits([shorter, longer], original: [longer, shorter]))
        XCTAssertThrowsError(try TemplateAuthoringStory.validateImageEdits([longer, longer], original: [longer, shorter]))
    }
    func testUnknownMalformedAndMissingFieldsStayUntouchedAndCannotBeEdited() throws {
        for raw in ["{broken", "[null]", #"[{"text":"x","tag":"t","imgs":[],"future":9007199254740993}]"#, #"[{"text":"x","imgs":[]}]"#, #"[{"text":"x","tag":"t","imgs":[null]}]"#] {
            var draft = TemplateAuthoringDraft(title: "Old"); draft.storyEnabled = true
            draft.storyJson = raw; draft.storyText = " old independent text "
            let before = draft
            XCTAssertThrowsError(try TemplateAuthoringStory.editableBeats(raw: raw))
            XCTAssertThrowsError(try draft.setStory([.init(text: "overwrite")]))
            let payload = try TemplateAuthoringContract.payload(draft)
            XCTAssertEqual(payload["storyJson"], .string(raw)); XCTAssertEqual(payload["storyText"], .string(" old independent text "))
            XCTAssertEqual(draft, before)
        }
    }
    func testReadingAndPreparingUneditedSupportedTimelineKeepsOriginalBytes() throws {
        var draft = TemplateAuthoringDraft(title: "Old"); draft.storyEnabled = true
        draft.storyJson = " \n[ { \"imgs\": [], \"tag\": \"\", \"text\": \" beat \" } ]\n"
        draft.storyText = "Original independent summary"
        let before = draft
        _ = try TemplateAuthoringStory.editableBeats(raw: draft.storyJson); _ = try draft.storyBeats()
        let payload = try TemplateAuthoringContract.payload(draft)
        XCTAssertEqual(payload["storyJson"], .string(before.storyJson!)); XCTAssertEqual(payload["storyText"], .string(before.storyText!))
        XCTAssertNil(draft.storyTimelineEdited); XCTAssertEqual(draft, before)
    }
    func testExplicitEmptyTimelineClearsProjectionWithoutErasingStoredLegacyText() throws {
        var draft = TemplateAuthoringDraft(title: "Story"); draft.storyEnabled = true; draft.storyText = "old"
        try draft.setStory([.init(text: " \n", tag: "only tag")])
        XCTAssertEqual(draft.storyJson, ""); XCTAssertEqual(draft.storyText, "old")
        XCTAssertEqual(try draft.preparedStoryText(), "")
        let payload = try TemplateAuthoringContract.payload(draft)
        XCTAssertEqual(payload["storyJson"], .string("")); XCTAssertEqual(payload["storyText"], .string(""))
    }
    func testDisabledStoryOmitsWireFieldsButKeepsDataForReenable() throws {
        var draft = TemplateAuthoringDraft(title: "Story"); draft.storyText = "old"
        try draft.setStory([.init(text: "new")]); let before = draft
        let payload = try TemplateAuthoringContract.payload(draft)
        XCTAssertNil(payload["storyText"]); XCTAssertNil(payload["storyJson"]); XCTAssertEqual(draft, before)
        draft.storyEnabled = true; XCTAssertEqual(try TemplateAuthoringContract.payload(draft)["storyText"], .string("new"))
    }
    func testOptionalMarkerRoundTripsAndOldEnvelopeStillDecodes() throws {
        var draft = TemplateAuthoringDraft(title: "Story"); try draft.setStory([.init(text: "derived")])
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored.storyTimelineEdited, true); XCTAssertEqual(try restored.preparedStoryText(), "derived")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        object.removeValue(forKey: "storyTimelineEdited"); object["storyText"] = "historical"
        let old = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.storyTimelineEdited); XCTAssertEqual(try old.preparedStoryText(), "historical")
    }
}

#if DEBUG
@MainActor final class TemplateAuthoringStoryStorageTests: XCTestCase {
    func testStoreRestoresExplicitMarkerAndOriginalIndependentText() throws {
        let session = try TemplateAuthoringSession(accountID: 11, namespace: "story", epoch: 1, authorizationRevision: "member")
        let identity = TemplateAuthoringIdentity(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        var draft = TemplateAuthoringDraft(title: "Stored story"); draft.storyText = "keep historical text"
        try draft.setStory([.init(text: " derived ")]); try store.save(draft, session: session, identity: identity)
        guard case .ready(let envelope) = store.load(session: session, identity: identity) else { return XCTFail("Stored draft missing") }
        XCTAssertEqual(envelope.draft, draft); XCTAssertEqual(try envelope.draft.preparedStoryText(), "derived")
        XCTAssertEqual(envelope.draft.storyText, "keep historical text")
    }
}

#endif
