import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ClubAdmissionIndependentRecoveryTests: XCTestCase {
    private func fixture(original: Bool = true, state: String = "APPLIED") throws -> RecoveryFixture {
        try RecoveryFixture(original: original, state: state)
    }
    func testReadOnlyGrantRecoversWhenDetailFailsWithoutAnyDetailOrWriteRequest() async throws {
        let f = try fixture()
        XCTAssertFalse(f.coordinator.isConfigured)
        XCTAssertTrue(f.coordinator.canRecoverOriginal(clubID: 7))
        let result = await f.coordinator.recoverOriginal(clubID: 7, expectedIdentity: f.reader.clubIdentity)
        XCTAssertEqual(result, .applied)
        XCTAssertNil(f.journal.value)
        XCTAssertEqual(f.paths, ["/api/club/admission/receipt"])
        XCTAssertEqual(f.reader.reads, 0); XCTAssertEqual(f.changed, 0)
        XCTAssertEqual(f.coordinator.readback(clubID: 7), .idle)
        if case .acknowledged(let receipt) = f.coordinator.state(clubID: 7) { XCTAssertEqual(receipt.state, "pending") } else { XCTFail() }
    }
    func testReadOnlyApprovalCannotPerformMembershipMutation() async throws {
        let f = try fixture()
        do { _ = try await f.writer.perform(.apply, clubID: 7, expectedIdentity: f.reader.clubIdentity, joinMessage: "reviewed", original: f.pending); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.notConfigured)) }
        XCTAssertTrue(f.paths.isEmpty); XCTAssertNotNil(f.journal.value)
    }
    func testNoReadGrantShowsUnknownButSendsNothing() async throws {
        let f = try fixture(); f.grant = nil
        XCTAssertTrue(f.coordinator.state(clubID: 7).preventsNewAction)
        XCTAssertFalse(f.coordinator.canRecoverOriginal(clubID: 7))
        let result = await f.coordinator.recoverOriginal(clubID: 7, expectedIdentity: f.reader.clubIdentity)
        XCTAssertEqual(result, .blocked(.unavailable)); XCTAssertTrue(f.paths.isEmpty)
        XCTAssertNotNil(f.journal.value)
    }
    func testUnknownReceiptKeepsOriginalFenceWithoutTryingCurrentDetail() async throws {
        let f = try fixture(state: "UNKNOWN")
        _ = await f.coordinator.recoverOriginal(clubID: 7, expectedIdentity: f.reader.clubIdentity)
        XCTAssertEqual(f.journal.value, f.pending); XCTAssertEqual(f.reader.reads, 0)
        XCTAssertTrue(f.coordinator.state(clubID: 7).preventsNewAction)
    }
    func testLegacyMarkerCannotUseNewOriginalReceipt() async throws {
        let f = try fixture(original: false)
        XCTAssertFalse(f.coordinator.canRecoverOriginal(clubID: 7))
        let result = await f.coordinator.recoverOriginal(clubID: 7, expectedIdentity: f.reader.clubIdentity)
        XCTAssertEqual(result, .blocked(.noReadback)); XCTAssertTrue(f.paths.isEmpty)
        XCTAssertNotNil(f.journal.value)
    }
    func testWrongExpectedIdentityCannotReadOriginal() async throws {
        let f = try fixture()
        let result = await f.coordinator.recoverOriginal(clubID: 7, expectedIdentity: .init(accountID: 2, epoch: 1))
        XCTAssertEqual(result, .blocked(.accountChanged)); XCTAssertTrue(f.paths.isEmpty)
    }
    func testRevocationWhileReceiptAwaitsDoesNotRetireOrLoadCurrentData() async throws {
        let f = try fixture(); f.onSend = { f.grant = nil }
        _ = await f.coordinator.recoverOriginal(clubID: 7, expectedIdentity: f.reader.clubIdentity)
        XCTAssertEqual(f.journal.value, f.pending); XCTAssertEqual(f.reader.reads, 0)
        XCTAssertEqual(f.paths.count, 1)
    }
    func testReplacementSessionDiscardsOldReceiptAndKeepsOriginalJournal() async throws {
        let f = try fixture(); f.onSend = { f.session = nil; f.reader.clubIdentity = .init(accountID: nil, epoch: 2) }
        _ = await f.coordinator.recoverOriginal(clubID: 7, expectedIdentity: f.reader.clubIdentity)
        XCTAssertEqual(f.journal.value, f.pending); XCTAssertEqual(f.reader.reads, 0)
    }
}
@MainActor private final class RecoveryFixture {
    let pending: ClubOrdinaryAdmissionPending
    let journal = RecoveryJournal()
    let reader = RecoveryUnavailableReader()
    var session: ClubActionSession?
    var grant: ClubOrdinaryAdmissionApproval?
    var paths: [String] = []
    var onSend: (() -> Void)?
    var changed = 0
    var writer: ClubActionSessionWriter!
    var coordinator: ClubActionCoordinator!
    init(original: Bool, state: String) throws {
        pending = .init(accountID: 1, clubID: 7, requestID: UUID(), action: .apply, hasOriginalReceipt: original, message: "reviewed")
        journal.value = pending
        let account = try JSONDecoder().decode(Account.self, from: Data("{\"id\":1,\"role\":\"player\"}".utf8))
        session = try .init(account: account, epoch: 1, token: "synthetic-token")
        let base = URL(string: "https://example.com")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 1, epoch: 1, namespace: "tests", token: "synthetic-token", role: "player"))
        grant = try .init(context: context) // read-only by default
        let service = ClubActionService(configuration: try APIConfiguration(baseURL: base), transport: RecoveryTransport { [weak self] request in
            guard let self else { throw APIError.notConfigured }
            self.paths.append(request.url!.path); self.onSend?()
            var fact: [String: Any] = ["actorMemberId": 1, "clubId": 7, "requestId": self.pending.requestID.uuidString.lowercased(),
                "action": "apply", "payloadSHA256": self.pending.payloadSHA256, "state": state]
            if state == "APPLIED" { fact["membershipState"] = "pending" }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": fact]), 200)
        })
        writer = ClubActionSessionWriter(service: service, currentSession: { [weak self] in self?.session }, approval: { [weak self] in self?.grant }, requiresOriginalReceipt: true)
        coordinator = ClubActionCoordinator(writer: writer, reader: reader, onMembershipChanged: { [weak self] _ in self?.changed += 1 }, journal: journal)
    }
}
@MainActor private final class RecoveryJournal: ClubOrdinaryAdmissionJournaling {
    var value: ClubOrdinaryAdmissionPending?
    func pending(accountID: Int, clubID: Int) throws -> ClubOrdinaryAdmissionPending? { value?.accountID == accountID && value?.clubID == clubID ? value : nil }
    func reserve(_ value: ClubOrdinaryAdmissionPending) throws { throw APIError.notConfigured }
    func retire(_ value: ClubOrdinaryAdmissionPending) throws { guard self.value == value else { throw APIError.invalidRequest }; self.value = nil }
}
@MainActor private final class RecoveryUnavailableReader: ClubReading {
    var isClubConfigured = false
    var clubIdentity = ClubReadIdentity(accountID: 1, epoch: 1)
    var reads = 0
    func clubDetail(id: Int) async throws -> ClubRecord { reads += 1; throw APIError.notConfigured }
    func clubHome() async throws -> ClubHome { throw APIError.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { throw APIError.notConfigured }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw APIError.notConfigured }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw APIError.notConfigured }
}
@MainActor private final class RecoveryTransport: HTTPTransport {
    let body: (URLRequest) async throws -> (Data, Int)
    init(_ body: @escaping (URLRequest) async throws -> (Data, Int)) { self.body = body }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await body(request) }
}
