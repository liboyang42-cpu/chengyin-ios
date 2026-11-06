import XCTest
@testable import QuestifyCore

final class MiniProgramVsNativeSupersetPageClassifierTests: XCTestCase {
    func testCanonicalClassificationsCoverStrictAPIAndNativeSupersetScopes() {
        let items = MiniProgramVsNativeSupersetPageClassifier.canonicalClassifications
        XCTAssertEqual(items.count, 9)
        XCTAssertTrue(items.allSatisfy(\.isCompliant))

        let result = MiniProgramVsNativeSupersetPageClassifier.evaluate()
        XCTAssertEqual(result.totalScopes, 9)
        XCTAssertEqual(result.apiCompatibleScopes, 9)
        XCTAssertEqual(result.nativeSupersetScopes, 4)
        XCTAssertTrue(result.isClassificationReady)
    }

    func testBrokenBackendAPIContractCompatibilityFailsInEitherMode() {
        var items = MiniProgramVsNativeSupersetPageClassifier.canonicalClassifications
        items[0] = ScopeAlignmentClassification(
            scopeCode: "w2-01",
            title: "Auth Bootstrap & AccountSessionGate Role Admission",
            alignmentMode: .strictAPIAndCopyAlignment,
            preservesBackendAPIContract: false,
            protectsNativeSupersetFromDowngrade: true
        )

        XCTAssertFalse(items[0].isCompliant)
        let result = MiniProgramVsNativeSupersetPageClassifier.evaluate(classifications: items)
        XCTAssertEqual(result.totalScopes, 9)
        XCTAssertEqual(result.apiCompatibleScopes, 8)
        XCTAssertFalse(result.isClassificationReady)
    }

    func testDowngradingNativeEnhancedSupersetToWebLimitsFailsClassification() {
        var items = MiniProgramVsNativeSupersetPageClassifier.canonicalClassifications
        items[7] = ScopeAlignmentClassification(
            scopeCode: "W14-W15",
            title: "Native 3D MapKit, Personal Fog & MV01..MV41 Visual Layers",
            alignmentMode: .nativeEnhancedSuperset,
            preservesBackendAPIContract: true,
            protectsNativeSupersetFromDowngrade: false
        )

        XCTAssertFalse(items[7].isCompliant)
        let result = MiniProgramVsNativeSupersetPageClassifier.evaluate(classifications: items)
        XCTAssertEqual(result.totalScopes, 9)
        XCTAssertEqual(result.apiCompatibleScopes, 9)
        XCTAssertEqual(result.nativeSupersetScopes, 3)
        XCTAssertFalse(result.isClassificationReady)
    }

    func testEmptyClassificationsAreRejected() {
        let result = MiniProgramVsNativeSupersetPageClassifier.evaluate(classifications: [])
        XCTAssertEqual(result.totalScopes, 0)
        XCTAssertEqual(result.apiCompatibleScopes, 0)
        XCTAssertEqual(result.nativeSupersetScopes, 0)
        XCTAssertFalse(result.isClassificationReady)
    }
}
