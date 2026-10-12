import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ClubOwnerFundsFlowTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-owner-funds"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var owner = true, permitted = true
        var topics: [ClubGovernanceValue] = [.object(["id": .integer(1), "topicId": .integer(91), "name": .string("Topic"), "status": .string("settled"), "amountStatus": .string("verified"), "amountText": .string("8.50"), "originalAmountText": .string("8.50"), "executedAdjustmentText": .string("0"), "netAmountText": .string("8.50"), "arrivedText": .string("8.50"), "paidText": .string("8.50")])]
        var reads = 0, sends = 0
        var onRead: (() -> Void)?
        let scope = ClubGovernanceScope(clubID: 81)
        func response() throws -> ClubGovernanceSnapshot {
            let p = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]), "permissions": .array(permitted ? [.string("club:finance:read")] : [])]), scope: scope)
            return .init(operation: .settlement, scope: scope, permissions: p, value: .object(["isOwner": .bool(owner), "settledAmountText": .string("120.00"), "settledAmountStatus": .string("verified"), "unverifiedSettledCount": .integer(0), "topics": .array(topics)]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            reads += 1; XCTAssertEqual(operation, .settlement); XCTAssertEqual(scope, self.scope); XCTAssertTrue(options.isEmpty); onRead?(); return try response()
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; XCTFail("No financial command allowed"); throw ClubGovernanceFailure.notConfigured }
    }
    @MainActor private final class Funds: ClubOwnerFundsReading {
        var scope: WalletCommerceScope? = .init(namespace: "synthetic-owner-funds", accountID: 701, epoch: UUID())
        var isConfigured = true
        var reads = 0
        var amount = "8.50", known = true
        var onRead: (() -> Void)?
        var pending: CheckedContinuation<WalletFundsStages, Error>?
        var suspend = false
        func response() throws -> WalletFundsStages {
            try JSONDecoder().decode(WalletFundsStages.self, from: Data("{\"pendingSettlement\":2,\"disputed\":1,\"withdrawable\":\"\(amount)\",\"complaintPeriod\":[],\"amountsKnown\":\(known)}".utf8))
        }
        func readClubOwnerFunds() async throws -> WalletFundsStages {
            reads += 1; onRead?()
            if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
            return try response()
        }
    }
    private func target(_ a: Access) throws -> ClubOwnerFundsTarget {
        let c = ClubGovernanceReadContext(operation: .settlement, scope: a.scope, identity: a.identity, viewerRevision: 3, authorizationGeneration: a.authorizationGeneration, accessIdentity: ObjectIdentifier(a))
        return try XCTUnwrap(ClubOwnerFundsTarget(snapshot: a.response(), context: c))
    }
    private func context(_ f: Funds) -> ClubOwnerFundsContext { .init(reader: f, isCurrent: { true }, support: { AnyView(EmptyView()) }) }
    func testNormalOwnerReadPositiveContactReturnAndRefreshSameClub() async throws {
        let a = Access(), f = Funds(), t = try target(a), c = context(f), m = ClubOwnerFundsWorkflow()
        await m.load(target: t, access: a, context: c, sourceIsCurrent: { true })
        XCTAssertEqual(m.availability, .positive); XCTAssertEqual(f.reads, 1); XCTAssertEqual(a.reads, 2)
        await m.openContact(target: t, access: a, context: c, sourceIsCurrent: { true })
        XCTAssertTrue(m.contactIsCurrent); XCTAssertEqual(f.reads, 2); XCTAssertEqual(a.reads, 4)
        m.closeContact(); XCTAssertFalse(m.contactPresented)
        await m.load(target: t, access: a, context: c, sourceIsCurrent: { true })
        XCTAssertEqual(m.loadedScope, f.scope); XCTAssertEqual(a.scope.clubID, t.clubID); XCTAssertEqual(f.reads, 3); XCTAssertEqual(a.sends, 0)
    }
    func testNonownerAndRevokedFinanceStopBeforeWalletRead() async throws {
        for mode in 0..<2 {
            let a = Access(), f = Funds(), t = try target(a), m = ClubOwnerFundsWorkflow()
            if mode == 0 { a.owner = false } else { a.permitted = false }
            await m.load(target: t, access: a, context: context(f), sourceIsCurrent: { true })
            XCTAssertEqual(f.reads, 0); XCTAssertNil(m.funds); XCTAssertNotNil(m.failure)
        }
    }
    func testOwnerLossDuringWalletReadDiscardsFinancialSnapshot() async throws {
        let a = Access(), f = Funds(), t = try target(a), m = ClubOwnerFundsWorkflow(); f.onRead = { a.owner = false }
        await m.load(target: t, access: a, context: context(f), sourceIsCurrent: { true })
        XCTAssertEqual(a.reads, 2); XCTAssertNil(m.funds); XCTAssertEqual(m.availability, .unknown)
    }
    func testUnknownAndZeroCannotOpenContact() async throws {
        for mode in 0..<2 {
            let a = Access(), f = Funds(), t = try target(a), c = context(f), m = ClubOwnerFundsWorkflow()
            if mode == 0 { f.known = false } else { f.amount = "0" }
            await m.load(target: t, access: a, context: c, sourceIsCurrent: { true })
            await m.openContact(target: t, access: a, context: c, sourceIsCurrent: { true })
            XCTAssertFalse(m.contactPresented); XCTAssertEqual(f.reads, 1); XCTAssertEqual(a.sends, 0)
        }
    }
    func testPositiveToZeroOnTapNeverOpensContact() async throws {
        let a = Access(), f = Funds(), t = try target(a), c = context(f), m = ClubOwnerFundsWorkflow()
        await m.load(target: t, access: a, context: c, sourceIsCurrent: { true }); f.amount = "0"
        await m.openContact(target: t, access: a, context: c, sourceIsCurrent: { true })
        XCTAssertEqual(f.reads, 2); XCTAssertEqual(m.availability, .zero); XCTAssertFalse(m.contactPresented)
    }
    func testForeignWalletAccountOrNamespaceRejectedBeforeRead() async throws {
        for scope in [WalletCommerceScope(namespace: "other", accountID: 701, epoch: UUID()), .init(namespace: "synthetic-owner-funds", accountID: 702, epoch: UUID())] {
            let a = Access(), f = Funds(), t = try target(a), m = ClubOwnerFundsWorkflow(); f.scope = scope
            await m.load(target: t, access: a, context: context(f), sourceIsCurrent: { true })
            XCTAssertEqual(f.reads, 0); XCTAssertEqual(a.reads, 0); XCTAssertNil(m.funds)
        }
    }
    func testEpochAuthorityWalletScopeAndConfigurationChangesAreFenced() async throws {
        for mode in 0..<5 {
            let a = Access(), f = Funds(), t = try target(a), m = ClubOwnerFundsWorkflow()
            f.onRead = { switch mode {
            case 0: a.identity = .init(accountID: 701, epoch: 2)
            case 1: a.authorizationGeneration = UUID()
            case 2: f.scope = .init(namespace: "synthetic-owner-funds", accountID: 701, epoch: UUID())
            case 3: a.storageNamespace = "other"
            default: f.isConfigured = false
            } }
            await m.load(target: t, access: a, context: context(f), sourceIsCurrent: { true })
            XCTAssertNil(m.funds); XCTAssertFalse(m.contactPresented)
        }
    }
    func testStaleHostOrDefaultContextDoesNotRead() async throws {
        let a = Access(), f = Funds(), t = try target(a), m = ClubOwnerFundsWorkflow()
        await m.load(target: t, access: a, context: context(f), sourceIsCurrent: { false })
        XCTAssertEqual(f.reads, 0); XCTAssertEqual(a.reads, 0)
        await m.load(target: t, access: a, context: .init(), sourceIsCurrent: { true })
        XCTAssertNil(m.funds); XCTAssertEqual(a.reads, 0)
    }
    func testLateResultCannotRestoreAfterLeaving() async throws {
        let a = Access(), f = Funds(), t = try target(a), c = context(f), m = ClubOwnerFundsWorkflow(); f.suspend = true
        let task = Task { await m.load(target: t, access: a, context: c, sourceIsCurrent: { true }) }
        while f.pending == nil { await Task.yield() }
        m.invalidate(); f.pending?.resume(returning: try f.response()); f.pending = nil; await task.value
        XCTAssertNil(m.funds); XCTAssertFalse(m.loading); XCTAssertFalse(m.contactPresented)
    }
    func testContextLossWhileContactOpenInvalidatesContactFence() async throws {
        let a = Access(), f = Funds(), t = try target(a), c = context(f), m = ClubOwnerFundsWorkflow()
        await m.load(target: t, access: a, context: c, sourceIsCurrent: { true })
        await m.openContact(target: t, access: a, context: c, sourceIsCurrent: { true }); XCTAssertTrue(m.contactIsCurrent)
        a.identity = nil; XCTAssertFalse(m.contactIsCurrent); m.invalidate(); XCTAssertNil(m.funds)
    }
    func testContactFactoryAbsenceDoesNotTriggerExtraReads() async throws {
        let a = Access(), f = Funds(), t = try target(a), m = ClubOwnerFundsWorkflow(); var c = context(f); c.support = nil
        await m.load(target: t, access: a, context: c, sourceIsCurrent: { true })
        await m.openContact(target: t, access: a, context: c, sourceIsCurrent: { true })
        XCTAssertEqual(f.reads, 1); XCTAssertFalse(m.contactPresented)
    }
    func testQueuedActionFromPreviousScreenGenerationCannotRestartRead() async throws {
        let a = Access(), f = Funds(), t = try target(a), m = ClubOwnerFundsWorkflow()
        let revision = m.revision; m.invalidate()
        await m.load(target: t, access: a, context: context(f), sourceIsCurrent: { true }, expectedGeneration: revision)
        XCTAssertEqual(a.reads, 0); XCTAssertEqual(f.reads, 0); XCTAssertNil(m.funds)
    }
    func testEmptySettlementStillReadsOwnerFundsButDoesNotOfferContact() async throws {
        let a = Access(), f = Funds(), m = ClubOwnerFundsWorkflow(); a.topics = []
        let t = try target(a), c = context(f); XCTAssertFalse(t.hasSettlementRows)
        await m.load(target: t, access: a, context: c, sourceIsCurrent: { true })
        XCTAssertEqual(m.availability, .positive)
        await m.openContact(target: t, access: a, context: c, sourceIsCurrent: { true })
        XCTAssertFalse(m.contactPresented); XCTAssertEqual(f.reads, 1)
    }
    func testRefreshClearsPreviousPositiveOnFailure() async throws {
        let a = Access(), f = Funds(), t = try target(a), c = context(f), m = ClubOwnerFundsWorkflow()
        await m.load(target: t, access: a, context: c, sourceIsCurrent: { true }); f.amount = "bad"
        await m.load(target: t, access: a, context: c, sourceIsCurrent: { true })
        XCTAssertEqual(m.availability, .unknown); XCTAssertNil(m.funds); XCTAssertFalse(m.loading)
    }
}
