import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor PrivateToolsWire: HTTPTransport {
    enum Reply { case body(String, Int), failure }
    var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    init(_ bodies: [String]) { replies = bodies.map { .body($0, 200) } }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch replies.removeFirst() {
        case .body(let text, let status): return (Data(text.utf8), status)
        case .failure: throw URLError(.timedOut)
        }
    }
}

@MainActor final class RoamPassportPrivateToolsTests: XCTestCase {
    private let base = URL(string: "https://tools.example/native")!
    /// 2026-10-19 12:00 Asia/Shanghai, a Monday.
    private let now = Date(timeIntervalSince1970: 1_792_382_400)
    private func service(_ wire: PrivateToolsWire) throws -> RoamPrivateToolsService {
        .init(configuration: try APIConfiguration(baseURL: base), transport: wire)
    }
    private func body(_ request: URLRequest) -> String { String(decoding: request.httpBody ?? Data(), as: UTF8.self) }
    private func goalJSON(id: String = "22", requestID: String = "request_goal_00000001", state: String = "ACTIVE", progress: Int = 2,
                          commemoration: Bool = false, counting: String = "COMPLETED_SESSION_AGGREGATE_V1", target: Int = 5) -> String {
        #"{"id":"\#(id)","requestId":"\#(requestID)","metric":"DISTINCT_ROUTES","target":\#(target),"startDate":"2026-10-19","endDateExclusive":"2026-11-01","progress":\#(progress),"state":"\#(state)","privateCommemoration":\#(commemoration),"timeZone":"Asia/Shanghai","countingVersion":"\#(counting)","asOfMs":1792382400000,"createdAtMs":1792382400000}"#
    }
    private let snapshotID = String(repeating: "a", count: 64)
    private func snapshotFields(expected: Int = 3, upper: String = "903", pageSize: Int = 2) -> String {
        #""format":"chengyin-exploration-export-v1","timeZone":"Asia/Shanghai","snapshotId":"\#(snapshotID)","startDate":"2026-09-20","endDateExclusive":"2026-10-20","asOfMs":1792382400000,"expiresAtMs":1792468800000,"upperRecordId":"\#(upper)","expectedRows":\#(expected),"pageSize":\#(pageSize)"#
    }
    private let cursor0 = "c" + String(repeating: "0", count: 47)
    private let cursor1 = "c" + String(repeating: "1", count: 47)
    private func row(_ id: String, _ at: String, title: String? = "老城墙夜行", available: Bool = true) -> String {
        #"{"recordId":"\#(id)","completedAt":"\#(at)","routeVersion":"4","elapsedSeconds":60,"routeAvailability":"\#(available ? "AVAILABLE" : "UNAVAILABLE")","routeTitle":\#(title.map { "\"\($0)\"" } ?? "null")}"#
    }

    func testShanghaiCivilCalendarRoundTripsAndKnowsMonday() {
        XCTAssertEqual(RoamShanghaiCalendar.dateText(atMilliseconds: 1_792_382_400_000), "2026-10-19")
        // 2026-10-18 16:30 UTC is already the 19th in Shanghai.
        XCTAssertEqual(RoamShanghaiCalendar.dateText(atMilliseconds: 1_792_341_000_000), "2026-10-19")
        let day = RoamShanghaiCalendar.parseDate("2026-10-19")!
        XCTAssertEqual(RoamShanghaiCalendar.mondayIndex(dayNumber: day), 0)
        XCTAssertEqual(RoamShanghaiCalendar.dateText(dayNumber: day + 74), "2027-01-01")
        XCTAssertEqual(RoamShanghaiCalendar.parseDate("2024-02-29").map { RoamShanghaiCalendar.dateText(dayNumber: $0) }, "2024-02-29")
        for bad in ["2026-02-29", "2026-13-01", "2026-1-01", "２０２６-10-19", "2026/10/19"] { XCTAssertNil(RoamShanghaiCalendar.parseDate(bad), bad) }
        XCTAssertTrue(RoamPrivateRequestID.isValid(RoamPrivateRequestID.make()))
        XCTAssertFalse(RoamPrivateRequestID.isValid("short"))
    }

    func testCapsuleListRedactsContentAndSendsOwnerGET() async throws {
        let wire = PrivateToolsWire([#"{"code":200,"data":{"items":[{"id":"12","state":"OPEN","unlockAtMs":1792209600000,"createdAtMs":1775102400000,"body":"secret","photoUrl":"https://x.example/p"},{"id":11,"state":"LOCKED","unlockAtMs":1796274000000,"createdAtMs":1790654400000,"body":"leak"}],"hasMore":true,"nextBeforeId":"11"}}"#])
        let page = try await service(wire).capsules(beforeID: nil, token: "token-a")
        XCTAssertEqual(page.items.map(\.id), ["12", "11"])
        XCTAssertEqual(page.items[0].body, "secret")
        XCTAssertNil(page.items[1].body, "A locked capsule never keeps body text")
        XCTAssertEqual(page.items[1].daysLeft(now: now), 46)
        XCTAssertEqual(page.nextBeforeID, "11")
        let request = await wire.requests[0]
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://tools.example/native/api/capsules/list?limit=20")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "token-a")
    }

    func testCapsuleUnknownStatesAndCursorDriftAreUnconfirmed() async throws {
        for json in [#"{"code":200,"data":{"items":[{"id":"1","state":"SEALED"}],"hasMore":false,"nextBeforeId":null}}"#,
                     #"{"code":200,"data":{"items":[{"id":"1","state":"LOCKED"}],"hasMore":false,"nextBeforeId":"1"}}"#,
                     #"{"code":200,"data":{"items":[{"id":"1","state":"LOCKED"},{"id":"1","state":"LOCKED"}],"hasMore":false,"nextBeforeId":null}}"#] {
            do { _ = try await service(PrivateToolsWire([json])).capsules(beforeID: nil, token: "t"); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testCapsuleCreateSendsOrderedJSONAndClassifiesOutcomes() async throws {
        let draft = RoamCapsuleDraft(requestID: "ios_0123456789abcdef", body: "写给\"未来\"", unlockDate: "2027-10-19")
        let ok = PrivateToolsWire([#"{"code":200,"data":{"id":"40","state":"LOCKED","unlockAtMs":1823702400000,"createdAtMs":1792382400000}}"#])
        let created = try await service(ok).createCapsule(draft, now: now, token: "t")
        XCTAssertEqual(created.state, .locked)
        let request = await ok.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/native/api/capsules/create")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(body(request), #"{"requestId":"ios_0123456789abcdef","body":"写给\"未来\"","photoUrl":"","unlockDate":"2027-10-19"}"#)
        let cases: [(PrivateToolsWire.Reply, RoamPrivateWriteError)] = [
            (.body(#"{"code":400,"msg":"请选择未来十年内的开启日期"}"#, 200), .rejected("请选择未来十年内的开启日期")),
            (.body(#"{"code":409,"msg":"原请求编号已用于不同内容"}"#, 200), .outcomeUnknown),
            (.body(#"{"code":500}"#, 200), .outcomeUnknown), (.body("", 502), .outcomeUnknown), (.failure, .outcomeUnknown),
            (.body(#"{"code":200,"data":{"id":"40","state":"MAYBE"}}"#, 200), .outcomeUnknown)]
        for (reply, expected) in cases {
            do { _ = try await service(PrivateToolsWire([reply])).createCapsule(draft, now: now, token: "t"); XCTFail() }
            catch { XCTAssertEqual(error as? RoamPrivateWriteError, expected) }
        }
    }

    func testCapsuleDraftRulesAndUnlockPresets() {
        XCTAssertEqual(RoamCapsuleUnlockOption.options(now: now).map(\.date), ["2026-11-18", "2027-04-19", "2027-10-19"])
        XCTAssertEqual(RoamCapsuleUnlockOption.minimumDate(now: now), "2026-10-20")
        for (text, date) in [("  ", "2027-01-01"), (String(repeating: "字", count: 4001), "2027-01-01"), ("ok", "2026-10-19"), ("ok", "2036-12-31"), ("ok", "2027-02-30")] {
            XCTAssertThrowsError(try RoamCapsuleDraft(body: text, unlockDate: date).validate(now: now), date)
        }
        XCTAssertNoThrow(try RoamCapsuleDraft(body: "ok", unlockDate: "2026-10-20").validate(now: now))
        XCTAssertNoThrow(try RoamCapsuleDraft(body: String(repeating: "字", count: 4000), unlockDate: "2036-10-19").validate(now: now))
    }

    func testDeleteAndCancelUseFormBodiesAndRequireConfirmedState() async throws {
        let wire = PrivateToolsWire([#"{"code":200,"data":{"id":"12","state":"DELETED"}}"#, #"{"code":200,"data":{"id":"12","state":"LOCKED"}}"#])
        let deleted = try await service(wire).deleteCapsule(id: "12", token: "t")
        XCTAssertEqual(deleted.state, .deleted)
        let request = await wire.requests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(body(request), "id=12")
        do { _ = try await service(wire).deleteCapsule(id: "12", token: "t"); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .outcomeUnknown) }
        let cancel = PrivateToolsWire([#"{"code":200,"data":\#(goalJSON(state: "CANCELLED"))}"#])
        let goal = try await service(cancel).cancelGoal(id: "22", token: "t")
        XCTAssertEqual(goal.state, .cancelled)
        let cancelRequest = await cancel.requests[0]
        XCTAssertEqual(body(cancelRequest), "id=22")
        do { _ = try await service(PrivateToolsWire([String]())).deleteCapsule(id: "012", token: "t"); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .invalidDraft) }
    }

    func testGoalProjectionIsStrict() async throws {
        let good = PrivateToolsWire([#"{"code":200,"data":\#(goalJSON())}"#])
        let goal = try await service(good).goal(id: "22", token: "t")
        XCTAssertEqual(goal.percent, 40)
        let detailRequest = await good.requests[0]
        XCTAssertEqual(detailRequest.url?.absoluteString, "https://tools.example/native/api/exploration-goals/detail?id=22")
        for bad in [goalJSON(state: "ACHIEVED", progress: 5, commemoration: false), goalJSON(state: "ACHIEVED", progress: 3, commemoration: true),
                    goalJSON(counting: "LIVE"), goalJSON(target: 101), goalJSON(id: "022"), goalJSON(requestID: "x")] {
            do { _ = try await service(PrivateToolsWire([#"{"code":200,"data":\#(bad)}"#])).goal(id: "22", token: "t"); XCTFail(bad) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testGoalListCursorMustBeLastItemAndCancelledStaysCancelled() async throws {
        let list = #"{"code":200,"data":{"items":[\#(goalJSON(id: "22")),\#(goalJSON(id: "21", requestID: "request_goal_00000002"))],"hasMore":true,"nextBeforeId":"21"}}"#
        let page = try await service(PrivateToolsWire([list])).goals(beforeID: nil, confirmedCancelled: ["22"], token: "t")
        XCTAssertEqual(page.items.map(\.state), [.cancelled, .active], "A late list never revives a confirmed cancellation")
        let drift = list.replacingOccurrences(of: #""nextBeforeId":"21""#, with: #""nextBeforeId":"22""#)
        do { _ = try await service(PrivateToolsWire([drift])).goals(beforeID: nil, token: "t"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }

    func testGoalCreateRequiresMatchingEchoAndTreats409AsRefusal() async throws {
        let draft = RoamGoalDraft(requestID: "request_goal_00000001", metric: .distinctRoutes, target: 5, startDate: "2026-10-19", endDateExclusive: "2026-11-01")
        let wire = PrivateToolsWire([#"{"code":200,"data":\#(goalJSON())}"#])
        _ = try await service(wire).createGoal(draft, now: now, token: "t")
        let createRequest = await wire.requests[0]
        XCTAssertEqual(body(createRequest), #"{"requestId":"request_goal_00000001","metric":"DISTINCT_ROUTES","target":5,"startDate":"2026-10-19","endDateExclusive":"2026-11-01"}"#)
        let cases: [(String, RoamPrivateWriteError)] = [(#"{"code":409,"msg":"冲突"}"#, .rejected("冲突")), (#"{"code":400}"#, .rejected(nil)),
                                                        (#"{"code":200,"data":\#(goalJSON(target: 6))}"#, .outcomeUnknown)]
        for (reply, expected) in cases {
            do { _ = try await service(PrivateToolsWire([reply])).createGoal(draft, now: now, token: "t"); XCTFail(reply) }
            catch { XCTAssertEqual(error as? RoamPrivateWriteError, expected) }
        }
        XCTAssertThrowsError(try RoamGoalDraft(metric: .explorationDays, target: 3, startDate: "2026-10-18", endDateExclusive: "2026-10-25").validate(now: now))
        XCTAssertThrowsError(try RoamGoalDraft(metric: .explorationDays, target: 0, startDate: "2026-10-19", endDateExclusive: "2026-10-25").validate(now: now))
        XCTAssertThrowsError(try RoamGoalDraft(metric: .explorationDays, target: 3, startDate: "2026-10-25", endDateExclusive: "2026-10-25").validate(now: now))
    }

    func testGoalPeriodsStartTodayAndKeepTheirEnds() {
        let periods = RoamGoalPeriod.periods(now: now)
        XCTAssertEqual(periods.map(\.startDate), ["2026-10-19", "2026-10-19", "2026-10-19"])
        XCTAssertEqual(periods.map(\.endDateExclusive), ["2026-10-26", "2026-11-01", "2026-11-18"])
        // Thursday 2026-12-31: week started Monday the 28th but begins today; month rolls into the new year.
        let late = RoamGoalPeriod.periods(now: Date(timeIntervalSince1970: 1_798_689_600))
        XCTAssertEqual(late.map(\.startDate), ["2026-12-31", "2026-12-31", "2026-12-31"])
        XCTAssertEqual(late.map(\.endDateExclusive), ["2027-01-04", "2027-01-01", "2027-01-30"])
    }

    func testExportPrepareAndChunksBuildCompleteJSONL() async throws {
        let wire = PrivateToolsWire([
            #"{"code":200,"data":{\#(snapshotFields()),"cursor":"\#(cursor0)"}}"#,
            #"{"code":200,"data":{\#(snapshotFields()),"cursor":"\#(cursor0)","offset":0,"items":[\#(row("903", "2026-10-18T19:42:10.120+08:00")),\#(row("877", "2026-10-09T09:05:00.000+08:00", title: nil))],"complete":false,"state":"MORE","nextCursor":"\#(cursor1)","emittedRows":2}}"#,
            #"{"code":200,"data":{\#(snapshotFields()),"cursor":"\#(cursor1)","offset":2,"items":[\#(row("851", "2026-09-30T16:20:00.500+08:00", title: nil, available: false))],"complete":true,"state":"COMPLETE","nextCursor":null,"emittedRows":3}}"#])
        let tools = try service(wire)
        let start = try await tools.prepareExport(.init(startDate: "2026-09-20", endDateExclusive: "2026-10-20", pageSize: 2), token: "t")
        let prepareRequest = await wire.requests[0]
        XCTAssertEqual(body(prepareRequest), #"{"startDate":"2026-09-20","endDateExclusive":"2026-10-20","pageSize":2}"#)
        let first = try await tools.exportPage(start, token: "t")
        let pageRequest = await wire.requests[1]
        XCTAssertEqual(body(pageRequest), #"{"cursor":"\#(cursor0)"}"#)
        let lines = first.data!.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[0], #"{"type":"metadata","format":"chengyin-exploration-export-v1","snapshot":{\#(snapshotFields())},"part":1,"offset":0}"#)
        XCTAssertEqual(lines[1], #"{"type":"record","recordId":"903","completedAt":"2026-10-18T19:42:10.120+08:00","routeVersion":"4","elapsedSeconds":60,"routeAvailability":"AVAILABLE","routeTitle":"老城墙夜行"}"#)
        XCTAssertEqual(lines[3], #"{"type":"footer","part":1,"emittedRows":2,"expectedRows":3,"complete":false}"#)
        let last = try await tools.exportPage(first.checkpoint, token: "t")
        XCTAssertTrue(last.checkpoint.complete)
        XCTAssertEqual(last.checkpoint.offset, 3)
        XCTAssertEqual(start.snapshot.fileName, "chengyin-exploration-20260920-20261020.jsonl")
        XCTAssertTrue(last.data!.hasSuffix(#"{"type":"footer","part":2,"emittedRows":3,"expectedRows":3,"complete":true}"# + "\n"))
    }

    func testExportRejectsReorderedRowsDriftAndReportsSourceChange() async throws {
        let start = try RoamExportCheckpoint.prepared(RoamPrivateEnvelope.parse(Data(#"{"code":200,"data":{\#(snapshotFields()),"cursor":"\#(cursor0)"}}"#.utf8)),
                                                      request: .init(startDate: "2026-09-20", endDateExclusive: "2026-10-20", pageSize: 2))
        let bad = [
            // ascending IDs
            #"{"code":200,"data":{\#(snapshotFields()),"cursor":"\#(cursor0)","offset":0,"items":[\#(row("877", "2026-10-09T09:05:00.000+08:00")),\#(row("903", "2026-10-18T19:42:10.120+08:00"))],"complete":false,"state":"MORE","nextCursor":"\#(cursor1)","emittedRows":2}}"#,
            // outside the range
            #"{"code":200,"data":{\#(snapshotFields()),"cursor":"\#(cursor0)","offset":0,"items":[\#(row("903", "2026-10-20T00:00:00.000+08:00")),\#(row("877", "2026-10-09T09:05:00.000+08:00"))],"complete":false,"state":"MORE","nextCursor":"\#(cursor1)","emittedRows":2}}"#,
            // unavailable route leaking a title
            #"{"code":200,"data":{\#(snapshotFields()),"cursor":"\#(cursor0)","offset":0,"items":[\#(row("903", "2026-10-18T19:42:10.120+08:00", available: false)),\#(row("877", "2026-10-09T09:05:00.000+08:00"))],"complete":false,"state":"MORE","nextCursor":"\#(cursor1)","emittedRows":2}}"#,
            // snapshot drift
            #"{"code":200,"data":{\#(snapshotFields(expected: 4)),"cursor":"\#(cursor0)","offset":0,"items":[],"complete":false,"state":"SOURCE_CHANGED","nextCursor":null,"emittedRows":0}}"#]
        for json in bad {
            XCTAssertThrowsError(try RoamExportChunk.decode(RoamPrivateEnvelope.parse(Data(json.utf8)), original: start)) { XCTAssertEqual($0 as? APIError, .malformedResponse) }
        }
        let changed = try RoamExportChunk.decode(RoamPrivateEnvelope.parse(Data(#"{"code":200,"data":{\#(snapshotFields()),"cursor":"\#(cursor0)","offset":0,"items":[],"complete":false,"state":"SOURCE_CHANGED","nextCursor":null,"emittedRows":0}}"#.utf8)), original: start)
        XCTAssertTrue(changed.restartRequired)
        XCTAssertNil(changed.data)
        XCTAssertTrue(changed.checkpoint.changed)
        XCTAssertEqual(RoamExportRangePreset.presets(now: now).map(\.startDate), ["2026-09-20", "2026-01-01", "2025-10-19"])
        XCTAssertEqual(RoamExportRangePreset.presets(now: now).map(\.endDateExclusive), ["2026-10-20", "2026-10-20", "2026-10-20"])
        XCTAssertFalse(RoamExportContract.isValidRange(start: "2025-10-18", end: "2026-10-20"))
        XCTAssertFalse(RoamExportContract.isValidRange(start: "1999-12-31", end: "2000-01-02"))
    }

    func testSessionReaderFailsClosedWithoutApprovalAndKeepsWritesSeparate() async throws {
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "roam-tools", token: "synthetic-7")
        var context: RuntimeDependencyContext? = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: session)
        let wire = PrivateToolsWire([#"{"code":200,"data":{"items":[],"hasMore":false,"nextBeforeId":null}}"#])
        var access: RoamPrivateToolsAccess?
        let reader = RoamPrivateToolsSessionReader(service: try service(wire), current: { context }, access: { _ in access })
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.capsules(beforeID: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let unapproved = await wire.requests.count
        XCTAssertEqual(unapproved, 0, "No approval, no request")
        access = try RoamPrivateToolsAccess(context: context!, approval: .init(baseURL: base, namespace: "roam-tools", accountID: 7, paths: RoamPrivateToolsRoute.reads))
        XCTAssertTrue(reader.isConfigured)
        XCTAssertFalse(reader.allowsWrites)
        _ = try await reader.capsules(beforeID: nil)
        do { _ = try await reader.createCapsule(.init(body: "ok", unlockDate: "2030-01-01")); XCTFail() }
        catch { XCTAssertEqual(error as? RoamPrivateWriteError, .writesDisabled) }
        let approvedReads = await wire.requests.count
        XCTAssertEqual(approvedReads, 1)
        reader.pendingCapsule = RoamCapsuleDraft(body: "ok", unlockDate: "2030-01-01")
        context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
                                           session: try PlayExperienceSession(accountID: 8, epoch: 1, namespace: "roam-tools", token: "synthetic-8"))
        XCTAssertNil(reader.pendingCapsule, "Another account never sees the earlier unconfirmed request")
        XCTAssertFalse(reader.isConfigured, "The approval is bound to the original account")
        XCTAssertThrowsError(try RoamPrivateToolsAccess(context: context!, approval: .init(baseURL: base, namespace: "roam-tools", accountID: 8, paths: ["api/roam/session"])))
    }

    func testCapsuleCoordinatorKeepsUnknownCreateUntilReceiptReadback() async {
        let fixture = RoamPrivateToolsFixture(scenario: .unknownCreate)
        let model = RoamCapsuleCoordinator(tools: fixture)
        await model.load()
        XCTAssertEqual(model.items.map(\.state), [.open, .locked])
        XCTAssertNil(model.items[1].body)
        model.prepareCreate(body: "给明年的自己", unlockDate: "2027-10-19")
        let reviewed = model.review
        XCTAssertNotNil(reviewed)
        XCTAssertTrue(fixture.dispatchedWrites.isEmpty, "Preparing a review never dispatches")
        let created = await model.confirmCreate()
        XCTAssertFalse(created)
        XCTAssertEqual(model.issue, .outcomeUnknown)
        XCTAssertEqual(model.pending, reviewed, "The exact reviewed request stays pending")
        model.prepareCreate(body: "另一枚", unlockDate: "2027-10-19")
        XCTAssertEqual(model.issue, .pendingFirst)
        await model.verifyPending()
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.items.count, 3)
        XCTAssertEqual(fixture.dispatchedWrites, [RoamPrivateToolsRoute.capsuleCreate])
        await model.open(model.items.first { $0.state == .open }!)
        XCTAssertEqual(model.opened?.body, "写给今天的自己：记得那次老城墙夜行。")
        model.prepareDelete()
        await model.confirmDelete()
        XCTAssertTrue(model.deleted)
        XCTAssertNil(model.opened)
    }

    func testReadOnlyFixtureNeverDispatchesWrites() async {
        let fixture = RoamPrivateToolsFixture(scenario: .readOnly)
        let capsules = RoamCapsuleCoordinator(tools: fixture), goals = RoamGoalsCoordinator(tools: fixture)
        await capsules.load(); await goals.load()
        capsules.prepareCreate(body: "x", unlockDate: "2027-01-01")
        goals.prepareCreate(metric: .distinctRoutes, target: 5, startDate: "2026-10-19", endDateExclusive: "2026-11-01")
        XCTAssertEqual(capsules.issue, .writesDisabled)
        XCTAssertEqual(goals.issue, .writesDisabled)
        XCTAssertNil(capsules.review); XCTAssertNil(goals.review)
        XCTAssertFalse(capsules.canWrite)
        XCTAssertTrue(fixture.dispatchedWrites.isEmpty)
    }

    func testGoalsCoordinatorCreatesAndCancelsOnce() async {
        let fixture = RoamPrivateToolsFixture()
        let model = RoamGoalsCoordinator(tools: fixture)
        await model.load()
        XCTAssertEqual(model.rows.map(\.state), [.active, .achieved])
        let week = model.periods[0]
        model.prepareCreate(metric: .explorationDays, target: 3, startDate: week.startDate, endDateExclusive: week.endDateExclusive)
        let created = await model.confirmCreate()
        XCTAssertTrue(created)
        XCTAssertEqual(model.rows.count, 3)
        XCTAssertEqual(model.detail?.target, 3)
        model.prepareCancel()
        XCTAssertNotNil(model.cancelReview)
        await model.confirmCancel()
        XCTAssertEqual(model.detail?.state, .cancelled)
        XCTAssertEqual(fixture.dispatchedWrites, [RoamPrivateToolsRoute.goalCreate, RoamPrivateToolsRoute.goalCancel])
        model.prepareCancel()
        XCTAssertNil(model.cancelReview, "A cancelled goal offers no second cancel")
    }

    func testExportCoordinatorReadsEveryChunkBeforeOfferingAFile() async {
        let model = RoamExportCoordinator(tools: RoamPrivateToolsFixture(), pageSize: RoamPrivateToolsFixture.fixturePageSize)
        let range = model.presets[0]
        await model.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
        XCTAssertEqual(model.phase, .prepared)
        XCTAssertEqual(model.expected, 3)
        await model.readNext()
        XCTAssertNil(model.shareableFile, "A partial export is never offered")
        XCTAssertEqual(model.read, 2)
        await model.readNext()
        XCTAssertEqual(model.phase, .complete)
        XCTAssertEqual(model.shareableFile?.rows, 3)
        XCTAssertEqual(model.shareableFile?.content.split(separator: "\n").count, 7)
        model.restart()
        XCTAssertNil(model.file)
        let empty = RoamExportCoordinator(tools: RoamPrivateToolsFixture(scenario: .empty))
        await empty.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
        await empty.readNext()
        XCTAssertEqual(empty.phase, .complete)
        XCTAssertNil(empty.shareableFile, "Zero rows: no empty file to save or share")
    }
}
