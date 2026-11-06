import XCTest
@testable import QuestifyCore

@MainActor
final class ClubCreateToManageFlowTests: XCTestCase {
    private func validCreateDraft() -> ClubOperationsDraft {
        var draft = ClubOperationsDraft()
        draft.name = "Chengyin Urban Explorers"
        draft.city = "Shanghai"
        draft.clubType = "兴趣社群"
        draft.activityPrefs = ["轻社交"]
        return draft
    }

    func testProductionDefaultCreationGateRemainsClosedAndDoesNotClaimClub28Coverage() async throws {
        let defaultGate = ClubCreationGate.productionDefault
        XCTAssertFalse(defaultGate.isConfigured)
        XCTAssertEqual(defaultGate.writeAvailability, .unverified)
        XCTAssertTrue(defaultGate.isBlocked)
        XCTAssertFalse(defaultGate.isCreationAllowed)
        XCTAssertTrue(defaultGate.bilingualGateCopy.contains("俱乐部创建门控未开启"))

        let enabledGate = ClubCreationGate(isConfigured: true, writeAvailability: .approved)
        XCTAssertTrue(enabledGate.isCreationAllowed)
        XCTAssertFalse(enabledGate.isBlocked)
        XCTAssertTrue(enabledGate.bilingualGateCopy.contains("不扩 Club28，旧暂停边界保持不变"))

        // Unverified fixture adapter refuses creation dispatch and blocks entering management.
        let access = ClubOperationsFixtureAccess(scenario: .unverified)
        let coordinator = ClubOperationsCoordinator(access: access)
        let identity = try XCTUnwrap(access.identity)
        let review = try await coordinator.prepare(
            .create(validCreateDraft()),
            target: .create,
            expectedIdentity: identity,
            ownerID: UUID()
        )
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.state(target: .create), .notSent)
        XCTAssertEqual(access.writeCount, 0)

        var flow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(access: access),
            receiptAccountId: identity.accountID,
            receiptClubId: 82,
            currentAccountId: identity.accountID,
            readbackAccountId: identity.accountID,
            readbackOwnedClubIds: [81, 82],
            readbackSucceeded: true,
            requestedTab: "manage"
        )
        XCTAssertEqual(flow.blockReason, .gateBlocked)
        XCTAssertFalse(flow.canEnterManagement)
        XCTAssertEqual(flow.validatedTab, .overview)
        XCTAssertNil(flow.enterClubManagement())
        XCTAssertTrue(flow.bilingualStatusCopy.contains("俱乐部创建门控未开启"))
        XCTAssertTrue(flow.bilingualStatusCopy.contains("Club creation gate is closed"))
    }

    func testConfirmedReceiptAndSameAccountReadbackEnablesEnterManagementAndValidatesTab() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .owner)
        let coordinator = ClubOperationsCoordinator(access: access)
        let identity = try XCTUnwrap(access.identity)
        let ownerID = UUID()

        let review = try await coordinator.prepare(
            .create(validCreateDraft()),
            target: .create,
            expectedIdentity: identity,
            ownerID: ownerID
        )
        await coordinator.confirm(review)

        guard case .acknowledged(let receipt) = coordinator.state(target: .create) else {
            XCTFail("Expected confirmed create receipt")
            return
        }
        let createdClubID = try XCTUnwrap(receipt.clubID)
        XCTAssertEqual(createdClubID, 82)

        var flow = ClubCreateToManageFlowState(requestedTab: "manage")
        flow.applyConfirmedReceipt(
            state: coordinator.state(target: .create),
            pendingIdentity: review.identity,
            currentIdentity: access.identity,
            access: access
        )
        let readbackSnapshot = try XCTUnwrap(
            flow.acceptReadback(from: coordinator, access: access, currentIdentity: access.identity)
        )
        XCTAssertTrue(readbackSnapshot.ownedClubIDs.contains(createdClubID))
        XCTAssertFalse(flow.requiresReadbackRecovery(state: coordinator.state(target: .create), hasSnapshot: true))

        XCTAssertNil(flow.blockReason)
        XCTAssertTrue(flow.canEnterManagement)
        XCTAssertEqual(flow.validatedTab, .manage)
        XCTAssertEqual(flow.actionButtonTitle, "进入俱乐部管理 / Enter Club Management")
        XCTAssertTrue(flow.bilingualStatusCopy.contains("同账号回读已确认（俱乐部 #82）"))
        XCTAssertTrue(flow.bilingualStatusCopy.contains("Same-account readback verified (Club #82)"))

        let destination = try XCTUnwrap(flow.enterClubManagement())
        XCTAssertEqual(destination, ClubCreateToManageDestination(accountId: 701, clubId: 82, tab: .manage))
        XCTAssertTrue(destination.opensManagementWorkspace)
        XCTAssertEqual(flow.enteredDestination, destination)

        let createdClubSnapshot = try await access.snapshot(target: .club(createdClubID))
        XCTAssertEqual(createdClubSnapshot.profile?.club.id, 82)
    }

    func testWorkspaceTabValidationFallsBackSafelyToOverviewAndDoesNotOpenManagementWorkspace() {
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: nil), .overview)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: ""), .overview)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "   "), .overview)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "invalid-tab"), .overview)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "MANAGE"), .manage)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "events"), .events)
        XCTAssertEqual(ClubWorkspaceTab.validate(requestedTab: "posts"), .posts)
        XCTAssertEqual(ClubWorkspaceTab.resolve(requestedTab: "manage", canEnterManagement: false), .overview)
        XCTAssertEqual(ClubWorkspaceTab.resolve(requestedTab: "manage", canEnterManagement: true), .manage)

        var verifiedFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(isConfigured: true, writeAvailability: .approved),
            receiptAccountId: 701,
            receiptClubId: 82,
            currentAccountId: 701,
            readbackAccountId: 701,
            readbackOwnedClubIds: [81, 82],
            readbackSucceeded: true,
            requestedTab: "unknown_tab"
        )
        XCTAssertTrue(verifiedFlow.canEnterManagement)
        XCTAssertEqual(verifiedFlow.validatedTab, .overview)
        let fallbackDestination = verifiedFlow.enterClubManagement(requestedTab: nil)
        XCTAssertEqual(
            fallbackDestination,
            ClubCreateToManageDestination(accountId: 701, clubId: 82, tab: .overview)
        )
        XCTAssertEqual(fallbackDestination?.opensManagementWorkspace, false)
        XCTAssertTrue(fallbackDestination?.bilingualDestinationLabel.contains("俱乐部详情（分栏：overview）") == true)
    }

    func testConfirmedCreateReceiptReadbackFailureThenRetryReadbackSucceedsAndUnlocksNavigation() async throws {
        let access = ClubOperationsFixtureAccess(scenario: .readbackUnavailable)
        let coordinator = ClubOperationsCoordinator(access: access)
        let identity = try XCTUnwrap(access.identity)
        let ownerID = UUID()

        let review = try await coordinator.prepare(
            .create(validCreateDraft()),
            target: .create,
            expectedIdentity: identity,
            ownerID: ownerID
        )
        await coordinator.confirm(review)

        guard case .acknowledged(let receipt) = coordinator.state(target: .create) else {
            XCTFail("Expected confirmed create receipt")
            return
        }
        XCTAssertEqual(receipt.clubID, 82)
        XCTAssertEqual(coordinator.readback(target: .create), .unavailable)

        var flow = ClubCreateToManageFlowState(requestedTab: "manage")
        flow.applyConfirmedReceipt(
            state: coordinator.state(target: .create),
            pendingIdentity: review.identity,
            currentIdentity: access.identity,
            access: access
        )
        let initialSnapshot = flow.acceptReadback(from: coordinator, access: access, currentIdentity: access.identity)
        XCTAssertNil(initialSnapshot)
        XCTAssertTrue(flow.readbackUnavailable)
        XCTAssertEqual(flow.blockReason, .readbackFailed)
        XCTAssertFalse(flow.canEnterManagement)
        XCTAssertTrue(flow.requiresReadbackRecovery(state: coordinator.state(target: .create), hasSnapshot: false))
        XCTAssertNil(flow.enterClubManagement())

        // Recover readback on the same account via retryReadback (the same path triggered by retryRead / readBack).
        access.readbackRecoveryEnabled = true
        let recoveredSnapshot = await flow.retryReadback(
            using: coordinator,
            access: access,
            currentIdentity: access.identity,
            ownerID: ownerID
        )
        XCTAssertNotNil(recoveredSnapshot)
        XCTAssertFalse(flow.readbackUnavailable)
        XCTAssertTrue(flow.readbackSucceeded)
        XCTAssertEqual(flow.readbackAccountId, 701)
        XCTAssertEqual(flow.readbackOwnedClubIds, [81, 82])
        XCTAssertNil(flow.blockReason)
        XCTAssertTrue(flow.canEnterManagement)
        XCTAssertFalse(flow.requiresReadbackRecovery(state: coordinator.state(target: .create), hasSnapshot: true))

        let destination = try XCTUnwrap(flow.enterClubManagement())
        XCTAssertEqual(destination, ClubCreateToManageDestination(accountId: 701, clubId: 82, tab: .manage))
        XCTAssertTrue(destination.opensManagementWorkspace)
    }

    func testReadbackFailureOrClubIdMismatchBlocksEnteringManagement() async throws {
        var mismatchedClubFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(isConfigured: true, writeAvailability: .approved),
            receiptAccountId: 701,
            receiptClubId: 82,
            currentAccountId: 701,
            readbackAccountId: 701,
            readbackOwnedClubIds: [81],
            readbackSucceeded: true,
            requestedTab: "manage"
        )
        XCTAssertEqual(mismatchedClubFlow.blockReason, .clubIdMismatch)
        XCTAssertFalse(mismatchedClubFlow.canEnterManagement)
        XCTAssertNil(mismatchedClubFlow.enterClubManagement())
        XCTAssertTrue(mismatchedClubFlow.bilingualStatusCopy.contains("俱乐部 ID 回读不匹配"))
        XCTAssertTrue(mismatchedClubFlow.bilingualStatusCopy.contains("Club ID readback mismatch"))
    }

    func testAccountMismatchBlocksEnteringManagementEvenAfterReceipt() {
        var switchedAccountFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(isConfigured: true, writeAvailability: .approved),
            receiptAccountId: 701,
            receiptClubId: 82,
            currentAccountId: 702,
            readbackAccountId: 701,
            readbackOwnedClubIds: [81, 82],
            readbackSucceeded: true,
            requestedTab: "manage"
        )
        XCTAssertEqual(switchedAccountFlow.blockReason, .accountMismatch)
        XCTAssertFalse(switchedAccountFlow.canEnterManagement)
        XCTAssertEqual(switchedAccountFlow.validatedTab, .overview)
        XCTAssertNil(switchedAccountFlow.enterClubManagement())
        XCTAssertTrue(switchedAccountFlow.bilingualStatusCopy.contains("账号已变更或不匹配"))
        XCTAssertTrue(switchedAccountFlow.bilingualStatusCopy.contains("Account mismatch detected"))

        var foreignReadbackFlow = ClubCreateToManageFlowState(
            gate: ClubCreationGate(isConfigured: true, writeAvailability: .approved),
            receiptAccountId: 701,
            receiptClubId: 82,
            currentAccountId: 701,
            readbackAccountId: 702,
            readbackOwnedClubIds: [81, 82],
            readbackSucceeded: true,
            requestedTab: "manage"
        )
        XCTAssertEqual(foreignReadbackFlow.blockReason, .accountMismatch)
        XCTAssertFalse(foreignReadbackFlow.canEnterManagement)
        XCTAssertNil(foreignReadbackFlow.enterClubManagement())
    }
}
