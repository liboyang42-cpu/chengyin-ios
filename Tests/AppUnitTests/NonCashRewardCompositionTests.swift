import XCTest
@testable import Questify

@MainActor final class NonCashRewardCompositionTests: XCTestCase {
    func testNormalSessionReaderTracksIdentityButNeverActivatesNetwork() async throws {
        let container = AppSessionContainer(arguments: [IntegratedNativeAcceptanceFixture.flag, "ready"])
        let fixture = try XCTUnwrap(container.integratedAcceptance)
        let defaults = try XCTUnwrap(fixture.defaults), suite = fixture.suiteName
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let session = try XCTUnwrap(container.session)
        let reader = session.nonCashRewardReader, guestScope = reader.scope
        XCTAssertFalse(reader.isAuthenticated); XCTAssertFalse(reader.isConfigured)
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertTrue(reader.isAuthenticated); XCTAssertNotEqual(reader.scope, guestScope)
        let authenticatedScope = reader.scope, before = fixture.ledger.count
        do { _ = try await reader.rewards(cursor: nil); XCTFail("Live rewards must remain disabled") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(fixture.ledger.count, before)
        await session.logout()
        XCTAssertFalse(reader.isAuthenticated); XCTAssertNotEqual(reader.scope, authenticatedScope)
        XCTAssertFalse(reader.isConfigured)
        withExtendedLifetime(container) {}
    }
}
