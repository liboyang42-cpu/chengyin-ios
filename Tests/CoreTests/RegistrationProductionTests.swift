import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class RegistrationProductionWire: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) throws -> String = { _ in "{}" }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(try handler(request).utf8), 200)
    }
}
@MainActor private final class RegistrationProductionJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    var fail = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        if fail { throw APIError.malformedResponse }; return records[ownerKey + targetKey]
    }
    func write(_ record: OperationPendingRecord) throws {
        if fail { throw APIError.malformedResponse }
        let key = record.ownerKey + record.targetKey
        if let old = records[key], old.operationID != record.operationID { throw APIError.invalidRequest }
        records[key] = record
    }
    func clear(_ record: OperationPendingRecord) throws {
        if fail { throw APIError.malformedResponse }; records.removeValue(forKey: record.ownerKey + record.targetKey)
    }
}

@MainActor final class RegistrationProductionTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    private let identity = ProfileReadIdentity(accountID: 1, epoch: 9)
    private let configuration = try! APIConfiguration(baseURL: URL(string: "https://api.example.com/prod-api")!)
    private var legal: String { #"{"code":200,"data":{"docType":"activity_host_data_sharing","docVersion":"fixture-v1","scene":"activity_signup","eventType":"AGREE"}}"# }
    private var quote: String { #"{"code":200,"data":{"payAmount":0,"quoteSign":"fixture-quote"}}"# }
    private func grant(paths: Set<String>? = nil, account: Int = 1, market: RegionalMarket = .china, storefront: String = "CHN") throws -> RegistrationProductionApproval {
        try .init(endpoint: .init(baseURL: configuration.baseURL, namespace: "fixture-namespace", accountID: account,
                                 paths: paths ?? RegistrationProductionApproval.registrationPaths.union(RegistrationProductionApproval.waitlistPaths)),
                  identity: identity, market: market, storefront: storefront, product: .physicalActivity, activityID: 7, ticketIDs: [11],
                  consentVersion: "fixture-v1", noticeURL: URL(string: "https://legal.example.com/signup-v1")!, expiresAt: fixedNow.addingTimeInterval(3600))
    }
    private func session(identity: ProfileReadIdentity? = nil, namespace: String = "fixture-namespace", storefront: String = "CHN") throws -> RegistrationProductionSession {
        try .init(identity: identity ?? self.identity, namespace: namespace, market: .china, storefront: storefront, token: "fixture-token")
    }
    private func status(_ state: String, id: Int? = nil, registrationID: Int? = nil) -> String {
        let ids = (id.map { ",\"id\":\($0)" } ?? "") + (registrationID.map { ",\"registrationId\":\($0)" } ?? "")
        return "{\"code\":200,\"data\":{\"activityId\":7,\"ticketId\":11,\"memberId\":1,\"state\":\"\(state)\",\"eligibilityState\":\"ELIGIBLE\",\"waitlistJoinAllowed\":true\(ids)}}"
    }
    private func installReadHandler(_ wire: RegistrationProductionWire) {
        let legal = self.legal, quote = self.quote
        wire.handler = { request in
            if request.url?.path.hasSuffix("consents/latest") == true { return legal }
            if request.url?.path.hasSuffix("registration/quote") == true { return quote }
            if request.url?.path.hasSuffix("registration/create") == true { return #"{"code":200,"data":{"registrationId":41,"payableAmount":0}}"# }
            if request.url?.path.hasSuffix("registration/info") == true { return #"{"code":200,"data":{"id":41,"registrationStatus":1,"paymentStatus":0}}"# }
            throw APIError.malformedResponse
        }
    }
    private func makeIntent(_ service: RegistrationProductionService) async throws -> RegistrationCreateIntent {
        let selection = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11)
        let quote = try await service.quote(selection, token: "fixture-token")
        return try .init(selection: selection, quote: quote, realName: "Fixture Person", phone: "13800000000", requestID: "fixture-intent")
    }
    func testFactoryHasNoDefaultGrantAndRejectsDifferentOrigin() throws {
        let journal = RegistrationProductionJournal(), current = try session()
        XCTAssertNil(RegistrationProductionFactory.make(configuration: configuration, approval: nil, journal: journal, current: { current }))
        XCTAssertNil(RegistrationProductionFactory.make(configuration: try .init(baseURL: URL(string: "https://other.example.com")!), approval: grant(), journal: journal, current: { current }))
    }
    func testGrantRequiresExactAccountCNStorefrontAndKnownPaths() {
        XCTAssertThrowsError(try grant(account: 2))
        XCTAssertThrowsError(try grant(market: .unitedStates, storefront: "USA"))
        XCTAssertThrowsError(try grant(storefront: "USA"))
        XCTAssertThrowsError(try grant(paths: ["api/registration/create"]))
        XCTAssertThrowsError(try grant(paths: RegistrationProductionApproval.registrationPaths.union(["api/pay/retry"])))
    }
    func testWrongAccountEpochNamespaceStorefrontAndTicketSendNothing() async throws {
        for current in [try session(identity: .init(accountID: 2, epoch: 9)), try session(identity: .init(accountID: 1, epoch: 10)), try session(namespace: "other"), try session(storefront: "USA")] {
            let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal()
            let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: journal, current: { current }, now: { self.fixedNow })
            do { _ = try await service.quote(.init(ownerID: 7, ticketID: 11), token: "fixture-token"); XCTFail("Mismatched scope") } catch {}
            XCTAssertTrue(wire.requests.isEmpty)
        }
        let wire = RegistrationProductionWire(), current = try session()
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: RegistrationProductionJournal(), current: { current }, now: { self.fixedNow })
        do { _ = try await service.quote(.init(ownerID: 7, ticketID: 12), token: "fixture-token"); XCTFail("Unapproved ticket") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExpiredGrantSendsNothing() async throws {
        let wire = RegistrationProductionWire(), current = try session()
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: RegistrationProductionJournal(), current: { current }, now: { self.fixedNow.addingTimeInterval(3600) })
        do { _ = try await service.quote(.init(ownerID: 7, ticketID: 11), token: "fixture-token"); XCTFail("Expired grant") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testLegalReadbackMustMatchVersionSceneAndAgree() async throws {
        for replacement in [legal.replacingOccurrences(of: "fixture-v1", with: "fixture-v2"), legal.replacingOccurrences(of: "AGREE", with: "REVOKE"), legal.replacingOccurrences(of: "activity_signup", with: "another_scene"), #"{"code":200,"data":{}}"#] {
            let wire = RegistrationProductionWire(), current = try session()
            wire.handler = { _ in replacement }
            let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: RegistrationProductionJournal(), current: { current }, now: { self.fixedNow })
            do { _ = try await service.quote(.init(ownerID: 7, ticketID: 11), token: "fixture-token"); XCTFail("Unverified legal receipt") } catch {}
            XCTAssertEqual(wire.requests.count, 1)
            XCTAssertTrue(wire.requests[0].url!.path.hasSuffix("consents/latest"))
        }
    }
    func testFreshQuoteCreateReceiptAndStatusNeverDispatchPayment() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        installReadHandler(wire)
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: journal, current: { current }, now: { self.fixedNow })
        let intent = try await makeIntent(service)
        let receipt = try await service.create(intent, token: "fixture-token")
        XCTAssertEqual(receipt.registrationID, 41)
        let readback = try await service.readStatus(registrationID: 41, token: "fixture-token")
        XCTAssertEqual(readback.registrationStatus, 1); XCTAssertEqual(readback.paymentStatus, 0)
        XCTAssertEqual(journal.records.count, 1)
        XCTAssertEqual(try service.creationLock(.init(activityID: 7, ticketID: 11)), .pending(registrationID: 41))
        let retained = try await service.readRetainedStatus(.init(activityID: 7, ticketID: 11))
        XCTAssertEqual(retained.registrationID, 41)
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("registration/create") }.count, 1)
        XCTAssertFalse(wire.requests.contains { $0.url!.path.contains("payment") || $0.url!.path.contains("retry") })
    }
    func testCreateTimeoutSurvivesServiceRecreationAndNeverResends() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        installReadHandler(wire)
        let baseHandler = wire.handler
        wire.handler = { request in
            if request.url!.path.hasSuffix("registration/create") { throw URLError(.timedOut) }
            return try baseHandler(request)
        }
        let grant = try grant()
        let service = RegistrationProductionService(configuration: configuration, approval: grant, transport: wire, journal: journal, current: { current }, now: { self.fixedNow })
        let intent = try await makeIntent(service)
        do { _ = try await service.create(intent, token: "fixture-token"); XCTFail("Timeout") } catch {}
        let restored = RegistrationProductionService(configuration: configuration, approval: grant, transport: wire, journal: journal, current: { current }, now: { self.fixedNow })
        XCTAssertEqual(try restored.creationLock(.init(activityID: 7, ticketID: 11)), .pending(registrationID: nil))
        let fresh = try await makeIntent(restored)
        do { _ = try await restored.create(fresh, token: "fixture-token"); XCTFail("Retained durable lock") } catch {}
        XCTAssertEqual(journal.records.count, 1)
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("registration/create") }.count, 1)
    }
    func testStaleQuoteAndCorruptJournalBlockBeforeCreate() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        installReadHandler(wire); var clock = fixedNow
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: journal, current: { current }, now: { clock })
        let intent = try await makeIntent(service); clock.addTimeInterval(120)
        do { _ = try await service.create(intent, token: "fixture-token"); XCTFail("Stale quote") } catch {}
        clock = fixedNow
        let next = try await makeIntent(service); journal.fail = true
        do { _ = try await service.create(next, token: "fixture-token"); XCTFail("Corrupt journal") } catch {}
        XCTAssertFalse(wire.requests.contains { $0.url!.path.hasSuffix("registration/create") })
    }
    func testUnknownWaitlistJoinRequiresReadbackAndCannotRepeatPost() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        var state = status("NONE")
        wire.handler = { request in
            if request.url!.path.hasSuffix("waitlist/status") { return state }
            throw URLError(.timedOut)
        }
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: journal, current: { current }, now: { self.fixedNow })
        let scope = try RegistrationWaitlistScope(activityID: 7, ticketID: 11)
        do { _ = try await service.join(scope); XCTFail("Unknown join") } catch {}
        do { _ = try await service.join(scope); XCTFail("Unresolved join") } catch {}
        XCTAssertEqual(journal.records.count, 1)
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("waitlist/join") }.count, 1)
        state = status("WAITING", id: 5)
        let result = try await service.status(scope)
        XCTAssertEqual(result.state, .waiting); XCTAssertTrue(journal.records.isEmpty)
    }
    func testCancelReceiptRequiresAuthoritativeTerminalReadback() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        var state = status("WAITING", id: 5)
        wire.handler = { request in request.url!.path.hasSuffix("waitlist/status") ? state : #"{"code":200,"data":true}"# }
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: journal, current: { current }, now: { self.fixedNow })
        let scope = try RegistrationWaitlistScope(activityID: 7, ticketID: 11)
        do { _ = try await service.cancel(scope); XCTFail("Nonterminal readback") } catch {}
        XCTAssertEqual(journal.records.count, 1)
        state = status("CANCELLED", id: 5)
        _ = try await service.status(scope); XCTAssertTrue(journal.records.isEmpty)
    }
    func testExplicitLegalAgreementUsesExactSourceFieldsAndReadback() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        let confirmed = legal; var agreed = false
        wire.handler = { request in
            if request.url!.path.hasSuffix("consents/latest") { return agreed ? confirmed : #"{"code":200,"data":{}}"# }
            agreed = true; return #"{"code":200,"data":{}}"#
        }
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: journal, current: { current }, now: { self.fixedNow })
        try await service.agreeToSignupNotice(.init(activityID: 7, ticketID: 11))
        XCTAssertEqual(wire.requests.count, 3); XCTAssertTrue(journal.records.isEmpty)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(wire.requests[1].httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["docType", "scene", "eventType", "requestId"])
        XCTAssertEqual(body["eventType"] as? String, "AGREE")
        try await service.agreeToSignupNotice(.init(activityID: 7, ticketID: 11))
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("/consents") }.count, 1)
    }
    func testUnknownConsentIsNotResubmitted() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        wire.handler = { request in
            if request.url!.path.hasSuffix("consents/latest") { return #"{"code":200,"data":{}}"# }
            throw URLError(.timedOut)
        }
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire, journal: journal, current: { current }, now: { self.fixedNow })
        for _ in 0..<2 { do { try await service.agreeToSignupNotice(.init(activityID: 7, ticketID: 11)); XCTFail("Unknown consent") } catch {} }
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("/consents") }.count, 1)
        XCTAssertEqual(journal.records.count, 1)
    }
    func testSessionReplacementDuringLegalReadCannotReachQuoteOrCreate() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal()
        var current: RegistrationProductionSession? = try session()
        let legal = self.legal
        wire.handler = { _ in current = nil; return legal }
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire,
            journal: journal, current: { current }, now: { self.fixedNow })
        do { _ = try await service.quote(.init(ownerID: 7, ticketID: 11), token: "fixture-token"); XCTFail("Session replaced") } catch {}
        XCTAssertEqual(wire.requests.count, 1); XCTAssertTrue(journal.records.isEmpty)
    }

    func testDefiniteWaitlistRefusalDoesNotBecomeAFalseJoinedState() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        let empty = status("NONE")
        wire.handler = { request in request.url!.path.hasSuffix("waitlist/status") ? empty : #"{"code":409,"msg":"Fixture refusal"}"# }
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire,
            journal: journal, current: { current }, now: { self.fixedNow })
        do { _ = try await service.join(.init(activityID: 7, ticketID: 11)); XCTFail("Business refusal") }
        catch { XCTAssertEqual((error as? RegistrationResponseFailure)?.code, 409) }
        XCTAssertTrue(journal.records.isEmpty)
        let result = try await service.status(.init(activityID: 7, ticketID: 11)); XCTAssertEqual(result.state, .none)
    }

    func testProductionOfferIsRereadBeforeQuoteAndCreateAndCannotBeReplaced() async throws {
        let wire = RegistrationProductionWire(), journal = RegistrationProductionJournal(), current = try session()
        let deadline = ISO8601DateFormatter().string(from: fixedNow.addingTimeInterval(1800))
        var token = "fixture-offer"
        let legal = self.legal, quote = self.quote
        wire.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("consents/latest") { return legal }
            if path.hasSuffix("waitlist/status") {
                return "{\"code\":200,\"data\":{\"id\":5,\"activityId\":7,\"ticketId\":11,\"memberId\":1,\"state\":\"OFFERED\",\"eligibilityState\":\"ELIGIBLE\",\"waitlistJoinAllowed\":true,\"offerToken\":\"\(token)\",\"offerExpiresAt\":\"\(deadline)\"}}"
            }
            if path.hasSuffix("registration/quote") { return quote }
            return #"{"code":200,"data":{"registrationId":41,"payableAmount":0}}"#
        }
        let service = RegistrationProductionService(configuration: configuration, approval: try grant(), transport: wire,
            journal: journal, current: { current }, now: { self.fixedNow })
        let offer = try RegistrationWaitlistOffer(id: 5, token: token)
        let selection = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11, waitlistOffer: offer)
        let received = try await service.quote(selection, token: "fixture-token")
        let intent = try RegistrationCreateIntent(selection: selection, quote: received, realName: "Fixture", phone: "13800000000", waitlistOffer: offer)
        token = "changed-offer"
        do { _ = try await service.create(intent, token: "fixture-token"); XCTFail("Offer changed after quote") } catch {}
        XCTAssertTrue(journal.records.isEmpty)
        XCTAssertEqual(wire.requests.filter { $0.url!.path.hasSuffix("waitlist/status") }.count, 2)
        XCTAssertFalse(wire.requests.contains { $0.url!.path.hasSuffix("registration/create") })
    }

}
