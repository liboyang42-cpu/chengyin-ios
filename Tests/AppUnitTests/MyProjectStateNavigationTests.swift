import XCTest
@testable import Questify

@MainActor final class MyProjectStateNavigationTests: XCTestCase {
    private let scope = UUID()
    private func project(_ json: String) throws -> CreatorContentProject {
        try JSONDecoder().decode(CreatorContentProject.self, from: Data(json.utf8))
    }
    private func decision(_ json: String, merchantScopeAccess: MyProjectMerchantScopeAccess = .init()) throws -> MyProjectStateNavigationDecision {
        MyProjectStateNavigation.decision(project: try project(json), readerScope: scope, merchantScopeAccess: merchantScopeAccess)
    }

    func testOwnDraftAndRejectedTopicsEnterOwnerBoundEditor() throws {
        for state in ["draft", "rejected"] {
            let member = try decision(#"{"id":7,"bizType":"topic","state":"\#(state)","ownerType":"member"}"#)
            guard case .ownerTopicEditor(let target) = member else { return XCTFail("member \(state) must open the owner editor") }
            XCTAssertEqual(target.topicID, 7); XCTAssertEqual(target.owner, .personal); XCTAssertEqual(target.readerScope, scope)
            let merchant = try decision(#"{"id":8,"bizType":"topic","state":"\#(state)","ownerType":"merchant"}"#)
            guard case .ownerTopicEditor(let merchantTarget) = merchant else { return XCTFail("merchant \(state) must open the owner editor") }
            XCTAssertEqual(merchantTarget.owner, .merchant)
        }
    }

    func testTopicWithoutReviewedEditorScopeDegradesToDetail() throws {
        XCTAssertEqual(try decision(#"{"id":7,"bizType":"topic","state":"draft","ownerType":"club"}"#), .detail(.topic(7)))
    }

    func testBrowseOnlyMerchantNeverEntersEditor() throws {
        let browseOnly = MyProjectMerchantScopeAccess(isMerchantScope: true, canManageProjects: false)
        XCTAssertTrue(browseOnly.isBrowseOnly)
        XCTAssertEqual(try decision(#"{"id":7,"bizType":"topic","state":"draft","ownerType":"member"}"#, merchantScopeAccess: browseOnly), .detail(.topic(7)))
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"rejected","ownerType":"club"}"#, merchantScopeAccess: browseOnly), .detail(.activity(9)))
    }

    func testActivityEditorRouteUsesExistingEditorForTheSameScope() throws {
        for state in ["pending", "rejected"] {
            let route = try decision(#"{"id":9,"bizType":"activity","state":"\#(state)","ownerType":"club"}"#)
            guard case .activityEditor(let request) = route else { return XCTFail("\(state) must open the activity editor") }
            XCTAssertEqual(request.activityID, 9)
            XCTAssertEqual(request.readerScope, scope)
        }
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"rejected","ownerType":"merchant"}"#), .detail(.activity(9)))
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"running","ownerType":"club"}"#), .detail(.activity(9)))
        XCTAssertFalse(MyProjectMerchantScopeExclusiveAdapter.access(entryScope: nil, canManageProjects: false).isBrowseOnly)
        XCTAssertFalse(MyProjectMerchantScopeExclusiveAdapter.access(entryScope: "member", canManageProjects: false).isBrowseOnly)
        XCTAssertTrue(MyProjectMerchantScopeExclusiveAdapter.access(entryScope: "MERCHANT", canManageProjects: false).isBrowseOnly)
        XCTAssertFalse(MyProjectMerchantScopeExclusiveAdapter.access(entryScope: "MERCHANT", canManageProjects: true).isBrowseOnly)
        let page = try JSONDecoder().decode(CreatorContentProjectPage.self, from: Data(#"{"rows":[],"total":0}"#.utf8))
        XCTAssertNil(page.serverScope)
        let scoped = try JSONDecoder().decode(CreatorContentProjectPage.self, from: Data(#"{"rows":[],"total":0,"scope":"MERCHANT"}"#.utf8))
        XCTAssertEqual(scoped.serverScope, "MERCHANT")
    }

    func testSaveReceiptRefreshesOnlyTheOpeningAccount() {
        let token = MyProjectActivityEditorReturnToken(readerScope: scope, activityID: 9)
        let refresh = MyProjectActivityEditorPolicy.refreshRequest(token: token, status: "acknowledged",
            currentScope: scope, authenticated: true, generation: 3)
        XCTAssertEqual(refresh, .init(readerScope: scope, activityID: 9, generation: 3))
        XCTAssertNil(MyProjectActivityEditorPolicy.refreshRequest(token: token, status: "acknowledged",
            currentScope: UUID(), authenticated: true, generation: 4))
        XCTAssertNil(MyProjectActivityEditorPolicy.refreshRequest(token: token, status: "acknowledged",
            currentScope: scope, authenticated: false, generation: 4))
    }

    func testCancelAndLocalDraftAreNotSaveReceipts() {
        for status in ["editing", "localSaved", "review", "notSent", "rejected", "unknown", "ready"] {
            XCTAssertFalse(MyProjectActivityEditorPolicy.isServerSaveReceipt(status))
            XCTAssertNil(MyProjectActivityEditorPolicy.refreshRequest(
                token: .init(readerScope: scope, activityID: 9), status: status,
                currentScope: scope, authenticated: true, generation: 1))
        }
        XCTAssertTrue(MyProjectActivityEditorPolicy.isServerSaveReceipt("acknowledged"))
    }

    func testFactoryResolvesOnlyForTheCurrentAuthenticatedScope() {
        XCTAssertTrue(MyProjectActivityEditorPolicy.mayResolveFactory(requestScope: scope, currentScope: scope, authenticated: true))
        XCTAssertFalse(MyProjectActivityEditorPolicy.mayResolveFactory(requestScope: scope, currentScope: UUID(), authenticated: true))
        XCTAssertFalse(MyProjectActivityEditorPolicy.mayResolveFactory(requestScope: scope, currentScope: scope, authenticated: false))
    }

    func testBrowseOnlyOmitsActivityWriteOperationsAndKeepsTopicApplies() throws {
        let browseOnly = MyProjectMerchantScopeAccess(isMerchantScope: true, canManageProjects: false)
        let activity = try project(#"{"id":9,"bizType":"activity","state":"running","ownerType":"club","signupCount":3}"#)
        XCTAssertTrue(MyProjectRowOperationsMenu.hasOperations([activity]))
        XCTAssertFalse(MyProjectRowOperationsMenu.hasOperations([activity], merchantScopeAccess: browseOnly))
        let writes = MyProjectListPresentation.card(activity, merchantScopeAccess: browseOnly).operations
        XCTAssertFalse(writes.contains(.edit))
        XCTAssertFalse(writes.contains(.toggle))
        XCTAssertFalse(writes.contains(.cancel))
        XCTAssertFalse(writes.contains(.delete))
        let topic = try project(#"{"id":7,"bizType":"topic","state":"running","ownerType":"member","acceptStatus":"clubOpen"}"#)
        XCTAssertEqual(MyProjectListPresentation.card(topic, merchantScopeAccess: browseOnly).operations, [.viewApplies])
    }

    func testOtherAndUnknownStatesDegradeWithoutInventingEditors() throws {
        XCTAssertEqual(try decision(#"{"id":7,"bizType":"topic","state":"running","ownerType":"member"}"#), .detail(.topic(7)))
        XCTAssertEqual(try decision(#"{"id":7,"bizType":"topic","state":"mystery","ownerType":"member"}"#), .detail(.topic(7)))
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"mystery","ownerType":"club"}"#), .detail(.activity(9)))
        XCTAssertEqual(try decision(#"{"id":11,"bizType":"template","state":"draft"}"#), .detail(.playTemplate(11)))
        XCTAssertEqual(try decision(#"{"id":12,"bizType":"mystery","state":"draft"}"#), .unavailable)
    }
}
