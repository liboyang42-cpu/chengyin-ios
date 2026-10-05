import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ClubContextualTests: XCTestCase {
    private func configuration() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.com/fixture/")!) }
    private func session() throws -> ClubOpsTimeSession { try .init(accountID: 1, epoch: 1, realm: "https://example.com/fixture/", token: "fixture-token") }
    private func aiSession() -> PublishingSession { .init(namespace: "fixture", accountID: 1, epoch: UUID(), role: "club", region: .china) }
    func testMeetingTimeValidationKeepsActivityDomainAndChinaWallTime() throws {
        let request = try ClubOpsTimeRequest(activityID: 8, startDate: "2026-10-03T14:30:00")
        XCTAssertEqual(request.startDate, "2026-10-03 14:30:00")
        XCTAssertEqual(request.activityId, 8)
        let hiddenSeconds = try XCTUnwrap(ClubOpsTimeRequest.date("2026-10-03 14:30:25"))
        XCTAssertEqual(ClubOpsTimeRequest.submissionTime(hiddenSeconds), "2026-10-03 14:30:00")
        for raw in ["2026-02-30 10:00:00", "2026-10-03 25:00:00", "2026-10-03", "2026-10-03T14:30:00Z"] {
            XCTAssertThrowsError(try ClubOpsTimeRequest(activityID: 8, startDate: raw))
        }
        XCTAssertThrowsError(try ClubOpsTimeRequest(activityID: 0, startDate: "2026-10-03 14:30:00"))
    }
    func testOpsTimeDormantAndExactJSONContract() async throws {
        let session = try session(), transport = ProfileTestTransport([.json(#"{"code":200}"#)])
        let request = try ClubOpsTimeRequest(activityID: 8, startDate: "2026-10-03 14:30:00")
        let dormant = ClubOpsTimeHTTPService(configuration: try configuration(), transport: transport, current: { session })
        do { try await dormant.save(request, session: session); XCTFail() } catch { XCTAssertEqual(error as? ClubOpsTimeFailure, .disabled) }
        XCTAssertTrue(transport.requests.isEmpty)
        let service = ClubOpsTimeHTTPService(configuration: try configuration(), transport: transport, enabled: true, current: { session })
        try await service.save(request, session: session)
        XCTAssertEqual(transport.requests[0].url?.path, "/fixture/api/club/lead/edit-ops")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), Set(["activityId", "startDate"]))
        XCTAssertEqual(fields["activityId"] as? Int, 8)
        XCTAssertNil(fields["topicId"]); XCTAssertNil(fields["seriesId"])
    }
    func testOpsUnknownCannotResendAndReadbackDoesNotUnlock() async throws {
        let session = try session(), transport = ProfileTestTransport([.json(#"{"code":500}"#, status: 408), .json(#"{"code":200,"data":{"id":8,"startDate":"2026-10-03 14:30:00"}}"#)])
        let service = ClubOpsTimeHTTPService(configuration: try configuration(), transport: transport, enabled: true, current: { session })
        let owner = ClubOpsTimeCoordinator(activityID: 8, service: service)
        let request = try ClubOpsTimeRequest(activityID: 8, startDate: "2026-10-03 14:30:00")
        await owner.save(request, expected: session)
        XCTAssertEqual(owner.state, .unknown)
        let date = try await service.read(activityID: 8, session: session)
        XCTAssertEqual(date, request.startDate); XCTAssertFalse(owner.canSave)
        await owner.save(request, expected: session)
        XCTAssertEqual(transport.requests.count, 2)
    }
    func testClubAIInputUsesOnlyExactSourceFields() throws {
        let input = try ClubAIDesignInput(idea: " Walk ", style: " Easy ", minutes: 90)
        let request = input.assistance.request
        XCTAssertEqual(request.path, "api/ai/club/design")
        XCTAssertEqual(Set(request.fields.keys), Set(["idea", "clubStyle", "targetDurationMin"]))
        XCTAssertEqual(request.fields["idea"], .string("Walk"))
        XCTAssertThrowsError(try ClubAIDesignInput(idea: " "))
        XCTAssertThrowsError(try ClubAIDesignInput(idea: "Walk", minutes: 0))
    }
    func testClubAIParseErrorInvalidatesAllFieldsAndEmptyIsDistinct() throws {
        let bad: ProjectEditJSON = .object(["parseError": .string(""), "plan": .object(["title": .string("Must not show")]), "promoCopy": .string("Must not show")])
        XCTAssertThrowsError(try ClubAIDesignResult(value: bad)) { XCTAssertEqual($0 as? ClubAIDesignFailure, .parse) }
        XCTAssertThrowsError(try ClubAIDesignResult(value: .object(["plan": .null]))) { XCTAssertEqual($0 as? ClubAIDesignFailure, .empty) }
    }
    func testClubAIAdoptionRemainsLocalAndCoordinatesUnconfirmed() throws {
        let result = try ClubAIDesignResult(value: .object(["traceId": .string("synthetic-trace"), "parseError": .null,
            "plan": .object(["title": .string("Walk"), "storyline": .string("A story"), "nodes": .array([.object(["merchantName": .string("Suggested stop"), "address": .string("Suggested address"), "longitude": .string("120.1"), "latitude": .string("30.1"), "task": .string("Find a detail")])])])]))
        let draft = try result.draft(clubID: 4)
        XCTAssertEqual(draft.clubID, 4); XCTAssertEqual(draft.name, "Walk")
        XCTAssertTrue(draft.categoryIDs.isEmpty); XCTAssertTrue(draft.imgUrl.isEmpty)
        XCTAssertEqual(draft.chapters[0].nodes[0].name, "Suggested stop")
        XCTAssertFalse(draft.chapters[0].nodes[0].hasUsableCoordinates)
        XCTAssertNil(draft.chapters[0].nodes[0].templateID)
    }
    func testClubAIQuotaStopsRepeatedGeneration() async throws {
        let session = aiSession(), generator = ClubAIFakeGenerator(outcome: .rejected("今日AI次数已用完"))
        let flow = ClubAIDesignFlow(generator: generator, current: { session })
        let input = try ClubAIDesignInput(idea: "Walk")
        await flow.generate(input); XCTAssertEqual(flow.failure, .quota); XCTAssertFalse(flow.canGenerate)
        await flow.generate(input); XCTAssertEqual(generator.calls, 1)
    }
    func testClubAICancelOrSessionChangeDropsLateResult() async throws {
        for cancel in [true, false] {
            var session: PublishingSession? = aiSession()
            let generator = ClubAIFakeGenerator(outcome: .acknowledged(.object(["plan": .object(["title": .string("Late")])])), suspended: true)
            let flow = ClubAIDesignFlow(generator: generator, current: { session })
            let input = try ClubAIDesignInput(idea: "Walk")
            let task = Task { await flow.generate(input) }
            await generator.waitForStart()
            if cancel { flow.cancel() } else { session = nil }
            generator.finish(); await task.value
            XCTAssertNil(flow.result); XCTAssertFalse(flow.busy)
            XCTAssertThrowsError(try flow.adopt(clubID: 4))
        }
    }
}
@MainActor private final class ClubAIFakeGenerator: ClubAIDesignGenerating {
    let outcome: PublishingAuxiliaryOutcome
    let suspended: Bool
    var calls = 0
    private var continuation: CheckedContinuation<PublishingAuxiliaryOutcome, Never>?
    private var started: CheckedContinuation<Void, Never>?
    init(outcome: PublishingAuxiliaryOutcome, suspended: Bool = false) { self.outcome = outcome; self.suspended = suspended }
    func generate(_ input: ClubAIDesignInput, session: PublishingSession) async -> PublishingAuxiliaryOutcome {
        calls += 1
        if suspended { return await withCheckedContinuation { continuation = $0; started?.resume(); started = nil } }
        return outcome
    }
    func waitForStart() async { if continuation != nil { return }; await withCheckedContinuation { started = $0 } }
    func finish() { continuation?.resume(returning: outcome); continuation = nil }
}
