import XCTest
@testable import QuestifyCore

final class TemplateTabPolicyTests: XCTestCase {
    private func access(_ json: String) throws -> MerchantMarketingAccess {
        try MerchantMarketingAccess(JSONDecoder().decode(MerchantMarketingValue.self, from: Data(json.utf8)))
    }

    func testMerchantScopeFailsClosedUntilProjectManagementIsProven() throws {
        XCTAssertFalse(TemplateTabScope.consumer.isStaffReadOnly)
        XCTAssertTrue(TemplateTabScope(merchantAccess: nil).isStaffReadOnly)
        let staff = try access(#"{"active":true,"merchant":{"id":3},"roleCode":"MERCHANT_CHECKIN","permissions":["merchant:checkin"]}"#)
        XCTAssertEqual(TemplateTabScope(merchantAccess: staff), .merchant(canManageProjects: false))
        let manager = try access(#"{"active":true,"merchant":{"id":3},"roleCode":"MERCHANT_MANAGER","permissions":["merchant:project:manage"]}"#)
        XCTAssertEqual(TemplateTabScope(merchantAccess: manager), .merchant(canManageProjects: true))
        XCTAssertFalse(TemplateTabScope(merchantAccess: manager).isStaffReadOnly)
        let inactive = try access(#"{"active":false}"#)
        XCTAssertTrue(TemplateTabScope(merchantAccess: inactive).isStaffReadOnly)
    }

    func testRefusalsFollowMiniProgramHandlerOrder() {
        let staff = TemplateTabScope.merchant(canManageProjects: false)
        XCTAssertEqual(TemplateTabPolicy.refusal(for: .viewDetail, previewOnly: true, scope: .consumer), .previewNotViewable)
        XCTAssertNil(TemplateTabPolicy.refusal(for: .viewDetail, previewOnly: false, scope: staff))
        XCTAssertEqual(TemplateTabPolicy.refusal(for: .configure, previewOnly: true, scope: staff), .staffBrowseOnly)
        XCTAssertEqual(TemplateTabPolicy.refusal(for: .configure, previewOnly: true, scope: .consumer), .previewNotConfigurable)
        XCTAssertEqual(TemplateTabPolicy.refusal(for: .verifyAndUse, previewOnly: true, scope: .consumer), .previewNotUsable)
        XCTAssertEqual(TemplateTabPolicy.refusal(for: .publish, previewOnly: false, scope: staff), .staffCannotPublish)
        XCTAssertNil(TemplateTabPolicy.refusal(for: .configure, previewOnly: false, scope: .merchant(canManageProjects: true)))
        XCTAssertEqual(TemplateTabRefusal.staffBrowseOnly.localizationKey, "discovery.templateTab.refusal.staffBrowseOnly")
    }

    func testStatusLabels() {
        XCTAssertEqual(TemplateTabPolicy.statusLabel(previewOnly: true, templateStatus: "VERIFIED"), .experimentalPreview)
        XCTAssertEqual(TemplateTabPolicy.statusLabel(previewOnly: false, templateStatus: "DRAFT"), .experimentalTemplate)
        XCTAssertNil(TemplateTabPolicy.statusLabel(previewOnly: false, templateStatus: "VERIFIED"))
        XCTAssertNil(TemplateTabPolicy.statusLabel(previewOnly: false, templateStatus: nil))
    }
}
