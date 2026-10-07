import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ProjectStoryExistingSaveTests: XCTestCase {
    private final class Storage: ProjectEditDataStorage {
        var values: [String: Data] = [:], attempts = 0
        var failAt: Int?, failReads = false
        func read(_ key: String) throws -> Data? { if failReads { throw ProjectEditError.persistenceUnavailable }; return values[key] }
        func write(_ data: Data, key: String) throws {
            attempts += 1
            if attempts == failAt { throw ProjectEditError.persistenceUnavailable }
            values[key] = data
        }
        func remove(_ key: String) throws { values[key] = nil }
    }
    private func session(_ account: Int = 7, namespace: String = "story-single-item") throws -> ProjectEditSession {
        try .init(accountID: account, epoch: 1, storageNamespace: namespace)
    }
    private func draft() -> ProjectEditDraft {
        var draft = ProjectEditDraft(product: .city); draft.name = "Saved city"
        var chapter = ProjectEditChapter(); chapter.description = "Saved story"
        chapter.blocks = [.init(kind: .text, content: chapter.description)]; draft.chapters = [chapter]
        var pending = ProjectEditNode(); pending.name = "Keep e\u{301}"; pending.localMetadata = ["future": .array([.null, .bool(true)])]
        draft.pendingMaterials = [.init(node: pending)]
        return draft
    }
    private func pointer(_ storage: Storage) throws -> String {
        try XCTUnwrap(storage.values.first(where: {
            guard let identity = try? JSONDecoder().decode(ProjectEditDraftIdentity.self, from: $0.value) else { return false }
            return identity.topicID == nil && identity.draftUUID.flatMap(UUID.init(uuidString:)) != nil
        })?.key)
    }
    private func envelope(_ storage: Storage, id: ProjectEditDraftIdentity) throws -> String {
        try XCTUnwrap(storage.values.first(where: { (try? JSONDecoder().decode(ProjectEditEnvelope.self, from: $0.value).identity) == id })?.key)
    }
    private func restored(_ store: ProjectEditLocalStore, session: ProjectEditSession, id: ProjectEditDraftIdentity, baseline: ProjectEditDraft) throws -> ProjectEditDraft {
        guard case .ready(let value) = store.load(session: session, identity: id, baseline: baseline) else { throw ProjectEditError.persistenceUnavailable }
        return value.draft
    }
    func testExistingNewDraftHasOneCommitAndNoSecondPointerWrite() throws {
        let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), id = try ProjectEditDraftIdentity(), original = draft()
        try store.save(original, session: session, identity: id)
        let pointerKey = try pointer(storage), pointerBytes = storage.values[pointerKey], before = storage.attempts
        var next = original; next.chapters[0].blocks?.append(.init(kind: .text, content: "Inserted"))
        storage.failAt = before + 2
        XCTAssertTrue(store.canReplaceExistingStoryDraft(original, session: session, identity: id))
        try store.replaceExistingStoryDraft(next, replacing: original, session: session, identity: id)
        XCTAssertEqual(storage.attempts, before + 1, "There is no second write to fail after a committed insertion")
        XCTAssertEqual(storage.values[pointerKey], pointerBytes)
        XCTAssertEqual(try restored(ProjectEditLocalStore(storage: storage), session: session, id: id, baseline: original), next)
        XCTAssertEqual(next.pendingMaterials, original.pendingMaterials)
    }
    func testFailedSingleCommitLeavesExactBytesAndRetryCommitsOnce() throws {
        let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), id = try ProjectEditDraftIdentity(), original = draft()
        try store.save(original, session: session, identity: id)
        var next = original; next.name = "Changed"
        let before = storage.values, attempts = storage.attempts; storage.failAt = attempts + 1
        XCTAssertThrowsError(try store.replaceExistingStoryDraft(next, replacing: original, session: session, identity: id))
        XCTAssertEqual(storage.values, before); XCTAssertEqual(storage.attempts, attempts + 1)
        XCTAssertEqual(try restored(ProjectEditLocalStore(storage: storage), session: session, id: id, baseline: original), original)
        storage.failAt = nil
        try store.replaceExistingStoryDraft(next, replacing: original, session: session, identity: id)
        XCTAssertEqual(storage.attempts, attempts + 2)
        XCTAssertEqual(try restored(ProjectEditLocalStore(storage: storage), session: session, id: id, baseline: original), next)
        XCTAssertThrowsError(try store.replaceExistingStoryDraft(next, replacing: original, session: session, identity: id))
        XCTAssertEqual(storage.attempts, attempts + 2, "A stale preimage cannot replay")
    }
    func testMissingConflictingAndCorruptActivePointersRefuseWithoutAnyWrite() throws {
        for mutation in 0..<4 {
            let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), id = try ProjectEditDraftIdentity(), original = draft()
            try store.save(original, session: session, identity: id); let key = try pointer(storage)
            switch mutation {
            case 0: storage.values[key] = nil
            case 1: storage.values[key] = try JSONEncoder().encode(ProjectEditDraftIdentity())
            case 2: storage.values[key] = Data("invalid".utf8)
            default: storage.values[key] = Data(("{\"draftUUID\":\"" + (id.draftUUID ?? "") + "\",\"draftUUID\":\"" + (id.draftUUID ?? "") + "\"}").utf8)
            }
            let before = storage.values, attempts = storage.attempts
            XCTAssertFalse(store.canReplaceExistingStoryDraft(original, session: session, identity: id))
            XCTAssertThrowsError(try store.replaceExistingStoryDraft(original, replacing: original, session: session, identity: id))
            XCTAssertEqual(storage.values, before); XCTAssertEqual(storage.attempts, attempts)
        }
    }
    func testMissingForeignMalformedAndChangedEnvelopesRefuseWithoutAnyWrite() throws {
        for mutation in 0..<9 {
            let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), id = try ProjectEditDraftIdentity(), original = draft()
            try store.save(original, session: session, identity: id); let key = try envelope(storage, id: id)
            if mutation == 0 { storage.values[key] = nil }
            else if mutation == 1 { storage.values[key] = Data("invalid".utf8) }
            else {
                var raw = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(storage.values[key]))
                switch mutation {
                case 2: raw["accountID"] = .number(8)
                case 3: raw["namespace"] = .string("foreign")
                case 4: raw["version"] = .number(9)
                case 5: raw["baseRevision"] = .string("changed")
                default:
                    var value = try XCTUnwrap(raw["draft"]?.object)
                    if mutation == 6 { value["owner"] = .string("MERCHANT") }
                    if mutation == 7 { value["name"] = .string("Later saved content") }
                    if mutation == 8 { value["unknownFuture"] = .bool(true) }
                    raw["draft"] = .object(value)
                }
                storage.values[key] = try JSONEncoder().encode(raw)
            }
            let before = storage.values, attempts = storage.attempts
            XCTAssertFalse(store.canReplaceExistingStoryDraft(original, session: session, identity: id))
            XCTAssertThrowsError(try store.replaceExistingStoryDraft(original, replacing: original, session: session, identity: id))
            XCTAssertEqual(storage.values, before); XCTAssertEqual(storage.attempts, attempts)
        }
    }
    func testUnsavedDraftAndReadFailuresDoNotInitializeOrFallbackToOrdinarySave() throws {
        let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), id = try ProjectEditDraftIdentity(), original = draft()
        XCTAssertFalse(store.canReplaceExistingStoryDraft(original, session: session, identity: id))
        XCTAssertThrowsError(try store.replaceExistingStoryDraft(original, replacing: original, session: session, identity: id))
        XCTAssertTrue(storage.values.isEmpty); XCTAssertEqual(storage.attempts, 0)
        try store.save(original, session: session, identity: id); let before = storage.values, attempts = storage.attempts
        storage.failReads = true
        XCTAssertThrowsError(try store.replaceExistingStoryDraft(original, replacing: original, session: session, identity: id))
        XCTAssertEqual(storage.values, before); XCTAssertEqual(storage.attempts, attempts)
    }
    func testDifferentActiveIdentityDoesNotSwitchPointerOrHideEitherOldDraft() throws {
        let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), a = try ProjectEditDraftIdentity(), b = try ProjectEditDraftIdentity(), original = draft()
        var other = original; other.name = "Other committed draft"
        try store.save(original, session: session, identity: a); try store.save(other, session: session, identity: b)
        let before = storage.values, attempts = storage.attempts
        XCTAssertThrowsError(try store.replaceExistingStoryDraft(other, replacing: original, session: session, identity: a))
        XCTAssertEqual(storage.values, before); XCTAssertEqual(storage.attempts, attempts)
        XCTAssertEqual(try store.activeIdentity(session: session, product: .city, owner: .personal), b)
        XCTAssertEqual(try restored(store, session: session, id: a, baseline: original), original)
        XCTAssertEqual(try restored(store, session: session, id: b, baseline: other), other)
    }
    func testTopicIdentityUsesExistingKnownRevisionAndOneEnvelopeWrite() throws {
        let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), id = try ProjectEditDraftIdentity(topicID: 51)
        var original = draft(); original.baseRevision = "r1"
        try store.save(original, session: session, identity: id)
        var next = original; next.name = "Inserted"; let attempts = storage.attempts
        try store.replaceExistingStoryDraft(next, replacing: original, session: session, identity: id)
        XCTAssertEqual(storage.attempts, attempts + 1); XCTAssertEqual(storage.values.count, 1)
        XCTAssertEqual(try restored(store, session: session, id: id, baseline: original), next)
        var missingRevision = next; missingRevision.baseRevision = ""
        XCTAssertFalse(store.canReplaceExistingStoryDraft(missingRevision, session: session, identity: id))
        XCTAssertThrowsError(try store.replaceExistingStoryDraft(missingRevision, replacing: next, session: session, identity: id))
        XCTAssertEqual(storage.attempts, attempts + 1)
    }
    func testOwnerProductAndRevisionCannotChangeAcrossNarrowCommit() throws {
        let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), id = try ProjectEditDraftIdentity(), original = draft()
        try store.save(original, session: session, identity: id); let attempts = storage.attempts, before = storage.values
        for mutation in 0..<3 {
            var next = original
            if mutation == 0 { next.owner = .merchant }
            if mutation == 1 { next.product = .freeExplore }
            if mutation == 2 { next.baseRevision = "different" }
            XCTAssertThrowsError(try store.replaceExistingStoryDraft(next, replacing: original, session: session, identity: id))
        }
        XCTAssertEqual(storage.attempts, attempts); XCTAssertEqual(storage.values, before)
    }
    func testCanonicalUnicodeDifferenceAndUnknownEnvelopeFieldsRefuseExactPreimage() throws {
        let storage = Storage(), store = ProjectEditLocalStore(storage: storage), session = try session(), id = try ProjectEditDraftIdentity()
        var original = draft(); original.name = "e\u{301}"
        try store.save(original, session: session, identity: id)
        var normalized = original; normalized.name = "é"
        let attempts = storage.attempts
        XCTAssertFalse(store.canReplaceExistingStoryDraft(normalized, session: session, identity: id))
        XCTAssertThrowsError(try store.replaceExistingStoryDraft(normalized, replacing: normalized, session: session, identity: id))
        let key = try envelope(storage, id: id)
        var raw = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(storage.values[key]))
        raw["unknownEnvelopeField"] = .bool(true); storage.values[key] = try JSONEncoder().encode(raw)
        let before = storage.values
        XCTAssertThrowsError(try store.replaceExistingStoryDraft(original, replacing: original, session: session, identity: id))
        XCTAssertEqual(storage.values, before); XCTAssertEqual(storage.attempts, attempts)
    }

}
