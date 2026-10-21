import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program parity for scene-member-withdraw-history (w2-05). Offline fixtures only.
@MainActor final class WithdrawalHistoryTests: XCTestCase {
    private func page(_ json: String) throws -> WithdrawalHistoryPage {
        try WithdrawalHistoryPage.decode(envelope: Data(json.utf8))
    }
    func testStatusMappingMatchesSourceAndUnknownNeverFailsTheTable() throws {
        let value = try page(#"{"code":200,"data":[{"id":1,"status":0,"receivedAmount":12.3},{"id":2,"status":1,"receivedAmount":5},{"id":3,"status":2,"receivedAmount":0},{"id":4,"status":3,"receivedAmount":1},{"id":5},{"id":6,"status":"x"}]}"#)
        XCTAssertEqual(value.rows.map(\.status), [.processing, .succeeded, .failed, .unknown, .unknown, .unknown])
        XCTAssertEqual(value.rows.map(\.statusKey), ["withdrawal.history.status.processing", "withdrawal.history.status.succeeded",
            "withdrawal.history.status.failed", "withdrawal.history.status.unknown", "withdrawal.history.status.unknown", "withdrawal.history.status.unknown"])
        XCTAssertNil(value.total); XCTAssertFalse(value.mayHaveMore)
    }
    func testAmountUsesReceivedAmountWithTwoDecimalsAndDashForMissingOrInvalid() throws {
        let value = try page(#"{"code":200,"data":[{"id":1,"status":1,"receivedAmount":12.3,"withdrawalAmount":99},{"id":2,"status":1,"withdrawalAmount":99},{"id":3,"status":1,"receivedAmount":"12.30"},{"id":4,"status":1,"receivedAmount":-1},{"id":5,"status":1,"receivedAmount":0.125}]}"#)
        XCTAssertEqual(value.rows.map(\.amountText), ["-12.30", nil, nil, nil, "-0.13"])
    }
    func testCreateTimeIsVerbatimAndBlankIsMissing() throws {
        let value = try page(#"{"code":200,"data":[{"id":1,"status":0,"createTime":"2026-10-01 10:00:00"},{"id":2,"status":0,"createTime":"  "}]}"#)
        XCTAssertEqual(value.rows.map(\.createTime), ["2026-10-01 10:00:00", nil])
    }
    func testTableShapesAreAcceptedAndOtherShapesFail() throws {
        let rows = try page(#"{"code":200,"data":{"rows":[{"id":1,"status":1}],"total":"3"}}"#)
        XCTAssertEqual(rows.rows.count, 1); XCTAssertEqual(rows.total, 3); XCTAssertTrue(rows.mayHaveMore)
        let list = try page(#"{"code":200,"data":{"list":[{"id":1,"status":1}],"total":1}}"#)
        XCTAssertEqual(list.rows.count, 1); XCTAssertFalse(list.mayHaveMore)
        for bad in [#"{"code":200,"data":null}"#, #"{"code":200,"data":{"items":[]}}"#, #"{"code":200}"#, #"{"code":200,"data":"rows"}"#] {
            XCTAssertThrowsError(try page(bad), bad)
        }
    }
    func testServiceSendsTheExistingBodylessReadAndMapsRows() async throws {
        let transport = WithdrawalHistoryTestTransport(#"{"code":200,"data":[{"id":40,"status":2,"receivedAmount":6}]}"#)
        let service = WalletCommerceService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: transport)
        let value = try await service.withdrawalHistory(token: "synthetic-token")
        XCTAssertEqual(value.rows.first?.status, .failed); XCTAssertEqual(value.rows.first?.amountText, "-6.00")
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests[0].url?.path, "/api/withdrawal/list")
        XCTAssertEqual(transport.requests[0].httpMethod, "POST"); XCTAssertNil(transport.requests[0].httpBody)
    }
    func testCoordinatorStatesForEmptyLoginDeniedFailureAndUnavailable() async throws {
        let scope = WalletCommerceScope(namespace: "synthetic-cn", accountID: 9, epoch: UUID())
        func coordinator(_ transport: WithdrawalHistoryTestTransport?, signedIn: Bool = true) throws -> WithdrawalHistoryCoordinator {
            let service = try transport.map { WalletCommerceService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: $0) }
            return WithdrawalHistoryCoordinator(reader: WalletCommerceReader(service: service) {
                guard signedIn else { return nil }; return (scope: scope, token: "synthetic-token")
            })
        }
        var model = try coordinator(.init(#"{"code":200,"data":[]}"#)); await model.load()
        XCTAssertEqual(model.phase, .empty); XCTAssertTrue(model.rows.isEmpty)
        model = try coordinator(.init(#"{"code":200,"data":[{"id":1,"status":1,"receivedAmount":2}]}"#)); await model.load()
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.rows.count, 1)
        model = try coordinator(.init(#"{"code":401}"#)); await model.load(); XCTAssertEqual(model.phase, .login)
        model = try coordinator(.init(#"{"code":403}"#)); await model.load(); XCTAssertEqual(model.phase, .denied)
        model = try coordinator(.init("", status: 403)); await model.load(); XCTAssertEqual(model.phase, .denied)
        model = try coordinator(.init(#"{"code":500}"#)); await model.load(); XCTAssertEqual(model.phase, .failed); XCTAssertTrue(model.canRetry)
        model = try coordinator(.init(#"{"code":200,"data":{"items":[]}}"#)); await model.load(); XCTAssertEqual(model.phase, .failed)
        let silent = WithdrawalHistoryTestTransport(#"{"code":200,"data":[]}"#)
        model = try coordinator(silent, signedIn: false); await model.load()
        XCTAssertEqual(model.phase, .login); XCTAssertEqual(silent.requests.count, 0)
        model = try coordinator(nil); await model.load(); XCTAssertEqual(model.phase, .unavailable); XCTAssertFalse(model.canRetry)
    }
    func testRowsAreHiddenAfterOwnerChanges() async throws {
        var scope: WalletCommerceScope? = WalletCommerceScope(namespace: "synthetic-cn", accountID: 9, epoch: UUID())
        let service = WalletCommerceService(configuration: try .init(baseURL: URL(string: "https://example.com")!),
            transport: WithdrawalHistoryTestTransport(#"{"code":200,"data":[{"id":1,"status":1}]}"#))
        let model = WithdrawalHistoryCoordinator(reader: WalletCommerceReader(service: service) {
            guard let scope else { return nil }; return (scope: scope, token: "synthetic-token")
        })
        await model.load(); XCTAssertEqual(model.rows.count, 1)
        scope = WalletCommerceScope(namespace: "synthetic-cn", accountID: 10, epoch: UUID())
        XCTAssertTrue(model.rows.isEmpty)
    }
    func testWithdrawalRoleGateAndThemeStyle() {
        XCTAssertEqual(WithdrawalRoleGatePresentation(canWithdraw: true), .allowed)
        XCTAssertTrue(WithdrawalRoleGatePresentation.allowed.isAllowed)
        XCTAssertNil(WithdrawalRoleGatePresentation.allowed.noticeText)

        XCTAssertEqual(WithdrawalRoleGatePresentation(canWithdraw: false), .denied)
        XCTAssertFalse(WithdrawalRoleGatePresentation.denied.isAllowed)
        XCTAssertEqual(WithdrawalRoleGatePresentation.denied.noticeText, "当前身份暂不支持提现")

        XCTAssertEqual(WithdrawalRoleGatePresentation(canWithdraw: nil), .unverified)
        XCTAssertFalse(WithdrawalRoleGatePresentation.unverified.isAllowed)
        XCTAssertNil(WithdrawalRoleGatePresentation.unverified.noticeText)

        XCTAssertEqual(WithdrawalRoleGatePresentation(permissions: ["withdrawable", "orders"]), .allowed)
        XCTAssertEqual(WithdrawalRoleGatePresentation(permissions: ["orders"]), .denied)
        XCTAssertEqual(WithdrawalRoleGatePresentation(permissions: nil), .unverified)

        XCTAssertEqual(WithdrawalThemeStyle(rawTheme: "merchant"), .merchant)
        XCTAssertEqual(WithdrawalThemeStyle(rawTheme: " MERCHANT "), .merchant)
        XCTAssertEqual(WithdrawalThemeStyle(rawTheme: "member"), .member)
        XCTAssertEqual(WithdrawalThemeStyle(rawTheme: nil), .member)
        XCTAssertEqual(WithdrawalThemeStyle.merchant.badgeTitle, "商家提现")
        XCTAssertEqual(WithdrawalThemeStyle.member.badgeTitle, "个人提现")
    }
}

private final class WithdrawalHistoryTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let body: String
    let status: Int
    init(_ body: String, status: Int = 200) { self.body = body; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(body.utf8), status) }
}
