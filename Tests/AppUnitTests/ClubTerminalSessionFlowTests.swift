import XCTest
@testable import Questify

@MainActor final class ClubTerminalSessionFlowTests: XCTestCase {
    private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 2)
        var isConfigured = true
        var storageNamespace = "synthetic-terminal"
        var authorizationGeneration: UUID? = UUID()
        let allowsOfflineWrites = false
        var activities = [41]
        var status = 1, lifecycle = 0, responseTopicID = 91
        var rejectReason = ""
        var canDirect: ClubGovernanceValue = .bool(true)
        var finance = true
        var sends = 0
        var reads: [ClubGovernanceRead] = []
        var beforeReturn: ((ClubGovernanceRead) -> Void)?
        var failure: ClubGovernanceFailure?
        let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
        func context() -> ClubGovernanceReadContext {
            .init(operation: .topicOverview, scope: scope, identity: identity, viewerRevision: 5, authorizationGeneration: authorizationGeneration, accessIdentity: ObjectIdentifier(self))
        }
        func response(_ op: ClubGovernanceRead, _ target: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([.string("CLUB_OWNER")]), "permissions": .array(finance ? [.string("club:finance:read")] : [])]), scope: target)
            let value: ClubGovernanceValue
            switch op {
            case .topicOverview:
                value = .object(["id": .integer(responseTopicID), "name": .string("Synthetic topic"), "status": .integer(status), "lifecycle": .integer(lifecycle), "rejectReason": .string(rejectReason), "activityList": .array(activities.map { .object(["id": .integer($0), "name": .string("Synthetic session")]) })])
            case .topicStats: value = .object(["canDirect": canDirect, "sessionStatus": .string("FINISHED"), "nodeCount": .integer(0), "sessionHeadcount": .integer(0), "pendingVerifyCount": .integer(0), "verifiedByMeCount": .integer(0)])
            case .access: value = .object([:])
            default: throw ClubGovernanceFailure.invalidRequest
            }
            return .init(operation: op, scope: target, permissions: permission, value: value)
        }
        func read(_ op: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            reads.append(op); XCTAssertTrue(options.isEmpty)
            if let failure { throw failure }
            let value = try response(op, scope); beforeReturn?(op); return value
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; XCTFail("read-only flow attempted write"); throw ClubGovernanceFailure.notConfigured }
    }
    private final class Provider: ClubTerminalProjectionReading {
        var identity = ClubReadIdentity(accountID: 701, epoch: 2)
        var namespace = "synthetic-terminal"
        let lifetimeID = UUID()
        var isCurrent = true
        var status = "FINISHED", sessionID = 501, revision = 3
        var returnedActivity: Int?
        var reads: [Int] = []
        var held = false
        var entered: (() -> Void)?
        var pending: CheckedContinuation<PlayDirectorProjection, Error>?
        func value(_ activityID: Int) throws -> PlayDirectorProjection {
            try .init(.object(["activityId": .int(activityID), "perspective": .string("CLUB"), "sessionId": .int(sessionID), "revision": .int(revision), "status": .string(status), "club": .object([:])]), activityID: activityID)
        }
        func read(activityID: Int) async throws -> PlayDirectorProjection {
            reads.append(activityID)
            if held { return try await withCheckedThrowingContinuation { pending = $0; entered?() } }
            return try value(returnedActivity ?? activityID)
        }
        func invalidate() { isCurrent = false }
    }
    private func flow(_ access: Access, _ provider: Provider, current: @escaping () -> Bool = { true }) -> ClubTerminalSessionFlow {
        .init(context: access.context(), access: access, provider: provider, sourceIsCurrent: current)
    }
    func testWholeReadTerminalFinanceRouteAndReturnKeepsSameSession() async throws {
        let a = Access(), p = Provider(), m = flow(a, p)
        await m.load(); XCTAssertTrue(m.terminal); XCTAssertEqual(m.selectedID, 41)
        await m.openSettlement(); let route = try XCTUnwrap(m.settlement)
        XCTAssertTrue(m.accepts(route)); XCTAssertEqual(a.reads.last, .access); XCTAssertEqual(a.sends, 0)
        await m.returned(route); XCTAssertNil(m.settlement); XCTAssertEqual(m.selectedID, 41); XCTAssertTrue(m.terminal)
        XCTAssertEqual(p.reads, [41,41,41]); XCTAssertEqual(a.sends, 0)
    }
    func testCancelledIsTerminalWithoutAnyVerificationOrMutation() async {
        let a = Access(), p = Provider(); p.status = "CANCELLED"; let m = flow(a,p)
        await m.load(); await m.openSettlement(); XCTAssertNotNil(m.settlement); XCTAssertEqual(a.sends,0)
    }
    func testRunningAndDisplayOnlyFinishedDoNotEnableSettlement() async {
        let a = Access(), p = Provider(); p.status = "RUNNING"; let m = flow(a,p)
        await m.load(); await m.openSettlement(); XCTAssertFalse(m.terminal); XCTAssertNil(m.settlement); XCTAssertFalse(a.reads.contains(.access))
    }
    func testMultipleSessionsRequireChoiceAndNeverChooseFirst() async {
        let a = Access(), p = Provider(); a.activities = [41,42]; let m = flow(a,p)
        await m.load(); XCTAssertNil(m.selectedID); XCTAssertTrue(p.reads.isEmpty)
        await m.select(42); XCTAssertEqual(m.selectedID,42); XCTAssertEqual(p.reads,[42])
    }
    func testNoSessionIsEmptyWithoutProjectionDispatch() async {
        let a = Access(), p = Provider(); a.activities = []; let m = flow(a,p)
        await m.load(); XCTAssertTrue(m.activities.isEmpty); XCTAssertTrue(p.reads.isEmpty)
    }
    func testDuplicateActivityIDsRejectWholeProjection() async {
        let a = Access(), p = Provider(); a.activities = [41,41]; let m = flow(a,p)
        await m.load(); XCTAssertEqual(m.failure,.malformed); XCTAssertTrue(p.reads.isEmpty)
    }
    func testForgedSelectionDoesNotDispatch() async {
        let a = Access(), p = Provider(), m = flow(a,p)
        await m.load(); let count = a.reads.count
        await m.select(999); XCTAssertEqual(a.reads.count,count); XCTAssertEqual(m.selectedID,41)
    }
    func testReviewingRejectedAndLifecycleSevenNeverReadDirector() async {
        for (status,lifecycle,reason) in [(0,0,""),(2,0,""),(1,7,""),(1,0,"Rejected")] {
            let a = Access(), p = Provider(); a.status=status; a.lifecycle=lifecycle; a.rejectReason=reason; let m=flow(a,p)
            await m.load(); XCTAssertFalse(m.terminal); XCTAssertTrue(p.reads.isEmpty)
        }
    }
    func testFalseMissingAndStringCanDirectFailClosedDespiteOwnerRole() async {
        let flags: [ClubGovernanceValue] = [.bool(false),.null,.string("true")]
        for flag in flags {
            let a=Access(), p=Provider(); a.canDirect=flag; let m=flow(a,p)
            await m.load(); XCTAssertEqual(m.failure,.forbidden); XCTAssertTrue(p.reads.isEmpty)
        }
    }
    func testFinancePermissionIsFreshAndRequiredAtOpen() async {
        let a=Access(), p=Provider(), m=flow(a,p); await m.load(); a.finance=false
        await m.openSettlement(); XCTAssertNil(m.settlement); XCTAssertEqual(m.failure,.forbidden); XCTAssertEqual(a.sends,0)
    }
    func testTerminalChangesBeforeOpenCannotNavigate() async {
        let a=Access(), p=Provider(), m=flow(a,p); await m.load(); p.status="RUNNING"
        await m.openSettlement(); XCTAssertNil(m.settlement); XCTAssertEqual(m.failure,.targetChanged)
    }
    func testDifferentSessionOrRegressedRevisionRejectsOldButton() async {
        for changedSession in [true,false] {
            let a=Access(), p=Provider(), m=flow(a,p); await m.load()
            if changedSession { p.sessionID=502 } else { p.revision=2 }
            await m.openSettlement(); XCTAssertNil(m.settlement); XCTAssertEqual(m.failure,.targetChanged)
        }
    }
    func testRemovedSelectedActivityDoesNotFallBackOnReturn() async throws {
        let a=Access(), p=Provider(), m=flow(a,p); await m.load(); await m.openSettlement(); let route=try XCTUnwrap(m.settlement)
        a.activities=[42]; await m.returned(route)
        XCTAssertEqual(m.selectedID,41); XCTAssertNil(m.projection); XCTAssertEqual(m.failure,.targetChanged); XCTAssertFalse(p.reads.contains(42))
    }
    func testOldReturnCallbackCannotCloseNewSettlement() async throws {
        let a=Access(), p=Provider(), m=flow(a,p); await m.load(); await m.openSettlement(); let old=try XCTUnwrap(m.settlement)
        await m.returned(old); await m.openSettlement(); let new=try XCTUnwrap(m.settlement)
        await m.returned(old); XCTAssertEqual(m.settlement,new)
    }
    func testDoubleOpenDoesNotIssueAnotherRead() async throws {
        let a=Access(), p=Provider(), m=flow(a,p); await m.load(); await m.openSettlement(); let count=a.reads.count
        await m.openSettlement(); XCTAssertEqual(a.reads.count,count)
    }
    func testIdentityNamespaceAuthorityAndProviderRevocationHideState() async {
        for kind in 0..<4 {
            let a=Access(), p=Provider(), m=flow(a,p); await m.load()
            switch kind { case 0:a.identity = .init(accountID:701,epoch:3); case 1:a.storageNamespace="other"; case 2:a.authorizationGeneration=UUID(); default:p.invalidate() }
            XCTAssertFalse(m.isCurrent); XCTAssertFalse(m.terminal); await m.openSettlement(); XCTAssertNil(m.settlement)
        }
    }
    func testSourceRetiredBeforeInitialReadDoesNotDispatch() async {
        let a=Access(), p=Provider(), m=flow(a,p,current:{false}); await m.load(); XCTAssertTrue(a.reads.isEmpty)
    }
    func testCloseDuringHeldReadRejectsLateResponse() async throws {
        let a=Access(), p=Provider(); p.held=true; let m=flow(a,p)
        let entered=expectation(description:"projection"); p.entered={entered.fulfill()}
        let task=Task { await m.load() }; await fulfillment(of:[entered],timeout:1)
        m.close(); p.pending?.resume(returning:try p.value(41)); await task.value
        XCTAssertNil(m.projection); XCTAssertFalse(m.loading); XCTAssertFalse(m.isCurrent); XCTAssertNil(m.settlement)
    }
    func testPermissionChangesDuringReadDiscardsResponse() async {
        let a=Access(), p=Provider(), m=flow(a,p)
        a.beforeReturn={_ in a.authorizationGeneration=UUID()}; await m.load()
        XCTAssertNil(m.projection); XCTAssertTrue(p.reads.isEmpty)
    }
    func testFailureRetryUsesSameActivityAndNoWrites() async {
        let a=Access(), p=Provider(), m=flow(a,p); a.failure = .malformed
        await m.load(); XCTAssertEqual(m.failure,.malformed); a.failure=nil
        await m.load(); XCTAssertTrue(m.terminal); XCTAssertEqual(a.sends,0)
    }
    func testForeignFreshTopicAndProjectionActivityFailClosed() async {
        let a=Access(), p=Provider(), m=flow(a,p); a.responseTopicID=92
        await m.load(); XCTAssertNil(m.projection); XCTAssertTrue(p.reads.isEmpty)
        a.responseTopicID=91; p.returnedActivity=42; await m.load()
        XCTAssertNil(m.projection); XCTAssertEqual(m.failure,.targetChanged)
    }
    func testProviderIdentityAndNamespaceMismatchCannotRead() async {
        for identityChange in [true,false] {
            let a=Access(), p=Provider()
            if identityChange { p.identity = .init(accountID:702,epoch:2) } else { p.namespace="other" }
            let m=flow(a,p); await m.load(); XCTAssertTrue(a.reads.isEmpty); XCTAssertTrue(p.reads.isEmpty)
        }
    }
    func testSourceGenerationRetiredDuringHeldReadCannotRevive() async throws {
        let a=Access(), p=Provider(); p.held=true; var current=true; let m=flow(a,p,current:{current})
        let entered=expectation(description:"projection"); p.entered={entered.fulfill()}
        let task=Task { await m.load() }; await fulfillment(of:[entered],timeout:1)
        current=false; p.pending?.resume(returning:try p.value(41)); await task.value
        current=true; XCTAssertFalse(m.isCurrent); XCTAssertNil(m.projection); XCTAssertNil(m.settlement)
    }
    func testStableOwnerConcreteIdentityRejectsOldDismissalAfterReopen() throws {
        let access = Access(), firstProvider = Provider(), secondProvider = Provider()
        let presentation = ClubTerminalSessionPresentation(), approval = UUID()
        let source = ClubTerminalSessionPresentation.Source(context: access.context(), generation: 1,
            snapshot: try access.response(.topicOverview, access.scope), approvalID: approval, viewerRevision: 5)
        var host = ClubTerminalSessionContext(viewerRevision: 5, approvalID: approval, makeProvider: { firstProvider })
        presentation.bind(source)
        presentation.open(source: source, host: host, access: access, sourceIsCurrent: { true })
        let first = try XCTUnwrap(presentation.presented)
        let owner = ClubTerminalSessionOwner(item: first, presentation: presentation, access: access,
            coordinator: ClubGovernanceCoordinator(access: access))
        let oldDismissal = owner.presentationBinding
        XCTAssertTrue(oldDismissal.wrappedValue)
        presentation.close(first.id); XCTAssertFalse(firstProvider.isCurrent)
        host.makeProvider = { secondProvider }
        presentation.open(source: source, host: host, access: access, sourceIsCurrent: { true })
        let second = try XCTUnwrap(presentation.presented)
        XCTAssertNotEqual(first.id, second.id)
        oldDismissal.wrappedValue = false
        XCTAssertEqual(presentation.presented?.id, second.id); XCTAssertTrue(secondProvider.isCurrent)
        XCTAssertTrue(presentation.isCurrent(second)); XCTAssertFalse(oldDismissal.wrappedValue)
        access.identity = .init(accountID: 702, epoch: 3)
        XCTAssertFalse(presentation.isCurrent(second))
        presentation.leave(); XCTAssertNil(presentation.presented); XCTAssertFalse(secondProvider.isCurrent)
        XCTAssertTrue(access.reads.isEmpty); XCTAssertTrue(firstProvider.reads.isEmpty)
        XCTAssertTrue(secondProvider.reads.isEmpty); XCTAssertEqual(access.sends, 0)
    }

}
