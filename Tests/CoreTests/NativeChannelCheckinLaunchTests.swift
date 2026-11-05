import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelCheckinLaunchTests: XCTestCase {
    func testStatusUsesShanghaiServerDateAcrossUTCMidnightDifference() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        h.wire.nextDay()
        await flow.activate(current: { h.live })
        XCTAssertEqual(flow.status?.checkinDate, "2026-11-05")
        flow.prepare()
        XCTAssertEqual(flow.review?.checkinDate, "2026-11-05")
        XCTAssertEqual(h.wire.posts.count, 0)
    }

    func testStatusAndRankRejectInconsistentServerClocks() async throws {
        let invalid: [[String: Any]] = [
            ["timezone": "UTC"], ["checkinDate": "2026-11-05"],
            ["checkinDate": "2026-02-30"], ["nextDayAt": Int64(1793808000001)],
            ["nextDayAt": Int64.max], ["serverTime": Int64.max]
        ]
        for fields in invalid {
            let h = try CheckinLaunchHarness()
            h.wire.statusChanges = fields; h.wire.rankChanges = fields
            do { _ = try await h.service.status(source: { true }); XCTFail("Accepted status: \(fields)") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            do { _ = try await h.service.rank(limit: 10, source: { true }); XCTFail("Accepted rank: \(fields)") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testMidnightDuringReviewRequiresNewConfirmationWithoutPosting() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepare()
        XCTAssertEqual(flow.review?.checkinDate, "2026-11-04")
        h.wire.nextDay(); await flow.confirm()
        XCTAssertEqual(flow.phase, .rejected("CHECKIN_DATE_OR_STATE_CHANGED"))
        XCTAssertNil(flow.review); XCTAssertNil(flow.pending)
        XCTAssertTrue(h.wire.posts.isEmpty); XCTAssertTrue(h.storage.rows.isEmpty)
        flow.prepare()
        XCTAssertEqual(flow.review?.checkinDate, "2026-11-05")
    }

    func testRestartRecoversOriginalDateAndRequestBeforeReadingCurrentDay() async throws {
        let h = try CheckinLaunchHarness(); let original = try await h.unknown()
        let command = try XCTUnwrap(original.pending); original.deactivate()
        h.wire.nextDay(); h.wire.calls.removeAll()
        let restored = try h.flow(); await restored.activate(current: { h.live })
        XCTAssertEqual(h.wire.calls.map { $0.url!.lastPathComponent }, ["checkin-request", "checkin-status"])
        let query = URLComponents(url: try XCTUnwrap(h.wire.calls.first?.url), resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "request_id" }?.value, command.requestId)
        XCTAssertEqual(query.first { $0.name == "checkin_date" }?.value, "2026-11-04")
        XCTAssertEqual(restored.lastConfirmedRequest?.requestID, command.requestId)
        XCTAssertEqual(restored.lastConfirmedRequest?.checkinDate, "2026-11-04")
        XCTAssertEqual(restored.status?.checkinDate, "2026-11-05")
        XCTAssertNil(restored.pending); XCTAssertTrue(h.storage.rows.isEmpty)
        XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testExplicitRetryReadsReceiptThenResendsIdenticalOriginalCommand() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
        let original = try JSONDecoder().decode(NativeChannelCheckinCommand.self, from: XCTUnwrap(h.wire.posts.first))
        h.wire.failPost = false; h.wire.receiptState = "NOT_FOUND"; h.wire.calls.removeAll()
        await flow.retryOriginal()
        XCTAssertEqual(h.wire.calls.map { $0.url!.lastPathComponent }, ["checkin-request", "checkin"])
        XCTAssertEqual(try h.wire.posts.map { try JSONDecoder().decode(NativeChannelCheckinCommand.self, from: $0) }, [original, original])
        XCTAssertEqual(flow.phase, .applied); XCTAssertNil(flow.pending)
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, h.wire.command?.requestId)
        XCTAssertTrue(h.storage.rows.isEmpty)
    }

    func testPendingReceiptNeverResendsOrManufacturesSuccess() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
        let command = flow.pending; h.wire.receiptState = "PENDING"
        await flow.retryOriginal()
        XCTAssertEqual(flow.phase, .unknown); XCTAssertEqual(flow.pending, command)
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertEqual(h.wire.posts.count, 1)
        XCTAssertFalse(h.storage.rows.isEmpty)
    }

    func testBusinessErrorDoesNotProveOriginalRequestUnapplied() async throws {
        for code in ["MEMBERSHIP_REQUIRED", "CHECKIN_DATE_CHANGED", "UNRECOGNIZED"] {
            let h = try CheckinLaunchHarness(); let flow = try h.flow()
            await flow.activate(current: { h.live }); flow.prepare()
            let command = try XCTUnwrap(flow.review); h.wire.postRejection = code
            await flow.confirm()
            XCTAssertEqual(flow.phase, .unknown); XCTAssertEqual(flow.pending, command)
            XCTAssertFalse(h.storage.rows.isEmpty); XCTAssertNil(flow.lastConfirmedRequest)
            h.wire.postRejection = nil; flow.deactivate()
            await flow.activate(current: { h.live })
            XCTAssertEqual(flow.lastConfirmedRequest?.requestID, command.requestId)
            XCTAssertEqual(h.wire.posts.count, 1)
        }
    }

    func testFinalUnappliedReceiptClearsOriginalWithoutRetryOrSuccess() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
        h.wire.receiptState = "NOT_FOUND"; h.wire.unappliedFinal = true
        await flow.retryOriginal()
        XCTAssertEqual(flow.phase, .expiredUnapplied); XCTAssertNil(flow.pending)
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertEqual(h.wire.posts.count, 1)
        XCTAssertTrue(h.storage.rows.isEmpty)
    }

    func testRedactedReceiptRetainsOnlyOriginalIdentityAndSkipsCurrentReadOnReentry() async throws {
        let h = try CheckinLaunchHarness(); let old = try await h.unknown()
        let command = try XCTUnwrap(old.pending); old.deactivate()
        h.wire.redacted = true; h.wire.calls.removeAll()
        let restored = try h.flow(); await restored.activate(current: { h.live })
        XCTAssertEqual(restored.phase, .redacted); XCTAssertNil(restored.status)
        XCTAssertEqual(restored.lastConfirmedRequest?.requestID, command.requestId)
        XCTAssertEqual(restored.lastConfirmedRequest?.resultRedacted, true)
        XCTAssertEqual(h.wire.calls.map { $0.url!.lastPathComponent }, ["checkin-request"])
        XCTAssertTrue(h.storage.rows.isEmpty)
    }

    func testMismatchedReceiptNeverSettlesOriginalJournal() async throws {
        let invalid: [[String: Any]] = [
            ["requestId": UUID().uuidString.lowercased()], ["requestHash": String(repeating: "0", count: 64)],
            ["actorId": "12"], ["channelId": "43"], ["checkinDate": "2026-11-05"],
            ["source": "current-status"], ["state": "UNKNOWN"]
        ]
        for fields in invalid {
            let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
            let command = flow.pending; h.wire.receiptChanges = fields
            await flow.recover()
            XCTAssertEqual(flow.phase, .unknown); XCTAssertEqual(flow.pending, command)
            XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(h.storage.rows.isEmpty)
            XCTAssertEqual(h.wire.posts.count, 1)
        }
    }

    func testMalformedAppliedResultDoesNotClearUncertainty() async throws {
        for fields: [String: Any] in [["streak": Int64(Int32.max) + 1], ["memberId": "12"],
                                      ["rewardIssued": true], ["source": "EVENT", "resultCode": "CHECKED"]] {
            let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
            h.wire.resultChanges = fields; await flow.recover()
            XCTAssertEqual(flow.phase, .unknown); XCTAssertNotNil(flow.pending)
            XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(h.storage.rows.isEmpty)
        }
    }

    func testJournalRemovalFailureStaysPersistenceFailedAndBlocksNewWrite() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
        h.storage.failRemove = true; await flow.recover()
        XCTAssertEqual(flow.phase, .persistenceFailed); XCTAssertNotNil(flow.pending)
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(flow.canCheckin)
        XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testFailedJournalSaveStaysBlockedThroughRefreshAndCancel() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepare(); h.storage.failWrite = true
        await flow.confirm(); XCTAssertEqual(flow.phase, .persistenceFailed)
        XCTAssertTrue(h.wire.posts.isEmpty)
        flow.cancelReview(); await flow.refresh()
        XCTAssertEqual(flow.phase, .persistenceFailed); XCTAssertFalse(flow.canCheckin)
        flow.prepare(); XCTAssertNil(flow.review); XCTAssertTrue(h.wire.posts.isEmpty)
        h.storage.failWrite = false; await flow.activate(current: { h.live })
        XCTAssertTrue(flow.canCheckin)
    }

    func testCorruptJournalCannotBeBypassedByStatusRefresh() async throws {
        let h = try CheckinLaunchHarness(); let old = try await h.unknown(); old.deactivate()
        let key = try XCTUnwrap(h.storage.rows.keys.first)
        h.storage.rows[key] = Data("corrupt original journal".utf8)
        let restored = try h.flow(); await restored.activate(current: { h.live })
        XCTAssertEqual(restored.phase, .persistenceFailed)
        await restored.refresh(); restored.cancelReview()
        XCTAssertEqual(restored.phase, .persistenceFailed); XCTAssertFalse(restored.canCheckin)
        restored.prepare(); await restored.confirm()
        XCTAssertNil(restored.review); XCTAssertEqual(h.wire.posts.count, 1)
        XCTAssertEqual(h.storage.rows[key], Data("corrupt original journal".utf8))
    }

    func testSaveReadbackFailureRecoversDurableOriginalOnReentry() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepare()
        let command = try XCTUnwrap(flow.review); h.storage.failWriteReadback = true
        await flow.confirm()
        XCTAssertEqual(flow.phase, .persistenceFailed); XCTAssertTrue(h.wire.posts.isEmpty)
        flow.cancelReview(); await flow.refresh()
        XCTAssertFalse(flow.canCheckin); XCTAssertEqual(flow.phase, .persistenceFailed)
        h.wire.command = command; h.wire.receiptState = "NOT_FOUND"
        flow.deactivate(); await flow.activate(current: { h.live })
        XCTAssertEqual(flow.pending, command); XCTAssertEqual(flow.phase, .unknown)
        XCTAssertTrue(h.wire.posts.isEmpty)
        await flow.retryOriginal()
        XCTAssertEqual(h.wire.posts.count, 1)
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, command.requestId)
    }

    func testRetryWithCorruptJournalDoesNotResendAndBlocksPersistence() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
        let command = flow.pending; let key = try XCTUnwrap(h.storage.rows.keys.first)
        h.storage.rows[key] = Data("corrupt original journal".utf8)
        h.wire.receiptState = "NOT_FOUND"; h.wire.failPost = false
        await flow.retryOriginal()
        XCTAssertEqual(flow.phase, .persistenceFailed); XCTAssertEqual(flow.pending, command)
        XCTAssertEqual(h.wire.posts.count, 1)
        let count = h.wire.calls.count
        await flow.retryOriginal(); XCTAssertEqual(h.wire.calls.count, count)
        XCTAssertEqual(h.storage.rows[key], Data("corrupt original journal".utf8))
    }

    func testUnresolvedReceiptCannotClearExistingPersistenceBlock() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
        h.storage.failRemove = true; await flow.recover()
        XCTAssertEqual(flow.phase, .persistenceFailed)
        h.wire.receiptState = "PENDING"; await flow.recover()
        XCTAssertEqual(flow.phase, .persistenceFailed)
        let count = h.wire.calls.count
        await flow.retryOriginal(); XCTAssertEqual(h.wire.calls.count, count)
        h.storage.failRemove = false; h.wire.receiptState = "APPLIED"; await flow.recover()
        XCTAssertEqual(flow.phase, .applied); XCTAssertNil(flow.pending)
        XCTAssertTrue(h.storage.rows.isEmpty); XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testAccountChangeDuringPostIgnoresLateReceiptAndKeepsJournal() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepare(); h.wire.pauseSuffix = "checkin"
        let task = Task { await flow.confirm() }; await h.wire.waitUntilPaused()
        h.live = false; h.wire.resume(); await task.value
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertNil(flow.status)
        XCTAssertFalse(h.storage.rows.isEmpty)
        XCTAssertEqual(h.wire.posts.count, 1)
        h.live = true
        XCTAssertFalse(flow.service.isCurrent, "A retired account context cannot revive")
    }

    func testRevocationDuringPostIgnoresLateReceiptAndRecoversSameRequestLater() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepare(); h.wire.pauseSuffix = "checkin"
        let task = Task { await flow.confirm() }; await h.wire.waitUntilPaused()
        let command = try XCTUnwrap(flow.pending)
        h.denied.insert("checkin"); h.wire.resume(); await task.value
        XCTAssertEqual(flow.phase, .unknown); XCTAssertEqual(flow.pending, command)
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(h.storage.rows.isEmpty)
        h.denied.remove("checkin"); await flow.recover()
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, command.requestId)
        XCTAssertEqual(h.wire.posts.count, 1); XCTAssertTrue(h.storage.rows.isEmpty)
    }

    func testBackgroundDuringPostKeepsOriginalForForegroundRecovery() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepare(); h.wire.pauseSuffix = "checkin"
        let task = Task { await flow.confirm() }; await h.wire.waitUntilPaused()
        let command = try XCTUnwrap(flow.pending)
        flow.deactivate(); h.wire.resume(); await task.value
        XCTAssertEqual(flow.phase, .closed); XCTAssertNil(flow.lastConfirmedRequest)
        XCTAssertFalse(h.storage.rows.isEmpty)
        await flow.activate(current: { h.live })
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, command.requestId)
        XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testCancelledPostKeepsOriginalJournalForLaterReceiptRecovery() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepare(); h.wire.pauseSuffix = "checkin"
        let task = Task { await flow.confirm() }; await h.wire.waitUntilPaused()
        let command = try XCTUnwrap(flow.pending)
        task.cancel(); h.wire.resume(); await task.value
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(h.storage.rows.isEmpty)
        flow.deactivate(); await flow.activate(current: { h.live })
        XCTAssertEqual(flow.lastConfirmedRequest?.requestID, command.requestId)
        XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testReceiptRevokedDuringRecoveryCannotSettleOrExposeLateResult() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown()
        let command = flow.pending; h.wire.pauseSuffix = "checkin-request"
        let task = Task { await flow.recover() }; await h.wire.waitUntilPaused()
        h.denied.insert("checkin-request"); h.wire.resume(); await task.value
        XCTAssertEqual(flow.phase, .unknown); XCTAssertEqual(flow.pending, command)
        XCTAssertNil(flow.lastConfirmedRequest); XCTAssertFalse(h.storage.rows.isEmpty)
        XCTAssertEqual(h.wire.posts.count, 1)
    }

    func testReactivationDuringReadDoesNotStayBusyOrAcceptOldResponse() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        h.wire.pauseSuffix = "checkin-status"
        let task = Task { await flow.activate(current: { h.live }) }; await h.wire.waitUntilPaused()
        h.wire.nextDay(); await flow.activate(current: { h.live })
        XCTAssertFalse(flow.busy); XCTAssertEqual(flow.status?.checkinDate, "2026-11-05")
        h.wire.statusChanges = ["checkinDate": "2026-11-04"]
        h.wire.resume(); await task.value
        XCTAssertFalse(flow.busy); XCTAssertEqual(flow.status?.checkinDate, "2026-11-05")
    }

    func testCancelledOlderRecoveryActivationCannotEraseNewVisit() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown(); flow.deactivate()
        h.wire.pauseSuffix = "checkin-request"
        let oldVisit = Task { await flow.activate(current: { h.live }) }
        await h.wire.waitUntilPaused()
        await flow.activate(current: { h.live })
        let confirmed = flow.lastConfirmedRequest
        XCTAssertNotNil(flow.status); XCTAssertEqual(flow.phase, .idle)
        let count = h.wire.calls.count
        oldVisit.cancel(); h.wire.resume(); await oldVisit.value
        XCTAssertNotNil(flow.status); XCTAssertEqual(flow.phase, .idle)
        XCTAssertEqual(flow.lastConfirmedRequest, confirmed)
        XCTAssertFalse(flow.busy); XCTAssertEqual(h.wire.calls.count, count)
    }

    func testOlderRecoveryActivationDoesNotRefreshNewerVisitAgain() async throws {
        let h = try CheckinLaunchHarness(); let flow = try await h.unknown(); flow.deactivate()
        h.wire.pauseSuffix = "checkin-request"
        let oldVisit = Task { await flow.activate(current: { h.live }) }
        await h.wire.waitUntilPaused(); await flow.activate(current: { h.live })
        let count = h.wire.calls.count
        h.wire.resume(); await oldVisit.value
        XCTAssertEqual(h.wire.calls.count, count, "An old activation must not schedule a new visit's read")
        XCTAssertNotNil(flow.status); XCTAssertFalse(flow.busy)
    }

    func testRevokedReadsCannotPublishLateStatusOrRank() async throws {
        for suffix in ["checkin-status", "checkin-rank"] {
            let h = try CheckinLaunchHarness(); h.wire.pauseSuffix = suffix
            let task = Task { () -> Bool in
                do {
                    if suffix == "checkin-status" { _ = try await h.service.status(source: { true }) }
                    else { _ = try await h.service.rank(limit: 10, source: { true }) }
                    return true
                } catch { return false }
            }
            await h.wire.waitUntilPaused(); h.denied.insert(suffix); h.wire.resume()
            let accepted = await task.value; XCTAssertFalse(accepted)
        }
    }

    func testConfirmedReceiptAndCachedStatusHideWhenTheirReadGrantIsRevoked() async throws {
        let h = try CheckinLaunchHarness(); let flow = try h.flow()
        await flow.activate(current: { h.live }); flow.prepare(); await flow.confirm()
        XCTAssertNotNil(flow.lastConfirmedRequest)
        await flow.refresh(); XCTAssertNotNil(flow.status)
        let count = h.wire.calls.count
        h.denied.formUnion(["checkin-status", "checkin-request"])
        XCTAssertNil(flow.status); XCTAssertNil(flow.lastConfirmedRequest)
        XCTAssertEqual(h.wire.calls.count, count)
    }

    func testUnauthorizedCurrentResponseRetiresServiceOnce() async throws {
        let h = try CheckinLaunchHarness(); h.wire.httpStatus = 401
        do { _ = try await h.service.status(source: { true }); XCTFail("Accepted unauthorized response") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        do { _ = try await h.service.status(source: { true }); XCTFail("Reused retired service") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(h.unauthorizedCount, 1); XCTAssertEqual(h.wire.calls.count, 1)
    }

    func testDifferentRuntimeContextCannotOwnServiceJournal() async throws {
        let h = try CheckinLaunchHarness()
        let foreign = RuntimeDependencyContext(market: .china, baseURL: h.context.baseURL, role: "player",
            session: try .init(accountID: 11, epoch: 2, namespace: "CN:checkin-launch-test", token: "fixture-only"))
        XCTAssertThrowsError(try NativeChannelCheckinFlow(service: h.service, context: foreign, storage: h.storage))
    }

    func testPendingJournalIsIsolatedFromAnotherAccountAndRealm() async throws {
        let h = try CheckinLaunchHarness(); let old = try await h.unknown(); old.deactivate()
        let saved = h.storage.rows
        for (account, realm) in [(12, "CN:checkin-launch-test"), (11, "CN:another-realm")] {
            let other = try CheckinLaunchHarness(account: account, namespace: realm, storage: h.storage)
            let flow = try other.flow(); await flow.activate(current: { other.live })
            XCTAssertNil(flow.pending); XCTAssertNil(flow.lastConfirmedRequest)
            XCTAssertEqual(other.wire.calls.map { $0.url!.lastPathComponent }, ["checkin-status"])
            XCTAssertEqual(h.storage.rows, saved)
        }
    }

    func testRankExpansionRequestsFreshTopFiftyAndKeepsActorConsistent() async throws {
        let h = try CheckinLaunchHarness()
        let first = try await h.service.rank(limit: 10, source: { true })
        let expanded = try await h.service.rank(limit: 50, source: { true })
        XCTAssertEqual(first.list.count, 10); XCTAssertTrue(first.hasMore)
        XCTAssertEqual(expanded.list.count, 12); XCTAssertFalse(expanded.hasMore)
        XCTAssertEqual(expanded.list.first { $0.memberId == "11" }?.rank, expanded.me.rank)
        let queries = h.wire.calls.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems! }
        XCTAssertEqual(queries.map { $0.first { $0.name == "limit" }?.value }, ["10", "50"])
        XCTAssertTrue(queries.allSatisfy { $0.first { $0.name == "days" }?.value == "30" })
        XCTAssertTrue(queries.allSatisfy { !$0.contains { $0.name == "cursor" || $0.name == "offset" } })
    }

    func testRankRejectsDuplicateUnorderedAndContradictoryPages() async throws {
        let h = try CheckinLaunchHarness()
        let invalid: [[String: Any]] = [
            ["list": [h.wire.row(1, rank: 1), h.wire.row(1, rank: 2)]],
            ["list": [h.wire.row(2, rank: 1), h.wire.row(1, rank: 2)]],
            ["list": [h.wire.row(1, rank: 2)]],
            ["me": h.wire.row(11, rank: 1)],
            ["othersVisible": false], ["limit": 50],
            ["list": [], "hasMore": true]
        ]
        for fields in invalid {
            h.wire.rankChanges = ["hasMore": false].merging(fields) { _, new in new }
            do { _ = try await h.service.rank(limit: 10, source: { true }); XCTFail("Accepted malformed rank") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
        h.wire.rankChanges = ["me": h.wire.row(11, rank: 11, days: 19)]
        do { _ = try await h.service.rank(limit: 50, source: { true }); XCTFail("Accepted contradictory own row") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }

    func testRankPrivacyAndInvalidLimitDoNotLeakOrDispatch() async throws {
        let h = try CheckinLaunchHarness()
        h.wire.rankChanges = ["othersVisible": false, "list": [], "me": h.wire.row(11, rank: nil), "hasMore": false]
        let rank = try await h.service.rank(limit: 10, source: { true })
        XCTAssertTrue(rank.list.isEmpty); XCTAssertNil(rank.me.rank)
        for limit in [0, 11, 51, Int.max] {
            do { _ = try await h.service.rank(limit: limit, source: { true }); XCTFail("Accepted invalid limit") }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertEqual(h.wire.calls.count, 1)
    }
}

@MainActor private final class CheckinLaunchStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    var failRemove = false, failWrite = false, failWriteReadback = false
    private var failNextRead = false
    func read(_ key: String) throws -> Data? {
        if failNextRead { failNextRead = false; throw APIError.invalidRequest }
        return rows[key]
    }
    func write(_ data: Data, key: String) throws {
        if failWrite { throw APIError.invalidRequest }
        rows[key] = data
        if failWriteReadback { failWriteReadback = false; failNextRead = true }
    }
    func remove(_ key: String) throws {
        if failRemove { throw APIError.invalidRequest }
        rows[key] = nil
    }
}

@MainActor private final class CheckinLaunchWire: HTTPTransport {
    var calls: [URLRequest] = [], posts: [Data] = []
    var command: NativeChannelCheckinCommand?
    var actor = "11", day = "2026-11-04"
    var serverTime: Int64 = 1793807999000, nextDayAt: Int64 = 1793808000000
    var failPost = false, redacted = false, unappliedFinal = false
    var receiptState = "APPLIED", httpStatus = 200
    var postRejection: String?
    var statusChanges: [String: Any] = [:], rankChanges: [String: Any] = [:]
    var receiptChanges: [String: Any] = [:], resultChanges: [String: Any] = [:]
    var pauseSuffix: String?
    private var paused: CheckedContinuation<Void, Never>?
    private var reached: CheckedContinuation<Void, Never>?
    func waitUntilPaused() async {
        if paused != nil { return }
        await withCheckedContinuation { reached = $0 }
    }
    func resume() { let continuation = paused; paused = nil; continuation?.resume() }
    func nextDay() { day = "2026-11-05"; serverTime = 1793808000000; nextDayAt = 1793894400000 }
    func row(_ member: Int, rank: Int?, days: Int = 20) -> [String: Any] {
        ["memberId": String(member), "rank": rank.map { $0 as Any } ?? NSNull(),
         "days": days, "makeupDays": 0, "streak": 2, "nickname": NSNull(), "avatar": NSNull()]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls.append(request)
        let suffix = try XCTUnwrap(request.url?.lastPathComponent)
        if request.httpMethod == "POST" {
            let bytes = try XCTUnwrap(request.httpBody); posts.append(bytes)
            command = try JSONDecoder().decode(NativeChannelCheckinCommand.self, from: bytes)
        }
        if pauseSuffix == suffix {
            pauseSuffix = nil
            await withCheckedContinuation { continuation in
                paused = continuation; reached?.resume(); reached = nil
            }
        }
        if request.httpMethod == "POST", failPost { throw APIError.malformedResponse }
        if request.httpMethod == "POST", let code = postRejection {
            return (try JSONSerialization.data(withJSONObject: ["code": 403, "errorCode": code]), 200)
        }
        var value: [String: Any]
        if suffix == "checkin-status" || suffix == "checkin-rank" {
            value = ["source": "original-channel-checkin-v1", "actorId": actor, "channelId": "42",
                     "timezone": "Asia/Shanghai", "checkinDate": day, "serverTime": serverTime, "nextDayAt": nextDayAt]
            if suffix == "checkin-status" {
                value.merge(["checked": false, "canCheckin": true, "makeupSelfService": false,
                             "rewardPolicyConfigured": false, "streak": 0, "history": [],
                             "makeupPolicy": ["configured": false, "enabled": false, "timezone": "Asia/Shanghai"]]) { _, new in new }
                value.merge(statusChanges) { _, new in new }
            } else {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                let limit = Int(query.first { $0.name == "limit" }!.value!)!
                value.merge(["periodDays": 30, "limit": limit, "list": (1...min(limit, 12)).map { row($0, rank: $0) },
                             "me": row(Int(actor)!, rank: Int(actor)!), "othersVisible": true, "hasMore": limit == 10]) { _, new in new }
                value.merge(rankChanges) { _, new in new }
            }
        } else {
            let original = try XCTUnwrap(command)
            let state = suffix == "checkin" ? "APPLIED" : receiptState
            value = ["source": "original-channel-checkin-request-v1", "actorId": actor, "channelId": "42",
                     "requestId": original.requestId, "requestHash": original.digest,
                     "checkinDate": original.checkinDate, "state": state]
            if state == "NOT_FOUND" { value["unappliedFinal"] = unappliedFinal }
            if state == "APPLIED" {
                value["resultRedacted"] = redacted
                if !redacted {
                    var result: [String: Any] = ["id": "9", "channelId": "42", "memberId": actor,
                        "checkinDate": original.checkinDate, "source": "CHANNEL", "resultCode": "CHECKED",
                        "streak": 1, "checkedAt": Int64(1793807999000), "rewardIssued": false]
                    result.merge(resultChanges) { _, new in new }; value["result"] = result
                }
            }
            value.merge(receiptChanges) { _, new in new }
        }
        return (try JSONSerialization.data(withJSONObject: ["code": httpStatus == 401 ? 401 : 200, "data": value]), httpStatus)
    }
}

@MainActor private final class CheckinLaunchHarness {
    let context: RuntimeDependencyContext
    let wire = CheckinLaunchWire()
    let storage: CheckinLaunchStorage
    var live = true, denied: Set<String> = []
    var unauthorizedCount = 0
    lazy var service: NativeChannelCheckinService = {
        try! NativeChannelCheckinService(context: context, channelID: "42", transport: wire,
            permits: { _, path in !self.denied.contains(String(path.split(separator: "/").last!)) },
            current: { self.live }, unauthorized: { self.unauthorizedCount += 1 })
    }()
    init(account: Int = 11, namespace: String = "CN:checkin-launch-test", storage: CheckinLaunchStorage? = nil) throws {
        self.storage = storage ?? CheckinLaunchStorage(); wire.actor = String(account)
        context = .init(market: .china, baseURL: URL(string: "https://example.test/")!, role: "player",
            session: try .init(accountID: account, epoch: 1, namespace: namespace, token: "fixture-only"))
    }
    func flow() throws -> NativeChannelCheckinFlow { try .init(service: service, context: context, storage: storage) }
    func unknown() async throws -> NativeChannelCheckinFlow {
        wire.failPost = true
        let flow = try flow(); await flow.activate(current: { self.live }); flow.prepare(); await flow.confirm()
        XCTAssertEqual(flow.phase, .unknown); XCTAssertNotNil(flow.pending)
        return flow
    }
}
