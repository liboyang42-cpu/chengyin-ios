import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif

@MainActor
final class MapVisualAndMerchantGameViewTests: XCTestCase {
    func testMapVisualLayerControlSectionViewInstantiationAndDatumBadges() throws {
        let dayTheme = MapVisualHostBridge.resolveTheme(manifestData: nil, systemIsDark: false)
        let nightTheme = MapVisualHostBridge.resolveTheme(manifestData: nil, systemIsDark: true)

        XCTAssertEqual(dayTheme.appearance, .day)
        XCTAssertEqual(nightTheme.appearance, .night)
        XCTAssertTrue(dayTheme.isCandidatePalette)
        XCTAssertTrue(dayTheme.contrastShortfalls.isEmpty)

        XCTAssertEqual(MapVisualLayerControlSectionView.datumBadgeText(for: .wgs84), "WGS-84")
        XCTAssertEqual(MapVisualLayerControlSectionView.datumBadgeText(for: .gcj02), "GCJ-02")

        let wgsObservation = try MapCoordinateObservation(
            latitude: 30.2741,
            longitude: 120.1551,
            datum: .wgs84,
            source: .deviceLocation
        )
        let gcjObservation = try MapVisualHostBridge.convertWGS84ToGCJ02Once(wgsObservation)
        XCTAssertEqual(gcjObservation.datum, .gcj02)

        let item = try MapLayerItem(
            key: MapSourceKey(type: .roamPOI, id: "poi-hz-1"),
            placeID: "place-hz-1",
            visibilityVersion: 2,
            state: .interactive,
            coordinate: gcjObservation,
            capabilities: [.viewDetail, .navigate],
            sortKey: "001",
            title: "West Lake Roam Node"
        )
        let lockedItem = try MapLayerItem(
            key: MapSourceKey(type: .sideQuest, id: "quest-hz-2"),
            placeID: nil,
            visibilityVersion: 1,
            state: .locked,
            coordinate: gcjObservation,
            capabilities: [.viewDetail],
            sortKey: "002",
            title: "Locked Side Quest"
        )

        let projections = try MapVisualHostBridge.projectAnnotations(
            items: [item, lockedItem],
            visibleLayers: [.roamPOI, .sideQuest],
            selectedKey: lockedItem.key,
            activeKey: item.key,
            targetDatum: .gcj02,
            theme: dayTheme
        )
        XCTAssertEqual(projections.count, 2)
        XCTAssertTrue(projections[0].allowsPrimaryAction)
        XCTAssertFalse(projections[1].allowsPrimaryAction)

        var selectedKey: MapSourceKey?
        let view = MapVisualLayerControlSectionView(
            theme: dayTheme,
            orderedLayers: MapVisualHostBridge.orderedLayers(),
            projections: projections,
            coordinateObservation: gcjObservation,
            onSelectAnnotation: { selectedKey = $0 }
        )

        XCTAssertEqual(view.orderedLayers.count, MapLayerOrder.allCases.count)
        XCTAssertEqual(view.orderedLayers.first, .basemap)
        XCTAssertEqual(view.orderedLayers.last, .controls)
        XCTAssertEqual(view.projections.count, 2)
        XCTAssertEqual(MapVisualLayerControlSectionView.layerDisplayName(.fog), "个人迷雾层 (Personal Fog)")
        XCTAssertEqual(MapVisualLayerControlSectionView.stateDisplayName(.active), "当前进行中")
        XCTAssertEqual(MapVisualLayerControlSectionView.stateDisplayName(.locked), "未解锁")
        _ = view.body
        view.onSelectAnnotation?(item.key)
        XCTAssertEqual(selectedKey, item.key)
    }

    func testMerchantInStoreGameDraftSectionViewLockedGateAndUnlockedSubmissionReadiness() {
        let revision = MerchantAuthoringRevision(
            draftID: "draft-game-101",
            version: 3,
            stage: .approved,
            authorID: "author-1",
            contentHash: "hash-v3",
            touchesThemeContent: true,
            merchantFactsApproval: MerchantAuthoringApproval(
                authority: .storeOwner,
                approverID: "store-owner-2",
                approvedHash: "hash-v3"
            ),
            themeContentApproval: MerchantAuthoringApproval(
                authority: .themeOwner,
                approverID: "theme-owner-3",
                approvedHash: "hash-v3"
            )
        )

        var gameDraft = InStoreGameDraft()
        gameDraft.interactionTemplateID = "tpl-puzzle-01"
        gameDraft.durationMinutes = 30
        gameDraft.maxParticipants = 6
        gameDraft.businessHoursText = "10:00-21:00"
        gameDraft.needsStaff = true
        gameDraft.noiseAndFilmingLimits = "禁止闪光灯与喧哗"
        gameDraft.accessibleAlternative = "提供一楼无障碍桌面版本"
        gameDraft.offlineFallback = "断网时可凭纸质线索卡继续"
        gameDraft.failureExit = "可随时中止并保留参与记录"
        gameDraft.reward = .approvedRule(id: "reward-rule-01")

        let catalog = [
            CanonicalSKUFact(merchantID: "merchant-1", skuID: "sku-tea-set", priceMinor: 6800, currency: "CNY")
        ]
        let productDraft = MerchantProductDraft(
            merchantID: "merchant-1",
            source: .canonical(skuID: "sku-tea-set"),
            claimedPriceMinor: 6800,
            claimedDiscountText: nil,
            createsThemeInventoryCopy: false
        )
        let requestID = UUID()

        // 1. Default locked gate state (MerchantAICommerceGates.disabled)
        let lockedPresentation = MerchantInStoreGameAuthoringPresentation(
            revision: revision,
            gameDraft: gameDraft,
            approvedTemplates: ["tpl-puzzle-01"],
            approvedRewardRules: ["reward-rule-01"],
            productDraft: productDraft,
            catalog: catalog,
            requestID: requestID,
            gates: .disabled
        )
        XCTAssertTrue(lockedPresentation.isGameDraftComplete)
        XCTAssertTrue(lockedPresentation.isProductDraftValid)
        XCTAssertFalse(lockedPresentation.isPublishGateEnabled)
        XCTAssertFalse(lockedPresentation.isReadyToPublish)
        XCTAssertNil(lockedPresentation.publishCommand)
        XCTAssertEqual(lockedPresentation.statusHeadline, "发布门控已关闭（默认关闭）")

        let lockedView = MerchantInStoreGameDraftSectionView(presentation: lockedPresentation)
        _ = lockedView.body

        // 2. Unlocked authoring publish gate with valid 3-part validation (fields + SKU + dual-domain approvals)
        var unlockedGates = MerchantAICommerceGates.disabled
        unlockedGates.merchantAuthoringPublish = true
        let unlockedPresentation = MerchantInStoreGameAuthoringPresentation(
            revision: revision,
            gameDraft: gameDraft,
            approvedTemplates: ["tpl-puzzle-01"],
            approvedRewardRules: ["reward-rule-01"],
            productDraft: productDraft,
            catalog: catalog,
            requestID: requestID,
            gates: unlockedGates
        )
        XCTAssertTrue(unlockedPresentation.isPublishGateEnabled)
        XCTAssertTrue(unlockedPresentation.isReadyToPublish)
        XCTAssertEqual(unlockedPresentation.publishCommand?.expectedVersion, 3)
        XCTAssertEqual(unlockedPresentation.publishCommand?.reviewedHash, "hash-v3")
        XCTAssertEqual(unlockedPresentation.statusHeadline, "已通过双域审批与主数据校验，可生成幂等发布指令")

        let unlockedView = MerchantInStoreGameDraftSectionView(presentation: unlockedPresentation)
        _ = unlockedView.body

        // 3. Invalid capacity / missing fields blocks publish even when gate is unlocked
        var invalidCapacityDraft = gameDraft
        invalidCapacityDraft.maxParticipants = 0
        let invalidCapacityPresentation = MerchantInStoreGameAuthoringPresentation(
            revision: revision,
            gameDraft: invalidCapacityDraft,
            approvedTemplates: ["tpl-puzzle-01"],
            approvedRewardRules: ["reward-rule-01"],
            productDraft: productDraft,
            catalog: catalog,
            requestID: requestID,
            gates: unlockedGates
        )
        XCTAssertFalse(invalidCapacityPresentation.isGameDraftComplete)
        XCTAssertEqual(invalidCapacityPresentation.missingGameFields, [.maxParticipants])
        XCTAssertFalse(invalidCapacityPresentation.isReadyToPublish)
        XCTAssertNil(invalidCapacityPresentation.publishCommand)
    }
}
