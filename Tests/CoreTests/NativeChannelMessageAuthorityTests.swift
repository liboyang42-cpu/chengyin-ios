import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor private final class MessageTestAuthority: NativeChannelMessageAuthorizing {
    var identity: MessagingReadIdentity? = .init(accountID: 3, epoch: 1)
    var permitted = true
    let value: NativeChannelMessageCredentials
    init() throws {
        let binding = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "source")
        value = try .init(identity: .init(accountID: 3, epoch: 1), namespace: "unit-only", baseURL: URL(string: "https://example.com")!,
                          binding: binding, authorityRevision: "source-revision", token: "test-only-native-channel-message-token")
    }
    func credentials(for capability: NativeChannelMessageCapability, binding: NativeChannelMessageBinding) throws -> NativeChannelMessageCredentials {
        guard permitted, identity == value.identity, binding == value.binding else { throw APIError.notConfigured }; return value
    }
}
@MainActor private final class MessageFinalForward: NativeChannelMessageDispatching {
    var waiting: CheckedContinuation<Void, Never>?
    var forwardCount = 0
    func send(_ request: URLRequest, fence: NativeChannelMessageDispatchFence) async throws -> (Data, Int) {
        await withCheckedContinuation { waiting = $0 }
        guard fence.isCurrent else { throw CancellationError() }
        forwardCount += 1
        return (Data(#"{"code":200,"data":{"list":[],"total":0,"limit":20}}"#.utf8), 200)
    }
}
@MainActor final class NativeChannelMessageAuthorityTests: XCTestCase {
    func testRevocationBeforeFinalForwardPreventsRequest() async throws {
        let authority = try MessageTestAuthority(), transport = MessageFinalForward()
        let client = NativeChannelMessageService(credentials: authority.value, authority: authority, transport: transport, onUnauthorized: { _ in })
        let read = Task { try await client.pins() }
        for _ in 0..<100 where transport.waiting == nil { await Task.yield() }
        guard let pending = transport.waiting else { XCTFail("Missing final-forward suspension"); read.cancel(); return }
        authority.permitted = false; pending.resume()
        do { _ = try await read.value; XCTFail("Revoked operation returned payload") } catch { }
        XCTAssertEqual(transport.forwardCount, 0)
    }
    func testRetirementPreventsForwardEvenWithSameAccount() async throws {
        let authority = try MessageTestAuthority(), transport = MessageFinalForward()
        let client = NativeChannelMessageService(credentials: authority.value, authority: authority, transport: transport, onUnauthorized: { _ in })
        let read = Task { try await client.pins() }
        for _ in 0..<100 where transport.waiting == nil { await Task.yield() }
        guard let pending = transport.waiting else { XCTFail("Missing suspension"); read.cancel(); return }
        client.retireOperations(); pending.resume()
        do { _ = try await read.value; XCTFail("Retired lifecycle returned payload") } catch { }
        XCTAssertEqual(transport.forwardCount, 0)
    }
}
