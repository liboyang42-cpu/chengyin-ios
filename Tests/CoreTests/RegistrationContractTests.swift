import Foundation
import XCTest
@testable import QuestifyCore

final class RegistrationContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func body<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func quote(_ json: String = #"{"payAmount":19.99,"quoteSign":"fixture-quote-not-valid"}"#) throws -> RegistrationQuote {
        try decode(RegistrationQuote.self, json)
    }

    private func intent(requestID: String = "fixture-intent", quoteJSON: String? = nil,
                        offer: RegistrationWaitlistOffer? = nil,
                        appPay: Bool = true) throws -> RegistrationCreateIntent {
        let selection = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11, usePoints: true)
        let result = try quoteJSON.map { try quote($0) } ?? quote()
        return try RegistrationCreateIntent(selection: selection, quote: result,
                                            realName: "Test Participant", phone: "fixture-phone",
                                            usesAppPaymentChannel: appPay, requestID: requestID,
                                            waitlistOffer: offer)
    }

    func testQuoteRequestUsesSourceJSONKeysAndFixedOwnerType() throws {
        let request = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11, usePoints: true)
        let json = try body(request)
        XCTAssertEqual(json["ownerType"] as? Int, 2)
        XCTAssertEqual(json["ownerId"] as? Int, 7)
        XCTAssertEqual(json["ticketId"] as? Int, 11)
        XCTAssertEqual(json["isUsePoint"] as? Int, 1)
        XCTAssertEqual(Set(json.keys), Set(["ownerType", "ownerId", "ticketId", "isUsePoint"]))
    }

    func testQuoteRequestOmitsUnselectedTicketAndDefaultsPointsOff() throws {
        let json = try body(RegistrationQuoteRequest(ownerID: 7))
        XCTAssertNil(json["ticketId"])
        XCTAssertEqual(json["isUsePoint"] as? Int, 0)
    }

    func testInvalidSelectionIDsAreRejected() {
        XCTAssertThrowsError(try RegistrationQuoteRequest(ownerID: 0))
        XCTAssertThrowsError(try RegistrationQuoteRequest(ownerID: 1, ticketID: -1))
    }

    func testMissingAndNullAmountsRemainUnknown() throws {
        for json in [#"{}"#, #"{"payAmount":null,"pointsDeductYuan":null,"memberDiscountYuan":null,"couponDeductYuan":null}"#] {
            let value = try quote(json)
            XCTAssertNil(value.payAmount)
            XCTAssertNil(value.pointsDeductYuan)
            XCTAssertNil(value.memberDiscountYuan)
            XCTAssertNil(value.couponDeductYuan)
            XCTAssertFalse(value.isUsableForCreate)
            XCTAssertFalse(value.hasPointsDeduction)
        }
    }

    func testQuoteUsesDecimalForEveryAmountWithoutRoundingToMinorUnits() throws {
        let value = try quote(#"{"payAmount":19.99,"pointsDeductYuan":0.01,"memberDiscountYuan":2.125,"couponDeductYuan":0,"quoteSign":"fixture-quote-not-valid"}"#)
        XCTAssertEqual(value.payAmount, Decimal(string: "19.99"))
        XCTAssertEqual(value.pointsDeductYuan, Decimal(string: "0.01"))
        XCTAssertEqual(value.memberDiscountYuan, Decimal(string: "2.125"))
        XCTAssertEqual(value.couponDeductYuan, Decimal.zero)
        XCTAssertTrue(value.hasPointsDeduction)
        XCTAssertTrue(value.isUsableForCreate)
    }

    func testQuoteSourceDefaultsAndExplicitBooleans() throws {
        let defaults = try quote(#"{}"#)
        XCTAssertEqual(defaults.pointsUsed, 0)
        XCTAssertTrue(defaults.pointsUsable)
        XCTAssertFalse(defaults.clubMember)
        XCTAssertEqual(defaults.quoteSign, "")
        let explicit = try quote(#"{"pointsUsable":false,"clubMember":true,"pointsUsed":5}"#)
        XCTAssertFalse(explicit.pointsUsable)
        XCTAssertTrue(explicit.clubMember)
        XCTAssertEqual(explicit.pointsUsed, 5)
    }

    func testPointsCountAloneDoesNotImplyMonetaryDeduction() throws {
        for json in [#"{"pointsUsed":5}"#, #"{"pointsUsed":5,"pointsDeductYuan":0}"#] {
            XCTAssertFalse(try quote(json).hasPointsDeduction)
        }
    }

    func testUnknownAmountOrBlankSignatureCannotCreateIntent() {
        for json in [#"{"quoteSign":"fixture-quote-not-valid"}"#,
                     #"{"payAmount":0}"#, #"{"payAmount":0,"quoteSign":"  \n "}"#] {
            XCTAssertThrowsError(try intent(quoteJSON: json))
        }
    }

    func testKnownZeroCanCreateAndSignatureIsCopiedUnchanged() throws {
        let value = try intent(quoteJSON: #"{"payAmount":0,"quoteSign":" fixture-quote-not-valid "}"#)
        let json = try body(value)
        XCTAssertEqual(json["quoteSign"] as? String, " fixture-quote-not-valid ")
        XCTAssertEqual(json["ownerType"] as? Int, 2)
        XCTAssertEqual(json["ownerId"] as? Int, 7)
        XCTAssertEqual(json["ticketId"] as? Int, 11)
        XCTAssertEqual(json["isUsePoint"] as? Int, 1)
        XCTAssertEqual(json["realName"] as? String, "Test Participant")
        XCTAssertEqual(json["phone"] as? String, "fixture-phone")
    }

    func testSameIntentRetainsIdenticalRequestIDAndPayloadAcrossRetries() throws {
        let value = try intent()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let firstAttempt = try encoder.encode(value)
        let retryCopy = value
        XCTAssertEqual(try encoder.encode(retryCopy), firstAttempt)
        XCTAssertEqual(try body(retryCopy)["requestId"] as? String, "fixture-intent")
    }

    func testRequestIDGeneratedOncePerNewIntent() throws {
        let selection = try RegistrationQuoteRequest(ownerID: 7)
        let first = try RegistrationCreateIntent(selection: selection, quote: quote(), realName: "Fixture", phone: "fixture-phone")
        let second = try RegistrationCreateIntent(selection: selection, quote: quote(), realName: "Fixture", phone: "fixture-phone")
        XCTAssertFalse(first.requestID.isEmpty)
        XCTAssertLessThanOrEqual(first.requestID.utf16.count, 64)
        XCTAssertNotEqual(first.requestID, second.requestID)
        XCTAssertEqual(try body(first)["requestId"] as? String, first.requestID)
        XCTAssertEqual(try body(first)["requestId"] as? String, first.requestID)
    }

    func testInvalidRequestIDAndBlankParticipantFieldsAreRejected() throws {
        for id in ["", " \n ", String(repeating: "x", count: 65)] {
            XCTAssertThrowsError(try intent(requestID: id))
        }
        XCTAssertNoThrow(try intent(requestID: String(repeating: "x", count: 64)))
        let selection = try RegistrationQuoteRequest(ownerID: 7)
        XCTAssertThrowsError(try RegistrationCreateIntent(selection: selection, quote: quote(), realName: " ", phone: "fixture-phone"))
        XCTAssertThrowsError(try RegistrationCreateIntent(selection: selection, quote: quote(), realName: "Fixture", phone: "\n"))
    }

    func testWaitlistOfferFieldsAreEncodedTogetherOrBothOmitted() throws {
        let offer = try RegistrationWaitlistOffer(id: 19, token: " fixture-offer-not-valid ")
        let offered = try body(intent(offer: offer))
        XCTAssertEqual(offered["waitlistOfferId"] as? Int, 19)
        XCTAssertEqual(offered["waitlistOfferToken"] as? String, " fixture-offer-not-valid ")
        let ordinary = try body(intent())
        XCTAssertNil(ordinary["waitlistOfferId"])
        XCTAssertNil(ordinary["waitlistOfferToken"])
        XCTAssertThrowsError(try RegistrationWaitlistOffer(id: 0, token: "fixture-offer-not-valid"))
        XCTAssertThrowsError(try RegistrationWaitlistOffer(id: 19, token: ""))
        XCTAssertThrowsError(try RegistrationWaitlistOffer(id: 19, token: " \n "))
    }

    func testAppChannelMatchesSourceAndCanBeOmitted() throws {
        XCTAssertEqual(try body(intent())["payChannel"] as? String, "APP")
        XCTAssertNil(try body(intent(appPay: false))["payChannel"])
    }

    func testEmptyOptionalFieldsOmittedAndNonemptyValuesPreserved() throws {
        let selection = try RegistrationQuoteRequest(ownerID: 7)
        let empty = try RegistrationCreateIntent(selection: selection, quote: quote(), realName: "Fixture", phone: "fixture-phone", email: "", participateDate: "")
        let absent = try body(empty)
        XCTAssertNil(absent["email"])
        XCTAssertNil(absent["participateDate"])
        XCTAssertNil(absent["ticketId"])
        XCTAssertEqual(absent["isUsePoint"] as? Int, 0)
        let supplied = try RegistrationCreateIntent(selection: selection, quote: quote(), realName: "Fixture", phone: "fixture-phone", email: "fixture@example.invalid", participateDate: "2026-10-01")
        let json = try body(supplied)
        XCTAssertEqual(json["email"] as? String, "fixture@example.invalid")
        XCTAssertEqual(json["participateDate"] as? String, "2026-10-01")
    }

    func testCreateResultDistinguishesMissingNullAndExplicitZeroAmounts() throws {
        for json in [#"{"registrationId":1}"#, #"{"registrationId":1,"payableAmount":null}"#] {
            let value = try decode(RegistrationCreateResult.self, json)
            XCTAssertNil(value.payableAmount)
            XCTAssertFalse(value.hasPaymentParameters)
        }
        let zero = try decode(RegistrationCreateResult.self, #"{"registrationId":1,"payableAmount":0}"#)
        XCTAssertEqual(zero.payableAmount, Decimal.zero)
        XCTAssertFalse(zero.hasPaymentParameters)
    }

    func testCreateResultAcceptsSourceNumericStringAmount() throws {
        for amount in ["19.99", #""19.99""#, #""1.999e1""#] {
            let value = try decode(RegistrationCreateResult.self, "{\"registrationId\":1,\"payableAmount\":\(amount)}")
            XCTAssertEqual(value.payableAmount, Decimal(string: "19.99"))
        }
    }

    func testPositiveAmountWithoutParametersRemainsRepresentableForReplay() throws {
        for suffix in ["", #", "payParams":null"#, #", "payParams":{}"#] {
            let json = "{\"registrationId\":1,\"payableAmount\":49.25\(suffix)}"
            let value = try decode(RegistrationCreateResult.self, json)
            XCTAssertEqual(value.payableAmount, Decimal(string: "49.25"))
            XCTAssertNil(value.payParams)
            XCTAssertFalse(value.hasPaymentParameters)
        }
    }

    func testIncompletePaymentParametersPreserveScalarsWithoutClaimingCompletion() throws {
        let value = try decode(RegistrationCreateResult.self, #"{"registrationId":1,"registrationNo":"fixture-order","payParams":{"timeStamp":123,"packageValue":"fixture-package","extra":null,"flag":true}}"#)
        XCTAssertTrue(value.hasPaymentParameters)
        XCTAssertEqual(value.registrationNo, "fixture-order")
        XCTAssertEqual(value.payParams, ["timeStamp": "123", "packageValue": "fixture-package", "extra": "", "flag": "true"])
        XCTAssertNil(value.payableAmount)
    }

    func testMalformedCreateIdentityAndParametersAreRejected() {
        for json in [#"{}"#, #"{"registrationId":0}"#, #"{"registrationId":-1}"#,
                     #"{"registrationId":"1"}"#, #"{"registrationId":1,"payParams":[]}"#,
                     #"{"registrationId":1,"payParams":{"nested":{}}}"#] {
            XCTAssertThrowsError(try decode(RegistrationCreateResult.self, json))
        }
    }

    func testMalformedMonetaryValuesDoNotBecomeZero() {
        for amount in ["-1", "true", #""invalid""#, #""19.99USD""#, #""NaN""#, #""""#] {
            XCTAssertThrowsError(try decode(RegistrationCreateResult.self, "{\"registrationId\":1,\"payableAmount\":\(amount)}"))
        }
        XCTAssertThrowsError(try quote(#"{"payAmount":-1}"#))
        XCTAssertThrowsError(try quote(#"{"payAmount":"19.99"}"#))
        XCTAssertThrowsError(try quote(#"{"pointsDeductYuan":-1}"#))
        XCTAssertThrowsError(try quote(#"{"pointsUsed":-1}"#))
    }

    func testQuoteAndCreateAmountKeysAreNotInterchangeable() throws {
        XCTAssertNil(try quote(#"{"payableAmount":0}"#).payAmount)
        XCTAssertNil(try decode(RegistrationCreateResult.self, #"{"registrationId":1,"payAmount":0}"#).payableAmount)
    }

    func testBothSourceSuccessEnvelopesDecode() throws {
        let quotation = try decode(RegistrationQuoteResponse.self, #"{"code":200,"data":{"payAmount":19.99,"quoteSign":"fixture-quote-not-valid"}}"#)
        XCTAssertTrue(quotation.data.isUsableForCreate)
        let creation = try decode(RegistrationCreateResponse.self, #"{"code":200,"data":{"registrationId":1,"payableAmount":0}}"#)
        XCTAssertEqual(creation.data.registrationID, 1)
    }

    func testStringBusinessCodesAndServerMessagesRemainAvailable() {
        for code in ["409", #""409""#] {
            XCTAssertThrowsError(try decode(RegistrationCreateResponse.self, "{\"code\":\(code),\"msg\":\"价格已更新\"}")) { error in
                let failure = error as? RegistrationResponseFailure
                XCTAssertEqual(failure?.code, 409)
                XCTAssertEqual(failure?.message, "价格已更新")
                XCTAssertEqual(failure?.hasServerMessage, true)
            }
        }
    }

    func testMissingServerMessageIsNotInventedAndEmptyMessageIsPreserved() {
        for (json, hasMessage) in [(#"{"code":410}"#, false), (#"{"code":410,"msg":""}"#, true)] {
            XCTAssertThrowsError(try decode(RegistrationCreateResponse.self, json)) { error in
                XCTAssertEqual((error as? RegistrationResponseFailure)?.hasServerMessage, hasMessage)
            }
        }
    }

    func testMissingSuccessDataAndStringSuccessCodeFailClosed() {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#,
                     #"{"code":200,"data":[]}"#, #"{"code":"200","data":{"registrationId":1}}"#,
                     #"{"code":200,"data":{}}"#] {
            XCTAssertThrowsError(try decode(RegistrationCreateResponse.self, json))
        }
        XCTAssertThrowsError(try decode(RegistrationQuoteResponse.self, #"{"code":200}"#))
    }
}
