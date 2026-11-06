import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor WeeklyPointsWire: HTTPTransport {
    var json: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ json: String, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(json.utf8), status)
    }
}
private actor WeeklyPointsSuspendedWire: HTTPTransport {
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitUntilReading() async { while pending == nil { await Task.yield() } }
    func finish(_ json: String, status: Int = 200) { pending?.resume(returning: (Data(json.utf8), status)); pending = nil }
}
final class ProfileWeeklyPointsTests: XCTestCase {
    private let payload = #"{"weekPoints":0,"rankPercentage":"TOP 50%","totalUsers":10,"userRank":5}"#
    private var response: String { "{\"code\":200,\"data\":\(payload)}" }
    private let base = URL(string: "https://weekly.example/native")!
    private func service(_ wire: any HTTPTransport) throws -> ProfileWeeklyPointsService {
        .init(configuration: try APIConfiguration(baseURL: base), transport: wire)
    }
    func testFourFieldsAndZeroAreRealDataWithoutRankMovement() throws {
        let value = try JSONDecoder().decode(ProfileWeeklyPoints.self, from: Data(payload.utf8))
        XCTAssertEqual(value.weekPoints, 0); XCTAssertEqual(value.rankPercentage, "TOP 50%")
        XCTAssertEqual(value.totalUsers, 10); XCTAssertEqual(value.userRank, 5)
        let extra = String(payload.dropLast()) + #", "rankDelta":99}"#
        XCTAssertEqual(try JSONDecoder().decode(ProfileWeeklyPoints.self, from: Data(extra.utf8)), value)
    }
    func testMissingNullWrongTypeAndInvalidBoundsFailInsteadOfEmptySuccess() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        for key in original.keys {
            for replacement in [NSNull(), [Any](), true] as [Any] {
                var fields = original; fields[key] = replacement
                XCTAssertThrowsError(try JSONDecoder().decode(ProfileWeeklyPoints.self,
                    from: JSONSerialization.data(withJSONObject: fields)), key)
            }
            var fields = original; fields.removeValue(forKey: key)
            XCTAssertThrowsError(try JSONDecoder().decode(ProfileWeeklyPoints.self, from: JSONSerialization.data(withJSONObject: fields)), key)
        }
        for json in [#"{"weekPoints":"0","rankPercentage":"50%","totalUsers":10,"userRank":5}"#,
                     #"{"weekPoints":1.5,"rankPercentage":"50%","totalUsers":10,"userRank":5}"#,
                     #"{"weekPoints":-1,"rankPercentage":"50%","totalUsers":10,"userRank":5}"#,
                     #"{"weekPoints":0,"rankPercentage":" ","totalUsers":10,"userRank":5}"#,
                     #"{"weekPoints":0,"rankPercentage":"50%","totalUsers":2,"userRank":5}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ProfileWeeklyPoints.self, from: Data(json.utf8)))
        }
    }
    func testRequestUsesCurrentTokenAndExactEmptyBodyWithNoMemberParameter() async throws {
        let wire = WeeklyPointsWire(response); let result = try await service(wire).read(token: "synthetic-weekly")
        XCTAssertEqual(result.weekPoints, 0)
        let requests = await wire.requests; let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, base.appendingPathComponent(ProfileWeeklyPointsReadRoute.path))
        XCTAssertNil(request.url?.query); XCTAssertNil(request.httpBody); XCTAssertNil(request.httpBodyStream)
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-weekly")
        XCTAssertTrue(ProfileWeeklyPointsReadRoute.accepts(request, baseURL: base))
    }
    func testInvalidCredentialDoesNotDispatch() async throws {
        let wire = WeeklyPointsWire(response)
        do { _ = try await service(wire).read(token: ""); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        let count = await wire.requests.count; XCTAssertEqual(count, 0)
    }
    func testMissingOrMalformedSuccessDoesNotBecomeZero() async throws {
        for json in ["{}", #"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":[]}"#, #"{"code":"200","data":{}}"#] {
            do { _ = try await service(WeeklyPointsWire(json)).read(token: "synthetic-weekly"); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testHTTPAndBusiness401AreUnauthorized() async throws {
        for wire in [WeeklyPointsWire("{}", status: 401), WeeklyPointsWire(#"{"code":401}"#)] {
            do { _ = try await service(wire).read(token: "synthetic-weekly"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
    }
    func testExactRouteRejectsQueryBodyMethodOriginAndAlternatePath() throws {
        let valid = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(ProfileWeeklyPointsReadRoute.path), fields: [:], token: "synthetic-weekly", includesBody: false)
        var candidates: [URLRequest] = []
        for suffix in ["?member_id=7", "?pageNum=1", "#fragment", "/other"] {
            var copy = valid; copy.url = URL(string: valid.url!.absoluteString + suffix); candidates.append(copy)
        }
        var copy = valid; copy.httpBody = Data("{}".utf8); candidates.append(copy)
        copy = valid; copy.httpBody = Data(); candidates.append(copy)
        copy = valid; copy.httpMethod = "GET"; candidates.append(copy)
        copy = valid; copy.url = URL(string: "https://other.example/native/" + ProfileWeeklyPointsReadRoute.path); candidates.append(copy)
        copy = valid; copy.setValue("application/json", forHTTPHeaderField: "Content-Type"); candidates.append(copy)
        for candidate in candidates { XCTAssertFalse(ProfileWeeklyPointsReadRoute.accepts(candidate, baseURL: base)) }
    }
    @MainActor func testNilApprovalIsUnavailableAndSendsNothing() async throws {
        let wire = WeeklyPointsWire(response)
        let session = try ProfileWeeklyPointsSession(accountID: 7, epoch: 1, viewerRevision: 1, role: "player", token: "synthetic-weekly", approvalRevision: nil)
        let reader = ProfileWeeklyPointsSessionReader(service: try service(wire), currentSession: { session })
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.weeklyPoints(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let count = await wire.requests.count; XCTAssertEqual(count, 0)
    }
    @MainActor func testAccountEpochTokenViewerRoleAndApprovalChangesDiscardLateResponsesAnd401() async throws {
        for change in ["account", "epoch", "token", "viewer", "role", "approval", "logout"] {
            for status in [200, 401] {
                let wire = WeeklyPointsSuspendedWire(), approval = UUID()
                var current: ProfileWeeklyPointsSession? = try .init(accountID: 7, epoch: 1, viewerRevision: 1, role: "player", token: "synthetic-weekly", approvalRevision: approval)
                var expired = 0
                let reader = ProfileWeeklyPointsSessionReader(service: try service(wire), currentSession: { current }, onUnauthorized: { _ in expired += 1 })
                let task = Task { try await reader.weeklyPoints() }; await wire.waitUntilReading()
                if change == "logout" { current = nil }
                else {
                    current = try .init(accountID: change == "account" ? 8 : 7,
                        epoch: change == "epoch" ? 2 : 1, viewerRevision: change == "viewer" ? 2 : 1,
                        role: change == "role" ? "merchant" : "player", token: change == "token" ? "rotated" : "synthetic-weekly",
                        approvalRevision: change == "approval" ? UUID() : approval)
                }
                await wire.finish(response, status: status)
                do { _ = try await task.value; XCTFail(change) } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(expired, 0)
            }
        }
    }
    @MainActor func testCurrent401InvokesExpiryOnceAndCancellationInvokesNone() async throws {
        let session = try ProfileWeeklyPointsSession(accountID: 7, epoch: 1, viewerRevision: 1, role: "player", token: "synthetic-weekly", approvalRevision: UUID())
        var expired = 0
        let reader = ProfileWeeklyPointsSessionReader(service: try service(WeeklyPointsWire("{}", status: 401)), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        do { _ = try await reader.weeklyPoints(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, 1)
        let wire = WeeklyPointsSuspendedWire()
        let cancelled = ProfileWeeklyPointsSessionReader(service: try service(wire), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        let task = Task { try await cancelled.weeklyPoints() }; await wire.waitUntilReading(); task.cancel(); await wire.finish(response)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 1)
    }
}
