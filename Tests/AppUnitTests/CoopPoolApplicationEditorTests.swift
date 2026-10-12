import XCTest
@testable import Questify

@MainActor final class CoopPoolApplicationEditorTests: XCTestCase {
    func testStableOwnerRejectsQueuedOldReaderBeforeItCanRebind() throws {
        let f = Fixture(), owner = CoopPoolApplicationOwnerBinding()
        let oldContext = try XCTUnwrap(f.context)
        let oldSource = CoopPoolApplicationHost.Source(readerID: ObjectIdentifier(f.reader), session: f.reader.session,
            loadedSession: f.loaded, generation: f.generation, poolBytes: try f.pool.canonical(), isCurrent: true)
        owner.synchronize(oldSource, model: f.model); f.model.appear()
        owner.open(context: oldContext, reader: f.reader, model: f.model); XCTAssertNotNil(f.model.session)
        let replacement = Reader(), newGeneration = UUID()
        let newSource = CoopPoolApplicationHost.Source(readerID: ObjectIdentifier(replacement), session: replacement.session,
            loadedSession: replacement.session, generation: newGeneration, poolBytes: try f.pool.canonical(), isCurrent: true)
        owner.synchronize(newSource, model: f.model); XCTAssertNil(f.model.session)
        owner.open(context: oldContext, reader: f.reader, model: f.model); XCTAssertNil(f.model.session)
        XCTAssertFalse(owner.permits(context: oldContext, reader: f.reader))
        let fresh = try XCTUnwrap(CoopPoolApplicationModel.Context(reader: replacement, topicID: 10,
            pool: f.pool, loadedSession: replacement.session, generation: newGeneration))
        owner.open(context: fresh, reader: replacement, model: f.model)
        let session = try XCTUnwrap(f.model.session); XCTAssertEqual(session.context, fresh)
        owner.leave(model: f.model)
        owner.open(context: fresh, reader: replacement, model: f.model); XCTAssertNil(f.model.session)
        XCTAssertEqual(f.reader.reads + replacement.reads, 0)
    }
    func testConcreteOwnerOldDismissalCannotCloseReopenedPoolDraft() throws {
        let f = Fixture(), old = try f.open()
        let oldOwner = CoopPoolApplicationOwner(session: old, model: f.model, reader: f.reader, currentContext: { f.context })
        let oldBinding = oldOwner.presentationBinding
        XCTAssertTrue(oldBinding.wrappedValue)
        oldBinding.wrappedValue = false; XCTAssertNil(f.model.session)
        let fresh = try f.open(), review = try f.review(fresh, " retained \n")
        XCTAssertNotEqual(old.id, fresh.id); XCTAssertFalse(oldBinding.wrappedValue)
        oldBinding.wrappedValue = false
        XCTAssertEqual(f.model.session?.id, fresh.id); XCTAssertTrue(f.allows(review, fresh, " retained \n"))
        let currentOwner = CoopPoolApplicationOwner(session: fresh, model: f.model, reader: f.reader, currentContext: { f.context })
        let currentBinding = currentOwner.presentationBinding
        XCTAssertTrue(currentBinding.wrappedValue)
        currentBinding.wrappedValue = false; XCTAssertNil(f.model.session)
        XCTAssertFalse(f.allows(review, fresh, " retained \n")); XCTAssertEqual(f.reader.reads, 0)
    }
    @MainActor private final class Fixture {
        let model = CoopPoolApplicationModel(), reader = Reader()
        var generation = UUID(), topicID = 10
        var pool: CoopFlowJSON = .object(["hasClub": .bool(true), "rows": .array([.object(["topicId": .id(10), "name": .string("Topic"), "merchantNick": .string("Merchant"), "state": .string("open")])])])
        var loaded: CoopFlowSession? = try! .init(accountID: 7, epoch: 1, token: "synthetic-fixture")
        var context: CoopPoolApplicationModel.Context? { .init(reader: reader, topicID: topicID, pool: pool, loadedSession: loaded, generation: generation) }
        func open() throws -> CoopPoolApplicationModel.Session {
            model.bind(context); model.appear(); model.open(context: context, reader: reader); return try XCTUnwrap(model.session)
        }
        func review(_ session: CoopPoolApplicationModel.Session, _ message: String = "note") throws -> CoopPoolApplicationModel.Review {
            try XCTUnwrap(model.review(message: message, session: session, context: context, reader: reader))
        }
        func allows(_ review: CoopPoolApplicationModel.Review, _ session: CoopPoolApplicationModel.Session, _ message: String = "note") -> Bool {
            model.allows(review, session: session, message: message, context: context, reader: reader)
        }
    }
    func testLocalEntryAndPreviewMakeNoReadsOrWrites() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session, " original \n")
        XCTAssertEqual(try review.operation.body()["message"], .string(" original \n")); XCTAssertTrue(f.allows(review, session, " original \n")); XCTAssertEqual(f.reader.reads, 0)
    }
    func testRepeatedEntryDoesNotResetCurrentEditingSession() throws {
        let f = Fixture(), session = try f.open(); f.model.open(context: f.context, reader: f.reader); XCTAssertEqual(f.model.session?.id, session.id)
    }
    func testPreviewBackAndModifyRetainsCallerDraftOriginalBytes() throws {
        let f = Fixture(), session = try f.open(); var message = "  first\n"
        let old = try f.review(session, message); XCTAssertTrue(f.allows(old, session, message))
        f.model.invalidateReview(sessionID: session.id); XCTAssertEqual(message, "  first\n")
        message += "second"; let new = try f.review(session, message)
        XCTAssertFalse(f.allows(old, session, message)); XCTAssertTrue(f.allows(new, session, message)); XCTAssertEqual(try new.operation.body()["message"], .string(message))
    }
    func testSecondConfirmationReplacesOldReviewNonce() throws {
        let f = Fixture(), session = try f.open(), old = try f.review(session), new = try f.review(session)
        XCTAssertFalse(f.allows(old, session)); XCTAssertTrue(f.allows(new, session))
    }
    func testMessageChangeAndCanonicalUnicodeAlternativeInvalidateReview() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session, "é")
        XCTAssertFalse(f.allows(review, session, "e\u{301}")); XCTAssertFalse(f.allows(review, session, "other"))
    }
    func testCancelAndReopenRetireOldReviewAndDismissal() throws {
        let f = Fixture(), old = try f.open(), review = try f.review(old)
        f.model.cancel(id: old.id); let new = try f.open(); f.model.cancel(id: old.id)
        XCTAssertEqual(f.model.session?.id, new.id); XCTAssertFalse(f.allows(review, old)); XCTAssertNil(f.model.review(message: "stale", session: old, context: f.context, reader: f.reader))
    }
    func testRetiredEditorCannotInvalidateNewReview() throws {
        let f = Fixture(), old = try f.open(); f.model.cancel(); let new = try f.open(), review = try f.review(new)
        f.model.invalidateReview(sessionID: old.id); XCTAssertTrue(f.allows(review, new))
    }
    func testBackgroundAndReturnDoNotRestoreOldSession() throws {
        let f = Fixture(), old = try f.open(), review = try f.review(old)
        f.model.leave(); f.model.appear(); XCTAssertNil(f.model.session); XCTAssertFalse(f.allows(review, old))
        let new = try f.open(); XCTAssertNotEqual(new.id, old.id)
    }
    func testAccountEpochTokenOrSignOutInvalidatesContext() throws {
        let replacements: [CoopFlowSession?] = [try .init(accountID: 8, epoch: 1, token: "synthetic-fixture"), try .init(accountID: 7, epoch: 2, token: "synthetic-fixture"), try .init(accountID: 7, epoch: 1, token: "replacement-fixture"), nil]
        for replacement in replacements {
            let f = Fixture(), session = try f.open(), review = try f.review(session); f.reader.session = replacement
            XCTAssertFalse(f.allows(review, session)); XCTAssertNil(f.model.review(message: "old", session: session, context: f.context, reader: f.reader))
        }
    }
    func testReaderReplacementCannotReuseSameSession() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session), replacement = Reader()
        XCTAssertFalse(f.model.allows(review, session: session, message: "note", context: f.context, reader: replacement))
    }
    func testTopicSelectionCannotCrossOldReview() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session); f.topicID = 11
        XCTAssertNil(f.context); f.model.bind(f.context); XCTAssertFalse(f.allows(review, session))
    }
    func testGenerationChangeRetiresCallbacksEvenForIdenticalPool() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session); f.generation = UUID(); f.model.bind(f.context)
        XCTAssertFalse(f.allows(review, session)); XCTAssertNil(f.model.review(message: "old", session: session, context: f.context, reader: f.reader))
    }
    func testMerchantRowChangeCannotReuseCurrentTopicReview() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session)
        f.pool = .object(["hasClub": .bool(true), "rows": .array([.object(["topicId": .id(10), "name": .string("Topic"), "merchantNick": .string("Replacement"), "state": .string("open")])])])
        f.model.bind(f.context); XCTAssertFalse(f.allows(review, session))
    }
    func testLostClubOrPoolEvidenceCannotKeepReview() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session); f.pool = .object(["hasClub": .bool(false), "rows": .array([])])
        f.model.bind(f.context); XCTAssertFalse(f.allows(review, session)); XCTAssertNil(f.context)
    }
    func testRetiredNilBindingBlocksEvenOldContextClosure() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session), oldContext = f.context
        f.model.bind(nil)
        XCTAssertFalse(f.model.allows(review, session: session, message: "note", context: oldContext, reader: f.reader))
    }
    func testOverlengthRemainsEditableButNeverProducesPreview() throws {
        let f = Fixture(), session = try f.open(), raw = String(repeating: "a", count: 501)
        XCTAssertNil(f.model.review(message: raw, session: session, context: f.context, reader: f.reader)); XCTAssertEqual(raw.count, 501)
        XCTAssertNotNil(f.model.review(message: String(raw.dropLast()), session: session, context: f.context, reader: f.reader))
    }
    func testEmptyMessageCanBeReviewedAsExplicitEmptyString() throws {
        let f = Fixture(), session = try f.open(), review = try f.review(session, "")
        XCTAssertEqual(try review.operation.body()["message"], .string(""))
    }
    func testEntryRequiresVisibleCurrentAcceptedSource() {
        let f = Fixture(); f.model.bind(f.context); f.model.open(context: f.context, reader: f.reader); XCTAssertNil(f.model.session)
        f.model.appear(); f.loaded = nil; f.model.bind(f.context); f.model.open(context: f.context, reader: f.reader); XCTAssertNil(f.model.session)
    }
    @MainActor private final class Reader: CoopFlowReading {
        var session: CoopFlowSession? = try! .init(accountID: 7, epoch: 1, token: "synthetic-fixture")
        var reads = 0
        func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON { reads += 1; throw CoopFlowFailure.disabled }
        func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { reads += 1; throw CoopFlowFailure.disabled }
    }
}
