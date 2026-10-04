import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class JourneyRoutingHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(#"{"code":200,"data":null}"#.utf8), 200)
    }
}

@MainActor final class JourneyCapabilityRoutingTests: XCTestCase {
    private let routes: [(String, PlayExperienceCapability)] = [
        ("check/roll", .journeyChecks), ("check/reroll", .journeyChecks),
        ("check/settle", .journeyChecks), ("egg/collect", .journeyEggCollection),
        ("journey/ask", .journeyAsks)
    ]
    private func service(_ http: JourneyRoutingHTTP, enabled: Set<PlayExperienceCapability>) throws -> PlayExperienceService {
        .init(configuration: try .init(baseURL: URL(string: "https://fixture.example/root/")!),
              transport: http, enabled: enabled)
    }
    func testEachJourneyCapabilityDispatchesOnlyItsExactPOSTRoutes() async throws {
        for (path, capability) in routes {
            let http = JourneyRoutingHTTP(), api = try service(http, enabled: [capability])
            _ = try await api.request("api/play/" + path, form: ["synthetic": "1"], capability: capability, token: "fixture-token")
            XCTAssertEqual(http.requests.count, 1)
            XCTAssertEqual(http.requests.first?.url?.path, "/root/api/play/" + path)
            XCTAssertEqual(http.requests.first?.httpMethod, "POST")
        }
    }
    func testJourneyRoutesRejectWrongCapabilitiesAndGETWithoutDispatch() async throws {
        let capabilities: [PlayExperienceCapability] = [.reads, .advanced, .classicCompletion, .runPersistence,
                                                       .journeyChecks, .journeyEggCollection, .journeyAsks]
        let http = JourneyRoutingHTTP(), api = try service(http, enabled: Set(capabilities))
        for (path, expected) in routes {
            for capability in capabilities where capability != expected {
                do {
                    _ = try await api.request("api/play/" + path, form: ["synthetic": "1"], capability: capability, token: "fixture-token")
                    XCTFail("Wrong capability dispatched " + path)
                } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
            }
            do {
                _ = try await api.request("api/play/" + path, capability: expected, token: "fixture-token")
                XCTFail("GET dispatched " + path)
            } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testJourneyCapabilitiesCannotBypassProtectedOrUnrelatedRoutes() async throws {
        let capabilities: [PlayExperienceCapability] = [.journeyChecks, .journeyEggCollection, .journeyAsks]
        let http = JourneyRoutingHTTP(), api = try service(http, enabled: Set(capabilities))
        for capability in capabilities {
            for path in ["answer", "checkin", "arrive", "photo", "sensor-result", "run-session/save", "run-session/clear",
                         "nodes", "check/unknown", "egg/unknown", "journey/unknown"] {
                do {
                    _ = try await api.request("api/play/" + path, form: ["synthetic": "1"], capability: capability, token: "fixture-token")
                    XCTFail("Journey capability escaped to " + path)
                } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
            }
        }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testJourneyAliasesAndDisabledCapabilitiesNeverDispatch() async throws {
        let http = JourneyRoutingHTTP(), api = try service(http, enabled: [.journeyChecks, .journeyEggCollection, .journeyAsks])
        for (path, capability) in routes {
            for alias in ["api/play/./" + path, "api/play//" + path, "api/play/" + path + "/",
                          "api/play/" + path + ";x=1", "api/play/%63heck/roll", "api/play/../play/" + path] {
                do {
                    _ = try await api.request(alias, form: ["synthetic": "1"], capability: capability, token: "fixture-token")
                    XCTFail("Alias dispatched " + alias)
                } catch { XCTAssertTrue(error is APIError) }
            }
            let disabled = try service(http, enabled: [])
            do {
                _ = try await disabled.request("api/play/" + path, form: ["synthetic": "1"], capability: capability, token: "fixture-token")
                XCTFail("Disabled capability dispatched")
            } catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        }
        XCTAssertTrue(http.requests.isEmpty)
    }
}
