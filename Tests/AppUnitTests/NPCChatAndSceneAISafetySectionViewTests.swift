#if canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
import XCTest
@testable import Questify

@MainActor
final class NPCChatAndSceneAISafetySectionViewTests: XCTestCase {
    func testDefaultSnapshotEnforcesNonGenerativeKillSwitchAndNPCDeletionFence() {
        let view = NPCChatAndSceneAISafetySectionView()
        _ = view.body

        XCTAssertFalse(view.snapshot.globalGenerationEnabled)
        XCTAssertFalse(view.snapshot.streamingDisplayAllowed)
        XCTAssertTrue(view.snapshot.enforcesScopeEchoAndIsolation)
        XCTAssertTrue(view.snapshot.dropsForbiddenBusinessEffects)
        XCTAssertTrue(view.snapshot.enforcesNPCChatDeletionReReadFence)
        XCTAssertTrue(view.snapshot.hasCanonicalGuards)
        XCTAssertTrue(view.snapshot.isAllCompliant)
        XCTAssertEqual(
            view.snapshot.rows.map(\.guardID),
            ["SceneAIKillSwitch", "SceneAIScopeIsolation", "NPCNarrativeEffectWhitelist", "NPCChatDeletionFence"]
        )
        XCTAssertTrue(view.statusHeadline.contains("I08"))
    }

    func testEnabledGenerationOrStreamingFailsSceneAIKillSwitchGuard() {
        let generativeSnapshot = NPCChatAndSceneAISafetySnapshot(
            globalGenerationEnabled: true,
            streamingDisplayAllowed: false
        )
        let view = NPCChatAndSceneAISafetySectionView(snapshot: generativeSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllCompliant)
        XCTAssertFalse(view.snapshot.rows[0].isEnforced)
        XCTAssertTrue(view.statusHeadline.contains("非生成式"))
    }

    func testDisabledNPCDeletionFenceOrNarrativeWhitelistReportsViolation() {
        let noDeletionFenceSnapshot = NPCChatAndSceneAISafetySnapshot(
            enforcesNPCChatDeletionReReadFence: false
        )
        let fenceView = NPCChatAndSceneAISafetySectionView(snapshot: noDeletionFenceSnapshot)
        _ = fenceView.body

        XCTAssertFalse(fenceView.snapshot.isAllCompliant)
        XCTAssertFalse(fenceView.snapshot.rows[3].isEnforced)
        XCTAssertTrue(fenceView.statusHeadline.contains("I08"))

        let unguardedEffectsSnapshot = NPCChatAndSceneAISafetySnapshot(
            dropsForbiddenBusinessEffects: false
        )
        let effectsView = NPCChatAndSceneAISafetySectionView(snapshot: unguardedEffectsSnapshot)
        _ = effectsView.body

        XCTAssertFalse(effectsView.snapshot.isAllCompliant)
        XCTAssertTrue(effectsView.statusHeadline.contains("白名单"))
    }
}
