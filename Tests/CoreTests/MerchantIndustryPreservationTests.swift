import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MerchantIndustryPreservationTests: XCTestCase {
    private func decor(_ fields: [String: Any]) throws -> MerchantStoreDecor {
        try JSONDecoder().decode(MerchantStoreDecor.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func catalog() throws -> [MerchantStoreIndustry] {
        try JSONDecoder().decode(MerchantStoreIndustryCatalog.self, from: JSONSerialization.data(withJSONObject:
            (1...6).map { ["id": $0, "categoryName": "Category \($0)", "type": 1] as [String: Any] })).rows
    }
    func testUnrelatedEditOmitsBothIndustryFields() throws {
        var value = try decor(["categoryId": 1, "categoryIds": "1,2,3", "slogan": "Before"])
        value.slogan = "After"
        let fields = try value.fields()
        XCTAssertNil(fields["categoryId"]); XCTAssertNil(fields["categoryIds"])
        XCTAssertEqual(value.selectedCategoryIDs, [1,2,3]); XCTAssertEqual(fields["slogan"] as? String, "After")
    }
    func testExplicitReplacementPreservesOrderAndDoesNotSendPrimary() throws {
        var value = try decor(["categoryId": 1, "categoryIds": "1,2,3"])
        try value.selectIndustries([3,1], catalog: catalog())
        XCTAssertEqual(try value.fields()["categoryIds"] as? String, "3,1")
        XCTAssertNil(try value.fields()["categoryId"])
        XCTAssertEqual(value.selectedCategoryIDs, [3,1])
    }
    func testReturningToOriginalSelectionRemovesReplacement() throws {
        var value = try decor(["categoryId": 1, "categoryIds": "1,2"])
        try value.selectIndustries([2,1], catalog: catalog())
        try value.selectIndustries([1,2], catalog: catalog())
        XCTAssertNil(value.categoryIDsReplacement); XCTAssertNil(try value.fields()["categoryIds"])
    }
    func testLegacyZeroAndMissingAreNotIndustryZero() throws {
        let cases: [[String: Any]] = [[:], ["categoryId": 0]]
        for fields in cases {
            let value = try decor(fields)
            XCTAssertEqual(value.selectedCategoryIDs, []); XCTAssertFalse(value.categorySourceUnavailable)
            XCTAssertNil(try value.fields()["categoryId"])
        }
    }
    func testUnknownSourceCannotBeNormalizedBySelection() throws {
        let cases: [[String: Any]] = [["categoryId": -1], ["categoryId": Int64(Int32.max) + 1], ["categoryIds": "1,broken"]]
        for fields in cases {
            var value = try decor(fields)
            XCTAssertTrue(value.categorySourceUnavailable)
            XCTAssertThrowsError(try value.selectIndustries([1], catalog: catalog()))
            XCTAssertNil(try value.fields()["categoryId"]); XCTAssertNil(try value.fields()["categoryIds"])
        }
    }
    func testInvalidExplicitSelectionsReject() throws {
        for ids in [[], [1,1], [7], [1,2,3,4,5,6]] {
            var value = try decor(["categoryIds": "1,2"])
            XCTAssertThrowsError(try value.selectIndustries(ids, catalog: catalog()))
            XCTAssertNil(value.categoryIDsReplacement)
        }
    }
    func testIndustryChangeDoesNotChangeOtherWireFields() throws {
        let before = try decor(["categoryId": 1, "categoryIds": "1,2", "slogan": "Original", "featuredType": 1, "featuredId": 17, "gallery": ["a", "b"], "tags": ["t"]])
        var after = before; try after.selectIndustries([2,3], catalog: catalog())
        var changed = try after.fields(); changed.removeValue(forKey: "categoryIds")
        let baseline = try before.fields()
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys]),
                       try JSONSerialization.data(withJSONObject: baseline, options: [.sortedKeys]))
    }
}

private final class IndustryPreservationTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response = ""
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), 200)
    }
}
@MainActor final class MerchantIndustryInfoReadTests: XCTestCase {
    private func access(_ permission: Bool = true) throws -> MerchantOperationsAccess {
        let fields: [String: Any] = ["active": true, "merchant": ["id": 31], "roleCode": "MERCHANT_OWNER",
            "permissions": permission ? ["merchant:profile:write"] : []]
        return try JSONDecoder().decode(MerchantOperationsAccess.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func service(_ transport: IndustryPreservationTransport) throws -> MerchantOperationsService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/prod-api")!), transport: transport)
    }
    func testDecorReadsOriginalInfoWithoutCooperationPermission() async throws {
        let transport = IndustryPreservationTransport()
        transport.response = #"{"code":200,"data":{"id":31,"categoryId":1,"categoryIds":"1,2","name":"Synthetic"}}"#
        let result = try await service(transport).document(.decor, access: access(), token: "synthetic")
        guard case .draft(.decor(let value)) = result else { return XCTFail("Wrong projection") }
        XCTAssertEqual(value.selectedCategoryIDs, [1,2])
        XCTAssertEqual(transport.requests.last?.url?.path, "/prod-api/api/merchant/info")
    }
    func testWrongMerchantInfoRejects() async throws {
        let transport = IndustryPreservationTransport()
        transport.response = #"{"code":200,"data":{"id":32,"name":"Synthetic","categoryIds":"1,2"}}"#
        do { _ = try await service(transport).document(.decor, access: access(), token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testMissingOriginalPermissionMakesNoRead() async throws {
        let transport = IndustryPreservationTransport()
        do { _ = try await service(transport).document(.decor, access: access(false), token: "synthetic"); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
