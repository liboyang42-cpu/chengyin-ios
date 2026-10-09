import XCTest
@testable import Questify

@MainActor final class MerchantOperatorInvitationReceiptTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "fixture://merchant", accountID: 9001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = true
        var accessCount = 0, executeCount = 0, snapshotCount = 0
        var holdAccess = false, failAccess = false, invalidExpiry = false
        var freshAccess: MerchantBusinessAccess?
        var executeError: Error?, accessError: Error?
        var continuation: CheckedContinuation<Void, Never>?
        static let token = String(repeating: "A", count: 43)
        static func accessValue(merchantID: Int = 610, role: String = "MERCHANT_OWNER", manage: Bool = true, name: String = "Synthetic workshop") throws -> MerchantBusinessAccess {
            var value = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!
            value["merchant"] = .object(["id": .int(merchantID), "name": .string(name)])
            value["roleCode"] = .string(role); value["canManageOperators"] = .bool(manage)
            if !manage { value["permissions"] = .array(value["permissions"]!.array!.filter { $0.string != "merchant:operator:manage" }) }
            return try .init(value)
        }
        func access() async throws -> MerchantBusinessAccess {
            accessCount += 1
            if holdAccess { await withCheckedContinuation { continuation = $0 } }
            if let accessError { throw accessError }
            if failAccess { throw URLError(.notConnectedToInternet) }
            return try freshAccess ?? Self.accessValue()
        }
        func resume() { let pending = continuation; continuation = nil; holdAccess = false; pending?.resume() }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            snapshotCount += 1
            return .init(access: try Self.accessValue(),
                         document: try .init(query: .operators, payload: MerchantBusinessSyntheticFixtures.payload(.operators)),
                         roles: try .init(query: .roles, payload: MerchantBusinessSyntheticFixtures.payload(.roles)))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            executeCount += 1
            if let executeError { throw executeError }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 28_800); formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxx"
            let expiry = formatter.string(from: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 3_600))
            return try .init(mutation: mutation, message: nil, data: .object([
                "invite": .object(["id": .int(68000 + executeCount), "roleCode": .string("MERCHANT_CHECKIN"), "status": .string("PENDING"),
                                   "version": .int(0), "expiresAt": .string(invalidExpiry ? "unrecognized" : expiry)]), "token": .string(Self.token)]))
        }
    }
    @MainActor private final class Clock {
        var now = Date(), uptime = ProcessInfo.processInfo.systemUptime
        func reset() { now = Date(); uptime = ProcessInfo.processInfo.systemUptime }
    }
    @MainActor private final class Harness {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore(), clock = Clock()
        let owner: MerchantBusinessViewModel
        init() { owner = .init(reader: reader, journal: journal) }
        func create() async throws -> MerchantOperatorInvitationReceiptModel {
            await owner.load(.operators); owner.prepare(.inviteOperator(role: "MERCHANT_CHECKIN"))
            await owner.confirm(try XCTUnwrap(owner.coordinator.confirmation))
            let presentation = try XCTUnwrap(owner.coordinator.operatorInvitation)
            clock.reset()
            return .init(owner: owner, presentationID: presentation.id, now: { [clock] in clock.now }, uptime: { [clock] in clock.uptime })
        }
    }
    private func waitUntilHeld(_ reader: Reader) async throws {
        for _ in 0..<100 { if reader.continuation != nil { return }; await Task.yield() }
        XCTFail("Synthetic fresh access did not suspend")
        throw MerchantBusinessFailure.stale
    }
    func testInitialReceiptAndTimerNeverReadOrRevealAutomatically() async throws {
        let h = Harness(), model = try await h.create()
        XCTAssertNil(model.visibleCode); XCTAssertFalse(model.revealed)
        model.tick(); model.tick()
        XCTAssertEqual(h.reader.accessCount, 0); XCTAssertEqual(h.reader.executeCount, 1)
        XCTAssertEqual(model.metadata?.merchantID, 610); XCTAssertEqual(model.metadata?.roleCode, "MERCHANT_CHECKIN")
    }
    func testExplicitRevealChecksFreshAccessAndReturnsExactReceivedCode() async throws {
        let h = Harness(), model = try await h.create()
        let result = await model.reveal()
        XCTAssertTrue(result); XCTAssertEqual(model.visibleCode, Reader.token)
        XCTAssertEqual(h.reader.accessCount, 1); XCTAssertEqual(h.reader.executeCount, 1)
        XCTAssertTrue(try h.journal.intents().isEmpty)
    }
    func testHideThenRevealRequiresAnotherExplicitFreshRead() async throws {
        let h = Harness(), model = try await h.create(); _ = await model.reveal()
        model.hide(); XCTAssertNil(model.visibleCode); model.tick(); XCTAssertEqual(h.reader.accessCount, 1)
        let result = await model.reveal(); XCTAssertTrue(result); XCTAssertEqual(h.reader.accessCount, 2)
        XCTAssertEqual(h.reader.executeCount, 1)
    }
    func testFailedReadKeepsCodeHiddenAndDoesNotAutomaticallyRetry() async throws {
        let h = Harness(), model = try await h.create(); h.reader.failAccess = true
        let result = await model.reveal(); XCTAssertFalse(result); XCTAssertNil(model.visibleCode)
        XCTAssertEqual(model.issue, "merchant.operatorInvite.accessFailed"); model.tick(); model.tick()
        XCTAssertEqual(h.reader.accessCount, 1); XCTAssertNotNil(h.owner.coordinator.receipt)
        h.reader.failAccess = false
        let retry = await model.reveal(); XCTAssertTrue(retry); XCTAssertEqual(h.reader.accessCount, 2)
        XCTAssertEqual(h.reader.executeCount, 1)
    }
    func testChangedStoreRolePermissionOrExactStoreNameDeniesReveal() async throws {
        let changes = [try Reader.accessValue(merchantID: 611), try Reader.accessValue(role: "MERCHANT_MANAGER"),
                       try Reader.accessValue(manage: false), try Reader.accessValue(name: "Changed store")]
        for access in changes {
            let h = Harness(), model = try await h.create(); h.reader.freshAccess = access
            let result = await model.reveal(); XCTAssertFalse(result); XCTAssertNil(model.visibleCode)
            XCTAssertFalse(model.active); XCTAssertNil(h.owner.coordinator.receipt); XCTAssertEqual(h.reader.executeCount, 1)
        }
    }
    func testPreReadRetirementDeniesAnyNewRead() async throws {
        let h = Harness(), model = try await h.create(); model.retire()
        let result = await model.reveal(); XCTAssertFalse(result); XCTAssertEqual(h.reader.accessCount, 0)
        XCTAssertNil(h.owner.coordinator.receipt); XCTAssertTrue(try h.journal.intents().isEmpty)
    }
    func testChangedAccountBeforeRevealPreventsRead() async throws {
        let h = Harness(), model = try await h.create()
        h.reader.scope = .init(realm: "fixture://merchant", accountID: 9002, epoch: 1)
        let result = await model.reveal(); XCTAssertFalse(result); XCTAssertEqual(h.reader.accessCount, 0)
        XCTAssertNil(h.owner.coordinator.receipt)
    }
    func testSuspendedReadRetiredByBackgroundCannotRevealOrRetry() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        model.retire(); h.reader.resume()
        let result = await task.value; XCTAssertFalse(result); XCTAssertNil(model.visibleCode)
        XCTAssertFalse(model.active); XCTAssertNil(h.owner.coordinator.receipt); XCTAssertEqual(h.reader.accessCount, 1)
        XCTAssertEqual(h.reader.executeCount, 1); XCTAssertTrue(try h.journal.intents().isEmpty)
    }
    func testSuspendedReadOwnerChangeWithoutManualRetirementCannotReveal() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        h.reader.scope = .init(realm: "fixture://merchant", accountID: 9001, epoch: 2); h.reader.resume()
        let result = await task.value; XCTAssertFalse(result); XCTAssertNil(model.visibleCode)
        XCTAssertNil(h.owner.coordinator.receipt); XCTAssertEqual(h.reader.executeCount, 1)
    }
    func testSuspendedReadAuthorizationChangeCannotReveal() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        h.reader.authorizationGeneration = UUID(); h.reader.resume()
        let result = await task.value; XCTAssertFalse(result); XCTAssertNil(model.visibleCode)
        XCTAssertNil(h.owner.coordinator.receipt)
    }
    func testSuspendedReadRoleLossCannotReveal() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        h.reader.freshAccess = try Reader.accessValue(role: "MERCHANT_CHECKIN", manage: false); h.reader.resume()
        let result = await task.value; XCTAssertFalse(result); XCTAssertNil(model.visibleCode); XCTAssertNil(h.owner.coordinator.receipt)
    }
    func testSuspendedReadExpiryCannotRevealAndClearsOriginalReceipt() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        h.clock.now = try XCTUnwrap(model.metadata?.expiresAt); h.reader.resume()
        let result = await task.value; XCTAssertFalse(result); XCTAssertNil(model.visibleCode)
        XCTAssertNil(h.owner.coordinator.receipt)
    }
    func testSuspendedReadReplacedReceiptCannotRevealOrClearNewerReceipt() async throws {
        let h = Harness(), old = try await h.create(); h.reader.holdAccess = true
        let task = Task { await old.reveal() }; try await waitUntilHeld(h.reader)
        let newer = try await h.create(); let id = try XCTUnwrap(h.owner.coordinator.operatorInvitation).id
        h.reader.resume(); let result = await task.value
        XCTAssertFalse(result); XCTAssertNil(old.visibleCode); XCTAssertNotNil(h.owner.coordinator.receipt)
        XCTAssertEqual(h.owner.coordinator.operatorInvitation?.id, id)
        let newResult = await newer.reveal(); XCTAssertTrue(newResult); XCTAssertEqual(newer.visibleCode, Reader.token)
        XCTAssertEqual(h.reader.executeCount, 2)
    }
    func testHideCancelsHeldRevealWithoutRetiringOriginalReceipt() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        model.hide(); h.reader.resume(); let result = await task.value
        XCTAssertFalse(result); XCTAssertNil(model.visibleCode); XCTAssertTrue(model.active); XCTAssertNotNil(h.owner.coordinator.receipt)
    }
    func testConcurrentRevealDoesNotDuplicateFreshRead() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        let duplicate = await model.reveal(); XCTAssertFalse(duplicate); XCTAssertEqual(h.reader.accessCount, 1)
        h.reader.resume(); let result = await task.value; XCTAssertTrue(result)
    }
    func testCancelledHeldReadCannotReveal() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        task.cancel(); h.reader.resume(); let result = await task.value
        XCTAssertFalse(result); XCTAssertNil(model.visibleCode); XCTAssertNil(h.owner.coordinator.receipt)
    }
    func testExpiredTickThenDepartureClearsRawReceipt() async throws {
        let h = Harness(), model = try await h.create(); _ = await model.reveal()
        h.clock.now = try XCTUnwrap(model.metadata?.expiresAt); model.tick(); model.retire()
        XCTAssertNil(model.visibleCode); XCTAssertNil(h.owner.coordinator.receipt); XCTAssertNil(h.owner.coordinator.operatorInvitation)
        XCTAssertEqual(h.reader.executeCount, 1)
    }
    func testInvalidAcknowledgedExpiryIsNotAFailedCreateAndStillClearsOnDeparture() async throws {
        let h = Harness(); h.reader.invalidExpiry = true; let model = try await h.create()
        XCTAssertNotNil(h.owner.coordinator.receipt); XCTAssertFalse(try XCTUnwrap(model.metadata).hasValidReceipt)
        XCTAssertFalse(h.owner.coordinator.isLocked); XCTAssertFalse(model.canReveal); XCTAssertTrue(try h.journal.intents().isEmpty)
        model.retire(); XCTAssertNil(h.owner.coordinator.receipt); XCTAssertEqual(h.reader.accessCount, 0)
    }
    func testInvalidReceiptHasNoUnboundedRawTokenLifetime() async throws {
        let h = Harness(); h.reader.invalidExpiry = true; let model = try await h.create()
        h.clock.uptime += 601; model.tick()
        XCTAssertFalse(model.active); XCTAssertNil(h.owner.coordinator.receipt)
    }
    func testRetiredOldModelCannotReviveAfterSameOwnerReturnOrClearNewReceipt() async throws {
        let h = Harness(), old = try await h.create(); old.retire()
        let newer = try await h.create(); let id = newer.presentationID
        let result = await old.reveal(); XCTAssertFalse(result); old.tick(); old.retire()
        XCTAssertEqual(h.owner.coordinator.operatorInvitation?.id, id); XCTAssertNotNil(h.owner.coordinator.receipt)
        XCTAssertEqual(h.reader.accessCount, 0)
    }
    func testCurrentGrantLossImmediatelyHidesAlreadyRevealedCode() async throws {
        let h = Harness(), model = try await h.create(); _ = await model.reveal()
        h.reader.canExecuteSyntheticMutation = false; XCTAssertNil(model.visibleCode); model.tick()
        XCTAssertNil(h.owner.coordinator.receipt); XCTAssertEqual(h.reader.accessCount, 1)
    }
    func testOldReceiptRetirementCannotReconcileNewUnknownWrite() async throws {
        let h = Harness(), old = try await h.create()
        await h.owner.load(.operators); h.owner.prepare(.inviteOperator(role: "MERCHANT_CHECKIN"))
        h.reader.executeError = URLError(.networkConnectionLost)
        await h.owner.confirm(try XCTUnwrap(h.owner.coordinator.confirmation))
        let intents = try h.journal.intents(); XCTAssertEqual(intents.count, 1); XCTAssertTrue(h.owner.coordinator.isLocked)
        old.retire(); old.tick()
        XCTAssertEqual(try h.journal.intents(), intents); XCTAssertTrue(h.owner.coordinator.isLocked)
        XCTAssertNil(h.owner.coordinator.operatorInvitation); XCTAssertEqual(h.reader.executeCount, 2)
    }
    func testSuspendedDefiniteAccessLossWithUnchangedScopePermanentlyRetiresOldReceipt() async throws {
        let failures: [Error] = [MerchantBusinessFailure.denied, MerchantBusinessFailure.stale, MerchantBusinessFailure.disabled,
                                 APIError.unauthorized, APIError.notConfigured, CancellationError()]
        for error in failures {
            let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
            let originalScope = h.reader.scope, originalAuthorization = h.reader.authorizationGeneration
            let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
            h.reader.accessError = error; h.reader.resume(); let result = await task.value
            XCTAssertFalse(result); XCTAssertFalse(model.active); XCTAssertNil(model.visibleCode)
            XCTAssertNil(h.owner.coordinator.receipt); XCTAssertNil(h.owner.coordinator.operatorInvitation)
            XCTAssertEqual(h.reader.scope, originalScope); XCTAssertEqual(h.reader.authorizationGeneration, originalAuthorization)
            XCTAssertTrue(h.reader.canExecuteSyntheticMutation); XCTAssertTrue(try h.journal.intents().isEmpty)
            h.reader.accessError = nil
            let restored = await model.reveal(); XCTAssertFalse(restored); XCTAssertEqual(h.reader.accessCount, 1)
            XCTAssertEqual(h.reader.executeCount, 1)
        }
    }
    func testCancelledSuspendedReadWithNetworkErrorRetiresInsteadOfOfferingRetry() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        task.cancel(); h.reader.failAccess = true; h.reader.resume(); let result = await task.value
        XCTAssertFalse(result); XCTAssertFalse(model.active); XCTAssertNil(h.owner.coordinator.receipt)
        h.reader.failAccess = false
        let restored = await model.reveal(); XCTAssertFalse(restored); XCTAssertEqual(h.reader.accessCount, 1)
    }
    func testContextLossWhileFailedReadIsSuspendedCannotReviveAfterReturn() async throws {
        let h = Harness(), model = try await h.create(); h.reader.holdAccess = true
        let original = h.reader.scope
        let task = Task { await model.reveal() }; try await waitUntilHeld(h.reader)
        h.reader.scope = .init(realm: "fixture://merchant", accountID: 9002, epoch: 1)
        h.reader.failAccess = true; h.reader.resume(); let result = await task.value
        XCTAssertFalse(result); XCTAssertFalse(model.active); XCTAssertNil(h.owner.coordinator.receipt)
        h.reader.scope = original; h.reader.failAccess = false
        let restored = await model.reveal(); XCTAssertFalse(restored); XCTAssertEqual(h.reader.accessCount, 1)
    }
}
