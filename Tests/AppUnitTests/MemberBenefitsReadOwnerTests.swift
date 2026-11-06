import Foundation
import SwiftUI
import Observation
import XCTest
@testable import Questify

@MainActor @Observable private final class BenefitsOwnerReader: MemberHomeReading {
    var scope = UUID(), isSignedIn = true, isConfigured = true, roleInfoAvailable = true
    var reads = 0, hold = false, withdrawable = true
    var pending: [Int: CheckedContinuation<MemberRoleInfo, Error>] = [:]
    var error: Error?
    func identity() async throws -> MemberIdentitySnapshot { throw APIError.notConfigured }
    func roleInfo() async throws -> MemberRoleInfo {
        reads += 1; let request = reads
        if hold { return try await withCheckedThrowingContinuation { pending[request] = $0 } }
        if let error { throw error }; return try Self.result(withdrawable: withdrawable)
    }
    static func result(withdrawable: Bool) throws -> MemberRoleInfo {
        try JSONDecoder().decode(MemberRoleInfo.self, from: JSONSerialization.data(withJSONObject: ["role": "player", "permission": ["maxThemes": 3, "withdrawable": withdrawable]]))
    }
    func finish(_ index: Int, withdrawable: Bool = true, error: Error? = nil) {
        guard let value = pending.removeValue(forKey: index) else { return }
        if let error { value.resume(throwing: error) } else { value.resume(with: Result { try Self.result(withdrawable: withdrawable) }) }
    }
    func finishAll() { for index in Array(pending.keys) { finish(index, error: CancellationError()) } }
}
@MainActor private final class BenefitsHostVault: AppTokenStorage {
    var token: String? = "synthetic-benefits"
    func read() throws -> String? { token }; func write(_ value: String) throws { token = value }; func clear() throws { token = nil }
}
@MainActor private final class BenefitsHostWire: HTTPTransport {
    var requests: [URLRequest] = [], role = "player"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path.hasSuffix("api/role/info") == true {
            return (Data("{\"code\":200,\"data\":{\"role\":\"\(role)\",\"permission\":{\"withdrawable\":true}}}".utf8), 200)
        }
        return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
    }
}
@MainActor private final class BenefitsHostObservationCount { var value = 0 }
@MainActor private final class BenefitsGrantBox { var value: MemberRoleInfoReadApproval? }
@MainActor final class MemberBenefitsReadOwnerTests: XCTestCase {
    private func setupOwner() -> (BenefitsOwnerReader, MemberBenefitsReadOwner) {
        let reader = BenefitsOwnerReader(), owner = MemberBenefitsReadOwner(reader: reader); owner.appear(active: true)
        addTeardownBlock { @MainActor in owner.scene(active: false); owner.disappear(); reader.finishAll() }
        return (reader, owner)
    }
    private func ready(_ owner: MemberBenefitsReadOwner) throws -> MemberBenefitsReadOwner.Snapshot {
        guard case .ready(let value) = owner.phase else { XCTFail("Expected synthetic ready snapshot"); throw APIError.notConfigured }; return value
    }
    private func waitFor(_ reader: BenefitsOwnerReader, _ count: Int) async {
        for _ in 0..<100 { if reader.pending[count] != nil { return }; await Task.yield() }
        XCTFail("Synthetic admission failed")
    }
    func testUnmountedAndBackgroundCannotStartQueuedReads() {
        let reader = BenefitsOwnerReader(), owner = MemberBenefitsReadOwner(reader: reader)
        XCTAssertNil(owner.refresh()); owner.appear(active: false); XCTAssertNil(owner.refresh())
        owner.scene(active: true); owner.disappear(); XCTAssertNil(owner.refresh()); XCTAssertEqual(reader.reads, 0)
    }
    func testAbsentPermissionKeepsOriginalUnavailableStateWithoutRequest() {
        let (reader, owner) = setupOwner(); reader.roleInfoAvailable = false
        XCTAssertNil(owner.refresh()); XCTAssertEqual(owner.phase, .unavailable); XCTAssertEqual(reader.reads, 0)
    }
    func testGuestCannotReadOrNavigateEvenWithAStubAvailableFlag() {
        let (reader, owner) = setupOwner(); reader.isSignedIn = false
        XCTAssertNil(owner.refresh()); XCTAssertEqual(owner.phase, .unavailable); XCTAssertEqual(reader.reads, 0)
    }
    func testOriginalRowsAndWithdrawableRemainTheOnlyEntryFacts() async throws {
        let (_, owner) = setupOwner(); await owner.refresh()?.value
        let value = try ready(owner); XCTAssertEqual(value.rows.map(\.kind), MemberBenefit.Kind.allCases)
        XCTAssertEqual(value.rows.first?.routeLimit, .limited(3)); XCTAssertEqual(value.rows.filter { $0.opensEarnings }.count, 1)
        XCTAssertNotNil(owner.openEarnings(value))
    }
    func testFalseWithdrawableDoesNotCreateNavigation() async throws {
        let (reader, owner) = setupOwner(); reader.withdrawable = false; await owner.refresh()?.value
        let value = try ready(owner); XCTAssertNil(owner.openEarnings(value)); XCTAssertNil(owner.currentNavigation)
    }
    func testFailureDoesNotInventReadyPermissionsAndRetryRemainsPossible() async throws {
        let (reader, owner) = setupOwner(); reader.error = APIError.httpStatus(503); await owner.refresh()?.value
        XCTAssertEqual(owner.phase, .failed); XCTAssertNil(owner.currentNavigation)
        reader.error = nil; await owner.refresh()?.value; _ = try ready(owner); XCTAssertEqual(reader.reads, 2)
    }
    func testNotConfiguredReadRemainsUnavailable() async {
        let (reader, owner) = setupOwner(); reader.error = APIError.notConfigured; await owner.refresh()?.value
        XCTAssertEqual(owner.phase, .unavailable)
    }
    func testLateOldSuccessCannotReplaceNewPermissions() async throws {
        let (reader, owner) = setupOwner(); reader.hold = true
        let first = owner.refresh(); await waitFor(reader, 1)
        let second = owner.refresh(); await waitFor(reader, 2)
        reader.finish(2, withdrawable: false); await second?.value; let newest = try ready(owner)
        reader.finish(1, withdrawable: true); await first?.value
        XCTAssertEqual(try ready(owner), newest); XCTAssertNil(owner.openEarnings(newest))
    }
    func testLateOldFailureCannotReplaceCurrentSuccess() async throws {
        let (reader, owner) = setupOwner(); reader.hold = true
        let first = owner.refresh(); await waitFor(reader, 1); let second = owner.refresh(); await waitFor(reader, 2)
        reader.finish(2); await second?.value; let newest = try ready(owner)
        reader.finish(1, error: APIError.unauthorized); await first?.value; XCTAssertEqual(try ready(owner), newest)
    }
    func testScopeChangeHidesRowsAndRejectsRenderedOldEntry() async throws {
        let (reader, owner) = setupOwner(); await owner.refresh()?.value; let old = try ready(owner)
        reader.scope = UUID(); XCTAssertEqual(owner.phase, .loading); XCTAssertFalse(owner.accepts(old)); XCTAssertNil(owner.openEarnings(old))
    }
    func testWithdrawalHidesRowsAndPreventsDestinationEvaluation() async throws {
        let (reader, owner) = setupOwner(); await owner.refresh()?.value
        let ticket = try XCTUnwrap(owner.openEarnings(ready(owner))); reader.roleInfoAvailable = false
        var builds = 0; let value: Int? = owner.navigationValue(ticket) { builds += 1; return 1 }
        XCTAssertNil(value); XCTAssertEqual(builds, 0); XCTAssertEqual(owner.phase, .unavailable); XCTAssertNil(owner.currentNavigation)
    }
    func testNavigationIsValidAfterItsListDisappearsForNormalPush() async throws {
        let (_, owner) = setupOwner(); await owner.refresh()?.value; let ticket = try XCTUnwrap(owner.openEarnings(ready(owner)))
        owner.disappear(); owner.disappear(); XCTAssertTrue(owner.navigationIsCurrent(ticket))
        XCTAssertEqual(owner.phase, .ready(ticket.snapshot)) // Keep the link anchor during a valid push.
        XCTAssertEqual(owner.navigationValue(ticket) { "synthetic earnings" }, "synthetic earnings")
        XCTAssertNil(owner.refresh()); owner.closeNavigation(ticket.id); XCTAssertFalse(owner.navigationIsCurrent(ticket)); XCTAssertEqual(owner.phase, .unavailable)
    }
    func testDestinationScopeIsRecheckedAfterListDisappears() async throws {
        let (reader, owner) = setupOwner(); await owner.refresh()?.value; let ticket = try XCTUnwrap(owner.openEarnings(ready(owner)))
        owner.disappear(); reader.scope = UUID(); XCTAssertFalse(owner.navigationIsCurrent(ticket))
        var builds = 0; XCTAssertNil(owner.navigationValue(ticket) { builds += 1; return 1 }); XCTAssertEqual(builds, 0)
    }
    func testSourceWithdrawalInsideBuilderDiscardsReturnedDestination() async throws {
        let (reader, owner) = setupOwner(); await owner.refresh()?.value; let ticket = try XCTUnwrap(owner.openEarnings(ready(owner)))
        let result = owner.navigationValue(ticket) { reader.roleInfoAvailable = false; return "stale" }
        XCTAssertNil(result)
    }
    func testOnlyExplicitOpenCreatesTicketAndDuplicateOpenIsBlocked() async throws {
        let (_, owner) = setupOwner(); await owner.refresh()?.value; let snapshot = try ready(owner)
        XCTAssertNil(owner.currentNavigation)
        let first = try XCTUnwrap(owner.openEarnings(snapshot)); XCTAssertNil(owner.openEarnings(snapshot))
        XCTAssertEqual(owner.currentNavigation?.id, first.id)
    }
    func testOriginalLinkBindingActivatesOnlyItsRenderedCurrentSnapshot() async throws {
        let (_, owner) = setupOwner(); await owner.refresh()?.value; let snapshot = try ready(owner)
        let binding = owner.earningsBinding(snapshot); XCTAssertFalse(binding.wrappedValue)
        binding.wrappedValue = true; let ticket = try XCTUnwrap(owner.currentNavigation)
        owner.disappear(); XCTAssertTrue(binding.wrappedValue); XCTAssertTrue(owner.navigationIsCurrent(ticket))
        binding.wrappedValue = false; XCTAssertNil(owner.currentNavigation)
    }
    func testOldLinkBindingCannotOpenAfterNewMetadataRead() async throws {
        let (_, owner) = setupOwner(); await owner.refresh()?.value
        let old = owner.earningsBinding(try ready(owner)); await owner.refresh()?.value
        old.wrappedValue = true; XCTAssertNil(owner.currentNavigation)
        let latest = owner.earningsBinding(try ready(owner)); latest.wrappedValue = true; XCTAssertNotNil(owner.currentNavigation)
    }
    func testOldBindingAndDismissCannotCloseNewTicket() async throws {
        let (_, owner) = setupOwner(); await owner.refresh()?.value; let snapshot = try ready(owner)
        let old = try XCTUnwrap(owner.openEarnings(snapshot)), binding = owner.earningsBinding(snapshot)
        owner.closeNavigation(old.id); let current = try XCTUnwrap(owner.openEarnings(snapshot))
        binding.wrappedValue = false; owner.closeNavigation(old.id)
        XCTAssertTrue(owner.navigationIsCurrent(current)); XCTAssertEqual(owner.currentNavigation?.id, current.id)
    }
    func testNewRefreshInvalidatesAlreadySelectedDestination() async throws {
        let (reader, owner) = setupOwner(); await owner.refresh()?.value; let old = try XCTUnwrap(owner.openEarnings(ready(owner)))
        reader.hold = true; let work = owner.refresh(); XCTAssertFalse(owner.navigationIsCurrent(old)); await waitFor(reader, 2)
        reader.finish(2); await work?.value
    }
    func testBackgroundClearsRowsAndTicketWithoutForegroundResurrection() async throws {
        let (_, owner) = setupOwner(); await owner.refresh()?.value; let old = try XCTUnwrap(owner.openEarnings(ready(owner)))
        owner.scene(active: false); XCTAssertEqual(owner.phase, .unavailable); XCTAssertFalse(owner.navigationIsCurrent(old))
        owner.scene(active: true); XCTAssertFalse(owner.navigationIsCurrent(old)); XCTAssertNil(owner.currentNavigation)
    }
    func testDisappearBeforeTaskAdmissionNeverCallsReader() async {
        let (reader, owner) = setupOwner(); let task = owner.refresh(); owner.disappear(); await task?.value
        XCTAssertEqual(reader.reads, 0)
    }
    func testCancelledOldTaskCannotEraseNewReadyRows() async throws {
        let (reader, owner) = setupOwner(); reader.hold = true
        let first = owner.refresh(); await waitFor(reader, 1); let next = owner.refresh(); await waitFor(reader, 2)
        reader.finish(2); await next?.value; let current = try ready(owner)
        first?.cancel(); reader.finish(1, error: CancellationError()); await first?.value
        XCTAssertEqual(try ready(owner), current)
    }
    func testHostPreservesDefaultNilAndRoleABAChangesActualReaderScope() async throws {
        let suite = "benefits-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = BenefitsHostVault(), wire = BenefitsHostWire(), box = BenefitsGrantBox()
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://benefits.example.test/native", approvedBaseURLs: [.china: ["https://benefits.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.benefits." + UUID().uuidString.lowercased(), realm: "synthetic")
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        root.memberRoleInfoReadApproval = { c in box.value.flatMap { $0.matches(c) ? $0 : nil } }
        let session = root.makeSession(); await session.bootstrap(); XCTAssertFalse(session.memberHomeReader.roleInfoAvailable)
        let context = try XCTUnwrap(session.profileSavedMediaIdentity(.avatar).context)
        box.value = try .init(context: context, expiresAt: Date().addingTimeInterval(600)); defer { box.value?.revoke() }
        XCTAssertTrue(session.memberHomeReader.roleInfoAvailable); let first = session.memberHomeReader.scope
        let observed = BenefitsHostObservationCount()
        withObservationTracking { _ = session.memberHomeReader.scope } onChange: { MainActor.assumeIsolated { observed.value += 1 } }
        wire.role = "merchant"; await session.refreshOwnAccount()
        XCTAssertEqual(observed.value, 1) // Host publishes scope before a view asks for it.
        // Do not sample the reader in the intermediate role.
        wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertTrue(session.memberHomeReader.roleInfoAvailable); XCTAssertNotEqual(session.memberHomeReader.scope, first)
        XCTAssertEqual(vault.token, "synthetic-benefits")
    }
}
