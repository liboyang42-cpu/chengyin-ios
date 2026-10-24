import XCTest
@testable import Questify

@MainActor final class ChannelAdmissionGovernanceEntryTests: XCTestCase {
    func testEntryUsesTheSameCurrentCatalogAndDoesNotSend() throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = EntryIdleTransport()
        let current = try catalog(published: 3, pending: 4, expected: 3)
        XCTAssertThrowsError(try ChannelAdmissionGovernanceEntry.make(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1,
            catalog: current, kind: 2, spaceID: 12)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .invalidCatalog)
        }
        let stale = try catalog(published: 3, pending: 4, expected: 2)
        XCTAssertThrowsError(try ChannelAdmissionGovernanceEntry.make(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1,
            catalog: stale, kind: 1, spaceID: 12)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesCASConflict)
        }
        let page = try ChannelAdmissionGovernanceEntry.make(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1,
            catalog: current, kind: 1, spaceID: 12)
        XCTAssertEqual(page.catalog, current)
        XCTAssertEqual(page.kind, 1)
        XCTAssertEqual(page.spaceID, 12)
        XCTAssertFalse(transport.sent)
        let route = ChannelAdmissionRoute(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1,
            catalog: current, kind: 1, spaceID: 12)
        let routed = try route.page()
        XCTAssertEqual(routed.catalog, current)
        XCTAssertFalse(transport.sent)
    }

    private func catalog(published: Int, pending: Int?, expected: Int) throws -> ChannelCatalogEntry {
        try ChannelCatalogEntry(
            channelID: 21, conversationID: 12, kind: .group,
            rules: try ChannelRulesCAS(publishedVersion: published, pendingVersion: pending, expectedVersion: expected))
    }
}

private final class EntryIdleTransport: HTTPTransport {
    private(set) var sent = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        sent = true
        XCTFail("opening the admission page must not send")
        return (Data(), 500)
    }
}
