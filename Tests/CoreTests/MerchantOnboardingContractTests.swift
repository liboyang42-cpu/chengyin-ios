import XCTest
@testable import QuestifyCore

final class MerchantOnboardingContractTests: XCTestCase {
    func testEveryReviewAndAccountStateUsesDisabledPrecedence() throws {
        for status in 0...2 {
            for account in 0...2 {
                let application = try makeMerchantOnboardingApplication(status: status, accountStatus: account)
                XCTAssertEqual(application.canReapply, status == 2 && account != 2)
                if account == 2 {
                    XCTAssertEqual(application.statusKey, "merchant.onboarding.status.disabled")
                    XCTAssertEqual(application.displayedReason, "Platform pause")
                } else if status == 2 { XCTAssertEqual(application.displayedReason, "License unreadable") }
                else { XCTAssertNil(application.displayedReason) }
            }
        }
        XCTAssertEqual(try makeMerchantOnboardingApplication(status: 0).statusKey, "merchant.onboarding.status.pending")
        XCTAssertEqual(try makeMerchantOnboardingApplication(status: 1).statusKey, "merchant.onboarding.status.activation")
        XCTAssertEqual(try makeMerchantOnboardingApplication(status: 1, accountStatus: 1).statusKey, "merchant.onboarding.status.effective")
    }
    func testDisabledDoesNotBorrowRejectionReason() throws {
        let application = try makeMerchantOnboardingApplication(status: 2, accountStatus: 2, extras: ["disableReason": "  "])
        XCTAssertNil(application.displayedReason)
    }
    func testApplicationIntegersAreStrictAndStatusesNeverDefaultToPending() throws {
        let valid = try JSONSerialization.data(withJSONObject: ["id": "17", "status": "2", "accountStatus": "0"])
        XCTAssertEqual(try JSONDecoder().decode(MerchantOnboardingApplication.self, from: valid).id, 17)
        let invalid: [[String: Any]] = [
            ["id": 0, "status": 0, "accountStatus": 0], ["id": 1.5, "status": 0, "accountStatus": 0],
            ["id": true, "status": 0, "accountStatus": 0], ["id": 1, "accountStatus": 0],
            ["id": 1, "status": 0], ["id": 1, "status": 3, "accountStatus": 0],
            ["id": 1, "status": 0, "accountStatus": -1], ["id": 1, "status": "pending", "accountStatus": 0]
        ]
        for fields in invalid {
            let data = try JSONSerialization.data(withJSONObject: fields)
            XCTAssertThrowsError(try JSONDecoder().decode(MerchantOnboardingApplication.self, from: data))
        }
    }
    func testExactRequiredFieldsAndNoInventedPhoneOrUSIdentityValidation() throws {
        var draft = MerchantOnboardingDraft()
        XCTAssertEqual(draft.blocker(step: 1), "merchant.onboarding.required.name")
        draft.name = "Example Store"
        XCTAssertEqual(draft.blocker(step: 1), "merchant.onboarding.required.phone")
        draft.phone = "+44 example"
        XCTAssertNil(draft.blocker(step: 1)) // Source checks nonblank, not a country-specific phone regex.
        XCTAssertEqual(draft.blocker(step: 2), "merchant.onboarding.required.address")
        draft.address = "Example street"
        XCTAssertEqual(draft.blocker(step: 2), "merchant.onboarding.required.hours")
        draft.businessTime = "Stored hours"
        XCTAssertEqual(draft.blocker(step: 3), "merchant.onboarding.required.license")
        draft.license = try .init(serverURL: "https://fixtures.example/license.jpg")
        XCTAssertNil(draft.blocker())
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.jsonData()) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), Set(["name", "preference", "phone", "description", "address", "businessTime", "businessLicense", "wechat"]))
        XCTAssertNil(fields["id"]); XCTAssertNil(fields["ssn"]); XCTAssertNil(fields["ein"]); XCTAssertNil(fields["roleCode"])
    }
    func testOnlyRejectedApplicationsBackfillTheirIDAndSourceFields() throws {
        for status in [0, 1] { XCTAssertThrowsError(try MerchantOnboardingDraft(reapplying: makeMerchantOnboardingApplication(status: status))) }
        XCTAssertThrowsError(try MerchantOnboardingDraft(reapplying: makeMerchantOnboardingApplication(status: 2, accountStatus: 2)))
        var draft = try MerchantOnboardingDraft(reapplying: makeMerchantOnboardingApplication(status: 2))
        XCTAssertEqual(draft.id, 17); XCTAssertEqual(draft.wechat, "")
        draft.name = "  Updated store \n"
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.jsonData()) as? [String: Any])
        XCTAssertEqual(fields["id"] as? Int, 17); XCTAssertEqual(fields["name"] as? String, "Updated store")
        XCTAssertNil(fields["derivatives"]); XCTAssertNil(fields["latitude"])
    }
    func testLicenseOnlyAcceptsSafeServerURLs() throws {
        for value in ["", "null", "file:///tmp/license.jpg", "http://fixtures.example/a", "https://user:secret@fixtures.example/a", "data:image/jpeg;base64,AA"] {
            XCTAssertThrowsError(try MerchantOnboardingLicense(serverURL: value))
        }
        XCTAssertEqual(try MerchantOnboardingLicense(serverURL: " https://fixtures.example/a ").url, "https://fixtures.example/a")
        let draft = try MerchantOnboardingDraft(reapplying: makeMerchantOnboardingApplication(status: 2, extras: ["businessLicense": "invalid"]))
        XCTAssertNil(draft.license); XCTAssertEqual(draft.blocker(), "merchant.onboarding.required.license")
    }
    func testBusinessHoursWireFormatDoesNotChangeWithUILanguage() throws {
        var hours = MerchantOnboardingHours()
        XCTAssertEqual(try hours.wireValue(), "周一至周日 10:00-22:00")
        hours.days = [0, 2, 6]; hours.startMinutes = 9 * 60 + 5; hours.endMinutes = 2 * 60
        XCTAssertEqual(try hours.wireValue(), "周一、三、日 09:05-次日02:00") // Source requires an explicit next-day marker.
        hours.days = []; XCTAssertThrowsError(try hours.wireValue())
        hours.days = [8]; XCTAssertThrowsError(try hours.wireValue())
        hours.days = [0]; hours.startMinutes = 1440; XCTAssertThrowsError(try hours.wireValue())
    }
    func testLocalImageSafeguardsDoNotInventAnUploadURL() throws {
        XCTAssertThrowsError(try MerchantOnboardingImage(jpegData: Data()))
        XCTAssertThrowsError(try MerchantOnboardingImage(jpegData: Data("not an image".utf8)))
        XCTAssertThrowsError(try MerchantOnboardingImage(jpegData: Data(repeating: 0xff, count: MerchantOnboardingImage.maximumBytes + 1)))
        XCTAssertEqual(try MerchantOnboardingImage(jpegData: Data([0xff, 0xd8, 0xff, 0xd9])).data.count, 4)
    }
}

func makeMerchantOnboardingApplication(status: Int = 0, accountStatus: Int = 0,
                                       extras: [String: Any] = [:]) throws -> MerchantOnboardingApplication {
    var fields: [String: Any] = [
        "id": 17, "status": status, "accountStatus": accountStatus, "name": "Example Store", "phone": "2025550100",
        "address": "Example address", "businessTime": "Stored hours", "businessLicense": "https://fixtures.example/license.jpg",
        "reson": "License unreadable", "disableReason": "Platform pause", "derivatives": "not a form field"
    ]
    fields.merge(extras) { _, new in new }
    return try JSONDecoder().decode(MerchantOnboardingApplication.self, from: JSONSerialization.data(withJSONObject: fields))
}
func makeMerchantOnboardingDraft() throws -> MerchantOnboardingDraft {
    var draft = MerchantOnboardingDraft()
    draft.name = " Example Store "; draft.phone = "2025550100"; draft.address = "Example address"; draft.businessTime = "Stored hours"
    draft.license = try .init(serverURL: "https://fixtures.example/license.jpg")
    return draft
}
