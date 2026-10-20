import XCTest
@testable import QuestifyCore

final class PublishMediaEditorBridgeTests: XCTestCase {
    private let digestA = String(repeating: "a", count: 64)
    private let digestB = String(repeating: "b", count: 64)

    private func makeProfile(version: String = "synthetic-v1", maxItems: Int = 4) throws -> PublishMediaProfile {
        try JSONDecoder().decode(
            PublishMediaProfile.self,
            from: Data("{\"profileVersion\":\"\(version)\",\"maxItems\":\(maxItems),\"maxImageBytes\":2048,\"maxVideoBytes\":8192,\"maxVideoMilliseconds\":60000}".utf8)
        )
    }

    private func makeOwnership(kind: String = "MERCHANT", ownerId: String = "merchant-1", worldId: String = "world-1") throws -> ContentOwnership {
        try JSONDecoder().decode(
            ContentOwnership.self,
            from: Data("{\"ownerKind\":\"\(kind)\",\"ownerId\":\"\(ownerId)\",\"worldId\":\"\(worldId)\"}".utf8)
        )
    }

    private func makeRelease(id: String, version: Int64, hash: String?, status: String) throws -> ThemeReleaseRef {
        let hashField = hash.map { ",\"contentHash\":\"\($0)\"" } ?? ""
        return try JSONDecoder().decode(
            ThemeReleaseRef.self,
            from: Data("{\"themeId\":\"theme-1\",\"releaseId\":\"\(id)\",\"version\":\(version),\"schemaVersion\":1,\"status\":\"\(status)\"\(hashField)}".utf8)
        )
    }

    private var enabledCapabilities: ReformWorldCapabilities {
        ReformWorldCapabilities.syntheticFixture([.themeRelease, .publishMedia])
    }

    func testDefaultOffCapabilitiesRefuseBridgeAndPinReconciliation() throws {
        let ownership = try makeOwnership()
        let ownerActor = PublishMediaEditorActor(kind: .merchant, actorId: "merchant-1", worldId: "world-1")
        let profile = try makeProfile()

        XCTAssertThrowsError(
            try PublishMediaEditorBridge(
                capabilities: .disabled,
                ownership: ownership,
                actor: ownerActor,
                profile: profile
            )
        ) { error in
            XCTAssertEqual(error as? PublishMediaEditorBridgeIssue, .capabilityDisabled(.themeRelease))
        }

        let onlyThemeRelease = ReformWorldCapabilities.syntheticFixture([.themeRelease])
        XCTAssertThrowsError(
            try PublishMediaEditorBridge(
                capabilities: onlyThemeRelease,
                ownership: ownership,
                actor: ownerActor,
                profile: profile
            )
        ) { error in
            XCTAssertEqual(error as? PublishMediaEditorBridgeIssue, .capabilityDisabled(.publishMedia))
        }

        let published = try makeRelease(id: "rel-1", version: 1, hash: digestA, status: "PUBLISHED")
        let pin = try RunReleasePin(runId: "run-1", release: published)
        XCTAssertThrowsError(
            try PublishMediaEditorBridge.reconcilePinnedRun(pin, currentRelease: published, capabilities: .disabled)
        ) { error in
            XCTAssertEqual(error as? PublishMediaEditorBridgeIssue, .capabilityDisabled(.themeRelease))
        }
    }

    func testCrossOwnerAndCrossWorldEditsAreRefusedAtInitAndMutation() throws {
        let ownership = try makeOwnership(kind: "MERCHANT", ownerId: "merchant-1", worldId: "world-1")
        let ownerActor = PublishMediaEditorActor(kind: .merchant, actorId: "merchant-1", worldId: "world-1")
        let otherOwner = PublishMediaEditorActor(kind: .merchant, actorId: "merchant-2", worldId: "world-1")
        let otherWorld = PublishMediaEditorActor(kind: .merchant, actorId: "merchant-1", worldId: "world-2")
        let otherKind = PublishMediaEditorActor(kind: .club, actorId: "merchant-1", worldId: "world-1")
        let profile = try makeProfile()

        for unauthorized in [otherOwner, otherWorld, otherKind] {
            XCTAssertThrowsError(
                try PublishMediaEditorBridge(
                    capabilities: enabledCapabilities,
                    ownership: ownership,
                    actor: unauthorized,
                    profile: profile
                )
            ) { error in
                XCTAssertEqual(error as? ThemeReleaseIssue, .crossOwner)
            }
        }

        var bridge = try PublishMediaEditorBridge(
            capabilities: enabledCapabilities,
            ownership: ownership,
            actor: ownerActor,
            profile: profile
        )
        let item = try bridge.selectMedia(uniformType: "public.jpeg", byteCount: 512, actor: ownerActor)
        XCTAssertThrowsError(
            try bridge.markProcessed(id: item.id, sha256: digestA, actor: otherOwner)
        ) { error in
            XCTAssertEqual(error as? ThemeReleaseIssue, .crossOwner)
        }
    }

    func testVideoStageProgressionRequiresPosterOnApprovalAndWalksToPlayable() throws {
        let ownership = try makeOwnership()
        let actor = PublishMediaEditorActor(kind: .merchant, actorId: "merchant-1", worldId: "world-1")
        var bridge = try PublishMediaEditorBridge(
            capabilities: enabledCapabilities,
            ownership: ownership,
            actor: actor,
            profile: try makeProfile()
        )

        let selected = try bridge.selectMedia(
            uniformType: "public.mpeg-4",
            byteCount: 4096,
            durationMilliseconds: 15000,
            actor: actor
        )
        XCTAssertEqual(selected.stage, .selected)

        XCTAssertThrowsError(
            try bridge.markUploaded(id: selected.id, assetId: "asset-v1", serverSHA256: digestA, actor: actor)
        ) { error in
            XCTAssertEqual(error as? PublishMediaIssue, .outOfOrder)
        }

        let processed = try bridge.markProcessed(id: selected.id, sha256: digestA, actor: actor)
        XCTAssertEqual(processed.stage, .processed)

        let uploaded = try bridge.markUploaded(id: selected.id, assetId: "asset-v1", serverSHA256: digestA, actor: actor)
        XCTAssertEqual(uploaded.stage, .uploaded)

        // Approving a video without a poster asset must fail closed.
        XCTAssertThrowsError(
            try bridge.markReviewed(id: selected.id, outcome: .approved, posterAssetId: nil, actor: actor)
        ) { error in
            XCTAssertEqual(error as? PublishMediaIssue, .invalid)
        }

        let reviewed = try bridge.markReviewed(id: selected.id, outcome: .approved, posterAssetId: "poster-1", actor: actor)
        XCTAssertEqual(reviewed.stage, .reviewed)
        XCTAssertEqual(reviewed.posterAssetId, "poster-1")

        let saved = try bridge.markSaved(id: selected.id, referencedAssetId: "asset-v1", actor: actor)
        XCTAssertEqual(saved.stage, .saved)
        XCTAssertTrue(bridge.selection.publishable)

        let readable = try bridge.markReadable(id: selected.id, readbackAssetId: "asset-v1", readbackSHA256: digestA, actor: actor)
        XCTAssertEqual(readable.stage, .readable)

        let playable = try bridge.markPlayable(id: selected.id, actor: actor)
        XCTAssertEqual(playable.stage, .playable)
    }

    func testDraftRestorationKeepsOnlyReadbackVerifiedMediaAndChecksProfileVersion() throws {
        let ownership = try makeOwnership()
        let actor = PublishMediaEditorActor(kind: .merchant, actorId: "merchant-1", worldId: "world-1")
        let profileV1 = try makeProfile(version: "synthetic-v1", maxItems: 4)
        var bridge = try PublishMediaEditorBridge(
            capabilities: enabledCapabilities,
            ownership: ownership,
            actor: actor,
            profile: profileV1
        )

        // Item 1: only reaches `.saved` (not yet read back) -> must NOT survive restore.
        let savedOnly = try bridge.selectMedia(uniformType: "public.png", byteCount: 300, actor: actor)
        try bridge.markProcessed(id: savedOnly.id, sha256: digestA, actor: actor)
        try bridge.markUploaded(id: savedOnly.id, assetId: "img-saved", serverSHA256: digestA, actor: actor)
        try bridge.markReviewed(id: savedOnly.id, outcome: .approved, actor: actor)
        try bridge.markSaved(id: savedOnly.id, referencedAssetId: "img-saved", actor: actor)

        // Item 2: reaches `.readable` -> MUST survive restore.
        let readableItem = try bridge.selectMedia(uniformType: "public.jpeg", byteCount: 400, actor: actor)
        try bridge.markProcessed(id: readableItem.id, sha256: digestB, actor: actor)
        try bridge.markUploaded(id: readableItem.id, assetId: "img-read", serverSHA256: digestB, actor: actor)
        try bridge.markReviewed(id: readableItem.id, outcome: .approved, actor: actor)
        try bridge.markSaved(id: readableItem.id, referencedAssetId: "img-read", actor: actor)
        try bridge.markReadable(id: readableItem.id, readbackAssetId: "img-read", readbackSHA256: digestB, actor: actor)

        let restored = try bridge.restoreDraft(currentProfile: profileV1, actor: actor)
        XCTAssertEqual(restored.selection.items.map(\.id), [readableItem.id])

        let profileV2 = try makeProfile(version: "synthetic-v2", maxItems: 4)
        XCTAssertThrowsError(
            try bridge.restoreDraft(currentProfile: profileV2, actor: actor)
        ) { error in
            XCTAssertEqual(error as? PublishMediaIssue, .staleProfile)
        }
    }

    func testRunReleasePinImmutabilityAndReleaseStatusTransitions() throws {
        let ownership = try makeOwnership()
        let actor = PublishMediaEditorActor(kind: .merchant, actorId: "merchant-1", worldId: "world-1")
        var bridge = try PublishMediaEditorBridge(
            capabilities: enabledCapabilities,
            ownership: ownership,
            actor: actor,
            releaseStatus: .draft,
            profile: try makeProfile()
        )

        let item = try bridge.selectMedia(uniformType: "public.heic", byteCount: 600, actor: actor)
        try bridge.markProcessed(id: item.id, sha256: digestA, actor: actor)
        try bridge.markUploaded(id: item.id, assetId: "asset-img", serverSHA256: digestA, actor: actor)
        try bridge.markReviewed(id: item.id, outcome: .approved, actor: actor)

        // Cannot approve release before media is saved.
        try bridge.advanceReleaseStatus(to: .review, actor: actor)
        XCTAssertThrowsError(try bridge.advanceReleaseStatus(to: .approved, actor: actor)) { error in
            XCTAssertEqual(error as? PublishMediaEditorBridgeIssue, .mediaNotPublishable)
        }

        try bridge.markSaved(id: item.id, referencedAssetId: "asset-img", actor: actor)
        try bridge.advanceReleaseStatus(to: .approved, actor: actor)
        XCTAssertEqual(bridge.releaseStatus, .approved)

        // Once approved, further media mutations are refused as non-editable.
        XCTAssertThrowsError(
            try bridge.selectMedia(uniformType: "public.jpeg", byteCount: 200, actor: actor)
        ) { error in
            XCTAssertEqual(error as? PublishMediaEditorBridgeIssue, .releaseNotEditable(.approved))
        }

        let r1 = try makeRelease(id: "rel-1", version: 1, hash: digestA, status: "PUBLISHED")
        let r2 = try makeRelease(id: "rel-2", version: 2, hash: digestB, status: "PUBLISHED")
        let driftedR1 = try makeRelease(id: "rel-1", version: 1, hash: digestB, status: "PUBLISHED")
        let pin = try RunReleasePin(runId: "run-100", release: r1)

        XCTAssertEqual(
            try PublishMediaEditorBridge.reconcilePinnedRun(pin, currentRelease: r2, capabilities: enabledCapabilities),
            .newerReleaseForNewRuns(r2)
        )
        XCTAssertEqual(pin.releaseId, "rel-1")
        XCTAssertEqual(pin.contentHash, digestA)

        XCTAssertThrowsError(
            try PublishMediaEditorBridge.reconcilePinnedRun(pin, currentRelease: driftedR1, capabilities: enabledCapabilities)
        ) { error in
            XCTAssertEqual(error as? ThemeReleaseIssue, .drift)
        }
    }
}
