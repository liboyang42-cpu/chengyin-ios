import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class RoamSessionTests: XCTestCase {
    private let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, label: "Synthetic area")
    private func session(_ id: Int = 1, _ epoch: UInt64 = 1, _ token: String = "fixture-token") throws -> RoamReadSession {
        try RoamReadSession(accountID: id, epoch: epoch, token: token)
    }
    private func service(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) throws -> RoamService {
        RoamService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: RoamClosureTransport(operation))
    }
    func testMissingAreaSendsNothingAndDoesNotReadCredential() async throws {
        var requests = 0; var credentialReads = 0
        let api = try service { _ in requests += 1; return (Data(), 500) }
        let reader = RoamSessionReader(service: api, currentSession: { credentialReads += 1; return nil }, searchArea: { nil })
        do { _ = try await reader.roamPlaces(radiusM: 3000); XCTFail() }
        catch { XCTAssertEqual(error as? RoamReadFailure, .searchAreaRequired) }
        XCTAssertEqual(requests, 0); XCTAssertEqual(credentialReads, 0)
    }
    func testUnconfiguredDoesNotReadCredential() async throws {
        var reads = 0
        let area = self.area
        let reader = RoamSessionReader(service: nil, currentSession: { reads += 1; return nil }, searchArea: { area })
        do { _ = try await reader.roamPlaces(radiusM: 3000); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(reads, 0)
    }
    func testGuestCannotRequestPersonalizedNodesOrPlayers() async throws {
        var requests = 0
        let api = try service { _ in requests += 1; return (Data(), 500) }
        let area = self.area
        let reader = RoamSessionReader(service: api, currentSession: { nil }, searchArea: { area })
        do { _ = try await reader.roamNodeDetail(id: 1); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        do { _ = try await reader.roamPlayers(radiusM: 3000); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(requests, 0)
    }
    func testSameAccountReplacementEpochDiscardsOldSuccess() async throws {
        var current: RoamReadSession? = try session()
        let replacement = try session(1, 2)
        let api = try service { _ in current = replacement; return (Data(#"{"code":200,"data":[{"id":1}]}"#.utf8), 200) }
        let area = self.area
        let reader = RoamSessionReader(service: api, currentSession: { current }, searchArea: { area })
        do { _ = try await reader.roamPlaces(radiusM: 3000); XCTFail("Stale result escaped its session") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reader.identity, replacement.identity)
    }
    func testTokenReplacementDiscardsStaleSuccessEvenWithSameIdentity() async throws {
        var current: RoamReadSession? = try session()
        let replacement = try session(1, 1, "replacement-fixture-token")
        let api = try service { _ in current = replacement; return (Data(#"{"code":200,"data":{"poiId":1}}"#.utf8), 200) }
        let reader = RoamSessionReader(service: api, currentSession: { current }, searchArea: { nil })
        do { _ = try await reader.roamNodeDetail(id: 1); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testOldAccount401CannotExpireReplacementAccount() async throws {
        var current: RoamReadSession? = try session()
        let replacement = try session(2, 2, "replacement-fixture-token")
        var expired = 0
        let api = try service { _ in current = replacement; return (Data("not JSON".utf8), 401) }
        let area = self.area
        let reader = RoamSessionReader(service: api, currentSession: { current }, searchArea: { area }, onUnauthorized: { _ in expired += 1 })
        do { _ = try await reader.roamPlayers(radiusM: 3000); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0); XCTAssertEqual(current, replacement)
    }
    func testMatchingUnauthorizedExpiresOnlyCapturedSession() async throws {
        var current: RoamReadSession? = try session()
        let original = try XCTUnwrap(current)
        var expired: [RoamReadSession] = []
        let api = try service { _ in (Data(#"{"code":401,"data":{}}"#.utf8), 200) }
        let area = self.area
        let reader = RoamSessionReader(service: api, currentSession: { current }, searchArea: { area }, onUnauthorized: {
            expired.append($0)
            if current == $0 { current = nil }
        })
        do { _ = try await reader.roamEvents(radiusM: 3000); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [original]); XCTAssertNil(current)
    }
    func testAreaChangeDiscardsOldCoordinatesAndResults() async throws {
        let current = try session()
        var area: RoamSearchArea? = self.area
        let replacement = RoamSearchArea(coordinate: RoamCoordinate(latitude: 2, longitude: 2)!, label: "Other synthetic area")
        let api = try service { _ in area = replacement; return (Data(#"{"code":200,"data":[{"id":1}]}"#.utf8), 200) }
        let reader = RoamSessionReader(service: api, currentSession: { current }, searchArea: { area })
        do { _ = try await reader.roamPlaces(radiusM: 3000); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reader.searchArea, replacement)
    }
    func testLogoutDropsPendingPlayerSnapshot() async throws {
        var current: RoamReadSession? = try session()
        let api = try service { _ in current = nil; return (Data(#"{"code":200,"data":[{"memberId":2,"lat":1,"lng":1}]}"#.utf8), 200) }
        let area = self.area
        let reader = RoamSessionReader(service: api, currentSession: { current }, searchArea: { area })
        do { _ = try await reader.roamPlayers(radiusM: 3000); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testOrdinaryFailureDoesNotExpireSession() async throws {
        let current = try session()
        var expired = 0
        let api = try service { _ in (Data(#"{"code":503,"data":null}"#.utf8), 200) }
        let area = self.area
        let reader = RoamSessionReader(service: api, currentSession: { current }, searchArea: { area }, onUnauthorized: { _ in expired += 1 })
        do { _ = try await reader.roamPlaces(radiusM: 3000); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .businessCode(503)) }
        XCTAssertEqual(expired, 0)
    }
    func testInvalidSessionCannotEnterReader() {
        XCTAssertThrowsError(try RoamReadSession(accountID: 0, epoch: 1, token: "fixture"))
        XCTAssertThrowsError(try RoamReadSession(accountID: 1, epoch: 1, token: ""))
        XCTAssertThrowsError(try RoamReadSession(accountID: 1, epoch: 1, token: "fixture\nheader"))
    }
}
private final class RoamClosureTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
