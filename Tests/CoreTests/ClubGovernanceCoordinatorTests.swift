import XCTest
@testable import QuestifyCore

@MainActor final class ClubGovernanceCoordinatorTests: XCTestCase {
    func testPrepareEveryOperationUsesFreshTargetProof() async throws {
        for operation in ClubGovernanceMutation.allCases {
            let access = ClubGovernanceFixtureAccess()
            let coordinator = ClubGovernanceCoordinator(access: access)
            // Independent instance per operation; no write happens during review.
            let review = try await coordinator.prepare(ClubGovernanceFixtures.command(operation))
            XCTAssertEqual(review.command.operation, operation)
            XCTAssertEqual(review.snapshot.operation, operation.reviewRead)
        }
    }
    func testAllOfflineCommandsPreflightThenAcknowledgeExactlyOnce() async throws {
        for operation in ClubGovernanceMutation.allCases {
            let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(operation)
            let coordinator = ClubGovernanceCoordinator(access: access)
            let review = try await coordinator.prepare(command)
            _ = try await coordinator.confirm(review)
            XCTAssertEqual(access.sent.count, 1); XCTAssertEqual(coordinator.state, .acknowledged)
            do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
            XCTAssertEqual(access.sent.count, 1)
        }
    }
    func testProductionReviewDoesNotEnableConfirmation() async throws {
        let access = ClubGovernanceFixtureAccess(); access.allowsOfflineWrites = false
        let coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(ClubGovernanceFixtures.command(.saveCustomer))
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testSameAccountNewEpochInvalidatesReview() async throws {
        let access = ClubGovernanceFixtureAccess()
        let real = ClubGovernanceCoordinator(access: access)
        let review = try await real.prepare(ClubGovernanceFixtures.command(.saveCustomer))
        access.identity = .init(accountID: 701, epoch: 2)
        do { _ = try await real.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testAccountSwitchWhilePreparingRejectsLateResult() async throws {
        let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(.saveCustomer)
        let coordinator = ClubGovernanceCoordinator(access: access)
        access.onRead = { access.identity = .init(accountID: 799, epoch: 2) }
        do { _ = try await coordinator.prepare(command); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testChangedTargetBaselineInvalidatesConfirmation() async throws {
        let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(.saveCustomer)
        let coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command)
        var changed = ClubGovernanceFixtures.value(.customer).object!; changed["remark"] = .string("Changed elsewhere"); access.overrideValue[.customer] = .object(changed)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testRevokedPermissionsRejectBeforeDispatch() async throws {
        let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(.saveCustomer)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
        var changed = ClubGovernanceFixtures.permissions.object!; changed["permissions"] = .array([]); changed["eventAccesses"] = .array([]); access.permissionValue = .object(changed)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden) }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testClosingReviewInvalidatesIt() async throws {
        let access = ClubGovernanceFixtureAccess()
        let real = ClubGovernanceCoordinator(access: access), review = try await real.prepare(ClubGovernanceFixtures.command(.saveCustomer))
        real.cancelReview()
        do { _ = try await real.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testUnknownOutcomeLocksAcrossSameAccountRelogin() async throws {
        let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(.saveCustomer)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
        access.writeFailure = .unknown(message: "Unconfirmed")
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(coordinator.state, .unknown); XCTAssertEqual(access.sent.count, 1)
        access.identity = nil; coordinator.cancelReview(); access.identity = .init(accountID: 701, epoch: 7)
        do { _ = try await coordinator.prepare(command); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .outcomeLocked) }
        XCTAssertEqual(access.sent.count, 1)
    }
    func testUnknownAccountDoesNotLockOtherAccount() async throws {
        let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(.saveCustomer)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
        access.writeFailure = .unknown(message: nil)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertFalse(coordinator.isLocked(command, identity: .init(accountID: 799, epoch: 1)))
    }
    func testSwitchAfterSendNeverShowsOldAccountAcknowledgment() async throws {
        let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(.saveCustomer)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
        access.onSend = { access.identity = .init(accountID: 799, epoch: 2) }
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .unknown(message: nil)) }
        XCTAssertEqual(coordinator.state, .unknown); XCTAssertTrue(coordinator.isLocked(command, identity: review.identity))
    }
    func testExplicitConflictUnlocksButRequiresNewReview() async throws {
        let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(.saveCustomer)
        let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
        access.writeFailure = .conflict(message: "Version changed")
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(coordinator.state, .conflict); XCTAssertFalse(coordinator.isLocked(command, identity: review.identity))
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
    }
    func testOwnerAndSelfCannotBeGovernanceTargets() async throws {
        let access = ClubGovernanceFixtureAccess()
        let coordinator = ClubGovernanceCoordinator(access: access)
        for target in [701, 999] {
            let command = try ClubGovernanceCommand(operation: .ban, scope: ClubGovernanceFixtures.scope, values: ["targetMemberId": .integer(target), "reason": .string("Fixture"), "expiresAt": .string("2026-10-08 09:00:00"), "requestId": .string("fixed")])
            do { _ = try await coordinator.prepare(command); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden) }
        }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testLeadMustBeCurrentMember() async throws {
        let access = ClubGovernanceFixtureAccess()
        let coordinator = ClubGovernanceCoordinator(access: access)
        var draft = ClubGovernanceFormDraft(operation: .createSeries, scope: ClubGovernanceFixtures.scope)
        draft.text["startDate"] = "2026-10-08"; draft.text["defaultLeadMemberId"] = "999"
        do { _ = try await coordinator.prepare(draft.command()); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .targetChanged) }
        XCTAssertTrue(access.sent.isEmpty)
    }
}

@MainActor final class ClubGovernanceRealmTests: XCTestCase {
    func testRealmChangeInvalidatesReviewEvenWithSameAccountEpoch() async throws {
        let access = ClubGovernanceFixtureAccess(), command = try ClubGovernanceFixtures.command(.saveCustomer)
        let coordinator = ClubGovernanceCoordinator(access: access)
        let review = try await coordinator.prepare(command)
        access.storageNamespace = "other-realm"
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? ClubGovernanceFailure, .staleReview) }
        XCTAssertTrue(access.sent.isEmpty)
    }
    func testChangingDraftCreatesDifferentImmutableRequest() throws {
        var draft = ClubGovernanceFormDraft(operation: .saveCustomer, scope: ClubGovernanceFixtures.scope)
        let before = try draft.command(); draft.text["remark"] = "Changed"
        let after = try draft.command()
        XCTAssertNotEqual(before, after)
        XCTAssertNotEqual(before.fields["requestId"], after.fields["requestId"])
        XCTAssertEqual(after, try draft.command())
    }
}
