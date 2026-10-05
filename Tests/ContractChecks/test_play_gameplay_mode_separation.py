"""Bounded source assertions; not Swift/Apple execution or live source acceptance."""
from pathlib import Path
import json
import unittest
ROOT=Path(__file__).resolve().parents[2]
class PlayGameplayModeSeparationContracts(unittest.TestCase):
    def read(self,path):return (ROOT/path).read_text()
    def test_exact_server_mode_without_product_or_entry_inference(self):
        mode=self.read('Core/PlayGameplayMode.swift')
        for marker in ['case cityOrientation = 1','case freeExploration = 2','init?(serverValue: Int?)']:
            self.assertIn(marker,mode)
        c=self.read('Core/PlayExperienceCoordinator.swift')
        self.assertIn('PlayGameplayMode(serverValue: snapshot?.result.mode)',c);self.assertNotIn('productType',c)
    def test_runtime_and_ordinary_fallback_have_distinct_free_surfaces(self):
        source=self.read('App/PlayExperienceView.swift')
        for marker in ['FreeExplorationExperienceView(model: model','private var orientationContent','if mode == .cityOrientation, previous != .cityOrientation',
                       'FreeExplorationStoreView(nodeID: id','nodeDestination: { AnyView(freeStoreDestination($0)) }']:
            self.assertIn(marker,source)
        fallback=self.read('App/PlaySessionView.swift')
        self.assertIn('FreeExplorationCardBrowser(snapshot: snapshot',fallback)
        self.assertIn('FreeExplorationReadStoreView(nodeID: nodeID, model: model)',fallback)
    def test_free_cards_keep_server_order_variable_count_and_accessibility(self):
        source=self.read('App/FreeExplorationViews.swift')
        for marker in ['playFree.pack.open','LazyVGrid','ForEach(presentation.stores)','typeSize.isAccessibilitySize ? 1 : 2','playFree.choiceHint']:
            self.assertIn(marker,source)
        for denied in ['playx.run.resume','playx.run.pause','playx.run.end','currentNodeID','sorted(', 'prefix(6)', 'startRun(', 'CityMapPresentation']:
            self.assertNotIn(denied,source)
        self.assertIn('stores = snapshot.availability == .registrationRequired ? [] : snapshot.visibleNodes',self.read('Core/PlayGameplayMode.swift'))
    def test_orientation_storage_is_gated_before_any_restore_access(self):
        source=self.read('Core/PlayExperienceCoordinator.swift')
        self.assertIn('public var canManageRun: Bool { gameplayMode == .cityOrientation',source)
        restore=source.split('public func restoreRun() async {',1)[1].split('private func reconcileRun',1)[0]
        self.assertLess(restore.index('gameplayMode == .cityOrientation'),restore.index('await reconcileRun'))
        self.assertIn('pausedLease = nil; pausedOwner = nil; clock.restore(nil)',source)
    def test_new_journals_bind_mode_and_legacy_cross_mode_cannot_settle(self):
        self.assertIn('public let gameplayMode: PlayGameplayMode?',self.read('Core/PlayRecoveryStorage.swift'))
        source=self.read('Core/PlayExperienceCoordinator.swift')
        for marker in ['review.gameplayMode == gameplayMode','pending.intent.gameplayMode == gameplayMode',
                       'guard let mode = review.gameplayMode, mode == PlayGameplayMode(serverValue: snapshot.result.mode)',
                       'completion.value.intent.gameplayMode != nil']:
            self.assertIn(marker,source)
    def test_store_evidence_does_not_borrow_orientation_game_or_redemption(self):
        source=self.read('Core/PlayGameplayMode.swift')
        for marker in ['node.arrived == false { return .merchantScan }','node.hasGame == false || (node.hasGame == true && node.gameDone == true)',
                       'return .merchantPhoto','if snapshot.isDone(node) { return .redeemed }']:
            self.assertIn(marker,source)
        free=self.read('App/FreeExplorationViews.swift')
        for marker in ['playFree.game.unavailable','playFree.redemption.unavailable','PlayDeviceTaskSection(model: device, task: task']:
            self.assertIn(marker,free)
        for denied in ['PlayPreferenceView','PlayAdvancedView','PlayLeadSection','PlayPlayerSessionView','requestHint(']:self.assertNotIn(denied,free)
    def test_free_ending_has_its_own_read_and_no_score_ranking_or_write(self):
        source=self.read('Core/PlayExperienceCoordinator.swift').split('public func loadFreeExplorationEnding() async {',1)[1].split('public func loadEndingAndLeaderboard',1)[0]
        for marker in ['gameplayMode == .freeExploration','isFullyRedeemed == true','service.ending']:self.assertIn(marker,source)
        self.assertNotIn('service.leaderboard',source);self.assertNotIn('dispatch',source)
    def test_bilingual_copy_and_authored_normal_runtime_ui_coverage(self):
        strings=json.loads(self.read('Resources/Localizable.xcstrings'))['strings']
        keys=[key for key in strings if key.startswith('playFree.') or key.startswith('playMode.')]
        self.assertEqual(len(keys),27)
        for key in keys:
            for language in ['en','zh-Hans']:self.assertTrue(strings[key]['localizations'][language]['stringUnit']['value'])
        tests=self.read('Tests/AppUITests/PlayExperienceFlowTests.swift')
        for name in ['testMode2ShowsSeparateVerificationStep','testChineseFreePackKeepsStoreChoiceAfterBackAndRefresh',
                     'testOrdinaryReadFallbackUsesFreeStoreCardsAndNoOrientationAnswerForm']:self.assertIn(name,tests)
    def test_authored_core_cases_cover_actions_not_just_hidden_buttons(self):
        tests=self.read('Tests/CoreTests/PlayModeLifecycleTests.swift')
        for name in ['testFreeModeCannotTouchOrientationClockStorageOrRunEndpointsEvenWithCapability',
                     'testFreshFreeModeDiscardsOnlyInMemoryOrientationState','testFreeEvidenceRejectsOrientationAnswerGPSAndSensorCommands',
                     'testStoreArrivalDoesNotRequireAnOrientationAdvancedTaskFirst',
                     'testCrossModeAndLegacyPendingWritesDoNotSettleFromSameStoreArrival',
                     'testFreeEndingRequiresRedemptionAndDoesNotLoadOrientationLeaderboard']:self.assertIn(name,tests)

    def test_ax_ids_are_on_leaf_or_concrete_list_not_virtual_parent_groups(self):
        source=self.read('App/FreeExplorationViews.swift')
        self.assertIn('Text("playFree.title").font(.caption.bold()).accessibilityIdentifier("playFree.pass")',source)
        self.assertNotIn('}.accessibilityIdentifier("playFree.pass")',source)
        root=self.read('App/PlayExperienceView.swift')
        wrapper=root.split('private var orientationContent',1)[0]
        self.assertNotIn('accessibilityIdentifier("playx.overview")',wrapper)
        orientation=root.split('private var orientationContent',1)[1].split('@ViewBuilder private func freeStoreDestination',1)[0]
        self.assertIn('.accessibilityIdentifier("playx.overview")',orientation)
        self.assertIn('.accessibilityIdentifier("playFree.overview")',source)

    def test_ephemeral_commands_bind_instance_session_generation_and_mode(self):
        source=self.read('Core/PlayExperienceCoordinator.swift')
        for marker in ['fileprivate let owner: UUID', 'fileprivate let session: PlayExperienceSession',
                       'fileprivate let generation: UInt64', 'fileprivate let mode: PlayGameplayMode',
                       'return context == current', 'guard accepts(context)',
                       'level == nil || gameplayMode == .cityOrientation']:
            self.assertIn(marker,source)
        changed=source.split('if authorityMode != mode {',1)[1].split('authorityMode = mode',1)[0]
        self.assertIn('advancedReadyNodeIDs = []',changed)
        for path in ['App/PlayExperienceView.swift','App/FreeExplorationViews.swift']:
            ui=self.read(path)
            self.assertIn('let context = model.interactionContext',ui)
            self.assertIn('model.review(nodeID: nodeID, evidence: evidence, context: context)',ui)
        story=self.read('App/ChapterStoryView.swift')
        self.assertIn('acceptAdvanced($0, context: advancedContext)',story)
        self.assertIn('await model.claimVisibleThoughts(chapterID: chapterID)',story)

    def test_authored_queued_command_and_advanced_mode_regressions(self):
        source=self.read('Tests/CoreTests/PlayModeLifecycleTests.swift')
        for marker in ['testQueuedHintAndLeadCommandsCannotAcquireChangedModeAuthority',
                       'testSameModeRefreshAndABARejectOldInteractionContext',
                       'testMissingOrOtherCoordinatorContextCannotDispatch',
                       'testFreshLeadAndGenericHintKeepTheirSourceBackedModeIndependentAuthority',
                       'testPuzzleHintRequiresCurrentOrientationModeEvenWithFreshContext',
                       'testAdvancedReadinessCannotCrossModeOrReturnThroughABA']:
            self.assertIn(marker,source)

    def test_device_result_retains_capture_lease_instead_of_latest_view_authority(self):
        core=self.read('Core/PlayDeviceTasks.swift')
        for marker in ['public struct PlayDeviceInteraction', 'private var capturedInteraction: PlayDeviceInteraction?',
                       'outputInteractionContext: PlayInteractionContext?', 'interaction?.isCurrent ?? true',
                       'output = result; outputID = UUID(); capturedContext = context; capturedInteraction = interaction',
                       'expectedOutputID == outputID', 'canReviewOutput else { return nil }']:
            self.assertIn(marker,core)
        view=self.read('App/PlayDeviceTaskViews.swift')
        self.assertIn('let interaction: PlayDeviceInteraction',view)
        self.assertIn('photoFilter: photoFilter, interaction: interaction',view)
        self.assertEqual(view.count('model.outputInteractionContext'),1)
        self.assertIn('let outputContext = model.outputInteractionContext, outputID = model.outputID',view)
        self.assertIn('await model.uploadPhoto(expectedOutputID: outputID)',view)
        self.assertIn('model.reviewedPhoto(expectedOutputID: outputID)',view)
        for path in ['App/PlayExperienceView.swift','App/FreeExplorationViews.swift']:
            self.assertIn('onEvidence: { prepare($0, context: $1) }',self.read(path))
        host=self.read('App/PlayExperienceView.swift')
        self.assertIn('if context != nil, context == currentContext { content(context) }',host)
        tests=self.read('Tests/CoreTests/PlayModeLifecycleTests.swift')
        for name in ['testDeviceCaptureRejectsLateOutputAfterModeChangesBeforeProviderReturns',
                     'testRetainedDeviceResultUsesOriginalLeaseEvenWhenNewViewOffersFreshCallback',
                     'testStaleOrMissingCaptureLeaseCannotStartProviderOrUploadOldPhoto',
                     'testPhotoUploadCannotRebindResultAfterModeSwitchDuringUpload',
                     'testQueuedPhotoUploadCannotUseReplacementCaptureWithinSameMode']:
            self.assertIn(name,tests)

    def test_child_runtime_send_and_upload_fence_before_dispatch_after_await_and_before_401(self):
        service=self.read('Core/PlayExperienceService.swift')
        send=service.split('@MainActor private func send(',1)[1]
        self.assertGreaterEqual(send.count('try checkReadLifetime()'),4)
        self.assertLess(send.index('try checkReadLifetime()'),send.index('transport.send(request)'))
        self.assertLess(send.index('try checkReadLifetime()',send.index('transport.send(request)')),send.index('status == 401'))
        upload=self.read('Core/PlayPhotoEvidence.swift')
        self.assertGreaterEqual(upload.count('try checkReadLifetime()'),4)
        self.assertLess(upload.index('try checkReadLifetime()',upload.index('transport.send(request)')),upload.index('status == 401'))
        for path in ['Core/PlayAdvancedRuntime.swift','Core/PlayPreferenceRuntime.swift']:
            core=self.read(path)
            self.assertIn('self.currentSession = { service.hasCurrentReadLifetime ? currentSession() : nil }',core)
            self.assertIn('blocksReadRebinding',core)

    def test_normal_child_factories_cannot_rebind_retained_unknown_operations(self):
        source=self.read('App/AppSession.swift')
        advanced=source.split('func playAdvanced(',1)[1].split('func playOperatingSummary(',1)[0]
        self.assertEqual(advanced.count('retained.blocksReadRebinding'),2)
        self.assertEqual(advanced.count('service: api.bound(to: lifetime)'),2)
        self.assertEqual(advanced.count('guard let lifetime, lifetime.isCurrent'),2)
        root=self.read('App/SessionPlayRuntimeView.swift')
        self.assertEqual(root.count('lifetime: model.makeInteractionLifetime()'),4)
        self.assertIn('readLifetime: lifetime, current:',source)
        self.assertIn('readLifetime: lifetime, currentContext:',source)
        self.assertIn('testNormalChildFactoriesKeepReadLifetimeImmutableAcrossModeChanges',self.read('Tests/AppUnitTests/PlayReadCompositionTests.swift'))

    def test_authored_child_command_tests_cover_unknowns_401_and_default_kit_capture(self):
        source=self.read('Tests/CoreTests/PlayReadLifetimeTests.swift')
        for name in ['testEveryAdvancedPreferenceTagAndUploadEndpointRejectsExpiredServiceBeforeTransport',
                     'testQueuedAdvancedStartAndPreferenceLoadCannotBorrowNewMode',
                     'testUnknownAdvancedActionStaysBlockedAfterModeChangeWithoutRetryOrNewStart',
                     'testUnknownPreferenceSubmissionStaysBlockedAfterModeChange',
                     'testLateResponseAndThrownUnauthorizedAreFencedBefore401Handling',
                     'testDefaultPlayKitDeviceCallsAndStillnessAreFencedByFactoryLifetime',
                     'testFreshBoundServiceStillLoadsAdvancedStateWithoutModeInference']:
            self.assertIn(name,source)

    def test_contradictory_child_mode_permanently_retires_shared_read_and_unknown_start(self):
        lifetime=self.read('Core/PlayInteractionLifetime.swift')
        self.assertIn('private var retired = false',lifetime)
        self.assertIn('!retired && current() == context',lifetime)
        self.assertIn('retired = true; onRetired()',lifetime)
        coordinator=self.read('Core/PlayExperienceCoordinator.swift')
        self.assertIn('@ObservationIgnored private var issuedInteractionLifetime',coordinator)
        self.assertIn('issuedInteractionLifetime.identity == context.lifetimeIdentity { return issuedInteractionLifetime }',coordinator)
        self.assertIn('self?.retireChildRead(generation: request)',coordinator)
        retired=coordinator.split('private func retireChildRead(',1)[1].split('private func accepts(',1)[0]
        self.assertIn('generation &+= 1; loadedSession = nil; snapshot = nil',retired)
        self.assertNotIn('pendingThoughtKeys = []',retired)
        self.assertNotIn('recovery.clear',retired)
        advanced=self.read('Core/PlayAdvancedRuntime.swift')
        self.assertIn('blocksReadRebinding: Bool { startOutcomeUnknown || pending != nil',advanced)
        start=advanced.split('public func start() async {',1)[1].split('public var isCurrent',1)[0]
        self.assertLess(start.index('startOutcomeUnknown = true'),start.index('service.startAdvanced'))
        tests=self.read('Tests/CoreTests/PlayReadLifetimeTests.swift')
        for name in ['testContradictoryChildReadRetiresSharedLeaseAndSiblingCommandsBeforeParentReload',
                     'testMissingChildModeRetiresAllIssuedAuthority',
                     'testDispatchedAdvancedStartWithStaleResultRemainsAnUncertainStartBlock']:
            self.assertIn(name,tests)
