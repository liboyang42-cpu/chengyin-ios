import XCTest
@testable import Questify

@MainActor private final class LedgerInboxMerchant: MerchantBusinessReading {
    var scope: MerchantBusinessScope? = .init(realm: "synthetic", accountID: 99, epoch: 1)
    var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = false
    var authorizationGeneration: UUID? = UUID()
    var value: MerchantBusinessSnapshot
    var reads = 0
    var fail = false
    var afterRead: (() -> Void)?
    init(query: MerchantBusinessQuery = .overview) throws {
        let access = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        value = try .init(access: .init(access), document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query)))
    }
    func access() async throws -> MerchantBusinessAccess { value.access }
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
        reads += 1; afterRead?(); if fail { throw MerchantBusinessFailure.malformed }; return value
    }
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt { XCTFail("No writes"); throw MerchantBusinessFailure.disabled }
}
@MainActor private final class LedgerInboxMessaging: MessagingReading {
    var isConfigured = true
    var identity: MessagingReadIdentity? = .init(accountID: 99, epoch: 1)
    var reads = 0
    func messagingConversations() async throws -> [MessagingConversation] { reads += 1; XCTFail("Gate must not read messages"); return [] }
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { reads += 1; XCTFail("Gate must not read messages"); throw APIError.invalidRequest }
}
@MainActor final class MerchantLedgerInboxNavigationTests: XCTestCase {
    private func source(_ r: LedgerInboxMerchant) throws -> MerchantLedgerInboxSource {
        try XCTUnwrap(MerchantLedgerInboxSource(reader: r, snapshot: r.value))
    }
    func testThreeLedgerSourcesOpenAfterFreshReadWithoutMessagingRequest() async throws {
        for query in [MerchantBusinessQuery.overview, .entries(source: "all", page: 1), .batches(page: 1)] {
            let r = try LedgerInboxMerchant(query: query), m = LedgerInboxMessaging(), gate = MerchantLedgerInboxGate(), s = try source(r)
            gate.activate(); await gate.open(s, currentMessaging: { m }); XCTAssertTrue(gate.permits(s,messaging:m)); XCTAssertEqual(r.reads,1); XCTAssertEqual(m.reads,0)
        }
    }
    func testNonLedgerPageDoesNotOfferEntry() throws {
        let r = try LedgerInboxMerchant(query: .operators)
        XCTAssertNil(MerchantLedgerInboxSource(reader:r,snapshot:r.value))
    }
    func testUnconfiguredMessagingDoesNotProbeMerchant() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate();m.isConfigured=false
        g.activate(); await g.open(try source(r),currentMessaging:{m});XCTAssertFalse(g.approved);XCTAssertEqual(r.reads,0)
    }
    func testAccountAndEpochMismatchReject() async throws {
        for identity in [MessagingReadIdentity(accountID:100,epoch:1),.init(accountID:99,epoch:2)] {
            let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate();m.identity=identity
            g.activate(); await g.open(try source(r),currentMessaging:{m});XCTAssertFalse(g.approved);XCTAssertEqual(r.reads,0)
        }
    }
    func testFailureRetryRereadsAndThenAllows() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r);r.fail=true
        g.activate(); await g.open(s,currentMessaging:{m});XCTAssertFalse(g.approved);r.fail=false
        g.activate(); await g.open(s,currentMessaging:{m});XCTAssertTrue(g.approved);XCTAssertEqual(r.reads,2)
    }
    func testAuthorizationChangeDuringReadRejects() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        r.afterRead={r.authorizationGeneration=UUID()};g.activate(); await g.open(s,currentMessaging:{m});XCTAssertFalse(g.approved)
    }
    func testCancellationRejectsLateApproval() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        r.afterRead={g.cancel()};g.activate(); await g.open(s,currentMessaging:{m});XCTAssertFalse(g.approved)
    }
    func testMessagingReaderReplacementRejectsEvenSameIdentity() async throws {
        let r=try LedgerInboxMerchant(),first=LedgerInboxMessaging(),second=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        var current=first;r.afterRead={current=second};g.activate(); await g.open(s,currentMessaging:{current});XCTAssertFalse(g.approved)
    }
    func testMerchantScopeSwitchDuringReadRejects() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        r.afterRead={r.scope = .init(realm:"new",accountID:99,epoch:1)};g.activate(); await g.open(s,currentMessaging:{m});XCTAssertFalse(g.approved)
    }
    func testApprovedDestinationDropsOnSessionChangeAndBackground() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        g.activate(); await g.open(s,currentMessaging:{m});m.identity=nil;XCTAssertFalse(g.permits(s,messaging:m));g.cancel();XCTAssertFalse(g.approved)
    }
    func testFreshDifferentDocumentIsRejected() async throws {
        let r=try LedgerInboxMerchant(),other=try LedgerInboxMerchant(query:.operators),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        r.value=other.value;g.activate(); await g.open(s,currentMessaging:{m});XCTAssertFalse(g.approved)
    }
    func testQueuedRetryBeforeExitCannotReadOrApprove() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        g.activate(); let permit=try XCTUnwrap(g.openingPermit()); g.deactivate()
        await g.open(s,currentMessaging:{m},permit:permit)
        XCTAssertEqual(r.reads,0); XCTAssertEqual(m.reads,0); XCTAssertFalse(g.approved); XCTAssertNil(g.openingPermit())
    }
    func testOldPermitCannotCrossForegroundReactivation() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        g.activate(); let old=try XCTUnwrap(g.openingPermit()); g.deactivate(); g.activate()
        await g.open(s,currentMessaging:{m},permit:old)
        XCTAssertEqual(r.reads,0); XCTAssertFalse(g.approved)
        let current=try XCTUnwrap(g.openingPermit())
        await g.open(s,currentMessaging:{m},permit:current)
        XCTAssertEqual(r.reads,1); XCTAssertTrue(g.permits(s,messaging:m)); XCTAssertEqual(m.reads,0)
    }
    func testBackgroundDuringFreshReadCannotApprove() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        g.activate(); let permit=try XCTUnwrap(g.openingPermit()); r.afterRead={g.deactivate()}
        await g.open(s,currentMessaging:{m},permit:permit)
        XCTAssertEqual(r.reads,1); XCTAssertFalse(g.permits(s,messaging:m)); XCTAssertFalse(g.busy)
    }
    func testDuplicateAppearanceDoesNotInvalidateCurrentPermit() async throws {
        let r=try LedgerInboxMerchant(),m=LedgerInboxMessaging(),g=MerchantLedgerInboxGate(),s=try source(r)
        g.activate(); let permit=try XCTUnwrap(g.openingPermit()); g.activate()
        XCTAssertEqual(g.openingPermit(),permit)
        await g.open(s,currentMessaging:{m},permit:permit)
        XCTAssertTrue(g.approved); XCTAssertEqual(r.reads,1)
    }

}
