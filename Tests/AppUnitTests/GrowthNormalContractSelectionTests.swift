import XCTest
@testable import Questify

@MainActor final class GrowthNormalContractSelectionTests: XCTestCase {
    private func selectedContract(_ service: GrowthCenterService) -> GrowthLeaderboardReadContract? {
        // Inspect stored selection without adding a production test hook or bypass.
        Mirror(reflecting: service).children.first { $0.label == "leaderboardContract" }?.value as? GrowthLeaderboardReadContract
    }
    private func configuration() throws -> APIConfiguration {
        try APIConfiguration(baseURL: URL(string: "https://example.test/native")!)
    }
    func testConcreteNormalChildSelectsAnonymousWithUnchangedCallerSignature() throws {
        let wire = Wire()
        let transport = GrowthNormalReadTransport(deployment: nil, underlying: wire,
            current: { nil }, approval: { _ in nil })
        let service = GrowthCenterService(configuration: try configuration(), transport: transport)
        guard case .anonymous? = selectedContract(service) else {
            XCTFail("The normal concrete-child initializer must select strict anonymous decoding")
            return
        }
    }
    func testGenericFixtureCallerKeepsLegacyContract() throws {
        let service = GrowthCenterService(configuration: try configuration(), transport: Wire())
        guard case .legacy? = selectedContract(service) else {
            XCTFail("Generic legacy callers must not change implicitly")
            return
        }
    }
    func testNormalSelectionDoesNotCreateAuthorityOrForwardAnyHeldRequest() async throws {
        let wire = Wire()
        let transport = GrowthNormalReadTransport(deployment: nil, underlying: wire,
            current: { nil }, approval: { _ in nil })
        let service = GrowthCenterService(configuration: try configuration(), transport: transport)
        let result = try await service.overview(token: "synthetic-7")
        XCTAssertEqual(result.center.issue, .notConfigured)
        XCTAssertEqual(result.progress.issue, .notConfigured)
        XCTAssertEqual(result.completed.issue, .notConfigured)
        XCTAssertEqual(result.rank.issue, .notConfigured)
        XCTAssertEqual(wire.count, 0)
        do {
            _ = try await service.leaderboard(query: .init(metric: .exp, period: .week), token: "synthetic-7")
            XCTFail("Missing producer/approval must remain held")
        } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(wire.count, 0)
    }
    @MainActor private final class Wire: HTTPTransport {
        var count = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            count += 1
            XCTFail("A default-held normal child must not touch the underlying wire")
            return (Data(), 500)
        }
    }
}
