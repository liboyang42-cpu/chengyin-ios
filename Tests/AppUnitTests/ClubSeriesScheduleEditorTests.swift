import XCTest
@testable import Questify

@MainActor final class ClubSeriesScheduleEditorTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-schedule"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var resources: [ClubGovernanceRead] = []
        var sends = 0
        var allowed = true
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation)
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
            let value: ClubGovernanceValue
            switch operation {
            case .eventTopics: value = .array([.object(["id": .integer(91)])])
            case .seriesDetail: value = .object(["version": .integer(7), "topicId": .integer(91)])
            case .members: value = .array([.object(["memberId": .integer(41)])])
            default: throw ClubGovernanceFailure.invalidRequest
            }
            return .init(operation: operation, scope: scope, permissions: permission, value: value)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private let now = ISO8601DateFormatter().date(from: "2026-10-11T01:00:00Z")!
    private func form(_ operation: ClubGovernanceMutation = .createSeries, club: Int = 81) -> ClubGovernanceFormDraft {
        .init(operation: operation, scope: .init(clubID: club, topicID: 91, seriesID: operation == .updateSeries ? 101 : nil),
              seed: ["defaultLeadMemberId": .integer(41), "version": .integer(7), "futureDates": .array([.string("2026-10-12")])])
    }
    private func session(_ form: ClubGovernanceFormDraft, _ access: Access) throws -> ClubSeriesScheduleSession {
        try XCTUnwrap(.init(form: form, identity: access.identity, access: access, now: now))
    }
    func testOrdinaryConfiguredReaderCreatesSessionWithoutReadOrWrite() throws {
        let access = Access(), draft = form(), value = try session(form(), access)
        XCTAssertEqual(value.operation, .createSeries); XCTAssertEqual(value.context.scope, draft.scope)
        XCTAssertEqual(value.context.accessIdentity, ObjectIdentifier(access)); XCTAssertEqual(access.resources, []); XCTAssertEqual(access.sends, 0)
    }
    func testSignedOutUnconfiguredAndWrongIdentityCannotOpen() {
        let access = Access(), draft = form()
        XCTAssertNil(ClubSeriesScheduleSession(form: draft, identity: nil, access: access, now: now))
        XCTAssertNil(ClubSeriesScheduleSession(form: draft, identity: .init(accountID: 702, epoch: 1), access: access, now: now))
        access.isConfigured = false; XCTAssertNil(ClubSeriesScheduleSession(form: draft, identity: access.identity, access: access, now: now))
    }
    func testCancelAndReopenRejectOldSheetEvenForSameDraft() throws {
        let access = Access(), draft = form(), old = try session(draft, access), next = try session(draft, access)
        XCTAssertTrue(old.isCurrent(activeID: old.id, form: draft, identity: access.identity, access: access))
        XCTAssertFalse(old.isCurrent(activeID: nil, form: draft, identity: access.identity, access: access))
        XCTAssertFalse(old.isCurrent(activeID: next.id, form: draft, identity: access.identity, access: access))
    }
    func testIdentityEpochAndAuthorizationReplacementRejectDelayedApply() throws {
        let access = Access(), draft = form(), value = try session(draft, access), original = access.identity
        access.identity = .init(accountID: 701, epoch: 2)
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: original, access: access))
        access.identity = original; access.authorizationGeneration = UUID()
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: original, access: access))
    }
    func testChangedReaderNamespaceAndTargetRejectApply() throws {
        let access = Access(), draft = form(), value = try session(draft, access), other = Access()
        other.authorizationGeneration = access.authorizationGeneration
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: other.identity, access: other))
        access.storageNamespace = "another-scope"
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: access.identity, access: access))
        access.storageNamespace = value.namespace
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: form(club: 82), identity: access.identity, access: access))
    }
    func testParentDraftEditInvalidatesSheetBeforeItCanOverwritePolicy() throws {
        let access = Access(); var draft = form(); let value = try session(draft, access)
        draft.text["capacity"] = "20"
        XCTAssertFalse(value.isCurrent(activeID: value.id, form: draft, identity: access.identity, access: access))
    }
    func testAppliedCreateAndUpdateCanUseExistingReviewAndCancelWithoutDispatch() async throws {
        for operation in [ClubGovernanceMutation.createSeries, .updateSeries] {
            let access = Access(), draft = form(operation), value = try session(draft, access)
            var schedule = value.initial; schedule.startDate = "2026-10-12"; schedule.recurrence = "WEEKLY"; schedule.occurrenceCount = 2
            let command = try schedule.applying(to: draft, now: now).command()
            let coordinator = ClubGovernanceCoordinator(access: access), review = try await coordinator.prepare(command)
            XCTAssertEqual(review.command.fields["startDate"], .string("2026-10-12"))
            XCTAssertEqual(review.command.fields["occurrenceCount"], .integer(2))
            XCTAssertEqual(access.resources, [operation.reviewRead, .members]); XCTAssertFalse(access.canDispatch(command))
            coordinator.cancelReview(); XCTAssertEqual(access.sends, 0)
        }
    }
    func testExistingPermissionPreflightStillRejectsAndNeverReadsMembersOrSends() async throws {
        let access = Access(), draft = form(), value = try session(draft, access); access.allowed = false
        var schedule = value.initial; schedule.startDate = "2026-10-12"
        let coordinator = ClubGovernanceCoordinator(access: access)
        do { _ = try await coordinator.prepare(schedule.applying(to: draft, now: now).command()); XCTFail("Expected forbidden") }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden) }
        XCTAssertEqual(access.resources, [.eventTopics]); XCTAssertEqual(access.sends, 0)
    }
}
