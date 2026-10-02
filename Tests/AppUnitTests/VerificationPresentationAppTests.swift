import XCTest
@testable import Questify

@MainActor final class VerificationPresentationAppTests: XCTestCase {
    func testShippedBusinessPresentationApprovalsRemainNil() {
        let dependencies = NativeRuntimeDependencies.dormant
        XCTAssertNil(dependencies.verificationCodeApproval)
        XCTAssertNil(dependencies.couponCodeApproval)
        XCTAssertNil(dependencies.ownerRefundApproval)
    }
    func testNormalSessionFactoriesRemainUnavailableWithoutApprovedDeployment() async {
        let session = AppSession()
        let ticket = session.makeVerificationCodeCoordinator(target: .init(kind: .ticket, id: 31))
        let city = session.makeVerificationCodeCoordinator(target: .init(kind: .cityVoucher, id: 31))
        await ticket.present(); await city.present()
        XCTAssertNil(ticket.displayCode); XCTAssertNil(city.displayCode)
        XCTAssertFalse(session.makeCouponCodeCoordinator(historyID: 21).enabled)
        XCTAssertFalse(session.clubOwnerRefundCoordinator.canDispatch)
    }
}
