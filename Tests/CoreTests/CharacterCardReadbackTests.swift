import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CharacterCardReadbackTests: XCTestCase {
    private func cardJSON(environment: Bool = true, party: PlayWireValue? = nil, equipment: PlayWireValue? = nil) -> PlayWireValue {
        var rpg: [String: PlayWireValue] = ["enabled": .bool(true)]
        if environment {
            rpg["environment"] = .object(["weather": .string("rain"), "daypart": .string("afternoon"),
                                          "weekpart": .string("weekday"), "season": .string("autumn")])
        }
        var root: [String: PlayWireValue] = [
            "topicId": .int(71), "created": .bool(true), "running": .bool(true),
            "attributes": .array([.object(["stateKey": .string("counter.str"), "label": .string("Strength"),
                                           "value": .int(5), "min": .int(0), "max": .int(20),
                                           "displayType": .string("bar"), "persistScope": .string("run")])]),
            "rpg": .object(rpg)
        ]
        if let party { root["party"] = party }
        if let equipment { root["equipment"] = equipment }
        return .object(root)
    }
    private func breakdown() -> PlayWireValue {
        .object(["die": .int(7), "skill": .object(["statKey": .string("counter.str"), "label": .string("Strength"), "value": .int(5)]),
                 "situational": .object(["raw": .int(7), "applied": .int(2), "cap": .int(2)]),
                 "dc": .int(13), "total": .int(14), "natAuto": .bool(true)])
    }
    private func command() throws -> PlayPlayerCommand {
        try .init(activityID: 41, nodeID: 701, requestID: "synthetic-request", expectedRevision: 2,
                  action: .choice, payload: ["choiceId": .string("LEFT")])
    }
    private func setup(enabled: Set<PlayExperienceCapability> = [.reads, .playerCommands],
                       card: PlayWireValue? = nil) throws -> (Owner, Transport, CharacterCardReadback) {
        let owner = try Owner(), transport = Transport()
        transport.card = card ?? cardJSON()
        transport.view = try PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player)
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!),
                                            transport: transport, enabled: enabled)
        let model = try XCTUnwrap(CharacterCardReadback(topicID: 71, activityID: 41, service: service, currentSession: { owner.value }))
        return (owner, transport, model)
    }
    func testDisabledReadsCannotCreateLease() throws {
        let owner = try Owner(), transport = Transport()
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!),
                                            transport: transport, enabled: [])
        XCTAssertNil(CharacterCardReadback(topicID: 71, activityID: 41, service: service, currentSession: { owner.value }))
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testFirstJourneyProjectsCardBreakdownEnvironmentPartyEquipmentThenRetriesSameRequestId() async throws {
        let (owner, transport, model) = try setup()
        var view = try XCTUnwrap(transport.view.object)
        var player = try XCTUnwrap(view["player"]?.object)
        player["teamActions"] = .array([.object(["memberId": .int(8), "displayName": .string("Synthetic teammate"),
                                                 "roleCode": .string("OBSERVER"), "status": .string("CONFIRMED")])])
        view["player"] = .object(player); transport.view = .object(view)
        transport.status = .object(["topicId": .int(71), "running": .bool(true),
                                    "rpg": .object(["enabled": .bool(true),
                                                    "environment": .object(["weather": .string("rain"), "asOf": .integer(1_000), "expiresAt": .integer(2_000)]),
                                                    "inventory": .object(["lantern": .object(["quantity": .int(1), "status": .string("VALID")])])])])
        await model.load()
        XCTAssertEqual(model.availability, .ready)
        XCTAssertEqual(model.card?.attributes.first?.stateKey, "counter.str")
        XCTAssertEqual(model.card?.environment.weather, .known("rain"))
        XCTAssertEqual(model.card?.party.members.first?.id, 8)
        XCTAssertEqual(model.card?.breakdown.availability, .waitingSource)
        model.acceptBreakdown(.object(["breakdown": breakdown()]))
        XCTAssertEqual(model.card?.breakdown.total, 14)
        XCTAssertEqual(model.card?.breakdown.skill?.statKey, "counter.str")
        XCTAssertEqual(model.card?.equipment.items.first?.id, "lantern")
        XCTAssertTrue(model.card?.equipment.items.first?.expiry.isValid == true)
        XCTAssertTrue(model.card?.expiry.isValid == true)
        let original = try command(); model.bindOriginal(original)
        XCTAssertEqual(model.originalRequestID, "synthetic-request")
        transport.receipt = .object(["activityId": .int(41), "requestId": .string("synthetic-request"),
                                     "action": .string("PLAYER_CHOICE"), "outcome": .string("APPLIED"),
                                     "receiptId": .int(1), "revision": .int(3)])
        await model.retryOriginal()
        let commands = transport.requests.filter { $0.url?.path == "/api/game/session/command" }
        XCTAssertEqual(commands.count, 1)
        let body = try JSONDecoder().decode(PlayWireValue.self, from: try XCTUnwrap(commands.first?.httpBody))
        XCTAssertEqual(body["requestId"].text, "synthetic-request")
        XCTAssertEqual(body["requestId"].text, original.requestID)
        XCTAssertEqual(model.originalRequestID, original.requestID)
        XCTAssertEqual(Set(transport.requests.compactMap { $0.url?.path }),
                       ["/api/play/character", "/api/play/rpg/status", "/api/game/session/view", "/api/game/session/command"])
        XCTAssertEqual(owner.value?.accountID, 7)
    }
    func testRetryWithoutOriginalRequestIdDoesNotMintOne() async throws {
        let (_, transport, model) = try setup()
        await model.load(); let paths = transport.requests.map { $0.url?.path }
        await model.retryOriginal()
        XCTAssertEqual(model.availability, .ready)
        XCTAssertNil(model.originalRequestID)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, paths)
    }
    func testMissingBreakdownAndEquipmentStayWaitingSource() async throws {
        let (_, _, model) = try setup()
        await model.load()
        XCTAssertEqual(model.card?.breakdown, .waitingSource)
        XCTAssertEqual(model.card?.equipment.availability, .waitingSource)
        model.acceptBreakdown(.object(["total": .int(99), "success": .bool(true)]))
        XCTAssertEqual(model.card?.breakdown.availability, .ready)
        XCTAssertEqual(model.card?.breakdown.total, 99)
        XCTAssertNil(model.card?.breakdown.die)
    }
    func testHiddenSkillIsRedactedAndSuccessIsNotRecomputed() {
        let hidden = CharacterCheckBreakdown.read(.object(["die": .int(6), "total": .int(10), "dc": .int(99),
                                                           "skill": .object(["hidden": .bool(true), "statKey": .string("counter.fate"), "label": .string("Fate"), "value": .int(4)])]))
        XCTAssertEqual(hidden.skill?.hidden, true)
        XCTAssertNil(hidden.skill?.statKey); XCTAssertNil(hidden.skill?.value)
        XCTAssertEqual(hidden.total, 10); XCTAssertEqual(hidden.dc, 99)
        XCTAssertEqual(CharacterCheckBreakdown.read(.null), .waitingSource)
        XCTAssertEqual(CharacterCheckBreakdown.read(.string("ok")).availability, .unknown)
    }
    func testAccountChangeAndDismissalDropTheCard() async throws {
        let (owner, transport, model) = try setup()
        await model.load(); XCTAssertEqual(model.availability, .ready)
        owner.value = try PlayExperienceSession(accountID: 8, epoch: 1, namespace: "synthetic", token: "synthetic-token")
        await model.load(); XCTAssertEqual(model.availability, .unknown); XCTAssertNil(model.card)
        owner.value = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token")
        await model.load(); model.dismiss()
        XCTAssertEqual(model.availability, .waitingSource); XCTAssertNil(model.card)
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
    }
    func testMalformedCharacterPayloadIsUnknownNotATemplateSuccess() async throws {
        let (_, transport, model) = try setup(card: .object(["topicId": .int(71)]))
        await model.load()
        XCTAssertEqual(model.availability, .unknown)
        XCTAssertNil(model.card)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/api/play/character"])
    }
}

@MainActor private final class Owner {
    var value: PlayExperienceSession?
    init() throws { value = try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token") }
}

private final class Transport: HTTPTransport {
    @MainActor var requests: [URLRequest] = []
    @MainActor var card: PlayWireValue = .null
    @MainActor var status: PlayWireValue = .null
    @MainActor var view: PlayWireValue = .null
    @MainActor var receipt: PlayWireValue = .null
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await execute(request) }
    @MainActor private func execute(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let data: PlayWireValue
        switch path {
        case "/api/play/character": data = card
        case "/api/play/rpg/status": data = status == .null ? card : status
        case "/api/game/session/view": data = view
        case "/api/game/session/command", "/api/game/session/receipt":
            data = receipt == .null ? .object(["activityId": .int(41), "requestId": .string("synthetic-request"),
                                               "action": .string("PLAYER_CHOICE"), "outcome": .string("APPLIED"),
                                               "receiptId": .int(1), "revision": .int(3)]) : receipt
        default: throw APIError.invalidRequest
        }
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": data])), 200)
    }
}
