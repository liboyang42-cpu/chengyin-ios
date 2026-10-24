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

@MainActor extension ClubOwnerFundsFlowTests {
    private func source(_ a: Access, _ f: Funds, generation: UInt64 = 1) throws -> ClubOwnerFundsParent.Source {
        .init(target: try target(a), readerID: ObjectIdentifier(f), walletScope: f.scope,
              generation: generation, namespace: a.storageNamespace)
    }
    private func parent(_ source: ClubOwnerFundsParent.Source) -> ClubOwnerFundsParent {
        let parent = ClubOwnerFundsParent(); parent.appear(); parent.synchronize(source); return parent
    }
    private func readFunds(_ p: ClubOwnerFundsParent, _ source: ClubOwnerFundsParent.Source, _ a: Access, _ f: Funds) async throws {
        let ticket = try XCTUnwrap(p.ticket(current: source, active: true, otherPresented: false))
        await p.load(ticket, access: a, context: context(f), current: { source }, active: { true }, otherPresented: { false })
    }
    private func contact(_ p: ClubOwnerFundsParent, _ source: ClubOwnerFundsParent.Source, _ a: Access, _ f: Funds) async throws -> ClubOwnerFundsParent.Contact {
        let ticket = try XCTUnwrap(p.ticket(current: source, active: true, otherPresented: false))
        await p.openContact(ticket, access: a, context: context(f), current: { source }, active: { true }, otherPresented: { false })
        return try XCTUnwrap(p.contact)
    }
    func testParentNormalFundsContactAndVisibleReturnRechecksBothFinanceReads() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let item = try await contact(p, s, a, f)
        XCTAssertEqual(a.reads, 4); XCTAssertEqual(f.reads, 2); XCTAssertTrue(p.current(item, source: s, active: true))
        p.binding(item, current: { s }, active: { true }).wrappedValue = false
        XCTAssertFalse(p.current(item, source: s, active: true)); XCTAssertTrue(p.dismissed(item, current: s, active: true))
        try await readFunds(p, s, a, f)
        XCTAssertEqual(a.reads, 6); XCTAssertEqual(f.reads, 3); XCTAssertEqual(a.sends, 0)
    }
    func testParentSheetCoverageRetainsExactContactAndFreshReturnWaitsForAppearance() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let item = try await contact(p, s, a, f)
        p.hide(); XCTAssertTrue(p.current(item, source: s, active: true)); XCTAssertNotNil(p.attachment)
        p.close(item); XCTAssertTrue(p.dismissed(item, current: s, active: true))
        XCTAssertNil(p.ticket(current: s, active: true, otherPresented: false)); XCTAssertTrue(p.needsRead)
        XCTAssertEqual(f.reads, 2); p.appear(); try await readFunds(p, s, a, f); XCTAssertEqual(f.reads, 3)
    }
    func testParentAppearanceBeforeContactDismissDoesNotReadUntilExactDismissal() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let item = try await contact(p, s, a, f)
        p.hide(); p.close(item); p.appear()
        XCTAssertNil(p.ticket(current: s, active: true, otherPresented: false)); XCTAssertEqual(f.reads, 2)
        XCTAssertTrue(p.dismissed(item, current: s, active: true)); try await readFunds(p, s, a, f); XCTAssertEqual(f.reads, 3)
    }
    func testOldContactBindingCloseAndDismissCannotTouchReopenedContact() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let old = try await contact(p, s, a, f)
        let binding = p.binding(old, current: { s }, active: { true }); p.close(old)
        XCTAssertTrue(p.dismissed(old, current: s, active: true)); try await readFunds(p, s, a, f)
        let fresh = try await contact(p, s, a, f); XCTAssertNotEqual(old.id, fresh.id)
        binding.wrappedValue = false; p.close(old); XCTAssertFalse(p.dismissed(old, current: s, active: true))
        XCTAssertTrue(p.current(fresh, source: s, active: true)); XCTAssertFalse(binding.wrappedValue)
    }
    func testOldRowTicketCannotRestartReadAfterContactReturn() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let old = try XCTUnwrap(p.ticket(current: s, active: true, otherPresented: false))
        let item = try await contact(p, s, a, f); p.close(item); XCTAssertTrue(p.dismissed(item, current: s, active: true))
        await p.load(old, access: a, context: context(f), current: { s }, active: { true }, otherPresented: { false }, force: true)
        XCTAssertEqual(f.reads, 2); XCTAssertTrue(p.needsRead)
    }
    func testRealDepartureThenLateDismissCannotReadHiddenOrRetireNewAttachment() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let item = try await contact(p, s, a, f), old = try XCTUnwrap(p.attachment)
        XCTAssertTrue(p.depart(old)); XCTAssertFalse(p.dismissed(item, current: s, active: true)); XCTAssertNil(p.ticket(current: s, active: true, otherPresented: false))
        p.appear(); p.synchronize(s); let fresh = try XCTUnwrap(p.attachment); XCTAssertNotEqual(old, fresh)
        XCTAssertFalse(p.depart(old)); XCTAssertEqual(p.attachment, fresh); try await readFunds(p, s, a, f); XCTAssertEqual(f.reads, 3)
    }
    func testHiddenSceneRecoveryCannotRestartFundsButVisibleRecoveryCan() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); p.hide(); p.background(); p.synchronize(s)
        XCTAssertNil(p.ticket(current: s, active: true, otherPresented: false)); XCTAssertNil(p.workflow.funds)
        p.appear(); try await readFunds(p, s, a, f); XCTAssertEqual(f.reads, 2); XCTAssertEqual(a.sends, 0)
    }
    func testPendingFundsReadDepartAndLateResponseCannotRestoreSnapshot() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s); f.suspend = true
        let ticket = try XCTUnwrap(p.ticket(current: s, active: true, otherPresented: false))
        let task = Task { await p.load(ticket, access: a, context: context(f), current: { s }, active: { true }, otherPresented: { false }) }
        while f.pending == nil { await Task.yield() }
        XCTAssertTrue(p.depart(try XCTUnwrap(p.attachment))); f.pending?.resume(returning: try f.response()); f.pending = nil; await task.value
        XCTAssertNil(p.workflow.funds); XCTAssertFalse(p.workflow.loading); XCTAssertNil(p.contact); XCTAssertEqual(a.reads, 1)
    }
    func testSourceAndWalletReplacementRejectOldReadAndQueuedContact() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let old = try XCTUnwrap(p.ticket(current: s, active: true, otherPresented: false))
        f.scope = .init(namespace: f.scope!.namespace, accountID: 701, epoch: UUID()); let fresh = try source(a, f, generation: 2)
        p.synchronize(fresh); await p.openContact(old, access: a, context: context(f), current: { fresh }, active: { true }, otherPresented: { false })
        XCTAssertEqual(f.reads, 1); XCTAssertNil(p.contact); XCTAssertNil(p.workflow.funds)
        try await readFunds(p, fresh, a, f); XCTAssertEqual(p.workflow.loadedScope, f.scope)
    }
    func testLedgerPresentationBlocksContactAndPreservesNoWriteSemantics() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let offered = try XCTUnwrap(p.ticket(current: s, active: true, otherPresented: false))
        XCTAssertNil(p.ticket(current: s, active: true, otherPresented: true))
        await p.openContact(offered, access: a, context: context(f), current: { s }, active: { true }, otherPresented: { true })
        XCTAssertEqual(f.reads, 1); XCTAssertNil(p.contact); XCTAssertEqual(a.sends, 0)
    }
    func testInterruptedReturnReadRestartsOnVisibleForegroundOnly() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); let item = try await contact(p, s, a, f); p.close(item); XCTAssertTrue(p.dismissed(item, current: s, active: true))
        f.suspend = true; let ticket = try XCTUnwrap(p.ticket(current: s, active: true, otherPresented: false))
        let task = Task { await p.load(ticket, access: a, context: context(f), current: { s }, active: { true }, otherPresented: { false }) }
        while f.pending == nil { await Task.yield() }; p.background()
        f.pending?.resume(returning: try f.response()); f.pending = nil; await task.value
        XCTAssertNil(p.workflow.funds); XCTAssertTrue(p.needsRead); f.suspend = false
        try await readFunds(p, s, a, f); XCTAssertEqual(f.reads, 4); XCTAssertEqual(a.sends, 0)
    }
}

@MainActor extension ClubOwnerFundsFlowTests {
    func testAccountSwitchDuringContactReadCannotOpenOrClearReplacementFunds() async throws {
        let a = Access(), oldFunds = Funds(), oldSource = try source(a, oldFunds), p = parent(oldSource)
        try await readFunds(p, oldSource, a, oldFunds)
        let ticket = try XCTUnwrap(p.ticket(current: oldSource, active: true, otherPresented: false)); oldFunds.suspend = true
        var liveSource = oldSource
        let pending = Task { await p.openContact(ticket, access: a, context: context(oldFunds), current: { liveSource }, active: { true }, otherPresented: { false }) }
        while oldFunds.pending == nil { await Task.yield() }
        a.identity = .init(accountID: 702, epoch: 2)
        let replacement = Funds(); replacement.scope = .init(namespace: a.storageNamespace, accountID: 702, epoch: UUID())
        liveSource = try source(a, replacement, generation: 2); p.synchronize(liveSource)
        try await readFunds(p, liveSource, a, replacement)
        oldFunds.pending?.resume(returning: try oldFunds.response()); oldFunds.pending = nil; await pending.value
        XCTAssertNil(p.contact); XCTAssertFalse(p.workflow.contactPresented); XCTAssertFalse(p.workflow.loading); XCTAssertEqual(p.workflow.loadedScope, replacement.scope)
        XCTAssertEqual(p.workflow.availability, .positive); XCTAssertEqual(replacement.reads, 1); XCTAssertEqual(a.sends, 0)
    }
    func testBackgroundDuringContactReadCannotPresentAfterLateWalletResponse() async throws {
        let a = Access(), f = Funds(), s = try source(a, f), p = parent(s)
        try await readFunds(p, s, a, f); f.suspend = true
        let ticket = try XCTUnwrap(p.ticket(current: s, active: true, otherPresented: false))
        let pending = Task { await p.openContact(ticket, access: a, context: context(f), current: { s }, active: { true }, otherPresented: { false }) }
        while f.pending == nil { await Task.yield() }; p.background()
        f.pending?.resume(returning: try f.response()); f.pending = nil; await pending.value
        XCTAssertNil(p.contact); XCTAssertNil(p.workflow.funds); XCTAssertTrue(p.needsRead); XCTAssertFalse(p.workflow.loading)
    }
}
