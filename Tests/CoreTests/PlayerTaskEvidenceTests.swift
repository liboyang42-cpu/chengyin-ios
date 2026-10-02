import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayerTaskEvidenceTests: XCTestCase {
    private func session(epoch: UInt64 = 1) throws -> PlayExperienceSession {
        try .init(accountID: 1, epoch: epoch, namespace: "synthetic", token: "synthetic-token")
    }
    private func projection(kind: String = "SCAN", revision: Int = 2) throws -> PlayPlayerGameProjection {
        let text = PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"inputType\":\"TEXT\"", with: "\"inputType\":\"\(kind)\"")
            .replacingOccurrences(of: "\"revision\":2", with: "\"revision\":\(revision)")
        return try .init(PlayExperienceSyntheticFixtures.wire(text))
    }
    func testScanPayloadUsesPlayerSubmitAndExactNodeRevision() throws {
        let value = try projection(), target = try PlayerTaskEvidenceTarget(projection: value, node: value.nodes[0], owner: session())
        let command = try target.command(scan: "  A + / 中文  ")
        XCTAssertEqual(command.action, .submit); XCTAssertEqual(command.activityID, 41); XCTAssertEqual(command.nodeID, 701)
        XCTAssertEqual(command.expectedRevision, 2); XCTAssertEqual(command.payload["taskCode"]?.text, "OBSERVE")
        XCTAssertEqual(command.payload["evidenceUrls"]?.array?.first?.text, try PlayPlayerCommand.textEvidence("A + / 中文", scan: true))
        XCTAssertTrue(value.allows(command))
    }
    func testWrongEvidenceKindAndEmptyCodeAreRejected() throws {
        let value = try projection(), target = try PlayerTaskEvidenceTarget(projection: value, node: value.nodes[0], owner: session())
        XCTAssertThrowsError(try target.command(scan: "  "))
        XCTAssertThrowsError(try target.command(photo: .photo(uploadedURL: "https://example.test/synthetic.jpg")))
        XCTAssertThrowsError(try target.command(scan: String(repeating: "x", count: 257)))
    }
    func testPhotoRequiresUploadedHTTPSAndNeverAcceptsLocalFile() throws {
        let value = try projection(kind: "PHOTO"), target = try PlayerTaskEvidenceTarget(projection: value, node: value.nodes[0], owner: session())
        XCTAssertNoThrow(try target.command(photo: .photo(uploadedURL: "https://example.test/synthetic.jpg")))
        XCTAssertNoThrow(try target.command(photo: .photo(uploadedURL: "https://example.test/issued-resource?signature=synthetic")))
        XCTAssertThrowsError(try target.command(photo: .photo(uploadedURL: "file:///private/photo.jpg")))
        XCTAssertThrowsError(try target.command(photo: .scan("a")))
        XCTAssertThrowsError(try target.command(scan: "a"))
    }
    func testSessionReplacementInvalidatesEvidenceReview() async throws {
        var owner: PlayExperienceSession? = try session()
        let transport = PlayerEvidenceTransport { _ in
            let text = PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"inputType\":\"TEXT\"", with: "\"inputType\":\"SCAN\"")
            return (PlayExperienceSyntheticFixtures.envelope(text), 200)
        }
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: [.reads])
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner })
        await model.load(); let target = try model.evidenceTarget(nodeID: 701)
        XCTAssertNoThrow(try model.reviewEvidence(target, scan: "synthetic"))
        owner = try session(epoch: 2)
        XCTAssertFalse(model.acceptsEvidence(target)); XCTAssertThrowsError(try model.reviewEvidence(target, scan: "synthetic"))
        XCTAssertThrowsError(try model.evidenceTarget(nodeID: 701))
    }
    func testUnavailablePlayerStatesBlockCaptureBeforeHardware() async throws {
        let owner = try session()
        let base = PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"inputType\":\"TEXT\"", with: "\"inputType\":\"SCAN\"")
        let denied = [
            base.replacingOccurrences(of: "\"confirmed\":true", with: "\"confirmed\":false"),
            base.replacingOccurrences(of: "\"status\":\"RUNNING\"", with: "\"status\":\"FINISHED\""),
            base.replacingOccurrences(of: "\"personalState\":\"ACTIVE\"", with: "\"personalState\":\"PAUSED\""),
            base.replacingOccurrences(of: "\"stationStatus\":\"ACTIVE\"", with: "\"stationStatus\":\"PAUSED\""),
            base.replacingOccurrences(of: "\"PLAYER_SUBMIT\",", with: ""),
            base.replacingOccurrences(of: "\"mySubmissions\":[]", with: "\"mySubmissions\":[{\"nodeId\":701,\"status\":\"PENDING\"}]")
        ]
        for json in denied {
            let transport = PlayerEvidenceTransport { _ in (PlayExperienceSyntheticFixtures.envelope(json), 200) }
            let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: [.reads])
            let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner })
            await model.load(); XCTAssertThrowsError(try model.evidenceTarget(nodeID: 701))
        }
    }
    func testRevisionReplacementInvalidatesEvidenceReview() async throws {
        let owner = try session(); var revision = 2
        let transport = PlayerEvidenceTransport { _ in
            let text = PlayExperienceSyntheticFixtures.player.replacingOccurrences(of: "\"inputType\":\"TEXT\"", with: "\"inputType\":\"SCAN\"")
                .replacingOccurrences(of: "\"revision\":2", with: "\"revision\":\(revision)")
            return (PlayExperienceSyntheticFixtures.envelope(text), 200)
        }
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: [.reads])
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner })
        await model.load(); let target = try model.evidenceTarget(nodeID: 701)
        revision = 3; await model.load(); XCTAssertFalse(model.acceptsEvidence(target))
    }
}
private final class PlayerEvidenceTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
