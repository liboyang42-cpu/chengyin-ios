import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class ProfileEditServiceTests: XCTestCase {
    private let profile = #"{"code":200,"data":{"id":901,"nickname":"A","introduction":"B","avatar":"avatar","wechat":"qr","casePics":"a;b","tagIds":"2,5"}}"#
    private func service(_ transport: ProfileTestTransport) throws -> ProfileEditService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    func testExactSelfReadAndUpdateContracts() async throws {
        let transport = ProfileTestTransport([.json(profile), .json(#"{"code":200}"#)])
        let service = try service(transport)
        let snapshot = try await service.read(token: "fixture-token")
        try await service.save(ProfileEditPayload(draft: .init(name: "Edited", introduction: "Bio"), preserving: snapshot), token: "fixture-token")
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/fixture/api/user/info", "/fixture/api/user/update"])
        XCTAssertTrue(transport.requests[0].value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        XCTAssertFalse(String(data: transport.requests[0].httpBody!, encoding: .utf8)!.contains("member_id"))
        for request in transport.requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: transport.requests[1].httpBody!) as? [String: String])
        XCTAssertEqual(body, ["name": "Edited", "introduction": "Bio", "avatar": "avatar", "wechat": "qr", "casePics": "a;b", "tagIds": "2,5"])
    }
    func testMalformedAcknowledgmentIsUnknownAndNeverRetried() async throws {
        let transport = ProfileTestTransport([.json(profile), .json(#"{"unexpected":true}"#)])
        let service = try service(transport)
        let snapshot = try await service.read(token: "fixture-token")
        do {
            try await service.save(ProfileEditPayload(draft: .init(name: "Edited"), preserving: snapshot), token: "fixture-token")
            XCTFail("Malformed acknowledgment must not claim success")
        } catch ProfileEditWriteError.outcomeUnknown {} catch { XCTFail("Wrong error: \(error)") }
        XCTAssertEqual(transport.requests.count, 2)
    }
    func testPreservationConflictAfterConfirmationDoesNotSend() async throws {
        let changed = profile.replacingOccurrences(of: "\"avatar\":\"avatar\"", with: "\"avatar\":\"updated-avatar\"")
        let transport = ProfileTestTransport([.json(profile), .json(profile), .json(changed)])
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "fixture-token")
        let coordinator = ProfileEditCoordinator(service: try service(transport), currentSession: { session })
        await coordinator.load(); await coordinator.prepare(.init(name: "Edited"))
        await coordinator.save(try XCTUnwrap(coordinator.confirmation))
        XCTAssertEqual(coordinator.messageKey, "profile.edit.changed")
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertTrue(transport.requests.allSatisfy { $0.url?.lastPathComponent == "info" })
    }
    func testStaleReadAndUnauthorizedNeverPublishOrExpireReplacement() async throws {
        for unauthorized in [false, true] {
            var current: ProfileEditSession? = try .init(accountID: 901, epoch: 1, token: "old")
            let replacement = try ProfileEditSession(accountID: 902, epoch: 2, token: "new")
            var expired = 0
            let response = profile
            let transport = ProfileEditClosureTransport { _ in
                current = replacement
                return (Data((unauthorized ? #"{"code":401,"msg":"Expired"}"# : response).utf8), unauthorized ? 401 : 200)
            }
            let service = ProfileEditService(configuration: try .init(baseURL: URL(string: "https://example.com/")!), transport: transport)
            let coordinator = ProfileEditCoordinator(service: service, currentSession: { current }, onUnauthorized: { _ in expired += 1 })
            await coordinator.load()
            XCTAssertNil(coordinator.snapshot); XCTAssertEqual(expired, 0)
            XCTAssertEqual(current, replacement)
        }
    }
    func testWrongOwnerResponseCannotBeEdited() async throws {
        let transport = ProfileTestTransport([.json(profile)])
        let current = try ProfileEditSession(accountID: 902, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: try service(transport), currentSession: { current })
        await coordinator.load()
        XCTAssertNil(coordinator.snapshot)
        XCTAssertEqual(coordinator.messageKey, "profile.edit.loadFailed")
    }

    func testUnknownWriteWithMatchingReadbackStaysLockedAcrossReloadAndReauthentication() async throws {
        let matching = profile.replacingOccurrences(of: "\"nickname\":\"A\"", with: "\"nickname\":\"Edited\"")
        let transport = ProfileTestTransport([
            .json(profile), .json(profile), .json(profile),
            .failure(APIError.httpStatus(504)), .json(matching), .json(matching), .json(matching)
        ])
        var current: ProfileEditSession? = try .init(accountID: 901, epoch: 1, token: "fixture")
        var savedCallbacks = 0
        let coordinator = ProfileEditCoordinator(service: try service(transport), currentSession: { current }, onSaved: { savedCallbacks += 1 })
        await coordinator.load(); await coordinator.prepare(.init(name: "Edited", introduction: "B"))
        await coordinator.save(try XCTUnwrap(coordinator.confirmation))
        XCTAssertTrue(coordinator.isLocked)
        XCTAssertEqual(coordinator.snapshot?.nickname, "Edited")
        XCTAssertEqual(coordinator.messageKey, "profile.edit.readbackUnconfirmed")
        coordinator.leaveScreen(); await coordinator.load()
        XCTAssertTrue(coordinator.isLocked)
        XCTAssertEqual(coordinator.messageKey, "profile.edit.readbackUnconfirmed")
        current = nil; coordinator.synchronizeSession()
        current = try .init(accountID: 901, epoch: 2, token: "replacement")
        coordinator.synchronizeSession(); await coordinator.load()
        XCTAssertTrue(coordinator.isLocked)
        XCTAssertEqual(coordinator.messageKey, "profile.edit.readbackUnconfirmed")
        await coordinator.prepare(.init(name: "Another", introduction: "B"))
        XCTAssertNil(coordinator.confirmation)
        XCTAssertEqual(savedCallbacks, 0)
        XCTAssertEqual(transport.requests.filter { $0.url?.lastPathComponent == "update" }.count, 1)
    }
    func testAcknowledgedWriteWithFailedReadbackUnlocksOnlyOnLaterMatchingRead() async throws {
        let matching = profile.replacingOccurrences(of: "\"nickname\":\"A\"", with: "\"nickname\":\"Edited\"")
        let transport = ProfileTestTransport([
            .json(profile), .json(profile), .json(profile), .json(#"{"code":200}"#),
            .failure(APIError.httpStatus(503)), .json(matching)
        ])
        let current = try ProfileEditSession(accountID: 901, epoch: 1, token: "fixture")
        var savedCallbacks = 0
        let coordinator = ProfileEditCoordinator(service: try service(transport), currentSession: { current }, onSaved: { savedCallbacks += 1 })
        await coordinator.load(); await coordinator.prepare(.init(name: "Edited", introduction: "B"))
        await coordinator.save(try XCTUnwrap(coordinator.confirmation))
        XCTAssertTrue(coordinator.isLocked)
        XCTAssertNotEqual(coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(savedCallbacks, 0)
        await coordinator.load()
        XCTAssertFalse(coordinator.isLocked)
        XCTAssertEqual(coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(savedCallbacks, 1)
        XCTAssertEqual(transport.requests.filter { $0.url?.lastPathComponent == "update" }.count, 1)
    }

}

private final class ProfileEditClosureTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
