import XCTest
@testable import QuestifyCore

final class CooperationInvitationDirectionTests: XCTestCase {
    func testReceivedPendingOnlyReplies() {
        XCTAssertEqual(CoopFlowContractState.pending.actions(direction: .received), [.accept, .reject])
    }
    func testSentPendingOnlyCancels() {
        XCTAssertEqual(CoopFlowContractState.pending.actions(direction: .sent), [.cancel])
    }
    func testEmployeeAndOwnerUseSameSentSource() {
        let owner = 90
        for principal in [owner, 91] {
            let row: CoopFlowJSON = .object(["fromId": .id(owner), "status": .id(0)])
            let state = CoopFlowContractState(invite: row)
            XCTAssertEqual(state.actions(direction: .sent), [.cancel])
            // Regression witness: the old principal equality misclassified the employee.
            if principal != owner {
                XCTAssertEqual(state.actions(isFrom: false, isTo: true), [.accept, .reject])
            }
        }
    }
    func testReceivedSourceWinsEvenWhenSenderIDMatchesPrincipal() {
        // IDs may identify a club/contract owner, not the authenticated principal.
        let row: CoopFlowJSON = .object(["fromId": .id(91), "status": .id(0)])
        XCTAssertEqual(CoopFlowContractState(invite: row).actions(direction: .received), [.accept, .reject])
    }
    func testUnknownSourceFailsClosed() {
        for state in [CoopFlowContractState.pending, .accepted, .frozen, .historicalReadOnly, .ended, .unknown] {
            XCTAssertTrue(state.actions(direction: nil).isEmpty)
        }
    }
    func testAcceptedMatrixIsUnchanged() {
        XCTAssertEqual(CoopFlowContractState.accepted.actions(direction: .sent), [.cancel])
        XCTAssertTrue(CoopFlowContractState.accepted.actions(direction: .received).isEmpty)
    }
    func testReadOnlyAndEndedRemainWithoutActions() {
        for state in [CoopFlowContractState.frozen, .historicalReadOnly, .ended, .unknown] {
            for direction in CooperationDirection.allCases { XCTAssertTrue(state.actions(direction: direction).isEmpty) }
        }
    }
}
