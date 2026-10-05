import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SignedInContentDetailTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func request(_ route: SignedInContentDetailReadRoute, id: String = "21", extra: [String: String] = [:]) throws -> URLRequest {
        var fields = extra; fields["id"] = id
        return try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(route.path), fields: fields,
            token: "synthetic", boundary: "DetailBoundary")
    }
    func testOnlyTwoExactCanonicalMultipartIDRoutes() throws {
        for route in SignedInContentDetailReadRoute.allCases {
            let request = try request(route)
            XCTAssertEqual(SignedInContentDetailReadRoute(url: request.url!, baseURL: base), route)
            XCTAssertTrue(route.accepts(request))
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.url?.query)
            for id in ["0", "-1", "+1", "01", "1.0", " 1", "1 ", "1\n", "１", "999999999999999999999999"] {
                XCTAssertFalse(route.accepts(try self.request(route, id: id)), id)
            }
            for extra in [["scope":""], ["memberId":"7"], ["owner":"7"], ["topicId":"21"]] {
                XCTAssertFalse(route.accepts(try self.request(route, extra: extra)))
            }
            var wrong = request; wrong.httpMethod = "GET"; XCTAssertFalse(route.accepts(wrong))
            wrong = request; wrong.httpBody = Data(#"{"id":21}"#.utf8)
            wrong.setValue("application/json", forHTTPHeaderField: "Content-Type"); XCTAssertFalse(route.accepts(wrong))
            wrong = request; wrong.httpBodyStream = InputStream(data: Data()); XCTAssertFalse(route.accepts(wrong))
            wrong = request; wrong.httpBody?.append(Data("extra".utf8)); XCTAssertFalse(route.accepts(wrong))
            wrong = request
            let duplicate = "--DetailBoundary\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n21\r\n"
            wrong.httpBody = Data((duplicate + String(data: request.httpBody!, encoding: .utf8)!).utf8)
            XCTAssertFalse(route.accepts(wrong))
            for suffix in ["?id=21", "?", "#fragment", "/", "/extra"] {
                let url = URL(string: request.url!.absoluteString + suffix)!
                XCTAssertNil(SignedInContentDetailReadRoute(url: url, baseURL: base))
            }
        }
        for path in ["api/activity/list", "api/topic/info", "api/topic/info-to-userx", "api/registration/create", "api/play/nodes", "api/activity/update"] {
            XCTAssertNil(SignedInContentDetailReadRoute(url: base.appendingPathComponent(path), baseURL: base))
        }
        XCTAssertNil(SignedInContentDetailReadRoute(url: URL(string: "https://other.test/native/api/activity/info")!, baseURL: base))
    }
    func testMissingDuplicateAndMalformedMultipartFramingAreRejected() throws {
        for route in SignedInContentDetailReadRoute.allCases {
            let exact = try request(route)
            let body = try XCTUnwrap(String(data: XCTUnwrap(exact.httpBody), encoding: .utf8))
            let duplicate = "--DetailBoundary\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n21\r\n"
            for raw in ["", "--DetailBoundary--\r\n", body + "\r\n", "\r\n" + body,
                        duplicate + body, body.replacingOccurrences(of: "name=\"id\"", with: "name=\"ID\""),
                        body.replacingOccurrences(of: "\r\n", with: "\n"),
                        body.replacingOccurrences(of: "21\r\n", with: "21\r\nContent-Type: text/plain\r\n")] {
                var malformed = exact; malformed.httpBody = Data(raw.utf8)
                XCTAssertFalse(route.accepts(malformed), raw)
            }
            for type in ["multipart/form-data", "multipart/form-data; boundary=", "multipart/form-data; boundary=DetailBoundary; charset=utf-8",
                         "multipart/form-data; boundary=\"DetailBoundary\"", "multipart/form-data; boundary=Other"] {
                var malformed = exact; malformed.setValue(type, forHTTPHeaderField: "Content-Type")
                XCTAssertFalse(route.accepts(malformed), type)
            }
            var absent = exact; absent.httpBody = nil; XCTAssertFalse(route.accepts(absent))
        }
    }
    func testActivityCorrelatesAllowedDetailButPreservesRedactedClubGate() async throws {
        let wire = DetailWire(), service = ActivityService(configuration: try APIConfiguration(baseURL: base), transport: wire)
        wire.json = #"{"code":200,"data":{"id":22,"name":"Wrong activity"}}"#
        do { _ = try await service.detail(id: 21); XCTFail("Mismatched identity") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        wire.json = #"{"code":200,"data":{"gate":true,"clubId":9,"message":"Join first","activityName":"Summary"}}"#
        let gated = try await service.detail(id: 21)
        XCTAssertEqual(gated, .clubRequired(clubID: 9, message: "Join first"))
        wire.json = #"{"code":200,"data":{"id":21,"name":"Exact activity"}}"#
        guard case .allowed(let detail) = try await service.detail(id: 21) else { return XCTFail() }
        XCTAssertEqual(detail.summary.id, 21)
    }
    func testActivityMalformedAndUnauthorizedEnvelopeStayErrors() async throws {
        let wire = DetailWire(), service = ActivityService(configuration: try APIConfiguration(baseURL: base), transport: wire)
        for json in [#"{"code":"200","data":{"id":21,"name":"Wrong"}}"#, #"{"code":200,"data":[]}"#, #"{"code":200,"data":null}"#, #"{"code":500,"data":{"id":21,"name":"Wrong"}}"#] {
            wire.json = json
            do { _ = try await service.detail(id: 21); XCTFail(json) } catch {}
        }
        for status in [200, 401] {
            wire.status = status; wire.json = #"{"code":401}"#
            do { _ = try await service.detail(id: 21); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
    }
    func testTopicShelfPreservesOmittedEmptyAndExactSummaryFields() throws {
        func decode(_ extra: String) throws -> TopicDetail {
            try JSONDecoder().decode(TopicDetail.self, from: Data(("{\"id\":31,\"name\":\"Route\"" + extra + "}").utf8))
        }
        XCTAssertNil(try decode("").activities)
        XCTAssertNil(try decode(",\"activityList\":null").activities)
        XCTAssertEqual(try decode(",\"activityList\":[]").activities, [])
        let value = try decode(#", "activityList":[{"id":21,"name":"Walk","imgUrl":"image","addressName":"Square","startDate":"2026-10-01 10:00:00","endDate":"2026-10-01 11:00:00","memberId":99,"isOwner":1}]"#)
        let row = try XCTUnwrap(value.activities?.first)
        XCTAssertEqual(row.id, 21); XCTAssertEqual(row.name, "Walk"); XCTAssertEqual(row.imageURL, "image")
        XCTAssertEqual(row.addressName, "Square"); XCTAssertEqual(row.startDate, "2026-10-01 10:00:00")
        XCTAssertEqual(row.endDate, "2026-10-01 11:00:00")
        XCTAssertFalse(value.isOwner)
        for shelf in [#"{}"#, #"[{"id":0,"name":"Invalid"}]"#, #"[{"id":"21","name":"Invalid"}]"#, #"[{"id":21,"name":" "}]"#, #"[{"id":21,"name":"A"},{"id":21,"name":"B"}]"#] {
            XCTAssertThrowsError(try decode(",\"activityList\":" + shelf))
        }
    }
    @MainActor func testGuestTopicDetailDoesNotDispatchAndRoleABADropsLate401() async throws {
        let wire = DetailWire()
        var current: TopicReadSession?
        var expired = 0
        let reader = TopicSessionReader(service: TopicService(configuration: try APIConfiguration(baseURL: base), transport: wire),
            currentSession: { current }, onUnauthorized: { _ in expired += 1 })
        do { _ = try await reader.topicDetail(id: 31); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(wire.requests.isEmpty)
        current = try TopicReadSession(accountID: 7, epoch: 1, token: "synthetic", role: "player", viewerRevision: 1)
        wire.pause = true
        let started = expectation(description: "Suspended signed-in detail"); wire.onPaused = { started.fulfill() }
        let task = Task { try await reader.topicDetail(id: 31) }
        await fulfillment(of: [started], timeout: 2)
        current = try TopicReadSession(accountID: 7, epoch: 1, token: "synthetic", role: "merchant", viewerRevision: 2)
        current = try TopicReadSession(accountID: 7, epoch: 1, token: "synthetic", role: "player", viewerRevision: 3)
        wire.finish(#"{"code":401}"#)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }
    @MainActor func testOwnedReplacementAndDismissalCancelLateUnauthorizedBeforeSessionSideEffect() async throws {
        for replace in [false, true] {
            let wire = DetailWire(), owner = SignedInContentDetailLoadOwner()
            let current = try TopicReadSession(accountID: 7, epoch: 1, token: "synthetic", role: "player", viewerRevision: 1)
            var expired = 0, staleWasCanceled = false, replacementID: Int?
            let reader = TopicSessionReader(service: TopicService(configuration: try APIConfiguration(baseURL: base), transport: wire),
                currentSession: { current }, onUnauthorized: { _ in expired += 1 })
            wire.pause = true
            let started = expectation(description: "Owned detail suspended"); wire.onPaused = { started.fulfill() }
            let stale = owner.start {
                do { _ = try await reader.topicDetail(id: 31); XCTFail("Stale response accepted") }
                catch { staleWasCanceled = error is CancellationError }
            }
            await fulfillment(of: [started], timeout: 2)
            if replace {
                wire.pause = false; wire.json = #"{"code":200,"data":{"id":31,"name":"New detail"}}"#
                await owner.run {
                    do { replacementID = try await reader.topicDetail(id: 31).id }
                    catch { XCTFail("\(error)") }
                }
            } else { owner.cancel() }
            wire.finish(#"{"code":401}"#)
            await stale.value
            XCTAssertTrue(staleWasCanceled)
            XCTAssertEqual(expired, 0)
            XCTAssertEqual(replacementID, replace ? 31 : nil)
        }
    }
    @MainActor func testParentCancellationCancelsOnlyItsOwnedRead() async throws {
        let owner = SignedInContentDetailLoadOwner(), firstWire = DetailWire(), secondWire = DetailWire()
        firstWire.pause = true; secondWire.pause = true
        let firstStarted = expectation(description: "Old parent suspended"), secondStarted = expectation(description: "New parent suspended")
        firstWire.onPaused = { firstStarted.fulfill() }; secondWire.onPaused = { secondStarted.fulfill() }
        var oldCanceled = false, newerCanceled = true
        let first = Task {
            await owner.run {
                _ = try? await firstWire.send(URLRequest(url: self.base))
                oldCanceled = Task.isCancelled
            }
        }
        await fulfillment(of: [firstStarted], timeout: 2)
        let second = Task {
            await owner.run {
                _ = try? await secondWire.send(URLRequest(url: self.base))
                newerCanceled = Task.isCancelled
            }
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        // The old parent's cancellation arrives after the new read owns the view.
        first.cancel(); firstWire.finish("{}")
        await first.value
        secondWire.finish("{}")
        await second.value
        XCTAssertTrue(oldCanceled)
        XCTAssertFalse(newerCanceled)
    }

}
private final class DetailWire: HTTPTransport {
    var json = "{}", status = 200, pause = false
    var requests: [URLRequest] = []
    var onPaused: (() -> Void)?
    private var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if pause { return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
        return (Data(json.utf8), status)
    }
    func finish(_ json: String) { let value = pending; pending = nil; value?.resume(returning: (Data(json.utf8), 200)) }
}
