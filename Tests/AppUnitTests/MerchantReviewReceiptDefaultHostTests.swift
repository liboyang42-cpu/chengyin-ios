import XCTest
import Foundation
@testable import Questify

@MainActor final class MerchantReviewReceiptDefaultHostTests: XCTestCase {
    func testUnconfiguredDefaultDoesNotConstructReaderOrIssueHTTP() throws {
        let suite = "merchant-receipt-default-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let wire = Wire(), vault = Vault()
        let root = AppCompositionRoot(storage: .init(defaults: defaults, tokenStore: { _ in vault }),
                                      makeTransport: { wire })
        let session = root.makeSession()
        XCTAssertNil(session.makeMerchantReviewOriginalReceiptReader())
        session.withMerchantReviewOriginalReadConfigurationChange { }
        XCTAssertNil(session.makeMerchantReviewOriginalReceiptReader())
        XCTAssertEqual(wire.requests, 0)
    }
    @MainActor private final class Vault: AppTokenStorage {
        func read() throws -> String? { nil }
        func write(_ value: String) throws { XCTFail("No credential write expected") }
        func clear() throws { }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests += 1; throw URLError(.unsupportedURL)
        }
    }
}
