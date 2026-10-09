import XCTest
@testable import QuestifyCore

final class ProjectChapterAudioTests: XCTestCase {
    func testReadingPreservesNilNullEmptyRawUnicodeAndUnknownWireTypes() throws {
        let values: [ProjectEditJSON?] = [nil, .null, .string(""), .string("  https://old.invalid/e\u{301}.mp3\n"), .number(12), .object(["future": .bool(true)])]
        for value in values {
            var draft = ProjectEditSyntheticFixtures.draft(product: .city)
            draft.chapters[0].preserved["audioUrl"] = value
            let before = ProjectEditPendingMaterials.exactData(draft)
            _ = ProjectChapterAudio.reference(in: draft.chapters[0])
            _ = ProjectChapterAudio.isUnsupported(in: draft.chapters[0])
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), before)
        }
    }
    func testClearChangesOnlyChapterURLAndExistingAudioCompanions() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .city)
        draft.chapters[0].preserved["audioUrl"] = .string("old/raw/e\u{301}.mp3")
        draft.chapters[0].preserved["audioFileName"] = .string("e\u{301}.mp3")
        draft.chapters[0].preserved["audioDuration"] = .number(42)
        draft.chapters[0].preserved["future"] = .object(["keep": .string("e\u{301}")])
        draft.chapters[0].blocks = [.init(kind: .audio, url: "story-audio-is-distinct")]
        var expected = draft
        expected.chapters[0].preserved["audioUrl"] = .string("")
        expected.chapters[0].preserved["audioFileName"] = .string("")
        expected.chapters[0].preserved["audioDuration"] = .number(0)
        let next = try ProjectChapterAudio.clearing(chapterID: draft.chapters[0].id, in: draft)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        let twice = try ProjectChapterAudio.clearing(chapterID: draft.chapters[0].id, in: next)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(twice), ProjectEditPendingMaterials.exactData(next))
    }
    func testAbsentNullAndEmptyNoOpsNeverSynthesizeCompanions() throws {
        let values: [ProjectEditJSON?] = [nil, .null, .string("")]
        for value in values {
            var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
            draft.chapters[0].preserved["audioUrl"] = value
            let next = try ProjectChapterAudio.clearing(chapterID: draft.chapters[0].id, in: draft)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(draft))
        }
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        draft.chapters[0].preserved["audioUrl"] = .string("raw")
        let next = try ProjectChapterAudio.clearing(chapterID: draft.chapters[0].id, in: draft)
        XCTAssertNil(next.chapters[0].preserved["audioFileName"])
        XCTAssertNil(next.chapters[0].preserved["audioDuration"])
    }
    func testUnknownMissingDuplicateAndCanonicalAliasCannotClear() throws {
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        draft.chapters[0].preserved["audioUrl"] = .bool(true)
        XCTAssertThrowsError(try ProjectChapterAudio.clearing(chapterID: draft.chapters[0].id, in: draft))
        draft.chapters[0].preserved["audioUrl"] = .string("raw")
        XCTAssertThrowsError(try ProjectChapterAudio.clearing(chapterID: "missing", in: draft))
        draft.chapters[0].id = "e\u{301}"
        XCTAssertThrowsError(try ProjectChapterAudio.clearing(chapterID: "é", in: draft))
        draft.chapters.append(draft.chapters[0])
        XCTAssertThrowsError(try ProjectChapterAudio.clearing(chapterID: "e\u{301}", in: draft))
    }
    func testChapterWireLimitIs512UTF16AndOverlongOldValueCanStillBeCleared() throws {
        XCTAssertTrue(ProjectChapterAudio.fitsWire(String(repeating: "😀", count: 256)))
        XCTAssertFalse(ProjectChapterAudio.fitsWire(String(repeating: "😀", count: 256) + "a"))
        XCTAssertTrue(ProjectChapterAudio.fitsWire(String(repeating: "a", count: 512)))
        var draft = ProjectEditSyntheticFixtures.draft(product: .city)
        draft.chapters[0].preserved["audioUrl"] = .string(String(repeating: "a", count: 513))
        let next = try ProjectChapterAudio.clearing(chapterID: draft.chapters[0].id, in: draft)
        XCTAssertEqual(ProjectChapterAudio.reference(in: next.chapters[0]), "")
    }
}
