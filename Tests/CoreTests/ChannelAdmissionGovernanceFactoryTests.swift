import Foundation
import XCTest
@testable import QuestifyCore

final class ChannelAdmissionGovernanceFactoryTests: XCTestCase {
    func testFactoryUsesThePublishedCatalogVersionAndDoesNotSend() throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = FactoryIdleTransport()
        let current = try catalog(published: 3, pending: 4, expected: 3)
        XCTAssertThrowsError(try ChannelAdmissionGovernanceFactory.client(
            configuration: configuration, transport: transport, token: " ", accountID: 7, epoch: 1, catalog: current))
        XCTAssertThrowsError(try ChannelAdmissionGovernanceFactory.client(
            configuration: configuration, transport: transport, token: "token", accountID: 0, epoch: 1, catalog: current))
        let stale = try catalog(published: 3, pending: 4, expected: 2)
        XCTAssertThrowsError(try ChannelAdmissionGovernanceFactory.client(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1, catalog: stale)) {
            XCTAssertEqual($0 as? ChannelAuthorizationError, .rulesCASConflict)
        }
        XCTAssertThrowsError(try ChannelCatalogEntry(
            channelID: 21, conversationID: 12, kind: .direct, rules: try rules(published: 3, pending: 4, expected: 3)))
        let client = try ChannelAdmissionGovernanceFactory.client(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1, catalog: current)
        XCTAssertEqual(ChannelAdmissionGovernanceClient.pausePath, "api/space/join-pause")
        XCTAssertEqual(ChannelAdmissionGovernanceClient.receiptPrefix, "api/channel-platform/admission/requests/")
        XCTAssertFalse(transport.sent)
        _ = client
    }

    private func rules(published: Int, pending: Int?, expected: Int) throws -> ChannelRulesCAS {
        try ChannelRulesCAS(publishedVersion: published, pendingVersion: pending, expectedVersion: expected)
    }

    private func catalog(published: Int, pending: Int?, expected: Int) throws -> ChannelCatalogEntry {
        try ChannelCatalogEntry(channelID: 21, conversationID: 12, kind: .group,
                                rules: try rules(published: published, pending: pending, expected: expected))
    }
}

private final class FactoryIdleTransport: HTTPTransport {
    private(set) var sent = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        sent = true
        XCTFail("factory construction must not send")
        return (Data(), 500)
    }
}
