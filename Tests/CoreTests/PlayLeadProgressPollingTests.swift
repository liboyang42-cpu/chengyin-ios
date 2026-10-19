import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// I09: team-progress reads follow mini pages/play loadTeamProgress. An older
/// response never replaces a newer applied one, and polling ends with the page.
@available(macOS 14.0, *)
@MainActor final class PlayLeadProgressPollingTests: XCTestCase {
    private func session() throws -> PlayExperienceSession { try .init(accountID: 9001, epoch: 1, namespace: "synthetic-cn", token: "synthetic-token") }
    private func model(_ wire: LeadHoldTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayExperienceCoordinator {
        .init(scope: .activity(41), service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!),
              transport: wire, enabled: [.reads, .leader]), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: current)
    }
    private func lead(_ chapter: String, meArrived: Bool) -> String {
        #"{"exists":true,"status":1,"leaderMemberId":9001,"isLeader":true,"chapterName":"\#(chapter)","arrived":\#(meArrived ? 1 : 0),"meArrived":\#(meArrived),"members":[{"memberId":9001,"nickname":"Synthetic leader","done":0,"arrived":\#(meArrived),"isLeader":true}]}"#
    }
    private func ready(_ wire: LeadHoldTransport) async throws -> (PlayExperienceCoordinator, PlayInteractionContext) {
        let owner = try session(), value = try model(wire) { owner }
        await value.load()
        return (value, try XCTUnwrap(value.interactionContext))
    }

    func testSlowEarlierReadCannotOverwriteNewerAppliedTeamState() async throws {
        let wire = LeadHoldTransport(); let (value, context) = try await ready(wire)
        wire.hold = true
        let slow = Task { await value.loadLead(context: context) }
        await wire.waitForHeld(1)
        let fresh = Task { await value.loadLead(context: context) }
        await wire.waitForHeld(2)
        wire.resume(1, lead("Synthetic newer chapter", meArrived: true)); await fresh.value
        XCTAssertEqual(value.lead?.chapterName, "Synthetic newer chapter")
        wire.resume(0, lead("Synthetic older chapter", meArrived: false)); await slow.value
        XCTAssertEqual(value.lead?.chapterName, "Synthetic newer chapter")
        XCTAssertEqual(value.lead?.meArrived, true)
        XCTAssertFalse(value.leadReadFailed); XCTAssertEqual(value.phase, .ready)
        // The stale "arrive" button state cannot dispatch against the newer read.
        wire.hold = false; let count = wire.requests.count
        await value.performLead(.arrive, context: context)
        XCTAssertEqual(wire.requests.count, count)
        XCTAssertFalse(wire.requests.contains { $0.httpMethod == "POST" })
    }
    func testResponsesSlowerThanTheIntervalStillLandInIssueOrder() async throws {
        let wire = LeadHoldTransport(); let (value, context) = try await ready(wire)
        wire.hold = true
        let first = Task { await value.loadLead(context: context) }
        await wire.waitForHeld(1)
        let second = Task { await value.loadLead(context: context) }
        await wire.waitForHeld(2)
        // Only "older than applied" is discarded, never "older than latest issued".
        wire.resume(0, lead("Synthetic first chapter", meArrived: false)); await first.value
        XCTAssertEqual(value.lead?.chapterName, "Synthetic first chapter")
        wire.resume(1, lead("Synthetic second chapter", meArrived: true)); await second.value
        XCTAssertEqual(value.lead?.chapterName, "Synthetic second chapter")
    }
    func testPollReadsOnlyWhileTeamExistsAndStopsOnExistsFalse() async throws {
        let wire = LeadHoldTransport(); let (value, context) = try await ready(wire)
        await value.pollLead(context: context, sleep: { _ in XCTFail("No team read yet; polling must not start") })
        XCTAssertEqual(wire.leadReads, 0)
        wire.leadReplies = [lead("Synthetic chapter", meArrived: false), lead("Synthetic chapter", meArrived: true), #"{"exists":false}"#]
        await value.loadLead(context: context)
        var sleeps: [UInt64] = []
        await value.pollLead(context: context, sleep: { sleeps.append($0) })
        XCTAssertEqual(wire.leadReads, 3)
        XCTAssertEqual(sleeps, [PlayLeadProgressPolling.intervalNanoseconds, PlayLeadProgressPolling.intervalNanoseconds])
        XCTAssertEqual(value.lead?.exists, false)
        XCTAssertFalse(wire.requests.contains { $0.httpMethod == "POST" })
    }
    func testLeavingThePageCancelsPollAndDropsItsLateResponse() async throws {
        let wire = LeadHoldTransport(); let (value, context) = try await ready(wire)
        await value.loadLead(context: context)
        let before = value.lead
        let idle = Task { await value.pollLead(context: context, sleep: { try await Task.sleep(nanoseconds: 3_600_000_000_000) }) }
        idle.cancel(); await idle.value
        XCTAssertEqual(wire.leadReads, 1)
        wire.hold = true
        let poll = Task { await value.pollLead(context: context, sleep: { _ in }) }
        await wire.waitForHeld(1)
        poll.cancel()
        wire.resume(0, lead("Synthetic late chapter", meArrived: true)); await poll.value
        XCTAssertEqual(value.lead, before)
        XCTAssertFalse(value.leadReadFailed); XCTAssertEqual(value.phase, .ready)
        XCTAssertEqual(wire.leadReads, 2)
    }
    func testChangedAuthorityEndsPollWithoutReading() async throws {
        let wire = LeadHoldTransport(); let (value, context) = try await ready(wire)
        await value.loadLead(context: context)
        await value.load()
        XCTAssertNotEqual(value.interactionContext, context)
        let reads = wire.leadReads
        await value.pollLead(context: context, sleep: { _ in })
        XCTAssertEqual(wire.leadReads, reads)
        let key = PlayLeadProgressPolling.Key(context: value.interactionContext, lead: value.lead, sceneActive: false)
        XCTAssertFalse(key.active)
    }
    func testPollFailureKeepsPageAndLastAppliedTeamUntilNextRead() async throws {
        let wire = LeadHoldTransport(); let (value, context) = try await ready(wire)
        wire.leadReplies = [lead("Synthetic chapter", meArrived: false)]
        await value.loadLead(context: context)
        wire.failNextLeadRead = true
        var rounds = 0
        await value.pollLead(context: context, sleep: { _ in rounds += 1; if rounds > 1 { throw CancellationError() } })
        XCTAssertTrue(value.leadReadFailed); XCTAssertEqual(value.phase, .ready)
        XCTAssertEqual(value.lead?.chapterName, "Synthetic chapter")
        wire.leadReplies = [lead("Synthetic chapter", meArrived: true)]
        rounds = 0
        await value.pollLead(context: context, sleep: { _ in rounds += 1; if rounds > 1 { throw CancellationError() } })
        XCTAssertFalse(value.leadReadFailed); XCTAssertEqual(value.lead?.meArrived, true)
    }
}

@MainActor private final class LeadHoldTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var hold = false
    var failNextLeadRead = false
    var leadReplies: [String] = []
    private var held: [CheckedContinuation<(Data, Int), Error>] = []
    var leadReads: Int { requests.filter { $0.url?.path.hasSuffix("/api/club/lead/team-progress") == true }.count }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        if path.hasSuffix("/api/play/nodes") { return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200) }
        guard path.hasSuffix("/api/club/lead/team-progress") else { throw URLError(.unsupportedURL) }
        if hold { return try await withCheckedThrowingContinuation { held.append($0) } }
        if failNextLeadRead { failNextLeadRead = false; throw URLError(.networkConnectionLost) }
        let raw = leadReplies.isEmpty ? PlayExperienceSyntheticFixtures.lead : leadReplies.removeFirst()
        return (PlayExperienceSyntheticFixtures.envelope(raw), 200)
    }
    func waitForHeld(_ count: Int) async { while held.count < count { await Task.yield() } }
    func resume(_ index: Int, _ raw: String) { held[index].resume(returning: (PlayExperienceSyntheticFixtures.envelope(raw), 200)) }
}
