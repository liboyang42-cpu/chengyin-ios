import XCTest
@testable import QuestifyCore

final class ImageAndVideoDiskCacheBudgetAuditTests: XCTestCase {

    func testCanonicalCachePoolsPassBudgetAndEvictionAudit() {
        let policies = ImageAndVideoDiskCacheBudgetAudit.canonicalPolicies
        XCTAssertEqual(policies.count, 3)
        XCTAssertEqual(
            policies.map(\.id),
            [
                "square-post-media-cache",
                "roam-map-tile-and-poi-cache",
                "avatar-and-stamp-asset-cache"
            ]
        )
        XCTAssertTrue(policies.allSatisfy(\.isCompliant))

        let result = ImageAndVideoDiskCacheBudgetAudit.evaluate()
        XCTAssertEqual(result.totalPools, 3)
        XCTAssertEqual(result.compliantPools, 3)
        XCTAssertTrue(result.isCacheBudgetReady)
    }

    func testMemoryLimitAbove150MBOrNonPositiveIsRejected() {
        var policies = ImageAndVideoDiskCacheBudgetAudit.canonicalPolicies
        policies[0] = MediaCacheBudgetPolicy(
            id: "square-post-media-cache",
            memoryLimitMB: 151,
            diskLimitMB: 250,
            purgesOnMemoryWarning: true,
            evictsDeletedOr404MediaImmediately: true
        )
        XCTAssertFalse(policies[0].isCompliant)

        let zeroMemory = MediaCacheBudgetPolicy(
            id: "zero-mem-cache",
            memoryLimitMB: 0,
            diskLimitMB: 100
        )
        XCTAssertFalse(zeroMemory.isCompliant)

        let result = ImageAndVideoDiskCacheBudgetAudit.evaluate(policies: policies)
        XCTAssertEqual(result.totalPools, 3)
        XCTAssertEqual(result.compliantPools, 2)
        XCTAssertFalse(result.isCacheBudgetReady)
    }

    func testDiskLimitAbove500MBOrNonPositiveIsRejected() {
        var policies = ImageAndVideoDiskCacheBudgetAudit.canonicalPolicies
        policies[1] = MediaCacheBudgetPolicy(
            id: "roam-map-tile-and-poi-cache",
            memoryLimitMB: 48,
            diskLimitMB: 501,
            purgesOnMemoryWarning: true,
            evictsDeletedOr404MediaImmediately: true
        )
        XCTAssertFalse(policies[1].isCompliant)

        let zeroDisk = MediaCacheBudgetPolicy(
            id: "zero-disk-cache",
            memoryLimitMB: 32,
            diskLimitMB: 0
        )
        XCTAssertFalse(zeroDisk.isCompliant)

        let result = ImageAndVideoDiskCacheBudgetAudit.evaluate(policies: policies)
        XCTAssertEqual(result.totalPools, 3)
        XCTAssertEqual(result.compliantPools, 2)
        XCTAssertFalse(result.isCacheBudgetReady)
    }

    func testMissingMemoryWarningPurgeOrMissing404EvictionIsRejected() {
        let missingMemoryPurge = MediaCacheBudgetPolicy(
            id: "square-post-media-cache",
            memoryLimitMB: 64,
            diskLimitMB: 250,
            purgesOnMemoryWarning: false,
            evictsDeletedOr404MediaImmediately: true
        )
        XCTAssertFalse(missingMemoryPurge.isCompliant)

        let missing404Eviction = MediaCacheBudgetPolicy(
            id: "square-post-media-cache",
            memoryLimitMB: 64,
            diskLimitMB: 250,
            purgesOnMemoryWarning: true,
            evictsDeletedOr404MediaImmediately: false
        )
        XCTAssertFalse(missing404Eviction.isCompliant)

        let result = ImageAndVideoDiskCacheBudgetAudit.evaluate(policies: [missingMemoryPurge, missing404Eviction])
        XCTAssertEqual(result.totalPools, 2)
        XCTAssertEqual(result.compliantPools, 0)
        XCTAssertFalse(result.isCacheBudgetReady)
    }
}
