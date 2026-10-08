import XCTest
@testable import QuestifyCore

final class MerchantOperatorRolePresentationTests: XCTestCase {
    private func role(_ codes: [String], name: String = "Server role", roleCode: String = "MERCHANT_MANAGER") throws -> MerchantBusinessRecord {
        try .init(kind: .role, fields: ["roleCode": .string(roleCode), "name": .string(name),
                                      "permissions": .array(codes.map { .string($0) })])
    }

    func testAllTwentyExactSourceCodesHaveDistinctDescriptions() throws {
        let codes = MerchantOperatorPermissionDescription.allCases.map(\.rawValue)
        let presentation = try MerchantOperatorRolePresentation(record: role(codes))
        XCTAssertEqual(codes.count, 20)
        XCTAssertEqual(Set(codes).count, 20)
        XCTAssertEqual(presentation.entries.map(\.code), codes)
        XCTAssertTrue(presentation.entries.allSatisfy { $0.description != nil })
        XCTAssertEqual(Set(presentation.entries.map(\.titleKey)).count, 20)
        XCTAssertEqual(Set(presentation.entries.map(\.detailKey)).count, 20)
    }

    func testDescriptionsMatchOnlyExactCodes() throws {
        let codes = ["merchant:*", "*", "merchant:crm:*", "merchant:finance:read ",
                     " merchant:verify", "MERCHANT:VERIFY", "merchant:unknown:write", ""]
        let presentation = try MerchantOperatorRolePresentation(record: role(codes))
        XCTAssertEqual(presentation.entries.map(\.code), codes)
        XCTAssertTrue(presentation.entries.allSatisfy { $0.description == nil })
        XCTAssertEqual(Set(presentation.entries.map(\.titleKey)), ["merchant.operatorRole.unknown.title"])
        XCTAssertEqual(Set(presentation.entries.map(\.detailKey)), ["merchant.operatorRole.unknown.detail"])
    }

    func testDuplicatesCollapseOnlyForPresentationAndKeepServerOrder() throws {
        let codes = ["merchant:verify", "future:grant", "merchant:verify", "merchant:finance:read", "future:grant"]
        let record = try role(codes)
        let presentation = try MerchantOperatorRolePresentation(record: record)
        XCTAssertEqual(presentation.entries.map(\.id), ["merchant:verify", "future:grant", "merchant:finance:read"])
        XCTAssertEqual(try record.fields.mbStrings("permissions"), codes)
    }

    func testEmptyManagerRoleDoesNotInferPresetPermissions() throws {
        let presentation = try MerchantOperatorRolePresentation(record: role([]))
        XCTAssertEqual(presentation.roleCode, "MERCHANT_MANAGER")
        XCTAssertTrue(presentation.entries.isEmpty)
    }

    func testRoleNameDoesNotGrantPermissions() throws {
        let presentation = try MerchantOperatorRolePresentation(record: role(["merchant:basic:read"], name: "Owner / all permissions"))
        XCTAssertEqual(presentation.entries.map(\.description), [.basicRead])
        XCTAssertEqual(presentation.roleCode, "MERCHANT_MANAGER")
    }

    func testRoleChangeUsesTheNewServerSuppliedList() throws {
        let first = try MerchantOperatorRolePresentation(record: role(["merchant:crm:read"], roleCode: "MERCHANT_MANAGER"))
        let second = try MerchantOperatorRolePresentation(record: role(["merchant:verify"], roleCode: "MERCHANT_CHECKIN"))
        XCTAssertEqual(first.entries.map(\.description), [.customerRead])
        XCTAssertEqual(second.entries.map(\.description), [.verify])
        XCTAssertNotEqual(first.roleCode, second.roleCode)
    }

    func testSameRoleRefreshDoesNotCacheOldPermissions() throws {
        let first = try MerchantOperatorRolePresentation(record: role(["merchant:finance:read"]))
        let refreshed = try MerchantOperatorRolePresentation(record: role([]))
        XCTAssertEqual(first.roleCode, refreshed.roleCode)
        XCTAssertTrue(refreshed.entries.isEmpty)
    }

    func testVerificationFinanceAndCustomerSensitivityStayDistinct() throws {
        let presentation = try MerchantOperatorRolePresentation(record: role([
            "merchant:verify", "merchant:verify:record:read", "merchant:finance:read",
            "merchant:crm:read", "merchant:crm:sensitive:read"]))
        XCTAssertEqual(presentation.entries.map(\.description), [.verify, .verificationRead, .financeRead, .customerRead, .customerSensitiveRead])
        XCTAssertEqual(Set(presentation.entries.map(\.detailKey)).count, 5)
    }

    func testAftercareReadOpinionResponseAndEvidenceStayDistinct() throws {
        let presentation = try MerchantOperatorRolePresentation(record: role([
            "merchant:aftercare:read", "merchant:aftercare:respond", "merchant:aftercare:decide", "merchant:aftercare:evidence"]))
        XCTAssertEqual(presentation.entries.map(\.description), [.aftercareRead, .aftercareRespond, .aftercareDecide, .aftercareEvidence])
    }

    func testNonRoleRecordCannotBecomePermissionPresentation() throws {
        let document = try MerchantBusinessDocument(query: .operators, payload: MerchantBusinessSyntheticFixtures.payload(.operators))
        for record in document.rows {
            XCTAssertThrowsError(try MerchantOperatorRolePresentation(record: record))
        }
    }

    func testMalformedPermissionValuesFailAtExistingRecordBoundary() throws {
        for malformed in [MerchantBusinessValue.null, .string("merchant:verify"), .array([.int(1)])] {
            XCTAssertThrowsError(try MerchantBusinessRecord(kind: .role, fields: ["roleCode": .string("MERCHANT_CHECKIN"), "permissions": malformed]))
        }
    }

    func testSourceDocumentAndMutationRequestRemainUnchanged() throws {
        let document = try MerchantBusinessDocument(query: .roles, payload: MerchantBusinessSyntheticFixtures.payload(.roles))
        let before = document
        for record in document.rows { _ = try MerchantOperatorRolePresentation(record: record) }
        XCTAssertEqual(document, before)
        let mutation = MerchantBusinessMutation.inviteOperator(role: "MERCHANT_CHECKIN")
        let request = try mutation.request(requestID: "permission-presentation-test")
        XCTAssertEqual(request.path, "api/merchant/operators/invite")
        XCTAssertEqual(request.body, .json(["roleCode": .string("MERCHANT_CHECKIN"), "requestId": .string("permission-presentation-test")]))
    }
}
