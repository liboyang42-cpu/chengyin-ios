import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ClubTerminalSessionProjectionTests: XCTestCase {
    private func projection(_ status: String = "FINISHED", activity: Int = 41, perspective: String = "CLUB") throws -> PlayDirectorProjection {
        try .init(.object(["activityId": .int(activity), "perspective": .string(perspective), "sessionId": .int(501), "revision": .int(3), "status": .string(status), "club": .object([:])]), activityID: 41)
    }
    func testOnlyAuthoritativeFinishedAndCancelledAreTerminal() throws {
        for status in ["FINISHED", "CANCELLED"] { XCTAssertTrue(ClubTerminalSessionProjection.isTerminal(try projection(status), activityID: 41)) }
        for status in ["RUNNING", "READY", "DRAFT", "ended", "finished", "UNKNOWN"] { XCTAssertFalse(ClubTerminalSessionProjection.isTerminal(try projection(status), activityID: 41)) }
    }
    func testForeignPerspectiveAndActivityRejectedByReusedDecoder() {
        XCTAssertThrowsError(try projection(perspective: "PLAYER"))
        XCTAssertThrowsError(try projection(activity: 42))
    }
    func testWrongSelectedActivityCannotUseTerminalProjection() throws {
        XCTAssertFalse(ClubTerminalSessionProjection.isTerminal(try projection(), activityID: 42))
    }
    func testTopicApprovedStatusIsNotSessionCompletion() {
        XCTAssertTrue(ClubTerminalSessionProjection.auditAllows(.object(["status": .integer(1)])))
        XCTAssertFalse(ClubTerminalSessionProjection.auditAllows(.object(["status": .string("ended")])))
    }
    func testAuditAndRejectionAlwaysOverrideTerminalCandidates() {
        let values: [ClubGovernanceValue] = [.object([:]), .object(["status": .integer(0)]), .object(["status": .integer(2)]), .object(["status": .integer(1), "lifecycle": .integer(7)]), .object(["status": .integer(1), "rejectReason": .string("Rejected")])]
        for value in values {
            XCTAssertFalse(ClubTerminalSessionProjection.auditAllows(value))
        }
    }
    private final class Transport: HTTPTransport {
        var requests: [URLRequest] = []
        var beforeReturn: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReturn?()
            return (Data(#"{"code":200,"data":{"activityId":41,"perspective":"CLUB","sessionId":501,"revision":3,"status":"FINISHED","club":{}}}"#.utf8), 200)
        }
    }
    private func fixture(_ transport: Transport, enabled: Set<PlayExperienceCapability> = [.reads], paths: Set<String> = ["api/game/session/view"]) throws -> (PlayExperienceService, ClubTerminalReadLease) {
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!)
        let session = try PlayExperienceSession(accountID: 701, epoch: 2, namespace: "synthetic-terminal", token: "synthetic-token")
        let lease = ClubTerminalReadLease(context: .init(market: .china, baseURL: api.baseURL, role: "club", session: session), approvalID: UUID(), viewerRevision: 3, paths: paths)
        return (.init(configuration: api, transport: transport, enabled: enabled), lease)
    }
    func testProviderUsesExactGetClubPerspectiveAndNoCommands() async throws {
        let recorder = Transport(), (service, lease) = try fixture(recorder)
        let provider = try XCTUnwrap(ClubTerminalProjectionProvider(service: service, lease: lease, current: { lease }))
        let value = try await provider.read(activityID: 41)
        XCTAssertEqual(value.status, "FINISHED"); XCTAssertEqual(recorder.requests.count, 1)
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/fixture/api/game/session/view")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(Set(query.map(\.name)), ["activityId", "perspective"])
        XCTAssertEqual(query.first(where: { $0.name == "perspective" })?.value, "CLUB")
        XCTAssertFalse(service.enabled.contains(.directorCommands))
    }
    func testMissingReadCapabilityOrExactEndpointCannotCreateProvider() throws {
        let recorder = Transport(), (disabled, lease) = try fixture(recorder, enabled: [])
        XCTAssertNil(ClubTerminalProjectionProvider(service: disabled, lease: lease, current: { lease }))
        let (service, wrong) = try fixture(recorder, paths: ["api/play/nodes"])
        XCTAssertNil(ClubTerminalProjectionProvider(service: service, lease: wrong, current: { wrong }))
        XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testMissingLeaseAndExplicitRetirementNeverDispatch() async throws {
        let recorder = Transport(), (service, lease) = try fixture(recorder)
        XCTAssertNil(ClubTerminalProjectionProvider(service: service, lease: lease, current: { nil }))
        let provider = try XCTUnwrap(ClubTerminalProjectionProvider(service: service, lease: lease, current: { lease }))
        provider.invalidate()
        do { _ = try await provider.read(activityID: 41); XCTFail() } catch {}
        XCTAssertTrue(recorder.requests.isEmpty)
    }
    func testRevocationDuringReadDropsResponseAndObservedABACannotRevive() async throws {
        let recorder = Transport(), (service, lease) = try fixture(recorder)
        var current: ClubTerminalReadLease? = lease
        let provider = try XCTUnwrap(ClubTerminalProjectionProvider(service: service, lease: lease, current: { current }))
        recorder.beforeReturn = { current = nil }
        do { _ = try await provider.read(activityID: 41); XCTFail() } catch {}
        current = lease; XCTAssertFalse(provider.isCurrent)
    }
    func testApprovalIssuanceAndViewerRevisionParticipateInLease() throws {
        let (_, lease) = try fixture(Transport())
        XCTAssertNotEqual(lease, .init(context: lease.context, approvalID: UUID(), viewerRevision: lease.viewerRevision, paths: lease.paths))
        XCTAssertNotEqual(lease, .init(context: lease.context, approvalID: lease.approvalID, viewerRevision: lease.viewerRevision + 1, paths: lease.paths))
    }
}
