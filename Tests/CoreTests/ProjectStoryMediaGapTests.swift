import XCTest
@testable import QuestifyCore

@MainActor final class ProjectStoryMediaGapTests: XCTestCase {
    private let session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "media-gap-core")
    private let identity = try! ProjectEditDraftIdentity(topicID: 101)
    private func draft() -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(); value.preserved["publishMode"] = .string("pro")
        let chapter = value.chapters[0]
        value.chapters[0].blocks = [.init(kind: .text, content: chapter.description), .init(kind: .node, nodeID: chapter.nodes[0].id), .init(kind: .text, content: "Tail")]
        return value
    }
    private func receipt(_ id: UUID = UUID()) throws -> ProjectStoryUploadedImage {
        try .restore(attemptID: id, ownerKey: session.ownerKey, reference: "https://example.com/e%CC%81.jpg?x=1")
    }
    func testGapInsertsFirstMiddleEndAndPreservesEveryOtherBlock() throws {
        for index in [0, 1, 3] {
            let before = draft(), old = try XCTUnwrap(before.chapters[0].blocks), anchor = index < old.count ? old[index].id : nil
            let gap = try ProjectStoryMediaGap(draft: before, identity: identity, session: session, chapterID: before.chapters[0].id, before: anchor)
            let audio = ProjectEditBlock(kind: .audio), next = try gap.inserting(audio, into: before, identity: identity, session: session)
            XCTAssertEqual(next.chapters[0].blocks?[index], audio)
            XCTAssertEqual(next.chapters[0].blocks?.filter { $0.id != audio.id }, old)
            XCTAssertEqual(gap.beforeBlockID, anchor)
        }
    }
    func testImageBeforeActionIsDistinctFromLegacyAppendAndReplacement() throws {
        let before = draft(), chapter = before.chapters[0], anchor = try XCTUnwrap(chapter.blocks?[1].id)
        let insert = try ProjectStoryImageTarget(draft: before, identity: identity, session: session, chapterID: chapter.id, insertingBefore: anchor)
        let append = try ProjectStoryImageTarget(draft: before, identity: identity, session: session, chapterID: chapter.id)
        XCTAssertEqual(insert.action, .insertBefore(anchor)); XCTAssertEqual(append.action, .append); XCTAssertNotEqual(insert.action, append.action)
        let next = try insert.applying(receipt(), to: before, identity: identity, session: session)
        XCTAssertEqual(next.chapters[0].blocks?[1].id, insert.resultingBlockID)
        XCTAssertEqual(next.chapters[0].blocks?[2].id, anchor)
        XCTAssertThrowsError(try ProjectStoryImageTarget(draft: before, identity: identity, session: session, chapterID: chapter.id, replacing: anchor, insertingBefore: anchor))
    }
    func testMissingMovedDuplicateAndReplacedAnchorNeverFallBackToAppend() throws {
        let before = draft(), anchor = try XCTUnwrap(before.chapters[0].blocks?[1].id)
        let target = try ProjectStoryImageTarget(draft: before, identity: identity, session: session, chapterID: before.chapters[0].id, insertingBefore: anchor)
        for mutation in 0..<4 {
            var changed = before
            switch mutation {
            case 0: changed.chapters[0].blocks?.remove(at: 1)
            case 1: changed.chapters[0].blocks?.swapAt(0, 1)
            case 2: changed.chapters[0].blocks?.append(try XCTUnwrap(before.chapters[0].blocks?[1]))
            default: changed.chapters[0].blocks?[1] = .init(kind: .text, content: "replacement")
            }
            XCTAssertThrowsError(try target.applying(receipt(), to: changed, identity: identity, session: session))
        }
        XCTAssertThrowsError(try ProjectStoryMediaGap(draft: before, identity: identity, session: session, chapterID: before.chapters[0].id, before: "missing"))
    }
    func testDuplicateChapterBlockIDsLimitAndForeignOwnerAreRejected() throws {
        let before = draft(), chapter = before.chapters[0], anchor = try XCTUnwrap(chapter.blocks?.first?.id)
        var duplicate = before; duplicate.chapters.append(chapter)
        XCTAssertThrowsError(try ProjectStoryMediaGap(draft: duplicate, identity: identity, session: session, chapterID: chapter.id, before: anchor))
        duplicate = before; duplicate.chapters[0].blocks?.append(try XCTUnwrap(chapter.blocks?.first))
        XCTAssertThrowsError(try ProjectStoryMediaGap(draft: duplicate, identity: identity, session: session, chapterID: chapter.id, before: nil))
        var full = before; full.chapters[0].blocks = (0..<200).map { .init(kind: .text, content: String($0)) }
        XCTAssertThrowsError(try ProjectStoryMediaGap(draft: full, identity: identity, session: session, chapterID: chapter.id, before: nil))
        let gap = try ProjectStoryMediaGap(draft: before, identity: identity, session: session, chapterID: chapter.id, before: anchor)
        let other = try ProjectEditSession(accountID: 8, epoch: 2, storageNamespace: session.storageNamespace)
        XCTAssertThrowsError(try gap.inserting(.init(kind: .audio), into: before, identity: identity, session: other))
        XCTAssertThrowsError(try gap.inserting(.init(kind: .audio), into: before, identity: .init(topicID: 102), session: session))
    }
    func testAlreadyAppliedInsertRequiresExactGapAndOriginalDraftWithoutInsertedBlock() throws {
        let before = draft(), chapter = before.chapters[0], receipt = try receipt()
        let target = try ProjectStoryImageTarget(draft: before, identity: identity, session: session, chapterID: chapter.id, insertingBefore: try XCTUnwrap(chapter.blocks?[1].id))
        let applied = try target.applying(receipt, to: before, identity: identity, session: session)
        XCTAssertTrue(target.hasAppliedReference(receipt, in: applied, identity: identity, session: session))
        var moved = applied; moved.chapters[0].blocks?.swapAt(0, 1)
        XCTAssertFalse(target.hasAppliedReference(receipt, in: moved, identity: identity, session: session))
        var replaced = applied; replaced.chapters[0].blocks?[2].content = "changed anchor"
        XCTAssertFalse(target.hasAppliedReference(receipt, in: replaced, identity: identity, session: session))
        var duplicate = applied; duplicate.chapters[0].blocks?.append(try XCTUnwrap(applied.chapters[0].blocks?[1]))
        XCTAssertFalse(target.hasAppliedReference(receipt, in: duplicate, identity: identity, session: session))
    }
    func testLegacyVersionOneAppendAndReplaceJournalsDecodeUnchanged() throws {
        let before = draft(), storage = ProjectEditMemoryStorage(), journal = ProjectStoryImageJournal(storage: storage)
        let target = try ProjectStoryImageTarget(draft: before, identity: identity, session: session, chapterID: before.chapters[0].id)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as? [String: Any])
        let key = "project-story-image.v1." + Data((session.ownerKey + ":" + identity.bucket).utf8).base64EncodedString()
        for (oldAction, expected) in [(["append": [:]] as [String: Any], ProjectStoryImageTarget.Action.append), (["replace": ["_0": "old-image"]], .replace("old-image"))] {
            var legacy = encoded; legacy["action"] = oldAction
            let envelope: [String: Any] = ["version": 1, "ownerKey": session.ownerKey, "draftBucket": identity.bucket,
                "entries": [["attemptID": UUID().uuidString, "target": legacy, "selectedDigest": String(repeating: "a", count: 64), "reference": "https://example.com/old.jpg", "applied": false]]]
            try storage.write(JSONSerialization.data(withJSONObject: envelope), key: key)
            XCTAssertEqual(try journal.read(session: session, identity: identity).entries.first?.target.action, expected)
        }
    }
    func testNewInsertJournalRoundTripKeepsExactAnchorAndReceipt() throws {
        let before = draft(), chapter = before.chapters[0], storage = ProjectEditMemoryStorage(), journal = ProjectStoryImageJournal(storage: storage)
        let target = try ProjectStoryImageTarget(draft: before, identity: identity, session: session, chapterID: chapter.id, insertingBefore: try XCTUnwrap(chapter.blocks?[1].id))
        let receipt = try receipt(), empty = try journal.read(session: session, identity: identity)
        let pending = try journal.begin(target: target, digest: String(repeating: "a", count: 64), expected: empty, session: session, identity: identity, id: receipt.attemptID)
        _ = try journal.record(receipt, expected: pending, session: session, identity: identity)
        let cold = try ProjectStoryImageJournal(storage: storage).read(session: session, identity: identity)
        XCTAssertEqual(cold.entries.first?.target, target); XCTAssertEqual(cold.entries.first?.receipt, receipt)
    }
}
