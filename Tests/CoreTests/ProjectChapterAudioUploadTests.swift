import XCTest
@testable import QuestifyCore

@MainActor final class ProjectChapterAudioUploadTests: XCTestCase {
    private let session = try! ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "chapter-audio-tests")
    private let identity = try! ProjectEditDraftIdentity(topicID: 101)
    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    private func target(_ draft: ProjectEditDraft) throws -> ProjectStoryAudioTarget {
        try .init(chapterNarrationIn: draft, identity: identity, session: session, chapterID: draft.chapters[0].id)
    }
    private func receipt(_ length: Int = 40) throws -> ProjectStoryUploadedAudio {
        let prefix = "https://example.com/"
        return try .restore(attemptID: UUID(), ownerKey: session.ownerKey,
            reference: prefix + String(repeating: "a", count: max(0, length - prefix.utf16.count)), filename: "e\u{301}.mp3", format: .mp3)
    }
    func testOldBlockTargetDecodesAndReencodesExactSortedLegacyShapeWithoutKind() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].blocks = [.init(kind: .audio)]
        let block = draft.chapters[0].blocks![0]
        let target = try ProjectStoryAudioTarget(draft: draft, identity: identity, session: session, chapterID: draft.chapters[0].id, blockID: block.id)
        let old: [String: ProjectEditJSON] = ["id": .string(target.id.uuidString), "ownerKey": .string(session.ownerKey), "draftBucket": .string(identity.bucket),
            "chapterID": .string(target.chapterID), "blockID": .string(block.id), "originalDraftHash": .string(target.originalDraftHash)]
        let bytes = try encoded(old), decoded = try JSONDecoder().decode(ProjectStoryAudioTarget.self, from: bytes)
        XCTAssertEqual(decoded.kind, .storyBlock); XCTAssertEqual(decoded.blockID, block.id)
        XCTAssertEqual(try encoded(decoded), bytes); XCTAssertEqual(try encoded(target), bytes)
    }
    func testChapterTargetHasExplicitKindAndNoFakeBlockIDAndRejectsMixedShape() throws {
        let draft = ProjectEditSyntheticFixtures.draft(), target = try target(draft)
        let data = try encoded(target), object = try JSONDecoder().decode([String: ProjectEditJSON].self, from: data)
        XCTAssertEqual(object["kind"], .string("chapterNarration")); XCTAssertNil(object["blockID"])
        XCTAssertEqual(try JSONDecoder().decode(ProjectStoryAudioTarget.self, from: data), target)
        let invalidValues: [ProjectEditJSON] = [.null, .string("fake-block")]
        for invalid in invalidValues {
            var mixed = object; mixed["blockID"] = invalid
            XCTAssertThrowsError(try JSONDecoder().decode(ProjectStoryAudioTarget.self, from: encoded(mixed)))
        }
        var missing = object; missing["kind"] = nil
        XCTAssertThrowsError(try JSONDecoder().decode(ProjectStoryAudioTarget.self, from: encoded(missing)))
    }
    func testChapterJournalCannotRewriteOrReadOldBlockJournalAndReusesRecoveryCache() throws {
        let storage = ProjectEditMemoryStorage(), blockJournal = ProjectStoryAudioJournal(storage: storage)
        let chapterJournal = blockJournal.chapterNarrationJournal()
        XCTAssertTrue(chapterJournal === blockJournal.chapterNarrationJournal())
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].blocks = [.init(kind: .audio)]
        let blockTarget = try ProjectStoryAudioTarget(draft: draft, identity: identity, session: session, chapterID: draft.chapters[0].id, blockID: draft.chapters[0].blocks![0].id)
        let digest = String(repeating: "a", count: 64)
        let legacyTarget: [String: ProjectEditJSON] = ["id": .string(blockTarget.id.uuidString), "ownerKey": .string(session.ownerKey),
            "draftBucket": .string(identity.bucket), "chapterID": .string(blockTarget.chapterID), "blockID": .string(draft.chapters[0].blocks![0].id),
            "originalDraftHash": .string(blockTarget.originalDraftHash)]
        let legacy: [String: ProjectEditJSON] = ["version": .number(1), "ownerKey": .string(session.ownerKey), "draftBucket": .string(identity.bucket),
            "entries": .array([.object(["attemptID": .string(UUID().uuidString), "target": .object(legacyTarget), "selectedDigest": .string(digest), "applied": .bool(false)])])]
        let key = "project-story-audio.v1." + Data((session.ownerKey + ":" + identity.bucket).utf8).base64EncodedString()
        storage.data[key] = try encoded(legacy)
        let oldBytes = storage.data, chapterTarget = try target(draft)
        XCTAssertEqual(try blockJournal.read(session: session, identity: identity).entries[0].target, blockTarget)
        XCTAssertEqual(storage.data, oldBytes)
        let chapterSnapshot = try chapterJournal.begin(target: chapterTarget, digest: digest, expected: chapterJournal.read(session: session, identity: identity), session: session, identity: identity)
        for (key, bytes) in oldBytes { XCTAssertEqual(storage.data[key], bytes); XCTAssertTrue(key.hasPrefix("project-story-audio.v1.")) }
        XCTAssertEqual(storage.data.count, 2)
        XCTAssertTrue(storage.data.keys.contains { $0.hasPrefix("project-chapter-audio.v1.") })
        XCTAssertEqual(try blockJournal.read(session: session, identity: identity).entries.count, 1)
        XCTAssertEqual(chapterSnapshot.entries[0].target.kind, .chapterNarration)
        XCTAssertThrowsError(try blockJournal.begin(target: chapterTarget, digest: digest, expected: blockJournal.read(session: session, identity: identity), session: session, identity: identity))
        XCTAssertThrowsError(try chapterJournal.begin(target: blockTarget, digest: digest, expected: chapterSnapshot, session: session, identity: identity))
    }
    func testChapterApplyUses512Not500AndChangesOnlyActualChapterProperties() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].preserved["audioUrl"] = .string("old")
        draft.chapters[0].preserved["audioDuration"] = .number(42)
        draft.chapters[0].blocks = [.init(kind: .audio, url: "story-stays")]
        let target = try target(draft), receipt = try receipt(512)
        let next = try target.applying(receipt, to: draft, identity: identity, session: session)
        var expected = draft; expected.chapters[0].preserved["audioUrl"] = .string(receipt.reference)
        expected.chapters[0].preserved["audioFileName"] = .string(receipt.filename); expected.chapters[0].preserved["audioDuration"] = .number(0)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertTrue(target.hasAppliedReference(receipt, in: next, identity: identity, session: session))
        XCTAssertThrowsError(try target.applying(self.receipt(513), to: draft, identity: identity, session: session))
        let block = try ProjectStoryAudioTarget(draft: draft, identity: identity, session: session, chapterID: target.chapterID, blockID: draft.chapters[0].blocks![0].id)
        XCTAssertThrowsError(try block.applying(receipt, to: draft, identity: identity, session: session))
    }
    func testChapterDeletionReorderUnknownAndDuplicateCannotReceiveReference() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters.append(ProjectEditChapter())
        let target = try target(draft), receipt = try receipt()
        for action in ["delete", "reorder", "duplicate"] {
            var next = draft
            switch action { case "delete": next.chapters.removeFirst(); case "reorder": next.chapters.reverse(); default: next.chapters.append(next.chapters[0]) }
            XCTAssertThrowsError(try target.applying(receipt, to: next, identity: identity, session: session))
        }
        draft.chapters[0].preserved["audioUrl"] = .object(["future": .bool(true)])
        XCTAssertThrowsError(try self.target(draft))
    }
}
