import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CharacterCardOpenEntryTests: XCTestCase {
    func testOpenOneCardReadsSameRequestAndActivityAndRefusesOtherActivityOrStaleIssuance() async throws {
        let requestID = "read-card-0041"
        let activityID = 41
        let issuance = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let owner = try Owner()
        let transport = Transport()
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!),
                                            transport: transport, enabled: [.reads])
        let model = try XCTUnwrap(CharacterCardReadback(topicID: 71, activityID: activityID, service: service,
                                                        currentSession: { owner.value }))
        let entry = try XCTUnwrap(CharacterCardOpenEntry(model: model, requestID: requestID, activityID: activityID,
                                                         issuance: issuance))
        let read = try XCTUnwrap(await entry.open())

        XCTAssertEqual(read.requestID, requestID)
        XCTAssertEqual(read.activityID, activityID)
        XCTAssertEqual(read.requestID, entry.requestID)
        XCTAssertEqual(read.activityID, entry.activityID)
        XCTAssertEqual(read.card.topicID, 71)
        XCTAssertEqual(read.card.attributes.first?.stateKey, "counter.str")
        XCTAssertNil(read.card.originalRequestID)
        XCTAssertNil(model.originalRequestID)
        let paths = transport.requests.map { $0.url?.path }
        XCTAssertEqual(paths, ["/api/play/character", "/api/play/rpg/status"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        let status = try XCTUnwrap(transport.requests.last?.url)
        let items = try XCTUnwrap(URLComponents(url: status, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "activityId" }?.value, "41")
        XCTAssertEqual(items.first { $0.name == "topicId" }?.value, "71")

        XCTAssertNil(entry.readBack(requestID: requestID, activityID: 99, issuance: issuance))
        XCTAssertNil(entry.readBack(requestID: "read-card-other", activityID: activityID, issuance: issuance))
        XCTAssertNil(entry.readBack(requestID: requestID, activityID: activityID, issuance: UUID()))
        XCTAssertEqual(transport.requests.map { $0.url?.path }, paths)
        XCTAssertEqual(entry.requestID, requestID)
        XCTAssertEqual(entry.activityID, activityID)

        let again = try XCTUnwrap(entry.readBack(requestID: requestID, activityID: activityID, issuance: issuance))
        XCTAssertEqual(again.requestID, requestID)
        XCTAssertEqual(again.activityID, activityID)
        XCTAssertEqual(again.card, read.card)

        owner.value = nil
        XCTAssertNil(entry.readBack(requestID: requestID, activityID: activityID, issuance: issuance))
        XCTAssertEqual(transport.requests.map { $0.url?.path }, paths)
        XCTAssertFalse(transport.requests.contains { ($0.url?.path ?? "").contains("command") || ($0.url?.path ?? "").contains("receipt") })
    }

    func testOtherActivityOrBlankRequestDoesNotOpenThisCard() throws {
        let owner = try Owner()
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!),
                                            transport: Transport(), enabled: [.reads])
        let model = try XCTUnwrap(CharacterCardReadback(topicID: 71, activityID: 41, service: service,
                                                        currentSession: { owner.value }))
        let issuance = UUID()
        XCTAssertNil(CharacterCardOpenEntry(model: model, requestID: "read-card-0041", activityID: 99, issuance: issuance))
        XCTAssertNil(CharacterCardOpenEntry(model: model, requestID: "", activityID: 41, issuance: issuance))
        XCTAssertNil(CharacterCardOpenEntry(model: model, requestID: " read-card-0041 ", activityID: 41, issuance: issuance))
        XCTAssertNil(CharacterCardOpenEntry(model: model, requestID: "read-card-0041", activityID: 0, issuance: issuance))
    }
}

@MainActor private final class Owner {
    var value: PlayExperienceSession?
    init() throws { value = try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token") }
}

private final class Transport: HTTPTransport {
    @MainActor var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await execute(request) }
    @MainActor private func execute(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let card = PlayWireValue.object([
            "topicId": .int(71), "created": .bool(true), "running": .bool(true),
            "attributes": .array([.object(["stateKey": .string("counter.str"), "label": .string("Strength"),
                                           "value": .int(5), "min": .int(0), "max": .int(20),
                                           "displayType": .string("bar"), "persistScope": .string("run")])]),
            "party": .object(["members": .array([.object(["memberId": .int(8), "displayName": .string("Synthetic teammate"),
                                                          "roleCode": .string("OBSERVER"), "status": .string("CONFIRMED")])])]),
            "rpg": .object(["enabled": .bool(true),
                            "environment": .object(["weather": .string("rain"), "daypart": .string("afternoon"),
                                                    "weekpart": .string("weekday"), "season": .string("autumn")])])
        ])
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": card])), 200)
    }
}
