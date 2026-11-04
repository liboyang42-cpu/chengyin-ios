import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class NativePushAttemptReadBoundaryTests: XCTestCase {
    private final class Transport: HTTPTransport {
        var requests: [URLRequest] = []
        var body = Data()
        var duringSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); duringSend?(); return (body, 200)
        }
    }
    private func page(ids: [String], next: String = "0", installation: String = "synthetic-install") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": [
            "source": "original-im-push-attempts-v1", "installation_id": installation,
            "items": ids.map { ["id": $0, "state": "UNKNOWN"] }, "next_before": next, "delivery_proven": false
        ]])
    }
    private func reader(_ transport: Transport, current: @escaping () -> Bool = { true }) throws -> NativePushAttemptReader {
        .init(configuration: try .init(baseURL: URL(string: "https://push.test")!), transport: transport,
            credential: "synthetic-credential", installation: "synthetic-install", current: current, unauthorized: {})
    }
    func testUnknownOriginalAttemptsPageWithoutSendingOrPromotingDelivery() async throws {
        let transport = Transport(), reader = try reader(transport)
        transport.body = try page(ids: ["100", "90"], next: "90")
        await reader.load(); XCTAssertNil(reader.issue); XCTAssertEqual(reader.items.map(\.state), ["UNKNOWN", "UNKNOWN"])
        transport.body = try page(ids: ["80"], next: "0")
        await reader.load(more: true)
        XCTAssertNil(reader.issue); XCTAssertEqual(reader.items.map(\.id), ["100", "90", "80"])
        XCTAssertEqual(transport.requests.last?.url?.query, "installation_id=synthetic-install&before=90")
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && !$0.httpShouldHandleCookies })
    }
    func testMalformedInitialPagesStayUnavailable() async throws {
        for (ids, next) in [(["100", "100"], "0"), (["0100"], "0"), (["100"], "101"), ([], "90"), (["100"], "00")] {
            let transport = Transport(), reader = try reader(transport)
            transport.body = try page(ids: ids, next: next)
            await reader.load(); XCTAssertNotNil(reader.issue); XCTAssertTrue(reader.items.isEmpty)
        }
    }
    func testMoreCannotRepeatEarlierRowsOrMoveCursorBackwards() async throws {
        for (ids, next) in [(["90"], "0"), (["100"], "0"), (["80"], "90"), (["80"], "85")] {
            let transport = Transport(), reader = try reader(transport)
            transport.body = try page(ids: ["100", "90"], next: "90"); await reader.load()
            transport.body = try page(ids: ids, next: next); await reader.load(more: true)
            XCTAssertNotNil(reader.issue); XCTAssertTrue(reader.items.isEmpty)
        }
    }
    func testAccountChangeAndRetirementDiscardLatePrivateRows() async throws {
        let transport = Transport(); var current = true
        let reader = try reader(transport, current: { current })
        transport.body = try page(ids: ["100"])
        transport.duringSend = { current = false; reader.retire() }
        await reader.load()
        XCTAssertTrue(reader.items.isEmpty); XCTAssertFalse(reader.busy); XCTAssertFalse(reader.isCurrent)
    }
    func testOversizedResponseCannotBecomeAnEmptySuccess() async throws {
        let transport = Transport(), reader = try reader(transport)
        transport.body = try page(ids: []) + Data(repeating: 32, count: 1_048_576)
        await reader.load(); XCTAssertNotNil(reader.issue); XCTAssertTrue(reader.items.isEmpty)
    }
}
