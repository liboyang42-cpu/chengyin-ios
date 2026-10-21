import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let inviteRow = #"{"id":12,"topicId":70,"chapterId":7,"topicName":"Route","chapterName":"Market chapter","status":0,"source":1,"merchantId":1}"#
private func accessJSON(role: String = "MERCHANT_OWNER", permissions: [String]) -> String {
    #"{"active":true,"merchant":{"id":31,"name":"Shop"},"roleCode":""# + role + #"","permissions":["# + permissions.joined(separator: "\",\"") + #"]}"#
}
private let coopAccess = accessJSON(permissions: ["merchant:coop:manage"])

final class MerchantChapterInvitationDomainTests: XCTestCase {
    private func access(_ json: String) throws -> MerchantAccess { try JSONDecoder().decode(MerchantAccess.self, from: Data(json.utf8)) }
    private func snapshot(_ access: MerchantAccess, _ raw: String, ownerMemberID: Int = 1) throws -> MerchantContentSnapshot {
        .init(query: .chapterInvitations, scope: UUID(), access: access, value: try MerchantContentFixtureData.value(raw), observedAt: Date(), ownerMemberID: ownerMemberID)
    }
    func testCoopOwnerGateNeverSubstitutesProjects() throws {
        XCTAssertTrue(MerchantChapterInvitation.accessAllows(try access(coopAccess)))
        XCTAssertTrue(MerchantChapterInvitation.accessAllows(try access(accessJSON(permissions: ["merchant:coop:manage", "merchant:project:manage"]))))
        XCTAssertFalse(MerchantChapterInvitation.accessAllows(try access(accessJSON(permissions: ["merchant:project:manage"]))))
        XCTAssertFalse(MerchantChapterInvitation.accessAllows(try access(accessJSON(role: "MERCHANT_MANAGER", permissions: ["merchant:coop:manage"]))))
        XCTAssertFalse(MerchantChapterInvitation.accessAllows(try access(accessJSON(permissions: []))))
    }
    func testOnlyChapterInvitationsQueryIsCoopGated() {
        XCTAssertTrue(MerchantContentQuery.chapterInvitations.requiresCoopOwner)
        XCTAssertFalse(MerchantContentQuery.chapterInvitations.requiresProjects)
        XCTAssertFalse(MerchantContentQuery.applications.requiresCoopOwner)
        XCTAssertTrue(MerchantContentQuery.applications.requiresProjects)
        XCTAssertTrue(MerchantContentQuery.projects.requiresProjects)
    }
    func testRespondRequestIsExactTwoFieldJSON() throws {
        let request = try MerchantContentCommand.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 7, topicID: 70).request()
        XCTAssertEqual(request.path, "api/merchant/chapter-application/invite/respond")
        guard case .json(let fields) = request.body else { return XCTFail("JSON required") }
        XCTAssertEqual(fields, ["applicationId": .integer(12), "accepted": .bool(true)])
        XCTAssertThrowsError(try MerchantContentCommand.respondChapterInvitation(applicationID: 0, accepted: true, chapterID: 7, topicID: 70).request())
    }
    func testValidateRequiresPendingInviteExactChapterTopicAndOwner() throws {
        let snapshot = try snapshot(try access(coopAccess), "[" + inviteRow + "]")
        XCTAssertNoThrow(try MerchantContentCommand.respondChapterInvitation(applicationID: 12, accepted: false, chapterID: 7, topicID: 70).validate(against: snapshot))
        for raw in [inviteRow.replacingOccurrences(of: #""source":1"#, with: #""source":0"#),
                    inviteRow.replacingOccurrences(of: #""status":0"#, with: #""status":1"#),
                    inviteRow.replacingOccurrences(of: #""status":0"#, with: #""status":2"#),
                    inviteRow.replacingOccurrences(of: #""merchantId":1"#, with: #""merchantId":31"#)] {
            XCTAssertThrowsError(try MerchantContentCommand.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 7, topicID: 70)
                .validate(against: snapshot(try access(coopAccess), "[" + raw + "]")))
        }
        XCTAssertThrowsError(try MerchantContentCommand.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 8, topicID: 70).validate(against: snapshot))
        XCTAssertThrowsError(try MerchantContentCommand.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 7, topicID: 71).validate(against: snapshot))
        let projectsOnly = try snapshot(try access(accessJSON(permissions: ["merchant:project:manage"])), "[" + inviteRow + "]")
        XCTAssertThrowsError(try MerchantContentCommand.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 7, topicID: 70).validate(against: projectsOnly))
    }
    func testIntentRoundTripsThroughSharedJournalWithoutSensitiveFields() throws {
        let intent = try MerchantChapterInvitationIntent(storageScope: "realm", accountID: 1, merchantID: 31, applicationID: 12, chapterID: 7, topicID: 70, accepted: true)
        let record = MerchantContentPendingRecord(storageScope: "realm", accountID: 1, merchantID: 31, target: intent.target, action: MerchantChapterInvitationIntent.action, station: nil)
        XCTAssertEqual(MerchantChapterInvitationIntent(record: record), intent)
        XCTAssertTrue(intent.matches(record))
        let json = String(decoding: try JSONEncoder().encode(intent), as: UTF8.self)
        for forbidden in ["token", "phone", "name", "message"] { XCTAssertFalse(json.contains(forbidden)) }
    }
    func testReadbackVerdicts() throws {
        let intent = try MerchantChapterInvitationIntent(storageScope: "realm", accountID: 1, merchantID: 31, applicationID: 12, chapterID: 7, topicID: 70, accepted: true)
        func verdict(_ raw: String?) -> MerchantChapterInvitationReadback {
            MerchantChapterInvitationReadback.evaluate(intent: intent, row: raw.map { try! MerchantContentFixtureData.value($0) }, currentOwnerMemberID: 1)
        }
        guard case .confirmedCurrentFact = verdict(inviteRow.replacingOccurrences(of: #""status":0"#, with: #""status":1"#)) else { return XCTFail("accept terminal") }
        guard case .oppositeTerminal = verdict(inviteRow.replacingOccurrences(of: #""status":0"#, with: #""status":2"#)) else { return XCTFail("opposite") }
        guard case .stillPending = verdict(inviteRow) else { return XCTFail("pending") }
        XCTAssertEqual(verdict(nil), .missing)
        XCTAssertEqual(verdict(inviteRow.replacingOccurrences(of: #""topicId":70"#, with: #""topicId":71"#)), .conflict)
        XCTAssertEqual(verdict(inviteRow.replacingOccurrences(of: #""source":1"#, with: #""source":0"#)), .conflict)
        XCTAssertEqual(MerchantChapterInvitationReadback.evaluate(intent: intent, row: try MerchantContentFixtureData.value(inviteRow), currentOwnerMemberID: 2), .conflict)
        XCTAssertEqual(verdict(inviteRow.replacingOccurrences(of: #""merchantId":1"#, with: #""merchantId":31"#)), .conflict, "Archive id is not the member id")
        XCTAssertTrue(MerchantChapterInvitationReadback.confirmedCurrentFact(reason: nil, row: .null).clearsIntentLock)
        XCTAssertFalse(MerchantChapterInvitationReadback.stillPending(row: .null).clearsIntentLock)
    }
}

private final class InvitationScriptTransport: MerchantContentOfflineTransport {
    var replies: [(String, Int)] = []
    var requests: [URLRequest] = []
    var failAt: Int?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if requests.count == failAt { throw URLError(.timedOut) }
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst(); return (Data(reply.0.utf8), reply.1)
    }
    func append(_ data: String) { replies.append(("{\"code\":200,\"data\":" + data + "}", 200)) }
    var respondCount: Int { requests.filter { $0.url?.path == "/api/merchant/chapter-application/invite/respond" }.count }
}

@MainActor final class MerchantChapterInvitationServiceTests: XCTestCase {
    private final class SessionBox { var value: MerchantContentSession? = try? .init(accountID: 1, epoch: 1, storageScope: "test-realm", token: "synthetic-token") }
    private func service(_ t: InvitationScriptTransport, box: SessionBox, journal: MerchantContentMemoryPendingStorage) throws -> MerchantContentService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://invite.example")!), transport: t,
              currentSession: { box.value }, journal: journal, execution: .injectedOfflineHarness)
    }
    private func baseline(_ t: InvitationScriptTransport, _ s: MerchantContentService, status: Int = 0) async throws -> MerchantContentSnapshot {
        t.append(coopAccess); t.append("[" + inviteRow.replacingOccurrences(of: #""status":0"#, with: "\"status\":\(status)") + "]")
        return try await s.load(.chapterInvitations)
    }
    func testMineLoadUsesCoopOwnerWithoutProjects() async throws {
        let t = InvitationScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal); _ = try await baseline(t, s)
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/merchant/chapter-application/mine"])
    }
    func testMineLoadDeniedForProjectsOnlyAndManagerBeforeMineFetch() async throws {
        for access in [accessJSON(permissions: ["merchant:project:manage"]), accessJSON(role: "MERCHANT_MANAGER", permissions: ["merchant:coop:manage"])] {
            let t = InvitationScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
            t.append(access); let s = try service(t, box: box, journal: journal)
            do { _ = try await s.load(.chapterInvitations); XCTFail("denied") } catch { XCTAssertEqual(error as? MerchantContentFailure, .denied) }
            XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testAcceptSuccessSendsOnce() async throws {
        let t = InvitationScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal); let base = try await baseline(t, s)
        t.append(coopAccess); t.append("[" + inviteRow + "]"); t.append("{}")
        t.append(coopAccess); t.append("[" + inviteRow.replacingOccurrences(of: #""status":0"#, with: #""status":1"#) + "]")
        _ = try await s.perform(.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 7, topicID: 70), baseline: base)
        XCTAssertEqual(t.respondCount, 1); XCTAssertTrue(try journal.records().isEmpty)
        let respond = try XCTUnwrap(t.requests.first { $0.url?.path == "/api/merchant/chapter-application/invite/respond" })
        let body = try JSONDecoder().decode([String: MerchantContentValue].self, from: respond.httpBody!)
        XCTAssertEqual(body, ["applicationId": .integer(12), "accepted": .bool(true)])
    }
    func testCapacityRejectionClearsLockAndKeepsServerMessage() async throws {
        let t = InvitationScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal); let base = try await baseline(t, s)
        t.append(coopAccess); t.append("[" + inviteRow + "]"); t.replies.append((#"{"code":500,"msg":"capacity full"}"#, 200))
        do { _ = try await s.perform(.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 7, topicID: 70), baseline: base); XCTFail("rejected") }
        catch { XCTAssertEqual(error as? MerchantContentFailure, .rejected(code: 500, message: "capacity full")) }
        XCTAssertTrue(try journal.records().isEmpty)
    }
    func testLostResponseKeepsLockAndReadbackConfirmsWithoutResend() async throws {
        let t = InvitationScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal); let base = try await baseline(t, s)
        t.append(coopAccess); t.append("[" + inviteRow + "]"); t.failAt = 5
        do { _ = try await s.perform(.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 7, topicID: 70), baseline: base); XCTFail("unknown") }
        catch { XCTAssertEqual(error as? MerchantContentFailure, .unknown) }
        XCTAssertEqual(try journal.records().count, 1)
        t.failAt = nil; t.append(coopAccess); t.append("[" + inviteRow.replacingOccurrences(of: #""status":0"#, with: #""status":1"#) + "]")
        let record = try XCTUnwrap(journal.records().first)
        guard case .confirmedCurrentFact = try await s.reconcileChapterInvitation(record) else { return XCTFail("confirmed") }
        XCTAssertEqual(t.respondCount, 1); XCTAssertTrue(try journal.records().isEmpty)
    }
    func testReadbackPendingMissingAndCrossAccountKeepLock() async throws {
        let t = InvitationScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let intent = try MerchantChapterInvitationIntent(storageScope: "test-realm", accountID: 1, merchantID: 31, applicationID: 12, chapterID: 7, topicID: 70, accepted: false)
        let record = MerchantContentPendingRecord(storageScope: "test-realm", accountID: 1, merchantID: 31, target: intent.target, action: MerchantChapterInvitationIntent.action, station: nil)
        try journal.insert(record); let s = try service(t, box: box, journal: journal)
        t.append(coopAccess); t.append("[" + inviteRow + "]")
        guard case .stillPending = try await s.reconcileChapterInvitation(record) else { return XCTFail("pending") }
        t.append(coopAccess); t.append("[]")
        XCTAssertEqual(try await s.reconcileChapterInvitation(record), .missing)
        XCTAssertEqual(try journal.records().count, 1); XCTAssertEqual(t.respondCount, 0)
        box.value = try .init(accountID: 2, epoch: 2, storageScope: "test-realm", token: "other-token")
        do { _ = try await s.reconcileChapterInvitation(record); XCTFail("locked") } catch { XCTAssertEqual(error as? MerchantContentFailure, .locked) }
        XCTAssertEqual(try journal.records().count, 1)
    }
    func testCoordinatorUnknownAutoReadbacksOnceWithoutResend() async throws {
        let t = InvitationScriptTransport(), box = SessionBox(), journal = MerchantContentMemoryPendingStorage()
        let s = try service(t, box: box, journal: journal)
        let coordinator = MerchantContentCoordinator(service: s, query: .chapterInvitations)
        t.append(coopAccess); t.append("[" + inviteRow + "]"); await coordinator.load()
        coordinator.prepare(.respondChapterInvitation(applicationID: 12, accepted: true, chapterID: 7, topicID: 70))
        let review = try XCTUnwrap(coordinator.review)
        t.append(coopAccess); t.append("[" + inviteRow + "]"); t.failAt = 5
        t.append(coopAccess); t.append("[" + inviteRow.replacingOccurrences(of: #""status":0"#, with: #""status":1"#) + "]")
        // failAt counts every request: load(2) + perform reload(2) + respond(1) = request 5.
        await coordinator.confirm(review)
        XCTAssertEqual(t.respondCount, 1); XCTAssertFalse(coordinator.locked); XCTAssertNotNil(coordinator.receipt)
        XCTAssertEqual(coordinator.issue, "merchantChapterInvitation.readbackConfirmed")
    }
}
