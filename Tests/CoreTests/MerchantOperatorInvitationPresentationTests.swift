import XCTest
@testable import QuestifyCore

private enum InvitationReceiptFixture {
    static let now = Date(timeIntervalSince1970: 1_791_511_200) // Synthetic clock; tests derive expiry from it.
    static let token = String(repeating: "A", count: 43)
    static let role = "MERCHANT_CHECKIN"
    static func expiry(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 28_800); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSxxx"
        return f.string(from: date)
    }
    static func snapshot() throws -> MerchantBusinessSnapshot {
        .init(access: try .init(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!),
              document: try .init(query: .operators, payload: MerchantBusinessSyntheticFixtures.payload(.operators)),
              roles: try .init(query: .roles, payload: MerchantBusinessSyntheticFixtures.payload(.roles)))
    }
    static func review(scope: MerchantBusinessScope = .init(realm: "fixture://merchant", accountID: 9001, epoch: 1),
                       authorization: UUID? = nil, role: String = InvitationReceiptFixture.role) throws -> MerchantBusinessConfirmation {
        let mutation = MerchantBusinessMutation.inviteOperator(role: role)
        return .init(id: UUID(), authorizationGeneration: authorization, journalRealm: scope.realm, mutation: mutation,
                     requestID: "fixture-invite", request: try mutation.request(requestID: "fixture-invite"), scope: scope, baseline: try snapshot())
    }
    static func data(now: Date = InvitationReceiptFixture.now, token: String = InvitationReceiptFixture.token, fields: MerchantBusinessObject = [:]) -> MerchantBusinessValue {
        let invite: MerchantBusinessObject = ["id": .int(68002), "roleCode": .string(role), "status": .string("PENDING"),
            "version": .int(0), "expiresAt": .string(expiry(Date(timeIntervalSince1970: floor(now.timeIntervalSince1970) + 3_600)))]
        return .object(["invite": .object(invite.merging(fields) { _, new in new }), "token": .string(token)])
    }
    static func receipt(now: Date = InvitationReceiptFixture.now, token: String = InvitationReceiptFixture.token, fields: MerchantBusinessObject = [:]) throws -> MerchantBusinessReceipt {
        try .init(mutation: .inviteOperator(role: role), message: nil, data: data(now: now, token: token, fields: fields))
    }
}

@MainActor private final class InvitationReceiptReader: MerchantBusinessReading {
    var scope: MerchantBusinessScope? = .init(realm: "fixture://merchant", accountID: 9001, epoch: 1)
    var authorizationGeneration: UUID? = UUID()
    var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = true
    var executeCount = 0, readCount = 0
    var error: Error?, changeScopeDuringExecute = false
    var response: MerchantBusinessReceipt?
    func access() async throws -> MerchantBusinessAccess { try InvitationReceiptFixture.snapshot().access }
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot { readCount += 1; return try InvitationReceiptFixture.snapshot() }
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
        executeCount += 1
        if changeScopeDuringExecute { self.scope = .init(realm: scope.realm, accountID: scope.accountID, epoch: scope.epoch + 1) }
        if let error { throw error }
        return try response ?? InvitationReceiptFixture.receipt(now: Date())
    }
}
@MainActor private final class InvitationFailingCompletionJournal: MerchantBusinessIntentStore {
    let memory = MerchantBusinessMemoryIntentStore()
    func intents() throws -> [MerchantBusinessIntent] { try memory.intents() }
    func reserve(_ intent: MerchantBusinessIntent) throws { try memory.reserve(intent) }
    func complete(_ intent: MerchantBusinessIntent) throws { throw MerchantBusinessFailure.journal }
}

@MainActor final class MerchantOperatorInvitationPresentationTests: XCTestCase {
    private let now = InvitationReceiptFixture.now
    private func value(token: String = InvitationReceiptFixture.token, fields: MerchantBusinessObject = [:]) throws -> MerchantOperatorInvitationPresentation {
        .init(receipt: try InvitationReceiptFixture.receipt(token: token, fields: fields), review: try InvitationReceiptFixture.review(), now: now, uptime: 100)
    }
    func testExactSourceWireExpiryAndTokenAreAccepted() throws {
        let p = try value(); XCTAssertTrue(p.hasValidReceipt); XCTAssertEqual(p.inviteID, 68002)
        XCTAssertEqual(p.merchantID, 610); XCTAssertEqual(p.roleCode, "MERCHANT_CHECKIN"); XCTAssertEqual(p.remainingSeconds(now: now, uptime: 100), 600)
    }
    func testStrictExpiryRejectsLocalUTCAlternativeMalformedAndImpossibleDates() {
        for raw in ["2026-10-10 09:30:00", "2026-10-10T09:30:00", "2026-10-10T01:30:00.000Z", "2026-10-10T09:30:00.000+00:00", "2026-10-10T09:30:00.001+08:00", "2026-02-30T09:30:00.000+08:00", "2026-10-10T24:00:00.000+08:00", " 2026-10-10T09:30:00.000+08:00"] {
            XCTAssertNil(MerchantOperatorInvitationPresentation.parseExpiry(raw), raw)
        }
    }
    func testPhoneTimeZoneDoesNotReinterpretSourceExpiry() throws {
        let original = NSTimeZone.default; defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(secondsFromGMT: -7 * 3_600)!
        let actual = try XCTUnwrap(MerchantOperatorInvitationPresentation.parseExpiry("2026-10-10T09:30:00.000+08:00"))
        XCTAssertEqual(actual, ISO8601DateFormatter().date(from: "2026-10-10T01:30:00Z"))
    }
    func testExpiredEqualityAndBeyondServerMaximumFailClosed() throws {
        for delta in [-1.0, 0, 86_401] {
            XCTAssertFalse(try value(fields: ["expiresAt": .string(InvitationReceiptFixture.expiry(now.addingTimeInterval(delta)))]).hasValidReceipt)
        }
    }
    func testServerExpiryWinsOverLocalPrivacyLifetime() throws {
        let p = try value(fields: ["expiresAt": .string(InvitationReceiptFixture.expiry(now.addingTimeInterval(5)))])
        XCTAssertEqual(p.remainingSeconds(now: now.addingTimeInterval(5), uptime: 105), 0)
    }
    func testMonotonicPrivacyDeadlineCannotBeExtendedByWallClock() throws {
        let p = try value()
        XCTAssertEqual(p.remainingSeconds(now: now.addingTimeInterval(1), uptime: 700), 0)
        XCTAssertFalse(p.privacyLifetimeIsActive(now: now.addingTimeInterval(1), uptime: 700))
    }
    func testClockRollbackAndNonfiniteUptimeFailClosed() throws {
        let p = try value()
        XCTAssertEqual(p.remainingSeconds(now: now.addingTimeInterval(-1), uptime: 101), 0)
        XCTAssertEqual(p.remainingSeconds(now: now, uptime: 99), 0)
        XCTAssertEqual(p.remainingSeconds(now: now, uptime: .nan), 0)
        XCTAssertEqual(p.remainingSeconds(now: now, uptime: .infinity), 0)
    }
    func testTokenMustBeExactCanonical32ByteBase64URL() throws {
        for token in [String(repeating: "A", count: 42), String(repeating: "A", count: 44), String(repeating: "A", count: 42) + "_", String(repeating: "A", count: 42) + "=", " " + InvitationReceiptFixture.token] {
            XCTAssertFalse(try value(token: token).hasValidReceipt)
        }
    }
    func testIdentifierAndVersionCannotUseLegacyStringCoercion() throws {
        XCTAssertFalse(try value(fields: ["id": .string("68002")]).hasValidReceipt)
        XCTAssertFalse(try value(fields: ["version": .string("0")]).hasValidReceipt)
        XCTAssertFalse(try value(fields: ["version": .int(1)]).hasValidReceipt)
    }
    func testExistingReceiptValidatorRejectsWrongRoleAndNonPendingStatus() {
        for fields in ([["roleCode": .string("MERCHANT_OWNER")], ["status": .string("REVOKED")], ["id": .int(0)]] as [MerchantBusinessObject]) {
            XCTAssertThrowsError(try InvitationReceiptFixture.receipt(fields: fields))
        }
    }
    func testDifferentReviewedRoleCannotAdoptAnotherReceipt() throws {
        let p = MerchantOperatorInvitationPresentation(receipt: try InvitationReceiptFixture.receipt(), review: try InvitationReceiptFixture.review(role: "MERCHANT_MANAGER"), now: now, uptime: 100)
        XCTAssertFalse(p.hasValidReceipt)
    }
    func testDifferentReceiptCannotRevealOldToken() throws {
        let reader = InvitationReceiptReader(); reader.authorizationGeneration = nil
        let receipt = try InvitationReceiptFixture.receipt(), p = try value()
        XCTAssertEqual(p.revealedCode(reader: reader, receipt: receipt, now: now, uptime: 100), InvitationReceiptFixture.token)
        let newer = try InvitationReceiptFixture.receipt(fields: ["id": .int(68003)])
        XCTAssertNil(p.revealedCode(reader: reader, receipt: newer, now: now, uptime: 100))
    }
    func testAccountEpochRealmAuthorizationAndGrantChangesBlockReveal() throws {
        for change in 0..<6 {
            let reader = InvitationReceiptReader(); let review = try InvitationReceiptFixture.review(scope: reader.scope!, authorization: reader.authorizationGeneration)
            let receipt = try InvitationReceiptFixture.receipt(), p = MerchantOperatorInvitationPresentation(receipt: receipt, review: review, now: now, uptime: 100)
            switch change {
            case 0: reader.scope = .init(realm: "fixture://merchant", accountID: 9002, epoch: 1)
            case 1: reader.scope = .init(realm: "fixture://merchant", accountID: 9001, epoch: 2)
            case 2: reader.scope = .init(realm: "fixture://other", accountID: 9001, epoch: 1)
            case 3: reader.authorizationGeneration = UUID()
            case 4: reader.canExecuteSyntheticMutation = false
            default: reader.isConfigured = false
            }
            XCTAssertNil(p.revealedCode(reader: reader, receipt: receipt, now: now, uptime: 100))
        }
    }
    func testRetirementClearsCodeButRetainsTextFreeReceiptMatchingForCleanup() throws {
        let reader = InvitationReceiptReader(); reader.authorizationGeneration = nil
        let p = try value(), receipt = try InvitationReceiptFixture.receipt(); p.retire()
        XCTAssertNil(p.revealedCode(reader: reader, receipt: receipt, now: now, uptime: 100)); XCTAssertTrue(p.matches(receipt))
    }
    func testInvalidReceiptStillHasBoundedPrivacyLifetime() throws {
        let p = try value(fields: ["expiresAt": .string("unrecognized")])
        XCTAssertFalse(p.hasValidReceipt); XCTAssertTrue(p.privacyLifetimeIsActive(now: now, uptime: 100))
        XCTAssertFalse(p.privacyLifetimeIsActive(now: now, uptime: 700))
    }
    func testPrepareOrCancelCannotMintPresentation() async throws {
        let reader = InvitationReceiptReader(); let owner = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role))
        XCTAssertNotNil(owner.confirmation); XCTAssertNil(owner.operatorInvitation); owner.cancelConfirmation()
        XCTAssertNil(owner.operatorInvitation); XCTAssertEqual(reader.executeCount, 0)
    }
    func testAcknowledgedCurrentCreateMintsOnlyAfterJournalCompletion() async throws {
        let reader = InvitationReceiptReader(), journal = MerchantBusinessMemoryIntentStore()
        let owner = MerchantBusinessCoordinator(reader: reader, journal: journal)
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role))
        await owner.confirm(try XCTUnwrap(owner.confirmation))
        let p = try XCTUnwrap(owner.operatorInvitation)
        XCTAssertTrue(p.hasValidReceipt); XCTAssertNotNil(owner.receipt); XCTAssertFalse(owner.isLocked)
        XCTAssertEqual(reader.executeCount, 1); XCTAssertTrue(try journal.intents().isEmpty)
    }
    func testUnknownCreateOutcomeNeverMintsOrRetriesInvitation() async throws {
        let reader = InvitationReceiptReader(), journal = MerchantBusinessMemoryIntentStore(); reader.error = URLError(.networkConnectionLost)
        let owner = MerchantBusinessCoordinator(reader: reader, journal: journal)
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role)); await owner.confirm(try XCTUnwrap(owner.confirmation))
        XCTAssertNil(owner.operatorInvitation); XCTAssertNil(owner.receipt); XCTAssertTrue(owner.isLocked)
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role))
        XCTAssertNil(owner.confirmation); XCTAssertEqual(reader.executeCount, 1); XCTAssertEqual(try journal.intents().count, 1)
    }
    func testJournalCompletionFailureCannotMintPresentation() async throws {
        let reader = InvitationReceiptReader(), journal = InvitationFailingCompletionJournal()
        let owner = MerchantBusinessCoordinator(reader: reader, journal: journal)
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role)); await owner.confirm(try XCTUnwrap(owner.confirmation))
        XCTAssertNil(owner.operatorInvitation); XCTAssertNil(owner.receipt); XCTAssertTrue(owner.isLocked); XCTAssertEqual(reader.executeCount, 1)
    }
    func testOwnerChangeDuringCreateCannotPublishReceipt() async throws {
        let reader = InvitationReceiptReader(); reader.changeScopeDuringExecute = true
        let owner = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role)); await owner.confirm(try XCTUnwrap(owner.confirmation))
        XCTAssertNil(owner.operatorInvitation); XCTAssertNil(owner.receipt); XCTAssertTrue(owner.isLocked)
    }
    func testRetirementClearsOriginalRawReceiptAndOldIDCannotClearNewReceipt() async throws {
        let reader = InvitationReceiptReader(); let owner = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role)); await owner.confirm(try XCTUnwrap(owner.confirmation))
        let old = try XCTUnwrap(owner.operatorInvitation); owner.retireOperatorInvitation(id: old.id)
        XCTAssertNil(owner.receipt); XCTAssertNil(owner.operatorInvitation)
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role)); await owner.confirm(try XCTUnwrap(owner.confirmation))
        let newer = try XCTUnwrap(owner.operatorInvitation); owner.retireOperatorInvitation(id: old.id)
        XCTAssertTrue(owner.operatorInvitation === newer); XCTAssertNotNil(owner.receipt)
    }
    func testInvalidateClearsPresentationAndOriginalResponse() async throws {
        let reader = InvitationReceiptReader(); let owner = MerchantBusinessCoordinator(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role)); await owner.confirm(try XCTUnwrap(owner.confirmation))
        let id = try XCTUnwrap(owner.operatorInvitation).id; owner.invalidate()
        XCTAssertNil(owner.operatorInvitation); XCTAssertNil(owner.receipt); XCTAssertNil(owner.operatorInvitationCode(id: id))
    }
    func testOldInvitationRetirementCannotClearAcknowledgedRevokeReceipt() async throws {
        let reader = InvitationReceiptReader(), journal = MerchantBusinessMemoryIntentStore()
        let owner = MerchantBusinessCoordinator(reader: reader, journal: journal)
        await owner.load(.operators); owner.prepare(.inviteOperator(role: InvitationReceiptFixture.role)); await owner.confirm(try XCTUnwrap(owner.confirmation))
        let oldID = try XCTUnwrap(owner.operatorInvitation).id
        await owner.load(.operators)
        let mutation = MerchantBusinessMutation.revokeInvite(id: try .init(68001), version: 0, reason: "Synthetic revoke")
        reader.response = try .init(mutation: mutation, message: nil, data: .object([
            "id": .int(68001), "roleCode": .string("MERCHANT_MARKETING"), "status": .string("REVOKED"),
            "expiresAt": .string("2026-10-08 09:00:00"), "version": .int(1), "mutationState": .string("EXACT_RESULT")]))
        owner.prepare(mutation); await owner.confirm(try XCTUnwrap(owner.confirmation))
        let revokeReceipt = try XCTUnwrap(owner.receipt); XCTAssertNil(owner.operatorInvitation)
        owner.retireOperatorInvitation(id: oldID)
        XCTAssertEqual(owner.receipt, revokeReceipt); XCTAssertTrue(try journal.intents().isEmpty); XCTAssertEqual(reader.executeCount, 2)
    }
}
