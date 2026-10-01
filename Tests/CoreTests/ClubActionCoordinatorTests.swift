import XCTest
@testable import QuestifyCore

@MainActor
final class ClubActionCoordinatorTests: XCTestCase {
    private func fixture() -> (ClubActionCoordinator, ClubActionFakeStore) {
        let store = ClubActionFakeStore()
        return (ClubActionCoordinator(writer: store, reader: store), store)
    }
    private func prepare(_ coordinator: ClubActionCoordinator, _ store: ClubActionFakeStore, action: ClubAction = .join, id: Int = 7) async throws -> ClubActionConfirmation {
        try await coordinator.prepare(clubID: id, action: action, expectedIdentity: store.clubIdentity)
    }
    func testPermissionMatrixNeverPromotesAdministratorOrOwner() throws {
        let cases: [([String: Any], Bool, ClubActionAvailability)] = [
            ([:], false, .available(.join)), (["joinPolicy": 1], false, .available(.apply)),
            (["myJoinStatus": 2, "joinPolicy": 1], false, .available(.apply)),
            (["myJoinStatus": 0], false, .pending), (["myJoinStatus": 9], false, .unsupportedStatus),
            (["isJoined": true], false, .available(.leave)), (["isJoined": true], true, .available(.leave)),
            (["isOwner": true, "isJoined": true], false, .owner), (["isOwner": true], true, .owner),
            ([:], true, .merchant), (["viewerIsAdmin": true], false, .available(.join)),
            (["viewerIsAdmin": true, "isJoined": true], false, .available(.leave))
        ]
        for (fields, merchant, expected) in cases {
            XCTAssertEqual(ClubActionAvailability.resolve(try clubActionFixture(fields), viewerIsMerchant: merchant), expected)
        }
    }
    func testPrepareAlwaysReadsAndCancelNeverWrites() async throws {
        let (c, s) = fixture()
        let intent = try await prepare(c, s)
        XCTAssertEqual(s.readIDs, [7]); XCTAssertEqual(c.state(clubID: 7), .awaitingConfirmation)
        XCTAssertEqual(intent.clubID, 7); XCTAssertEqual(intent.clubName, "Fixture club")
        XCTAssertTrue(s.writes.isEmpty)
        c.cancel(intent)
        XCTAssertEqual(c.state(clubID: 7), .idle)
        let result = await c.confirm(intent)
        XCTAssertEqual(result, .blocked(.staleConfirmation)); XCTAssertTrue(s.writes.isEmpty)
    }
    func testMissingConfigGuestBadIdentityAndInvalidClubDoNotRead() async throws {
        let (c, s) = fixture()
        s.isConfigured = false
        do { _ = try await prepare(c, s); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .unavailable) }
        s.isConfigured = true; s.identity = nil
        do { _ = try await prepare(c, s); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .signedOut) }
        s.identity = s.clubIdentity
        do { _ = try await c.prepare(clubID: 7, action: .join, expectedIdentity: .init(accountID: 2, epoch: 1)); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionBlock, .accountChanged) }
        do { _ = try await prepare(c, s, id: 0); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .invalidClub) }
        XCTAssertTrue(s.readIDs.isEmpty); XCTAssertTrue(s.writes.isEmpty)
    }
    func testChangedDetailCannotConvertJoinIntoLeaveOrApply() async throws {
        let values: [[String: Any]] = [["isJoined": true], ["isOwner": true], ["joinPolicy": 1], ["myJoinStatus": 0]]
        for fields in values {
            let (c, s) = fixture(); s.detail = try clubActionFixture(fields)
            do { _ = try await prepare(c, s); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .eligibilityChanged) }
            XCTAssertTrue(s.writes.isEmpty); XCTAssertEqual(c.state(clubID: 7), .idle)
        }
    }
    func testPrepareRejectsWrongClubAndLeavesOtherClubUnchanged() async throws {
        let (c, s) = fixture(); s.detail = try clubActionFixture(["id": 8])
        do { _ = try await prepare(c, s); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .invalidClub) }
        XCTAssertEqual(c.state(clubID: 7), .idle); XCTAssertEqual(c.state(clubID: 8), .idle)
    }
    func testSuccessfulReceiptAlwaysReadsBackWithoutOptimisticMembership() async throws {
        let (c, s) = fixture()
        s.receipt = ClubActionReceipt(state: "joined", message: nil)
        let intent = try await prepare(c, s)
        _ = await c.confirm(intent)
        XCTAssertEqual(c.state(clubID: 7), .acknowledged(s.receipt))
        XCTAssertEqual(s.readIDs, [7, 7]); XCTAssertEqual(s.writes, [.join])
        guard case .received(let detail) = c.readback(clubID: 7) else { return XCTFail() }
        XCTAssertFalse(detail.isJoined, "Even state=joined must not override fresh detail")
    }
    func testApplicationRemainsPendingAndDoesNotGrantMembers() async throws {
        let (c, s) = fixture(); s.detail = try clubActionFixture(["joinPolicy": 1])
        s.writeOperation = { _ in
            s.detail = try clubActionFixture(["joinPolicy": 1, "myJoinStatus": 0])
            return ClubActionReceipt(state: "pending", message: nil)
        }
        let intent = try await prepare(c, s, action: .apply)
        _ = await c.confirm(intent)
        guard case .received(let detail) = c.readback(clubID: 7) else { return XCTFail() }
        XCTAssertTrue(detail.joinPending); XCTAssertFalse(detail.isJoined); XCTAssertFalse(detail.canSeeMembers)
        XCTAssertEqual(s.writes, [.apply])
    }
    func testJoinedAndLeaveUseFreshServerMembershipCount() async throws {
        for action in [ClubAction.join, .leave] {
            let (c, s) = fixture(); s.detail = try clubActionFixture(["isJoined": action == .leave, "memberCount": 8])
            s.writeOperation = { _ in
                s.detail = try clubActionFixture(["isJoined": action == .join, "memberCount": action == .join ? 12 : 6])
                return ClubActionReceipt(state: nil, message: nil)
            }
            let intent = try await prepare(c, s, action: action)
            _ = await c.confirm(intent)
            XCTAssertEqual(c.readback(clubID: 7), .received(s.detail))
            XCTAssertEqual(s.readIDs, [7, 7]); XCTAssertEqual(s.writes, [action])
        }
    }
    func testRepeatedConfirmAndConcurrentPrepareCannotDuplicateWrite() async throws {
        let (c, s) = fixture()
        var resume: CheckedContinuation<ClubActionReceipt, Error>?
        s.writeOperation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let intent = try await prepare(c, s)
        let task = Task { await c.confirm(intent) }
        while resume == nil { await Task.yield() }
        let duplicate = await c.confirm(intent)
        XCTAssertEqual(duplicate, .blocked(.staleConfirmation))
        do { _ = try await prepare(c, s); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .pendingOperation) }
        resume?.resume(returning: s.receipt); _ = await task.value
        let repeated = await c.confirm(intent)
        XCTAssertEqual(repeated, .blocked(.staleConfirmation)); XCTAssertEqual(s.writes.count, 1)
    }
    func testRepeatedPrepareWhileReadSuspendedIsBlocked() async throws {
        let (c, s) = fixture()
        var resume: CheckedContinuation<ClubRecord, Error>?
        s.readOperation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let task = Task { try await self.prepare(c, s) }
        while resume == nil { await Task.yield() }
        do { _ = try await prepare(c, s); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .pendingOperation) }
        resume?.resume(returning: s.detail)
        let intent = try await task.value; c.cancel(intent)
        XCTAssertEqual(s.readIDs, [7]); XCTAssertTrue(s.writes.isEmpty)
    }
    func testUnknownOutcomeDoesNotAutoReadRetryOrUnlockAfterReadback() async throws {
        let (c, s) = fixture()
        s.writeOperation = { _ in throw ClubActionWriteError.outcomeUnknown(.transport) }
        let intent = try await prepare(c, s); _ = await c.confirm(intent)
        XCTAssertEqual(s.readIDs, [7]); XCTAssertEqual(c.state(clubID: 7), .outcomeUnknown(.transport))
        s.detail = try clubActionFixture(["isJoined": true])
        let result = await c.readBack(clubID: 7)
        XCTAssertEqual(result, .applied); XCTAssertEqual(c.readback(clubID: 7), .received(s.detail))
        XCTAssertEqual(c.state(clubID: 7), .outcomeUnknown(.transport))
        do { _ = try await prepare(c, s, action: .leave); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .pendingOperation) }
        XCTAssertEqual(s.writes.count, 1); XCTAssertEqual(s.readIDs, [7, 7])
    }
    func testReadbackFailureNeverClaimsMembershipOrRetriesWrite() async throws {
        let (c, s) = fixture()
        let intent = try await prepare(c, s)
        s.readOperation = { _ in throw APIError.malformedResponse }
        _ = await c.confirm(intent)
        XCTAssertEqual(c.readback(clubID: 7), .unavailable)
        XCTAssertEqual(s.writes.count, 1)
        s.readOperation = nil
        _ = await c.readBack(clubID: 7)
        XCTAssertEqual(c.readback(clubID: 7), .received(s.detail)); XCTAssertEqual(s.writes.count, 1)
    }
    func testExplicitRejectionAndNotSentNeverRetryAutomatically() async throws {
        let failures: [ClubActionWriteError] = [.rejected(.init(code: 409, message: "Source denial")), .notSent(.invalidRequest), .eligibilityChanged, .preflightFailed]
        for failure in failures {
            let (c, s) = fixture(); s.writeOperation = { _ in throw failure }
            let intent = try await prepare(c, s); _ = await c.confirm(intent)
            XCTAssertFalse(c.state(clubID: 7).preventsNewAction)
            XCTAssertEqual(s.writes.count, 1); XCTAssertEqual(s.readIDs, [7])
            let replacement = try await prepare(c, s)
            XCTAssertNotEqual(replacement.id, intent.id); XCTAssertEqual(s.writes.count, 1)
        }
    }
    func testEpochChangeBeforeConfirmationCannotSend() async throws {
        let (c, s) = fixture(); let intent = try await prepare(c, s)
        s.changeIdentity(accountID: 1, epoch: 2)
        let result = await c.confirm(intent)
        XCTAssertEqual(result, .blocked(.accountChanged)); XCTAssertTrue(s.writes.isEmpty)
    }
    func testAccountChangeDuringPreparationDiscardsConfirmation() async throws {
        let (c, s) = fixture()
        s.readOperation = { _ in s.changeIdentity(accountID: 2, epoch: 2); return s.detail }
        do { _ = try await prepare(c, s); XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .accountChanged) }
        XCTAssertEqual(c.state(clubID: 7), .idle); XCTAssertTrue(s.writes.isEmpty)
    }
    func testAccountChangeDuringWriteHidesOldReceiptAndRetainsOriginalAccountLock() async throws {
        let (c, s) = fixture()
        s.writeOperation = { _ in s.changeIdentity(accountID: 2, epoch: 2); return ClubActionReceipt(state: "joined", message: "Old account message") }
        let intent = try await prepare(c, s)
        let result = await c.confirm(intent)
        XCTAssertEqual(result, .ignoredStale); XCTAssertEqual(c.state(clubID: 7), .idle); XCTAssertEqual(c.readback(clubID: 7), .idle)
        s.changeIdentity(accountID: 1, epoch: 3)
        XCTAssertEqual(c.state(clubID: 7), .outcomeUnknown(.accountChanged))
        XCTAssertEqual(s.readIDs, [7]); XCTAssertEqual(s.writes.count, 1)
    }
    func testAccountChangeWithDefiniteNoSendDoesNotLockOriginalClub() async throws {
        let (c, s) = fixture()
        s.writeOperation = { _ in
            s.changeIdentity(accountID: 2, epoch: 2)
            c.synchronizeSession()
            throw ClubActionWriteError.notSent(.unauthorized)
        }
        let intent = try await prepare(c, s)
        let result = await c.confirm(intent)
        XCTAssertEqual(result, .ignoredStale)
        s.changeIdentity(accountID: 1, epoch: 3)
        XCTAssertEqual(c.state(clubID: 7), .idle)
    }
    func testCurrentSessionExpiryAfterDefiniteRejectionDoesNotLockOriginalClub() async throws {
        let (c, s) = fixture()
        s.writeOperation = { _ in
            s.identity = nil; s.clubIdentity = .init(accountID: nil, epoch: 2)
            c.synchronizeSession() // Matches AppSession's expiry callback.
            throw ClubActionWriteError.rejected(.init(code: 401, message: "Expired"))
        }
        let intent = try await prepare(c, s)
        _ = await c.confirm(intent)
        s.changeIdentity(accountID: 1, epoch: 3)
        XCTAssertEqual(c.state(clubID: 7), .idle)
    }
    func testUnknownLockSurvivesDismissalAndReloginButNotOtherClubOrAccount() async throws {
        let (c, s) = fixture(); s.writeOperation = { _ in throw ClubActionWriteError.outcomeUnknown(.transport) }
        let intent = try await prepare(c, s); _ = await c.confirm(intent)
        c.leaveScreen(clubID: 7, expectedIdentity: s.clubIdentity)
        XCTAssertEqual(c.state(clubID: 8), .idle)
        s.changeIdentity(accountID: 2, epoch: 2); XCTAssertEqual(c.state(clubID: 7), .idle)
        s.changeIdentity(accountID: 1, epoch: 3)
        XCTAssertEqual(c.state(clubID: 7), .outcomeUnknown(.accountChanged))
        XCTAssertEqual(c.readback(clubID: 7), .idle)
    }
    func testDismissedPreparationCannotReviveAndSend() async throws {
        let (c, s) = fixture()
        var resume: CheckedContinuation<ClubRecord, Error>?
        s.readOperation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let task = Task { try await self.prepare(c, s) }
        while resume == nil { await Task.yield() }
        c.leaveScreen(clubID: 7, expectedIdentity: s.clubIdentity)
        resume?.resume(returning: s.detail)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertEqual(error as? ClubActionBlock, .cancelledBeforeDispatch) }
        XCTAssertTrue(s.writes.isEmpty); XCTAssertEqual(c.state(clubID: 7), .idle)
    }
    func testDismissedDispatchIgnoresLateSuccessAndRemainsLocked() async throws {
        let (c, s) = fixture()
        var resume: CheckedContinuation<ClubActionReceipt, Error>?
        s.writeOperation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let intent = try await prepare(c, s)
        let task = Task { await c.confirm(intent) }
        while resume == nil { await Task.yield() }
        c.leaveScreen(clubID: 7, expectedIdentity: s.clubIdentity)
        resume?.resume(returning: s.receipt)
        let result = await task.value
        XCTAssertEqual(result, .ignoredStale); XCTAssertEqual(c.state(clubID: 7), .outcomeUnknown(.cancelled))
        XCTAssertEqual(s.readIDs, [7]); XCTAssertEqual(s.writes.count, 1)
    }
    func testStaleAndWrongClubReadbackNeverPublishes() async throws {
        for switchAccount in [false, true] {
            let (c, s) = fixture(); let intent = try await prepare(c, s)
            s.readOperation = { _ in
                if switchAccount { s.changeIdentity(accountID: 2, epoch: 2) }
                return try clubActionFixture(["id": 8, "isJoined": true])
            }
            _ = await c.confirm(intent)
            XCTAssertEqual(c.readback(clubID: 7), switchAccount ? .idle : .unavailable)
        }
    }
    func testReadbackCancellationDiscardsLateResultAndKeepsUnknownLock() async throws {
        let (c, s) = fixture(); s.writeOperation = { _ in throw ClubActionWriteError.outcomeUnknown(.transport) }
        let intent = try await prepare(c, s); _ = await c.confirm(intent)
        var resume: CheckedContinuation<ClubRecord, Error>?
        s.readOperation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let task = Task { await c.readBack(clubID: 7) }
        while resume == nil { await Task.yield() }
        let duplicate = await c.readBack(clubID: 7)
        XCTAssertEqual(duplicate, .blocked(.readbackInProgress))
        c.leaveScreen(clubID: 7, expectedIdentity: s.clubIdentity)
        resume?.resume(returning: s.detail)
        let result = await task.value
        XCTAssertEqual(result, .ignoredStale); XCTAssertEqual(c.readback(clubID: 7), .idle)
        XCTAssertEqual(c.state(clubID: 7), .outcomeUnknown(.transport))
    }
    func testOlderScreenCannotCancelNewerConfirmationForSameClub() async throws {
        let (c, s) = fixture(); let oldOwner = UUID(), newOwner = UUID()
        let old = try await c.prepare(clubID: 7, action: .join, expectedIdentity: s.clubIdentity, ownerID: oldOwner)
        c.cancel(old)
        let current = try await c.prepare(clubID: 7, action: .join, expectedIdentity: s.clubIdentity, ownerID: newOwner)
        c.leaveScreen(clubID: 7, expectedIdentity: s.clubIdentity, ownerID: oldOwner)
        XCTAssertEqual(c.state(clubID: 7), .awaitingConfirmation)
        _ = await c.confirm(current)
        XCTAssertEqual(s.writes.count, 1)
    }
    func testOlderScreenCannotCancelNewerUnknownReadback() async throws {
        let (c, s) = fixture(); let oldOwner = UUID(), newOwner = UUID()
        s.writeOperation = { _ in throw ClubActionWriteError.outcomeUnknown(.transport) }
        let intent = try await c.prepare(clubID: 7, action: .join, expectedIdentity: s.clubIdentity, ownerID: oldOwner)
        _ = await c.confirm(intent)
        var resume: CheckedContinuation<ClubRecord, Error>?
        s.readOperation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let task = Task { await c.readBack(clubID: 7, ownerID: newOwner) }
        while resume == nil { await Task.yield() }
        c.leaveScreen(clubID: 7, expectedIdentity: s.clubIdentity, ownerID: oldOwner)
        XCTAssertEqual(c.readback(clubID: 7), .loading)
        resume?.resume(returning: s.detail)
        let result = await task.value
        XCTAssertEqual(result, .applied); XCTAssertEqual(c.readback(clubID: 7), .received(s.detail))
        XCTAssertEqual(c.state(clubID: 7), .outcomeUnknown(.transport))
    }
    func testOldReadbackCannotClearNewOperationWithSameReadGeneration() async throws {
        let (c, s) = fixture(); let oldOwner = UUID(), newOwner = UUID()
        var oldResume: CheckedContinuation<ClubRecord, Error>?
        var newResume: CheckedContinuation<ClubRecord, Error>?
        let old = try await c.prepare(clubID: 7, action: .join, expectedIdentity: s.clubIdentity, ownerID: oldOwner)
        s.readOperation = { _ in
            if s.readIDs.count == 2 { return try await withCheckedThrowingContinuation { oldResume = $0 } }
            if s.readIDs.count == 4 { return try await withCheckedThrowingContinuation { newResume = $0 } }
            return s.detail
        }
        let oldTask = Task { await c.confirm(old) }
        while oldResume == nil { await Task.yield() }
        c.leaveScreen(clubID: 7, expectedIdentity: s.clubIdentity, ownerID: oldOwner)
        let current = try await c.prepare(clubID: 7, action: .join, expectedIdentity: s.clubIdentity, ownerID: newOwner)
        let newTask = Task { await c.confirm(current) }
        while newResume == nil { await Task.yield() }
        oldResume?.resume(returning: s.detail); _ = await oldTask.value
        XCTAssertEqual(c.readback(clubID: 7), .loading)
        newResume?.resume(returning: s.detail); _ = await newTask.value
        XCTAssertEqual(c.readback(clubID: 7), .received(s.detail)); XCTAssertEqual(s.writes.count, 2)
    }
    func testCancellationBeforeConfirmationNeverWrites() async throws {
        let (c, s) = fixture(); let intent = try await prepare(c, s)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await c.confirm(intent)
        }
        let result = await task.value
        XCTAssertEqual(result, .blocked(.cancelledBeforeDispatch)); XCTAssertTrue(s.writes.isEmpty)
    }
    func testReadbackStartNotificationOrdersFreshReadAfterAcknowledgedWrite() async throws {
        let (c, s) = fixture(); var events: [String] = []
        s.readOperation = { _ in events.append("read"); return s.detail }
        s.writeOperation = { _ in events.append("write"); return s.receipt }
        let intent = try await prepare(c, s)
        _ = await c.confirm(intent, onReadbackStarted: { events.append("start") })
        XCTAssertEqual(events, ["read", "write", "start", "read"])
        events.removeAll()
        _ = await c.readBack(clubID: 7, onStarted: { events.append("explicit-start") })
        XCTAssertEqual(events, ["explicit-start", "read"])
    }
    func testUnknownOutcomeDoesNotAnnounceUnrequestedReadback() async throws {
        let (c, s) = fixture(); var starts = 0
        s.writeOperation = { _ in throw ClubActionWriteError.outcomeUnknown(.transport) }
        let intent = try await prepare(c, s)
        _ = await c.confirm(intent, onReadbackStarted: { starts += 1 })
        XCTAssertEqual(starts, 0); XCTAssertEqual(s.readIDs, [7])
    }
    func testMembershipInvalidationOnlyFollowsAcknowledgedCurrentAccountWrite() async throws {
        let s = ClubActionFakeStore(); var changed: [Int] = []
        let c = ClubActionCoordinator(writer: s, reader: s, onMembershipChanged: { changed.append($0) })
        let first = try await prepare(c, s); _ = await c.confirm(first)
        XCTAssertEqual(changed, [7])
        s.writeOperation = { _ in throw ClubActionWriteError.outcomeUnknown(.transport) }
        let second = try await prepare(c, s); _ = await c.confirm(second)
        XCTAssertEqual(changed, [7]); XCTAssertEqual(s.writes.count, 2)
    }
}

private func clubActionFixture(_ overrides: [String: Any] = [:]) throws -> ClubRecord {
    let fields = ["id": 7, "name": "Fixture club"] as [String: Any]
    return try JSONDecoder().decode(ClubRecord.self, from: JSONSerialization.data(withJSONObject: fields.merging(overrides) { _, new in new }))
}

@MainActor
private final class ClubActionFakeStore: ClubReading, ClubActionWriting {
    var isConfigured = true
    var isClubConfigured: Bool { isConfigured }
    var identity: ClubReadIdentity? = .init(accountID: 1, epoch: 1)
    var clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    var viewerIsMerchant = false
    var detail = try! clubActionFixture()
    var receipt = ClubActionReceipt(state: nil, message: nil)
    var writes: [ClubAction] = []
    var readIDs: [Int] = []
    var readOperation: ((Int) async throws -> ClubRecord)?
    var writeOperation: ((ClubAction) async throws -> ClubActionReceipt)?
    func changeIdentity(accountID: Int, epoch: UInt64) { clubIdentity = .init(accountID: accountID, epoch: epoch); identity = clubIdentity }
    func clubDetail(id: Int) async throws -> ClubRecord { readIDs.append(id); return try await readOperation?(id) ?? detail }
    func perform(_ action: ClubAction, clubID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        guard expectedIdentity == identity else { throw ClubActionWriteError.notSent(.unauthorized) }
        writes.append(action); return try await writeOperation?(action) ?? receipt
    }
    func clubHome() async throws -> ClubHome { throw APIError.invalidRequest }
    func clubOwned() async throws -> [ClubRecord] { throw APIError.invalidRequest }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.invalidRequest }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.invalidRequest }
}
