import XCTest
@testable import Questify

@MainActor final class ProfileFavoriteRemovalAppTests: XCTestCase {
    private func make(_ scenario:String="success",approved:Bool=true) throws -> (ProfileFavoriteRemovalController,ProfileFavoriteRemovalFixtureWire,ProfileFavoriteRemovalFixtureContext,SquarePost,UUID) {
        let scope=UUID(), context=ProfileFavoriteRemovalFixtureContext(scope:scope), wire=ProfileFavoriteRemovalFixtureWire(scenario)
        let config=try APIConfiguration(baseURL:URL(string:"https://profile.example/native")!)
        let endpoint=try OperationEndpointApproval(baseURL:config.baseURL,namespace:"synthetic-favorite",accountID:81,paths:ProfileFavoriteRemovalApproval.paths)
        let grant=try ProfileFavoriteRemovalApproval(endpoint:endpoint,identity:context.session!.identity,postID:101,expiresAt:Date(timeIntervalSince1970:4102444800))
        let c=ProfileFavoriteRemovalController(configuration:config,approvals:approved ? [grant] : [],transport:wire,journal:ProfileFavoriteRemovalFixtureJournal(),current:{context.session})
        let p=try JSONDecoder().decode(SquarePost.self,from:Data(#"{"id":101,"memberId":91}"#.utf8)).qualified(as:.legacySquare)
        return (c,wire,context,p,scope)
    }
    func testFixtureUsesRealRemovalControllerAndView() throws {
        let(c,_,_,p,s)=try make();_ = ProfileFavoriteRemovalEntry(post:p,scope:s,controller:c,isCurrent:{true},onRemoved:{})
        _ = ProfileFavoriteRemovalFixtureHost()
    }
    func testNormalContextHasNoImplicitGrant() throws {
        let(c,w,_,p,s)=try make(approved:false);XCTAssertFalse(c.isAvailable(post:p,collectionScope:s));XCTAssertEqual(w.writes,0)
    }
    func testReviewThenCancelDoesNotChangeSyntheticServer() async throws {
        let(c,w,_,p,s)=try make();let id=try XCTUnwrap(c.begin(post:p,collectionScope:s));await c.prepare(id);c.retire(id)
        XCTAssertTrue(w.marked);XCTAssertEqual(w.writes,0)
    }
    func testConfirmedRemovalRequiresPostwriteReadback() async throws {
        let(c,w,_,p,s)=try make();let id=try XCTUnwrap(c.begin(post:p,collectionScope:s));await c.prepare(id);await c.confirm(try XCTUnwrap(c.review))
        XCTAssertEqual(c.phase,.removed);XCTAssertEqual(w.writes,1);XCTAssertEqual(w.reads,3)
    }
    func testUnknownThenReadOnlyResolveDoesNotResend() async throws {
        let(c,w,_,p,s)=try make("unknown");let id=try XCTUnwrap(c.begin(post:p,collectionScope:s));await c.prepare(id);await c.confirm(try XCTUnwrap(c.review))
        XCTAssertEqual(c.phase,.unknown);w.marked=false;w.scenario="success";await c.reconcile(id)
        XCTAssertEqual(c.phase,.removed);XCTAssertEqual(w.writes,1)
    }
    func testAcknowledgedButUnreadableDoesNotClaimRemoval() async throws {
        let(c,w,_,p,s)=try make("ackUnreadable");let id=try XCTUnwrap(c.begin(post:p,collectionScope:s));await c.prepare(id);await c.confirm(try XCTUnwrap(c.review))
        XCTAssertEqual(c.phase,.unknown);XCTAssertFalse(w.marked);XCTAssertEqual(w.writes,1)
    }
    func testRetiredAccountCannotSubmitReviewedAction() async throws {
        let(c,w,context,p,s)=try make();let id=try XCTUnwrap(c.begin(post:p,collectionScope:s));await c.prepare(id);let review=try XCTUnwrap(c.review)
        context.session=nil;await c.confirm(review);XCTAssertEqual(w.writes,0)
    }
    func testSuccessfulDismissalRefreshesOnceAcrossEntryAndSheetCallbacks() async throws {
        let (c, w, _, p, scope) = try make()
        let id = try XCTUnwrap(c.begin(post: p, collectionScope: scope)); await c.prepare(id)
        await c.confirm(try XCTUnwrap(c.review))
        let presentation = ProfileFavoriteRemovalPresentation(id: id, postID: p.id, scope: scope)
        let refreshed = expectation(description: "One verified return refresh"); refreshed.expectedFulfillmentCount = 1
        var count = 0
        for _ in 0..<3 {
            presentation.finish(controller: c, isCurrent: { true }, onRemoved: { count += 1; refreshed.fulfill() })
        }
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(count, 1); XCTAssertEqual(w.writes, 1); XCTAssertEqual(c.phase, .idle)
    }
    func testCancelledOrUnknownDismissalDoesNotReportRemoval() async throws {
        for scenario in ["success", "unknown"] {
            let (c, w, _, p, scope) = try make(scenario)
            let id = try XCTUnwrap(c.begin(post: p, collectionScope: scope)); await c.prepare(id)
            if scenario == "unknown" { await c.confirm(try XCTUnwrap(c.review)) }
            let presentation = ProfileFavoriteRemovalPresentation(id: id, postID: p.id, scope: scope)
            var count = 0
            presentation.finish(controller: c, isCurrent: { true }, onRemoved: { count += 1 })
            await Task.yield()
            XCTAssertEqual(count, 0); XCTAssertEqual(w.writes, scenario == "unknown" ? 1 : 0)
        }
    }
    func testOldPresentationFinishCannotRetireNewReviewOrRefreshNewScope() async throws {
        let (c, _, _, p, scope) = try make()
        let first = try XCTUnwrap(c.begin(post: p, collectionScope: scope)); await c.prepare(first)
        let presentation = ProfileFavoriteRemovalPresentation(id: first, postID: p.id, scope: scope)
        c.retire(first)
        let next = try XCTUnwrap(c.begin(post: p, collectionScope: scope)); await c.prepare(next)
        var count = 0
        presentation.finish(controller: c, isCurrent: { true }, onRemoved: { count += 1 })
        await Task.yield()
        XCTAssertEqual(c.presentationID, next); XCTAssertEqual(c.phase, .reviewed); XCTAssertEqual(count, 0)
    }
    func testSuccessfulDismissalRejectsChangedCollectionBeforeDelivery() async throws {
        let (c, _, _, p, scope) = try make()
        let id = try XCTUnwrap(c.begin(post: p, collectionScope: scope)); await c.prepare(id)
        await c.confirm(try XCTUnwrap(c.review))
        let presentation = ProfileFavoriteRemovalPresentation(id: id, postID: p.id, scope: scope)
        var current = true, count = 0
        presentation.finish(controller: c, isCurrent: { current }, onRemoved: { count += 1 })
        current = false
        await Task.yield()
        XCTAssertEqual(count, 0)
    }

}
