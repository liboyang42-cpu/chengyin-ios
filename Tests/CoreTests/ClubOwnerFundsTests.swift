import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ClubOwnerFundsTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81)
    private var context: ClubGovernanceReadContext {
        .init(operation: .settlement, scope: scope, identity: .init(accountID: 701, epoch: 1), viewerRevision: 3, authorizationGeneration: nil)
    }
    private func snapshot(owner: ClubGovernanceValue = .bool(true), permitted: Bool = true) throws -> ClubGovernanceSnapshot {
        let p = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]), "permissions": .array(permitted ? [.string("club:finance:read")] : [])]), scope: scope)
        return .init(operation: .settlement, scope: scope, permissions: p, value: .object(["isOwner": owner, "settledAmountText": .string("120.00"), "settledAmountStatus": .string("verified"), "unverifiedSettledCount": .integer(0), "topics": .array([])]))
    }
    private func funds(_ amount: String, known: String = "true") throws -> WalletFundsStages {
        try JSONDecoder().decode(WalletFundsStages.self, from: Data("{\"pendingSettlement\":\"12.30\",\"disputed\":2,\"withdrawable\":\"\(amount)\",\"complaintPeriod\":[{\"availableDate\":\"2026-10-18\",\"amount\":\"4.50\"}],\"amountsKnown\":\(known)}".utf8))
    }
    func testOwnerAndFinanceProofRequiredForExactClub() throws {
        let target = try XCTUnwrap(ClubOwnerFundsTarget(snapshot: snapshot(), context: context))
        XCTAssertEqual(target.clubID, 81); XCTAssertTrue(target.accepts(try snapshot()))
        XCTAssertNil(ClubOwnerFundsTarget(snapshot: try snapshot(permitted: false), context: context))
    }
    func testDelegatedFinanceReadDoesNotGrantOwnerWalletRead() throws {
        for owner in [ClubGovernanceValue.bool(false), .null, .integer(1), .string("true")] {
            XCTAssertNil(ClubOwnerFundsTarget(snapshot: try snapshot(owner: owner), context: context))
        }
    }
    func testForeignClubAndExtraTopicScopeRejected() throws {
        for scope in [ClubGovernanceScope(clubID: 82), .init(clubID: 81, topicID: 91)] {
            let c = ClubGovernanceReadContext(operation: .settlement, scope: scope, identity: context.identity, viewerRevision: 3, authorizationGeneration: nil)
            XCTAssertNil(ClubOwnerFundsTarget(snapshot: try snapshot(), context: c))
        }
    }
    func testUnknownIsNotZeroOrPositive() throws {
        XCTAssertEqual(ClubOwnerFundsAvailability(nil), .unknown)
        XCTAssertEqual(ClubOwnerFundsAvailability(try funds("10", known: "false")), .unknown)
        XCTAssertEqual(ClubOwnerFundsAvailability(try funds("0", known: "false")), .unknown)
    }
    func testKnownZeroAndPositiveAreDistinct() throws {
        XCTAssertEqual(ClubOwnerFundsAvailability(try funds("0")), .zero)
        XCTAssertEqual(ClubOwnerFundsAvailability(try funds("0.01")), .positive)
    }
    func testStagesPreserveAmountsDatesAndUnknownCurrency() throws {
        let value = try funds("987654321.123456")
        XCTAssertEqual(value.withdrawable.text, "987654321.123456")
        XCTAssertEqual(value.pendingSettlement.text, "12.3")
        XCTAssertEqual(value.complaintPeriod.first?.availableDate, "2026-10-18")
        XCTAssertNil(value.currency)
    }
    func testMalformedOrNegativeMoneyCannotBecomeZero() throws {
        XCTAssertThrowsError(try funds("-1")); XCTAssertThrowsError(try funds("invalid"))
        XCTAssertThrowsError(try JSONDecoder().decode(WalletFundsStages.self, from: Data("{}".utf8)))
    }
    func testRevokedOwnershipInvalidatesTarget() throws {
        let target = try XCTUnwrap(ClubOwnerFundsTarget(snapshot: snapshot(), context: context))
        XCTAssertFalse(target.accepts(try snapshot(owner: .bool(false))))
    }
    private final class Transport: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return (Data(#"{"code":200,"data":{"pendingSettlement":0,"disputed":0,"withdrawable":"3.00","complaintPeriod":[],"amountsKnown":true}}"#.utf8), 200)
        }
    }
    @MainActor func testActualExistingReaderAdapterUsesOnlyStagesJSONRead() async throws {
        let http = Transport(), configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let scope = WalletCommerceScope(namespace: "synthetic", accountID: 701, epoch: UUID())
        let reader = WalletCommerceReader(service: .init(configuration: configuration, transport: http), session: { (scope, "synthetic-token") })
        let value = try await reader.readClubOwnerFunds()
        XCTAssertEqual(value.withdrawable.text, "3"); XCTAssertEqual(http.requests.count, 1)
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url?.path, "/api/wallet/stages"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, Data("{}".utf8)); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    @MainActor func testDefaultUnconfiguredReaderDoesNotMakeRequest() async {
        let reader = WalletCommerceReader(session: { nil })
        do { _ = try await reader.readClubOwnerFunds(); XCTFail("Unavailable must not read") } catch { }
    }
}
