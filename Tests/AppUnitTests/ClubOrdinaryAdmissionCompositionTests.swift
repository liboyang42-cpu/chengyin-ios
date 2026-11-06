import Foundation
import XCTest
@testable import Questify

@MainActor final class ClubOrdinaryAdmissionCompositionTests: XCTestCase {
    private func context(account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic-token") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://composition.invalid")!, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: "tests", token: token, role: "player"))
    }
    func testNoIssuerDefaultsClosed() throws {
        let context = try context()
        XCTAssertNil(ClubOrdinaryAdmissionComposition.approval(context: context, select: { _ in nil }))
    }
    func testApprovalCannotFollowReplacementAccountEpochOrToken() throws {
        let captured = try context(), grant = try ClubOrdinaryAdmissionApproval(context: captured)
        XCTAssertEqual(ClubOrdinaryAdmissionComposition.approval(context: captured, select: { _ in grant }), grant)
        for current in [try context(account: 8), try context(epoch: 2), try context(token: "replacement-token")] {
            XCTAssertNil(ClubOrdinaryAdmissionComposition.approval(context: current, select: { _ in grant }))
        }
    }
}
