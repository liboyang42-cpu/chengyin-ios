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

    func testActivityEditorRouteFallsBackToDetailUntilLoadContractExists() throws {
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"pending","ownerType":"club"}"#), .activityEditorUnavailableDetail(.activity(9)))
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"rejected","ownerType":"club"}"#), .activityEditorUnavailableDetail(.activity(9)))
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"rejected","ownerType":"merchant"}"#), .detail(.activity(9)))
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"running","ownerType":"club"}"#), .detail(.activity(9)))
    }

    func testOtherAndUnknownStatesDegradeWithoutInventingEditors() throws {
        XCTAssertEqual(try decision(#"{"id":7,"bizType":"topic","state":"running","ownerType":"member"}"#), .detail(.topic(7)))
        XCTAssertEqual(try decision(#"{"id":7,"bizType":"topic","state":"mystery","ownerType":"member"}"#), .detail(.topic(7)))
        XCTAssertEqual(try decision(#"{"id":9,"bizType":"activity","state":"mystery","ownerType":"club"}"#), .detail(.activity(9)))
        XCTAssertEqual(try decision(#"{"id":11,"bizType":"template","state":"draft"}"#), .detail(.playTemplate(11)))
        XCTAssertEqual(try decision(#"{"id":12,"bizType":"mystery","state":"draft"}"#), .unavailable)
    }
}
