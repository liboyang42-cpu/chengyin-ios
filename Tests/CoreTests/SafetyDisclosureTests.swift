import Foundation
import XCTest
@testable import QuestifyCore

final class SafetyDisclosureTests: XCTestCase {
    func testEveryAISurfaceDisclosesIdentityAndCommitmentBoundary() {
        for surface in AIIdentitySurface.allCases {
            let keys = AIIdentityDisclosure(surface: surface).boundaryKeys
            XCTAssertTrue(keys.contains("opsSafety.ai.notHuman"))
            XCTAssertTrue(keys.contains("opsSafety.ai.noCommitments"))
        }
        XCTAssertEqual(AIIdentityDisclosure(surface: .publicMerchantNPC).boundaryKeys.first, "opsSafety.ai.scope.merchant")
        XCTAssertEqual(AIIdentityDisclosure(surface: .themeNPC).boundaryKeys.first, "opsSafety.ai.scope.progress")
        XCTAssertEqual(AIIdentityDisclosure(surface: .creatorCopilot).boundaryKeys.first, "opsSafety.ai.scope.draft")
        XCTAssertTrue(AIIdentityDisclosure(surface: .themeNPC).boundaryKeys.contains("opsSafety.ai.storyStillCompletable"))
        XCTAssertTrue(AIIdentityDisclosure(surface: .creatorCopilot).boundaryKeys.contains("opsSafety.ai.draftOnly"))
        XCTAssertFalse(AIIdentityDisclosure(surface: .merchantPrivateAssistant).boundaryKeys.contains("opsSafety.ai.storyStillCompletable"))
    }

    func testSensitiveTextScreenFindsCommonFormsWithoutFalseMatchesInLongerNumbers() {
        XCTAssertEqual(AIOutgoingTextScreen.findings(in: "call 13800138000 please"), [.mainlandMobile])
        XCTAssertEqual(AIOutgoingTextScreen.findings(in: "138 0013 8000"), [.mainlandMobile])
        XCTAssertEqual(AIOutgoingTextScreen.findings(in: "１３８００１３８０００"), [.mainlandMobile])
        XCTAssertEqual(AIOutgoingTextScreen.findings(in: "ID 11010519491231002X"), [.residentIdentity])
        XCTAssertEqual(AIOutgoingTextScreen.findings(in: "mail a.b@example.test"), [.email])
        XCTAssertEqual(AIOutgoingTextScreen.findings(in: "order 2138001380001 table 12"), [])
        XCTAssertEqual(AIOutgoingTextScreen.findings(in: "Where is the next clue?"), [])
        XCTAssertEqual(AIOutgoingTextScreen.findings(in: String(repeating: "a", count: 16_385)), Set(AIOutgoingSensitiveKind.allCases))
    }

    func testStoppedNodeBlocksStartAndOnlyOffersFreeServerAlternative() throws {
        let stopped = OfflineNodeSafetyDecoder.decode(Data(#"""
        {"code":200,"data":{"nodeId":7,"status":"STOPPED","categories":["NIGHT","FLOOD"],
         "alternative":{"nodeId":8,"title":"Library route","requiresPurchase":false}}}
        """#.utf8), expectedNodeID: 7)
        XCTAssertFalse(stopped.permitsStart)
        XCTAssertEqual(stopped, .stopped(categories: [.night, .unrecognized("FLOOD")], alternative: .init(nodeID: 8, title: "Library route", requiresPurchase: false)))
        XCTAssertEqual(stopped.noPurchaseAlternative?.nodeID, 8)
        let paid = OfflineNodeSafetyDecoder.decode(Data(#"{"code":200,"data":{"nodeId":7,"status":"STOPPED","alternative":{"nodeId":8,"title":"Cafe","requiresPurchase":true}}}"#.utf8), expectedNodeID: 7)
        XCTAssertNil(paid.noPurchaseAlternative)
        let selfAlternative = OfflineNodeSafetyDecoder.decode(Data(#"{"code":200,"data":{"nodeId":7,"status":"STOPPED","alternative":{"nodeId":7,"title":"Same","requiresPurchase":false}}}"#.utf8), expectedNodeID: 7)
        XCTAssertEqual(selfAlternative, .stopped(categories: [], alternative: nil))
    }

    func testNodeSafetyReadoutForAnotherNodeOrUnknownStatusIsUnknownNotOpen() {
        XCTAssertEqual(OfflineNodeSafetyDecoder.decode(Data(#"{"code":200,"data":{"nodeId":9,"status":"OPEN"}}"#.utf8), expectedNodeID: 7), .unknown)
        XCTAssertEqual(OfflineNodeSafetyDecoder.decode(Data(#"{"code":200,"data":{"nodeId":7,"status":"PAUSED"}}"#.utf8), expectedNodeID: 7), .unknown)
        XCTAssertEqual(OfflineNodeSafetyDecoder.decode(Data(#"{"code":401,"data":{"nodeId":7,"status":"OPEN"}}"#.utf8), expectedNodeID: 7), .unknown)
        XCTAssertFalse(OfflineNodeSafetyState.unknown.permitsStart)
        XCTAssertEqual(OfflineNodeSafetyDecoder.decode(Data(#"{"code":200,"data":{"nodeId":7,"status":"OPEN"}}"#.utf8), expectedNodeID: 7), .open)
    }

    func testNoPresenceEvidenceIsProofAloneAndReviewNeverAccuses() {
        XCTAssertTrue(PresenceEvidenceKind.allCases.allSatisfy { !$0.sufficientAlone })
        XCTAssertEqual(PresenceReviewOutcome(code: "NEEDS_REVIEW"), .needsReview)
        XCTAssertEqual(PresenceReviewOutcome(code: "FRAUD"), .unknown)
        XCTAssertEqual(PresenceReviewOutcome(code: nil), .unknown)
    }
}
