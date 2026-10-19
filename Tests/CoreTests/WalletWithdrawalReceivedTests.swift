import XCTest
@testable import QuestifyCore

final class WalletWithdrawalReceivedTests: XCTestCase {
    private func record(_ extra: String) throws -> WalletWithdrawalRecord {
        try JSONDecoder().decode(WalletWithdrawalRecord.self, from: Data("{\"id\":4,\"withdrawalAmount\":10,\"status\":3\(extra)}".utf8))
    }
    func testReceivedAmountIsOptionalAndNeverNegative() throws {
        XCTAssertEqual(try record(",\"receivedAmount\":9.5").receivedAmount?.value, Decimal(string: "9.5"))
        XCTAssertNil(try record("").receivedAmount)
        XCTAssertNil(try record(",\"receivedAmount\":null").receivedAmount)
        XCTAssertNil(try record(",\"receivedAmount\":-1").receivedAmount)
        XCTAssertEqual(try record(",\"receivedAmount\":9.5").statusKey, "wallet.paid")
    }
}
