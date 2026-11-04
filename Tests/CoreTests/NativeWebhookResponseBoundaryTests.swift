import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class NativeWebhookResponseBoundaryTests: XCTestCase {
    func testServerFailuresAfterDispatchRemainUnknownAndKeepOriginalOnRestart() async throws {
        for (status, body) in [(503, "<html>gateway</html>"), (500, #"{"code":403}"#), (200, #"{"code":503,"trace_id":"synthetic-trace"}"#)] {
            let provider = NativeWebhookFixtureProvider(try NativeWebhookFixtures.context())
            let journal = NativeWebhookMemoryJournal()
            let transport = NativeWebhookFixtureTransport { request in
                request.httpMethod == "GET" ? (NativeWebhookFixtures.list(), 200) : (Data(body.utf8), status)
            }
            let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport)
            let flow = NativeWebhookCoordinator(service: service, provider: provider, journal: .init(journal: journal))
            await flow.load(); flow.prepareAction(.rotate, resource: try NativeWebhookFixtures.resource())
            let original = try XCTUnwrap(flow.confirmation)
            await flow.confirm(original.id)
            XCTAssertEqual(flow.phase, .unknown)
            XCTAssertEqual(journal.record?.nativeWebhook?.requestID, original.requestID)
            let restarted = NativeWebhookCoordinator(service: service, provider: provider, journal: .init(journal: journal))
            await restarted.load()
            XCTAssertEqual(restarted.pending?.requestID, original.requestID)
            XCTAssertEqual(transport.requests.filter { $0.httpMethod != "GET" }.count, 1)
        }
    }
    func testMalformedPagesCannotBecomeAuthoritativeResources() async throws {
        let row = NativeWebhookFixtures.resourceJSON()
        let other = row.replacingOccurrences(of: "\"id\":\"\(NativeWebhookFixtures.resourceID.rawValue)\"", with: "\"id\":\"12\"")
        for page in [
            "{\"list\":[\(row),\(row)],\"has_more\":false}",
            "{\"list\":[\(row),\(other)],\"has_more\":false}",
            "{\"list\":[],\"has_more\":true,\"next_cursor\":\"next\"}",
            "{\"list\":[\(row)],\"has_more\":true,\"next_cursor\":\"previous\"}"
        ].enumerated() {
            let provider = NativeWebhookFixtureProvider(try NativeWebhookFixtures.context())
            let transport = NativeWebhookFixtureTransport { _ in (NativeWebhookFixtures.envelope(page.element), 200) }
            let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport)
            do {
                _ = try await service.resources(.subscription, context: provider.value, cursor: "previous", limit: page.offset == 0 ? 2 : 1)
                XCTFail("Malformed page accepted")
            } catch { XCTAssertTrue(error is NativeWebhookClientError) }
        }
    }
    func testDeliveryFilterMismatchFailsAndMatchingUnknownStaysUnknown() async throws {
        let provider = NativeWebhookFixtureProvider(try NativeWebhookFixtures.context())
        let transport = NativeWebhookFixtureTransport { _ in
            (NativeWebhookFixtures.envelope("{\"list\":[" + NativeWebhookFixtures.deliveryJSON() + "],\"has_more\":false}"), 200)
        }
        let service = NativeWebhookHTTPService(provider: provider, authorizer: provider, transport: transport)
        do {
            _ = try await service.deliveries(NativeWebhookFixtures.resourceID, context: provider.value, state: .sent)
            XCTFail("UNKNOWN presented in SENT results")
        } catch { XCTAssertEqual(error as? NativeWebhookClientError, .invalidWire) }
        let page = try await service.deliveries(NativeWebhookFixtures.resourceID, context: provider.value, state: .unknown)
        XCTAssertEqual(page.list.first?.state, .unknown)
    }
}
