import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class TeamReadApprovalTests: XCTestCase {
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", namespace: String = "synthetic-realm-A", base: String = "https://example.test/native", token: String = "synthetic-7", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: URL(string: base)!, role: role,
            session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    func testFullContextExpiryAndIrreversibleRevocation() throws {
        let original = try context(), deadline = Date().addingTimeInterval(600)
        let lease = try TeamReadApproval(context: original, expiresAt: deadline)
        XCTAssertTrue(lease.matches(original))
        for changed in [try context(account: 8), try context(epoch: 2), try context(role: "merchant"),
                        try context(namespace: "synthetic-realm-B"), try context(base: "https://other.test/native"),
                        try context(base: "https://example.test/other"), try context(token: "rotated"), try context(market: .unitedStates)] {
            XCTAssertFalse(lease.matches(changed))
        }
        XCTAssertFalse(lease.matches(original, now: deadline)); lease.expireIfNeeded(now: deadline)
        XCTAssertTrue(lease.isRevoked); XCTAssertFalse(lease.matches(original, now: deadline.addingTimeInterval(-1)))
        XCTAssertThrowsError(try TeamReadApproval(context: context(role: "admin"), expiresAt: deadline))
        XCTAssertThrowsError(try TeamReadApproval(context: context(market: .unitedStates), expiresAt: deadline))
    }
    func testServiceRequiresFreshMembershipForIDButPreservesNonmemberInvitation() async throws {
        let context = try context(), account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":7,"role":"player"}"#.utf8))
        let session = try TeamSession(account: account, epoch: 1, region: "CN", storageNamespace: "synthetic-realm-A", token: "synthetic-7")
        let wire = Wire(), service = TeamReadOnlyService(configuration: try APIConfiguration(baseURL: context.baseURL), transport: wire,
            currentSession: { session }, requiresIDMembership: true)
        do { _ = try await service.detail(.id(61), session: session); XCTFail() } catch { XCTAssertEqual(error as? TeamFailure, .invalidContract) }
        let invitation = try await service.detail(.invitation("invite-61"), session: session)
        XCTAssertEqual(invitation.joined, false); XCTAssertEqual(invitation.team.id, 61)
        wire.json = #"{"code":200,"data":{"team":{"id":62,"inviteCode":"another"},"joined":true}}"#
        for lookup in [TeamLookup.id(61), .invitation("invite-61")] {
            do { _ = try await service.detail(lookup, session: session); XCTFail() } catch { XCTAssertEqual(error as? TeamFailure, .invalidContract) }
        }
    }
    private final class Wire: HTTPTransport {
        var json = #"{"code":200,"data":{"team":{"id":61,"inviteCode":"invite-61"},"joined":false,"members":[]}}"#
        func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(json.utf8), 200) }
    }
}
