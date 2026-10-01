import Foundation
import XCTest
@testable import QuestifyCore

final class RegistrationUIFormTests: XCTestCase {
    func testSourceContactValidationAndTrimming() {
        XCTAssertEqual(RegistrationUIFormDraft().validation, .nameRequired)
        XCTAssertEqual(RegistrationUIFormDraft(realName: "Fixture").validation, .phoneRequired)
        for phone in ["138****1234", "+8613800000000", "２３４５６７８９０１２", "23800000000", "1380000000", "138000000000"] {
            XCTAssertEqual(RegistrationUIFormDraft(realName: "Fixture", phone: phone).validation, .invalidPhone)
        }
        let draft = RegistrationUIFormDraft(realName: " Fixture Guest \n", phone: " 13800000000 ")
        XCTAssertNil(draft.validation)
        XCTAssertEqual(draft.participantDetails.realName, "Fixture Guest")
        XCTAssertEqual(draft.participantDetails.phone, "13800000000")
        XCTAssertNil(draft.participantDetails.email)
        XCTAssertNil(draft.participantDetails.participateDate)
        XCTAssertTrue(draft.participantDetails.usesAppPaymentChannel)
    }
    func testMissingMoneyAndCurrencyStayUnknownWhileYuanDeductionsKeepCNY() {
        XCTAssertNil(RegistrationUIMoney.display(nil, locale: Locale(identifier: "en_US")))
        XCTAssertNil(RegistrationUIMoney.display(-1, locale: Locale(identifier: "en_US")))
        XCTAssertEqual(RegistrationUIMoney.yuanCurrencyCode, "CNY")
        XCTAssertEqual(RegistrationUIMoney.display(.zero, locale: Locale(identifier: "en_US")), "0.00")
        let en = RegistrationUIMoney.display(.zero, locale: Locale(identifier: "en_US"), currencyCode: RegistrationUIMoney.yuanCurrencyCode)
        XCTAssertNotNil(en)
        XCTAssertTrue(en?.contains("0.00") == true)
        XCTAssertTrue(en?.contains("CN") == true || en?.contains("CNY") == true || en?.contains("¥") == true)
        let zh = RegistrationUIMoney.display(12.5, locale: Locale(identifier: "zh_Hans_CN"), currencyCode: RegistrationUIMoney.yuanCurrencyCode)
        XCTAssertTrue(zh?.contains("12.50") == true)
    }
    func testOnlyVerifiedRegistrationLabelsAndCreationDisabledByDefault() {
        XCTAssertFalse(RegistrationUICreationPolicy.disabled.permitsCreation)
        XCTAssertEqual(RegistrationUIStatus.registrationKey(1), "registration.form.awaitingPayment")
        XCTAssertEqual(RegistrationUIStatus.registrationKey(2), "registration.form.registered")
        XCTAssertEqual(RegistrationUIStatus.registrationKey(3), "registration.form.cancelled")
        XCTAssertEqual(RegistrationUIStatus.registrationKey(4), "registration.form.expired")
        XCTAssertEqual(RegistrationUIStatus.registrationKey(nil), "registration.form.unknownStatus")
        XCTAssertEqual(RegistrationUIStatus.registrationKey(99), "registration.form.unknownStatus")
    }
}
