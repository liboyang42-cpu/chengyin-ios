import XCTest
import Foundation
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Four original boundary methods recovered unchanged from the preserved public source.
@MainActor final class OfficialPublicEventReadRouteTests: XCTestCase {
    private let base = URL(string: "https://example.test/prod-api")!
    private func request(_ suffix: String = "api/official/events") -> URLRequest {
        var value = URLRequest(url: base.appendingPathComponent(suffix))
        value.httpMethod = "GET"; value.setValue("application/json", forHTTPHeaderField: "Accept")
        return value
    }
    func testOnlyCanonicalPublicListCityAndPositiveDetailAreAccepted() throws {
        XCTAssertTrue(OfficialPublicEventReadRoute.accepts(request(), baseURL: base))
        XCTAssertTrue(OfficialPublicEventReadRoute.accepts(request("api/official/events/71"), baseURL: base))
        var city = request()
        var parts = URLComponents(url: city.url!, resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "city", value: "Example & town/城")]
        city.url = parts.url
        XCTAssertTrue(OfficialPublicEventReadRoute.accepts(city, baseURL: base))
        city.setValue("synthetic-token", forHTTPHeaderField: "Authorization")
        XCTAssertTrue(OfficialPublicEventReadRoute.accepts(city, baseURL: base))
    }
    func testPrivateReadsWritersEncodedAliasesAndForeignOriginsAreRejected() {
        let paths = ["api/official/my-events", "api/official/active-for-roam", "api/official/can-publish",
                     "api/official/my-published", "api/official/v2/party-inbox",
                     "api/official/events/71/signup", "api/official/events/0", "api/official/events/-1",
                     "api/official/events/071", "api/official/events/71/"]
        for path in paths { XCTAssertFalse(OfficialPublicEventReadRoute.accepts(request(path), baseURL: base), path) }
        for url in ["https://evil.test/prod-api/api/official/events",
                    "https://example.test/other/api/official/events",
                    "https://user@example.test/prod-api/api/official/events",
                    "https://example.test/prod-api/api/official/%65vents",
                    "https://example.test/prod-api/api/official/events#fragment",
                    "https://example.test/prod-api/api/official/events?city=A&city=B",
                    "https://example.test/prod-api/api/official/events?memberId=71",
                    "https://example.test/prod-api/api/official/events/71?city=A",
                    "https://example.test/prod-api/api/official/events?"] {
            var bad = request(); bad.url = URL(string: url)
            XCTAssertFalse(OfficialPublicEventReadRoute.accepts(bad, baseURL: base), url)
        }
    }
    func testBodyStreamsHeadersAndMethodsNeverBecomePublicReads() {
        let good = request()
        for method in ["POST", "PUT", "DELETE", "HEAD"] {
            var bad = good; bad.httpMethod = method
            XCTAssertFalse(OfficialPublicEventReadRoute.accepts(bad, baseURL: base))
        }
        var body = good; body.httpBody = Data("{}".utf8)
        XCTAssertFalse(OfficialPublicEventReadRoute.accepts(body, baseURL: base))
        var stream = good; stream.httpBodyStream = InputStream(data: Data())
        XCTAssertFalse(OfficialPublicEventReadRoute.accepts(stream, baseURL: base))
        for (name, value) in [("Content-Type", "application/json"), ("Cookie", "session=synthetic"),
                              ("Proxy-Authorization", "synthetic"), ("Authorization", ""), ("Accept", "text/html")] {
            var bad = good; bad.setValue(value, forHTTPHeaderField: name)
            XCTAssertFalse(OfficialPublicEventReadRoute.accepts(bad, baseURL: base), name)
        }
    }
    func testPublicSourceIsExactAndRevocableWithoutIssuingActorAuthority() throws {
        let source = try OfficialPublicEventReadSource(baseURL: base, namespace: "synthetic.bundle.realm")
        XCTAssertTrue(source.matches(baseURL: base, namespace: "synthetic.bundle.realm"))
        XCTAssertFalse(source.matches(baseURL: URL(string: "https://evil.test/prod-api")!, namespace: source.namespace))
        XCTAssertFalse(source.matches(baseURL: base, namespace: "other.bundle.realm"))
        source.revoke(); XCTAssertFalse(source.matches(baseURL: base, namespace: source.namespace))
        for invalid in ["http://example.test", "https://example.test?x=1", "https://user@example.test"] {
            XCTAssertThrowsError(try OfficialPublicEventReadSource(baseURL: URL(string: invalid)!, namespace: "scope"))
        }
        XCTAssertThrowsError(try OfficialPublicEventReadSource(baseURL: base, namespace: ""))
    }
}

@MainActor private final class OfficialHostIdentityWire: HTTPTransport {
    var afterRead: (() -> Void)?
    var code = 200
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); afterRead?()
        return (Data("{\"code\":\(code),\"data\":[]}".utf8), 200)
    }
}

@MainActor final class OfficialPublicEventReadIdentityTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    func testSelectionStartsEmptyAndNeverCreatesSource() {
        let selection = OfficialPublicEventReadSelection(), initial = selection.revision
        XCTAssertNil(selection.source)
        XCTAssertNil(selection.activeRevision(baseURL: base, namespace: "synthetic"))
        selection.select(nil); XCTAssertEqual(selection.revision, initial)
    }
    func testSameSelectionIsStableButRemovalAndReselectionNeverRestoreOldRevision() throws {
        let selection = OfficialPublicEventReadSelection()
        let source = try OfficialPublicEventReadSource(baseURL: base, namespace: "synthetic")
        selection.select(source); let first = selection.revision
        selection.select(source); XCTAssertEqual(selection.revision, first)
        selection.select(nil); XCTAssertNotEqual(selection.revision, first)
        selection.select(source); XCTAssertNotEqual(selection.revision, first)
        XCTAssertTrue(selection.source === source)
        XCTAssertEqual(selection.activeRevision(baseURL: base, namespace: "synthetic"), selection.revision)
    }
    func testRevocationCannotBeUndoneByReselectingSameSource() throws {
        let selection = OfficialPublicEventReadSelection()
        let source = try OfficialPublicEventReadSource(baseURL: base, namespace: "synthetic")
        selection.select(source); source.revoke(); selection.select(nil); selection.select(source)
        XCTAssertNil(selection.activeRevision(baseURL: base, namespace: "synthetic"))
        XCTAssertNil(selection.activeRevision(baseURL: base, namespace: "foreign"))
    }
    func testOriginalContextInitializersRemainCompatible() throws {
        let guest = OfficialReadContext(guestEpoch: 2)
        let member = try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7")
        XCTAssertFalse(guest.isAuthenticated); XCTAssertTrue(member.isAuthenticated)
        XCTAssertNil(member.role); XCTAssertEqual(member.viewerRevision, 0); XCTAssertNil(member.publicSourceRevision)
        XCTAssertEqual(member, try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7"))
    }
    func testContextDistinguishesRoleBytesViewerABAAndSourceRevision() throws {
        let revision = UUID()
        let original = try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7", role: "player", viewerRevision: 4, publicSourceRevision: revision)
        for changed in [
            try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7", role: "merchant", viewerRevision: 4, publicSourceRevision: revision),
            try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7", role: "player", viewerRevision: 6, publicSourceRevision: revision),
            try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7", role: "player", viewerRevision: 4, publicSourceRevision: UUID())] {
            XCTAssertNotEqual(original, changed)
        }
        XCTAssertNotEqual(try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7", role: "caf\u{00e9}"),
                          try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7", role: "cafe\u{0301}"))
    }
    func testReaderDropsSuccessAndUnauthorizedAfterRoleRevisionOrPublicSourceChanges() async throws {
        for code in [200, 401] {
            for change in ["role", "viewerABA", "source", "guestEpoch"] {
                let wire = OfficialHostIdentityWire(); wire.code = code
                let oldRevision = UUID()
                var current = try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7", role: "player", viewerRevision: 4, publicSourceRevision: oldRevision)
                let reader = OfficialSessionReader(service: OfficialEventService(configuration: try APIConfiguration(baseURL: base), transport: wire),
                    currentContext: { current }, onUnauthorized: { _ in XCTFail("Stale refusal expired the current reader") })
                let scope = reader.scope
                wire.afterRead = {
                    switch change {
                    case "role": current = try! .init(accountID: 7, epoch: 2, token: "synthetic-7", role: "merchant", viewerRevision: 4, publicSourceRevision: oldRevision)
                    case "viewerABA": current = try! .init(accountID: 7, epoch: 2, token: "synthetic-7", role: "player", viewerRevision: 6, publicSourceRevision: oldRevision)
                    case "source": current = try! .init(accountID: 7, epoch: 2, token: "synthetic-7", role: "player", viewerRevision: 4, publicSourceRevision: UUID())
                    default: current = .init(guestEpoch: 3)
                    }
                }
                do { _ = try await reader.events(city: nil); XCTFail(change) }
                catch { XCTAssertTrue(error is CancellationError, change) }
                XCTAssertNotEqual(reader.scope, scope); XCTAssertEqual(wire.requests.count, 1)
            }
        }
    }
    func testGuestSourceChangeRejectsResultAndDoesNotBecomeAuthentication() async throws {
        let wire = OfficialHostIdentityWire()
        var current = OfficialReadContext(guestEpoch: 4, publicSourceRevision: UUID())
        let reader = OfficialSessionReader(service: OfficialEventService(configuration: try APIConfiguration(baseURL: base), transport: wire), currentContext: { current })
        wire.afterRead = { current = .init(guestEpoch: 4, publicSourceRevision: UUID()) }
        do { _ = try await reader.events(city: nil); XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(reader.isAuthenticated)
        XCTAssertNil(wire.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }
    func testCurrentAuthenticated401StillExpiresMatchingContextOnce() async throws {
        let wire = OfficialHostIdentityWire(); wire.code = 401
        let current = try OfficialReadContext(accountID: 7, epoch: 2, token: "synthetic-7", role: "player", viewerRevision: 4, publicSourceRevision: UUID())
        var refusals: [OfficialReadContext] = []
        let reader = OfficialSessionReader(service: OfficialEventService(configuration: try APIConfiguration(baseURL: base), transport: wire),
            currentContext: { current }, onUnauthorized: { refusals.append($0) })
        do { _ = try await reader.events(city: nil); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(refusals, [current])
    }
}
