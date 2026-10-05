import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ClubOwnerRefundTests: XCTestCase {
    private func target() throws -> ClubOwnerRefundTarget { try .init(clubID: 81, registrationID: 121) }
    private func setup(_ scenario: ClubOwnerRefundFixtureAccess.Scenario = .accepted) -> (ClubOwnerRefundFixtureAccess, ClubOwnerRefundMemoryLocks, ClubOwnerRefundCoordinator) {
        let access = ClubOwnerRefundFixtureAccess(scenario), locks = ClubOwnerRefundMemoryLocks()
        return (access, locks, ClubOwnerRefundCoordinator(access: access, locks: locks))
    }
    private func value(_ text: String) -> ClubGovernanceValue { ClubGovernanceFixtures.json(text) }
    func testExactFormContainsOnlyRegistrationIDAndNoIdempotencyKey() throws {
        let service = ClubOwnerRefundService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!))
        let request = try service.request(registrationID: 121, token: "synthetic")
        XCTAssertEqual(request.url?.path, "/api/registration/cancel-by-owner"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data;") == true)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n121")); XCTAssertFalse(body.contains("clubId")); XCTAssertFalse(body.contains("amount"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Idempotency-Key"))
    }
    func testProductionServiceCannotDispatchEvenWithValidConfiguration() async throws {
        let service = ClubOwnerRefundService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!))
        var checkCalled = false
        do { _ = try await service.cancel(registrationID: 121, token: "synthetic") { checkCalled = true }; XCTFail() }
        catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .disabled) }
        XCTAssertFalse(checkCalled); XCTAssertFalse(service.canDispatchOffline)
    }
    func testShippingAdapterOffersReviewButCannotSend() async throws {
        let fixture = ClubOwnerRefundFixtureAccess(), locks = ClubOwnerRefundMemoryLocks()
        let access = ClubOwnerRefundReadOnlyAccess(governance: fixture.governance)
        let coordinator = ClubOwnerRefundCoordinator(access: access, locks: locks), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        XCTAssertFalse(access.canDispatchOffline); XCTAssertEqual(coordinator.state(target).phase, .notSent)
        XCTAssertEqual(coordinator.state(target).failure, .disabled); XCTAssertTrue(locks.values.isEmpty)
    }
    func testFreshCanRefundAndOwnerPermissionBothRequired() async throws {
        let (access, _, coordinator) = setup()
        var detail = access.governance.overrideValue[.checkin]!.object!; detail["canRefund"] = .bool(false); access.governance.overrideValue[.checkin] = .object(detail)
        do { _ = try await coordinator.prepare(target(), ownerID: UUID()); XCTFail() } catch {}
        detail["canRefund"] = .bool(true); access.governance.overrideValue[.checkin] = .object(detail)
        access.governance.permissionValue = value(#"{"active":true,"club":{"id":81},"roleCodes":["CLUB_OPERATOR"],"permissions":["club:member:list:read"],"canManageRoles":false}"#)
        do { _ = try await coordinator.prepare(target(), ownerID: UUID()); XCTFail() } catch {}
        XCTAssertEqual(access.sent, 0)
    }
    func testMissingCanRefundAndCrossRegistrationReject() async throws {
        let (access, _, coordinator) = setup()
        for fields in [#"{"registrationId":122,"statusCode":"PENDING","railStep":0,"canRefund":true}"#, #"{"registrationId":121,"statusCode":"PENDING","railStep":0}"#] {
            access.governance.overrideValue[.checkin] = value(fields)
            do { _ = try await coordinator.prepare(target(), ownerID: UUID()); XCTFail() } catch {}
        }
        XCTAssertEqual(access.sent, 0)
    }
    func testCancelAndDismissBeforeDispatchDoNotAcquireLock() async throws {
        let (access, locks, coordinator) = setup(), target = try target(), owner = UUID()
        let review = try await coordinator.prepare(target, ownerID: owner); coordinator.cancel(review); await coordinator.confirm(review)
        let second = try await coordinator.prepare(target, ownerID: owner); coordinator.leave(ownerID: owner); await coordinator.confirm(second)
        XCTAssertEqual(access.sent, 0); XCTAssertTrue(locks.values.isEmpty)
    }
    func testChangedReviewFactsPreventDispatch() async throws {
        let (access, locks, coordinator) = setup(), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID())
        var detail = access.governance.overrideValue[.checkin]!.object!; detail["ticketText"] = .string("Changed ticket"); access.governance.overrideValue[.checkin] = .object(detail)
        await coordinator.confirm(review); XCTAssertEqual(access.sent, 0); XCTAssertTrue(locks.values.isEmpty)
        XCTAssertEqual(coordinator.state(target).failure, .stale)
    }
    func testExpiredReviewPreventsDispatch() async throws {
        let access = ClubOwnerRefundFixtureAccess(), locks = ClubOwnerRefundMemoryLocks(); var now = Date(timeIntervalSince1970: 1000)
        let coordinator = ClubOwnerRefundCoordinator(access: access, locks: locks, now: { now }), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); now.addTimeInterval(121)
        await coordinator.confirm(review); XCTAssertEqual(access.sent, 0); XCTAssertTrue(locks.values.isEmpty)
    }
    func testSameAccountEpochChangeAndPermissionRevocationPreventDispatch() async throws {
        let (access, locks, coordinator) = setup(), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); access.identity = .init(accountID: 701, epoch: 2)
        await coordinator.confirm(review); XCTAssertEqual(access.sent, 0)
        let second = try await coordinator.prepare(target, ownerID: UUID()); access.markRefundRecorded()
        await coordinator.confirm(second); XCTAssertEqual(access.sent, 0); XCTAssertTrue(locks.values.isEmpty)
    }
    func testDismissDuringFreshPreflightPreventsDispatch() async throws {
        let (access, locks, coordinator) = setup(), target = try target(), owner = UUID()
        let review = try await coordinator.prepare(target, ownerID: owner)
        access.onEvidence = { coordinator.leave(ownerID: owner) }
        await coordinator.confirm(review); XCTAssertEqual(access.sent, 0); XCTAssertTrue(locks.values.isEmpty)
    }
    func testRepeatedConfirmIsAtMostOneSend() async throws {
        let (access, locks, coordinator) = setup(), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID())
        await coordinator.confirm(review); await coordinator.confirm(review)
        XCTAssertEqual(access.sent, 1); XCTAssertEqual(locks.values.count, 2)
    }
    func testUnknownOutcomeRemainsLockedWhenReadbackStillPending() async throws {
        let (access, locks, coordinator) = setup(.unknown), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        XCTAssertEqual(coordinator.state(target).phase, .outcomeUnknown); XCTAssertEqual(locks.values.count, 2)
        await coordinator.reconcile(target); XCTAssertEqual(access.sent, 1)
        do { _ = try await coordinator.prepare(target, ownerID: UUID()); XCTFail() } catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .locked) }
    }
    func testRefundedReadbackDoesNotInventCashReceiptOrUnlock() async throws {
        let (access, locks, coordinator) = setup(.unknown), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        access.markRefundRecorded(); await coordinator.reconcile(target)
        XCTAssertEqual(coordinator.state(target).phase, .refundRecorded); XCTAssertNil(coordinator.state(target).receipt)
        XCTAssertEqual(locks.values.count, 2); XCTAssertEqual(access.sent, 1)
    }
    func testAcknowledgedCashProcessingIsNotPayoutSuccess() async throws {
        let (_, locks, coordinator) = setup(), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        XCTAssertEqual(coordinator.state(target).phase, .acknowledged)
        XCTAssertEqual(coordinator.state(target).receipt?.cash, .processing)
        XCTAssertEqual(coordinator.state(target).receipt?.cancellation, .cancelled); XCTAssertEqual(locks.values.count, 2)
    }
    func testManualReviewMissingPointsRemainsUnknown() async throws {
        let (_, locks, coordinator) = setup(.manual), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        XCTAssertEqual(coordinator.state(target).phase, .manualReview)
        XCTAssertEqual(coordinator.state(target).receipt?.points, .unconfirmed); XCTAssertEqual(locks.values.count, 2)
    }
    func testEveryDispatchedNonSuccessRetainsBothLocks() async throws {
        for scenario in [ClubOwnerRefundFixtureAccess.Scenario.httpFailure, .httpTimeout, .businessTimeout, .malformed] {
            let (access, locks, coordinator) = setup(scenario), target = try target()
            let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
            XCTAssertEqual(coordinator.state(target).phase, .outcomeUnknown)
            XCTAssertEqual(locks.values.count, 2); XCTAssertNotNil(coordinator.state(target).failure?.message)
            do { _ = try await coordinator.prepare(target, ownerID: UUID()); XCTFail() }
            catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .locked) }
            XCTAssertEqual(access.sent, 1)
        }
    }
    func testLockStorageFailurePreventsSend() async throws {
        let (access, locks, coordinator) = setup(), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); locks.failWrites = true; await coordinator.confirm(review)
        XCTAssertEqual(access.sent, 0); XCTAssertEqual(coordinator.state(target).failure, .storage)
    }
    func testUnknownLockSurvivesSameAccountReloginAndCoordinatorReplacement() async throws {
        let (access, locks, coordinator) = setup(.unknown), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        access.identity = .init(accountID: 701, epoch: 2)
        let replacement = ClubOwnerRefundCoordinator(access: access, locks: locks)
        XCTAssertEqual(replacement.state(target).phase, .outcomeUnknown)
        do { _ = try await replacement.prepare(target, ownerID: UUID()); XCTFail() } catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .locked) }
    }
    func testLocksDoNotExposePreviousAccountReceipt() async throws {
        let (access, _, coordinator) = setup(), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        access.identity = .init(accountID: 799, epoch: 2)
        XCTAssertEqual(coordinator.state(target).phase, .idle); XCTAssertNil(coordinator.state(target).receipt)
    }
    func testReadbackFailureDoesNotEraseAcknowledgedReceipt() async throws {
        let (access, _, coordinator) = setup(), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        access.governance.readFailure = .rejected(code: 503, message: nil); await coordinator.reconcile(target)
        XCTAssertEqual(coordinator.state(target).receipt?.cash, .processing); XCTAssertTrue(coordinator.state(target).readbackUnavailable)
    }
    func testMalformedCrossTargetAndContradictoryReceiptsAreUnknown() {
        for text in [#"{"registrationId":999,"cancellationStatus":"CANCELLED","cashRefundStatus":"SUCCESS","pointsRefundStatus":"RETURNED"}"#, #"{"registrationId":121,"cancellationStatus":"MANUAL_REVIEW","cashRefundStatus":"SUCCESS"}"#, #"{"registrationId":121,"cancellationStatus":"CANCELLED","cashRefundStatus":"FUTURE_STATUS","pointsRefundStatus":"RETURNED"}"#] {
            XCTAssertThrowsError(try ClubOwnerRefundReceipt(value: value(text), message: nil, registrationID: 121))
        }
    }
    func testHTTPServerFailureCannotBeMisclassifiedAsDefiniteRejection() async throws {
        let service = ClubOwnerRefundService(offlineConfiguration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!), offlineTransport: ClubOwnerRefundFixtureTransport(status: 503, body: #"{"code":403}"#))
        do { _ = try await service.cancel(registrationID: 121, token: "synthetic") {}; XCTFail() }
        catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .unconfirmed(message: nil)) }
    }
    private func useRegistration(_ access: ClubOwnerRefundFixtureAccess, id: Int, orderNo: String?) {
        var detail = access.governance.overrideValue[.checkin]!.object!
        detail["registrationId"] = .integer(id); detail["orderNo"] = orderNo.map(ClubGovernanceValue.string) ?? .null
        access.governance.overrideValue[.checkin] = .object(detail)
    }
    func testSiblingSameParentCannotReplayAfterUnknownOrAcknowledgedAcrossRestore() async throws {
        for scenario in [ClubOwnerRefundFixtureAccess.Scenario.unknown, .accepted] {
            let (access, locks, coordinator) = setup(scenario), first = try target()
            useRegistration(access, id: 121, orderNo: "SAME-PARENT")
            let review = try await coordinator.prepare(first, ownerID: UUID()); await coordinator.confirm(review)
            useRegistration(access, id: 122, orderNo: "SAME-PARENT")
            let sibling = try ClubOwnerRefundTarget(clubID: 81, registrationID: 122)
            let restored = ClubOwnerRefundCoordinator(access: access, locks: locks)
            do { _ = try await restored.prepare(sibling, ownerID: UUID()); XCTFail() }
            catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .locked) }
            XCTAssertEqual(restored.state(sibling).phase, .outcomeUnknown)
            XCTAssertEqual(access.sent, 1); XCTAssertEqual(locks.values.count, 2)
            XCTAssertFalse(locks.values.contains { $0.contains("SAME-PARENT") })
        }
    }
    func testSiblingPreparedBeforeFirstDispatchIsBlockedAtFreshPreflight() async throws {
        let (access, locks, coordinator) = setup(.unknown)
        useRegistration(access, id: 121, orderNo: "SHARED")
        let first = try await coordinator.prepare(target(), ownerID: UUID())
        useRegistration(access, id: 122, orderNo: "SHARED")
        let siblingTarget = try ClubOwnerRefundTarget(clubID: 81, registrationID: 122)
        let sibling = try await coordinator.prepare(siblingTarget, ownerID: UUID())
        useRegistration(access, id: 121, orderNo: "SHARED"); await coordinator.confirm(first)
        useRegistration(access, id: 122, orderNo: "SHARED"); await coordinator.confirm(sibling)
        XCTAssertEqual(access.sent, 1); XCTAssertEqual(locks.values.count, 2)
        XCTAssertEqual(coordinator.state(siblingTarget).phase, .outcomeUnknown)
    }
    func testCancellationInsideLockAcquisitionKeepsBothLocksAndNeverSends() async throws {
        let (access, locks, coordinator) = setup(), target = try target(), owner = UUID()
        let review = try await coordinator.prepare(target, ownerID: owner)
        locks.onAcquire = { coordinator.leave(ownerID: owner) }
        await coordinator.confirm(review)
        XCTAssertEqual(access.sent, 0); XCTAssertEqual(locks.values.count, 2)
        XCTAssertEqual(coordinator.state(target).phase, .outcomeUnknown)
        await coordinator.confirm(review); XCTAssertEqual(access.sent, 0)
    }
    func testPartialAcquisitionRetainsRegistrationLockWithoutDispatch() async throws {
        let (access, locks, coordinator) = setup(), target = try target()
        let review = try await coordinator.prepare(target, ownerID: UUID()); locks.failAfterAcquisitions = 1
        await coordinator.confirm(review)
        XCTAssertEqual(access.sent, 0); XCTAssertEqual(locks.values.count, 1)
        let restored = ClubOwnerRefundCoordinator(access: access, locks: locks)
        do { _ = try await restored.prepare(target, ownerID: UUID()); XCTFail() }
        catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .locked) }
    }
    func testMissingOrBlankParentDoesNotInventSiblingGrouping() async throws {
        for orderNo in [nil, "", "   ", "\t\r\n", "\u{0000}\u{001F}"] as [String?] {
            let (access, locks, coordinator) = setup(.unknown), target = try target()
            useRegistration(access, id: 121, orderNo: orderNo)
            let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
            XCTAssertEqual(locks.values.count, 1)
            useRegistration(access, id: 122, orderNo: orderNo)
            let sibling = try ClubOwnerRefundTarget(clubID: 81, registrationID: 122)
            _ = try await coordinator.prepare(sibling, ownerID: UUID())
            XCTAssertEqual(access.sent, 1)
        }
    }
    func testLaterMissingParentReadbackCannotEraseKnownSiblingLock() async throws {
        let (access, locks, coordinator) = setup(.unknown)
        useRegistration(access, id: 121, orderNo: "KNOWN")
        let review = try await coordinator.prepare(target(), ownerID: UUID()); await coordinator.confirm(review)
        useRegistration(access, id: 122, orderNo: "KNOWN")
        let sibling = try ClubOwnerRefundTarget(clubID: 81, registrationID: 122)
        do { _ = try await coordinator.prepare(sibling, ownerID: UUID()); XCTFail() } catch {}
        useRegistration(access, id: 122, orderNo: nil); await coordinator.reconcile(sibling)
        do { _ = try await coordinator.prepare(sibling, ownerID: UUID()); XCTFail() }
        catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .locked) }
        XCTAssertEqual(access.sent, 1); XCTAssertEqual(locks.values.count, 2)
    }
    func testUnicodeWhitespaceParentUsesExactBackendGroupingRatherThanSwiftTrim() async throws {
        let (access, locks, coordinator) = setup(.unknown)
        useRegistration(access, id: 121, orderNo: " \u{00A0}\u{2003} ")
        let review = try await coordinator.prepare(target(), ownerID: UUID())
        await coordinator.confirm(review)
        XCTAssertEqual(locks.values.count, 2)
        useRegistration(access, id: 122, orderNo: " \u{00A0}\u{2003} ")
        let sibling = try ClubOwnerRefundTarget(clubID: 81, registrationID: 122)
        let restored = ClubOwnerRefundCoordinator(access: access, locks: locks)
        do { _ = try await restored.prepare(sibling, ownerID: UUID()); XCTFail() }
        catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .locked) }
        XCTAssertEqual(access.sent, 1)
    }
    func testParentGroupingUsesExactNonemptySourceBytes() async throws {
        let (access, _, coordinator) = setup(.unknown), target = try target()
        useRegistration(access, id: 121, orderNo: "PARENT")
        let review = try await coordinator.prepare(target, ownerID: UUID()); await coordinator.confirm(review)
        useRegistration(access, id: 122, orderNo: " PARENT ")
        _ = try await coordinator.prepare(ClubOwnerRefundTarget(clubID: 81, registrationID: 122), ownerID: UUID())
        XCTAssertEqual(access.sent, 1)
    }
    func testHTTP408Business408HTTP499AndMalformedResponsesStayUnconfirmed() async throws {
        for (status, body, message) in [(408, #"{"code":408,"msg":"Timed out"}"#, "Timed out" as String?), (200, #"{"code":408,"msg":"Business timeout"}"#, "Business timeout"), (499, #"{"code":499}"#, nil), (200, #"{"code":200,"msg":"Incomplete","data":{}}"#, "Incomplete"), (200, "not-json", nil)] {
            let service = ClubOwnerRefundService(offlineConfiguration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!), offlineTransport: ClubOwnerRefundFixtureTransport(status: status, body: body))
            do { _ = try await service.cancel(registrationID: 121, token: "synthetic") {}; XCTFail() }
            catch { XCTAssertEqual(error as? ClubOwnerRefundFailure, .unconfirmed(message: message)) }
        }
    }
    func testCancelledReadbackDoesNotLeaveRetainedCoordinatorBusy() async throws {
        let (access, _, coordinator) = setup(), target = try target()
        let started = expectation(description: "Readback started")
        access.onEvidence = { started.fulfill() }
        access.beforeEvidence = { try? await Task.sleep(nanoseconds: 10_000_000_000) }
        let task = Task { await coordinator.reconcile(target) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel(); await task.value
        XCTAssertFalse(coordinator.state(target).readbackLoading)
    }
    func testFileLockPersistsAcrossNewInstancesAndCorruptContents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ClubOwnerRefundFileLocks(directory: directory); try first.acquire("synthetic-lock")
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("partial".utf8).write(to: file)
        let second = ClubOwnerRefundFileLocks(directory: directory); XCTAssertTrue(try second.contains("synthetic-lock"))
        XCTAssertThrowsError(try second.acquire("synthetic-lock"))
        XCTAssertFalse(file.lastPathComponent.contains("synthetic-lock"))
    }
}
