import XCTest
import SwiftUI
@testable import Questify

@MainActor final class WalletEarningsOverviewTests: XCTestCase {
    func testUnknownDoesNotBecomeZeroAndLegalZeroIsNotAFailure() throws {
        let unknown = try stages(#"{"pendingSettlement":"7","disputed":"7","withdrawable":"0","complaintPeriod":[],"amountsKnown":false}"#)
        var input = WalletFundsStageInput(configured: true, hasScope: true, scopeMatches: true, stages: unknown)
        XCTAssertEqual(WalletFundsStageClassifier.phase(input), .unknown)
        XCTAssertFalse(WalletFundsStageClassifier.showsAmounts(.unknown))
        let zero = try stages(#"{"pendingSettlement":0,"disputed":0,"withdrawable":0,"complaintPeriod":[],"amountsKnown":true,"currency":"CNY"}"#)
        input.stages = zero
        XCTAssertEqual(WalletFundsStageClassifier.phase(input), .empty)
        XCTAssertTrue(WalletFundsStageClassifier.showsAmounts(.empty))
        XCTAssertEqual(zero.withdrawable.value, 0)
        let formatted = WalletFormatting(locale: Locale(identifier: "en_US")).amount(zero.withdrawable, currency: zero.currency)
        XCTAssertTrue(formatted.contains("0"))
        XCTAssertFalse(formatted.contains("Unknown"))
        let moving = try stages(#"{"pendingSettlement":"3","disputed":0,"withdrawable":0,"complaintPeriod":[],"amountsKnown":true}"#)
        input.stages = moving
        XCTAssertEqual(WalletFundsStageClassifier.phase(input), .known)
        XCTAssertEqual(moving.withdrawable.value, 0)
    }

    func testStagePhasesStayDistinct() {
        let base = WalletFundsStageInput(configured: true, hasScope: true, scopeMatches: true)
        XCTAssertEqual(WalletFundsStageClassifier.phase(base), .loading)
        var loading = base; loading.loading = true
        XCTAssertEqual(WalletFundsStageClassifier.phase(loading), .loading)
        var failed = base; failed.failed = true
        XCTAssertEqual(WalletFundsStageClassifier.phase(failed), .failed)
        var unconfigured = base; unconfigured.configured = false; unconfigured.unavailable = true
        XCTAssertEqual(WalletFundsStageClassifier.phase(unconfigured), .unconfigured)
        var denied = base; denied.unavailable = true
        XCTAssertEqual(WalletFundsStageClassifier.phase(denied), .unconfigured)
        var signedOut = base; signedOut.hasScope = false
        XCTAssertEqual(WalletFundsStageClassifier.phase(signedOut), .signedOut)
        var expired = base; expired.requiresLogin = true
        XCTAssertEqual(WalletFundsStageClassifier.phase(expired), .signedOut)
    }

    func testUnconfiguredStagesDoNotDispatchAndDenialIsNotARetryableFailure() async {
        let wire = RecordingTransport()
        let missing = reader(transport: wire, configured: false)
        let screen = WalletScreen<WalletFundsStages>()
        await screen.load(missing) { try await $0.stages(token: $1) }
        XCTAssertTrue(wire.paths.isEmpty)
        XCTAssertEqual(WalletFundsStageClassifier.phase(WalletFundsStageClassifier.input(reader: missing, funds: screen)), .unconfigured)
        wire.stagesStatus = 0
        wire.stagesError = APIError.notConfigured
        let deniedReader = reader(transport: wire)
        let denied = WalletScreen<WalletFundsStages>()
        await denied.load(deniedReader) { try await $0.stages(token: $1) }
        XCTAssertEqual(wire.paths, ["/api/wallet/stages"])
        XCTAssertEqual(WalletFundsStageClassifier.phase(WalletFundsStageClassifier.input(reader: deniedReader, funds: denied)), .unconfigured)
        XCTAssertFalse(denied.failed == false && denied.value != nil)
        wire.paths = []
        wire.stagesError = APIError.httpStatus(503)
        let failed = WalletScreen<WalletFundsStages>()
        await failed.load(deniedReader) { try await $0.stages(token: $1) }
        XCTAssertEqual(WalletFundsStageClassifier.phase(WalletFundsStageClassifier.input(reader: deniedReader, funds: failed)), .failed)
        XCTAssertNil(failed.value)
    }

    func testClearedStageReadDropsTheLateResultAndABalanceSurvivesStageFailure() async {
        let wire = RecordingTransport(); wire.pause = true
        let owner = reader(transport: wire)
        let funds = WalletScreen<WalletFundsStages>()
        let started = expectation(description: "stages paused")
        wire.onPaused = { started.fulfill() }
        let task = Task { await funds.load(owner) { try await $0.stages(token: $1) } }
        await fulfillment(of: [started], timeout: 2)
        funds.clear()
        wire.resume()
        await task.value
        XCTAssertNil(funds.value); XCTAssertFalse(funds.loading); XCTAssertNil(funds.loadedScope)
        wire.pause = false
        wire.stagesStatus = 503
        let earnings = WalletScreen<WithdrawalBalance>()
        await earnings.loadEarnings(owner)
        await funds.load(owner) { try await $0.stages(token: $1) }
        XCTAssertEqual(earnings.value?.balance.text, "12")
        XCTAssertTrue(funds.failed); XCTAssertNil(funds.value)
        XCTAssertEqual(earnings.loadedScope, owner.scope)
    }

    func testDeniedOrganizerFinanceDoesNotReadAndAGrantReadsOncePerCall() async throws {
        let reader = WalletEarningsSyntheticFinanceReader()
        var reads = 0
        reader.onFinanceRead = { reads += 1 }
        let denied = WalletOrganizerFinanceAccess(reader: reader, allowsRead: { false }) { EmptyView() }
        if WalletOrganizerFinanceAdmission.showReader(allowsRead: denied.allowsRead(), hasSession: denied.reader.session != nil, mounted: true) {
            _ = try await denied.reader.read(.finance)
        }
        XCTAssertEqual(reads, 0)
        let allowed = WalletOrganizerFinanceAccess(reader: reader, allowsRead: { true }) { EmptyView() }
        XCTAssertTrue(WalletOrganizerFinanceAdmission.showReader(allowsRead: allowed.allowsRead(), hasSession: true, mounted: true))
        XCTAssertFalse(WalletOrganizerFinanceAdmission.showReader(allowsRead: true, hasSession: false, mounted: true))
        XCTAssertFalse(WalletOrganizerFinanceAdmission.showReader(allowsRead: true, hasSession: true, mounted: false))
        let value = try await allowed.reader.read(.finance)
        XCTAssertEqual(reads, 1)
        let row = try XCTUnwrap(value["topics"].rows?.first)
        XCTAssertEqual(row["pendingReason"], .null)
        let header = CoopFinanceSummary(value)
        XCTAssertNil(header.pendingReason)
        XCTAssertEqual(header.creditedIncome, 0)
        XCTAssertEqual(row["myIncome"].text, "12.5")
        let settlement = CoopFlowSettlement(source: .finance, record: row)
        XCTAssertEqual(settlement.status, "inTransit")
        XCTAssertNotEqual(settlement.status, "credited")
        XCTAssertEqual(settlement.amount.currency, "CNY")
        let missing = CoopFlowSettlement(source: .finance, record: .object(["topicId": .id(8), "settled": .bool(true), "myIncome": .null]))
        XCTAssertNil(missing.amount.amount)
        XCTAssertEqual(missing.status, "pending")
        XCTAssertNotEqual(missing.amount.amount, Decimal.zero)
    }

    func testTabHoldDoesNotRemountOnSwitchAndDropsOnBackground() {
        var hold = WalletEarningsTabHold()
        hold.select(.organizer)
        XCTAssertTrue(hold.mounted)
        hold.select(.income)
        XCTAssertTrue(hold.mounted)
        XCTAssertEqual(hold.tab, .income)
        hold.background()
        XCTAssertFalse(hold.mounted)
        hold.foreground()
        XCTAssertFalse(hold.mounted)
        hold.select(.organizer)
        hold.background()
        hold.foreground()
        XCTAssertTrue(hold.mounted)
        XCTAssertEqual(WalletOrganizerFinanceIdentity.key(accountID: 7, epoch: 1), "7:1")
        XCTAssertNotEqual(WalletOrganizerFinanceIdentity.key(accountID: 7, epoch: 1), WalletOrganizerFinanceIdentity.key(accountID: 7, epoch: 2))
    }

    private func stages(_ json: String) throws -> WalletFundsStages {
        try JSONDecoder().decode(WalletFundsStages.self, from: Data(json.utf8))
    }

    private func reader(transport: RecordingTransport, configured: Bool = true, scope: WalletCommerceScope? = .init(namespace: "synthetic", accountID: 7, epoch: UUID())) -> WalletCommerceReader {
        let service = configured ? WalletCommerceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport) : nil
        return WalletCommerceReader(service: service) {
            guard let scope else { return nil }
            return (scope, "synthetic-token")
        }
    }
}

private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    var paths: [String] = []
    var stagesStatus = 200
    var stagesError: Error?
    var pause = false
    var onPaused: (() -> Void)?
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func resume() {
        lock.lock(); pause = false; let pending = waiters; waiters = []; lock.unlock()
        pending.forEach { $0.resume() }
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = request.url?.path ?? ""
        lock.lock(); paths.append(path); let shouldPause = pause; lock.unlock()
        if shouldPause {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if pause { waiters.append(continuation); lock.unlock(); onPaused?() }
                else { lock.unlock(); continuation.resume() }
            }
        }
        if path == "/api/wallet/stages" {
            if let stagesError { throw stagesError }
            if stagesStatus != 200 { return (Data("{\"code\":503}".utf8), stagesStatus) }
            let body = #"{"code":200,"data":{"pendingSettlement":1,"disputed":0,"withdrawable":0,"complaintPeriod":[],"amountsKnown":true}}"#
            return (Data(body.utf8), 200)
        }
        return (Data(#"{"code":200,"data":{"balance":"12"}}"#.utf8), 200)
    }
}
