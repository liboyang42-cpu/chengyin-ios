import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantNoteCorrectionPresentationTests: XCTestCase {
    func testNewNoteAndCorrectionHaveDistinctTitles() throws {
        let customer = try MerchantCustomerID(61001)
        XCTAssertEqual(MerchantBusinessMutation.addNote(customer: customer, content: "New", correctsNoteID: nil).titleKey, "merchant.business.addNote")
        XCTAssertEqual(MerchantBusinessMutation.addNote(customer: customer, content: "Correction", correctsNoteID: 901).titleKey, "merchant.business.correctNote")
    }
    func testCorrectionRequestKeepsOriginalTargetAndAppendRoute() throws {
        let mutation = MerchantBusinessMutation.addNote(customer: try .init(61001), content: "Correction", correctsNoteID: 901)
        let request = try mutation.request(requestID: "correction-contract")
        XCTAssertEqual(request.path, "api/merchant/crm/customers/61001/notes")
        XCTAssertEqual(request.query, [:])
        guard case .json(let fields) = request.body else { return XCTFail() }
        XCTAssertEqual(Set(fields.keys), ["correctsNoteId", "content", "requestId"])
        XCTAssertEqual(fields["correctsNoteId"], .int(901)); XCTAssertEqual(fields["content"], .string("Correction"))
        XCTAssertEqual(fields["requestId"], .string("correction-contract"))
    }
    func testCancelModeStillNeedsNewNonemptyTextBeforeReview() throws {
        let customer = try MerchantCustomerID(61001)
        XCTAssertThrowsError(try MerchantBusinessMutation.addNote(customer: customer, content: "", correctsNoteID: nil).request(requestID: "validation-only"))
        let new = try MerchantBusinessMutation.addNote(customer: customer, content: "User typed a new note", correctsNoteID: nil).request(requestID: "new-note-contract")
        guard case .json(let fields) = new.body else { return XCTFail() }
        XCTAssertEqual(new.path, "api/merchant/crm/customers/61001/notes")
        XCTAssertEqual(new.query, [:])
        XCTAssertEqual(fields["correctsNoteId"], .null)
        XCTAssertEqual(fields["content"], .string("User typed a new note"))
        XCTAssertEqual(fields["requestId"], .string("new-note-contract"))
    }
    func testCorrectionAndNewNoteKeepSamePermissionsAndJournalTarget() throws {
        let customer = try MerchantCustomerID(61001)
        let correction = MerchantBusinessMutation.addNote(customer: customer, content: "Correction", correctsNoteID: 901)
        let new = MerchantBusinessMutation.addNote(customer: customer, content: "New", correctsNoteID: nil)
        XCTAssertEqual(correction.permissions, new.permissions)
        XCTAssertEqual(correction.permissions, ["merchant:crm:read", "merchant:crm:segment"])
        XCTAssertEqual(correction.targetKey, new.targetKey)
        let scope = MerchantBusinessScope(realm: "synthetic", accountID: 7, epoch: 1)
        let pending = MerchantBusinessIntent(scope: scope, merchantID: 31, target: correction.targetKey, requestID: "pending-correction")
        let proposed = MerchantBusinessIntent(scope: scope, merchantID: 31, target: new.targetKey, requestID: "proposed-new")
        XCTAssertTrue(pending.sameTarget(as: proposed))
    }
    func testInvalidCorrectionIDsRemainRejected() throws {
        for id in [0, -1] {
            let value = MerchantBusinessMutation.addNote(customer: try .init(61001), content: "Correction", correctsNoteID: id)
            XCTAssertThrowsError(try value.request(requestID: "validation-only"))
        }
    }
}
