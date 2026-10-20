import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class PublishMediaEditorSectionViewTests: XCTestCase {
    private let digestA = String(repeating: "a", count: 64)
    private let digestB = String(repeating: "b", count: 64)

    private var enabledCapabilities: ReformWorldCapabilities {
        ReformWorldCapabilities.syntheticFixture([.themeRelease, .publishMedia])
    }

    private func makeProfile(version: String = "synthetic-v1", maxItems: Int = 4) throws -> PublishMediaProfile {
        try JSONDecoder().decode(
            PublishMediaProfile.self,
            from: Data("{\"profileVersion\":\"\(version)\",\"maxItems\":\(maxItems),\"maxImageBytes\":4096,\"maxVideoBytes\":16384,\"maxVideoMilliseconds\":60000}".utf8)
        )
    }

    private func makeOwnership(kind: String, ownerId: String = "owner-1", worldId: String = "world-1") throws -> ContentOwnership {
        try JSONDecoder().decode(
            ContentOwnership.self,
            from: Data("{\"ownerKind\":\"\(kind)\",\"ownerId\":\"\(ownerId)\",\"worldId\":\"\(worldId)\"}".utf8)
        )
    }

    func testOwnershipLabelsAndCrossOwnerCrossWorldRefusalPresentation() throws {
        XCTAssertEqual(PublishMediaEditorSectionView.ownerKindLabel(.creator), "创作者")
        XCTAssertEqual(PublishMediaEditorSectionView.ownerKindLabel(.club), "俱乐部")
        XCTAssertEqual(PublishMediaEditorSectionView.ownerKindLabel(.merchant), "商家")
        XCTAssertEqual(PublishMediaEditorSectionView.ownerKindLabel(.platform), "平台")

        for (rawKind, kind) in [
            ("CREATOR", ContentOwnership.OwnerKind.creator),
            ("CLUB", ContentOwnership.OwnerKind.club),
            ("MERCHANT", ContentOwnership.OwnerKind.merchant),
            ("PLATFORM", ContentOwnership.OwnerKind.platform)
        ] {
            let ownership = try makeOwnership(kind: rawKind, ownerId: "actor-10", worldId: "world-10")
            let matchingActor = PublishMediaEditorActor(kind: kind, actorId: "actor-10", worldId: "world-10")
            let bridge = try PublishMediaEditorBridge(
                capabilities: enabledCapabilities,
                ownership: ownership,
                actor: matchingActor,
                profile: try makeProfile()
            )
            let allowedView = PublishMediaEditorSectionView(bridge: bridge, actor: matchingActor)
            XCTAssertEqual(allowedView.bridge.ownership.ownerKind, kind)
            XCTAssertEqual(allowedView.actor, matchingActor)
            _ = allowedView.body

            let crossOwnerActor = PublishMediaEditorActor(kind: kind, actorId: "actor-99", worldId: "world-10")
            let crossWorldActor = PublishMediaEditorActor(kind: kind, actorId: "actor-10", worldId: "world-99")
            XCTAssertThrowsError(
                try ownership.permitsEdit(
                    actorKind: crossOwnerActor.kind,
                    actorId: crossOwnerActor.actorId,
                    worldId: crossOwnerActor.worldId
                )
            ) { error in
                XCTAssertEqual(error as? ThemeReleaseIssue, .crossOwner)
            }
            XCTAssertThrowsError(
                try ownership.permitsEdit(
                    actorKind: crossWorldActor.kind,
                    actorId: crossWorldActor.actorId,
                    worldId: crossWorldActor.worldId
                )
            ) { error in
                XCTAssertEqual(error as? ThemeReleaseIssue, .crossOwner)
            }

            let deniedView = PublishMediaEditorSectionView(bridge: bridge, actor: crossWorldActor)
            XCTAssertEqual(deniedView.actor, crossWorldActor)
            _ = deniedView.body
        }
    }

    func testThemeReleaseStatusProgressionAndLabels() throws {
        XCTAssertEqual(PublishMediaEditorSectionView.releaseStatusLabel(.draft), "草稿(DRAFT)")
        XCTAssertEqual(PublishMediaEditorSectionView.releaseStatusLabel(.review), "审核中(REVIEW)")
        XCTAssertEqual(PublishMediaEditorSectionView.releaseStatusLabel(.approved), "已通过(APPROVED)")
        XCTAssertEqual(PublishMediaEditorSectionView.releaseStatusLabel(.published), "已发布(PUBLISHED)")
        XCTAssertEqual(PublishMediaEditorSectionView.releaseStatusLabel(.retired), "已下架(RETIRED)")

        XCTAssertTrue(ThemeReleaseStatus.draft.canAdvance(to: .review))
        XCTAssertTrue(ThemeReleaseStatus.review.canAdvance(to: .approved))
        XCTAssertTrue(ThemeReleaseStatus.approved.canAdvance(to: .published))
        XCTAssertTrue(ThemeReleaseStatus.published.canAdvance(to: .retired))
        XCTAssertFalse(ThemeReleaseStatus.retired.canAdvance(to: .draft))

        let ownership = try makeOwnership(kind: "MERCHANT", ownerId: "m-1", worldId: "w-1")
        let actor = PublishMediaEditorActor(kind: .merchant, actorId: "m-1", worldId: "w-1")
        var bridge = try PublishMediaEditorBridge(
            capabilities: enabledCapabilities,
            ownership: ownership,
            actor: actor,
            releaseStatus: .draft,
            profile: try makeProfile()
        )

        let item = try bridge.selectMedia(uniformType: "public.jpeg", byteCount: 512, actor: actor)
        try bridge.markProcessed(id: item.id, sha256: digestA, actor: actor)
        try bridge.markUploaded(id: item.id, assetId: "asset-1", serverSHA256: digestA, actor: actor)
        try bridge.markReviewed(id: item.id, outcome: .approved, actor: actor)

        try bridge.advanceReleaseStatus(to: .review, actor: actor)
        XCTAssertEqual(bridge.releaseStatus, .review)

        // Cannot advance to `.approved` before media is saved.
        XCTAssertThrowsError(try bridge.advanceReleaseStatus(to: .approved, actor: actor)) { error in
            XCTAssertEqual(error as? PublishMediaEditorBridgeIssue, .mediaNotPublishable)
        }

        try bridge.markSaved(id: item.id, referencedAssetId: "asset-1", actor: actor)
        try bridge.advanceReleaseStatus(to: .approved, actor: actor)
        XCTAssertEqual(bridge.releaseStatus, .approved)

        let view = PublishMediaEditorSectionView(bridge: bridge, actor: actor)
        XCTAssertEqual(view.bridge.releaseStatus, .approved)
        XCTAssertTrue(view.bridge.selection.publishable)
        _ = view.body
    }

    func testSevenStageMediaPipelineAndVideoPosterRequirementInView() throws {
        let expectedStages: [(PublishMediaStage, String)] = [
            (.selected, "select"),
            (.processed, "process"),
            (.uploaded, "upload"),
            (.reviewed, "review"),
            (.saved, "save"),
            (.readable, "read"),
            (.playable, "play")
        ]
        for (stage, label) in expectedStages {
            XCTAssertEqual(PublishMediaEditorSectionView.stageLabel(stage), label)
        }

        XCTAssertEqual(
            PublishMediaEditorSectionView.stageChainSummary(current: .selected),
            "[select*] -> process -> upload -> review -> save -> read -> play"
        )
        XCTAssertEqual(
            PublishMediaEditorSectionView.stageChainSummary(current: .saved),
            "[select✓] -> [process✓] -> [upload✓] -> [review✓] -> [save*] -> read -> play"
        )
        XCTAssertEqual(
            PublishMediaEditorSectionView.stageChainSummary(current: .playable),
            "[select✓] -> [process✓] -> [upload✓] -> [review✓] -> [save✓] -> [read✓] -> [play*]"
        )

        let ownership = try makeOwnership(kind: "CLUB", ownerId: "club-7", worldId: "world-3")
        let actor = PublishMediaEditorActor(kind: .club, actorId: "club-7", worldId: "world-3")
        var bridge = try PublishMediaEditorBridge(
            capabilities: enabledCapabilities,
            ownership: ownership,
            actor: actor,
            profile: try makeProfile()
        )

        let video = try bridge.selectMedia(
            uniformType: "public.mpeg-4",
            byteCount: 8192,
            durationMilliseconds: 20000,
            actor: actor
        )
        try bridge.markProcessed(id: video.id, sha256: digestB, actor: actor)
        try bridge.markUploaded(id: video.id, assetId: "vid-1", serverSHA256: digestB, actor: actor)

        // Video approval requires a valid poster asset ID.
        XCTAssertThrowsError(
            try bridge.markReviewed(id: video.id, outcome: .approved, posterAssetId: nil, actor: actor)
        ) { error in
            XCTAssertEqual(error as? PublishMediaIssue, .invalid)
        }

        try bridge.markReviewed(id: video.id, outcome: .approved, posterAssetId: "poster-vid-1", actor: actor)
        try bridge.markSaved(id: video.id, referencedAssetId: "vid-1", actor: actor)
        try bridge.markReadable(id: video.id, readbackAssetId: "vid-1", readbackSHA256: digestB, actor: actor)
        let playable = try bridge.markPlayable(id: video.id, actor: actor)
        XCTAssertEqual(playable.stage, .playable)
        XCTAssertEqual(playable.posterAssetId, "poster-vid-1")

        let sectionView = PublishMediaEditorSectionView(bridge: bridge, actor: actor)
        XCTAssertEqual(sectionView.bridge.selection.items.count, 1)
        XCTAssertEqual(sectionView.bridge.selection.restorable().count, 1)
        _ = sectionView.body
    }
}
