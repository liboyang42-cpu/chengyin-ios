import XCTest
@testable import Questify

@MainActor final class ClubNotificationAudienceTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 901, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-notification-audience"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var resources: [ClubGovernanceRead] = []
        var permissions: [String] = ["club:notify:send", "club:event:operate"]
        var counts: ClubGovernanceValue = .object([
            "ALL_MEMBERS": .integer(9), "ADMINS": .integer(2), "REGISTERED": .integer(6),
            "WAITLIST": .null, "NO_SHOW": .integer(0), "INACTIVE": .integer(1)])
        var failedOperation: ClubGovernanceRead?
        var failure: ClubGovernanceFailure = .malformed
        var heldOperation: ClubGovernanceRead?
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        var responseScope: ClubGovernanceScope?
        var responseOperation: ClubGovernanceRead?
        var missingPermissions = false
        var countsPermissions: [String]?
        func response(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope) throws -> ClubGovernanceSnapshot {
            let selected = operation == .audienceCounts ? countsPermissions ?? permissions : permissions
            let proof = try ClubGovernancePermissions(value: .object([
                "active": .bool(true), "club": .object(["id": .integer(scope.clubID ?? 81)]),
                "roleCodes": .array([]), "permissions": .array(selected.map(ClubGovernanceValue.string))]), scope: scope)
            return .init(operation: responseOperation ?? operation, scope: responseScope ?? scope,
                         permissions: missingPermissions ? nil : proof,
                         value: .object(["counts": counts]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation); XCTAssertTrue(options.isEmpty)
            if operation == failedOperation { throw failure }
            if operation == heldOperation { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
            return try response(operation, scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            XCTFail("Audience selection must not send"); throw ClubGovernanceFailure.notConfigured
        }
    }
    private let club = ClubGovernanceScope(clubID: 81)
    private let event = ClubGovernanceScope(clubID: 81, activityID: 92)
    private func context(_ access: Access, scope: ClubGovernanceScope? = nil) -> ClubNotificationAudienceReadModel.Context {
        ClubNotificationAudienceReadModel.context(scope: scope ?? event, identity: access.identity, access: access)
    }
    private func activate(_ model: ClubNotificationAudienceReadModel, _ expected: ClubNotificationAudienceReadModel.Context) throws -> ClubNotificationAudienceReadModel.Permit {
        model.bind(expected); return try XCTUnwrap(model.activate(expected))
    }
    private func loaded(_ access: Access, scope: ClubGovernanceScope? = nil) async throws -> (ClubNotificationAudienceReadModel, ClubNotificationAudienceReadModel.Permit) {
        let model = ClubNotificationAudienceReadModel(), expected = context(access, scope: scope)
        let permit = try activate(model, expected)
        await model.load(permit, access: access, isCurrent: { true })
        return (model, permit)
    }
    func testSixFiniteGroupsReadAccessBeforeCountsWithoutSending() async throws {
        let access = Access(), (model, permit) = try await loaded(access)
        let options = try XCTUnwrap(model.accepted(permit.context, access: access))
        XCTAssertEqual(options.map(\.id), ["ALL_MEMBERS", "ADMINS", "REGISTERED", "WAITLIST", "NO_SHOW", "INACTIVE"])
        XCTAssertEqual(access.resources, [.access, .audienceCounts]); XCTAssertTrue(options.allSatisfy(\.enabled))
    }
    func testClubScopeShowsThreeEventGroupsDisabledWithUnknownCounts() async throws {
        let access = Access(), (model, permit) = try await loaded(access, scope: club)
        let options = try XCTUnwrap(model.accepted(permit.context, access: access))
        XCTAssertEqual(options.filter(\.enabled).map(\.id), ["ALL_MEMBERS", "ADMINS", "INACTIVE"])
        for row in options where ["REGISTERED", "WAITLIST", "NO_SHOW"].contains(row.id) {
            XCTAssertTrue(row.needsActivity); XCTAssertNil(row.count)
            XCTAssertFalse(model.canSelect(row.id, snapshotID: model.snapshotID, permit: permit, access: access))
        }
    }
    func testEventOnlyPermissionCannotSelectClubWideAudiences() async throws {
        let access = Access(); access.permissions = ["club:event:operate"]
        let (model, permit) = try await loaded(access)
        XCTAssertEqual(model.options?.filter(\.enabled).map(\.id), ["REGISTERED", "WAITLIST", "NO_SHOW"])
        XCTAssertFalse(model.canPrepare("ALL_MEMBERS", context: permit.context, access: access))
        XCTAssertTrue(model.canPrepare("REGISTERED", context: permit.context, access: access))
    }
    func testClubOnlyPermissionCannotSelectEventAudiencesEvenWithAnEvent() async throws {
        let access = Access(); access.permissions = ["club:notify:send"]
        let (model, permit) = try await loaded(access)
        XCTAssertEqual(model.options?.filter(\.enabled).map(\.id), ["ALL_MEMBERS", "ADMINS", "INACTIVE"])
        XCTAssertFalse(model.canPrepare("REGISTERED", context: permit.context, access: access))
    }
    func testDeniedAuthorityNeverRequestsCounts() async throws {
        let access = Access(); access.permissions = []
        let (model, _) = try await loaded(access)
        XCTAssertEqual(access.resources, [.access]); XCTAssertEqual(model.failure, .forbidden); XCTAssertNil(model.options)
    }
    func testZeroIsDistinctFromNullMissingAndInvalidCounts() async throws {
        let access = Access(); access.counts = .object(["ALL_MEMBERS": .integer(0), "ADMINS": .null,
            "REGISTERED": .string("4"), "WAITLIST": .integer(-1), "NO_SHOW": .decimal(2.5)])
        let (model, _) = try await loaded(access)
        XCTAssertEqual(model.options?.first(where: { $0.id == "ALL_MEMBERS" })?.count, 0)
        XCTAssertTrue(model.options?.filter { $0.id != "ALL_MEMBERS" }.allSatisfy { $0.count == nil } == true)
    }
    func testUnknownAudienceIsNotAddedFromResponseAndCannotBeSelected() async throws {
        let access = Access(); access.counts = .object(["PERSON_IDS": .integer(6)])
        let (model, permit) = try await loaded(access)
        XCTAssertEqual(model.options?.count, 6)
        XCTAssertFalse(model.canSelect("PERSON_IDS", snapshotID: model.snapshotID, permit: permit, access: access))
    }
    func testOptionalCountFailureRetainsAuthorizedChoicesWithUnknownCounts() async throws {
        let access = Access(); access.failedOperation = .audienceCounts
        let (model, permit) = try await loaded(access)
        XCTAssertTrue(model.countsUnavailable); XCTAssertNil(model.failure)
        XCTAssertTrue(model.options?.allSatisfy { $0.count == nil } == true)
        XCTAssertTrue(model.canPrepare("ALL_MEMBERS", context: permit.context, access: access))
    }
    func testCountsPermissionRevocationDoesNotKeepEarlierChoices() async throws {
        let access = Access(); access.countsPermissions = []
        let (model, _) = try await loaded(access)
        XCTAssertNil(model.options); XCTAssertEqual(model.failure, .forbidden)
    }
    func testCountsForbiddenDoesNotFallBackToEarlierAuthority() async throws {
        let access = Access(); access.failedOperation = .audienceCounts; access.failure = .forbidden
        let (model, _) = try await loaded(access)
        XCTAssertNil(model.options); XCTAssertFalse(model.countsUnavailable); XCTAssertEqual(model.failure, .forbidden)
    }
    func testCountsScopeMismatchCannotPublishOrFallBack() async throws {
        let access = Access(), model = ClubNotificationAudienceReadModel(), expected = context(access)
        let permit = try activate(model, expected); access.heldOperation = .audienceCounts
        let entered = expectation(description: "counts"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, access: access, isCurrent: { true }) }
        await fulfillment(of: [entered], timeout: 1)
        access.responseScope = .init(clubID: 81, activityID: 93)
        access.pending[0].resume(returning: try access.response(.audienceCounts, scope: event)); await task.value
        XCTAssertNil(model.options); XCTAssertEqual(model.failure, .targetChanged)
    }
    func testAuthorityWrongResourceOrMissingProofStopsBeforeCounts() async throws {
        for missing in [false, true] {
            let access = Access(); access.missingPermissions = missing
            if !missing { access.responseOperation = .members }
            let (model, _) = try await loaded(access)
            XCTAssertEqual(access.resources, [.access]); XCTAssertNil(model.options); XCTAssertEqual(model.failure, .targetChanged)
        }
    }
    func testSignedOutOrUnconfiguredNeverReads() async throws {
        for signedOut in [false, true] {
            let access = Access(); if signedOut { access.identity = nil } else { access.isConfigured = false }
            let (model, _) = try await loaded(access)
            XCTAssertTrue(access.resources.isEmpty); XCTAssertNil(model.options)
            XCTAssertEqual(model.failure, signedOut ? .signedOut : .notConfigured)
        }
    }
    func testLocalChoiceKeepsContentAndUsesExistingRequestIdentityInvalidation() async throws {
        let access = Access(), (model, permit) = try await loaded(access)
        var form = ClubGovernanceFormDraft(operation: .sendNotification, scope: event)
        form.text["title"] = "Synthetic title"; form.text["content"] = "Synthetic content"
        let old = form.requestID
        XCTAssertTrue(model.canSelect("WAITLIST", snapshotID: model.snapshotID, permit: permit, access: access))
        form.text["audienceType"] = "WAITLIST"
        XCTAssertNotEqual(form.requestID, old)
        XCTAssertEqual(form.text["title"], "Synthetic title"); XCTAssertEqual(form.text["content"], "Synthetic content")
        XCTAssertEqual(try form.command().fields["audienceType"], .string("WAITLIST"))
        XCTAssertEqual(access.resources, [.access, .audienceCounts])
    }
    func testRefreshHidesPreviousCountsAndRejectsPreviousRow() async throws {
        let access = Access(), (model, permit) = try await loaded(access), oldID = model.snapshotID
        access.heldOperation = .access
        let entered = expectation(description: "refresh"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, access: access, isCurrent: { true }) }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertNil(model.accepted(permit.context, access: access)); XCTAssertNil(model.options)
        XCTAssertFalse(model.canSelect("ALL_MEMBERS", snapshotID: oldID, permit: permit, access: access))
        access.pending[0].resume(returning: try access.response(.access, scope: event)); await task.value
        XCTAssertFalse(model.canSelect("ALL_MEMBERS", snapshotID: oldID, permit: permit, access: access))
    }
    func testIdentityChangeDuringAuthorityCannotStartCounts() async throws {
        let access = Access(), model = ClubNotificationAudienceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.heldOperation = .access; let entered = expectation(description: "authority"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, access: access, isCurrent: { true }) }
        await fulfillment(of: [entered], timeout: 1); access.identity = .init(accountID: 902, epoch: 2)
        access.pending[0].resume(returning: try access.response(.access, scope: event)); await task.value
        XCTAssertEqual(access.resources, [.access]); XCTAssertNil(model.accepted(expected, access: access)); XCTAssertNil(model.options)
    }
    func testHiddenOwnerDuringAuthorityCannotStartCountsWithoutLeave() async throws {
        let access = Access(), model = ClubNotificationAudienceReadModel(), expected = context(access), permit = try activate(model, expected)
        var visible = true; access.heldOperation = .access
        let entered = expectation(description: "authority"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, access: access, isCurrent: { visible }) }
        await fulfillment(of: [entered], timeout: 1); visible = false
        access.pending[0].resume(returning: try access.response(.access, scope: event)); await task.value
        XCTAssertEqual(access.resources, [.access]); XCTAssertNil(model.options)
    }
    func testInactiveOwnerDuringCountsCannotPublishWithoutLeave() async throws {
        let access = Access(), model = ClubNotificationAudienceReadModel(), expected = context(access), permit = try activate(model, expected)
        var active = true; access.heldOperation = .audienceCounts
        let entered = expectation(description: "counts"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, access: access, isCurrent: { active }) }
        await fulfillment(of: [entered], timeout: 1); active = false
        access.pending[0].resume(returning: try access.response(.audienceCounts, scope: event)); await task.value
        XCTAssertNil(model.options); XCTAssertNil(model.accepted(expected, access: access))
    }
    func testLeaveAndReopenRejectOldPermitAndQueuedRetry() async throws {
        let access = Access(), (model, old) = try await loaded(access)
        model.leave(old.context); _ = model.activate(old.context)
        let reads = access.resources.count
        await model.load(old, access: access, isCurrent: { true })
        XCTAssertEqual(access.resources.count, reads); XCTAssertNil(model.options)
    }
    func testAuthorizationNamespaceReaderAndScopeChangesInvalidateChoices() async throws {
        let access = Access(), (model, permit) = try await loaded(access), stamp = model.snapshotID
        access.storageNamespace = "changed"
        XCTAssertFalse(model.canSelect("ALL_MEMBERS", snapshotID: stamp, permit: permit, access: access))
        access.storageNamespace = permit.context.namespace; access.authorizationGeneration = UUID()
        XCTAssertNil(model.accepted(permit.context, access: access))
        let other = Access(); other.authorizationGeneration = permit.context.read.authorizationGeneration
        XCTAssertNil(model.accepted(permit.context, access: other))
        let next = context(access, scope: club); model.bind(next)
        XCTAssertNil(model.accepted(permit.context, access: access))
    }
    func testOlderCountResponseCannotReplaceNewerCounts() async throws {
        let access = Access(), model = ClubNotificationAudienceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.heldOperation = .audienceCounts
        let first = expectation(description: "first"), second = expectation(description: "second")
        access.entered = { access.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await model.load(permit, access: access, isCurrent: { true }) }
        await fulfillment(of: [first], timeout: 1)
        let new = Task { await model.load(permit, access: access, isCurrent: { true }) }
        await fulfillment(of: [second], timeout: 1)
        access.counts = .object(["ALL_MEMBERS": .integer(12)])
        access.pending[1].resume(returning: try access.response(.audienceCounts, scope: event)); await new.value
        access.counts = .object(["ALL_MEMBERS": .integer(3)])
        access.pending[0].resume(returning: try access.response(.audienceCounts, scope: event)); await old.value
        XCTAssertEqual(model.options?.first?.count, 12)
    }
    func testCancelledAuthorityCannotStartCounts() async throws {
        let access = Access(), model = ClubNotificationAudienceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.heldOperation = .access; let entered = expectation(description: "authority"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, access: access, isCurrent: { true }) }
        await fulfillment(of: [entered], timeout: 1); task.cancel()
        access.pending[0].resume(returning: try access.response(.access, scope: event)); await task.value
        XCTAssertEqual(access.resources, [.access]); XCTAssertNil(model.options)
    }
    func testCountFailureRetryRecoversFreshCountsWithoutSelectingOrSending() async throws {
        let access = Access(); access.failedOperation = .audienceCounts
        let (model, permit) = try await loaded(access)
        XCTAssertTrue(model.countsUnavailable)
        access.failedOperation = nil
        await model.load(permit, access: access, isCurrent: { true })
        XCTAssertFalse(model.countsUnavailable); XCTAssertEqual(model.options?.first?.count, 9)
        XCTAssertEqual(access.resources, [.access, .audienceCounts, .access, .audienceCounts])
    }
}
