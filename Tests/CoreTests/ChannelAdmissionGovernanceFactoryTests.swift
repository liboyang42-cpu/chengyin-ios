import Foundation
import XCTest
@testable import QuestifyCore

final class ChannelAdmissionGovernanceFactoryTests: XCTestCase {
    func testFactoryRejectsABlankTokenAndAZeroAccount() throws {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://api.example.test/prod-api")!)
        let transport = FactoryIdleTransport()
        XCTAssertThrowsError(try ChannelAdmissionGovernanceFactory.client(
            configuration: configuration, transport: transport, token: " ", accountID: 7, epoch: 1, consentedVersion: 3))
        XCTAssertThrowsError(try ChannelAdmissionGovernanceFactory.client(
            configuration: configuration, transport: transport, token: "token", accountID: 0, epoch: 1, consentedVersion: 3))
        let client = try ChannelAdmissionGovernanceFactory.client(
            configuration: configuration, transport: transport, token: "token", accountID: 7, epoch: 1, consentedVersion: 3)
        XCTAssertEqual(ChannelAdmissionGovernanceClient.pausePath, "api/space/join-pause")
        XCTAssertEqual(ChannelAdmissionGovernanceClient.receiptPrefix, "api/channel-platform/admission/requests/")
        _ = client
    }
}

private final class FactoryIdleTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        XCTFail("factory construction must not send")
        return (Data(), 500)
    }
}
