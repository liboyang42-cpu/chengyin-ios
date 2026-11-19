import Foundation
import XCTest
@testable import QuestifyCore

/// F12 family ticket (1 adult + 1 child): parsing, age range and the create body. Synthetic data only.
@MainActor
private final class FamilyCaptureService: RegistrationCoordinatingService {
    private(set) var creates: [RegistrationCreateIntent] = []
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        try JSONDecoder().decode(RegistrationQuote.self, from: Data(#"{"payAmount":19.99,"quoteSign":"fixture-signature"}"#.utf8))
    }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        creates.append(intent)
        return try JSONDecoder().decode(RegistrationCreateResult.self, from: Data(#"{"registrationId":41}"#.utf8))
    }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot { throw APIError.notConfigured }
}

@MainActor
final class RegistrationFamilyTicketTests: XCTestCase {
    private func ticket(_ json: String) throws -> ActivityTicket {
        try JSONDecoder().decode(ActivityTicket.self, from: Data(json.utf8))
    }
    private func body(_ intent: RegistrationCreateIntent) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
    }
    private func quote() throws -> RegistrationQuote {
        try JSONDecoder().decode(RegistrationQuote.self, from: Data(#"{"payAmount":19.99,"quoteSign":"fixture-signature"}"#.utf8))
    }

    func testFamilyTicketParsesCompositionAndAgeRange() throws {
        let family = try ticket(#"{"id":9,"name":"示例亲子票（1 大 1 小）","adultCount":1,"childCount":1,"childAgeMin":3,"childAgeMax":12}"#)
        XCTAssertEqual(family.party.adultCount, 1); XCTAssertEqual(family.party.childCount, 1)
        XCTAssertEqual(family.party.childAgeMin, 3); XCTAssertEqual(family.party.childAgeMax, 12)
        XCTAssertTrue(family.party.isFamily)
        XCTAssertEqual(family.party.childAgeRange, 3...12)
    }
    func testOrdinaryAndOldTicketsDefaultToOneAdultNoChild() throws {
        for json in [#"{"id":9,"name":"示例票"}"#, #"{"id":9,"name":"示例票","adultCount":1,"childCount":0,"childAgeMin":null,"childAgeMax":null}"#,
                     #"{"id":9,"name":"示例票","adultCount":"bad","childCount":true}"#] {
            let value = try ticket(json)
            XCTAssertEqual(value.party, RegistrationTicketParty(), json)
            XCTAssertFalse(value.party.isFamily); XCTAssertNil(value.party.childAgeRange)
        }
        XCTAssertEqual(try ticket(#"{"id":9,"name":"示例票","childCount":"1","childAgeMin":"4","childAgeMax":"10"}"#).party.childAgeRange, 4...10)
    }
    func testChildAgeMustBeInsideTheTicketRange() {
        let family = RegistrationTicketParty(adultCount: 1, childCount: 1, childAgeMin: 3, childAgeMax: 12)
        XCTAssertFalse(family.accepts(childAge: nil))
        XCTAssertFalse(family.accepts(childAge: 2)); XCTAssertFalse(family.accepts(childAge: 13))
        XCTAssertTrue(family.accepts(childAge: 3)); XCTAssertTrue(family.accepts(childAge: 12))
        // A family ticket without a usable range cannot be ordered; the server would reject it.
        XCTAssertFalse(RegistrationTicketParty(adultCount: 1, childCount: 1).accepts(childAge: 7))
        XCTAssertFalse(RegistrationTicketParty(adultCount: 1, childCount: 1, childAgeMin: 12, childAgeMax: 3).accepts(childAge: 7))
        // Ordinary tickets never send an age.
        XCTAssertTrue(RegistrationTicketParty().accepts(childAge: nil))
        XCTAssertFalse(RegistrationTicketParty().accepts(childAge: 7))
    }
    func testCreateBodyCarriesChildAgeOnlyWhenSupplied() throws {
        let selection = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11)
        let plain = try body(RegistrationCreateIntent(selection: selection, quote: quote(), realName: "示例参与者", phone: "fixture-phone"))
        XCTAssertNil(plain["childAge"])
        let family = try body(RegistrationCreateIntent(selection: selection, quote: quote(), realName: "示例参与者", phone: "fixture-phone", childAge: 7))
        XCTAssertEqual(family["childAge"] as? Int, 7)
        XCTAssertNil(family["childName"])
        XCTAssertThrowsError(try RegistrationCreateIntent(selection: selection, quote: quote(), realName: "示例参与者", phone: "fixture-phone", childAge: -1))
    }
    func testCoordinatorForwardsChildAgeToTheCreateIntent() async throws {
        let service = FamilyCaptureService()
        let coordinator = RegistrationCoordinator(service: service, makeRequestID: { "fixture-request-id" })
        try coordinator.setAccount(id: 1, token: "fixture-account-one-token")
        XCTAssertEqual(coordinator.select(try RegistrationQuoteRequest(ownerID: 7, ticketID: 11)), .applied)
        let quoted = await coordinator.requestQuote()
        XCTAssertEqual(quoted, .applied)
        _ = await coordinator.confirm(RegistrationParticipantDetails(realName: "示例参与者", phone: "fixture-phone", childAge: 7))
        XCTAssertEqual(service.creates.map(\.childAge), [7])
    }
    func testDraftDetailsCarryChildAge() {
        let draft = RegistrationUIFormDraft(realName: " 示例参与者 ", phone: "13800000000", childAge: 5)
        XCTAssertEqual(draft.details(waitlistOffer: nil, childAge: 5).childAge, 5)
        XCTAssertNil(draft.details(waitlistOffer: nil).childAge)
        XCTAssertNil(draft.validation)
    }
}
