import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private final class JoinReasonTransport: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(#"{"code":200,"msg":"已拒绝入会申请"}"#.utf8), 200)
    }
}

@MainActor private final class JoinReasonAccess: ClubManagementAccess {
    var identity: ClubReadIdentity? = .init(accountID: 1, epoch: 1)
    let isConfigured = true
    var reasons: [String?] = []
    var legacyWrites = 0
    var supportsReason = true
    func snapshot(clubID: Int) async throws -> ClubManagementSnapshot {
        let club = try JSONDecoder().decode(ClubRecord.self, from: Data(#"{"id":81,"name":"Fixture club","isOwner":true,"isJoined":true}"#.utf8))
        let rows = try JSONDecoder().decode([ClubManagementRequest].self, from: Data(#"[{"memberId":3,"nickname":"Applicant"}]"#.utf8))
        return .init(club: club, requests: rows, members: [])
    }
    func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        legacyWrites += 1; return .init(state: nil, message: nil)
    }
    func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, reviewReason: String?, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        reasons.append(reviewReason); return .init(state: nil, message: nil)
    }
}

@MainActor private final class LegacyOnlyAccess: ClubManagementAccess {
    var identity: ClubReadIdentity? = .init(accountID: 1, epoch: 1)
    let isConfigured = true
    var writes = 0
    func snapshot(clubID: Int) async throws -> ClubManagementSnapshot { throw APIError.malformedResponse }
    func perform(_ action: ClubManagementAction, clubID: Int, memberID: Int, expectedIdentity: ClubReadIdentity) async throws -> ClubActionReceipt {
        writes += 1; return .init(state: nil, message: nil)
    }
}

final class ClubOpsJoinReviewReasonTests: XCTestCase {
    func testReasonIsTrimmedOptionalAndBoundedByUTF16() {
        XCTAssertNil(ClubOpsJoinReviewReason.normalized("  \n "))
        XCTAssertEqual(ClubOpsJoinReviewReason.normalized("  名额已满 "), "名额已满")
        XCTAssertTrue(ClubOpsJoinReviewReason.isValid(String(repeating: "满", count: 500)))
        XCTAssertTrue(ClubOpsJoinReviewReason.isValid(" " + String(repeating: "a", count: 500) + " "))
        XCTAssertFalse(ClubOpsJoinReviewReason.isValid(String(repeating: "a", count: 501)))
        XCTAssertFalse(ClubOpsJoinReviewReason.isValid(String(repeating: "👋", count: 251)))
        XCTAssertEqual(ClubOpsJoinReviewReason.count(" 👋 "), 2)
        XCTAssertTrue(ClubOpsJoinReviewReason.isDispatchable(nil))
        XCTAssertFalse(ClubOpsJoinReviewReason.isDispatchable(" padded"))
        XCTAssertFalse(ClubOpsJoinReviewReason.isDispatchable(""))
    }
    private func service(_ t: JoinReasonTransport) throws -> ClubManagementService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/")!), transport: t)
    }
    func testRejectSendsReviewReasonOnlyWhenPresent() async throws {
        let t = JoinReasonTransport()
        _ = try await service(t).perform(.reject, clubID: 81, memberID: 3, token: "fixture-token", reviewReason: "名额已满")
        _ = try await service(t).perform(.reject, clubID: 81, memberID: 3, token: "fixture-token")
        XCTAssertEqual(t.requests.count, 2)
        let first = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(t.requests[0].httpBody)) as? [String: Any])
        XCTAssertEqual(Set(first.keys), ["clubId", "memberId", "reviewReason"])
        XCTAssertEqual(first["reviewReason"] as? String, "名额已满")
        XCTAssertEqual(first["clubId"] as? Int, 81)
        XCTAssertEqual(t.requests[0].url?.path, "/api/club/join-request/reject")
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(t.requests[1].httpBody)) as? [String: Int])
        XCTAssertEqual(second, ["clubId": 81, "memberId": 3])
    }
    func testInvalidOrMisplacedReasonNeverDispatches() async throws {
        let t = JoinReasonTransport()
        for (action, reason) in [(ClubManagementAction.approve, "x"), (.remove, "x"), (.reject, " x"), (.reject, ""), (.reject, String(repeating: "a", count: 501))] {
            do { _ = try await service(t).perform(action, clubID: 81, memberID: 3, token: "fixture-token", reviewReason: reason); XCTFail() }
            catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.invalidRequest)) }
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    @MainActor func testConfirmationFreezesReasonForRejectOnly() async throws {
        let access = JoinReasonAccess(), coordinator = ClubManagementCoordinator(access: access)
        let pending = try await coordinator.prepare(clubID: 81, action: .reject, memberID: 3, expectedIdentity: access.identity!)
        XCTAssertNil(pending.reviewReason)
        let reviewed = pending.reviewing(reason: "  名额已满  ")
        XCTAssertEqual(reviewed.id, pending.id); XCTAssertEqual(reviewed.memberID, 3)
        XCTAssertEqual(reviewed.reviewReason, "名额已满")
        XCTAssertNil(pending.reviewing(reason: "   ").reviewReason)
        let result = await coordinator.confirm(reviewed)
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(access.reasons, ["名额已满"]); XCTAssertEqual(access.legacyWrites, 0)
        let approve = try await coordinator.prepare(clubID: 81, action: .approve, memberID: 3, expectedIdentity: access.identity!)
        XCTAssertNil(approve.reviewing(reason: "ignored").reviewReason)
    }
    @MainActor func testOverlongReasonIsNotSentAndLegacyAccessRefusesReason() async throws {
        let access = JoinReasonAccess(), coordinator = ClubManagementCoordinator(access: access)
        let pending = try await coordinator.prepare(clubID: 81, action: .reject, memberID: 3, expectedIdentity: access.identity!)
        let result = await coordinator.confirm(pending.reviewing(reason: String(repeating: "a", count: 501)))
        XCTAssertEqual(result, .applied)
        XCTAssertEqual(coordinator.state(clubID: 81), .notSent)
        XCTAssertTrue(access.reasons.isEmpty)
        let legacy = LegacyOnlyAccess()
        do { _ = try await legacy.perform(.reject, clubID: 81, memberID: 3, reviewReason: "x", expectedIdentity: legacy.identity!); XCTFail() }
        catch { XCTAssertEqual(error as? ClubActionWriteError, .notSent(.invalidRequest)) }
        _ = try await legacy.perform(.reject, clubID: 81, memberID: 3, reviewReason: nil, expectedIdentity: legacy.identity!)
        XCTAssertEqual(legacy.writes, 1)
    }
}

final class ClubOpsJoinRequestPresentationTests: XCTestCase {
    func testIntroNameAndQuotedMessage() {
        XCTAssertEqual(ClubOpsJoinRequestPresentation.introPendingCount(3), 3)
        XCTAssertNil(ClubOpsJoinRequestPresentation.introPendingCount(0))
        XCTAssertNil(ClubOpsJoinRequestPresentation.displayName(nil))
        XCTAssertNil(ClubOpsJoinRequestPresentation.displayName("  "))
        XCTAssertEqual(ClubOpsJoinRequestPresentation.displayName("Rider"), "Rider")
        XCTAssertNil(ClubOpsJoinRequestPresentation.quotedMessage(nil))
        XCTAssertNil(ClubOpsJoinRequestPresentation.quotedMessage(""))
        XCTAssertEqual(ClubOpsJoinRequestPresentation.quotedMessage("x&lt;y"), "\u{201C}x<y\u{201D}")
    }
    func testDisplayTextDecodesFiveEntitiesInOnePass() {
        let decode = ClubOpsJoinRequestPresentation.decodeDisplayText
        XCTAssertEqual(decode("a&lt;b&gt;c&amp;d&quot;e&#39;f"), "a<b>c&d\"e'f")
        XCTAssertEqual(decode("&#60;&#062;&#x3C;&#X3e;&#x26;&#34;&#039;"), "<><>&\"'")
        XCTAssertEqual(decode("&amp;lt;"), "&lt;")
        XCTAssertEqual(decode("&nbsp;&#65;&LT;"), "&nbsp;&#65;&LT;")
        XCTAssertEqual(decode("plain"), "plain")
    }
}

final class ClubOpsNotifyPresentationTests: XCTestCase {
    private func campaign(_ fields: [String: ClubGovernanceValue]) throws -> ClubOpsNotifyCampaign {
        let base: [String: ClubGovernanceValue] = ["id": .integer(131)]
        return try .init(value: .object(base.merging(fields) { $1 }))
    }
    func testCampaignPhasePendingAndProcessing() throws {
        let processing = try campaign(["totalCount": .integer(4), "successCount": .integer(0), "failedCount": .integer(0), "status": .string("PROCESSING")])
        XCTAssertEqual(processing.phase, .delivering); XCTAssertTrue(processing.processing); XCTAssertEqual(processing.pendingCount, 4)
        XCTAssertFalse(processing.canRetryFailed)
        let partial = try campaign(["totalCount": .integer(8), "successCount": .integer(5), "failedCount": .integer(1), "status": .string("partial_failed")])
        XCTAssertEqual(partial.phase, .partialFailed); XCTAssertFalse(partial.processing); XCTAssertEqual(partial.pendingCount, 2)
        XCTAssertTrue(partial.canRetryFailed)
        XCTAssertEqual(try campaign(["totalCount": .integer(2), "successCount": .integer(2), "failedCount": .integer(0), "status": .string("COMPLETED")]).phase, .completed)
        let missing = try campaign(["totalCount": .integer(1), "successCount": .integer(3)])
        XCTAssertEqual(missing.phase, .delivering); XCTAssertFalse(missing.processing); XCTAssertEqual(missing.failedCount, 0); XCTAssertEqual(missing.pendingCount, 0)
    }
    func testCampaignRejectsMissingIDAndNegativeCounts() {
        XCTAssertThrowsError(try ClubOpsNotifyCampaign(value: .object(["totalCount": .integer(1)])))
        XCTAssertThrowsError(try campaign(["failedCount": .integer(-1)]))
        XCTAssertThrowsError(try campaign(["totalCount": .string("x")]))
    }
    func testAudienceRowsKeepNullUnknownAndOrder() throws {
        let rows = try ClubOpsNotifyPresentation.audienceRows(.object(["counts": .object(["ALL_MEMBERS": .integer(8), "ADMINS": .integer(1), "REGISTERED": .integer(8), "WAITLIST": .null, "NO_SHOW": .integer(0), "INACTIVE": .integer(-2)])]))
        XCTAssertEqual(rows.map(\.id), ClubOpsNotifyPresentation.audienceIDs)
        XCTAssertEqual(rows.map(\.count), [8, 1, 8, nil, 0, nil])
        XCTAssertThrowsError(try ClubOpsNotifyPresentation.audienceRows(.object([:])))
    }
    func testDraftIssueMatchesMiniProgramOrderAndBounds() {
        typealias P = ClubOpsNotifyPresentation
        XCTAssertEqual(P.draftIssue(title: "  ", content: ""), .title)
        XCTAssertEqual(P.draftIssue(title: String(repeating: "a", count: 81), content: "ok"), .title)
        XCTAssertEqual(P.draftIssue(title: "周六集合", content: " "), .content)
        XCTAssertEqual(P.draftIssue(title: "周六集合", content: String(repeating: "a", count: 1001)), .content)
        XCTAssertNil(P.draftIssue(title: String(repeating: "a", count: 80), content: String(repeating: "a", count: 1000)))
        XCTAssertEqual(P.previewCount(.object(["recipientCount": .integer(0)])), 0)
        XCTAssertNil(P.previewCount(.object(["recipientCount": .integer(-1)])))
    }
}
