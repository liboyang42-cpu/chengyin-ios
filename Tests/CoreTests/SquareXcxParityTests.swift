import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// w2-07: mini-program Square list/detail presentation and the dormant deletion contract.
final class SquareXcxParityTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)  // fixed synthetic clock

    private func post(_ json: String, _ generation: SquareContentGeneration = .communityV1) throws -> SquarePost {
        try JSONDecoder().decode(SquarePost.self, from: Data(json.utf8)).qualified(as: generation)
    }
    private func china(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f.string(from: date)
    }

    func testRelativeAgeMatchesSourceBuckets() {
        XCTAssertEqual(SquareRelativeAge.of(china(base.addingTimeInterval(-20)), now: base), .justNow)
        XCTAssertEqual(SquareRelativeAge.of(china(base.addingTimeInterval(-5 * 60)), now: base), .hoursMinutes(hours: 0, minutes: 5))
        XCTAssertEqual(SquareRelativeAge.of(china(base.addingTimeInterval(-(2 * 3600 + 7 * 60))), now: base), .hoursMinutes(hours: 2, minutes: 7))
        XCTAssertEqual(SquareRelativeAge.of(china(base.addingTimeInterval(-3 * 86_400 - 60)), now: base), .days(3))
        XCTAssertEqual(SquareRelativeAge.of(china(base.addingTimeInterval(600)), now: base), .justNow)
        XCTAssertNil(SquareRelativeAge.of("not a time", now: base))
        XCTAssertNil(SquareRelativeAge.of("", now: base))
    }

    func testWallClockIsChinaTimeAndISOKeepsOffset() {
        XCTAssertEqual(SquareXcxTime.date("2026-10-19 08:00:00"), SquareXcxTime.date("2026-10-19T00:00:00Z"))
        XCTAssertEqual(SquareXcxTime.date("1790000000000"), Date(timeIntervalSince1970: 1_790_000_000))
    }

    private func event(_ id: Int, status: Int, banner: Bool, startOffset: TimeInterval, avatars: Int = 0, participants: Int? = nil) throws -> OfficialEvent {
        var raw: [String: Any] = ["id": id, "title": "Synthetic event \(id)", "status": status, "bannerEnabled": banner ? 1 : 0,
                                  "activityStart": (base.timeIntervalSince1970 + startOffset) * 1000, "city": "Example city",
                                  "participantAvatars": (0..<avatars).map { "https://example.invalid/a\($0).png" }]
        if let participants { raw["participants"] = participants }
        return try JSONDecoder().decode(OfficialEvent.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    func testUpcomingBannerFiltersWindowStatusAndFlagThenSorts() throws {
        let events = [try event(1, status: 2, banner: true, startOffset: 7200),
                      try event(2, status: 1, banner: true, startOffset: 600, avatars: 5, participants: 12),
                      try event(3, status: 3, banner: true, startOffset: 600),
                      try event(4, status: 2, banner: false, startOffset: 600),
                      try event(5, status: 2, banner: true, startOffset: 86_400),
                      try event(6, status: 2, banner: true, startOffset: -60)]
        let items = SquareUpcomingBannerItem.select(events, now: base)
        XCTAssertEqual(items.map(\.id), [2, 1])
        XCTAssertEqual(items[0].avatars.count, 3)
        XCTAssertEqual(items[0].overflow, 9)
        XCTAssertEqual(items[0].subtitle, "Example city")
        XCTAssertEqual(items[0].countdown(now: base), .minutes(10))
        XCTAssertEqual(items[1].countdown(now: base), .hours(2))
        XCTAssertEqual(items[1].countdown(now: base.addingTimeInterval(7170)), .soon)
    }

    func testCardFactsForPlayAndCompletionShares() throws {
        let template = try post(#"{"post":{"id":9,"authorId":3,"body":"x","version":1,"lifecycle":"CHECKING"},"sportName":"Synthetic route","sportCover":"https://example.invalid/c.png","isTopicTemplate":1,"sportTopicId":31,"nodeTotal":5,"nodeDoneCount":2}"#)
        let facts = SquarePostCardFacts(template)
        XCTAssertTrue(facts.hasPlayCover); XCTAssertFalse(facts.isCompletionShare)
        XCTAssertEqual(facts.playSubtitle, .progress(done: 2, total: 5))
        XCTAssertEqual(facts.lifecycle, .checking)
        XCTAssertTrue(facts.isRemixable)
        XCTAssertNil(facts.leadingRoutePreview)

        let roam = try post(#"{"post":{"id":10,"authorId":3,"pics":"https://example.invalid/1.png;https://example.invalid/2.png","dataType":3,"dataId":4},"completed":1,"nodeTotal":4}"#)
        let roamFacts = SquarePostCardFacts(roam)
        XCTAssertTrue(roamFacts.isCompletionShare)
        XCTAssertEqual(roamFacts.strip, [])
        XCTAssertEqual(roamFacts.playCover, "https://example.invalid/1.png")

        let plain = try post(#"{"id":11,"memberId":3,"contents":"short","pics":"https://example.invalid/1.png;https://example.invalid/2.png","routePreviewImg":"https://example.invalid/r.png"}"#, .legacySquare)
        let plainFacts = SquarePostCardFacts(plain)
        XCTAssertEqual(plainFacts.leadingRoutePreview, "https://example.invalid/r.png")
        XCTAssertTrue(plainFacts.showsCountPill)
        XCTAssertFalse(plainFacts.bodyExpandable)
        XCTAssertNil(plainFacts.lifecycle)  // PUBLISHED shows no review line
    }

    func testBodyExpandableAtSourceThresholds() throws {
        func body(_ text: String) throws -> SquarePost {
            let raw: [String: Any] = ["id": 12, "memberId": 3, "contents": text]
            return try JSONDecoder().decode(SquarePost.self, from: JSONSerialization.data(withJSONObject: raw)).qualified(as: .legacySquare)
        }
        XCTAssertTrue(SquarePostCardFacts(try body(String(repeating: "字", count: 41))).bodyExpandable)
        XCTAssertTrue(SquarePostCardFacts(try body("a\nb\nc")).bodyExpandable)
        XCTAssertFalse(SquarePostCardFacts(try body(String(repeating: "字", count: 40))).bodyExpandable)
    }
}

private final class DeletionTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var reply: () throws -> (Data, Int)
    init(_ reply: @escaping () throws -> (Data, Int)) { self.reply = reply }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try reply() }
}

@MainActor final class SquareDeletionFlowTests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.invalid")!
    private func coordinator(_ transport: DeletionTransport, approved: Set<String>?) throws -> SquareDeletionCoordinator {
        let configuration = try APIConfiguration(baseURL: baseURL)
        let approval = try approved.map { try OperationEndpointApproval(baseURL: baseURL, namespace: "cn", accountID: 7, paths: $0) }
        return SquareDeletionCoordinator(service: .init(configuration: configuration, transport: transport), configuration: configuration,
                                         approval: approval, current: { ("cn", 7, "synthetic-token") })
    }
    private let target = SquareDeletionTarget.post(id: 41, expectedVersion: 3)

    func testWithoutApprovalNothingDispatches() async throws {
        let transport = DeletionTransport { (Data(#"{"code":200}"#.utf8), 200) }
        let flow = try coordinator(transport, approved: nil)
        flow.prepare(target)
        XCTAssertEqual(flow.phase, .disabled)
        await flow.confirm()
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertFalse(SquareDeletionCoordinator.disabled().isAllowed(target))
    }

    func testApprovedDeleteSendsSourceWireOnceAfterExplicitConfirm() async throws {
        let transport = DeletionTransport { (Data(#"{"code":200}"#.utf8), 200) }
        let flow = try coordinator(transport, approved: [SquareDeletionTarget.postRoute])
        await flow.confirm()  // no prepare: no dispatch
        XCTAssertTrue(transport.requests.isEmpty)
        flow.prepare(target)
        XCTAssertEqual(flow.phase, .confirming(target))
        await flow.confirm()
        XCTAssertEqual(flow.phase, .done(target))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/api/v1/community/posts/41")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["expectedVersion"] as? Int, 3)
        XCTAssertEqual(Set(body.keys), ["expectedVersion", "requestId"])
    }

    func testCommentRouteNeedsItsOwnApproval() throws {
        let flow = try coordinator(DeletionTransport { (Data(), 200) }, approved: [SquareDeletionTarget.postRoute])
        XCTAssertFalse(flow.isAllowed(.comment(postID: 41, commentID: 5, expectedVersion: 0)))
        XCTAssertEqual(SquareDeletionTarget.comment(postID: 41, commentID: 5, expectedVersion: 0).path, "api/v1/community/posts/41/comments/5")
    }

    func testUnknownKeepsRequestIDAndBlocksOtherTargetsUntilReadback() async throws {
        var fail = true
        let transport = DeletionTransport { if fail { throw URLError(.timedOut) }; return (Data(#"{"code":200}"#.utf8), 200) }
        let flow = try coordinator(transport, approved: [SquareDeletionTarget.postRoute])
        flow.prepare(target); await flow.confirm()
        XCTAssertEqual(flow.phase, .unknown(target))
        let firstID = try XCTUnwrap(flow.requestID(for: target))
        flow.prepare(.post(id: 42, expectedVersion: 0))
        XCTAssertEqual(flow.phase, .unknown(target))
        flow.resolveUnknown(stillPresent: nil)  // failed readback keeps the lock
        XCTAssertEqual(flow.phase, .unknown(target))
        flow.resolveUnknown(stillPresent: true)
        XCTAssertEqual(flow.phase, .confirming(target))
        fail = false; await flow.confirm()
        XCTAssertEqual(flow.phase, .done(target))
        var ids: [String] = []
        for request in transport.requests {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
            ids.append(try XCTUnwrap(body["requestId"] as? String))
        }
        XCTAssertEqual(ids, [firstID, firstID])
    }

    func testReadbackShowingGoneConfirmsWithoutDispatch() async throws {
        let transport = DeletionTransport { (Data("<html>".utf8), 502) }
        let flow = try coordinator(transport, approved: [SquareDeletionTarget.postRoute])
        flow.prepare(target); await flow.confirm()
        XCTAssertEqual(flow.phase, .unknown(target))
        flow.resolveUnknown(stillPresent: false)
        XCTAssertEqual(flow.phase, .done(target))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testBusinessRejectionIsTerminalAndKeepsMessage() async throws {
        let transport = DeletionTransport { (Data(#"{"code":409,"msg":"Synthetic version conflict"}"#.utf8), 200) }
        let flow = try coordinator(transport, approved: [SquareDeletionTarget.postRoute])
        flow.prepare(target); await flow.confirm()
        XCTAssertEqual(flow.phase, .rejected(target, "Synthetic version conflict"))
        XCTAssertNil(flow.requestID(for: target))
    }

    func testLegacyAndUnversionedContentCannotTargetDeletion() throws {
        let legacy = try JSONDecoder().decode(SquarePost.self, from: Data(#"{"id":5,"memberId":3}"#.utf8)).qualified(as: .legacySquare)
        XCTAssertNil(SquareDeletionTarget(post: legacy))
        let community = try JSONDecoder().decode(SquarePost.self, from: Data(#"{"post":{"id":5,"authorId":3,"version":2}}"#.utf8)).qualified(as: .communityV1)
        XCTAssertEqual(SquareDeletionTarget(post: community), .post(id: 5, expectedVersion: 2))
    }

    func testRetireDropsPendingIdentity() async throws {
        let flow = try coordinator(DeletionTransport { throw URLError(.networkConnectionLost) }, approved: [SquareDeletionTarget.postRoute])
        flow.prepare(target); await flow.confirm()
        flow.retire()
        XCTAssertEqual(flow.phase, .idle)
        XCTAssertNil(flow.requestID(for: target))
    }
}
