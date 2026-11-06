import XCTest
@testable import Questify

@MainActor final class MerchantLedgerInboxReaderLifetimeTests: XCTestCase {
    private func container() throws -> (AppSessionContainer, IntegratedNativeAcceptanceFixture, AppSession) {
        let container = AppSessionContainer(arguments: [IntegratedNativeAcceptanceFixture.flag, "ready"])
        let fixture = try XCTUnwrap(container.integratedAcceptance)
        let defaults = try XCTUnwrap(fixture.defaults), suite = fixture.suiteName
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (container, fixture, try XCTUnwrap(container.session))
    }
    private func login(_ session: AppSession) async {
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    func testRealFactoryReaderIsRetainedThroughGateRevalidationAndRendering() async throws {
        let (container, fixture, session) = try container()
        _ = container
        await login(session)
        let owner = MerchantLedgerInboxReaderOwner(), gate = MerchantLedgerInboxGate()
        let first = owner.reader(for: session)
        // The factory intentionally creates issuance-bound readers; the host must retain one.
        XCTAssertFalse(first === session.messagingReader)
        let merchant = try Merchant(identity: XCTUnwrap(first.identity))
        let source = try XCTUnwrap(MerchantLedgerInboxSource(reader: merchant, snapshot: merchant.value))
        let before = fixture.ledger.count
        gate.activate()
        await gate.open(source, currentMessaging: { owner.reader(for: session) })
        XCTAssertTrue(gate.approved)
        XCTAssertTrue(owner.reader(for: session) === first)
        XCTAssertTrue(gate.permits(source, messaging: owner.reader(for: session)))
        XCTAssertEqual(merchant.reads, 1)
        XCTAssertEqual(fixture.ledger.count, before, "Admission must not fetch messaging history")
        gate.deactivate()
        XCTAssertFalse(gate.permits(source, messaging: first))
    }
    func testLogoutAndSameAccountReloginNeverReviveRetainedReader() async throws {
        let (container, fixture, session) = try container()
        _ = container
        await login(session)
        let owner = MerchantLedgerInboxReaderOwner(), old = owner.reader(for: session)
        let identity = try XCTUnwrap(old.identity)
        await session.logout()
        XCTAssertNil(old.identity); XCTAssertFalse(old.isConfigured)
        XCTAssertFalse(owner.reader(for: session) === old)
        await login(session)
        let fresh = owner.reader(for: session)
        XCTAssertFalse(fresh === old)
        XCTAssertEqual(fresh.identity?.accountID, identity.accountID)
        XCTAssertNotEqual(fresh.identity?.epoch, identity.epoch)
        XCTAssertTrue(fresh.isConfigured)
        XCTAssertNil(old.identity)
        let before = fixture.ledger.count
        do { _ = try await old.messagingConversations(); XCTFail("Retired reader dispatched") } catch {}
        XCTAssertEqual(fixture.ledger.count, before)
    }
    func testExpiredIssuanceReplacesReaderWithoutRevivingOldAuthority() async throws {
        let (container, fixture, session) = try container()
        _ = container
        await login(session)
        let owner = MerchantLedgerInboxReaderOwner(), old = owner.reader(for: session)
        let context = try XCTUnwrap(session.currentRuntimeDependencyContext)
        let approval = try XCTUnwrap(fixture.makeComposition().messagingHistoryReadApproval(context))
        approval.expireIfNeeded(now: approval.expiresAt)
        XCTAssertFalse(old.isConfigured)
        let fresh = owner.reader(for: session)
        XCTAssertFalse(fresh === old)
        XCTAssertTrue(fresh.isConfigured)
        XCTAssertNil(old.identity)
        XCTAssertTrue(owner.reader(for: session) === fresh)
    }
    func testIssuanceChangeDuringMerchantReadCannotApproveReplacement() async throws {
        let (container, fixture, session) = try container()
        _ = container
        await login(session)
        let owner = MerchantLedgerInboxReaderOwner(), gate = MerchantLedgerInboxGate()
        let old = owner.reader(for: session)
        let context = try XCTUnwrap(session.currentRuntimeDependencyContext)
        let approval = try XCTUnwrap(fixture.makeComposition().messagingHistoryReadApproval(context))
        let merchant = try Merchant(identity: XCTUnwrap(old.identity))
        let source = try XCTUnwrap(MerchantLedgerInboxSource(reader: merchant, snapshot: merchant.value))
        merchant.afterRead = { approval.revoke() }
        gate.activate()
        await gate.open(source, currentMessaging: { owner.reader(for: session) })
        XCTAssertFalse(gate.approved)
        XCTAssertFalse(gate.permits(source, messaging: owner.reader(for: session)))
        XCTAssertNil(old.identity)
        XCTAssertEqual(merchant.reads, 1)
    }
    func testDifferentSessionCannotReuseEvenMatchingGuestIssuance() throws {
        let (firstContainer, _, first) = try container()
        let (secondContainer, _, second) = try container()
        _ = firstContainer; _ = secondContainer
        XCTAssertEqual(first.messagingViewIdentity, second.messagingViewIdentity)
        let owner = MerchantLedgerInboxReaderOwner(), reader = owner.reader(for: first)
        XCTAssertTrue(owner.reader(for: first) === reader)
        XCTAssertFalse(owner.reader(for: second) === reader)
    }
    @MainActor private final class Merchant: MerchantBusinessReading {
        var scope: MerchantBusinessScope?
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = false
        var authorizationGeneration: UUID? = UUID()
        let value: MerchantBusinessSnapshot
        var reads = 0
        var afterRead: (() -> Void)?
        init(identity: MessagingReadIdentity) throws {
            scope = .init(realm: "synthetic", accountID: identity.accountID, epoch: identity.epoch)
            let access = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
            value = try .init(access: .init(access), document: .init(query: .overview, payload: MerchantBusinessSyntheticFixtures.payload(.overview)))
        }
        func access() async throws -> MerchantBusinessAccess { value.access }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot { reads += 1; afterRead?(); return value }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            XCTFail("No mutations"); throw MerchantBusinessFailure.disabled
        }
    }
}
