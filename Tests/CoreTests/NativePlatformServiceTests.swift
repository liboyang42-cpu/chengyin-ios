import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class NativePlatformServiceTests: XCTestCase {
    func testDefaultOffAndSeparateCapabilityGatesDoNotDispatch() async throws {
        let owner = try nativeOwner(), transport = NativePlatformHTTPRecorder()
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!)
        let disabled = NativePlatformService(configuration: configuration, transport: transport, owner: owner, current: { owner })
        do { _ = try await disabled.timeWindow(activityID: 0, topicID: 71, nodeID: 701); XCTFail() } catch {}
        let onlyReminders = NativePlatformService(configuration: configuration, transport: transport, owner: owner, remindersEnabled: true, current: { owner })
        do { _ = try await onlyReminders.action(issue()); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testReminderExactReadRouteScopeAndReadback() async throws {
        let owner = try nativeOwner(), transport = NativePlatformHTTPRecorder()
        transport.response = nativeWindow()
        let service = NativePlatformService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, owner: owner, remindersEnabled: true, current: { owner })
        let window = try await service.timeWindow(activityID: 0, topicID: 71, nodeID: 701)
        XCTAssertEqual(window.timeZone, "UTC")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/synthetic/api/play/advanced/time-window")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value!) }), ["activityId":"0", "topicId":"71", "nodeId":"701"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        do { _ = try await service.timeWindow(activityID: 0, topicID: 72, nodeID: 701); XCTFail() } catch { XCTAssertEqual(error as? NativePlatformIssue, .invalidContract) }
    }
    func testNativeActionUsesExactEnvelopeAndNoWeRunFields() async throws {
        let owner = try nativeOwner(), transport = NativePlatformHTTPRecorder()
        transport.response = .object(["sessionId": .int(11), "activityId": .int(0), "topicId": .int(71), "nodeId": .int(701), "version": .int(2), "status": .string("RUNNING")])
        let service = NativePlatformService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, owner: owner, stepsEnabled: true, current: { owner })
        _ = try await service.action(issue())
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/synthetic/api/play/advanced/action")
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: request.httpBody!)
        XCTAssertEqual(raw["action"].text, "ISSUE_NATIVE_STEP_CHALLENGE")
        XCTAssertEqual(Set(raw.object!.keys), ["sessionId", "version", "idempotencyKey", "action", "payload"])
        XCTAssertEqual(Set(raw["payload"].object!.keys), ["provider", "deviceKeyId"])
        XCTAssertEqual(raw["version"].integer, 1)
    }
    func testUnknownPayloadKeyAndStaleSessionRejectBeforeDispatch() async throws {
        let owner = try nativeOwner(), transport = NativePlatformHTTPRecorder(); var current: PlayExperienceSession? = owner
        let service = NativePlatformService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, owner: owner, stepsEnabled: true, current: { current })
        let bad = try NativePlatformPending(sessionID: 11, version: 1, key: "synthetic-1", action: .issue, payload: ["provider": .string(NativeStepChallenge.provider), "deviceKeyId": .string("fixture-key"), "encryptedData": .string("forbidden")])
        do { _ = try await service.action(bad); XCTFail() } catch { XCTAssertEqual(error as? NativePlatformIssue, .invalidContract) }
        current = nil
        do { _ = try await service.action(issue()); XCTFail() } catch { XCTAssertEqual(error as? NativePlatformIssue, .staleSession) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testOpeningChapterPrerequisiteIsActionableAndReadOnly() async throws {
        let owner = try nativeOwner(), transport = NativePlatformHTTPRecorder()
        transport.code = 409; transport.response = .object(["reasonCode": .string("TIME_WINDOW_OPENING_REQUIRED")])
        let service = NativePlatformService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, owner: owner, remindersEnabled: true, current: { owner })
        do { _ = try await service.timeWindow(activityID: 0, topicID: 71, nodeID: 701); XCTFail() }
        catch { XCTAssertEqual(error as? NativePlatformIssue, .openingRequired) }
        XCTAssertEqual(transport.requests.count, 1); XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
    }
    func testLogoutDuringReadRejectsResponse() async throws {
        let owner = try nativeOwner(), transport = NativePlatformHTTPRecorder(); var current: PlayExperienceSession? = owner
        transport.response = nativeWindow(); transport.onSend = { current = nil }
        let service = NativePlatformService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, owner: owner, remindersEnabled: true, current: { current })
        do { _ = try await service.timeWindow(activityID: 0, topicID: 71, nodeID: 701); XCTFail() } catch { XCTAssertEqual(error as? NativePlatformIssue, .staleSession) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testSubmitRejectsBackendAssertionAndStepCountOverflowBeforeSending() async throws {
        let owner = try nativeOwner(), transport = NativePlatformHTTPRecorder()
        let service = NativePlatformService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, owner: owner, stepsEnabled: true, current: { owner })
        for (steps, assertion) in [(100_001, Data([1]).base64EncodedString()), (-1, Data([1]).base64EncodedString()), (1, Data(repeating: 1, count: 4_097).base64EncodedString())] {
            do { _ = try await service.action(submit(steps: steps, assertion: assertion)); XCTFail() }
            catch { XCTAssertEqual(error as? NativePlatformIssue, .invalidContract) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testSubmitAcceptsEnrolledVerifierExactUpperBounds() async throws {
        let owner = try nativeOwner(), transport = NativePlatformHTTPRecorder()
        transport.response = .object(["sessionId": .int(11), "activityId": .int(0), "topicId": .int(71), "nodeId": .int(701), "version": .int(2), "status": .string("RUNNING")])
        let service = NativePlatformService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/synthetic")!), transport: transport, owner: owner, stepsEnabled: true, current: { owner })
        let assertion = Data(repeating: 1, count: 4_096).base64EncodedString()
        XCTAssertEqual(Data(base64Encoded: assertion)?.count, 4_096)
        _ = try await service.action(submit(steps: 100_000, assertion: assertion))
        XCTAssertEqual(transport.requests.count, 1)
    }
    private func submit(steps: Int, assertion: String) throws -> NativePlatformPending {
        try .init(sessionID: 11, version: 1, key: "synthetic-submit", action: .submit, payload: [
            "provider": .string(NativeStepChallenge.provider), "deviceKeyId": .string("fixture-key"),
            "challengeId": .string("synthetic-challenge"), "dayKey": .string("2026-10-02"),
            "sampleStartAt": .int(1_790_899_200_000), "sampleEndAt": .int(1_790_899_260_000),
            "cumulativeSteps": .int(steps), "assertion": .string(assertion)])
    }
    private func issue() throws -> NativePlatformPending {
        try .init(sessionID: 11, version: 1, key: "synthetic-1", action: .issue, payload: ["provider": .string(NativeStepChallenge.provider), "deviceKeyId": .string("fixture-key")])
    }
}
@MainActor private final class NativePlatformHTTPRecorder: HTTPTransport {
    var code = 200
    var requests: [URLRequest] = []; var response: PlayWireValue = .null; var onSend: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); onSend?()
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(code), "data": response])), 200)
    }
}
