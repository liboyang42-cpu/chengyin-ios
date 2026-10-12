import XCTest
@testable import QuestifyCore

final class TemplateAuthoringIntroExamplesTests: XCTestCase {
    private func home(_ value: [String:Any]) throws -> DiscoveryTemplateHome {
        try JSONDecoder().decode(DiscoveryTemplateHome.self,from:JSONSerialization.data(withJSONObject:value))
    }
    private func rows(_ ids: [Int]) -> [[String:Any]] { ids.map { ["id":$0,"title":"Real \($0)","imgUrl":"https://example.invalid/\($0).jpg"] } }
    func testRecommendedPrecedesHotAndLatestWithoutMixing() throws {
        let examples = TemplateAuthoringIntroExamples(home:try home(["recommendList":rows([5]),"hotList":rows([8,9]),"latestList":rows([10])]))
        XCTAssertEqual(examples.pool,.recommended); XCTAssertEqual(examples.rows.map(\.id),[5])
    }
    func testEmptyRecommendedFallsBackToHotThenLatest() throws {
        let hot = TemplateAuthoringIntroExamples(home:try home(["recommendList":[],"hotList":rows([8]),"latestList":rows([10])]))
        XCTAssertEqual(hot.pool,.hot); XCTAssertEqual(hot.rows.map(\.id),[8])
        let latest = TemplateAuthoringIntroExamples(home:try home(["latestList":rows([10])]))
        XCTAssertEqual(latest.pool,.latest); XCTAssertEqual(latest.rows.map(\.id),[10])
    }
    func testPrefixThreeRetainsServerOrderAndDuplicateIDs() throws {
        let examples = TemplateAuthoringIntroExamples(home:try home(["recommendList":rows([8,8,2,9])]))
        XCTAssertEqual(examples.rows.map(\.id),[8,8,2]); XCTAssertEqual(TemplateAuthoringIntroExamples.maximum,3)
    }
    func testEmptyTitlesDoNotDiscardRowsOrFallThroughToAnotherPool() throws {
        let examples = TemplateAuthoringIntroExamples(home:try home(["recommendList":[["id":3,"title":""]],"hotList":rows([8])]))
        XCTAssertEqual(examples.pool,.recommended); XCTAssertEqual(examples.rows.map(\.id),[3]); XCTAssertEqual(examples.rows.first?.title,"")
    }
    func testAllEmptyHasNoInventedExample() throws {
        let examples = TemplateAuthoringIntroExamples(home:try home([:]))
        XCTAssertEqual(examples.pool,.latest); XCTAssertTrue(examples.rows.isEmpty)
    }
    func testBannerAndMustPlayNeverReplaceSourcePools() throws {
        let examples = TemplateAuthoringIntroExamples(home:try home(["bannerList":rows([1]),"mustPlayList":rows([2])]))
        XCTAssertTrue(examples.rows.isEmpty)
    }
    func testAvailableDTOImageTitleAndOtherFieldsRemainExact() throws {
        let source = try home(["recommendList":[["id":36,"title":"真人示例","imgUrl":"https://example.invalid/图.jpg?a=1","description":"Keep","packType":2]]])
        let examples = TemplateAuthoringIntroExamples(home:source)
        XCTAssertEqual(examples.rows,source.recommended); XCTAssertEqual(examples.rows[0].imgUrl,"https://example.invalid/图.jpg?a=1")
    }
    func testMissingNameAndCategoryFieldsAreNotGuessedFromOtherData() throws {
        let source = try home(["recommendList":[["id":36,"name":"Unsupported name","sysCategoryList":[["categoryName":"Not exposed"]]]]])
        let examples = TemplateAuthoringIntroExamples(home:source)
        XCTAssertEqual(examples.rows[0].title,""); XCTAssertNil(examples.rows[0].categoryId)
    }
    func testMalformedExistingTypedHomeContractFailsInsteadOfCreatingSamples() throws {
        let bodies: [[String:Any]] = [["recommendList":"bad"],["hotList":[true]],["latestList":[["id":0]]]]
        for body in bodies {
            XCTAssertThrowsError(try home(body))
        }
    }
}
