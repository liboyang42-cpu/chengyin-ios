#!/usr/bin/env python3
"""Fixed, same-run native diagnostics. Never emits a full-CI completion receipt.

TN2339: compile once per configuration, then select exact XCTest methods.
Only the existing isolated AppUnit helper may archive/ad-hoc-sign a simulator
host. This runner does not copy source, upload artifacts, or use credentials.
"""
import argparse
import base64
import zlib
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
HISTORICAL_BASE_COMMIT = '45b728c7d48cf7969ac864e5693322d45e79394a'
HISTORICAL_BASE_TREE = '440cdc3bbd4a40369e6cb6762eec6306e4aa921d'
PATHS = ('.github/workflows/native-targeted.yml', 'tools/targeted_native_selection.json',
         'tools/run_targeted_native.py', 'tools/tests/test_targeted_native.py')
REPAIR_PATHS = ('App/ProjectNodeImageCrop.swift', 'tools/run138_editor_readiness_contract.json', 'tools/run138_editor_readiness.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', 'tools/run_static_checks.py', 'tools/tests/test_native_static_checks.py')
GROUPS = {'core': ('QuestifyCoreTests', None, 44),
          'app-unit': ('QuestifyAppUnitTests', 'QuestifyAppUnitTests', 14),
          'ui': ('QuestifyUITests', 'Questify', 7)}
BOUND_SOURCES = {'Questify.xcodeproj/project.pbxproj', '.github/workflows/native-ios.yml', 'Questify.xcodeproj/xcshareddata/xcschemes/QuestifyAppUnitTests.xcscheme', 'Package.swift', 'App/MerchantOperationsViews.swift', 'App/ProjectNodeImageCrop.swift', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift', 'App/MerchantOperationsFixtureSupport.swift', 'tools/prepare_simulator_keychain_host.py', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift', 'App/ProfileEditView.swift', 'Config/Base.xcconfig', 'App/MerchantDecorTagEditor.swift', 'Questify.xcodeproj/xcshareddata/xcschemes/Questify.xcscheme', 'App/MerchantOperationsEditor.swift', 'Core/MerchantOperationsReading.swift', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift', 'Core/ProfileEditService.swift', 'Config/AppUnitTests.xcconfig', 'tools/build_simulator_keychain_host.py', 'Tests/CoreTests/ProfileEditTests.swift', 'tools/ci_gates.py', 'Core/ProfileEditCoordinator.swift', 'Core/MerchantDecorTagDraft.swift', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift', 'App/TemplateAuthoringMineView.swift', 'Core/TemplateAuthoringShelf.swift', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'}
FIXED_METHOD_SOURCES = (('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testDuplicateOverLimitHistoricalTagsStayUnchangedOnOpenCancelAndInvalidOwner', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'), ('QuestifyAppUnitTests/MerchantDecorTagPickerTests/testSemicolonTagApplyCancelAndReopenPreserveExactLabels', 'Tests/AppUnitTests/MerchantDecorTagPickerTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedRefreshNeverSurvivesOwnerLeaseABAExpiryOrCancellation', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCachedSnapshotPreparationClearsRevokedScopeBeforeAnotherRequest', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testClonedTransportRejectsLateLeaseReplacementTokenRoleAndErrors', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testCurrent401ExpiresOnlyCurrentOwner', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testGuestDefaultNilRevokedReaderAndReplacementNeverAdoptLease', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLateShelfAndDetailSuccess401ErrorNeverApplyAcrossLifetimeChanges', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testLoadedReadOnlyRefreshSnapshotSurvives503ThenReplacesAndClears', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testNormalFactoryPagedShelfDetailAndEveryWriterRemainOff', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOuterClonesOnlyAdmitExactReadsAndDenyAllAdjacentMutations', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testOwnerConfigurationFactoryDoesNotAlterLocalDraftAndClearsOnLeaseChange', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testSearchedPageElevenLegacyStoryRequiresFreshOwnedDetail', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyAppUnitTests/TemplateShelfReadCompositionTests/testShelfLeaseChangesPreserveUnsavedLocalEditorAndDormantAuthority', 'Tests/AppUnitTests/TemplateShelfReadCompositionTests.swift'), ('QuestifyCoreTests/MerchantDecorTagDraftTests/testHistoricalLabelsRemainByteExactUntilExplicitRemoval', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'), ('QuestifyCoreTests/MerchantDecorTagDraftTests/testSemicolonCustomLabelRemainsOneLiteralTag', 'Tests/CoreTests/MerchantDecorTagDraftTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testAcknowledgedWriteReadbackFailureKeepsLockUntilReadOnlyRetry', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testCancelledReadDoesNotPublishLateServerExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFailedRefreshRetainsSnapshotAndShowsExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testFinalPreWriteReadFailureDoesNotDispatchOrReuseConfirmation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testInitialReadFailureShowsExactServerMessageAndRetryClearsItWithoutWriting', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testLateFailureCannotPublishAfterSameAccountTokenReplacement', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testNewReadClearsPriorExplanationBeforeResponse', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testPrepareFailureKeepsSnapshotAndRequiresANewReview', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testSessionResetClearsPreviouslyDisplayedExplanation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnauthorizedCallbackInvalidatesFailureBeforePresentation', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testUnknownWriteReadbackFailureAndMatchingRetryNeverUnlockOrResend', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/ProfileReadFailureRecoveryTests/testWhitespaceAndNonServerErrorsNeverBecomeUserText', 'Tests/CoreTests/ProfileEditTests.swift'), ('QuestifyCoreTests/TemplateAuthoringHTTPTests/testRefreshSnapshotCannotReplaceHundredRowWritePreflightOrOldReview', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAlreadyCancelledRefreshClearsSnapshotWithoutDispatch', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testAuthContractUnknownAndCancellationFailuresClearRefreshSnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testCachedRefreshLifetimeTransitionsAndABAFenceAllLateResults', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testContinuationAuthAndContractErrorsClearRowsButOverlapRemainsRetryable', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testNewKeywordNeverDisplaysPreviousQuerySnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testOnlyExplicitTransientFailuresRetainSnapshotAndRequireFirstPageRetry', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshAtHundredPageBoundaryRestartsAtOneWithoutPage101', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testRefreshReplacesOverlappingIDsAndValidEmptyClearsSnapshot', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfRefreshSnapshotTests/testSameKeywordNewGenerationRejectsOldSuccessAndError', 'Tests/CoreTests/TemplateAuthoringHTTPTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testActualMiniCounterexamplesSeparatePersonalAndMarketplaceStates', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testAlreadyCancelledRefreshCannotDispatchOrKeepSidecars', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testAuthContractAndCancellationErrorsClearEveryCachedState', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testCanonicalOptionalTextAndMissingFieldsRemainCompatible', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testDisplayMetadataNeverChangesSharedDTOOrAcknowledgesPendingMutation', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testEmptyFirstPageClearsRowsAndDisplayStatesTogether', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testExistingBaseDTOValidationIsNotRelaxedByTolerantDisplayColumns', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testFeedbackIsVerbatimOptionalTextAndNeverAnAction', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMalformedBaseRowsClearStatesWithoutCommittingPartialPage', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMalformedOptionalColumnsNeverInvalidateAnOtherwiseLegalRow', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMarketIdentityLongBoundsAreReadFromOriginalBytesWithoutCoercion', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testMarketplaceMatrixIgnoresPersonalPublishStatus', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testNewKeywordCannotRetainOldStateWhenRequestFails', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testOldSuccessAndErrorCannotOverwriteNewSameIDState', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testOverlappingContinuationCannotPartiallyReplaceOrAppendStates', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testPartialMetadataDecodingDoesNotDropOtherFieldsOrOtherRows', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testPersonalReviewPrecedenceMatchesSourceMatrix', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testSameIDsAndEqualBaseRowsStillReplaceChangedDisplayStates', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testScopeTransitionsABARevocationLeaveAndCancelRetireStates', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyCoreTests/TemplateOwnShelfStateProjectionTests/testTransientRefreshRetainsStatesWithRowsAndRetryReplacesBoth', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testAccountChangeDismissesReviewAndSignoutClearsShelf', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testChineseLargeTextCanCancelReview', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testDefaultDisabledHasNoMutationConfirmation', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testDeleteRequiresSeparateReviewAndSimulationIsLabelled', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testLibraryReviewShowsIdentityAndCancellationDoesNotSubmit', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testOwnedDetailBackAndReopenKeepsStableDestination', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'), ('QuestifyUITests/TemplateOwnShelfFlowTests/testUnknownLocksBothActionsAcrossReopen', 'Tests/AppUITests/TemplateOwnShelfFlowTests.swift'))
METHOD = re.compile(r'(QuestifyCoreTests|QuestifyAppUnitTests|QuestifyUITests)/([A-Za-z][A-Za-z0-9_]*)/(test[A-Za-z0-9_]+)')
SELECTION_CONTRACT_SHA256 = 'ffc171f8f6c7b3097a8edc8d71e0e82fe0b123ac77c68cbc36009e9b83f4b379'
CREATOR_PATHS = ('App/TemplateAuthoringMineView.swift', 'Core/TemplateAuthoringShelf.swift', 'Resources/Localizable.xcstrings', 'Tests/ContractChecks/test_template_shelf_state_projection.py', 'Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift', 'tools/tests/creator_shelf_state_history.py', 'tools/tests/test_creator_shelf_state_history.py', 'tools/tests/creator_shelf_refresh_history.py', 'tools/tests/test_creator_shelf_refresh_history.py', 'tools/tests/test_creator_pending_synthetic_storage_history.py', 'tools/run138_editor_readiness_contract.json', 'tools/run138_editor_readiness.py', 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py', 'App/MerchantBusinessEditor.swift', 'Tests/ContractChecks/test_merchant_review_draft_return.py')
CREATOR_CHANGES_CONTRACT_SHA256 = 'a0a916e50820419681f69c6e21ad048655f5b5d6db628079cc8a44a96ab7e1e9'
HISTORICAL_ALLOWED_CHANGES = ('M	.github/workflows/native-targeted.yml', 'M	tools/targeted_native_selection.json', 'M	tools/run_targeted_native.py', 'M	tools/tests/test_targeted_native.py', 'M	App/TemplateAuthoringMineView.swift', 'M	Core/TemplateAuthoringShelf.swift', 'M	Resources/Localizable.xcstrings', 'A	Tests/ContractChecks/test_template_shelf_state_projection.py', 'A	Tests/CoreTests/TemplateOwnShelfStateProjectionTests.swift', 'A	tools/tests/creator_shelf_state_history.py', 'A	tools/tests/test_creator_shelf_state_history.py', 'M	tools/tests/creator_shelf_refresh_history.py', 'M	tools/tests/test_creator_shelf_refresh_history.py', 'M	tools/tests/test_creator_pending_synthetic_storage_history.py', 'M	tools/run138_editor_readiness_contract.json', 'M	tools/run138_editor_readiness.py', 'M	Tests/ContractChecks/test_profile_read_failure_remote_admission.py', 'M	App/MerchantBusinessEditor.swift', 'M	Tests/ContractChecks/test_merchant_review_draft_return.py')
# This repair is a distinct fifteen-path child of the already-published discovery
# commit. The old nineteen-path image remains historical evidence only.
BASE_COMMIT = '3393ec85076a7a4e246e94e98ddf81f6b73ede2f'
BASE_TREE = '7dd9461bafbe546e1c5ef5eaacc750267b416b2f'
STATIC_REPAIR_PATHS = ('App/ProjectThoughtDefinitionsEditor.swift',
 'App/ProjectEndingConditionPicker.swift',
 'tools/run138_editor_readiness.py',
 'tools/run138_editor_readiness_contract.json',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'tools/club_customer_directory_admission.py',
 'Tests/ContractChecks/test_category_roam_registration.py',
 'tools/tests/test_creator_shelf_state_history.py',
 'tools/tests/test_club_parity_integration_budget.py',
 'tools/tests/test_readiness_contract_parse_cache.py',
 'Tests/ContractChecks/test_global_search_category_recovery.py',
 'Tests/ContractChecks/test_club_customer_directory_remote_admission.py')
ALLOWED_CHANGES = ('M\tApp/ProjectThoughtDefinitionsEditor.swift',
 'M\tApp/ProjectEndingConditionPicker.swift',
 'M\ttools/run138_editor_readiness.py',
 'M\ttools/run138_editor_readiness_contract.json',
 'M\tTests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'M\ttools/club_customer_directory_admission.py',
 'M\tTests/ContractChecks/test_category_roam_registration.py',
 'M\ttools/tests/test_creator_shelf_state_history.py',
 'M\ttools/tests/test_club_parity_integration_budget.py',
 'A\ttools/tests/test_readiness_contract_parse_cache.py',
 'M\ttools/run_targeted_native.py',
 'M\ttools/targeted_native_selection.json',
 'M\ttools/tests/test_targeted_native.py',
 'M\tTests/ContractChecks/test_global_search_category_recovery.py',
 'M\tTests/ContractChecks/test_club_customer_directory_remote_admission.py')
CREATOR_COMMIT = 'b75f7549678caf51a65ec8942b6a6d0c23e887de'
CREATOR_TREE = '6d5a1e4a1486b3e97ed2f1e995ac5194e568bc20'
CREATOR_PARENT_PATHS = ('Questify.xcodeproj/project.pbxproj',
 'Resources/Localizable.xcstrings',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'Tests/ContractChecks/test_template_shelf_state_projection.py',
 'tools/run138_editor_readiness.py',
 'tools/run138_editor_readiness_contract.json',
 'tools/tests/creator_shelf_state_history.py',
 'tools/tests/test_creator_shelf_state_history.py')
CREATOR_PARENT_CHANGES_SHA256 = '3f704cdecbafab177689f9c35ecc52c2c581ad0a963ea6002b098610900952d2'
PARENT_HISTORY_CHANGES = ('M\tApp/ClubGovernanceViews.swift',
 'M\tApp/GlobalSearchView.swift',
 'M\tApp/RoamExperienceComponents.swift',
 'M\tApp/RoamHistoryViews.swift',
 'M\tApp/SearchMapFilterSheet.swift',
 'M\tCore/ClubCustomerHistoryTopicRoute.swift',
 'M\tCore/ClubGovernanceContracts.swift',
 'M\tCore/RoamExperienceMath.swift',
 'M\tCore/SearchMapReading.swift',
 'M\tQuestify.xcodeproj/project.pbxproj',
 'M\tResources/Localizable.xcstrings',
 'A\tTests/AppUnitTests/ClubCustomerKeywordDebounceTests.swift',
 'A\tTests/ContractChecks/test_category_roam_registration.py',
 'A\tTests/ContractChecks/test_club_customer_directory_remote_admission.py',
 'A\tTests/ContractChecks/test_club_customer_keyword_debounce.py',
 'A\tTests/ContractChecks/test_club_customer_permissions.py',
 'A\tTests/ContractChecks/test_global_search_category_recovery.py',
 'M\tTests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'A\tTests/ContractChecks/test_roam_route_replay.py',
 'M\tTests/ContractChecks/test_template_shelf_state_projection.py',
 'A\tTests/CoreTests/ClubCustomerPermissionTests.swift',
 'M\tTests/CoreTests/ClubGovernanceProductionTests.swift',
 'A\tTests/CoreTests/GlobalSearchCategoryRecoveryTests.swift',
 'A\tTests/CoreTests/RoamRouteReplayTests.swift',
 'A\tTests/CoreTests/SearchMapCategoryRecoveryTests.swift',
 'A\tdocs/club-customer-keyword-debounce.md',
 'A\tdocs/club-customer-permissions.md',
 'A\tdocs/global-search-category-recovery.md',
 'A\tdocs/roam-route-replay.md',
 'A\ttools/club_customer_directory_admission.py',
 'M\ttools/run138_editor_readiness.py',
 'M\ttools/run138_editor_readiness_contract.json',
 'M\ttools/tests/creator_shelf_state_history.py',
 'M\ttools/tests/test_creator_shelf_state_history.py')
HISTORICAL_SOURCE_FILES_SHA256 = '80b4ed9152d4acf4f1688962c0cf8a30209fb475405b2f2b247595ca9706a0de'
STATIC_REPAIR_CHANGES_SHA256 = '4ab9e7d7117f44afcbf10f45d89ec2fe7a3f9e6cc0a37d59e5fd42d13ad407c6'
STATIC_DIAGNOSTIC_BASE_BLOBS = {'tools/targeted_native_selection.json': 'd3d549ea73885294a64928274e24196aacb2afca', 'tools/run_targeted_native.py': '720fe9fffccdfaad4744e9dc9a03fa4ae2d0abc1', 'tools/tests/test_targeted_native.py': '5b464736a814967c8ef15276e48b6142ee160683'}

# The new fourteen-path child is an independent layer. The existing v5 constants
# remain the immutable c2af -> 3393 -> b75 -> 45b historical authority.
NATIVE_BASE_COMMIT = 'c2af90a5e11a789ca8dc99eb8daae2c1e84e0700'
NATIVE_BASE_TREE = 'bb341123236a28027becc55e06f35cb294bb718f'
NATIVE_NAME = 'shelf-profile-merchant-creator-navigation-repair-v6'
# Runtime capture avoids self-hash recursion and rejects a different or changed
# runner on disk, even when --source-root names a separate physical view.
NATIVE_IMPLEMENTATION_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
NATIVE_SELECTION_CONTRACT_SHA256 = 'c69ec5ac6b725d463a3a60a02c3aa507799c004e8fa2b93deeebf3fa4efbab0f'
NATIVE_REPAIR_CHANGES_SHA256 = 'd94e6c660b6822ff9c53a64abd9383d2b83f916dfedc8500f2f84857067aa505'
NATIVE_PREIMAGES = {'App/ProjectEditIssueNavigation.swift': ('ff473e0c1695a05f3b983e0675f0e7cd431f5b8258dad01b6d1a73f0911b0a2b',
                                          '5933c8c4b6920c5b74056a7fcbef7f08d314c4d6'),
 'tools/run138_editor_readiness_contract.json': ('d3fedafc9efe917220f4c52cb4c82d742f840a7307546da35e4da130a80d7fdb',
                                                 '7f6a9115079c5aea1842c1ae20851c92f87aaf2b'),
 'tools/run138_editor_readiness.py': ('3854d1af7783eeb72ea095e53a0330d2919c823ab0fd349ae623be4206f1a642',
                                      'bf9e201f5d18c6be8f174782debf54a4cdcd7216'),
 'Tests/ContractChecks/test_category_roam_registration.py': ('0af9b683f459178b3388921bd593dffd5d1ef4e4916df509e464d6620f5fd501',
                                                             'b25603121c22fcc332674b3e4497c4fa325f6eda'),
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': ('402c5c67484ca946d65ddd7c77352d7075445fa69064e9ffeb3f98f896cab470',
                                                                        'e8f664f803c16cd40e361074240c5ceb7a6289ca'),
 'Tests/ContractChecks/test_global_search_category_recovery.py': ('03c1954fe6862fe2d4651384ca6b1b3296382cba7896c6202a82520aadb95b98',
                                                                  'ce0bacb80a0f0776fd574657d169d98f60b5f676'),
 'tools/club_customer_directory_admission.py': ('1878c5c48f1da07910178409ca0b927be695e92a462497dc8cd9aa7d9a929aaf',
                                                '950b01cd6066819b9d1cb3a4e6f20e1d972c4995'),
 'tools/tests/test_readiness_contract_parse_cache.py': ('f65761715213da40330ceca4098ead9f668d9442eff58c1656d89c79aa11ee59',
                                                        'd33a46dc0fd47cf4b7b22a6cc35a0112fd52b497'),
 'tools/tests/test_run138_current_ci_entry.py': ('503ca3cb20863529767cd9fe1558dd2e21faac16eaadb088beda155470022312',
                                                 '271d10fe654b6b0b0e5980cfd0ea20ed3eecc8e9'),
 'Questify.xcodeproj/project.pbxproj': ('a397f1c25ca67e4657846e799d8b1f55f8755d3debc7bc7609dcc6040afc9f50',
                                        '833f6b1e4dc3c22028df18a1c216e2be7125ada9'),
 'tools/run138_current_source_projection.py': ('c0e6a5351bd024bdcbf8d1152bb4e8cb683cc5ff15e370627a14e229a1158727',
                                               'becd4b3230d3fc3ac1cc9f58537f504c277f3ffa')}
NATIVE_DIAGNOSTIC_BASE_BLOBS = {'tools/run_targeted_native.py': '5223156b4e0154bb6d8f37461319ed7f33a8dcee', 'tools/targeted_native_selection.json': '02ae2c0e2092a40257ecf8e9aca83f5776470853', 'tools/tests/test_targeted_native.py': '7ad4998ec65832b7ed5d8d97e806cc748015f970'}
NATIVE_PAYLOAD_PATHS = tuple(NATIVE_PREIMAGES)
NATIVE_PATHS = NATIVE_PAYLOAD_PATHS + tuple(NATIVE_DIAGNOSTIC_BASE_BLOBS)
NATIVE_ALLOWED_CHANGES = tuple('M\t' + path for path in NATIVE_PATHS)

LIMIT = 10 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def read_json(path):
    raw = Path(path).read_bytes()
    require(len(raw) <= LIMIT, 'Oversized JSON evidence')
    return json.loads(raw, object_pairs_hook=unique_object)


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True)


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(encode(value) + '\n')
    temporary.replace(path)



def inverse_reviewed_repair(row, raw):
    require(hashlib.sha256(raw).hexdigest() == row['after_sha256'], 'Changed reviewed repair: ' + row['path'])
    source = raw.decode('utf-8')
    for hunk in reversed(row['hunks']):
        require(source.count(hunk['after']) == 1, 'Missing/duplicate reviewed repair hunk')
        source = source.replace(hunk['after'], hunk['before'], 1)
    restored = source.encode('utf-8')
    require(hashlib.sha256(restored).hexdigest() == row['before_sha256'], 'Repair did not restore complete predecessor')
    require(hashlib.sha1(b'blob ' + str(len(restored)).encode() + b'\0' + restored).hexdigest() == row['before_blob'], 'Repair predecessor differs from reviewed Git blob')
    return restored


def validate_static_repair(selection, root, *, predecessor=None):
    """Authenticate complete current bytes, then restore exactly the published 3393 image.

    This fixed twelve-file layer does not grant any new path to a historical inverse.
    Diagnostic metadata is scope-bound separately to avoid self-hash recursion.
    """
    rows = selection.get('static_repair_changes')
    require(isinstance(rows, list) and all(isinstance(row, dict) for row in rows)
            and [row.get('path') for row in rows] == list(STATIC_REPAIR_PATHS),
            'Missing/reordered static repair payload scope')
    require(hashlib.sha256(encode(rows).encode()).hexdigest() == STATIC_REPAIR_CHANGES_SHA256,
            'Changed independently frozen static repair bindings')
    restored = {}
    for row in rows:
        require(set(row) == {'path', 'status', 'before_sha256', 'before_blob',
                             'after_sha256', 'after_blob', 'hunks'},
                'Unknown static repair binding fields')
        require(row['status'] + '\t' + row['path'] in ALLOWED_CHANGES,
                'Wrong static repair path status')
        path = root / row['path']
        require(not path.is_symlink() and path.is_file()
                and path.resolve().is_relative_to(root.resolve()),
                'Static repair source escaped checkout or is not a regular file')
        raw = historical_source(row['path'], path.read_bytes(), predecessor)
        require(hashlib.sha256(raw).hexdigest() == row['after_sha256'],
                'Changed complete current static repair bytes')
        require(hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest() == row['after_blob'],
                'Changed complete current static repair blob')
        if row['status'] == 'A':
            require(row['before_sha256'] is None and row['before_blob'] is None and row['hunks'] == [],
                    'Added static repair file cannot have a fabricated predecessor')
        else:
            require(row['status'] == 'M' and isinstance(row['hunks'], list) and bool(row['hunks']),
                    'Invalid static repair modification')
            require(all(isinstance(hunk, dict) and set(hunk) == {'before', 'after'}
                        and all(isinstance(hunk[key], str) and hunk[key] for key in ('before', 'after'))
                        for hunk in row['hunks']), 'Invalid static repair inverse hunk')
            restored[row['path']] = inverse_reviewed_repair(row, raw)
    return restored


def verify_static_repair_tree(selection, root, revision, before, *, diagnostic_blobs=None):
    """Bind mode, presence, and Git blobs at the real 3393 tree and current HEAD."""
    paths = tuple(change.split('\t', 1)[1] for change in ALLOWED_CHANGES)
    raw = checked(['git', 'ls-tree', '-z', revision, '--', *paths], root)
    entries = {}
    for entry in raw.split('\0'):
        if not entry:
            continue
        metadata, path = entry.split('\t', 1)
        require(path not in entries, 'Duplicate static repair tree path')
        entries[path] = metadata.split(' ')
    rows = selection['static_repair_changes']
    expected = {row['path']: row['before_blob' if before else 'after_blob']
                for row in rows if not before or row['status'] == 'M'}
    for path, old_blob in STATIC_DIAGNOSTIC_BASE_BLOBS.items():
        if before:
            expected[path] = old_blob
        elif diagnostic_blobs is not None:
            require(set(diagnostic_blobs) == set(STATIC_DIAGNOSTIC_BASE_BLOBS),
                    'Invalid historical diagnostic image scope')
            expected[path] = diagnostic_blobs[path]
        else:
            source = root / path
            require(not source.is_symlink() and source.is_file()
                    and source.resolve().is_relative_to(root.resolve()),
                    'Static diagnostic source escaped checkout or is not a regular file')
            data = source.read_bytes()
            expected[path] = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    require(set(entries) == set(expected), 'Static repair tree has missing or unexpected paths')
    for path, blob in expected.items():
        require(entries[path] == ['100644', 'blob', blob],
                'Static repair tree differs from exact reviewed mode/blob')
    return entries


def restore_creator_inputs(selection, root, *, predecessor=None):
    """Current15 -> exact3393 -> fixed b75 inputs; historical domains stay fixed."""
    parent = validate_static_repair(selection, root, predecessor=predecessor)
    rows = selection.get('creator_parent_changes')
    require(isinstance(rows, list) and all(isinstance(row, dict) for row in rows)
            and [row.get('path') for row in rows] == list(CREATOR_PARENT_PATHS),
            'Missing/reordered creator parent bridge')
    require(hashlib.sha256(encode(rows).encode()).hexdigest() == CREATOR_PARENT_CHANGES_SHA256,
            'Changed independently frozen creator parent bridge')
    restored = {}
    for row in rows:
        require(set(row) == {'path', 'status', 'before_sha256', 'before_blob',
                             'after_sha256', 'after_blob', 'hunks'} and row['status'] == 'M',
                'Invalid creator parent bridge fields/status')
        require(row['path'] in BOUND_SOURCES or row['path'] in CREATOR_PATHS
                or row['path'] in REPAIR_PATHS, 'Creator bridge expanded a historical source domain')
        path = root / row['path']
        require(not path.is_symlink() and path.is_file()
                and path.resolve().is_relative_to(root.resolve()), 'Creator bridge source escaped checkout')
        raw = parent.get(row['path'], historical_source(row['path'], path.read_bytes(), predecessor))
        require(hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest() == row['after_blob'],
                'Changed complete creator parent bridge blob')
        require(isinstance(row['hunks'], list) and bool(row['hunks'])
                and all(isinstance(h, dict) and set(h) == {'before', 'after'}
                        and all(isinstance(h[k], str) and h[k] for k in ('before', 'after'))
                        for h in row['hunks']), 'Invalid creator parent bridge inverse')
        restored[row['path']] = inverse_reviewed_repair(row, raw)
    sources = selection.get('historical_source_files')
    require(isinstance(sources, list) and hashlib.sha256(encode(sources).encode()).hexdigest()
            == HISTORICAL_SOURCE_FILES_SHA256, 'Changed fixed historical source bindings')
    require({row['path'] for row in sources} == BOUND_SOURCES,
            'Changed historical source domain')
    for row in sources:
        raw = restored.get(row['path'], parent.get(row['path'], (root / row['path']).read_bytes()))
        require(hashlib.sha256(raw).hexdigest() == row['sha256'],
                'Historical source digest changed: ' + row['path'])
    return restored


def verify_creator_parent_tree(selection, root, revision, before):
    raw = checked(['git', 'ls-tree', '-z', revision, '--', *CREATOR_PARENT_PATHS], root)
    entries = {}
    for entry in raw.split('\0'):
        if not entry:
            continue
        metadata, path = entry.split('\t', 1)
        require(path not in entries, 'Duplicate creator parent tree path')
        entries[path] = metadata.split(' ')
    require(set(entries) == set(CREATOR_PARENT_PATHS), 'Incomplete creator parent tree scope')
    for row in selection['creator_parent_changes']:
        require(entries[row['path']] == ['100644', 'blob', row['before_blob' if before else 'after_blob']],
                'Creator parent tree differs from exact reviewed mode/blob')
    return entries


def verify_creator_baseline(selection, root):
    # The exact published tree is independently fixed. An added path must be
    # absent from that real tree; no empty-file inverse can stand in for absence.
    raw = checked(['git', 'ls-tree', '-z', HISTORICAL_BASE_TREE, '--', *CREATOR_PATHS], root)
    entries = {}
    for entry in raw.split('\0'):
        if not entry:
            continue
        metadata, path = entry.split('\t', 1)
        require(path not in entries, 'Duplicate creator baseline path')
        entries[path] = metadata.split(' ')
    require(set(entries) <= set(CREATOR_PATHS), 'Unexpected creator baseline path')
    for row in selection['creator_changes']:
        if row['status'] == 'A':
            require(row['path'] not in entries, 'Added creator file already exists in baseline')
        else:
            require(entries.get(row['path']) == ['100644', 'blob', row['before_blob']],
                    'Creator predecessor differs from exact baseline tree')
    return entries


def verify_creator_current_tree(selection, root, head):
    raw = checked(['git', 'ls-tree', '-z', head, '--', *CREATOR_PATHS], root)
    entries = {}
    for entry in raw.split('\0'):
        if not entry:
            continue
        metadata, path = entry.split('\t', 1)
        require(path not in entries, 'Duplicate creator current-tree path')
        entries[path] = metadata.split(' ')
    require(set(entries) == set(CREATOR_PATHS), 'Incomplete creator current-tree scope')
    for row in selection['creator_changes']:
        require(entries[row['path']] == ['100644', 'blob', row['after_blob']],
                'Creator current tree differs from exact reviewed mode/blob')
    return entries


def validate_creator_changes(selection, root, *, predecessor=None):
    published = restore_creator_inputs(selection, root, predecessor=predecessor)
    rows = selection.get('creator_changes')
    require(isinstance(rows, list) and [r.get('path') for r in rows] == list(CREATOR_PATHS),
            'Missing/reordered creator current scope')
    require(hashlib.sha256(encode(rows).encode()).hexdigest() == CREATOR_CHANGES_CONTRACT_SHA256,
            'Changed independently frozen creator bindings')
    restored = {}
    for row in rows:
        require(set(row) == {'path', 'status', 'before_sha256', 'before_blob', 'after_sha256', 'after_blob', 'hunks'},
                'Unknown creator binding fields')
        require(row['status'] + '\t' + row['path'] in HISTORICAL_ALLOWED_CHANGES, 'Wrong creator path status')
        path = root / row['path']
        require(not path.is_symlink() and path.resolve().is_relative_to(root.resolve()), 'Creator source escaped checkout')
        raw = published.get(row['path'], path.read_bytes())
        require(hashlib.sha256(raw).hexdigest() == row['after_sha256'], 'Changed complete current creator bytes')
        require(hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest() == row['after_blob'],
                'Changed complete current creator blob')
        if row['status'] == 'A':
            require(row['before_sha256'] is None and row['before_blob'] is None and row['hunks'] == [],
                    'Added creator file cannot have a fabricated predecessor')
        else:
            require(row['status'] == 'M' and isinstance(row['hunks'], list) and bool(row['hunks']), 'Invalid creator modification')
            restored[row['path']] = inverse_reviewed_repair(row, raw)
    return restored


def validate_reviewed_repairs(selection, root, *, predecessor=None):
    creator = validate_creator_changes(selection, root, predecessor=predecessor)
    repairs = selection.get('reviewed_repairs')
    require(isinstance(repairs, list) and [row.get('path') for row in repairs] == list(REPAIR_PATHS), 'Missing/changed reviewed repair scope')
    restored = {}
    for row in repairs:
        require(set(row) == {'path', 'before_sha256', 'before_blob', 'after_sha256', 'hunks'} and isinstance(row['hunks'], list) and bool(row['hunks']), 'Invalid reviewed repair binding')
        path = root / row['path']
        require(not path.is_symlink() and path.resolve().is_relative_to(root.resolve()), 'Repair escaped checkout')
        restored[row['path']] = inverse_reviewed_repair(row, creator.get(row['path'], path.read_bytes()))
    current = (read_json(root / REPAIR_PATHS[1]) if predecessor is None else
               json.loads(historical_source(REPAIR_PATHS[1], (root / REPAIR_PATHS[1]).read_bytes(), predecessor),
                          object_pairs_hook=unique_object))
    repair_hashes = {row['path']: row['after_sha256'] for row in selection['static_repair_changes']}
    crop = repairs[0]
    require(current['feature_batch_support_sha256'][crop['path']] == crop['after_sha256'], 'Current crop support is not genuine')
    require(current['feature_batch_sources'][crop['path']] == {k: crop[k] for k in ['before_sha256', 'after_sha256', 'hunks']}, 'Missing exact central crop inverse')
    require(current['feature_batch_support_sha256'][repairs[3]['path']] == repair_hashes[repairs[3]['path']], 'Current admission support is not genuine')
    for row in repairs[4:]:
        require(current['followon_support_sha256'][row['path']] == row['after_sha256'], 'Current static support is not genuine')
    pins = re.findall(r"^CONTRACT_SHA256 = '([0-9a-f]{64})'$", historical_source(REPAIR_PATHS[2], (root / REPAIR_PATHS[2]).read_bytes(), predecessor).decode(), re.MULTILINE)
    require(pins == [repair_hashes[repairs[1]['path']]], 'Current readiness pin differs from complete contract')
    return restored


def declared_methods(source, target):
    """Count declarations; bound complete source hashes authenticate Swift syntax."""
    counts, current = {}, None
    for line in source.splitlines():
        cls = re.search(r'\bfinal class (\w+)\s*:\s*XCTestCase', line)
        if cls:
            current = cls.group(1)
        for method in re.finditer(r'\bfunc (test\w+)\s*\(', line):
            if current:
                name = target + '/' + current + '/' + method.group(1)
                counts[name] = counts.get(name, 0) + 1
    return counts


def validate_selection(selection, root, *, predecessor=None):
    require(isinstance(selection, dict) and type(selection.get('version')) is int and selection.get('version') == 1, 'Unsupported selection version')
    require(set(selection) == {'repository', 'groups', 'base_tree', 'base_commit', 'creator_changes', 'branch', 'allowed_changes', 'name', 'version', 'source_files', 'coverage_boundary', 'reviewed_repairs', 'historical_base', 'static_repair_changes', 'creator_base', 'creator_parent_changes', 'historical_source_files'}, 'Unknown fixed selection fields')
    require(selection.get('name') == 'shelf-profile-merchant-creator-unified-repair-v5', 'Unknown fixed selection')
    require(selection.get('base_commit') == BASE_COMMIT and selection.get('base_tree') == BASE_TREE, 'Wrong reviewed base')
    require(selection.get('repository') == 'liboyang42-cpu/chengyin-ios' and selection.get('branch') == 'migration/native-ios', 'Wrong repository or branch')
    require(selection.get('allowed_changes') == list(ALLOWED_CHANGES), 'Changed exact fifteen-path repair boundary')
    require(selection.get('historical_base') == {'base_commit': HISTORICAL_BASE_COMMIT,
            'base_tree': HISTORICAL_BASE_TREE, 'allowed_changes': list(HISTORICAL_ALLOWED_CHANGES)},
            'Changed historical nineteen-path boundary')
    require(selection.get('creator_base') == {'base_commit': CREATOR_COMMIT,
            'base_tree': CREATOR_TREE, 'parent_changes': list(PARENT_HISTORY_CHANGES)},
            'Changed exact published creator-to-parent history')
    sources = selection.get('source_files')
    require(isinstance(sources, list) and all(isinstance(row, dict) and set(row) == {'path', 'sha256'} for row in sources), 'Invalid source bindings')
    hashes = {row['path']: row['sha256'] for row in sources}
    require(len(hashes) == len(sources) and set(hashes) == BOUND_SOURCES, 'Incomplete/duplicate source binding')
    for relative, expected in hashes.items():
        require(re.fullmatch('[a-f0-9]{64}', expected or '') is not None, 'Invalid source digest')
        path = root / relative
        require(not path.is_symlink() and path.resolve().is_relative_to(root.resolve()), 'Source escaped checkout')
        actual = (digest(path) if predecessor is None else
                  hashlib.sha256(historical_source(relative, path.read_bytes(), predecessor)).hexdigest())
        require(actual == expected, 'Source digest changed: ' + relative)
    require(not (root / 'Config/Local.xcconfig').exists(), 'Private local configuration is not allowed')
    rows = selection.get('groups')
    require(isinstance(rows, list) and [r.get('name') for r in rows] == list(GROUPS), 'Missing/reordered test groups')
    for group in rows:
        require(set(group) == {'name', 'kind', 'target', 'scheme', 'methods', 'method_sources'}, 'Unexpected group selection fields')
        target, scheme, count = GROUPS[group['name']]
        require(group.get('target') == target and group.get('scheme') == scheme, 'Wrong test target or scheme')
        require(group.get('kind') == ('swift' if scheme is None else 'xcode'), 'Wrong test runner')
        methods = group.get('methods')
        require(isinstance(methods, list) and len(methods) == count and methods == sorted(set(methods)), 'Empty, duplicate or changed method selection')
        bindings = group.get('method_sources')
        require(isinstance(bindings, list) and all(isinstance(row, dict) and set(row) == {'method', 'source'} for row in bindings), 'Missing exact method/source bindings')
        require([row['method'] for row in bindings] == methods, 'Incomplete, duplicate or reordered method/source bindings')
        require([(row['method'], row['source']) for row in bindings] == [row for row in FIXED_METHOD_SOURCES if row[0].startswith(target + '/')], 'Changed fixed method/source identity')
        prefix = {'core': 'Tests/CoreTests/', 'app-unit': 'Tests/AppUnitTests/', 'ui': 'Tests/AppUITests/'}[group['name']]
        declarations = {}
        for row in bindings:
            path = row['source']
            require(isinstance(path, str) and path in hashes and path.startswith(prefix), 'Unbound or wrong-target method source')
            if path not in declarations:
                declarations[path] = declared_methods((root / path).read_text(), target)
            identifier = row['method']
            require(METHOD.fullmatch(identifier) is not None and identifier.startswith(target + '/'), 'Not an exact method')
            require(declarations[path].get(identifier) == 1, 'Selected method is not uniquely declared in its own bound source')
    validate_reviewed_repairs(selection, root, predecessor=predecessor)
    require(hashlib.sha256(encode(selection).encode()).hexdigest() == SELECTION_CONTRACT_SHA256, 'Fixed selection contract changed')
    return selection


def execute(command, cwd, timeout, capture=False, env=None):
    """Every process tree gets bounded interrupt/terminate/kill cleanup."""
    require(timeout > 0, 'Diagnostic deadline exhausted')
    process = subprocess.Popen([str(x) for x in command], cwd=cwd, start_new_session=True,
                               stdout=subprocess.PIPE if capture else None,
                               stderr=subprocess.PIPE if capture is True else None, env=env)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        for sig, grace in [(signal.SIGINT, 20), (signal.SIGTERM, 10), (signal.SIGKILL, 5)]:
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = process.communicate(timeout=grace)
                break
            except subprocess.TimeoutExpired:
                continue
        else:
            raise RuntimeError('Process tree did not exit within bounded cleanup')
    stdout, stderr = stdout or b'', stderr or b''
    require(len(stdout) <= LIMIT and len(stderr) <= LIMIT, 'Oversized captured command output')
    return (124 if timed_out else process.returncode), stdout


def checked(command, root, timeout=60):
    code, output = execute(command, root, timeout, capture=True)
    require(code == 0, 'Read command failed: ' + str(command[0]))
    return output.decode().strip()


def ensure_creator_commit(root):
    """Read only the one public b75 object when depth-two checkout lacks it."""
    require(CREATOR_COMMIT == 'b75f7549678caf51a65ec8942b6a6d0c23e887de'
            and CREATOR_TREE == '6d5a1e4a1486b3e97ed2f1e995ac5194e568bc20'
            and HISTORICAL_BASE_COMMIT == '45b728c7d48cf7969ac864e5693322d45e79394a',
            'Changed fixed public creator object target')
    try:
        checked(['git', 'cat-file', '-e', CREATOR_COMMIT + '^{commit}'], root)
        checked(['git', 'cat-file', '-e', CREATOR_COMMIT + '^{tree}'], root)
    except ValueError:
        # Deliberately do not inherit tokens, proxies, askpass, SSH, config-count,
        # custom object stores, or HOME credentials into the network subprocess.
        environment = {'PATH': os.environ.get('PATH', os.defpath), 'LANG': 'C',
                       'HOME': '/dev/null', 'GIT_TERMINAL_PROMPT': '0',
                       'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                       'GIT_ASKPASS': '/usr/bin/false', 'SSH_ASKPASS': '/usr/bin/false'}
        code, raw = execute(['git', 'config', '--local', '--includes', '--name-only', '--list'],
                            root, 10, True, env=environment)
        require(code == 0, 'Cannot inspect public-read repository configuration')
        keys = raw.decode().lower().splitlines()
        require(not any(k.startswith(('url.', 'http.', 'credential.', 'include.', 'includeif.'))
                        or k in {'core.askpass', 'extensions.worktreeconfig'} for k in keys),
                'Public creator read rejects credential, redirect, or included configuration')
        command = ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                   '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                   '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                   'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                   'https://github.com/liboyang42-cpu/chengyin-ios.git',
                   'b75f7549678caf51a65ec8942b6a6d0c23e887de']
        code, _ = execute(command, root, 60, True, env=environment)
        require(code == 0, 'Exact public b75 read failed; historical source verification is unavailable')
    raw = checked(['git', 'cat-file', '-p', CREATOR_COMMIT], root)
    headers = raw.split('\n\n', 1)[0].splitlines()
    require([line[5:] for line in headers if line.startswith('tree ')] == [CREATOR_TREE]
            and [line[7:] for line in headers if line.startswith('parent ')] == [HISTORICAL_BASE_COMMIT],
            'Published b75 commit/tree/parent identity differs')


def verify_scope(root, selection):
    head = checked(['git', 'rev-parse', 'HEAD'], root)
    require(re.fullmatch('[a-f0-9]{40}', head) is not None and head == os.environ.get('GITHUB_SHA'), 'Actual HEAD differs from GITHUB_SHA')
    try:
        base_tree = checked(['git', 'rev-parse', BASE_COMMIT + '^{tree}'], root)
        parents = checked(['git', 'rev-list', '--parents', '-n', '1', 'HEAD'], root).split()
    except ValueError as error:
        raise ValueError('Published 3393 repair baseline is unavailable; the exact parent must be present') from error
    require(base_tree == BASE_TREE, 'Published 3393 repair baseline tree differs')
    require(parents == [head, BASE_COMMIT], 'Static repair must have exactly the published 3393 parent')
    changes = checked(['git', 'diff', '--name-status', BASE_COMMIT, head], root).splitlines()
    require(set(changes) == set(ALLOWED_CHANGES) and len(changes) == len(ALLOWED_CHANGES), 'Source changes differ from fifteen exact repair statuses')
    ensure_creator_commit(root)
    require(checked(['git', 'rev-parse', HISTORICAL_BASE_COMMIT + '^{tree}'], root) == HISTORICAL_BASE_TREE, 'Historical baseline tree differs')
    historical = checked(['git', 'diff', '--name-status', HISTORICAL_BASE_COMMIT, CREATOR_COMMIT], root).splitlines()
    require(set(historical) == set(HISTORICAL_ALLOWED_CHANGES) and len(historical) == len(HISTORICAL_ALLOWED_CHANGES),
            'Published b75 history differs from nineteen exact reviewed statuses')
    parent_history = checked(['git', 'diff', '--name-status', CREATOR_COMMIT, BASE_COMMIT], root).splitlines()
    require(set(parent_history) == set(PARENT_HISTORY_CHANGES) and len(parent_history) == len(PARENT_HISTORY_CHANGES),
            'Published creator-to-3393 history differs from its exact statuses')
    verify_creator_parent_tree(selection, root, CREATOR_TREE, before=True)
    verify_creator_parent_tree(selection, root, BASE_TREE, before=False)
    verify_static_repair_tree(selection, root, BASE_TREE, before=True)
    verify_static_repair_tree(selection, root, head, before=False)
    verify_creator_current_tree(selection, root, CREATOR_COMMIT)
    require(not checked(['git', 'status', '--porcelain', '--untracked-files=normal'], root), 'Checkout is not clean')
    validate_selection(selection, root)
    # Both tree witnesses are mandatory before any build and at finalization.
    # Current-byte validation alone stays usable in a history-free checkout.
    verify_creator_baseline(selection, root)
    return {'source_sha': head, 'source_tree': checked(['git', 'rev-parse', 'HEAD^{tree}'], root),
            'base_commit': BASE_COMMIT, 'base_tree': BASE_TREE,
            'historical_base_commit': HISTORICAL_BASE_COMMIT,
            'historical_base_tree': HISTORICAL_BASE_TREE,
            'creator_base_commit': CREATOR_COMMIT, 'creator_base_tree': CREATOR_TREE}


def blob_id(raw):
    return hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()


PORTABLE_BASE_COMMIT = 'f04f1cab7ef92afcafcdbde411dde71b4a605820'
PORTABLE_BASE_TREE = '75569d4e6d8ed5c23ee9865164a8d01c2e346116'
PORTABLE_PATHS = ('tools/run_targeted_native.py',
 'tools/targeted_native_selection.json',
 'tools/tests/test_targeted_native.py',
 'tools/tests/test_run138_current_ci_entry.py')
PORTABLE_BEFORE_BLOBS = {'tools/run_targeted_native.py': '2267a55673f9b73c07d9c8b25376ddc7bcc215b2',
 'tools/targeted_native_selection.json': '96061e6ad4fdad7dfc3a7ba21d7812da8ac4d3ca',
 'tools/tests/test_targeted_native.py': '6293c976bb333c5b25a667d6d218ec1cba734930',
 'tools/tests/test_run138_current_ci_entry.py': '075aff96a46321527451fc3c358d109ff023fe0d'}
PORTABLE_LAYER = {'version': 1,
 'name': 'native-diagnostic-source-portability-v7',
 'base_commit': 'f04f1cab7ef92afcafcdbde411dde71b4a605820',
 'base_tree': '75569d4e6d8ed5c23ee9865164a8d01c2e346116',
 'allowed_changes': ['M\ttools/run_targeted_native.py',
                     'M\ttools/targeted_native_selection.json',
                     'M\ttools/tests/test_targeted_native.py',
                     'M\ttools/tests/test_run138_current_ci_entry.py'],
 'before_blobs': {'tools/run_targeted_native.py': '2267a55673f9b73c07d9c8b25376ddc7bcc215b2',
                  'tools/targeted_native_selection.json': '96061e6ad4fdad7dfc3a7ba21d7812da8ac4d3ca',
                  'tools/tests/test_targeted_native.py': '6293c976bb333c5b25a667d6d218ec1cba734930',
                  'tools/tests/test_run138_current_ci_entry.py': '075aff96a46321527451fc3c358d109ff023fe0d'},
 'source_changes': {'tools/tests/test_run138_current_ci_entry.py': {'path': 'tools/tests/test_run138_current_ci_entry.py',
                                                                    'status': 'M',
                                                                    'before_sha256': '08766906799a3069dea21b563d6072fff81e543bb14ddc6938a9b5e043529367',
                                                                    'before_blob': '075aff96a46321527451fc3c358d109ff023fe0d',
                                                                    'after_sha256': '2ee4f0dac630e697d10d06595a1ac257d50d49f9ef421ef9f0c1549e5f516f08',
                                                                    'after_blob': '57ae77dbe8d00c07c3505016a9f0d361bf663a2a',
                                                                    'hunks': [{'before': '                '
                                                                                         'raw = '
                                                                                         'file.read_bytes()\n'
                                                                                         '                '
                                                                                         'alternative = '
                                                                                         "raw.replace(b'WeChatApp\\\\u0041uth', "
                                                                                         "b'WeChat\\\\u0041ppAuth')\n"
                                                                                         '                '
                                                                                         'self.assertNotEqual(alternative, '
                                                                                         'raw)\n'
                                                                                         '                '
                                                                                         'self.assertEqual(json.loads(alternative), '
                                                                                         'json.loads(raw))\n',
                                                                               'after': '                raw '
                                                                                        '= '
                                                                                        'file.read_bytes()\n'
                                                                                        '                '
                                                                                        'alternative = '
                                                                                        "raw.replace(b'WeChatApp\\\\u0041uth', "
                                                                                        "b'WeChat\\\\u0041ppAuth')\n"
                                                                                        '                if '
                                                                                        'relative == '
                                                                                        "'tools/run138_editor_readiness_contract.json':\n"
                                                                                        '                    '
                                                                                        'alternative = '
                                                                                        "raw.replace(b'WeChatAppAuth', "
                                                                                        "b'WeChatApp\\\\u0041uth', "
                                                                                        '1)\n'
                                                                                        '                '
                                                                                        'self.assertNotEqual(alternative, '
                                                                                        'raw)\n'
                                                                                        '                '
                                                                                        'self.assertEqual(json.loads(alternative), '
                                                                                        'json.loads(raw))\n'}]}}}
PORTABLE_PRE_SELECTION_SHA256 = 'd7de3664b2c70ddf52d327dcf4ad539630d3b2315abc8e19a63c6fdcd52effe5'
PORTABLE_SELECTION_SHA256 = 'c0ba9258fa046a0d5fc7acbf632deeedd9797619c4b1d8d07c632105ff00506d'
PORTABLE_SELECTION_RAW_SHA256 = '6d7d4bdc8d71278e11b0086fb83bc95255bb0e3c31659f417cf73a9c372e6c2f'
PORTABLE_TEST_SHA256 = '37b8a210e51c0c062964fedfd146313e53895fb255f4465db3eef0f0aaded993'
PORTABLE_SOURCE_ROWS = {'tools/tests/test_run138_current_ci_entry.py': {'path': 'tools/tests/test_run138_current_ci_entry.py',
                                                 'status': 'M',
                                                 'before_sha256': '08766906799a3069dea21b563d6072fff81e543bb14ddc6938a9b5e043529367',
                                                 'before_blob': '075aff96a46321527451fc3c358d109ff023fe0d',
                                                 'after_sha256': '2ee4f0dac630e697d10d06595a1ac257d50d49f9ef421ef9f0c1549e5f516f08',
                                                 'after_blob': '57ae77dbe8d00c07c3505016a9f0d361bf663a2a',
                                                 'hunks': [{'before': '                raw = '
                                                                      'file.read_bytes()\n'
                                                                      '                alternative = '
                                                                      "raw.replace(b'WeChatApp\\\\u0041uth', "
                                                                      "b'WeChat\\\\u0041ppAuth')\n"
                                                                      '                '
                                                                      'self.assertNotEqual(alternative, '
                                                                      'raw)\n'
                                                                      '                '
                                                                      'self.assertEqual(json.loads(alternative), '
                                                                      'json.loads(raw))\n',
                                                            'after': '                raw = '
                                                                     'file.read_bytes()\n'
                                                                     '                alternative = '
                                                                     "raw.replace(b'WeChatApp\\\\u0041uth', "
                                                                     "b'WeChat\\\\u0041ppAuth')\n"
                                                                     '                if relative == '
                                                                     "'tools/run138_editor_readiness_contract.json':\n"
                                                                     '                    alternative = '
                                                                     "raw.replace(b'WeChatAppAuth', "
                                                                     "b'WeChatApp\\\\u0041uth', 1)\n"
                                                                     '                '
                                                                     'self.assertNotEqual(alternative, raw)\n'
                                                                     '                '
                                                                     'self.assertEqual(json.loads(alternative), '
                                                                     'json.loads(raw))\n'}]}}


# Exact published7b description initialization repair; older layers stay independent.
DESCRIPTION_BASE_COMMIT = '7b882973b47dee412b9f0a95e9ad030798ab2ea5'
DESCRIPTION_BASE_TREE = '0b5e932191ef736a9a780438087b8476c5b2aae9'
DESCRIPTION_PATHS = ('App/ProjectEditNodeDescriptionField.swift',
 'tools/run138_editor_readiness_contract.json',
 'tools/run138_editor_readiness.py',
 'Tests/ContractChecks/test_category_roam_registration.py',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'Tests/ContractChecks/test_global_search_category_recovery.py',
 'tools/club_customer_directory_admission.py',
 'tools/tests/test_readiness_contract_parse_cache.py',
 'tools/run_targeted_native.py',
 'tools/targeted_native_selection.json',
 'tools/tests/test_targeted_native.py')
DESCRIPTION_PAYLOAD_PATHS = ('App/ProjectEditNodeDescriptionField.swift',
 'tools/run138_editor_readiness_contract.json',
 'tools/run138_editor_readiness.py',
 'Tests/ContractChecks/test_category_roam_registration.py',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py',
 'Tests/ContractChecks/test_global_search_category_recovery.py',
 'tools/club_customer_directory_admission.py',
 'tools/tests/test_readiness_contract_parse_cache.py')
DESCRIPTION_DIAGNOSTIC_PATHS = ('tools/run_targeted_native.py',
 'tools/targeted_native_selection.json',
 'tools/tests/test_targeted_native.py')
DESCRIPTION_BEFORE_BLOBS = {'App/ProjectEditNodeDescriptionField.swift': '4a251eda154fedd38f0184ca0807474d9d8ccaa5',
 'tools/run138_editor_readiness_contract.json': '8646e5b07dea1cf9bb3880b427fa26af08fce288',
 'tools/run138_editor_readiness.py': '9be0b046c4799542785266ce2c9b9308da3db992',
 'Tests/ContractChecks/test_category_roam_registration.py': 'd7ad83faf07d35199193f12950a554c5631fcaa7',
 'Tests/ContractChecks/test_profile_read_failure_remote_admission.py': 'd9c5c2b18d0df6c35b3e3ab0e8830350bf3f3592',
 'Tests/ContractChecks/test_global_search_category_recovery.py': '11ae7e2c82c8b8574e65212d5dc9e1e21ff2f712',
 'tools/club_customer_directory_admission.py': '6d15aa94e878a366ba56b48676521bc3a50e27c1',
 'tools/tests/test_readiness_contract_parse_cache.py': '160a9f2cbbd66ad0af3d0968b3a5ca6a13f67ed0',
 'tools/run_targeted_native.py': '78007b893d007c3399a9db5b8328102fc36ee6f1',
 'tools/targeted_native_selection.json': 'f0633a67c5824460d37e6ac1cdaa9f68a9b61ae1',
 'tools/tests/test_targeted_native.py': '91937ee7b9690b80de047ac24bf0748bf95c50e7'}
DESCRIPTION_PORTABLE_BEFORE_BLOBS = {'tools/run_targeted_native.py': '78007b893d007c3399a9db5b8328102fc36ee6f1',
 'tools/targeted_native_selection.json': 'f0633a67c5824460d37e6ac1cdaa9f68a9b61ae1',
 'tools/tests/test_targeted_native.py': '91937ee7b9690b80de047ac24bf0748bf95c50e7',
 'tools/tests/test_run138_current_ci_entry.py': '57ae77dbe8d00c07c3505016a9f0d361bf663a2a'}
DESCRIPTION_REPAIR_CHANGES_SHA256 = '7040723830db228696e8dd06f25fd9a9c47566ca743865de1f01cb1be2d9d470'
DESCRIPTION_PRE_SELECTION_SHA256 = '6d7d4bdc8d71278e11b0086fb83bc95255bb0e3c31659f417cf73a9c372e6c2f'
DESCRIPTION_SELECTION_SHA256 = '3b5aeaa59eb51ca768d4ec6c1b56e6e20b94eaefd42f3773ef3a25ed9acf5f87'
DESCRIPTION_SELECTION_RAW_SHA256 = '9d910be0f7ada355666e646b471917adaed0074c6e05e2295e72c9c8019d7d6f'
DESCRIPTION_TEST_SHA256 = 'cf610cfd2794c66d486d67c73ddaba93d34cb5f688635dec28b754dce01834fc'
DESCRIPTION_LAYER = json.loads(zlib.decompress(base64.b85decode(
    'c-ri}2fO0NvNrlx7A6c~7%K;pbIzG<BNRa(B%wft-+o)H1uIUlXS~lj-*d-d2<qzU>I!dFm&EZmR#CLAC@}n-RcE64+aLe=t@fvt'
    '()Hh)hPDuSD<{ZST@%EtX!3@vTe7C+Wl<5nm|I!0e*5fPZfTlg{%+VRj8cpU251Ijh^!#1qG>X`rdkHeTVEEYrvAWyFZ%xRs;+2S'
    '=I@!O;hDL}FU{XA@FByqmN?UlJ!5F>3XGh|Cb-7o?FR<yh9=31c%6`uSXr?R=gms9M1~bsvT6PpotdI>tiqTgYw+_IEQ!3f5sm$w'
    '!sB9j#pW2^HZ5%>8jK)=%Pi;e_cK0TZ(ZlTPV`=sjLsUS2<GJH;+t_msEoxLGtmOOssfp8-d^$MTd)8H@Zxarc7tB<@BzucKL5tC'
    '4j0;LC0oD!@f*oe6hf0IhmnFPVlcwd62#KDNV5WjLL^PG93ry#Z%+d)LlnU<hyz!k2u#DGM4|*svm^y!C<Re~AVv~A&LJ!-(qNb%'
    'volpQEtzLHQPRM^abOdG)*gTR=IQ}&6a)csG%A3<c@(8-mKHdiqfmr`Aw=R)LKF!J29x}dl>Yclf(R6436jSt1j7hOKuM8cd6*Yi'
    'mX-*Lr8xp-#TOL6Da}8AqhT755J`?EXo#aAL4+`p<q?dNAQGcEiN<*x63O4rpMO)?l_NUg*(k%ZDqAwE$cL*Pgbh(=Wh1<y!2CM9'
    'S2Xseksp6!B@5`GBR*#f2%d!nk;ZTl;|W5*2$B^LjD`^y#wY@(A%x&K909Z*$C+~$!3i*uhfo3GNCIJLN2(Y`OC(JrFvg)c0aFlA'
    'U6>YVp5S;IB5+AUcmx+Ap5=IwgmBc+h3B0F1TjDu76lf@F-a5zl#(Er!gv;<fDlMbpaqKO*+(UM9C+u2AW#WsSrnrw7z_|mk*5)e'
    '6k!5~F^D56j-z;rMJb#@0fT@QfyD$01?!_FM09wW+v@U#d;rmhr$1o-r7xyt8@%`sdw6^id3fB&`v+eh-~XxJMk(OSr;X`~yB8O#'
    'z@>iK8mz91LZ4M^@ym<7d>(H-4thZ%^1$*-Rog0}FcXFJ9_SOeAj?{;|HV~bY)hg7k95v|s&`@i^n$D(U&S{#wLW0+{FkGs)*P_-'
    'cfyZpv6c<C?6(@Qi#KY`6RZSFEP_Fjh>Ng@U;@wuibElc7kLb(Imbp3{=Hfg5=%+~OmR2_0n4T^RKkFvL$rWXyg-u@#9@#iKpb#('
    'Fe}g~3UrEP2?U351QD@!YE2OsA>teaJR=M963uZaMFAoR3HSqSLX^ad2t|FM)-;b0G;j?lFino7fN>(IqtX<~a}W=PaXbv{3h29|'
    '?zF&?EJ9P@6)lPg&k^5H>%X4F|M~InKYv{EfByEz!||pTf4=6~`R>o3w#Gky`}|D*<@P+1|5?ZLiu_eR4&DDeYx?o|<?{+3=l<7>'
    ';ZOAiTQ64rdfI>JRDPLPakzXYcD}v*>l^Oo#dmirefsj9(v?ip7VGRro;@PEyS@RP5<sk`V1eXGOe6>b!yrr)P@pj&gbOG^q7;B1'
    'ya-HFz+sx82*C+kz~B%X1?q5@?%&k(U#M>HX6^tN3#8FBL{n6)cT1)z5SmGX=750<Bu<K8%?Qj9;GF~_HiWT+gs~J#iL5A6u!Lj0'
    'B!W1J0M7)G2yvbG?S}l{kohn3ApbKmf3N6InShf+e4K^cQzd=>$cc#2h{W=OAPNBa5d@5r2rSSLM8O<DXF&EGi_wsXLm>J%c#{+b'
    '9HUtRKxT}i*cT%B`Gn|^C7dGxGz0Pn8o|*xiim;}ga{00VG73`?8`zB54Zpd0>T|mk{E`;uq4p90Fr<YSTe-NSItL8oE^G;@Jbng'
    'E+Ht!u_Vc3C@YCP*mi<OfW1i)1kwwN6TwUz4mJg+aEJhD1cwU18Ub%$gT7)1|4(cQK>|=g;s`~c0P;`}4iExK0T7Ri94gT$06Y+a'
    'Ap*{#fGG~62?Y2v>bgfbz$O2qTk_sazLEETC5is3WFVRYNfQYpz+)o<OQ1MU0<Z+U7)P@dk05|ifuJ#vV&H&rihvwnf`|a9p&|^w'
    'l+2H(@sCpj-$ZaCLLw9m!;nOB5()Gl77$7jFrY9b@Lx1=njjkmfra8FNRlX^CoD*W3GnR?>B(z$mg0V^83H4SoMx-Mc;^KnfR!Q='
    'BET>X3!Dh>B=F)OkwRdg!W>P3SO!vH;MaiX6FC;Ad5EGh5{H0;6^XAI&;J`6g_1N2X2cK_1+EJR?i^SO4`hG?O{Eb61%ksU5kW!r'
    'O(7s4(Uha#6op8<Bv91<zK!}?<aw+>@W81!1vhgJGC;=3pG0OZn~rqud<ahBBk?2<Ghjymf~F}B;~>m=1B(&@ybFfII01YhM$nW*'
    'P{7EY1cag?4ibMzCf_fhJu*Xyq`+Z3DS`hH5=@eU6MR{T<9UEGK+XkF2#lc|#{#dyi4<_ZfPWF=5fFy}ci(Vtg)0l4D+ie;2HH>a'
    'zw>t(OHv}w5+V-^5)6|dw-k`8mnEJ5BuTvTCjd7H;0Hi0lz;$74B<eFV2BdG8G`<g?hTLvOCvl90vim$Gz!rqPm2Ts^ie<&2nR|F'
    'GGtr;4i3TyU_Lw!gE&P)IB<9@B>eB%oA-tzXuSEmQ)Lbtnr(?rSxsU0Usl2s7~(OIadWT$mcmMs00IAjIe=KCL3D&58sjmT1a6BX'
    'F&ZFO4#!bKgb)rVSq!D|AM+jGs&+r}L4q_x5CO`904xEzfdPX6%LcBBVmYuyz)kTq4{!l+SvUgR2f)Y#OA4?+i6X-Cj|tuRL;d_e'
    'A_9<=01VDUPQ4Il7Y~pZ1!e$B$piQUk{F3XfM%isSUdO*0f_>H5E#%4fKh=nc_D%qrKrDmwDGNCl!T%r#~}!XfPgQs6i0y62H`o1'
    'a&!>*eS{DkZr>N9P>@M+0xBXH$MLL#?<AT8;Zl@<;Y*?ba}o}L+zW&VP5=&oCUKhO05(Th2t+gCT``L0MBoT8g2zY)03sxXBLu;V'
    '2v2jsgeieV1rB7l9~7e~k|!u&FaX+PhzQa$N`h(9Q8E&!07pU~R|ClbO0yuCf>mKS3jBj0foP3EAa;LPj4IWd)m$xC@20w?MxE&t'
    'Q(&@(*u$JP=ZegId7Rzf1Y6=~m@6=50$;A!m~%=M{y^Z%T-*ur4CsnK@TZz-)Vu9eru$6l)6Z7)KK-e78ohQV$J~fJR6o>MN#0oi'
    'ubaQ?j~VCt6D~(xKE1ZJ|Aq{Hwvza-$lynf?eP@rTNZ{>BuGCokp+<-gd>Ruy39KWQW6A^ln5{i@-j$}-dotuy3cnOCXiqZDzOqo'
    '3MdZK&e@Ixz%35EBglMk;29-g%H#(Y_OpKMLkn|1<aS_l9t7EZ44}Wafg^nYeq1yjH1)xniw}~a9YpoPL8=dJ<Uvw2&G_=Cn#$Hn'
    'osOfE`BJ@*Yd71a`gPxV1b7dgKtcWw#3PWX<eU@X1kQ1&D1tywb0iKjLs$?nfZq^+PaQUa?*}>vVlmkKOsbnJG}<Gkn*-_(-Y|`P'
    'zLRsvJ8B8NHj#g05dy&xK!iB(uRO>tM3kdwkTg>QfZo7$k|-}BAV_f(2^<_iH6klv0xl5X9Y_;k^2ZkO7FQVJ+6EbkUsQQb5d9mc'
    'RvUPT#U2cH`}yHhT~m2h)l`{hmEQ$hS7aytJ@B?+h^qB)i#ng4PETGGd6}nc7+KYA%Y3B#`N7aM>*?a#)K8AW?|k*}`$H#J%`?qZ'
    'xA?}VI81%$nm&LEzjjr>lF_&FcmBwL%ayFoz&0Hn|MSPgZ3^ezYw8bRmDi8Ks0YXQn&;;NxGX(><Zxh$mcQ9<<V)2@ADJ6=nNq#k'
    '>vjSUr|Y-vTr*W_Gu2$`aT)h7>VWA!7}aaH!3tiCI%ad7OuN*)uIWDR{Kw04f`<q9LrPH|aO6Rs?@dR<cfmfY!h;U5yC{ecqGLJE'
    'I{~~mP0jfI+C~86ZJXkk*F<m2{`?@Y7V9kjCbciJC9Z&E-f;11<D4NtCjNG#(fv@YKq)fUBWdCHmAn&$JIgo{c0~H{6h;1c`1BBZ'
    '9REC>sQjyfe<$9n?@@r{Y)+9uekMEs7XU{duH^)E7JlL#?0{@OsE(8$IF?@m4i!=O6>=4KItZj--q<UPf3cIylf0P6^C17@6yK8n'
    '&0PQs4SatmZydbax5pIqs&$S~{^fo9<KqME{~HGVvDw1UX8V0}1&-1=!24fiu<(DwVE_1vD+kg66N7z!eDUR)p#uHCUibOoQByuY'
    'z)#GWisl@Df{gF0u;9<%0RJ!jZnK?xdCixn7#9GS0Xm;<2ckDoJ~6^;wrcsE`L6K^2J-8v&N-|4@YwnDa4$y!$pE<;x*-E`IwPDo'
    '_>r3bON;&R+yB-w-`8E7e;(1^3*U0pLV)y?edMlr&y)>u#mcJra6Qa%S{fg(`0_~Xk#V4bH>-a#PiJGFG9*?N9-h#K;}4ysyu0W>'
    '&hWop7?B|Yg;yPj^B5!?SR-4&RXV)$2rIo@z}2>&Ox79kbx;1vgFk!c8~>_ieYl1{J}Th+%d-3yFK;*Y>I1H$fN*c-?-=(Bi9Ty='
    'w$#Zq`Z)lti@9nu*Zx&j`cj2~Y=1z1pU&f+8Z91lS^da7|Ap24EwlV(>-xyas+zHK+6$fVe{UOOfWiV!1O@~o(NI~10Z|6{BkRgQ'
    ';5}Qnk>Az)JI;RwFkgfI@0SHap00=>xwx_QaAWJ!3!XGZV4hd<)aQAxGy<OF6+64J{1tEftEKXtwf@(Z`msk&*&xSOt;fVo6}OLG'
    '<g=4`J3hm4F5)!}cP;`ipRw}Q6W+_EZ`{a}(|wgUzIDHE%31F{Ft6$RFM=rQ&Wl^}`F)psz3|B;UtfR2Dc|^iqW+Wof9$CL4H4hg'
    '^^u5vb`f7IZQRoKuVTrUwCkxp({2p@^XX+>?$cjR(cnqTpCZ(Ai_%j7du(YIzEU*!j*od6I-Y#+Ymf7l3*Ic`<w~Be`e-q)f%n^$'
    'T`N{k@c9uZyj<JYN-h5@q<owG(~qCLfBHI?|CR*bD(Z8pbWg0`pqO5>*=Tn^NSyu#bo<86ybl9cqx;V%No22CJjYu6oH1=(*9_|}'
    'g)cLZ8(qm=qv$hUeZP-SLvLbum6g5KsGk<c*H`*KywH~$|EGE@B9q*M(=Ho+v5OC{Z=raZbUzlEL6~@pHvgSdmTzF%UsSaIu%_tH'
    '{^1_YH$+~zM~BSca0MSQ1B~CP;(U5_Hu4E<>(91?esX-sYqtWZ{%mvaBh~Av3n2HO8{ZD;U)C!A>3!Yi$ql}5BLDQ(Q(hPRlAV9t'
    'LjE;2KK-)Z@=xc#&L67QSC!&t8@N7Jil6P@`?^y6`CGo)XtbZoU5@Mg^ds%qfZ)6P177Uy_o;rvmOsB~>VNeIB%+^Q9nIdV#*aF~'
    'JRR{qne%r^{f)K0Q-v4R8b=j=e1X5rcl-^<_RCcBANIvK4E*eA^7k0{(MIL#2K;23^7nZ8e$Sf2#m{!Ey;Os*w<<U@{cNwyr;n8X'
    '5rzH#+W-G+|No5kztPEi^8--Md}+uOd-aMFd|rVdL6n}#Ro||0|M4DReEPRa*f*5)jE(*|m;WY{?<e|YXBZz+|EFgf9}@e!XB-at'
    'b9Util;=$??%S&Ki;HR>PxZ|z+YhVTch~jbTh^zasSJKkxqhx(`yuteTfY53+y4CR->YxE1;u~<_5&5KJK}$x!~Nnq=WAj9`P;9p'
    'dtQ<JTeJRWHK&g)?}v&|?=A4xu<+>@R|P-vfj@ST|L31Ser9;R_Psb?>;JDg-v5dU|M+@-{Dk-8RsCCw`f!{6)*0_F+p%AC^81yo'
    '`bTT}!CiY}OyAkWU%1YXUH`v!D*N91zc{D;hTMO}!TDQB{-T5QZ`!~wXrg=T>c7=g_w~T=Yr5>dP5(#Q?!IBU|3V|)dv*JuHSc|)'
    '?$a-9*8B7ojsE4D@#&wnPk%L#|H^jiZ%*=0)aKvO8stN*`7x#W^h-Oke|T%ZyMaI1u>H$-?$fVs=zc@~yZzmNUzL8Q;rrjzlRrL&'
    '$hQR0xwY(z^Ta#T|KY;lAi|%%U*#*|`$yUN7r1#Z_#eGV=z0JLNT^PIf_XLSUAx$0HS9XoiZzzNfB-=J^ykkWvft%n+R|gI^A#1U'
    'Kx-JrdGaB{ICA;KFi!D|VLtuw^lU2|kalXJU!2eVFD3CNU%r*bKE7e-uI$h7=j8&P^MXgKeA^ZCj7uMd@`y~Yl{x1tQ5DRsY|Z_T'
    't9uE$Ue5A(SKAZnbDk0*u*Uv2)ng9x`2on`O49`DaGUPA_1ke$&iSL`o(#vonWEtTZt?bIXUD6aa_44LK<z2N|Mb@##eaVK{K*)f'
    'zj)vH@hbVc(z)aI+M`?k-4Jz=b-dzBX*|gRBw(T;vEY@dv+BzR$NyVh@gJ+xN3HQs&71ER=3Mak7vIC+$OpW6RLl<z2e5Ko%*SW4'
    '|G6g?PE%RtW;`zg@H^|dwvRv6Dql31U2BA3Hpde^`l27MBL8uFoWOHEp8t@QYm|&Ug?{$tO2dz>W6ykYd!04SZ?(REER7Fu5_sEg'
    'dGkbH5$F%zZSWk9!_G;=vz<JjIb2T|%-eoGSBt;AUeOy??lJd|SG~ke6S1sbJqmNJ)B3ML>Z3lM&o6HSdetERl_KNcp6R*t`1QH&'
    'ius=U_e0zV^!|4@_rG*6A9wh_mVra=onQI&H(xxv-&eA1_v-ccdw=UuzX90$GdG^>{dFU~?i`|lg@|8(6BSrR@f%=He_|Dwe9)oi'
    '{|^+V*|7B2k-*M@PacQ0j~nw9QT02tzbWE7Z{L@$L+d}#U!Nbo(?|FswtgtHd*m*F7cZnHudaQN&f~QS?DNAxk+~Nl{U5tm;ia_x'
    '$qftNw$b}t3-<)$Dm+K_kAnEZQTUTU9f^E#SO6i%^gqw?`GF1uzC6m}C2)~s!?d1Z?OpEeMykf-+l_G!z{baCVx)70QvEf!SJ<b)'
    '-yWH(XJ3!|b-?#o4WD=aKYxTBy?(-<e*yb^TqUs6Pfv`s!CE>%As=D!BbVc9Db1u)og9TbCoK-g*CC(2EHp6d>kP~P=`r&N0lm?U'
    'r=&*skNk%mqM*MX3%`Is;Mq$!XjQ&KRR??fq0bKvlTQPIGEq?A>PoH|jzjn=+}CJDR7~+zW3p_D4=K|W4M%lyhM^gLpp*a%%i{J8'
    '#C(~EIA->hX7}$PpliVXD){*T^1QoM_Iudp>&aWpvB%f&r|mqhi4~rzR3LoXz}~L0|0$z*ScxmnseC*_d{*6G)#WjD1(JCDiGi2c'
    '=Xy^yh=9(6Xg+wZ#C2`p<1aFB)%%qqtIMk^$i8#|PnhINN;U!Zdb;u^^K0={wH%jzJU=Hhx3-7x;;n1Mi#@!!{rkNia~O55d&THA'
    'OS^sQ{QdGHuw|OE0UtSE8lv(Tp)BnxhUaespWin>-m;s|4?qm84zvL*=V{hAdibi&_~DJzH|abo8(8NPcW*oHpN>SIq;QWg?>+VF'
    '9sEiG;+7Kw#vf}yPuld_x4(IYhpnpDs=%G)7s3ANnb6-2^j8|U#P{dp{7Z5lhxzM{KSk<$NO*q_!Y#OcSR}Yf;w2<lX@aeYFQxIE'
    'FMa519tV80Qc=}d;f(@4XD)&)NdP%J55-yC_3FCkH<rLA%YyTe!F%+7>gjz30h)scpE&t1B+rjCy+gMz8=Iak`SDCR>c~0%gg~$K'
    'KD_j8XY~(OfnKETZ)3*C_qkjpY(CxK@?o|W_%IK1GMqOo-gNM>S>_vMwx=BGD?#n9kRNjM*H_v3-W^&E<?1i^n;@T5@IyXD<L@x{'
    'B4K>b-jClx_5%#w?kEF^lwkAETz=d+@|AwwkM5fK>3gAG$AJ&SPUag6dz$0J5cBu?iyp=BhMmBx1B4HF`=<ZA-O=@8whxff-(m7a'
    '<he(IZy~vtk?L=GhUaupcD`NRo-qHWxOEfP_bXhl`_{gS^-{niS+6kOx4Qx5)ylS54n!n?O#g-ZhQE{IzOQOMPIo)Gdso!Du^4&V'
    'Eqklr@w})5%;*Tge7JYg{_{tqeaCz2n*NjC`w0|&tVT~B8!)#0RW9d;T+JO--sbqw*#7o*zcZl^6QpO`xdW(g)Q7LLf8TySJVd>M'
    '+M6oeCVOpAX<G*2VJ50JVCl^<@>3hY=O^8B4vj$?v$}2Q{b>0L%|9v~J4KwAi2RQat9;I7Z<)NFmF&KfHQb`rTO|HMYEN7DU2pT|'
    '*fQ{1_J8BSHQy{?yt)zjJ6FDVROmndZNP6mL6oE<oToV$SO`xMlElIYi;5D#ArwS$0*@d(C(;D;{t2Q#`>Po5pCC%}IFE2JB|w5i'
    '@F>oqBFb`*NKq(+;t(gH5{iHLjNYHU)8xY^h+b=bPig<l=g;0!Vx2Xv!5;ys%=b#izu?KCul43vGWQE^uKrO~{TshT`7NylTgf9R'
    '!UBB}1RzJ2gMoUm0xpsWk3u3)KMJC;4}QJxXP>P9PHSP96-g1{Dex~x;m$7x;Rp;=P2g$g2iTk&-z5_MNNa!g&ZMvY%-N@Og*_%}'
    '%Sj4qmLr8wj<B)K$dD2yRhW{qc0VbF(J8V~NW{$Z6RN(8voXC|n0rpr6tX?W!M(5(BVHI#t?DU=Z=MRZpV;V_%6IZDEf*i{;bc&q'
    '`Gf6N1dDfinZP*0#wP*T)iMqNt9GWMQFlocIpsuWf=$J*xzp;}ILtzHd7El>g?Z>ayV1=Na-y<ciTz`%>Dx?ct)XGZS+?EvA2i)-'
    '6p%W;9kxg`P+f1OakJ4avcs%*Y~o!tfTY4~fW)(KXd10pYpvNtkQ?22RtzjFC8G_GJAGsqAQJtaJqzREGU-1yBD=1?)5%a62uhm`'
    'UJDKm!7&E&%Wyd;bK#LO8pO{NGdPG{a#eMV*ONE813o(`rNx#`(sN6bQNd+LZ90qi5;a>5T0t|p-kuH+#6ab9rx6lD%kFl66vysK'
    'Pl`6(>4dunRZ308TaKEM3p~2fwaN4v4O@$l&Urfdt-D(FHImKQye7xJ?1^boYq>aHQ!%2(DTikJY=vFtG+*5;g3(H<)t9tMTrIOJ'
    'sWcz#+3Z2P(WRh8J(W&d72e)829>R6T04!q+ZB5hthADb2AtlAof4_mlttPxm919;u$d{R(vdhrouedbo6xdX4Y;>@ZDMe-8{G=+'
    '>!H)wJU;CNk(C$<<t%S7PMGEakMHvgp*5*=obltMrK_m*2KsK9oDCEC@;2kGi(B0o={OuAnHn}%a<IE_=T`{vus7{dVv}aBq9kEL'
    'wnuKNNhfE$9M>}x*EtgM)h`*NlIUmGEr0PCIs}?{v7XHmA$Q$My4dZI+x3q%`9y6l#*OZ}8asE~+gv3A7bl_kHi6ZOF&T?2-O+eq'
    'HPKSXhE`qrvBFecl=_(-)0U)0WVH@=A{Y01=xdF=m!jDlWQ%<iN{;CpT|h<|j;**iX$<8sv~`!yMnLB9bkLs)u`}I>@N^mVFEE`v'
    'x4m7j#f7ULcds+89IA%L3S@JBH=YVrHoDx)o~YD~ZgDD|%^-2ux<U%&U1i(_GSSkqBjAFyh;Ohc=XkDUrZ&`mAVV7lf=|L+4JBBM'
    'V1qtSU7k$L?s41AGV1`>CNlVqZh#t)yAkG{N{i8)XbR?OU2JscF>k^cG_+2G-%Ti`beVD8bsy@s6#rIR=h`@3DCUBdAuci4+6VSv'
    'mX$fzV4exz=oY4PW|>u&n`GvwV^gCt*oyo#*&^2!oRF7&t~;qpF}N_x<-|}-)yX{*oLsV_b!>a2LK{yGJ5l+b-c;$M$Wr|HMt3;O'
    'tOBhQQsdM^UNd<((J-5#RS?Nw#WcZ{qd9aVdwtPNWtix;syQR)4yB+NA8Qs};S1W4)1~6b?+&!I{$@No-}P)9G+DoCtc6R>awl~)'
    'e(^Htd2M#-Gi7tN8-y8!;l)87YwN!GG!XQOLcg9m$gc4z=8miUdOt0y<p^E2^X~MD6mN9ZkvR+Z=CnKFCzk$xHAy#%8wB=CBO({B'
    '2S{d}C=G>it&yQ3IXi*&%wV!OV}<HkSD>+0Id%(^Vz+QHu|WktsF54p(J?Wv*_X-ImEG=}oufX@#=0TI#<F3xhezud-8;-$k+fCp'
    'Pv%muoN)*2ojf#;tw`%gLu_KYt`{O4nOk?g0kcot=qgQrLGFvHJ2^UU#l&WkGbe$VPZ;h>;SM&g!!DmcosouW8sE1Ttd>KFO+Xn&'
    'E68#gP6@6qzF)^&Nqw+0wSK49zR_i7)fGI1LqXUT*bH^qpezr0(Nh7t((3qzVZECtR#_Ly)>$u{64EA)nHZlwp4zD-wKYp!dt1rP'
    'm+L;VlnPy4ztOGLCvzwtw4)<;xh_RBvjaO03_`l-!9BikxKuRu*w|x8Q#58}EtjvwqXysHvud7!uvBo-liUVT$+tpiKQ>7WTX#Ph'
    '-5g|MT?zy<p_6<m&XR-LIG%`xT-n6YD&*s-wmVnf#>$rF7wkD4Vw6g&J@wWnk#diU=BA_SevvZpM*r-d2Udq0-D6InPmS=bU=LY;'
    'M+s9+30bfWF792_a&R%SA}V7hy^@8%%%^*qR4%g1bSqJM*wCQ)&d#$Wwn$RlSbsA+?m~gPK5QjKJ|yhWG~kOyBQ)NgHlyKDBuyaY'
    'V+P&s{FAijlG${3UXM3EaEY|Hl-W<??)C00?#mNb%<M}R9=_<vxU7?%{*A83h%_>NfiIF|mya|;F?l#(j3Xh_u1(F27Rxii8Y_vU'
    'SStI_kegHVX-JBD0(iX9$BtW-Z0W^iIbJTZlhtK3<8O2$;f79HDA|#ZabQ2Qa2VZMAsLwkE`@mqnMKn<R#^I%qwuV_(q^89+dNFL'
    'len8y3}#TM`#6h>O{WaJ>1F&2&+10k>Mt8dZ$vj~9BIw@QnS3T*W2r9q~VR4a&R8DTh?fK^vC+~O(sFqT^&2VYlyvbh}iW<X$wD;'
    'j?i9-u1+f?*5CVXbcx=)?%QcyWfY3=>}Ap?qeHyUA<dB;(ml)EWtZIS&9jYGe1x|i^<dswJsOEGOb_Lmkd@suc3do}qk&S@WD41o'
    'Z*=kX&b&<a*;HESH>qe#6udD~x9NO0$}J6d-Y}&)Z_umZqQgfGa-X&jf!dbt(_%%XFWf-excw0q?GCvc6C@lV@BYlEjEAXoosKZe'
    '{qpSf=d)IVY46m|nn?Gm_11RR6(|GQg|O9rKjRBr4Tt&EY`Nmxqg^ItYnMgTm#b~+J&;M@mm6KflazPdemb?M$z;@{sBWT)3Ja>t'
    'oa^migF1QkuxGcH@QAvnr==DS&7cL@YMN##5MuoEMvre!;AlWOF4MAL3pcvZury8%6nwj@ruQdonLb9)L;BDzt(xLITN485NT}F4'
    'MySO;(3SFVYQ^#KrEBi4EDFRar&8%T)~)!@_5=#H_r7~PcE$8vc1Q2Mvc0!hco*yY%R{fWYtn{yS}73%teCQA>2txW6&;WG$fIwf'
    'ujtV{VsU+Jhx!{a|G8f~yZWT3I?59Fc)UNy3@o>*?`zv$pyvyQnMLdp%Ogy!<}b%~P_0m`)VRfbo^@AuO)7X2s;7CE&NeIPYQ`zk'
    'gS!+8rR99>=nuN$&>ipSL8vqFCo|;4rOEEFD`7T@(E5_fL>jGr6R#IlcHHb2ZNsxOi|I&E3vHtK(BJJ?iJYPea1q@sqCm{te90sd'
    '@QrR-7W?jcqwGK6(O?fb7PG`rK-!X$>Z~^;8LI8KeUd#_&;XI%1ZUI|X`|_AB_AvquCgnssYsdLle>fAi_{{@%5~p2K6*+N!ezl|'
    '1`kZEHyItunr=_ZNn%&Iklukmwk%uOb^>jMtmf)4%{6L-KApFUDLq<sq4Jvbww68=lVz(^X7BMhSi&*6lHa3ZUK(X-s}u57k5Z3A'
    'v{1UeY*@uOu}@D*8Fn;-laM#M*=E9AUvTTa;oh5r=$68o-DJMT$GjfPjoxvIxg2>DE55}<0xP7FXt<=*EKOvTRz&9fzFLLp?@Qf~'
    '9?1;Ra;w&hH?!K%TgBqzVy%!oQf{1|FKfd>DDR#s&3P_=qZ{ICp(fSqhKBokT1{4i4J8nO_I?zn?RXAKRnv;c1DP@I5{{#;cpzBq'
    'q+!gxNo)IDcoL5aI_7WY`EXIdyxoFux8r(Z@14%3Rbf!mm8IB42K{;lDo0!u2rYyLa-!hz`(kra&^9I16ETCW{!}`xa7(Qe+q27H'
    '7^bXC&OISg+g^Ve%-rb0Ej7S51Fqy`ZF>g3S<@PIsD5CrtcB%P3QQrP2BJ@T??SS2%Uf!VO0K?Hl_tC5c{wj^H|nrm8TPh*b<hsu'
    'qqB0yXByNFBk=>0)OVLzZtV8r`m8zdcs#5SIJ-{GJsl2b!)TY;x#MoWn<WEsGrqQbF%RUg5w$!!^LM>fWt9ty)HvX|(OtR{;ekNG'
    'NqlxWcf(^}ev>L`qhM9tQCK;bJYn8L@FZ;n_|l}N@rYd|TbW!uu^!CM_O_l`%)R1a5Vkz!fj!WXJ3fQMcC@IDyC6F(cdD*%e_TDK'
    '+ov9?47cV;Y0fV7ZZBJ>GUhIHUTyaR7_NF|%G8+9#h~|4a5pOTmY9Lsy<#nf)^BvXmsvxIc)9Y)6))4r&9=cN^T%^^&P955D9Y@S'
    '?!m$$RAy}j$CClO16gbexTx8#>**9L!?M88yIy{8!O7jwwYW7%eJW>*C#o`ptWb|9Qoh-IThHc)<K2?oj7M>A-<#}h(6!VL`9=!w'
    'UPQ;SiLZP(<vf)b-wDRsnb5w?Q2A=d@Ez$==&rxfL(;3{-M#Ww%3Pq%aEzp>PCC|Ap!uw29p|TnPYN3AXf}r&Ta#AR8b(k1Am5M3'
    'Has}ZtVEU0q(+fxvF%qDig3p}zE*yI(9YN-Q-Lz0d|+OzCft<*(w<=ELd0fRc!IQ}g9@p2S6cw8_AR--@vT<uECs?}ps`wYyX6Yd'
    '`AF28*3f(2ZRE8Mlxu~h%vKFC2r|+YxR|fiiP0rBoES;E24^<Y*4Bu|YC-4Wf;hHN7fe-eL6yxV+Nm+aSt+u$hzlGG_p|r9MkN!R'
    '0G&po{S3<amT^yPwG{X)mL+<DfgewL-4VmEs!fDIJw&EnJrz@GOuGc5t7Tyo8KjH@9f11%i(MwfcEo>|Z(toCxMv+>Y(@~NZ|7}%'
    'g@<F+0EeEU3^Hjmbiae=GXr8)jBNAnQn`grRb!CWx4sx3OeRp;)zkV}D^-L%M>_1k+eOcg%<{%i=Lz$)pG>VvJiD3C4mr=E7A|Gn'
    'A<|<j@oET)>rGT@$notwns28}ET~XZjDV}2Kt8m<RaY5Rl;a$`$4y_E(U+HDmRF*o#w8zbXo*d3mMCz@Y}%L2kk#`PcHY_4nw}=A'
    'xlHJl)a8QJwT55dJqy$AO4f?~B*JYoabb=!cU%$<p3)=o#0{lnK=8EFc3amL)#k2H<+$>pOzJzX!gU09Ij-rwX!w}pA}KV)`KxB0'
    'ZgDhuY;W-;(PxOZdnjeIcYKD0We*o^Y}Nz5LE1^yHd=H2sPQ8Ja%24zCAsHjGNrkPMj@)XTlrbXW75c&lCWtpxmeEwu5>jLERK+>'
    '_p)f+^NU{3zvOJ$$H2s5Gn1<gPhvS&{XuzuNo0CLg5FZoS;4(&)q`uRx66~8m?ABGP<C0F<~A|QzaEqIqZs1LdL8$0cf0UY19;{}'
    'F71=(L8yMm?zU$UOJF*UZX#FDd34^cG$N!KsaW1wnMxb@CWSPoz2TBKv63I@AZpTxjq`GO8{NCC`@U@#xlCkXu6x<>rBEy%(oyo<'
    '_hkZuvaC;hyi)2~$Iz;CoV9kAF!J=F7`)Epc$T2>lb;?B2HQ|PH^)~{$4^|mje8y-g&4F)jI@-Aaw~toTW(JHE=^!F&xCDGBp*J('
    'MLgggxp}C&qRXY8=-cdiJu5lK=29ZeRhF)aoL%R99TFW>=k~o`lF*qn((J(@W1U%MmQ+d1h8SWRLEZg0S}Bg`{VuW}2gb8D8Wy6`'
    ')NLt&d5bB;gG_L}3j~*E5DwbK&~j{EA~E(}pWMfjZt-N(vw(Z7MaPS^qEe(fNYupSX0`0LO479M6V+_Q)nHc$x3JULeic=1)Elw+'
    'xi$+{Nn-~?VUQ%1#{RqC>G4%GwwBsH^uPs13!W{N_SWVgL0KIak1Zk<F%n@l6bf5pnPP{vtUIh<I40Yk>Z!f8x&*gU{ggJaNu;W0'
    'hj!<l2gF66w*;+EyN#QJJ@d6EPD+qn19-06@IbLzA<}h?)wQ4${G%T5q<kV>HA#0ee3lK#D;;va$tgKbCZ;LO2=>o6x};~MFR~cl'
    '3gpTv6{QP_bW?^<v+5^%_*qA~dN(>sjDiv~R+ipDp2D_?Rx8_1mUv%45BAR0nrD4V+U-r(>y3==b%JRK+L;13WXuK`AI+2_C*|cD'
    '5_3i5vzKZpQmlh4@Ub0<W>!<FP82e&(`5$bXGuFTi1ur<P>`>1R4^yDgVW;XZpT)$OQq8NM0>!(b0kep$A@V~=>RZ#k#n7DC{y%D'
    '+O5J2pH;$bhLpCvIq`7wO69oXqoquUg;RXQv~%UclE|3byPl0V(P`aJh<hE_K_JB?8pjMfUHN)-nAW4rF14L?gY8wLxr><Gv=-&{'
    '*(}n=mch-b8j#FBvzu+!hfGGBrZ<5G8@<sDYb62luC0+RWT(B%zNi(F!_Khp!%d~wbgeI$%r5Ie%5x^fVcSVM8=Mg`YQ_qxkm>jc'
    '?if(2zWs0@h+AoB2k!Y$&@Plzi<;JYnd;<x?wz>Qj5~=g{Xj1HYGtGNhT+aU6!a-<Yji*?*c*yuTjFNMKqBMO56NDnRKY?>-DolK'
    '7#+CdNt39~0~1edtDqrd8C@8CNm!R@4-$`ewa_7(AU*BOO5GG|C)?d?*VdxETIUOR^l}Nc<e}Le`&Dv|Grnq&<MrB&Znn;^dp^&_'
    'e<*fBlie0ij)R+KO0<T)ON4a=?S+t6eaTDD6fG^sNxdetEE)!6+Dy7V9cGWYByDf?aoL;6b+;$!j-$@)-1Z<!sjYh6B*OufQ*s$8'
    '1Wj{DiaDZlQEw#m%2M4xfg_3fPt95eqW1Bn)P|s8y_;+A7Q4>67BbU1(e_z)ep{1WTiNQqL97%^Owy%3u4STa_aq_uvWe4ZT8Owt'
    '@VR~&G>W66kZ5LWtz!s<HgKmP6z9|S8pACZ>Bl3h>M$sE?sz>?I$nZ&z1kHjtC}9w>AB`n%O3wAI1d+H^@~u3#_S<Z+JzR4Op|F9'
    'mu*pyjAlVt4O9O5gqtpEd2hC$A!|>*daqaS>&0C#u~}{gyyUlh9qY0RH?t-_njJl+bC3kA1wlht*1wvM+^ALSjd$hKsMN65>%>4D'
    'PF#b$aw-$mihp;scK5oGDVMsXs?k@YwN9L203rmTs!mg<<6-3Mc;-F`*;R%ZB|y^!)30Nv&=Jptd+`q8Pi0n354QlxuZp!y54-Z2'
    'i^`3z*FVUH#JWF<B_qgkl-ncPBC|0q$W>2oOEbFRjruXJFpZnBa<**Y^QvSVO|~%Q2D5@_8|#&KnH+jBZp-bMM(iGkQk_)Dn{vnZ'
    'N42gTeXg;R;14>0jG06z)5!UG)}NF>W<7>uL7Ti3tM+bc$I|tZ*V|H(Og$3IGWA2Wq$oKR#d3ptopzpC4P~ovJclDLd^s+~E6CDK'
    'x=$h3rJFz}vt6o_rH0eJj%{gzA7ImRBOfPfCct>zaI)QMmuFR68^mUQoXRHd^%8#ys?XL(5DZ%L0Z6Yrh`ScwVN*L2gQI2~>0Xe^'
    '*cyuInOlPiL(4|9X^&N8^q!CIp8bJgX+<k}t-m_CsmPkR*SWU&%%N0<@|*42Z%*cxd1SoVInEWkd0f~HlSpAs`dNsX2oSdw{87*L'
    'z-OCW?vTMdN-5_{XL`f4ut>W=*43DxcmFHy^y#dW?`Fi%S++|ZkYAoR+wHD~mB-37S&sDPzGgOzBm(ZKc#IDl1mEsdM{droYQbVp'
    'E+jPm6d+e~{^<5Ff%Uzv%-ZwBs^P6Q>COBcacN_v>m!b;KT%h#$#P#UC9`Q=n~#Mg&!+_UJfzEQBN8G{aC~l>#ahHt=c`hIC`S>U'
    'jNQ+jmPAoMZ#r-cEy>EhlJKMBNXzPrmYwkR;rS@l#oRl;KH9WL>!@L;J&-TwN_V1DF48J$qE3hlzfY@oBjR3k2WI!UIc}+k7#s}6'
    'i@UXJUI>N?{-tNq7ZTVc?iwtoJA{teims-~U8#qJk>S7<p3js<5mzh5F-{#=^z3W8MuoNROSfjFd%b$^72_2~s&y3(u8n3PzB3<G'
    '`^Rp8!S?dVS6Iahs8sHzt>JR9pH}+SvEU66h%!wSHk^N7gtp_h2gy=UeKGe;@8>wOzOw@dW`d<=>4dh=494TIhmGtH%^KzDrYG%T'
    'uhGRy;YB6eo&|ax@3NZTZ-Vnw>(nHDwU!kN35{h=4^7-ICQ!K7J>d~eUR3`gWKz*k+8fj+&0+53%P1u+n?{PJ5N!#^RAjBzD=kH='
    '=izu(U%Ho-#9=wI;DohnVsmO2&8RM|n%!S^H@Y2pxSeZ;0OzEWSc?RYjTYjkhj=N^9D|6-taPtG9HlVLv$N;b%UlMzWuJ*cn`mYt'
    'tA|nBTWAf*;A&HtbE0P7?Rbb`X=SLxrZzhdwW01cE}c0Uod)W~^)64-;|dk<ldam~lxwgD?;a$cwRVRZ7cWA0R~;Orz(|%F8?o8y'
    '#|R=nz0uV|@bb9c`if^UD%i|`+Z52Cj}7M13+a$AAi*u4KoTBCihAR9k2O;DY+v#wP6+K=xHDv&GgASCf-~8sJ&a8>^hQ@-bfbIK'
    ')9%Fmcq2WbvubduZ#=_HdbhGGWx>5H^mndED#rC2rNYilkH%3h87zb*7?$hUmx?w!E|NKdOSWSJBYV#aGak{~o|{y2*XjisW5ar4'
    '?nDJ`cb2k*&x4CY7nmDSRTD@X)u|m*4Q4Mc%vImEpdHaN4^?c8<Os|vN|9`N(mCGsjQ8@P8RtGl(yc<f<F=q)UnVVLYB%|dY^~}O'
    'tJpsIg)x=2ax;F!OwxkR`V}u2){awI0`pNpb{$BNNo{+W-Q^%Lq4;cQxcP&3+ii0$W3|hy*oax`Po;KydbZ~F=)j%yWpZ-FW9cC!'
    '63tknWa~73QbYz7rf_E<3=1sRl4Fs>J@4MF28~Q5U*;?~)AP7&=_Dj#eIZbGTP0L4P&2C4bFVY59vjE$0GxB%)mBFddvkd&=aW;!'
    'l8&MHV1L-x14cp4-SezKa=Qui$K1~4!Ps*sVHAzxRFXn`-z-DxBY~|u;e0ohb01v{d(hUK^ifSG5_quV8}5Ciy$Y<0EdT&d_=(Ea'
    'my3Ixho%{h>lC;7w9-NQNutwdQF>O_T>HE}SRHC1-!Mfgl0VR2W=9g%vMei?ji$X&b;|Q-PHMH&`*VxI=>)vUpYL^};bp?Qj~$~l'
    '?H$XFcE(6%>p>~5gi4i+c!WI_d^bWMyYA^ksZP-+wAagNPMl@DRTy1f65}*K!6cENPu!JYp5*TMEYkBHH%SYE=X{qONPe_$@vJiO'
    'TV4~cbVsFCz;)>F07wR&COPemTNf`cl@fSd+Rb^%-AL!{jJPRA2ecoH7svN=k(Smf(kL=5@An>h)7lKVMBHER_<H+&-W_G*Tq%YZ'
    '{DnY=8f_2r+PuH2PB-3-2ZPdHIVD>GAviq1K4$5fPrMu0y2s<ZP{HHTp||aB%86|`TaY##lwe^Y6DZdyxNI+{>q5DwsmJo5;OZ)9'
    'MDNe)u3Dp3&*GgKQAhVJAu%ab+@=&q?&kqAP|M5qV48t>sb-z4@s_tajmWuiU-8?sSS>RzTU<WBwLB{;U8e|Tw>(R|p-UJo<>?V^'
    '*#)!;w~NfNJX(ZG{(HUTxUH6(wKKhS8-r-L9cJcYvrD)=sd#}t27$XShyhPI6EHoqRmeN#n<XfGY)hHKc-Lv$qo$Y`_Pd*~dYPDw'
    'W@mRlM^8qYsch1k9u!P12G{w0V2-uLp<sLF9a2!Bm04fa&BfY%ab--qb;{P=LhyL@vD~RL@Q5<BYfdNgResVw*wuFFIe%j`CZp8n'
    'C5-g#>)O%hzHpEWS9`n7c~K1|#g%UqHT>0mOyG*xs1Ksh$}=Z=gM}cNoOtx=)<p`LaUh~bx7ok@b)2!Mkt{P6lys7UTON0`pdDJN'
    '>L^0Q;G#Z-G%m=+&r3zWY-w+A<VuVivqWIgGP^i`?(dj+l~+9*tnQObYR7ZmH=#W}*1H++7~S{!rkiowqF5_$*|I0nnho;FG=?_l'
    '5SQGY1|tykn9F(5sN`F_+IRvt&w)8rGu#cKxZ4*enfxBV*VhZRscD7sJsrd2@thQ3>pOWx9S_ksL2!LPG_l<IUP>P&)O|*)FFkgx'
    '1F@si7Cw;X20aReP!V?(W&rou-A<Of_XUOaj5tcK1>4&mvBTp6VG8N#NGNNKCP-Q;rf<G;g}kkKOK%@rYtK=bEJnlh(&u5ccw6v#'
    'qJ{h<*QzR3PTM9AmpfjE(cM^Y1`2b&?U5o>psQ`@`ncU}S4U;0y$ywTJRT|>ywwA<2<B_^f^6>GId8GNY8*GCX}h)FOM4#?EbO^4'
    'I*#4*i-MIi_+u(#8(E_@z!hX!_qvB8$sV<=<Jfj}X83+>fq<dN%j|p%2WM7DE^g9|89nQ@8KGBGnq~?L>P=fm@Z$YEE0{U*SfrI*'
    'Y?IwCk1qF6Z(D}(WTP~a(rL9=U1tJRN{tYu66*Ce#%Oldt_4a%X;y2&RVItn&|`xL`I`R1s-4T-^|uxA>ZLWm4)yx>d3Bnk{nZ)F'
    'w|$%C5OT2|A*iKLyV1xFBf$oh=A_kS4jXc2u<IsmvmEM53mwaka=1tGC1k95uRm;KVKQ9syAf}2rKUX9<E9s{C6{fj%b+8kHOG8g'
    '9>fV!FjlBqU;9Qqi@F4e_{uJ*)s{7NMZBpclG>CL;}L;%8+ZSJcKW?Rii(;2)5<el68OnI9dKD84Yj05KyS>eu?=lz2jxU_$mRp*'
    '6>wyHx0Z#2y^%yEQtp(Nr#q-jOc<N3-Eno3s`?TsDr7SXmrlc3bFu0u2_LskcE_b$XUV2a<6NP0S$7-&62-(={JczEysM<F=)-CI'
    '0HA;X%dKKNkfj9TUgzq&2v5p|^x>*`*dGN&FkqeDgJj0bR5rNx6z!x`lFn56XWa|YTFLJYl13!9Z{T!gGuU2Moh9yVW!Ed24YY{?'
    'cgJV>gceTd>AZ{^mo;B14-<jtW}aWSJVg*M>~*4b91N$a+$0jxTg%EqQfy!OplRc>mUWe@Scylr$S~Z(JIthUxSu;ISt^<<C5DN_'
    'rWLykM&4+#9PSxCmt|zmM^|tfPZ+uMDnScwG~Ot($3+>Z5F|X;&b#Gs4j<aftYEW&!Jv8UHH-H;qJ}_{8C)tf?si8@Eq^ZA*2+eW'
    'n7jOYw2O1qKrH0aJ8U~XtHYkq6dt<=xiL(f+HN}-FT`M9jx0}h2p(W_l$|cz=r-EoT0YiKARrdPk#2FBj;Hyo5#FZL&E{mFpUP?U'
    '*n;~(!h25GjJQd!MLE@8i#vCrJ!urgt+(UjgXv@f>c^^~d;esZCNcdew{!Vf$_f!FHxNR@dzwbp4TzXx>E_T11@g(b?TN(#!AmCJ'
    'Tf(bmGnK<e!Zs~LQg-3EW5al5uG=Znb@yj<zM#qxZ|5Sdqg$Jca~x?Le0n7w%a#|H#)67RldW+9O_y0R?OT*M)W=snE|)jym0Ht?'
    'Nf?bSpDRapi-jk$K=1uVaM3qCEE9BVJ+WK!Zr8W*EimcA)Z(~+hKrj(yMaV%7dcT2YVkt^ByhzAj34qtS8I+Km8iaUpWK_AZW`lt'
    'S{dK{j?gIakpWGw?U1f*1BH6HMn|XK#`frKWs+V31U0=1y94=LZ0UD1<N83}+3ZL<vD(-gyX&rQE{2~Hr*ei1hz0Dq?=^AmmiG95'
    'm+AK?0v4v-lNKT<12ZR5A6=0-NSqMnFr8WFQk&7Jv#_S|LMpl%glTIzz_x|7b2G|9wrSPJm*Kk{IJoT&4MuBJ3U#rOe;7{GYO~`g'
    '<sMF&d%WE8CB{Cnd#-D=nJhugQ>~k|piC^fqXRkInq$#bO7tBqXcf=<y0j;L?|(4zVcT8l_xeimd|3xLC0WIax_(^bMJT0(5*W2>'
    'wLAPFq;;cYvIV1-ycA}1t{rJ3n0qiBf^@aB-$3<gUgy-ip2^4Ih9KO8lgpO^L`yPfy3QOkcHo3Ixk6^jz($_6V%>fPm#WpGu$;>Z'
    '-lJQG){q!X4s&VP373<xFtg%xa(J)z^%e$s>ST0D$hc#N6Dl_>olXn6-EM03`7{@WX1P%`XcQZ>F519%_H@<{`hDAYTE)3@kCKg6'
    'g9%~eI*^I6hLpR}J=7&8Te=u?ZI#PS=dzkFrz>Z8TPdA8XJq4%qJa%vmi08|i8e-Kl&Xz`>i|3%Q^;`>Qf9I8IpPWwrTmICGMI3$'
    'a|Ls~B%z%9Gb~ftBf0V*DWzcy#Bl#*BgWU2adgz0qI4F<@a{ZTqn9(WiWVAvsTfDvfx&p{KWK5_NwU#hvRdDC?{Z+=wG)-zdqZg+'
    'ZF7~CnoxYX^M>_ry!?zJPo;60QJUj%tC%YFn&}W+VGQfwSvL_{ql{Rb3-#5m39Xvl4g%HX`#FOep|TuyN@gbU$TDvmfn2^C7u8-c'
    'cXau1c%08-!)~-5s4RDJF9v1L;;LRoyZw!q$$R0>wqcRGd9H<>Z7Ufw@Ajs%g>@v|Lvv$S*&po`!-f7j+Mk4u2P0;zaICn~v~<+F'
    '4|$C4G1{teAo2(Dhqxzl+_bWM2uj2z9Y#=3turs$${p|Ym-$^HcJ`hY<zY9_$L;E_7f^e}R<2kfk11b#+REGM?%2o<w#&*ES#y=p'
    'Ng~(9VQec|!@V(Y4+7qGQiLe!w9eh@>!m|<Tq`j(cQA<VQlY#w+uM!G;W(4WFh1vll$fxxSk}|&<B}i;Ly6>u<yaxbXNMV`WYX3C'
    'lCI4wjk#&7y<GTouX`4W&P0xziH0((PD`sKQk;13*Z>U|SoIR@^xzB>thTgF!Lru5=~%ghx+SdI?e!De<UD^q(5Ygk*It{@p;uV4'
    '_dbPfw3Rg*yX3Yug94FAP$8r}-%7_gPcR)>L=h{O^mSDuPWQTq+YOZm>x|GCRqS*m%c~8-Unhz_HVv01H9rgmUH5&Xv2ZxFVuoSZ'
    'Y?^$EYMOgeJFvz;&q^Vzgr&!s<5CW-T7{-JYT?XbHuB}i+2fqlb2AgsBhqvz9}gnhN)#?)G<fe*sGmKtfj2@28x?tfP@8I?w&?Td'
    'K`WmQ;gNW#%tt{%YzvEIJiOfwkj<_`7OL`|tDjU^znmJUVOiSCs+6tSdF#&aG@>nGtC*aT$-eF>Xql;h&l>22&EoYYneocm0ijU('
    'Vbbr}VJT4Q#35!sttG;dNOqdA6Ae-t^fR+uQ|S)SLtuE%hpMyss4^~=TCrJJk)~@Q*rltUL1QZViy^nDyJS@K45avIWh65YUshxL'
    '9Z6=?<7NW~>fQRX7|y%1%BE0XM*I7F{lQ$N<I9liJg!ueavAj`TDxYhP9N#Wz-VRzeEZmI1W2}>h%Q~zoz@S^Dp%}OJEQn9vtYez'
    'tyDd%#vMBwS*0`E$Q?%ot^NFHPO%<tR5!~=+h5zYA=F)QccL!2+0zw?3surFz9Bc)$fg-~9a7LVh>(-~XaaTnsoA#fhSwIlm*Bc@'
    'U%c1*APXL}2V=?Z27>1?-ya+2P9C#PY96X*f%jXrBb#{FWcX2ntXCqb?y29$_p6$>s*q-juzeweOjmqrYZi?qTgl$NUn4R=sZI-3'
    '!!GS4t+2U*XO4@m9ZR^w*@1cDN`jWh)2-s{M7!f#10nT>)mqh);lLJ#2iUAK;YC;}=k-X-h7b4pLwHE$Q>pqcXyS|fYJz7uZm?=K'
    '{fmWrpMzR(vuqHwI@;}qgX#ZA)|Krl%LU74F^UlkiK3uJ5t+pq0U0hBL<B?yLB#pl&;Czx{4UPzz98&HukPxq>Xs}n<k;wcI@B({'
    'R&wV&W^uQT=}^<?RoW0K$dzB;UEM*Tx|r{Gps{0_tMmz4Y!A#i(#|MmGV9@oO*yTIAC{<h=gJ@OTt5#FvL^_l_TB0IH0ze88C=^i'
    '4f=Xdw4Yz@`Yil$ZI*y%R_ukz^RPILhL^(mWIG3E!KYHwYQ**ReaU|yKnNOda}iIX?8Ym@HX={8_qcc+FUQ+(lP`k#zy27xH1K&-'
    'cWK&r*31VA_L=ZWnw=t;J<4b`Ea{azI@Vf$2ebxvh;k{(ZhD})t48Cw2BB9QscgLc>Rd)dWXDf`yb&&S>-{wu!JR{~-Lh8!>Dy0x'
    'u^2{|%af?DMWTqFuT3FuC*7BUi4lAMSVfli$isS$V)>ahM-yNFgU$~I(N{md+A{rD`D#7W$8i9eC%bn4Yu5bxo5xRbCD}emf87`e'
    'T8;7rC2oQy5gv;(8VqjEyFOP>i9pXDk89YEt`k9jaX%erkwC5EU8GQALLI;5&Ql!BPo?pu4)d*7w%#{z3M5!NnW!&UF}Sg?R>WCt'
    '6Qv<bR`P9GgC_SCdUCF^VE<*zA3rG$(bh(FuEu2S5{NsqCp8h9qglt923dOA*EVlpFN}xj0KY6_Bn(QA;ASgadk3Va_j5j5=|+2H'
    'T`<g5;`{vPUuV%O+gQmRvu|GiaM>drJy-H;fmUZMvj0@%k0DmI=rBEhx`wVkTaIr9g^i=}m*aO<V^4?sLGLm-kt}ZQ9sKv)99Hw$'
    'sN6YhGt4G~WG4+-iRm@{i}D;B<I`s=)kgt&MvEOYS#mw-z{Q4fz;gMy0vysmEbp`Cv3?Fm;5m8y^KIk)IT1YDP(8ZOKhB1XhuLZ~'
    'A5xU8<uC6c2f^dpt6Rge^t{!?DK$ILHWsZbY8AM7pu?AN^)2#tEn0z2x%2yO!NT=ve|4>UtoCC0@#ULInxOJI94iQUX_b#G^xU7a'
    'jSci%_}HXQy=Cpa@vfC|afJ_+IH$?620BAj8aY+qhx@EC={E9f?eyl88_m4lFPqwnUW>w}&9?52LkuR$Q4|dxvL`=q(}DB%iomS+'
    'lSmQK66PCBX`izN+<h?q`SyEmT&epv8~O0iiXAbyXh7v|Cjo*7tlW?8h&gvFN7J1%ocdg@AN58(pexhKuAj5&1TUXGuXCB~3?-Bw'
    'm7@F|{CLl&Lb1bIMcZa2z$&BKyUVg`h@{s<Wo=rf(J6nsW^oa=)Ag|FoGes)s@S62xn1Q2sz5KlPsFQJ7m2L#hI2+gT)jDXG-hq1'
    'wpTT&rmB1!V#TX`=Z)@hvyw+s_Z8Re#W{F)%y-Sf!J;cbMV5Nsyd1XJRQw{XcfN<fD%tnIT^#-2bIV=1JbmO(esC2~Ja2js9^+*7'
    '?Givn%R^1DJZaVMw#idE1t-Y-{k&s&|FNyil=yL7(8IjAf0-*IYu@v`=YIY^D+DeC!w6Rk-tZ!0rRKdgR#7D%^!j7L((XaiEq^3r'
    'K<}ppmp$B>#7&mB996s7@m*}#y>KgpgFm`gSn19Ge6Le(mb4CkeaZ_f#!JreU(A-|_!agt`DRXrZ`F{p>wLg7Jw(djQ^HPf4ucbv'
    'Mgn#G^Pym*cm+>W%Yy=5*MENHg})z5DCR?`;7lKDp65^B+H0Qe3;+duFT3Z}5QT+wu>2sCn{-d6hrUFVqQU3(B+_+hNEt0)IV(J_'
    'AGD~$ukS{=ixXC3vSma{(&P7{2tiIJmd5btY~4Da_wA}PBLZmqU6wje6@Uc!c8RU@6-T^xK;d(HeZumr+A@m!HT(YJVPRcK3nM!3'
    '(q&ziulrKxC`~t3r&i`yS%s1D77QD9KC)}A`KTTW;&kva6o;~eUbrcBQ>V8P_)^=?!=T>B`JbPQD}S?)Fn!tYrrQL)c;|Dy=k%w|'
    'QAWmtRU{$>;aAa6{ba2X(-~hzau3j!x8=T0CX=KX4*|FHJnf~^?B0Bze*AjZUQ8eUW9<#cU^}u#b79J47oZTQe!zC(H*4*igO!ri'
    'GLrT;f|XcZaK^Gu+#TNas<E6edLy84l}^pRH9OrOFGurYA3HGJGs_hgWD1>Z{lvCUFY5pb`R>*-`n|`j+Ei}(Uj|;Y6ntTatM0wa'
    'nC0!UyB2nH`cO!o7NeYg>izopg*!eJOuJV@Crx$KGiFDP%QRTq2NZT*1)IAymuuCX>Z{PBM$V&jM7qs+)ZVJtz{+m5tSvIm`(bMz'
    'sLm|HU%%OG^I1l~8NeNJV&9@FZ~A2K-0#9T;2nsi<9fgAV*7#Yy^|%w4Hf3ux4TK)Sl!l;em|3=(Ph9xrHguur%nBLkE5o=sNwZ5'
    'IfQL#5Nle$AzaZoi~4@X4NCOFoEToGW9~6`+1s=ku33D{BSf`x>MOm>ZQXNLWm2&lo6ohkB>(AI2CgDH*AS<?by;NH#S5#0P?Dp~'
    '<|s$*n2tA2SmT|LEfezeiBo~M^G(HJlqR9s{i$a{e0{ckN@fanGGO<^lTd3mvE2u;>qF*VC2!gIFR?OLmGa-+`vspCTisIW^D;2k'
    'Xt^4o7zfmjyX#Ys`gcw%EkA+9aGPqf)8M(PResMM4b-!u;-6KJR_C2DY%LG^!S5}M3%EGq$4LILP`h>BGGDf|6-!t2oG>TRfHRMH'
    '>c)qL)Z{ve`2BI5kLS($PiN?Ngz{q>eG3cCKHPaia8$rvp{<_><rup@V*EK>*G2K9=!Z)Td&hyHar+sJS*lJ@OuCsKgx2xA`Z(Rq'
    'H3k0Z-O~G3N{_kt-N1Y~>dMU-J1a4|aV4H7^Cj?7ziQd{&&;+)k$z6tmN}SF69Y;;3%8e3YI%ASpW+eCDQJVee!6txSLB4+bdIOP'
    'bIC2oT|Zx4FrAiSaoIDVw^LYQHv|7VQmVM!>L!~V;(MA!O>|GC@RmBjEa=}1_kA9aWNtiu?>p7{^?f7`Z!fNX4WQ%4un6NAUiz`<'
    'v<r9cN03z=m1^r|RAx54ipRFd>_A1GPvgjUr)JOTyyVqlpOk^hcJ|{n!Wl)Hrpdzlp<o0l=zl&OMN&5=&CKnl;Dbae5wnv#<GhzJ'
    '8s27`dfp7iv)%i=Uw}qsHK{=P5ZVSRt*-U-_gw5M^!E_X<RO9J0x%eyVQYH|OM|&H-CEQ->Xqut$B-t}p^Bd(<;l;MsR&-D{jz)*'
    'x;Sv@(A2EqO~>+h1^n|BixX})zIY=KUEian!q29o+dNPpjzN!J#^}S|L(PTuV*MQ7A>q4o^(e2Fonpq+VtKcf2v^t1B>Zbc%+WCE'
    '|MJ73aKnD`RGN2eRvUvXzuQvdQbn;-BEm~@=M-X9aUt^W#nj!1=>qO;PA;_DtdrYbe->85wR1Ev8L)oLD(As3e(Sed6a{g8v@qp~'
    'o!$(j;YL!r_>1FniQj)dtFg<f$Kta442vo=d43l81$@i&^Ys_d>Fa!nmuvQ<;6e+rQs~F;IJ$-=D_+4=!hpg)dF|Jn$woRS+<mgZ'
    'VW{EUo6?H>EHlOVdR-2TmD`7T24bbX>e{nN5I?52j9oX<ig2L(>ZT2$$@1ahb@??snBIMOHrAc`L_Xa*-~4>!#>@K^L4i%nxQhqi'
    '?sq729ab8AdmTt}?~s63^!42kdTLZ5j%9y-PwUB0W(WU1-r1*4H9a6rX>W224pVMAIRMV5+ye@Lxn92a1i>$r-SOOj-0J+A(Nrs{'
    'M@5aVeQ#L}Tn9~ruKwy<l`{nx2yq}O?&s$TUwD*rW@hSIJLuwwP7!h!ZR|W;GAC%s%$_4?v;dt+sj9bw|8&Q&H|ux*V2^8`Unjx*'
    ';iwijvw*173i_ijke4Eim95Equ=7Ky7!DL;Q*Y>(?V_lkxAj7QUHWz6Mt;tMGQ$VyDLJ`EJ8Q|82fAqMp^2A&Jl6uB^~_Fh+2gFQ'
    'Zr|xma%s4&&XX*oFU*8fd4mMi;`LY!N8R~8SrdkvE8F6<ufA=^S%btwX+K`h7;M$n+Vr0fI?^jxBe-cgIh=1{C{9*xsZ=7(@Z`y('
    ')l|l#ROBY#Xvxqys5<SuWgYF419y~G1w3boBpqJoc*|ku^Z8x=-M6EauS(}&m!e1IvY<UBZoS7-xSJ@v=5g?a_=AoHy=68htaO;>'
    's8TGk=6Ks)j<@q+*I27^OcZ7hnWuPE8Jj=7`vDK#8y1MFTUzO-Q0BH7tdn^l45s7l?Jy1=?ZHjz-uu<Yg4r#4>Z+7~DUNd;ZXcZH'
    'gfYL4nB|f0XShD=jDG!4GR!8HqTA}=X(qscY&qI^?lzNod9a)cDZZS%9}JNL!Rk`Kp>yxx-{oh^KDsTo*ilSvZF?hZp~*&g9YPE0'
    '=X>?5KpBML*Bmr=k%qfN#TxozV|ZDsIxsbK+sV{jqf0JVJ?qey8%|cr_UfH#aOieKdI3@_H>T2J-6wm*?D*%0xh<aSFfLqXtISuj'
    'Fv9w}SUs{D4lo&$(K8el?d1c~YYY)=0r<i7@a^ZIa`Rmkt7y*&TFgo@u+dK566Hp(-<)OAvLISRhSLF|TQWR4yp2|tZ>N#d7%yi~'
    'tCzWa1+n54ygf?-^pckYoqF1(wtxudU8jV!h$w@W;%mZd&Q1OCsm)B(+TL@!!?9j-b9Bh=U_u%LH*&_|Bs9fO?|n!7C)>yY&)fZV'
    'mk+r+7_6%c*r+reF!-o0JV%<=ezxv({N#rp=+6bELaqxIr(SaZ3nC76E@mC-VFnt{YlrVfoPKJ|9C&fCF`<>bGxlvK74ySpv4i`B'
    'TsQo(8||zX+^i3)zxc)H>*KOQJT`0g^ZDjIsoa(-99lFEvTbbX`qwY|B1kLCzt0XrvnLC)%7@f0Jbqj>Q$AKJB%gm?;M!>omGb$g'
    'clW&0qz|7a<C0z}4CT1;JLjAI!n5)5MT)OYd}2tYh_~hKq9tMxbh&VpC@1K-UI`x&y%bZj(PG3LGlu%@YW?O8;AQ1b*q%37RSo5|'
    'dz|i<>^Kj^sIWZmi9MU|Jgi&S<5eo~*60NXpfK_fi;q)kSx+w;dK!hGNPV`AobJ?Lzj^dd-kAhUdfKyOe_(B~`J;)Pc_1EUhf$A0'
    '{yH3$1(hMUBdOlTe)ewa;Pc%+TXR7;#P~}gjA_JM(^K>9oLa-{&$o@|#%5<_aHlzfDtgiB9&l}ub6%$+V6!(c<R4e*YgcNA*!rlT'
    '9nFPP13Q#3Wa!GPqcDW}$+sM3!Kp_D)AR7h)5@FO;lpsVzc&!^)2$MWX#WTg3Jf|W?O9cqE?aBdnW)1?X|SF0i#N{COU%05D3`Su'
    'np%bhb=*I=<5c>xqd7lax~6f(+CA5!_CR{TrG|E0+x};RO@!8agFJ;f=Nln$;NWNz5S_t#<Lv1pW91thJRA=j{vFtUw&oO9TT^WC'
    '{KYRp<{x7vj{1X6bBjs%h(G8X368kl`}_(adPcUH34%Ph!(F`~{q3O|36lCokJ_f+A-2`z09>U~i1O#YEpf$<KSRL`cn!_TVu61i'
    'a9jlZ($dYEqz<Qq37+nQa%bD{73to+z{xeqCXn`FzhwyWqdsrKVy|=hB-%FXXfrOpGe3L=3avrHbcRm~dbOR^Xk?ldVv~!viieM;'
    'IE?HX)kS?Xo$*TA(*(jP7$rG1`#02%xN<@_0XHNX_^5B0@lO8!_%lr4<sl9Cpe?^41$MuAHlvGO!oE3sP3ySw%IVe=E4B(pJj!(3'
    'O2B&Yjc8hV?Re_55uo@Ikt+a=nwO>2TK?i;GrFP=$K~2-&|LE;-1}~7>zOe260ZEL<0K!V)~l1$`u0REZKR67f1ZScp~Re6g5%O@'
    '!-`dp>m)qb2ebqF%aiv8SaHCnQzlAPYTLW`!(;F&Bd>!LjEU+N1Gh?CHV8Dz*hSlbz)!bR8KU0K-XnlhXhGB>rSuRDZ&TtB(d%EF'
    '?T4!g*{bmCQ#=`8pIdfUnYxIc12vE7^Yoy?7<-N^m)TJ|etB;CCQ}Nk1$G41QL{3|_H3#b2Cs<Su#2x>zj>TiV5pUu${^2S3tFil'
    'Rv}E*`Zk-y2tmTvWKDO>(cu)saBFGosexhor;Z{X&iCXkzf;ITThCAY2+ZBKb0$hZ{vlnLh3;`_TPNb~q=J}FnXjdgt$=1gys|_I'
    'rTs+iPP0>m4N<5pC}fD8;@q|GaEIGmRxj-^UAoiKCT((T^YM${aTD3{cb{<2(rghqSj=?{uV0PTR`Vl*{t<6Jv|$T>D05Tm8o=Jz'
    'v-F3Y!E>pBZ2MRCrtaaWyOer?b<~XEuO3TQ>QL<pF_CM_(x7&)zu^udf$ha9o$SB2V79$HzSiC?<ho4Zg2v97Bi`A+PO4j!&{Mxy'
    'PEF=|8}~sTfXn1hC(|%D+TZh{U*E#|5xun@*<;kd=kMZ*)6G@&CAr%d=b@ASqFdoEWg#u;wUn*eNInYg$e>P7)T1zU0?fRC-ulOv'
    'w02*4nYJ%@S)|D!7A#x)Hf7*~R5;k+YZ)%rf~uuaDm5DQ?}%@+LWy0Z>ICG#if$`JQ4=>coZVuz7~I!SzjH_f)F`V=9Q8IHdOQ4K'
    'kEPLm6M3YS)U{k+)@5xcTF?RPGiAWQThAw3GU;ouTBqCgm(PKAucuBDSnF&}C&+$2{@%9;zsUt_y5RP{2aH#h@aA{PB-~A!+!o`Z'
    'biPd}Y}EFQS$1z#(MPMaPvQXDG`3f~-+xXoVx=Yazwi?=bo`emCpC9qZUAwGXtQ4RS?QKvOu2*|q(08yC2**ScB6hfn@;z+H%Ruy'
    'nfhbP#;@D5=^t>%+EAOIER3(C7SRw`;QDWF{QbNx!h)KLXsjL;X|8U{Gux)D>02ldWuGd~RfQPbm)B@VO@pJVo$tQudAv1eh(Ura'
    'DzCMye9G2$I`xpB4$0i!m8(qk@~s`H@Azho4uyTN9y^#Ruy()OWPtsVo!lzAcD}r-8S^Ovt7MUqC+&8u&%2jvZ>|-aw?jw(aRlnW'
    'I^X(>#2z?7o6v?UwUoG`#~EUavhvnyrI8^Fx7q7b)zOxLk?gl3D_yR1IA1ng<mEw6`0UvxH3sLSM^IE(!Y>|pnjF<67}Igm$1m0P'
    '5Q;E&YZUKoB|q1F|2(=1^S9th$0w%@tLH_)FhaFLS^RKoEFfc!>{aX0Y;R~6%~Xy0;WO+i*TH$Ek(#`$?xyb!LmOdpQ0QkXNSFMw'
    '$L!!`pMcf4C}HEKnOWB_R(cJW;{ivrY_Q=up|Nn;ZQFI-*RSuM5w_f=>4^Z#cX<hgP_ZsHtFATd_v3k_jK)FL+3{s=-;Le#AJTpa'
    ';&IpQR%wK8$fXI|-W}F@twecs;W!(uf4;VmLL%Mo1FY5#v(^}`S%Nfca6U&H>KgPv%c1(ef@Uv0nlG;O=*&lvuHp)_iCb5WVUknN'
    '=U>$#7Ukz#TK($VX!`^Qa0JEu^7YjKqe7c`==Uji!hGwImT{#;fopZ%L@6(lz{hXKt=!~orA7mdlk+_aK-fm8?P7tEX+`fw|Ma(@'
    'CS3RG{xl{Qvy=bmXoR&U3vRzAHq%@A1MQNX^%oRKJesYLf!dQAOpBx5A6q3)Z23fP@3$!yDJ->Qp4%T@cUs%H0%_gpWh}?25Nd<k'
    '#YQ}1aa|0U{je5qsRe>;s=dix@C_m@6dh<?qX9MUH7?yiKG3~%cc5p%C2vtT|EC8e<y9id{v1<y>a29=M{f^qWs9mY3bH=YcCS53'
    'j$^T%_AAnehqklx-y1FlZ0EpmIxwcj7r^{HSGC0!K3Hz)r*GDlHNlsw{N5G{m$iv+4LIG<<gUySq1Ar3GNeok9CP*@qS%l5=1#Db'
    '<1}r})3}durLcaTG$Gk2)!rYOScJd4er}Gx0r7`1!pX5LE1iSTc@*3E3s~CM`X9Euj082Ax$}%Z_I;zb$HPmra=VOMJxT4g2F1F}'
    'Ed()%Q{q~wzGuHY>D54`%H6wFN+VcIv9>Y!@aW_ID|17P8V|dNM->P^a;KGxf9)=pfP@h5hFTb2nciCS%aZ{20#D$@`sjmAfBY{n'
    '^_20g4WxEdk_<4e>FV3I+RNcBh4TvMxbuemsg$d%0@FdiH>z+6!p!A#bV}!cF;W?VOdc-W^><S|wnXRWYulG7UEFQ1TyBq<-7LT_'
    '6_#CT?%1nY%cCG!Z{#f3E-xsPoJnWLoOl#dg7qLbv1x^DjA`j$Af;2QQr_2Zfc~4Ck=+K<?@r2ix7mZ9kkx+;rUwVV#=>fZeK-`y'
    'N)W~zhZSvi{ezsfPlAMbEpMYGIHiE`X9w)fyNsM)oV#JN=pUX$%TDu^YMPoZX6uP*#K(NM6rw;h`osNwaFn)scVpWw7S);86~$+A'
    'C0>WD-7x8Xb#4a^jfNHU75gdREtsF~WJ^Zxl@CgRf47|5v}915#9lp~!&xzVO}h<BpJx`>J)?J~wA;Ev=7N0L#=>5;;DqcG!fe@g'
    'smY;_RQy^X)_?ubALd^p8A#6c=dgE1nsdM@S%U_WrDT^JXgV((N!<H`I+EQY*7VzB5>ojXy~U1Vx|1Td&aIA#9rnyoI)AC!&-YsM'
    'i8h0~%B*_RAo#h+1g^o11S~f%NCl6Nv&L%q1|^ErfM+BfT1)OY2sZjea=#$IsSriEkDtEx?ZojUu`T^@^-*nx{IxdY`|{W@n&Z5+'
    '=Pqr2y)A_?-9L59ut*P{`Bs0|w@JdR*Pp#4;@MPoD_3!JpIsgN%Xu;WsjLTDdie2jogKZL=Xc<~ARScD@fL8o066iwo*TR9LdBQ+'
    'W!IX3A4?3s-)Vi!NrYz*?$#?-OdWs7gG>lRjZNAD*2vnQAMYu*wsUn0J{Uc`OdBj(70oHuJkez9Xm$&dlFZGcQ92;$@p+>2oi{Gk'
    'Z<bZ5c1980btLY6ki^EFeTpDbTnOaHdsh4*uA1&(G$@)?wtsNx%nql(prReugHFnHyXCbK;JfMMjeK^UmTkn<d9$@UoJ6nl31_Er'
    'Hv7AP$Jt2%EcN!wXR_|j!qeW~T~6>ag}Q7MeV*uFeI3=~J#?TqjmrG{1<%f?XW^dfjJSENI*`*U`9)H5W3+Ddi2;rbbmi~vuj6l?'
    'EY!m3ZvOu4MhuWF#?>OM-C$>v_yeBbmz8t)*{i@D9gVklC=mck#%JF?_ZVa}zM{EHqds|{wzg`vJ+})R(fFrl)iM_9RXzcdiAASV'
    '4E^D4J75r5uh&U%j<+GRnwewPd94qpa1EcG1=!lA-9y8;E_?Ud?%b^@05~Ww$LMj>`0e)$1g$h98Y9?>-v~F`$_t^jK%`|HkiBgg'
    's3|&q=XH$Ux9u*^VL@G64WMY<&}uqKWCeKJmQc}cpZux4nefOj|2h>mN5+sg5iMd?40kkDlLvQd*uOH<;h0?{5ZPJf)jqFh%V6A#'
    'p41y<>i%h5USMeV=%>vjI{JAj-esm(W`F(ACgf09J%sIBOp>itQ&^Q(U_Ov9T<>)IR7cdc8BThZPBwsP$7WfPCca%`sMkiryd}i0'
    'JYEWOKx4_z(4{!)$HQRv>7aGw%8$41V1Bl*t@3RmX}I6n057|OfC0pOR(u@gr`H7?vi@T>hL@Ma*^Cz2?bBZ3D`ND%qOEq@vj^JG'
    '_exhkVuD-rtxt{1)kkyXcBjv!OD{$t(nPwFhybsVgUU4bD4dB6XkCUl9KrAcJMisRC0oq<ij;g>eWS|;zWm{+fqC8H#}zhg2dF#S'
    'lzSZ{;1?Zt@U&iBs*v?D!_$tCFT(LQ>rbsVs!m#)nWf4r%40aGsAYG)IGh*mf+(B!Up$nD#N2|>2j#DtW*cc%*kLl*4qEWOp^Xui'
    'NiP%MT?ighormk&l#MFvld1zR)}*`(QGFEE;+`N<^aKX&iL?IIA)+6=zO&tjYMxgSve%H(wA_`yhZ?e-S>hzW(A~(XnUcBC+UHi*'
    '->jzuHrF-UXtXy{S7i>OP^yJ^V3)5l-2VAfHTIp7(=o9c@UqM+CR*__IjO)~O%FL3uvSghQC6VlUx^RTBil*sJh+kiOj%!rQAbLw'
    'O{CAC{l%_R9qs4q;$MBU2V;iW4fFFP98=Kdw&q&|@=zd}mMYNo^ZHokYP*rvh*?(SWY!dwuku`g=SFqC>hIbq{fCykXxVk)2Kx^`'
    'NC4mHh67j1!>9~QM)kHg#tgIyu4jgP?ht=@UmHI0Hdoyhvj_JTh7>LAZwH&xbE3W)r)cGqT{e4=Cu{JL{l&u+)W?Fk`RHV;$15H;'
    'xa<baqzbA)$!u)7MR|F~fnIBR7E8ojcW6uiD;rQQlXL0w?3}3S@rrcb&u#g$c<h^{pMEiT50ogbmXF=ldrRx3#1C<+C?0{|LwY0|'
    'KdpSc5WCSjw;hXz&D~6iplcj(-$G`&j=Zz(7J0IV5-5eLpZs`Qr$1fhnuR)S{+&Mb9`jm|qCNX4(2#W1N>vEB#nothM6Q)K)i+FC'
    'u72IG#P0HWFDLu3i82rtj<VV6UFVbLPsj0j6_&Ci;#Q~lON@@?=5D4{|0?kP0B(k234j&ehbom;X=jA}E>J1GI=%bo2$UKe+?yo0'
    'i+sAhy2cCq6>fz;zFJL!14?~EJ8Ff<Vq%Gn&seZW;p{lMHNtCf8mMWDM4xW07%V{>ShE}a{VZKqu(+wS`70n}sNOw%3k*CkMgF^Q'
    'A`vhHF7NIqpo-2MnOU4a`Saj6W)rIDMi4ZwDPX73OSkRn#UPK`raj{apPj#GuI{q)So+hqnjqxH_V^|~{^=KVybQt}Jr<{p=@-gw'
    '@E$MXNiV0bZztF}@)k&*5aFM^3A*$kWB9x;HMPQ+r?%g1q10Rj>q}><HF>}CvKrDq{mttGhp?1v6}$_DJD>)0<>S~i3&gmlI`Q`}'
    '`_#94X?Peiz7~1(oEjZP18T-~Ap6c2k`}&I2nls;4BN+M^7Fm!jycN3IkR|dnoC{bFd@f!kg9^(PNM8My=m#3bQL1t;B5N;_gbFa'
    ')r$Q<+{u^6JlOyI_&!fNi`Sy9Xs|B~#ca4og~mZY;2X?fQez_%XoKGP@}`U~SqSg{MQQt*tEyD<%1@*b7-i*imcILkpTYGI_I~_>'
    '?zt4A#|?OQxnUC>5^kH3$K6ufUD&=2a*fhc*2m+nb(lP}wz8|C3bW6zL!Hl%nS)kI842h$7dB1t7R&xG?=+NUj`7>56`+)lEv3$Q'
    '58UPMXTfTQx?=43x`?!H#z)_IYwIp`=-L?$qBb;_TVRi~TR?uEw$Bt}mDT{;VSf2H5jSkZA}aa^ZhyB6kF3D`dH6s-@|0}>94(&('
    'b^0XyW&$2@rSF4*t;2*zF8_}6-TQR3=e>rJc6)S8AOk=Ce1or<L|=q&K`c(YqOl#~HBj}zM|$QHdRF7rb3ZYOT66YVqA{7Dkc<Ng'
    'p~kSUibkCGW(s+hr8XwaqdXydJ@e<we0C@ARFLH3==o@QZwtKGF1cjuO>41vUEYhC6cAS1QPnI;o`a8Zdtt>ATvALtjj@)|!Ct;Y'
    '`j|(0p*wV?-(2X+@BhI7sw`^PV*(}}#zRJ7L&@5bopfKv@Jz4y$&pt6%I&(mdiZDRwa8C(rSiE}!8QPl_td=hE)BFKhnLOoFaKI;'
    '?bUmEBa%V~9b`h^M&@2h6tPS)(}p|BSpKCHapN(e?`>>H*VN#}oUW{lTXJ<?YYl2^$+}F*CcH%CQr!8~H!wf>wz{to%a@{OxlV%}'
    '|Fu8yJ#vZir+$dskD}7LnDEy@JMYD+c7A!%bMT(Klbuq$y3vb>NM3WWeYthmZ&$xQYg}G+d{=fFMDRcdkLovO?Q8Gj!%2A82eV#^'
    'SFhxJ?@6?S+v&jF0pwlpZFBQ{cu}ts<(6v^5+8e@c)um+&rh(iYmNJ)Dz$H2v9%b{L)(s5&2v(#mf<6THv4pcV9$o5ov7@!2q7Ae'
    '+&m5)R@^OmgYBZmv=CX4jPwmD%c8IT_$b#6R^1I4)DGu_8TR`R^h}bkF`<>e$m|)=kIu_UtIH~elH30BoxCgfY!^I+$9un8tkc^|'
    '?eE^z5SdKU_`I}!eBW(N)NcFps=d2sOSS?#tM!S#hcA7%1O8qBev;=#trB&t64PhW+C~x9Tm4%p-Yb#{ag>vXBq3}|SLu1wodo#l'
    '-CoGPGw-%u8}N6tg2vwbN!aVdsO9@|HSlVldPV(Febt!Kp)>o-BBk}H{cdoxPxsw#iD<j6cV4Eit|0_O-R+OJ-`@{hynBsW9PgDL'
    '%&|2Q5aW=qN<?rE-z$F9o4_3_%`3)AdR=T0(WYLbMvSHn??I4f;|(YaFEMef=M_Zo{_SxYw_CIOjKn^RCnyUuKAZy`dP|czL{591'
    '>Nfx0_WK(H!sDZSU*vBhm>-Ps{CX-*Pj+d&?+-8!N-$-`=K0kremnv3;OYs~eKNG#9Tws1R5Ug?+LLuXnT7CjCG1L%_*~8g)KyXE'
    'Uvc-b=dX+I;5YQb6diCAG=uxH_IV#G=<Rm>@dRB;I)T>8c{O(RdAYY`ySL|}CHE@XmfpRDHxy<T%+H5qz7?q5uun2q)yDr$$wX`O'
    'Ac~m^f20clsjbY?i}rtWRPAlOH|x1Kp+lIA7L=XKnJxAy@tsVQdC3`__G5T;r_c8OOv3;^tYQa+81&oo;mdWqmkAeFE&|&NJ^-2A'
    ')#O(<!|V+h3pi0)<w@8X%>um=7e4aE=&zi?Aobj~_f=GW!lJv#$g*!e>Rhz1J*HLWv&&~5bBKnYsD7#5i0e$%e|sX4-q7B9;H)`G'
    '=V2@6Rdce37xhbd3ybO19ov{xhU?3K)3MiNIaA>_TU(7je9`|JI&+1|TKNF49~M@g2hIEG$J=-NN585_Rf#+fKHqOUuAM43sqng`'
    '^J%06%~l|<KOZMuQYKa!Oc-qxLGIzUQ=09;D{jA2M<mlMxhs`<J})6ZpKi};Exs>z*B%e6aCR_oSRLZ0Wph+u=h84a+$xLvbGMn+'
    '*EjURicjgaOYS?j=)rHS(z@qjAkwN9iRIF~8`9T*`=Es@H?8kv{90&I51C(^t2#ScKohPXwA<SkRg%E|I7Ax~-K=U!FM>Cr5%0@4'
    'W3g((iVeu@vw3LmzUg+NCeE)fTpiREKQ;xr9(?Qm4B$bu?dtL?QxxxWe+{pEja_UY1&W5(nLG*#Z$qru)(x?r$8{DRjEp`?ND!EV'
    'w>mjYesk`iIXc$N(YPdduQ-b+@H_op*~{ua_a04VF$yFKyAOeG(7nFsp$CIvVAdl*mNhix*Y=7=`c?T@C+tBsu9=PBoDaB=G1J}x'
    '&=dohs%XPcce388LWLv`QfXAy_CiA^bx4}lxoX&UWN8dL?^s);Xs`hni)wrjqnbQarg8*+xnCW6X_N8nL_yH^x2Z5lwgVVEE#kvY'
    'C}#7i)F@V-?+ac^?A9k^kFt}q)a-C-(KVTR`f9!V#*SkS-Q$z};q_Y+720&&bJoV}ejlf-b5_Bkjit9@dHbNFM1tagFTwYZU9->9'
    'nduoYaw3KPiPF&$T&c767gZxG{7k~>VE&tb%S^3#*=^u%J+w-*uJd4^lQ79te_Kks^wBOYj^3dX&7!E%d&Zw`(zU&VU8q6(^qHl*'
    'r8PcZosSUsc+DAZFTXtkZb$QHmCFz#aU}id*E5$#+ZXm&Uq+WR_KMhJx3F&&O~pY?O`yp|uUv>jF0~Wt>s<-0x~=->J~FJXo@IJi'
    '{rO%GFKyHHMz)^ln*5muy7VT>EVMoBS(d5Nl2HEA?|@*nN7jaxJk``^9FXquaZ)!tFOM4)=FGJ#jq!YW?1}&ON^}ns9?X*kh~D5t'
    '2U%>~%*wW{e4R4!ov~q<w>#cLf8$4~SKY{u-4FvLtI??`3wSAh$L-q$MS;49&plCd=^yTccW0t3>#yDo7_F<E>oX8=bE@LyDe54m'
    'zDA#_1@Zlya5ZG!*zT{2-APSgF8C`a+23}vIc(1L1SFT#jXdK&+_&4(5l?;k`f-1>c5rc9cDqWiP<M0U?+>m3i*c>7?&TRaL9qvT'
    'DQ82<t{*ON^Eg!<eW$~_Jx4?4bFmptOY2|1xxM<s=|nxl+WBm4Zf>;8Cw*z%-5J{<9LdEK-4}_zzTeUAN>sS$kj02dOFd~&TCpr^'
    '03N+vy9C{jpQ+5-#=kj<+8$`{G)uuSvXb=J7Am-d_uemuBcO3^&rJ#tE&A`x(6!yfh}mbYIz8-Bns#ijd|9GzuH3#?pM7SmRhk#z'
    'w+FeXsn5dnvB%ulq~54R=CU{5o3yfe!WBo=_h&E(?(<q^#HGWyEPmaQFsZ(pHh+T;n$);#AGwcD==4H$AEV#A9wn^*u8zqYO<&nN'
    '_#+;qPnoJN-$;3s^6?3R_E}|k*<8QXV|(IG5|$J5E?1AUwlk{4<8;0q=AF$L-8X7IwerK0&{x5WnX=!j6!eE#=~w5~4o7APSYacs'
    'rsl2wA!79aUWMji{D)nAg1mI%I(;!?XE$=B4mzdc551jvb(M>`pDtqHn?unCr`*_GcXi10D;=00!uMPI(<IjS8EhfGKl@;Z-~l^T'
    'u)56dadr+a@{wL}L8JYu0a<Ad_dP##6WROWD395OGO?0s%yAVj-;F7fZ#v!O;|PmjE14?HJ&sb15*pF9#1qRjt`|hwcxF#Yvojt&'
    'e-N@=zsjBS1%6PX{i{Qo$xU*(xhx&l(ymu4Zhq>dO%rM~O#Hf<LF`g?{6A!D?n}YQ4oCNg*q^}L6l?%hKcvpDdp_el(?gk}b$(F)'
    'eDQa&6iM!1-kX?n9yJzAq`OzbbRA(LFi0hOx-|P+H|(OsX3}BZ1h9|mDKRu_@A2!n?+*2E^Qjk^&~S!HXY|YK$20oYv0e$EjG=vm'
    'y1U$u_&xo|TAa4O9OX4+uACgC&l}4#Dx~|d0{yYMm-o9Hapv?Tm5zP)R^^$pG2=A;r;G5LYEcWJ=e^#odqto3yxU;^to0G3Wz>!!'
    'dQZm3aCGLf&NxhHZA&6k)`6-2Qb#@4iJ^;s*Lh_X55x@KUZEde?@r$j#zyQhQdwi$;LNOQ6Ps$tGrY-&dN>$6G*)^)zdp_1Wue*u'
    'oT97AHwP$<{U)_zDquL<T*jrxv|hen_WZv&z%RZ;gm}8Vlw!vX&3g6G>dtSZq29ojVkz8wdN_Y5_E64Z#xKi6{|Ypw%8ebL#?}6?'
    '4wO6e__Ri!PVL<^fA?b7#OFcW;b1!u6=Z7z1m38gO2wo@uSqg5zce`J`;A=s4$G?};!`Fq5OZvJ>NgI#o;1g8<W?yyI#}7^6bktH'
    'qn@`+^TwLdwAZt7JcS=$SXeX%T1^3$id?J=Y%V6B@oKefl;Xe2ZA>0b-kSoO$x2yYX4lc$*_<9~?O+ad$PIpcNwvU%K92YM7b{tH'
    '-FddD+LPM`6KAaV?X-ZX%GMX7@B8plD5f0|ho#Q8SMUAWO}Ab2w8{7A<N6G6JbykF^7K207XMd0pmli*9*HR2z2psuf=}G*)wKO`'
    ';HyBh*X&?ck^t6e)Nh_7>RE~g!O4Fq6K;S|_;sqSxn3sp(CbZK{(eW{<d2YKF5MQ3&T;HG>NUMfr;G?iNwt=2y}n^>cy!wJjZn+8'
    'F&C^hfwcR^!q66%DY-Jy$X?f5U0GU~qt@r&ewZu0o0LTQ%Ukt{f=pc!u0HntL$y1dyY%9myoWQx9882m>dntN`wT$sTmL%>Yi}8o'
    '`YTbF7kK}?0gDF~ib3$hJA<;Pm7L~#cnE#&6Ra=1X*9OVCH_kR>y;*~ZXQWSsJWer;YTsY2|E5DYOHPF>*<D^W_8g+Yb8o5N1gus'
    'v;5V~{tjJ{OAHXm1UMdGm7CNaa|?uuL*9eR$1su%_?*hc>5}%d2mGSR;aPjaDM6wnxC5u(#kB`iT1-{4mfZ62`yHFA$DR6hp=;EM'
    'iDV5L`g%WH77c4WkLXo%WkuLyGn19!#cs61wGj*<tGl%Ma((rlS4NH;rxEn(_R?ET8PJ>gFYh?x(z<Vq(Ol>@V{LeuTgCA-1^;UI'
    'GVTN%aO->%w7)xUhFWVCYt*cH{wxU-O|S7NNqX;2&90rCc(z{|(!N>w^@R{$1C0@_?W5x?VkJ5Lwy}Lh7>@YXJ0FM)mNbD1q2uSd'
    'W={;Gp3k-B(emMt)OulEgE~@qak^(b%rkH5IQi|7<=bcX&>TI5v0Uu+88~QO4*6tT?0SQ~sP@uw3E9Qu@m^F4MoeS<T-A-MG(c4A'
    'qo<y4#YJh;HD#YmR|HD`o2z@R?ZJs9KGIF$FYoGx>Uy>}UrF;)i&lMLxoYX<k+Ot$dRKV&Tf?thnfxIVVM<E|_t;jpSK2V15y+`-'
    'H&{47-^#1xHK%OSI2;?)y7#jC?~X77J+lK^-n)D8sj}*>#&zrJmg8DpBCOp}US6NikRA>mBh$FoYQygWIG(kdwcV6|doY$t(8x+c'
    '0G?OcWlopi7<itbg~jt~HL+Q!QMC_9D(}1f!vthtJxmTlhjLqH@~Dm(i0rf=q}QnI<xfHd>HBxzfLFiLnl9>hVsNGZF2nbMy_Fp8'
    '4LSpE<UcFLgvWgxEbFh@h3bRwOqg5~yxm3y`*NQ|d5gZZ*`0=IjCE*G+3y^}j$d!fM^Ag7-#~efCD$&cxU^Z(FCOrElReGIulEt;'
    '&#`Flc7pP?7Pw|l%<rqrSrnyU@lb);a%t@5F!$7de4k@qC+uY@`Yi~fjnnfrnT+*;?U0=OYIe%?CjoLFaH#B4Lk{bnd>tkJcTvIg'
    '16aO#=N5Oeo-NZnvu)3gTGwBFI~GsJnDPU7kgR9zjNMf^Ay&W3c;Nf^;z|WByW2qR&LmQINgIKcqMC*q$@{)TcbokcdZXOii1fyL'
    '*%u^y{cw~w+9)};sJn7d(hl3xVArt_)IPTFy9pLk*GoxU%-St@xHK1Pf`FIilrncu;30QsMd>Mir&JD<>|~O<O^)ZXf8Q;;nw{Rp'
    'TCY~h?Mx3H<cJ3DuszE6l;-Pn+#5bsA3Xb_AhoMOy{o^|R!Hm-0gn}DXO_xqKn(cK^_gbw`o|Nj&Stn+HRctj{AsCNfo=yS{!)hj'
    '?m*Zcotw56FPLXf($v<oRcy6MK7UnxnhV>H(Ufv^+tFn68jd8WEaa`{&o4KT8LIK0*Xr6-h+dBC@0GME`waj^;s#o`wX|ne!y{CT'
    'FM8Kp4JNV)BO264AwURniU6yVvF!JIKB}<e_UfmT5!UeS&mQZjw<nti`l)^@Ht^T`&=<!Xxbrf-K9HSBrE!|aH|I`hue|ZvB?vDF'
    '<a@FUrbo&nKJpPg*NI1Ibo{-q%mB}o!x8V>5e6Gq!+rG<cTP-aHTJAkkCyy6hmXl}a-BzF3ob{}z`bH6&q@wosQ%tQ<q38+XPaJQ'
    ')PE}7_@_Hv)@^XuC|8H8x+&7$9h{vI;o8Mz%iXRV>>C72&^b^+aUvvpxK+xh*9&Q98aVBWW6U^iQHm>?@p3H;OAt`|>Hcfc75=_W'
    'fY1AN*eB-F#qN4Orc5p#*Uqmqw>6^<9II1H-s9{Rr(~=?xSh*<$0li@HBOO|g%kDtyLHM+pZvGSC2Aj>CAABosOL9kP()lZ=dkGm'
    'FwtyuEB(?a&;2-9pL_GY4!1dSzS~@y-}~G>;O}aj0{Cckce)Ur(raw7;D2~$Dmp}S=>#XF_C56%JI=YUq3ZLN6H8&<b?aysgk~hl'
    'ioJ6R7ozf@7`E2{b-*m9O@H@Zj+7}T*O9fT9usu>^MMo_TN?*T=X)bo(`<9DgM{7PH{b<=S>v?w&{vb>(65?prnAC#>c>F`sWZ1C'
    'DIBnIemD(SGK^Q3PWFb;#}57ReM=rI+LP%0EsfA9Q#(gEl#g&7Q)m6&Jg$Lfsxn5-9P(OiFueTM27LR~l62dKeDRK5)$;1q0~QdJ'
    '@PRB2h2OrF&hTmV&VxAdkCQcm7dH9wFXv(0jIGuM_ba9vKe^Vbbvo1gU9|PJ_k@oPG&%GRf0gzV^wRf&8RjQtaCd9MKi}ZcpUcO!'
    'G*g}>abAl$gR@w7zrFKjc=LB``(TgGvx<*T3+6IVI*sQ*>VZhPN%cB}pucw=_BpJhXqdiz6&sI_zkXgEk>9I??DqgW>NXzG=&20#'
    'W+~TBUXZE!y=oQs(3GWYT)vq2Zj23foBhejwf`aN%63)Ng5b9hhX{lOR1l&vD1tZ(qQV0xgP^D&f&vcTe)oOx{J_p~?WVh`y1LiB'
    'IknWr`;tw|2X7Udy=QYU)P8x=TwcJ*73xmee6NR{a~aHaWCtHMld>KPt3HB}gK>dpnVOs7`n(acQ{nq0M4pC8tABo6VX9>1+hX)Y'
    '8?8Y3oj2^`Qn71bDR%~$34dSsJKD)9WJK0;!Z~ZY2r+j!&?iG!MYi&JQ)iYWc-@i84VvvuuS)LgIqr`2+HG??-+q3Wq^Ex-73Pjs'
    'X1&^&?_I0yTTu1T{H(}y(VddF7yRnR;2fB2%+0L)?I_<V{pceV?b0l*p{q|SNk>c3n%!LV%0HdJYhe2sM_C*1XwFc^hHf<|UT{_B'
    '`rd4ztgwp}dp=ETtrvWIlzej)=@vS+WFIxmyULVr3cGM$E7z*eyR+l-UtijVp8B<HdSAL9W!Fw1me82ufm>_(o$q(x@p#GXcP2mx'
    '@QuSLKEjXx9q|~v2$}d(f^9BPk|k7Kb%kjA-2djVyG&858$<E!gnW5HZ|c?mN&M!Wu$2a|RIdV8-xpiFlp_oOxKoAEmJSqnJjov+'
    'T*mY3xIbS<P7w%YEz7C-Pp3`1<Hjm-<BMBPg6hxW5BXKggVMDtGVb;8kyoF1Rg;M!?Y5-b+oc)9ca40<j0(23{k&hd6v^xAblX1;'
    '@;v|b17=T26Rq#(|0ZN<e^7+y)G`_g;Wchl!=4LWU^_$RI;RIIwlh?0$eWtB2pt(1AMe^b#0zRMHxXigqL*J~_Pd8&*^NpDB{&aU'
    '?lTnN&9$!1;?&MZI^^PU|J2~32Jf_<eW^`by4^m&0@{XMP6-JVEzDEXnNTEQq&aiW@##-5Y4RI&%&^+@&bRwOFBZ3t9PETx=LLz!'
    'gUMtCL_tRcJ}oS>DpyYEVNfO3qbhu}k6xs%sm^H+?mIsIEj-?N{`%d)IU3wHIm>1*R;(b@Uo6q&0gUmW0#q9>Yh{@tl4T%uzt`Rz'
    'nzo8&>+jo?y3>LVp0ID&YUkp-YDjmr!%Bl+UT-~gC~zJF{xz3)Fdp8IU(VTV&(1iqwzbKkOpwmgX<Zz(1nom>a_CCxTqyTv#qKI4'
    'i@a_2Px6b+wYh#gCyjspvwR9%qIGi!8u!?vZ{^f!IE!|=X_t&zvcp=vw9#(WFlG+>!b}lYd-N+n5#UL(9OEiLVg*syk<<Z%wlq?I'
    '{8*OI@gKi<P1l%HjHyZoVC)Ge5mzs9p3QM-maCM}hGVKt==1;Adkj#+x$3nR+?8y{J7N#N*1JACa9et|XVGtNv0cixpIpt@o@>W9'
    'zD=5?A&og?PA@Ti+P3H7o!UNM6UqGY9c><OR@S}!M>KJQEcf?d&x3DCRPbXsbF+w8{PfA~JBiaHYsEczcOGV~+P2<u7?rPx5x3}f'
    '*AJ^bAL&%7?t{B^Un**SrRJsSSVCe&T|GXa7cIa=xp>ap;<bT({Wp{{4vv_++c~X+YZ)}t(mYbfZ|w4kQqCoNOa;hD6BSl7kYbkS'
    'juHFDC!c&z=jS~#FZp~Y7%+jMoAYu4`@g)yySnnabcQFbI-LXw#n<%y1S%Ltczlgzr#Ut5z}!e5LSsEBAr+BmJgzJ0oo)}C?cN`o'
    '!E(Y96MwfH<Scy}{qDgj?WlG`_3t#8ZSRT9oIJ;Yh4<&O$_2cNXB63&&{B{4&_W~B?ybYU%scNkhe+!3nX>)MdrqZpIR~76Uo?Jo'
    'b3NVm6x@_X^ApW}J4uv1xHU)_O#r@}zV(I_C7KEYbxn3wM3JRE?3n){$t2vazKmcJ^TRhVHE}tpSiNeA{m19!<a;V}%UiW4m+$2<'
    'za`+?XpOh!%El9?-PY`#cc%Wcw+?F0j{Gi7yOBgkJ8RvcAV$Kp?Y4|brG7lLXS*%=Zx8(dS<rQ>@WID|vF_bZg>pvar?B6p-X>1f'
    '?%BKQ942@9?O600?MVmH-yxkR<Gw$EPaivm2JBnQ;`WyYKd0Y*+D$TTF0|pHy@o%MdVE-H>s^Dc%C>U6IaIE>i;^-a;FotQif+EC'
    'YsA#di>P9x*hF<?>(N<2LfBvb6~wwS=6`iQ9tmpc;Z0*LETUn;&J4%GNN{{*wV79}FI?U8o1ZoB&abK3dQ4h9G;jJQRUTRB;eIun'
    '&auBP@3`)c(`(M~=hGb%)yfCHe6h_|zkNH+SJrf8x~)Kc>gwZ*YAo<T%e6W!y8O7WQ(!SHms+?Ia^{FDy)t!lnfkNTm#6Xo-qM?&'
    'Z!q`j&Qn6aBl>22`vA}SDsp{(Cgsg%_~kB-K^^aD$ucAL>#|hvNNK+$@S)U;YI-J7wa1G1_MC0W_FeV7sBV7qZ;M`_(Md+i^KSjN'
    'x4C`9ci2;7nABcj+*)pRDc!f?Tz;m+7(x)v9!zff^JU`$54w?NVI_03d)|Bw=lZL~4S#&71SHccUMHLQU@KRG*+DR7oXs+(Ew_%W'
    'kd%TC<{VG%rTvN1GhEAuYG0NwxHnO{X>^|%pj_m;heX(FGo!CReVyk6E9oheObV8ftp=w;Iq;7r07P~BR3)}UdS7m-4Jl<`RivW6'
    '&V5-}a8ch*b#bSy5b!{<*^vPFXghw2>*K$@w=o2$mz6N`&lu9^@$zx^9z2^5^L3#exk)<GWQhQUbsg>H^~QXXgZG5tFJsY|mQ`cE'
    'dYr*}EJq>TtVKoR$B*A6|7BFJTA2zX{2+%_EPX-At?|M|<$M=saW#b?pxlpVIC0loJ()@<;F;RI-!K0W_LZ-b^J5;zPr6*`ee+-5'
    '30vD?=z@h(?JpP8o4t7qmS6~hT9hN*!MgDb4z^5LGn*_LkL7rOyNvsBVm`IAo`%TbZOQFZgB3T$b2kgxr{7+bV%ztSV9>33rN{%i'
    'W{dTUO>6<I(2nu-<Rw!hLft};Zfi3*e-S2O8pvFg26CrGj?xWOo6iA#RiRtE?LD@CdnK5?u(Fm1I%H^O&0oqD?L(u}HAId#!##Pm'
    'J-vczdJU!2R3!Pn*GJi#F}>nS2~*eX#5JPpZi@9{ez3Ys$M(-}bW8bJW!BFR%cpK4Q1n+@7F#|2a(|V>o598bH}FZ$tgR{p1tYky'
    '#taWejW_m^2@FUU<`ucVZmr4d=7q@gU!GiUF!XpwTgGCLRZ}vhz=~d&@5;xv@IdNrnTBECv-wr%>E+ull9W{Q3~JV+MpytHvFv3g'
    'tx)~n1Lm@2aqz>FSnmP<6%bWmOX&m{x69eaBRf+Dc6Z_d0xvu@b&L{cYJx1m+4Jy7su^*r1*tjPP0H4y4=$MbaR6SG4y0Jd@4Q1e'
    'KT@14Za52<cJ#LIx2}KH4Eq4Onb)^E6y5r%CL=OVxaWDb?x2PeoEyu!faY2U-YA*XH=_7(X@Pg+R{g~p^U-iK4Am*T@E?yu`Q4L;'
    'yPJ5~R3=zwHm&aBPkAC928#-4MEv_D4}{JQErz`KmIf%%nXX%~Jzn;;{`s|-wSRar9wRS&SRFn`xP(kjl{1wX)}|>+MCr3c(L<Tk'
    'Wn@2Yj??fWbo=<Nn}3CCefMz>ouQ&_*ZNn%*Xp4?6mEE^{`&Klw=vZvd!L@Huf<QI8^ZXTeKNjp-meiOl=O!AkT)XI>}V})zFXSK'
    'dAv9-TdY-D%Cm_aYc2;@#3khnZW4q3`V6!``8283Xl%8l@we-?sxMV9!;8(7AU0*ZQn9`&eJ=y260_s?Z7j#iXeq!iqj-26%yZb7'
    'zIocGPs00fz{A<^9!Lu4{{8B$v+0zSB;bc@whA75^{#^~nbtb)>hB8kj0#41S^kjI8~D^>nS8%9JNF}dQ0}!^bKI&vr<_V&yTc!@'
    'R%XZgMnx~+H-`k|u^np61@^{0?hH*_@WvncCxbi<Kx<>4u~q(lSPke$?+$T4v!Fkl{=XI#Uj&05qBj^>{P`+q`rcYZF|!}#wmY-W'
    'Zr)jGbnQyi&-)T-GK-{Koi0%Q`ow3e8lL-GqSjrgbCaL#RxY*;{OWtgh0o{087k)N-@AzT+3Hfx)^yMEqUP4xtZT!%PM*Ts9P7bK'
    'bDOm!xJEN-U_VD1w6C63&+0#FBl*f)lweWs%%I1)R*pYx$2kA;1OJEEn7ovsm%Ut#_K7i$1XEca%KyJ<I1%OPx_KzK6_I<DgOpKZ'
    'SFp<lBV6NbL3F+~Pi?k+Lq>{$&=l_m;Qx3F6n<5w@&>QHO<>>EsQ39=$PV@f+xxM+D&pu|!3ga@(!6wUXA5z1_DlG-c_1wI^tP1I'
    'aD>&yw@GGBXy8)*eaALFs<?$CAVNfR+)mJQ`;sY8Ua6<P$C>S1>WkE_%>d;6Mw&5xUoLv@5X8g^5!UbEbOe+qiCYYJ<;&*|zxtPd'
    '?<h2mhb#2j4!5rGsN2)B)8uZ(;`ubUhOuHb47e%U$bijni|;I+e1$I%mNDkg_WM|svDtd<qTlZ8Ig){Mq5%JVOpHocNQMM@AxOj6'
    'zg63R!Tdeein%#FNF?hXkNC)GF7f()VC=`m5ZB(FDPKH_MsW%5#=}S6CsXX9T^nxy@{Uj)f(-H6sPt&Qo(*=$rsB^sc@r1cUDD6S'
    'p)r*c`_Q5x{d;K+lmssm<rPv-$=A@?Heuq@_EtwdRblA#4g0_Ng$X(dFmK=F(p`Zz4%?o=TUgV3KRs5Xn&(>DTbcrJ+cuiyxq^>o'
    '{(3&$l%>wT7l}vqMT6ja-xcUq{G!|Q!w>hd5X020ev|D#n^!e*;`U|v7d#1yn{tp``&}rZ(z20U-F|sF#bq){3Sm7h>`Y5mqalVT'
    'w-G=*;1>2x*$4IO7Y3Ja`oV_D4(<+{v#?%!ewTAY+I(#6p1g>ai+rHa*}p0~v6zj6>UX9E;d+9P;?Is2iO$33)8$vJthe=m8$5n_'
    'QVx`MVqAwiE(D!D2UB9zdCWMcC`I!)REf=ARIt*OI=4>GooNn9quO<(_jwiq@3$13U;QIj|2x((s5Q_i`1SQrcUM}r)4{%{@Gc7D'
    'RJ+z6S+y&5ShrtpUbJqb_(Xv3O}Pne<~y#q*S1vnMUG=@Rg2wG{pvQ1B7BUTIrV+1KRlU<$$i`6s-T)Oh!{#zZ#B2ntK{=++-8iA'
    'yEc|l=k;<so$^xBnmatH((lT^+3se=ey9_AJ$?3E@9@F5J+Jw@hevO6To~Q{zH|a&qU%&EYvA~*0E0y@UI-U$>iyyJDO9hj-^=mh'
    'rgC>QAVx>;f!*RgFy1wTt9BaE@7Ri~eBAz>7ptlLNjQx@B3|hat4#Uzm{D7x!jJ7h$4|2Nz2J)t(pH;v@6M*6$u6U#=fuh&#sreB'
    'W#aD9DT|?eGjDhD)%&Nf)0^fzFpeu1vdnRnO_^3zbd~%r!VZvm!LjMpI(D091gg_1k+mK;Pi`9n6`LRY74d)R`F^5S+kFxq8g%sI'
    '7bkdde9kJ8_mSDL(Rl(=gypK$gD||i`#iL9qgin&BU>~wWR)s|9oX4&gAw;fOWT!8BPRDF;9LT;qLJJ8VdIB)dPS%GQL7K?p}#6F'
    'eOHP6xnqsm*z_sV?v@bpzR7O6cc?CV;%@bVaU$?QuOXL}RnRT-fq{T6{)T<j4NW#5KVK%flEIbVUNrUQE4_!v`OJ@w-{s&9Ehv#*'
    '27;T4Zf{G^pqIz`Axg8hWZ;g`h5G|0_&b$R?-9^EVuqjA4qyFr&p)m{YGloTNJeQeHW$N7OqVh8@<Cmq{A{uxMMu$nY?ef@e(PJg'
    '(T2}xzchO+GRv(7>9n<_?`KctueT-wE5G~znde9qKXIIC?=Mqcp|ZlZu-)3zmmlpG^p|tI_3b7xC5rI{-n>r198RTqjV~WhggTt8'
    '^j>bPg-xT?yYDua-yBL{a8sh<59UZiRBaPq&Mx!`Q6_(ML27ZvUIe7U+{U8SHYcE2*{?vEaA^pGMv-@qdGRcrG}61ar^ad95nTDl'
    'TSktz_J=EDj6Yf^`aITla7~0^HHq(SI5nVjvd51Pr@mJo_Tl2zhojq76ESx5AkO!?qm0{U<roDU=aLp5nfUF&XmqW*xb9SE<LWSn'
    'mK{QvmX=8OFDw*eywtgX%x2|hL)?v@$IIx+$smc_<19iOCn9{evBI|BZRIG#_t%0_uD^PbQ@vz(?LKlA{;S4`dB0gH&L*R{k&dQ3'
    '*%><53Oq-LHMYx@`8D%4E!@$1!t6wQkNA?&MH#YGVoAIj^Zn`Hdj|q0%~t|Utyq<z4*Q~1*{fKifcZUA=S`DNyG--a&4$|5fzXQ4'
    '7&P!s(~;Jv9$sKa`B-<kCxmev9XJwaX#d{(0^TD=LA~Zpg`@hiQdYki+%N9~uoXnrPKG46lXg0+%*8~h?rIkZxNxv3Qs$)foVj&~'
    'u9TGL>DX8lmfid-2EYE$fa&c!e~j+Rw*4vjSL(pg{zd}G=%6IpA2hpTHCM&WB0uhscwl^0sl}+u5LTR5UP0r2vJWV0S(|?O?y_3?'
    'eQ)KDnSUB04NhP@FGi!aon%CKO1}I3I?*sU)enNIOF~lFpU2dhPpeW7JU5xO-cFTg$3p0k@2$evgXC~PQa>G>A*bUTUfe`}GPQNP'
    'S|kB^JiNvuJxL%lEOt8DKTjJqKG<%(<75`|Q#S>IxezbL)##HtCb}(!cgpfcGZMspd_Epd!uILQ9`y1AdTg3}saj_U=!>-RO7iqy'
    '$=uCa@nwS#^x>|iu?7-gLX+&Rq3IMH`=5S&(Nz57Y>kyhvS<I!Ym1Kn?~amQHuTmAeVWsle`ribI&~Y|UfB$GYLeV<c4U6YpH>++'
    'AA76hBW%Xm9phe|^s$-txnoauKK&B382x+-s-hbk@UF<YA8zpbWMMZUVJ1Qpb==tGcG(=Hmg6WdKv0{lO|5as+3U61nMV^W5ZUMw'
    'H6!zYgT=Vp>z|*49}fUNUf@qWWYLb3?hw$t@$gus(dwIDJoDw&m?O&h^MIWGPCP#r-1&jCvqpd0X$K-zeihO<X60p+)KFCwQrY~?'
    '2P`WMQG=&sA~Lh?nMbDlUsY~30FW4$jP$W1U~Km;WPil;+|Gd4{S<ggX>Ub!+!FtKp^`avOS)DdyHDY^_rE;?NID&K+OuI-39Y_c'
    'g^Mx`*V$fcwj?828FktD_EujGyNmO})cOtY%tI?cecemnS|0dWllB8RKuQPFajQ!K`uQg*;P{<aH|2xh^;cbQk}fBV0lXv6{D#9P'
    'Ng2V;(&K#vY}We-TL@<i^<UbGUQJqk6J9_wiLDTvdtSn&rv3*`fBh^fh7NYq)5L0O$whg9HOKHv8bxBW0YY&h%-((1U@N6UPGA1J'
    '8xIo@d++ZeczMUf;R+JPUkbLT{oSFwaMhpgIki$Y4zdApg(q6Jd>qA(B2T(2=k`KxPyVhbjQf(cM-8}(JXh{=J6UCWqkUgJ&7w7N'
    'GdBkLX$V+U7m{8__`QFj745J*dk4+sc>#N_Sbc9Lv=!?Kwt$F6Z@3|uvm0sZx^f?#oSg%hecsL|JW>5j>jUW&Ml%krj8=*Is`U)#'
    'm(Ng(-yHN|a&0f?&TZIlJX?#UIkY?8k+q+1qC@LCb=U}Px{<F|TqsYfVGRRTt1a4^5JH(~tXk1cvo|VsB4X&L8+rI{Qr`h_-D^^3'
    ';W!q@!#?oMkVDI@`1|vc)v8rMGEL<i!IVx4-L>wP*OSM4^x$0oRm1F-#<GbLfP3}~K)*aGep4pfRwjv5`zqtZ6JJ-eCOE2x&w9Od'
    'ppsBaPlv~QdZ|ha69cDP(>}E#*{H%|uRUm&e9L%05`Zl>2?W&pKcB){CHp71SoLH-{??O4j}prZX1^%gdRk-q#;Vmd^J$A}9vj0y'
    '#{KD3CU2+wQIE^s^KPBVA-X;R+*$I0gmR_Zj~Akg9rg~~bHh#Az3LE47q^CGrnmcEl`_9HB75cjS`I1Ko7rHf(cR7b+(zLmS?{_p'
    'kFd@igeecGQT8CG->&iVUHRK&G4cYbbQ}nIMc%?usV;qAJ~&0^#Hd;3Wv`Q2K4F2i#wS07hy5dTxK<Td$IJc2Som7KRB!f$=JOPy'
    'qksGOPoVSepcabu+G)H+htEN3(u(!iKM&9EBq}LqcP-V=JF#-Aq-J#vj4Um<i~y$HYA*)H?0X5Fy2pICb4^;D4?n%y*B%i3houUr'
    '(R<SuW|m2Fy~|WwP(IOt_~t8*K9ry$o4e?yb6!!v)qH?E0~m_4X0=^Hq&xD)8^O}5tJ~A?=W8Q`Xws5$l%RY5L-njnDdrlp<Vh?K'
    '!wslS*%?shiq`=4(QtAn=hl|Z-suKk=SSfbWw=>(7ve!mf##}uzV3f}0Yj=46r1IDUA-N1sv#Zv!QggO_uiB_qy<;>fNjHmPX~>+'
    '(RWEcpx2;bI@Opta7d0|1luI!#Z5ca_xVoUC_n$s=&T8B6Yb(l5w@H8wspAzZb8-0`g&&1N87<-3=-ePIB#niQQ9TTmWb?%NpB(O'
    '<h}d>rGcB;Ul+onwkFHt-#d7F2K&Ukl9#I4B=*-F^M(kn*IR#J_teZ2-EoIrTb}ezhapuSoOrPTErfN`+#u)UaI)>6O2Sg`FgvA}'
    'lUq3c<@M+`IKS^5=?q}X^f8;v;}u`&WiPif*knLEFfWizT<r{>troRp=Gf21DjfFjo0-hcRPAoQ@trVMWvHJMZtwo%^XBzHznHba'
    '7!-b6Q{3~pF$Vo&b)e_AXvE>bQ^xizdt9oA!*0Pxy}U$QuCjM$+uJbfUCZF5B2ISbW|fE?JNo5^b!V8!-X#sr4UEKI*@Ip~eJx#v'
    '-KNm&NMS^y02kcdqP2fE`)BI2Hem!R(yFaLf@_xYn~M#d&!t>MImB~*dwt>!C~N3ms%;dod{)TA3>E90flYL(h0xeb!)=4;T?Zc)'
    'ox*6AI-T>NM|yv(JY5Nh+=(5c!he7}KdLBw`7aIrcosCE)J29>)`<U=$~wd~F2K%!)}8vre7M!ldJPRhcWTZlde207-DRlOU`J<1'
    '9a=qn2BS&hUXxShpy_*Q_q*TYEFcS%h3bxc7uy%l#O#$>H%3v!4Ziujf;|^WVfRRN7tLw<dZh|%ID1(s(d7$+t)Du|Z1YfFwx%R8'
    'e?xzH9h-Nt3-f6ApW!yYU+%&+In}cX^F8kvzkkvcF&gjvNoU-sbQD@F71Olxe#?aDTX;}6g`QDoFUaF0_fLB9;(q&$`ltgQFN|y6'
    '328H;$)rV#kE~r8z1&t+D6UT4S!Bb)x!e-ul~Z(JX`feh>l)Fdf2kXr>7{inA8HcQ-S;f@@~g+kDV(^B^dRaj{ENfDc6V!RHE1O1'
    'n|LiXhu}zx;>)?08FS97YV}5O`vU8H4ZIq&1*{EU_uH;}&&%(5gNI4(H$POXUvxK5!M{>rd`444KAktPwwD`nIwAT_SDwKJ8(_3w'
    'H061^O?mK%Z%zXBAs|>wQh81+2bDZCfyI$O{L!4B|4dct+g;IKzE*vmfgxrBRF-l0z~xutKDbM@{i}2Ha;iI??7QnWtV7ivnmXMj'
    'N=Has%a+Z<q}R^6*xz?^S&6?oFV3+8o6mQT5QwGe&BNrAtI8N1yuKZOaZa^A1WZJ9l9aCkT1toGKIx_vOl6xdr9bP{CiBEN@*QG7'
    '_G*xH{rLu;vj<onv}|WlepRR0q*Ou&=PR77gOj_O1>HR&ByqdAy40tpG1<KH=qf92WL_TgXi32M1@TLfs|RSxr`9|C=^F0_d|tE='
    't$u5MRtAH9nf30x@iY{tE9zH{5B&kXom7^q^TfRl6~*=_aio`yE#yF_YJKCV6Yc_u_^#AnlT-M&PocbQ?V3oG(cETUvl~IQe+;lm'
    '=;qEtnU7iuG+y6oTzk36Zu9p!DEE;~#X6yBQ#qIV9i)Q}MY(m6+Hv<9-Aw#fk1wrLeU)Z5IYNB+?%&B(Isw(VpD#u-**tBg921u$'
    '`w3QC^7z6yZ?#FUJ60BaS*Wf1_UXb-XZ#MGx*(?|hoAlnjSW7J!*(siw?epv#BD-fjlqDPmHqwd#_5CnV%Ymp?D}l+T(Ak#tI2W?'
    'gsB!iklN{uDUtqRwR)_pHa_|Ma7mp3G3Z#%;a0YJb*pP;J+{ZELHRjD`IM(>Wv>@+{=%OmL2@|1WoxJ1nW7zR#4<c5^*@vS;Yc<0'
    ';#8oc^c4McPg_5GP+Gcx`#E%M;O#1n3$Qrrz?*Mh3!@}Fm%sxO6J|?jEWnu`cM5NMsOz(=oju=|E3x&5wJ81z$YB7G=U<(FMxSXo'
    'Qmx`i9ai<}n0-?z+WWhl#S65@^g^7%Lvb;gwv+HtB-o{jNHi~#sUp_tC^IjMUf0rE^)S`eR5+^t=KX~`j(n_{<k2|18y&T+Ocl8E'
    '2MzA?45*R~wWDtLl{9vy^z+>}`h2i1EcARX?Dkq%v)HT3oP*0W6D@XVPo3Xh6zK}p(m&kWoK$N1Z2w%m7u}*V)xASanVDq6<?^eJ'
    'utLeBt(dRNi)QaWsk1dWWJ`oFcD~)dbZZG#SK7CyFXM-!s)@fUcM0BRQsF8Bv*s@8a|YX&XF#~q=@|$hjy;JO@uXl!+dYWm^&MeV'
    'Ob`Zsy|&%eF3hRNaog#vIgZ%rj~7lhbOT?9*E<<%uTE=r1xZmjn-#C#;twINjxl3|I-}w2V6+6U(`L&E#=(MezipP?)v#uA5%D@M'
    '=K~Av5a7Recc4m#iH->ABC3O+k=klTcrvXIKX&=OAv$)y(?z?^Hq<^aab-r?A2clPcL^?-sJ}PQ<tm_J$MWoUY)se6Zu`qSlj23`'
    'Yr>gE@lpGN;2X<3jzc^}XTf#e9hia6ZNFWaUs&)nYd5dshU+T85y(fhG5(mX>@jE6#e)31jSbe6f4Wh2t+NO%{Q>Hg<N!v!eKCUv'
    'CVSA7@{28eZ1oO8zz&XzBV9&>K@H)B6P0*uBnTXO4ue^weePDskW|H2<omz5P=JOTF%{@<Ir0E-v8;8B;&C`gC45Y}LPy%x+jMyR'
    '1S=NGMtPg`CS*KX^*4VfKP<Zx@t6kXlY+b;8Bn?X&v&(Tik^j<_N;g85z<X9Se%z^jGSMMEDQvChHozqv5z+;A$~(5vJPZ34aBR$'
    'w))*Jys?nS-n}&(WHRf&`OQxU=kZ?BRsP7ZGF`(bOxSftE(GbrHe69Tp~lDJtR!Av<)B_c8Fa<0o-O|c0<6`guk)eNT&Soi6I(2J'
    '|KZQI|C_(K5DAVt1eA;f?XpiEKr-H7PbKEYAJ>IiWK->(L=^1po=oZoN*%ht&=FRrLjAf7i}^S-VD71>*VW<?b{eqp^UE3Uj7q8%'
    'sMtTCjM7fatKRVDPBV#1(SeE0;IM2|c4)6OL^0(oGH`*cLc7}bcdgM|y$Yi^xCcb-4;@UL;_>T~nS1s#tbQHYjT%ZL^RmlhcTx$h'
    'xFT2S<})+02H7xYTyq9{j}k&1UH-7sq2E72$i99aJ7UAJ_GZ)>59Cqm{(MYX|8C7k+NFZYwBG(>gz9rB0+8R|7wdMvuTQM>uhJXn'
    '=^>PEzUB>=*+2(~CmASvQ!Ou00QE1GUZtkdZoP8+&7qvSANvXCLVeh<tFY9IllC=a^|b(g+SSvDUA*CJGWn{+X^dC-d3ci1w|)YA'
    'N%I>$8gH%w1$ztEX0LJE66^6lpO_3{W}TVLc2T+4@UcJA_>j(Rv#gBfEr3tWEqjR9h>_Nga)>U@$IcN`=pFROi@SMwg6Ga>qS`x`'
    'ya(l0aR2qu71b#XW8A#6y^2WxuVnE<04z$QW+I1ecGJ+9V-1O3enTIes!fZ-4&~`{UGgQG<oiu*2C;Zxp>})7oPc=v)2pBU*yUV2'
    '-yO&ZS*PXqxE6A|d;YG(W>b_<D1qnuB_z~W>NrKdp=cfedgg4KxG+X$#(17Sl#aE}YBjc6k4nG)+iC&y9y`=%561bk?Qk-9;!!8D'
    'mz9I-@|V?ovlcbyWKfHKKx!gJ^j_!b=-|9^ZRxFy>4UfZOMPMN4yy<oEq?K9cO|LZmbYZ1PQ>!=*4@+^*K;cGPUVf!BvwNiSuCmc'
    'CvUO3VC=->nwGSUGW#0GY%^o5sTkevb=UlSHHZ^Fzr534W?y|+2&qK+YBJ>g!|9zgykf4N)?`ABaiB|pz9~|DRa_eTXXLEn;|{59'
    'W~V+ht}H(PZ@k<;T7p1tC3*A9J9ccnJWfkZteEWc%Bl2vAZ1kAdMC3sSgWCN1bQ^+4o}H}IUI$#e7NRCQ<1u#(zw~XLLdva<d?Ir'
    '%2ZT~)t}zy81xscK2CqR(F!(PTQ;+#1@E6K!8LZ%YkU7js%!KEK93ywXpadaWrWX+$hrx)I)w0hq)^>{Yt?O9_#LGF%^&xt3q6;U'
    '4-;X)aeil#vPSIb%DoQlU;aQHOQQ-VW}(q26bl2P?y@uyZfXFhFRzTkhwqa=Sy^%kI$rg%L(9KCk@}z#Uh|Nt<duts8%_myd+ljS'
    '*!z?=`3|MDBmV{4br@ZCn_W*n)mDy9s`n?kuE;1KL+H56eR$#Ri(^-5UVpw7pU4~1T&g}sclO(ql}+7<x^aJwH%kh-J{+5KyIXGE'
    'M$-R&zWQ<UCgv%~?_1;=T^;Mg{dA~2aB5^vIc3xD{hRZdubihf-Ql18BO1?Vw5LCLUmn+XVXW^hFBI0*%d~tA_u~{-gk2cM;ih9X'
    '&lb6xd)UV==5{(7b?E*%=C_^EFHfF6{2yrc2%tpyHKzfcYTl>vhHpAU$?_BHNwzS(b9QsQmlwUml@m3#WR|-7$qeR}@0<#b*A4Gj'
    '6|Of^Y!>_BU#afJ?70!|>_szUFF>tX;1)Xmp#E)Keuw&*;wrO~A#-MrGg6?u6%N3lJFX7j9%7*Epxz)6EA4N?fNJOf^4pu_G4sW>'
    'RJkuDT#1AJ(?AE>YQhB+Y^L4qsx3TP1l*(Nct7Z~tT*2r4)#(;2c<ymV`>5xY?FP|^Pb_NN<V^r`@yZnDU0mJaShGh7p=e9PKU0H'
    ')VW%zgGybTUg~yaMXPh8rx$t~2keh_4sfg|?oQwOK8?0lG?%W`&13*6KsNpDKLhp$X`?CfV!?mu2<0xm8sBPPMTi@UU))yrSyTNQ'
    '4$xW-n}Oxm#(Nf=;$>I&-Ffw%t0LHuy&~GPs?i@+#b00A-kF>WEc#7gn|_z4qT@)>ur*zl-NpkBLSGY7bGL4;p2!552$W;`lWnP4'
    '<G5We$GcL>Vmu8^GG7caqx%4V{n(DK!kD;qZnh?fhdcTQpx65CDr(i<9QsRse|VpxPTd$*vdtLW%|v25ZI8zXM;xCn#v=bfK50~('
    '_i`Y0-!SX^s~1<YXwjwMJc$atapCxvI3W>Nwedci$9^^(&T|zYQ@XUY^BgD0uo%}KG+JGNGJ@5rFx|u4ZZmH~P}!^e`egBAU)~A6'
    '+%1jvz3q0@`D}ZQcX#+KQM=u;-7Pv-v@?QlH?E%Mdn(E1f5?kFBM<xZ#rcO-aJ;wYuFekT&K1%9?Vs$hgXq@HN%3e(WtODU2211Z'
    'd_$pG6t|s$0RG+2YU1tJ5MILZP0#MJy`VK0Dq3}3#`4DSn#}z|qrT1`PYQo|awE+!>Lt5lyunxJ9j{>Dw_(GX0@IGrSpwK=@#q%$'
    '08xzG2{yrWG-?zzFoFVMQ{f4k7~fH{-)lqGxC$^b|HJFADDJ$H$*{<-I`!(ghkL^}#_R9)<(F2Uq!m?)lO&J+!e(x2%UA5}kkGm6'
    '&0}=vZ8zb2Mn6x!SoKDwDBp5}pT3?@t0hrCZH)0<U-Q$&yC+I@7gE3wBLh|b!`2HQJcB9%iF-ZRF<hepHXaUsR(jWiiyq=UWb?s|'
    'L`F+=L)?CPiD`|!5;!{?2lwf+;Z&1M4z{1Q)$PnKl{t4Vf*@Jk=~qPKrmXkfKFGCsJKEO;c-7KZr|r04(qRye?^liOaX;P2!~v>#'
    '5m4*fZ6pheNj1nUk(XQCH0k&G`0hK&{(Ecp^8IVBU)d5!*NmF7Yhm3N(atzF8HNqJlach120UE(@xoTU>Sx*eG7uRIIX=;Dhg76P'
    'W}g+^=)7S0Bdlm_oB}IMVCs2o`7Vkba3GJ8fuyDL0YFV-_5DOD&@wvU;@|$WJ$B|aN~mz>{`{Li7xA?F5FXhA)^#X)Cc7<osay%v'
    ';nuCic@(kmc7>TA?j~Q-+xAkG+>s!*vfH;3Jel=v_Rmj%8O@ntKXJ^8xqzvqr$b*OH=QLh7@@`D(QHB9DcvdN6*yEN5GO%+<<@-q'
    'ww|(B_c^tvrlgPV{A=PWDBt<vlGYrqy|R#QHEa0fNpt)=tkU_Uay6{Zl(Sx|z83!d9lp6eC16?nem=8UtnRJ2VKbFL67<vUppm($'
    'K5nf8`Tg}x-BxAWTz((L>9o*qwRY()<`3X##s*h1_v&NlKTV;<TFbY(=O>|>$AkyF{_GotsgpE_4gxQz?&#9JeUj0;^os}jVH_Fp'
    'vKLQGo;mlcQE;|3r&aH%_^pHH*s~hifv1xJ$x+8!aBV<c6%kRV=dqpSII7y)4{#~nX8Ou&$JhGr{g%oHPwc7~qer3cADU|A-Kyzi'
    '&f7qCY;QDGfwqM}bW*>zyM96T%`Q)T@41`NrNh8(HPL6)>`85SO<{uyTjzgstlbzyR{&cnNl1o%XVtU6^$q0y_Vx6=AI}V3J02?Q'
    'RVQ@3Y-4V*Q06x|sVLvKN90ZsUd`*HyQtc$13$dW(_jAWez|H$KeD=1?S@GQpsBayD?{WNrNSPvkEq=m4vA-q0$XtMd;#s~-V_|R'
    'u6?X*G|mT|%m;S^RN31HifsEoy&Aair+I>{);*=<5Jh}=XDz=Q&LO-@oRa>f*e?&*2S)qADHkm8y*9T!7al_E>lp*_b;MKMQuz<g'
    'rfdJuGhRR4vpp=(Z$dTZyV78!-<s>P*e;EulOTkSL<?J!TVIaz)@24xw79z1^M3^bd>uy9aZwut6Juyrqq04pt<c#`m|#CVIn79q'
    'nSkjh&^Kc4z1+EN6cmLWaJ_v(hsr^La+!d`N^8ir5U`}AFkueKv_O4bo%%FiRS_R!1CJS2{G$G=L){NFSfJl7y)(DmMQts2rxUHb'
    'z`vq3iS`QNjHczAGL}I`8PA>}is0PPi_z^O+Ks&Khtiz`Wd&9Lrf@o7Z<t@4&F|iY#A<O>a4A|C+MT=2H3Zk5t*??(nH*=KTs<Vq'
    '=SXi4*b50FV&NEAJhpvv^?4Odw0r(k!<3e$DKt6!;*8&~;_avin`fEYcE(xKw}4~!QiotKdS!5$XKiDddsdKi3Uy^qo*c1yPftj6'
    'f{{aUA9GMhEESZKD9PKO&f|YN*QW;Rnra>(q<Lj}#d9|Er+s$QJeN%lo+R=IT7H&+^1=7!aT?9MO5<{T9QG}w?XP#z)ZY@w7t+E~'
    '4Q_|E$xnZv>f_DaA05?wOuiPV5Innuh0E!tck(fG26s)j^%@J+h}5c<PTin^_iZd~>U+R<k6T<u2<=h|%Xth9u+`!>2WSZOlHYNi'
    '?RvHBMbAaOca>_j9J~?@w-30TGICInTnl2pdO7Cvk1o2VYK;wMGI}LD+(aJninJ~GO=9uq3I6l<U9IVTG^8+o+<1A9OB-chl4y1{'
    '9-7cI8_nC&WgsciW>tj^>NuV7dAqr3*KTnMxj|eaPsLi3o2{5S`zY}7PlqWqvebCR6ywv-;H{g8m<|4lt%|cdq@3x_%JN0WaJCOh'
    '(fP{y)9_)hxFTlYQG*FMzmiI$I*2NLZ>m3LtG)KmXY<ilcT*T(!)gO+oX}aTjR0=|$}_;JpGCQIJO_ye2{%a)><C$5iP@Sb)nbO1'
    'oP%HOAnK%??V1HcRkF_Kw>Jr%(I6-SBVRPhvt>WdpY7+}+O?tS=^ECKOlyksU!{*<wPXt-dy~_z4-4QTcxajs8(4R^08MzQPRo_-'
    '4Z1%baLuDeld6U?MA#PcLU?zmgUc#cGc}|`VObhj-O(RM%Ws=WMBRM{Qyzw~pB%ot)~d7pxB`Z^w|OTsBG&x<&p&zZi{|0^{xr_|'
    '&U-!e%&^5q95j+wQl(~bE9p(vb1rdp@HloZQEiu*c=P!z?z4t9d2DuG*L)MX`Tj!!@v0R3n?J54H=}yq5Kkn7P7t>{ytR5&HL5vS'
    '8TP4u*@(TtH0#kPg<C?v10Q6@>ceG~s#6d<prJPU9DX$(EXf|>PVcv;m)l;eH(@;~Z<EzZ>pch7wK)WL<!=4Dqukp4d+aJoOP`NJ'
    '6yvG!NPm{p_x;^s)4Nb1uHZbXI`kl4*1(EHnD|dG38&32QzGj8{M<yaWuUbe^CA3nm&tQ$6lK}$@IxZ9F?^=$acklo8w|2sbXw(k'
    '_3e#%?c*t=Zj6oTL`^EL$}fJ^>WObHybXWM%$9i9SY%(TgF`hH^Vf(&<L=|N`N(IJ3Ps?LcXge=;wPL2)SSZiNl`1$$Na=CT}z}r'
    'PI58*>0CL!{I-kFwK{K^Z)bL&O%KiEcK@`c)-ZiEFIxsiB_Qjb$jUUBbvl(qt4}YR?rbU$$y(j7cfPR2Ym@PE!kOjW4@YSe^wG8G'
    'UgbMqJ-&EIY3%&0^8EqvwclZkytARRNm2ceQ?EM@{INHECMdJj#ujcIw3iw|2Vt?wPu-KO8r<3Xw_gJ?smgZVt#vw8>LlNa9a$On'
    '+_b@Mm7@Xo!Kfeq<ql6NudTZ~2LRh4d)}$kUUymcg`9_PnRfP@31d;GeE*x5F1a2m?|V@%ub=L8`*zse+68+*ee#LCw#u8PUbJSt'
    'k+W|aty>(JI5eu??6k)9=YJuDEH0JPNk5U~^Fh*o4Emoxswv^S(rQ$^Zl%U>;mwYP?X0f>*U_ZUz!VTfU$MwxAlzj>%1-n;X5Jn{'
    'pVr5=1q0svUe+cMn7m5slwJVlukW<IGu)@$qSvdjl*5uP0Z1y^8$~QnYOnq^8#gXB!|3AM#VZablMy(O4*3GNrLF8cY5nsRD$TXe'
    'L`Xg=O$zPDvz~!nA5V{;bIe=^<a?;K$ZKP_e`5YJQ(b0$2JO48;5$TUWO%RGDaVAj^~aInTGCW6y@wM->Qbye#d^C}jrjT3{pH=D'
    'v?EE1e#~U&ZhneeYO=3fb>s@i=lCK7rLoes<B_1G8F%(y%J*KN>ZPCt4BDW9?H|b%=1ps90$b~9{qsTNFMEAi4nLX%TBbxkn0l>w'
    'ypEpCmS*8w!dCkM?4sB5hzE{~@VdF}llsbjwf)mRw3K00K-2y-NXje82(w?^jOl}`TO8O|@3;20&`+YsJX32qDtc6HP?~@p*}TA('
    '+vd9rSGBKuu{G)6DDwQqj;LP=k)(3ZojUa`oXVy0{JneDJ7xnazQ;Alrit4ih3Ua<sEx*lg)@r}gLGf{tVnsJHTPwq9$xP44Y`mm'
    'va)Iag=eRHJCAzAb7$|R#ImYU{LAaqeM`RRXdQP3iFSC_$Y#4!Z%jK_ikvr_n|Wft#+J8u`2Db#$wBm>kr%wvaPww&<-D?b(F&>d'
    'LR1_1m_QXjeP=WS)LFE_spel6D4tAhU{TuK74tp4UuoTh><<r5wwAP9>s<0Wgx@Z_Ro&xHTT0f|u{nNxk<hI^sR%^ar~T{eA^M`?'
    'wiZG?m75NOmQFb4Lu@0#$PGf(0>4c-Yq9dovhca#Ue5(wIo~hL)|BE6<eS)6(O|$Zq2g9X{K2{VukX|tIXn0P+=+a0eBtehsGiU4'
    'wf<a9`GdD|<>!4>TmOMZxHb>M@G5F$Td~_kqZ_iC6XoTEw|4lNL;RW00sp=KwxFN8@gzMyLvf&<aYNjkj8jr?DJ{0skr$se@+2ef'
    'N~qgLHW6nd4L>%z!#3~d4e2&}@Md|n8ORu86IB1N>izn$H*>&J#|RkPonQ{tmCvSn271OUU3nt9R|03^oF8RS{tKeFYU@tp$p>%('
    '?j#S288j`}`g`2G%B>=#Sm5z*zXpDc+1S(MY*DE`Lrm`&2e=vDO{lg!0r$4G-M$?H?LRu#mHPqxd3qDxUF4+1pjWH}aqwn8n`h-B'
    'bjd2UO7UOb$xAHCYU-|;Hs@l7jDx=)`v}4I%ayi#r6h(x_jW$-oA>#*VKo^*wBL1VVsr=5R)QvmbV4gDE!lU90j^ZEe|l>7(?zq_'
    'B{en2KLpeA>62>CYxt6Cf@D9Yab-4#V2V?n?H^5CNDA;Rfj)eCTE4$>_Dl&3>KEctrT8ffCp+OcCwx$R9O=9F$7Vp>-jA}k-b~k<'
    'XS3Yv0oCK2$chiA$|C(AQ`g$Op8IuQOG8bEF@vNU<&Z>lqL3b-l9WhDO7+_B&+q@B@BIdhVPAW#wfDOACj1so1fOl=0Cu17?WNeG'
    '*)?v@ZmQw_$y>Q~bL9x}f4GT^%NSnuwlz3KxnsnRdZoxjJ))CS%k`4<x$fn%J`mT0KOBliGzM`lc&sqCf+QQgoXFqD8+#M2Aluug'
    'W$gd+G4=G_3*T)z0Z}<5r&O|&K%0w3rE>_iX<X6Y#jc<x>3CizX$l9rC`HbboI|<VdwKBsQ~w<_p2nis49zVk{+>(l(?aG-v3Q4W'
    'oonx~im;XITup!d(1V6yBVlkpYZbkr+ts#n7@vC1dT->*4Z0$VzAB=98BzGA7+HQk>(zhHW!b6eFKNt0k9sG=7K2k|?lE3TQ9<R8'
    'O|3eI&dJ#HTh}enwhqcC5R^yxfSul(opK*k^3PoEFqOzSgY8~!FMo4Unv3&jd`BuwZ;0^+@YNA<1(StQwtArTT^P64COc61N4eI='
    'Tf6KLN{vdB64zU1US1p^k!fL*2+Z2;^E_dp((k{ilg)F@I?Vnf%*NWhdPt*E4M0~Pt7e}obHp9H8e?=nZDExVNSyd@u@<vqgiKa}'
    'HGk(pts8nSI)W|lJiHqJ?&W7x1~RZy3l6=l07Umex>oI`P};hyO6%xe#q)i`1?lCF;e4D?srosqr4@AdQv10gt&o{3vx7e`-#R%q'
    'Pl2D#q8lXoo=ZZZCAa>`IL|As!LA}k*VABPev9BXKI?n`(Zye0Ty1Q6Fcy$Q0WIpN!o?ec;z;Rod4gSY7`dAr`_ozea5q(Tyf>KE'
    '<FY<L{PPN{*+vU9h;n6$KHbi{EAa3i>~n5y^bY*vStwQy&+CoW+IbT$mS|G&wYc^d+f_#W<@JHLnvrd=0wB~vscB*-RqK^)g<pI2'
    ')|JxZVDs!3N5b0z2c({7=W%<Z7#!+V*#0v;P%=A*awJ)_AKTZhNxptKe;66Hajk6EF>(F6&#%+v?kz+`)T=p6T{>6RmCKse<mufT'
    '>R+g^cWC)9Jo@UL`s1#NF?z@?ykclB&)-9qB!2Ngy5sVksaKBBCMht{z!_ZjsjuVLRx8+w)~vs+%Ui>{U?P5RWqq!6Dcg-HwV4>-'
    '?bc|i>|AP6mBoqQ^F(C-=ATVY$WH9ek9vQ|!h4&vpKV;t^I~)M2j?;K9^v(sj+GE8g1~N4n|a{Pp$6u&dp=v&&GtaFu>sAy;jMR='
    'qPzERzNb{Vp4;%-1b7RZ*6bP~eCM&$?-I3#@qIyAU`>E6gO&R2^_X$i!%4iM_p2(7IB_ZWeRj^D@P0KI4!cO>X^nn3-+yIfBo5wx'
    'WbwSlYsX`R-&vfWH}TfM86u|jtqJ)-l_aUl;}E1j?`;1r_ln^LR*)9`ZqS(gl{4zoS&Wzq@$;9|0$N;9@i$}-v;bV{b8^^Na;pBu'
    'SU`-j$WfD(AjLHdM;H`1%Y*Rm3_0b@dJ@fjeKs8R4}{+nbhOg$FX`;}+=SK>gupGcaaTcTeyQZ+=O305ZJFTjvvDu=wpS%a)p664'
    'I@0jHTh8;*ttgi4vs|2qz5b$MO7)U+iG{`89{+Ug^0vBwrg|*J8iHC$x}R72oV`r^&8NQG<d=D@s>7Q{a&~VrS^JBXRY_hO(>R3m'
    'QRc5v)I5)TscpX=!jZSwUp?y8&YkxoaCTSQ^~Zm>^`<f;t@0;j9aMttV5{Y?w>TS4xYqty;}^$mmFaTT!BunAqHLY)m0&&*(1L~='
    '?zXu7{Od~lL3Z;>^N(0pH+2q~RR}Fy&sVOv9JcP=!;-2^irW1am-Nd{v%$2coSzSYUV@x`mjz@;#P<H%t`Exk10wyOZ<}0#@H-mx'
    '7IWqMIAHgDv~BGcTF-Y_ZrxDox;Z$_mUCGkiLzpx_P8Kcd+MXH(bUIkU|cvsH&oA=v;ebVj#s~PoWAa-6E(6X=Wd{7kkfv!pEgOJ'
    '51cMGzc78NyBXV<y~FW|=!AVeR~?K-E)t(z?b!q_bMU;V)(QHtkm1Fp`8#jHJ~!kMrrkc7-Z4<S`VrmyQLzQNEC~{}I>DdXwA!nU'
    'Knphh5Y+FqMtN(Ggzz+UxIO-Cxcf3)X?1Lo8Bx#QTq@?~{rxU@#X3-n&9)5UEtc%GOMab!vaU%|fcQjXhj}u-*hDOSE7#R>t%Pv='
    'Y=w4aM%}-jwA^m&@R}y2=l<_~RUB;W_Q<RcB1cl^rsZhF9Hr|UM_b9ZyPd%jJHmSt;=B@i&&!8(B`sL`_x<w?UJOb-^>)}0=Ar)K'
    'CZ(mt{^x7M&3&sZ_vrcP7B(*6aeWSZX|J8m;ub+<hW95YtN5sWLRu?~h+JHUm`UEEvFNdc8!K#S`H<5J&({t&A!rr*^`&uX6?ae^'
    'JB)c^;$g__S!gdpFkS}@$?-8TRo(gEa`M`hW>sauFha)h{QY`B*mNQB{jhqU)0tvk&-&(eg`}U)F<0#%Fs#Mo!vLLJ*7_JWU>xOL'
    'GJ{F*8OmhW^cM4~K1u7bqlC5R89tW*Z1X@wQ7(pkU#P-jUrd^0&D4|0FMiD`-i|tlKT2Nfey>Qsre@DSCfM(FvmL9&sC9*Q*P&mu'
    'ECOb4x(?$wt3?ArFLAOtZyL<-RK58qg&sTdA({UAdiX8FA7c^VgvzJhZav0NRvDS(xiPB`>4np?UX=|*Gq-W+wVs?$DGfgnGH$5P'
    's~IF@_q9#w(|dM(+ii}rNBOUx)l_dzxDnf<xD1l3>kw4?^PZZIfz|bJV5hIdvkXjkik1L<<W~QUoz?K563!qQ@4U4nOg52XD~B<u'
    '@3ZQK{MEVU(<>!=-pB3^Zx+llbeQ557?{_X?|#PYLUw*)gc8~9Z+ipA#gY1nS><fZ)(+ZCUu=WI|1RJS*i#rU@6POBA4h(m&FgFF'
    'GM&h*PW0hdC#xs^^<vQ3!w(y)`Cu8phfXdqVf!pnJY_tp{H<%LD?Pqa;{Hyuv;MApzR#nBJHGyWK|%#J=I7x=lvmsQ(XQLHgz)!v'
    '#&&!dEky;^ory!#J8;Yp+Egu!mhm1MpLb>`$YNy~*80J?6xZhZrA(Lm+v~r*1Th?#tW-`~b=GEaNG6%(F^5OKpbUCz*VsIKe)EO@'
    'xcKWjy^S&Y4Ext&pRTHdEWWk*MzSh<x8}LgTAs%9Uwx;7a$3jkybK*~fNfBR3jqn`Jgk<8#^CY-nd{h?3d_R)IQgo0BD#JxKn@z8'
    '&5C6*@mF#}DfPPl5gUfU-DbaiRO+!K)Vi(r!~~hqN8h5$M`x3`I|S(dvBdWH_=M?T=2X|HO!WLx$v4qy=ftDQq~)#Q4Dcy&uBN)v'
    '=)Jmar}gW%$nvMYn10SrUK?}HW3^86kAhSUM|3dCXDgdB;g65qopzaTvtU1a&y%J^me}nY@!Mu!gLSZ&pS#SY9IWzI|Ce`YH^UWk'
    'rWWLSQ`)F?`#??X^~rc#``@&UF?eT|6C5Pj^OJq4^(WntEv!a;i=bNHqKx}PpwzVQuff>rRi?=5_kCymXT1kXf;?AhwGm;pFYvdt'
    'ufdoq3guqg=EAvfY~_PxDWltTHzM@ugbU+TJINevpt9b;cB`TK5zukx+5P_JoF1;osL>!+fQ*k7cCiliZ^I@nwrk%{gY0!lBoU}6'
    'HsC!~wXDAilv4Q7hHLm&^ZruUJ3Ol@w<_8eL}U0dnIC_MS9c{JB8E>}D$$R^BCql-VpvTv>cRi<<&)hr_SFrjEhJ-9#C%dhJxsjn'
    'X?dEx`RTMh1I4fA1UI^f?a2D|A-CbcA^zU6**RN-=UojQAZQZL-Ckb|lfO_G0vML7!xwQb*Wv^n!qTF9V(#S*o_5D;_N`DiM0=v-'
    '3Esb@o%zEdv(1n4sC{O{0Du-R@<I=rX|0Fcr`m2O*GRf#C8g254V>$LFw<S%t2$p!ChpWOE(|}MVDo?#NLUbhK&h^{=YM;Z|KL|z'
    '?CEC4%ynH|Ejf@VvC)DW)Vl6z_hx8<?nr%&#naQhf^Qo;*D5Zp>t*Pp*MV^KL&FEw{s0iB3;XiBe_XMjF-v?`<EC7|_+BKaallRp'
    'w0Sv_4k{__>$d{Sl2y6M`}^)(RJ%SF3NI+l<$!E8wezbUO{Kw%7T)iv`Oh~fDw^yOeK^arM<kR=wzn<q;<4z=%XH~hx{dx2$(?p^'
    '!8XQG*uBo?d0H$pXd3j{^zvjGt}^{n_~zn8Sfd#H?qAUN&mcUW?9r`bRkOgfOw+lHwy);7?UrnGj|of--W_(2{lZK;1Oo22?ql4~'
    'U#3v@KjlzAc4y$QMs+UjT##nJ?>oUdyLXdW{i)jkdHE7H`bbUu)2a4`a(t@3-Rk<v?3>E;kIW)K48|flORL3BRZ5-17Kh$J?l(T2'
    'k9@$pGp+vPJKaWa_&(G3hoU}~9o~g)+QJurMfEVD7&bDye_r0N^gS?>R(Zz(pVz4NVH#unIG0Y~`Kgz}tqxZEpSc9Tll@O0!_V><'
    'uj7i(vrhFGg*h|W&`_l8q%!(|oT9V#Uz>~KAvCHL*NMt3+W0strLY7<!6*Js)SADmc#loZqwG`nr{5r?N_H&!+gQE?88qJ`dUV5='
    'ZIUzePUrYMZZhov8a-t(m{^<X>x{%G_Fk-mI~<h6H{6;Y8u13dqPBuw`03=ACre45>~8nfvrt9u#9f5cUbcXq@luRtxbTZzLB4`~'
    '$`KJ2mk)k_jt$Q9xT&A&*x}yFNnsVAgw0Y*-$QX<Qpf-L(iOY`kLt;MZK0JLJ!3Y1@q6Q;L&Tpa>?Mws{#Z?#e7{>T`Zgm#y)Z~-'
    '_BNSQH(O{1Li2w-g8xQ4G+5t$b2zgu+gU4I&z$Kdv3|&6XU{xu1GoM3E7bB}?*i7tq;W5cXMJIP4;FKToejK=io#VhJ6+4zaiZ-7'
    '<#}KA=4;~Dm&U)3SQi!|Szt|I&QI*{X7!(WvemTrmS4PNX$vG3M-^{x{h&TI`O{7Y+wmqMLJDmZ<MJEMKBAZe+4c#J_rH2yIk|6f'
    '=c4DG1pRc?S0r0)^>mwU(?CM1dX;U3V{HD#FWt?W@ZT5HA6;9yb7||ARAF2rNWZGb(qQR{Y#{3!|K>Clvl(lbRCmUZAI6nt<eW?z'
    '#-(kK!GWEX?@Dts*;#H6h8-!~?Ru?f+G@r7vC8UySlcm}eqXNc$VxX$WWV;0?;JN1{RuT~3m&M7r||ciF$hTRJ6CLM)J4}*vUGE&'
    'vQc;b(mx6`#H}*L%Kji$ib}iv(E9U9G$F*TKixe@;dj4~#dkjD$Xc4~{sEqogZDzGy2IuDawtavb7a;#U+p!R75-hH|No?}d1EHC'
    '{x;^{=sXhNNSCTn?SJ<RPnCE0z3-5ZQ%`yi;yqDjC5PFqx8moeK#kL^@i~`!jY`+TwSn2fnzvlPdWY>BkvJ&zCvdd$uZA%OT~ca7'
    '|K`vye4V?o^$RyWJ(Qi7U>ibPtJ88SMdeTRk4X2X@*hJ(T%i-Jj`m~TwL9@t+9=*Lk=BHFYuUCGK0+v;hMa``d}7<~=J7}GUyG|a'
    'E@r)clUwba^*1X|P_CK^>bd1Lo$J@?!zwjYTkflo48z`Lj0qcBV<+2LZ#+ZE;3&GGz9<2|cwpum#|v~JgGYMv*@}SlicNwY^Z}3w'
    'oMYYFV@p@Nd`c0+KFT)0^{F@r!bLFct*XDb=JYwR(D!*Hij&F+wSPLc63ppyXE+LL5mPjy{>g)Mz$BdNJ-p1@Oyaa)ynxBm)O%L#'
    'e2KNdWib=@lKLf@^Dv8mE#w{w6BiD<Mn-J#fAy05q!@L}8+6KzYoQd6{|e#zFVEV~mkQ?BUA6-HPoNj|9=3@gsVWVt+(U1X>jB8~'
    'mFfL?#XD{PanH?f-2Uxvxp38Gw<#o3Ga4Pn^_=6+qR>blbFQd8_!?-f(_=@feV&bd^SwrIo`g41&<svC{OX^k_2V7e9F-bV4D|2-'
    'ML&G&Z%(4v-8eOHt{*uNREH?hXz+BIT0KY2>k%%FLkLz^RBXk^`DdT*`*o@Y6Mtvt*?(5+Lx%H5w>3Jf0R9fY{(QRjZhh&y6?!x8'
    '?dH81S-{nkG^<+^e`@i$G7ht{S$+^BN)Zj9ts3P|{3f38xC%)dMjIN^y_Gf=&(=+n1}?Vx)r}nWJeljHocTsv)%=La<yz-hqP6ys'
    '?REI+(;I;LT>i$23p&~3*sf#oG(n}0)5&xCoYlr9uAd}rJRhDe-+#Vs3Vff-&K+MGtCiC@?+9qUBCOjBV0xdrMv<RAR^8430i5||'
    'x_=ZH0|7{tbw0R0FWm++PV9H4fBY9t&C*Ob|8TPn!?*QqCB8qEH~)MPHDV5%FlTq1>{c||gfERP-EC}oK^20Rjq`T>^ss0p?Cfvh'
    'kEl_aG@X=HAJL>&ns!e=e~GesAoL%j*B-~ukvS9_gPLsZPuag^t+*N19vz)QK&uri>1L-=)9h)si;Q*^!i_ePUx{b!!8nl?@OB5#'
    '8ui1?*~}e6YABDBYhS6H6d4}C;TIP5R?@PCS6D@zj@UA)hl4;>Q}#G1s<o-dZ9kh!42<S+xS6<5kF!v}cu~y1zEi5a7v(KMB2p(F'
    'TAcbEP!ZTbm;1@<5#+C7Vtj9p=_k)84_#R_(!EUe)RT65uP=HtdYqi|r7e6OlRkBIVQ}&Db9MiKAiKW2^_XJDsa$!VzJ^-bDM@K('
    'ZCcC?*!mZ|a%xDeA-aCRml%UMav_(#n&#6Wf2seSU2*d0t3rt;--{o<#b$Tftc?t5U7!_LY@7vPV%AHM#e;l$ax67Jf+lwI-7EXN'
    'lt>!uhs{$a&w#tsF&gmVC4OC_WxLtA&F+x<&+i%G<fDRP1UBNHZ2^|srV8%zAwYrC<LsOzCfi$IrZ*9Mn&f1m&Yp|w1JLG{k#%k$'
    '>bci8SIHW=+kMVV>OlVXWNHiJBfwv96hboxXisl~F&njj6D3>h$(d?@;t4uQ2hB2W>)zo&mnf=Pq(*PE?{1AM$CKnLt**3Z+8qqA'
    'M*izdFP!J$%I*64m3}uqM={q6axBh+PJ70s>_*_P?G31}9<A4adz0oON)D^#ObxrB`)Iw}=wfPj4b7EyuSJPSOV!_8HR?XEMYyZF'
    '7?gcK&bHs{Z?lnrF!-Sxc(k6F+sFICop4n(M>}{{YqI!ck_(6LsZ)3(8Tu&ixvPNN54PzeKfSp>#&ZVk>Yyvj*r_D;zu<%nTb1CC'
    'z(Row?z%%Q!N((>SbU*w)JmiBGUp&<CDkGXQ2QoJ(}*5H2k6UC;Nmxj)Bcv_8}P!-#u1TM{^NZapoPL7jyjr8S{3!SGEv!WQq5LQ'
    'NjD4p0Eg2kX^)&S(#@m>ZD*smE;LChbVE3r{PMbXxC^y%71yARbo-Q)*s)}x&K2Ti4zx;5v*-3e?D>KBWrvl*#zZeB9Wy=P!=_ht'
    '!dAS*5=@hrKTQ<@j`9BaHJTYb{9@(o<m@oEP^8-5xd6sfbPzOAiB{&f<-XfJ0ETM@@bMC1pX4-d>PBhRe45#=8jP9i@mQKCSFKR*'
    '@ARiHQm43v@(q{S;yH%n!{!q-p7yZk&+<*gt_KmZ)VsU1d03Y}`Pf&6k9W5PwI9Z$hSk2~L$vs><20!ni_7pNcYgK0wu9tAc>$*H'
    '-Uy`I+hB0p0qYk!)b13W?jMZ-8!vZcYt(OJfa;(yq-i6hT=~r7Nw;Jb1ul)C)j9vvCXv?We*Bkxk24mo7gGoxvrAd4Am}~5oT|l$'
    'Ysg9rs00`8#@qkyim+8Vb@*9a45aP|8Y@b#|6NKzp}m&8FSWS3WPX0%;ZKD7t@U9@kiD3$54%e`hW5`CRs*y4N^MLyerqdJtvSl3'
    'He5ZG@n7be{YCpA+P5}q!Ml*ns%G{3U_Vg}eDupZ)djGcb4vYgu0Kl}z6ow;=!5)hYcT42G)nTEZH|tIOJcmDwbvXiUYEUljr)FL'
    'tf{8c%Qon`^@cC_^p7|lN5B3>exeU;!Ht}|_XnL?<^%N-j#BM95S<P9>U*dCtT3E~_WUZ97*&q3xk)aowu`u2wqT|0^e}sw&J;QO'
    '!~J*i^D8eJ3Oid$%vhl`w_T}r_}DvZ7w=GhAW(ez6n_kCWM0$kq1)D`J{m=CS!1`IUUR>zDb!HPwVGh&&#}veDD=;VC$P_qH>wWL'
    'fQQ33P7(O<7cEP@A&jUAKYG-$E2`$xN|@HxN80?*Z`qDeuNnM7>FVPEIZ=+`)aPCnTRRV5zyG$eU-OnSNG5^eN9}|h%qonqN6_is'
    '*{+9=heExE9l8$?jp?)Q0@3Tpz3(QnZ6nHRx|;bGSiJ_f*^(@S;Y1t%>dMEUd9k(=z<P4)?`n?oyJHZ&y@X`=%9vGGp*G+s?)wM&'
    'x3hn3kJs%vZ$azP<l`Tj8(%NEUUjGR*xqWmQo803=j-o)J_QveeAXf_S`0N#Ja>AoKe9)+n{ldxU1X|FZ=|$R@zVYJzEj@BWYBHw'
    '_mB;C#1)-)f&j0zZK3xq?|(X$yfvnY5DhK=PdT-TO7@CeBtF(zs9G6M+PG#j(^iqFn=7(zH}be&huf?6)(HyG5}jJG2k^}?#Benj'
    '?6=YVx8IZl&z(*;NgE7%Mc1wsOaQsfw8QYQKmLgm1Stysa`&z+VVfj<{?atTd*@HqF_$^YXG8j$4a@fZs+zCoed!E-Jc_)W7vAWz'
    '%ukO@V1tH36}SpSvSXj6YY)Rd7d=VNq>~+Q$9?hltzDsBrWe?4kuT4_!_~HFwL-veP3WMLHU9I(o8vN+cjMZjXOL>|YJkpjs9b1f'
    'd5{GCur2NV$pQgQsH7ps^eEZ5d3p0jCcN^`ndzZ_8GqO1a56@HGH1$@-#J!-n1E0tmPhKAA79VTsh*iCC$Ao&a5AM2+wvmQFI{Tv'
    '+J$aUw6?npu<f23fA5{HTB$eC%)?1^b{*xX%o>{i?uCMyW2^1X=&olpwXfVOl6PlW`{uQROcCK3o0rq)>1F!14xrS<7dv-KmoWMY'
    'Q?7Yzpf3b{Yrw5`3g*S`_uSVL$c1cG`BSDOfy_yhqTOq0>)KloB)rG^<vyXsHY?{Dvj1K)WB=5e;L(VYlYFqZA<Rs>-wC8F@i6UN'
    'yuq)oF%26Pk-raGz4;U$v}QLx@$M5k>`VBY%JzNh^I2auZpmL<+2-RLN(<&YA5F1t?zSKwJ<?^dlK-I<*&g;vto8FbCRb-_Q|RZG'
    '_v|c!`TY(JqtmDdmGl&MmowwyCgBmNwWL$|nVjqMeW;pn=h}wfD+nL;QpjWE{D24(Bya1TACIz+$z|)jv*AMvC!Qsb>e1!S(d{Di'
    ')$B4%y>iu<txVH(+4g7Gf<1NcDLD85IJ~@L;?DX^&n@jP*h9WrH4nf3{D`6#c-Xi5tr(Y<0#*6@d$mPub-R6La*T#1RmT^G_P&MJ'
    '7{Xd-iAb9C$61d<s}GG)i0Yr;(;@{AZRb_H1i$z_PNE}94oQ4yDjlm#0VAA`zXc{SnBC5(*(qtxDV*gut|&V}O&p}&vHsnkmROxN'
    'S><vZwr0n>3%;&=WyTo4bKDtqpX_4DU02(etG9G|!h4&JwU(~^Ehz;MVAeox#&m&2s8Xlr8(+88=5E^*+Qc3x^|HQiwdacfOVGO}'
    'F!axdr_-^nhhx|ryat=@aqMO@6?%==#89x?{6Pf4%zUXYGs!_Yc-7C%BTn6kmAENlI%9=G$y(<wM6pDJw-<B%-yEV~T#oN$Rqqu`'
    '@GG7U_NcnN8GEn!%xH|QUf{+~72NLy?XGM_zE&MlQ@N`<wtDNn8ieInyK0Q;uZFQ+SW2h#Z{MQw!~!w<Z~lTluCyn!Sqgj!!bikP'
    'gKF;~ja<UDV}&v*_E)T6*Nj>M)n<zZ@0%0Es<+Y{5t2e5mcG$<uKj#%WLOc$uJW$6-h55#fHOfyiZuj$4@_TKh`e%M@TY!wFx(QM'
    '8*OFD0>HA(vCyuT?i^(&m8$fg<gehjVl8OQzkO;iaP{Qg6S-&-r2*U*@xh2bsyuCV!OEn2u*8me0z0)W7RB`i!8I!#9IuKsb|6#_'
    'WdRwlfPR;R!uus1XuIe)_kif}W1?w@;qFq#v_t#742(60LBR`U_9#ld1;EPVfixyKs<SKsTIlF5Dr(kn>eB`1NFomR-|Q)4yO&DA'
    '{Ctj=DH+)1PjOgwEvczyhsEGt%|G6Z{AM(eocZ-YCaczQJ@DB1ijUdG`qDAXZ2Jj9w%lCxLbHc{z~d6R82m>3#e)(h<wCz+8zVJ5'
    'l=c*`m#ZE&l4p-dorNTbKapr<AgR%*cM_IgcVcnlJPgq8$-yZ!UasU>xBHdrdC2ikD*d~6>tPvg=@QNj!psYq%gT3z{lpw?%R~))'
    '{5RGCt6t~jv}QL+S0m<cXjO_DeZ=BDb;Hlh{bGz5kC)1ze+*vzor_bjZ^U+@H`%EjKpr=R^1}9_Z@0)l=w$>?Wg!c|7BpW8uOM%Z'
    ';*ZeV68$@7DBB~+K(d}!%g*U@DpA(cpa1gYeAxllD@=bK4y~`tfveV4K3n(GzH!-d6>gkWHfH&>Xg8(S=CyBrX24?emzj|eB+9jH'
    'ix-KxziQ)|PNt6$sQz@}jIZz7#)qWY#tjn=)M;|{U4!UFkN&2SoR5diDyQ%(@1ZI@f4aDF!;5*$a+j$%;;<0AL|yBEwA9e{+0~c%'
    ')e-*y?^xkzoYfc0m&~;<fp~tb`@lpwy|2l%v=i?Hc9;?Dsf_WjxQdr{6!>CV9fnu4`GD_}r86{<tuF}dWaas*(`L2547mfbN=l{1'
    'jy&A>K&V~EQH;(Ur18A3ad^LUlg(<T)S)Tf9NN_6V%yjAt~<b<$+61LAM}QrrxiHo{PM5QI~}jiFXQ3|4+SHN9&a!M{Q=9&qr%2*'
    'Xc9fqQ?PWul5igjC++LWm4l!L-`=Brd`tqr6x=J35im&ZKdOoU58ni)#m>~C!_QXnc9}z*;S#NGwdo^OuKTLXo7acS+6}l|`%tZ}'
    'hs^VQt%Kv`VtX2aonGE(*mu0%JQML`xt;jGe0H2Qh01hx$GkmUx(%OLoeNm-*&#+&(HnqHx1-Nr$FNN#i1u!+;9hmrFoRcXp%9XU'
    'SekNsy-$VdbLE+Rt3H3{7>R1Wp7@RVczP+_qDB#&Hf|<Sy+glZY}V4IxHNCidU_mJjlx}3L(Iq-_AdZ@YA>InkEW?+Yu{wKr&a2I'
    'I=_0K2|n~(`);?j>;B+9-yM%wj0TD@Xj<aA+<GqV=i#XIdNS=d6cmwoyW!uq{PgQUy?6>I>zMKSTXtI^-Iy;@{P)}{FF-&nBUr&b'
    '2V$a6>f<N4udOIQ8|D)|aSmK{dpm#*bJ?$GOnz2ix{AdZpgoyCk&7lw$!yaF)~XGj0@MHbxwyYSr9RV&`ldnde5V8;)oSg~0|z-;'
    'Ud3Hg+Er&jW{hWRI`!?znC~TC`gD!}Syjf{DaxY#$Gm!OI>B-Q{>$si>C>KA&Gj*F*53EKL)8`#9hKy$wsUGNc6)I^t0m5m|4o<X'
    '+7F_(sM#C8YZ3bLS}P6{3hNA*-dHRe7V_eL^%5E$-?oE*6K+C|cacUOS}jHOB62xo9tttoH$MNHDP8jNzRVB0MnkYaqe=&Or{9;X'
    'u3ISsy{G$yJeu6rLi0D@v*>VYT|V*Pd|8JUFT<<H_fb4<pq=3gDuGG4`A}ELxLKTf(Gpv%!nRq4$78&#mQI#Dmi=Cr*pIK_$nKr#'
    '%i~wKpT+VGyFQv%vYNE;^eH0{%%#YO)zdfG=Z@{*+-b3+?vcfdC|WGz;mlj5d$O_-;B10`Bj~+z30uaWHOGqS-#tJTC9?_rj>Z&p'
    '7#<1UE{5pZq_MK3sZRC?qcCrf;~PklXlMSa+NWMx7v=-FCBy6ktAJOx{PvMQ_-DSV!xq1Jneg?~^+aV!%pC!*^>4>g*<X}Yvbq)t'
    '=J7)GU1F3S36aj!N5pG~jC%FUBXd{dqsyyXWD9xAC{fkjk#E>ypkKY(p*?As4W^>Ec+Se-X?=t=k&yx4bfjA{-m}hDtt!iX{pB{k'
    'iS!9<en#0{MROYAWAR66F;cmL)+3l1$I3@@em*9tu=*Or5%T7Kq92XnlG!*G>gVwO&Thvdas7<zg<+N;3oE6S<F}vp<`=1vdY}3q'
    'i=I+yc@%i-jyzg-_wG&leFyWS(5LS8UAX{!*e=(0Utj}vvVM0Ne}-Sjx<6XIzSOzgeD^6A>n9>@#RD2%BluJa?c)4_82yRA4q(|G'
    'MttQr_m(d#sNHIY7wW8-vsPo9Z}JQO5D|1g<r%$t>D~DN2E2UX1~ydGwsZI{AKd>ohl`!UE_I6g&Ig;}Fs1$iR{i-ZUic*9>!D#T'
    'gQc_X#oc*61uk9AIGona&Izk|N6|48X~QT@;A#-n3*!w|L^=H+o|ZXI^|(RRQ`yNcooc_Y{_-Ss_CDA`_Kv8#^EB}fu&TSOh_@#d'
    'N)V?M=)Oncq1)p#UD29cQ7i$k{>Kp|;QKDOrS(`7mPuBAl*n2yATH5QzZELy?u|sXBMsbal};nMjIU3pb|5ck(pHb9pv0%fqBG_W'
    'l7Gt+V&vUJED}nDSlKyc-778$+iC9(=B~R+cfb6=H{R?7;|INBkj(oy-DGB;Wp(y=Mg7mrdtoEkt*JEuSsJCL13LJQP**tnA}u_M'
    'YkYs=jFY4_L~pZZ*#m~PfAegno~5)%nO8g88C~P$%T6!f@NJSy8@CCHz|mEYgHQkO+xH}+VPeelUVQD%L)bdn;ZG`^TFNuLY*#(8'
    'T7QN=AJYcjLDjB+eb;xqCt9+x=uTY?sl<=*x<TBOyD=Sq!A+e@v=U-;X*ug6IB<!B7e}PMOeVsih_TR=h{Lk%{hI?fH(u0M2zQT$'
    'DcoO*28bz(TGr5|D_?CL=zc5i%p`cnXYV>oZ)o<pZZ73dWqo&0P3L$3w^9{(8FWt8Qt|xD>rGPvU@L44Bj2me)i)nyYaM=dv*G-j'
    'NwgHK8&|zGE|G_U!#679X~b=u9Ek58uaAh^Q0xFAvNukz1Aix_^}jjO05Ewi0YPaF)y<cvvvQ}x^(({c4663X>=~VhtvYC9vYnEZ'
    'aE)BkyEh4>^8C(Jgo{_DuZu=&ygCGSLIFtm*WVO|c)c7ps{wdu_N;nOUYQH!({8?GyqiWMYjtMrP!KlvsPXp$t5mUjg<iGx{G>PS'
    'eu~6USkCJyaZ6`2J3q~T^F8nLY<Nn?X_XnF!-v}F;Rk(v%tXH#Ex}o5!lY|FjHhm~TY%Jd`v^vjIi~E|(E3w@b^Wv!N<ChBnXApj'
    'R-(ZVFK$LL#OmUGR4SxS&&(dfWJVY0^LUxARq;OKB;R4Yv*51lX0LgnKQP(!$xl!cDBF}9wwo=RT`Y}*V7l&-x1TR_@uDd$Sm5NS'
    '{py@4p00n&i9&6^ack)CXRo8B(+X@^hw-6&h-#~pcxq0kYiILG`SNJZ2kmMK_}1E}9WTe%=oe@4GT-eWO#hasRR)yagS018t3;dN'
    'Xz4t^AH@cab?5q|jZI7{Ar4n2p)w>KRnPT3P%mYTNZhaKaE}?EIo#^~cpuHR7Byi3kf<e#J49n1oTo7fYGHhtb@ozqTcaKzKYiVM'
    'Lh~GGZRFgBrv5Yvjuc6Y8*`c?keLIyQ4`ZV|J5IcINaD9-`t@^q8}$@0xz9JId=Es{^VQ+Hj}0^^)Kb-f9os_5FZ;F+`&=FX`8`A'
    '-*-Pxd%Y{$<;a32<rP=`>0`&3mFFqsmE%UYc3R<Gxt>qmrGmkDR5!3trIa!oP1qI0S<h1iqapj+ENNB3gN=?`z$5Ye_NWs1-fBsf'
    '?|yS4!_ua7%Qn_`?6hZ_x`q)WC!yW!HL_HV@9w19eMH2i*R29Q26X}fv%8tj@L75-A4})mMcAjkwN|nym+poq^vC;#!kdPwTW3}!'
    'Cs&v63SdE#>-8iYvftzKMnHrGg3L+n%o`K`fm7PaSYMY!`*YAeJ(v+81vvFMX{l-P)DPs(uc6BJEA5PDPU{9>$HCS$f{P~v;W=tn'
    '{zNi-`EEAXzY}ImHr;!)obY%2`AGt`zUZRH{@ym~3Kgqe+Ygw6>!`oJ|31;?PdJVqJlw;BHnq2`6H)F=nF5zkI0ozXaq^d39_Bg%'
    'g;~V6?!>}rvYn(pY=WloNe8#PX{fJFrRNaR=~t(Hz2|H3bsXJa$@OqotaF_S{!-_&Sq?_cwRYOSmZ>ll+%3d-Lv8Uz@h)ef$*MB#'
    'caFnJ`n6GRkY{JTaxwql`M2-u(w8r_+4pq)c02~EJf&u+6usN-@(N=lJO)Rn(~5ZUG}mR^soH<kVxE$lE2)1zk!(Flc1<PFw!5iQ'
    'A^YKGKOBmd3j!(HmzPe}Xrs|FTL;v(V&v5uB`u4W&%5)AF$cSTM~UTrmwZt@@a5ijQ<KHY$L_YdoDHhda5ti|<+0lMoeLu|YjIEL'
    '^ysGhjRF<Vd)XqdZ4?bHp0yV@_@1?!B$1Jh!d|OK1ut;3y909Ik=0_+@TP}yCKx>|3XBjw{qr03OssYsbxK31EUreV=w*wjG`QC4'
    'N_K8|i)CJ_8uaSC-?R>UPFV~3{#wdE?{wF3X{FAFTuLy`x*wf8a(QQze!kb|q=9{C)Ihxyoq(vzs2Bq}J=yNu#$~(X<Ilc{A=`%v'
    'JU-il{yjobadw<wvgFvKTJ;jcGJtKj)<9vWj@5oT;9v!ZNkLSNo-za`r86)|Snh*r=>EMcm2QQ}@Nh|z<I4GM@+1FR*>KY>B<}v?'
    'pw^bCm}$vHWc1x$r3pjR_itV%6}{edjXG!G5Z;6aOMzsWQ_=}Nnw^If#f2KMer+Mh`@&(Bt10XHIkp{qf7jRS=(^|iTXx4zp-$T='
    'lrHn1?%s6n?sK(q#?v-mTub}YrKb|@3f4HTl0K5)hfR1GK5i>bUl;gk@vTmj<wk4P!*o6C&K>;@GF|%$b|l0#O04|5_l1wY1@YJ#'
    'F1U5Cg`F?mYiz1VHu!JCZ}HN)k4d|aka4wlvUj>EPX`p0;hoa-u-a<tDdYPp@JBGAk60bPo#NM*mKzSo0AifFMAgF;a<w_qyFrbd'
    'IpfNBsj-gPonRNlFj^9?&(%X?p)#fI{BXGB4c=LLnha#-&3~oH6)feO-+7CBuc8Sy<MQW_R*>hWSE;*j5N2C2*N)z;64bOAdI@E='
    'OC7N7DGwSLUo*Ok^D!zfDR2z0mxkhM7H4y9$XfmSknqs3B>Zu!t)WY4Y_IFjd2`%^{*;PB1My=x#Jnu8Voi+F4-U&w;Ank|WyYF5'
    'KNy2mo0pTa&#4O2xc583x%KlC7_t3+q;*o$hQk}J?gtGFSxrKF3o^RrvBe%53tf7rfWyWqtdO1WrkrAjWb^3au;%Q&+tm0zfa09n'
    'K!w%(-}}a;_S)<0ozN=sD`ShNO}~%@NU1_<0U-_So_F?HrlDb@{H@eiqtoMl3C4@g0;;)GpqM4%G3&yE1HC2h=SKJE1EEE2*K3~p'
    'jaKQLCGY9SCHGRf(wW~ouDD*lr$>bayy|J}ZAyY$+B%P#J~<%T@`T%$dwdhc9%HT|eP>N*M%n&!fJ(N=NACjV^wD~CC$;cPY_4wY'
    '9f(PK9EP#$=7SzGM_j7t0Lu}6u7vGT`X5td9t)-4-;e{r?`@*<_ttF$to=`C>2!0%-TKkqySCQa`BA?0S}ewk_oaEoyJ(`!?zpZ$'
    'nQ3p#n|la8t`5Z@*t&yZu4Av^D%f8E_a$rrg|VYwACjN4Fp$l!#LH|Y+(@gwhL2KVEtmjisWP*<3%%E*0%2z+<ay0IEMQtcEnD`S'
    '*g;z+fErVGXKRgNnYu|6hWXWLAK%Izt6Y;{-`v<>zgL;g89a=rTh}3r#msqCzt;<bd*^2g_m<JXeVEH`WlKJT($!XtLwF@xz!DmL'
    '7l4T0$3LI>AIyv73~dYqIp)!AVQb1ft#Yh*k_}yJz8~e<sslN22Su-4i%tw=7LXw^-iCelb|uHh!NbWOb7GbW<%ZKI{?$Emet<ue'
    ')1yTnR6<an51{{DWU=gac2|7368}z!RHinu<t?y=FyJqyK!5D#>G)xx!J-NYjeEgB69-=NlR){mzgyn()I3{)!|`->Pq`#Ioe{3@'
    '+SPJX)k27yuASD|D#6jH2;K`H$3tU?)~~xw?Y@G$d+3nm*@%!gleVJ#+jnq+<a0HpuW93{JpFT?J$YuoT87h3hao!T)m*I?2ADFl'
    '=^H|O9r7{^%60P%12)yBsLK5|&cNwA^KZj5dzX@5zk4p}<P;>V5{);tRe2s_+#P1I7viv5-Z}Sj_aU!dWi7+;8Pq;@Z4cvx9(nqU'
    '&H7%vzNa>)Yr*YOaSzR~e);jJw~$BxdA+O(V!RoN*B;VVz0o$<%h#IPo_>~KuVo)%?KqkEUQ!3}Me{F%si&fuPGj<!4Nj|UZ8zt@'
    'qMX6u;8#ZsT1w@)yUmSQG43PLv8W1^&@T}qgs*Q&rN~GV;64H|%$U45<i5i9N=tpKUs#(<i%(3mC>FJ|_=<cwI8^=Vi>lX5dZvH)'
    '@~>wyoSUWk2-}gck82g_xI7%&v;O?<gdftAU@oZ_%l4tZIbw&Z+J9x|bd%bQDGbZ^XxnXexaV&V$Z$=-*%N}~Nq;hd)5jb@@%`k2'
    'Z8e6YS?wY|cGzT;2-hzOjkNh?2#gN9(E-TT37(TquVCx)q}&b}=HAY$o8SBT2Cg0L?GkFOC7%5gR~gIJ=YqxywaKbCRzJ+XGdiOs'
    'M}DO1x?8FQ^1eNud#H^q^fS6YGLOp8s&S6fG1kT6heJoG#VC|Yq;W(cVreF~(7CvHl&DvGLHX{(z^vwBb%iKqnKq$%J-ll9-9mv1'
    'U5s_Es2Wq~>%Tn*T?)KDegEob=am%P8-88~%GXXjfwL10A9k4g@cnIl%sTbrGVXTR%AHI-H}%8K!fV}xZgY0VS4T6@m(Jz^0To|?'
    'R_JHw{Q6E%K6aMZWvl*WY|uUX!w+H}D`o%lct5vws(<l0DQ%s;p^z;=^NruO)5Ad+40LBQ^@(LWYKrVS<|us9E;}jp^Q~Zx!~RL@'
    'A)F0!8eQ-tBj2XGygUquq}xk2=9k!B^TY;k)koj+UekUP98A3BHa6JDY)tA8Q5?=kQ;Iw0y$$-yzuU<C&?OQYYj^q>4(|OZr%!BB'
    'q;mP?7D{p&Tp6Y{rcy@0r+`4hbA{jGb1hPaoBdt8Uvi{Ty#RDnOY}7i{rHY?$-4IC3p$L<Gdyb^kK?JN+KWp6dp;<BRC;BP8pT-9'
    'tri-VzT)Y^n<*mn9nZA)jDPu*OVW>`z|>9nX`??KTm11~n_7yd@j8`}t)wi^PF<WtV_@+|sY`De+ynEVB-*WdioR!aovG#PK!49h'
    '4Qu~+#{1(Ir9b<1|4WBGD*gHGXZM1>kdNyVe9xA2+`B~9*Bu0lN1@e(F;u>0WW6cEL;8H>7WWMymH_%sZ%Hk(xdp0Diq+*>oh%A='
    '(e956`8O9E0yaBi1J(x$j8~z$kMtQ6DqhSJ0_uWj*S-e``r?;pNpB+lEix29ZCZE8#czwK2Smr@*i!p0vaS>)Bz)YTzKGn)vKO!1'
    ')UiOdn^VLHh|AcJc^0(|FwLq}<Jj+8$qL6AqdHjTlG|(6!0aqhC6n&GH%Nav)JiHbZ#3z#`fpDg<~5DF>kPVzeTkX&dOOSxZ<aof'
    '8_ywoDx~b{E_`A(DYVimFYv*$#W2S+c~i0T^duGppIIKZ9R6jh6?Ky*zqt}UH<*oY*{hSQ;Z>X!J^Br|QpSCC8AzymL<>v6>D0d2'
    'ClUg1-Y=~*!94PazIpCLc@Ej8G0LmUvIxesn-jmj>8fe6^{YR%q?%WxJjISEA|t*RET45CJ+t5^8nt(`)B0%w@6qhC#kW`N0>3P='
    '+5-@70o&F|teI51gV)sB{TFADaIto^Mrn6U9rs?%_BYmHUtIFX?RNCLx7KkNWV!CL&12667y{%shC0A_YfL)0k{!E)V>1XR+N@Mw'
    'pTL9g!+HNxg3>vR*H=b?zu$W+0$;=v+rCtL#+g3AtP4F1Caoz65!0i&&Tmz^v0U-;{kVgj$jSW}fMylbI8_uSSp4c-m*PlYD(%6m'
    'g}OY>4dB<UlF=O~yWgRXR8p^bxqIFEkl-QXA>NV?&ETL^x0Cp_&ydzk|6|SlyFMx}H=F*{#(%tzE1_Zmg>SoScca%W_9sZEda3Sa'
    'eQ$Yu%|-|+u#dcySJCmdY<%`w+W?%wdHH`tU0ZLmS`hs$L?9|L5#$<B6fb~+h#;U3B3@8I@Pdef`rA*>i{C?&HfgP;duG;}HM91#'
    'y_qvrVEXPAE3{C;cSBrb0`-fF6sixyqpcT5q5+~B`8l>PdtT`19wp5;;wYB=!R`n=h^yA-X2juD?$(>#2?5X9619JUL^Rpjhv=0)'
    'a%z?R>sKSx=>;B|E#NJi_}s$uJw7?<$&*-YvA(z%vd+g_9HJ4nkLS~RgbxD$)^lfvSePD=kM(d<i@&zoO8ewK=W_AuE2r=N_kz|v'
    '{0q**rZ>@w(U4*0X&9E|Z3FSPBuB5RJk7Yn$C{a~fOnL}N<j?HBg#fcGaG%+C=uokh=V(M_ZP>{oZ`!TSlpQv2)5<2%u2#YZwwh9'
    'EFWs)H#7wa;S9C+S>ruuF0-#ljMslfw7hsBc&jC`WcQR_HD(bDp%x=QpMUML#K?I#l^z+hpI`bhI=1&Y5tdg_i@0I%7CXxuhO0kl'
    'zZxzq-XFo-w5S*NPWwE7*6V|~0Gjt+r-<P`DrvuY&xa-~2Bo>6f&0hDFDoL;9yzUteaWk0w!Ck*0tFq7qU-J*#x-v)+==OZ-Z;K$'
    'v^gZ*41MkuD5K5s(1T(p`{^Q;%beLwmsLA^aG8vRljr~sGnMPwJ8aM(#<%C9&PXG#?Y3VgvvaqqZ=Wx-Lv6I(`>fcAkX;|2gCHNj'
    'VE8co`A=R+Vf<KZs!jpe-7Q(dmh1CzS;~d;RM^~{exd>Rb^I4EvvwEXiMW33cOR?8Lz|J$F8mp6DmOTv4eOhJN62&Fr~9|oem4gX'
    '_2q}QzvxM`nc1ywtojDUO9^ExdaZWje*F81vGT6(l``cox<zzo?SURGNLKCKJzMKw4@VU0C4lwoYXtLc_%30kQfclO<L0m!*A5)B'
    '(D`+(S*j{;;SACx|0AR_HyGj^e=0$1Q~*$SxGO0zw)(ulZxe$C^U<VHZRfwZXzmtSnY&JB)u3X|`NdpX)$C7{Kh_v#R#3OrNRG{V'
    '8y)wEY8Ik<yE@o!NMgDy%jeQ$@64}ra71wHr_PM>hxhLuh48k}?hp`9cgH#VGEQ8pKJs~LP4``L03SQ2$$42(Wfr~-`{7)aD+;eO'
    'H(%X0_<lD0i(;(X<Zj`rgY*b*{=;VxSE#YUAUHXEm*#O2vC0L%e!|?^b=2afek2f5+E-2Jwy@#)NTPIQIhv(eIon5g<MP;nkX1hM'
    'JA_3&qg?*Q@v;8#1WmUZ+2Fied@HliS*${o)!W@cSE7grb{`m@N^Lk2)D8HD+R(Et1tOWdGolPIWkF$&vm92Y!5{CBe|@eFFc|mm'
    'p#t!jWZ5QmVSyWd_A`}iS!M<FZ^|3?|CoCH`k@32xZhTXM#+B99t!gI6IYR_Mq`52Z1&TBipcVZqkIWI&kEytugaJNmyt`H=MVGL'
    'ICo}uOlna=P&**LFiKxY*8RiD$%8tS*)PWOfMIuEa20DJDh$x0>-9KGdcVB0%C1`i+UhJ~mk)LWB%l`Ag3_VE@jJbJyGD;8i*C24'
    '`wBlDRA_ml7PXmi>MRp>46fkJHCiBr)=J%DzY$c=zrFlDv)H;)55xDB&aj)78EcE}J7&lp@}9cuX6$S+G{*yy3c1Dl@`jc{yW1K<'
    'z=1=X0Oucw8{lYm_w0>Y`KV+6tH*!XJ)42Y;SL%#k;&cFUctT)$H}a}Y3T@wN4undl9!5W6R_J|&&C?7($n(%#n$uL*r7I<|0eq<'
    'PCmFdH2pVsC9)4Ek|7P{mfIE%_PhIZ=NtIoEUs)sCQ1*KImyQAeruK;>$Zz$e$zzg&UEMA4hgl`-J8R&j!oag_nlgZ_kZ^qp=iO>'
    '!Hn1OJ_8TY8b2bk4Leoc=y?|_%u*R%OLlbGX~T=P*uO-Kde=(%HyC-%_K{c_QLlrOb&wA(ZqNDktD(muDBliJgY(Tcy&-P<r8x-W'
    'FQ0YAf>6D#F&z@3UBS?kLTP8Al`wQjZne#c&km^Q^~|s<!Bj7o6=wQTem;h^I{S_u1p6r~&APj=(j7f+_iyEiUkt*OL5K4yb@Q~4'
    'g$obg94bC-=t;L+t%6&7yLd-6ZE`;%<+#>U=nT((`aJWV9}larO|0xmDl33+>>jf_2lwYq>;8gI+fpDx2kOnzLd%1eduA3>O3g^E'
    'u1ooi(rrdO)<!!S*}y^_b-%wp7u0%Q#8oFYy8@GxT)ovxOG&5I91wk1)avLS>(u^=u8({LHfmJ{AnWwn4!6DOA9+1Sa}17kTo=H7'
    'zMl?v(r;e`;u)~PGD1o54BYY$6}YBb#}YT|9K2kb*NVA>CsJCue){>&nc^)6y6EV8_(%J7x(KH>@1(0XAYa8}j;QCKAL;n0YT%$V'
    'p$~ftOvH|xPxNU8skd6;sLGw<N+z?tv{6Hkr_hK-_4XKZN3LMu2<+Ur*(*MmZ+@>+6Q)iulCxi(uYx#*V|P34!{Jc1?&D%KxPSAi'
    'atXdO0S!mkLu5+z&c@krOK0+8AMGg@lOo{QP(u;q?WQ`sW(dU}q@|N#Ki|4jv|ETQJ(AY={{3CuJ^H@wxrYYSzNCh?hbq~q1%a0M'
    'd|7u2=qtw(*!#<t5eGIQMj|TvMfScz>j>}RWqh^x?S-~%wVLLTI7AyTam6ee>5-uWnNE7`I?wWIhN|8KpK)?M?cQ`*nRTw<*X{My'
    'Bc)hI<ye3{ONAM~#aG4`73Kf!H8&5=$bHWdl=D=%tXzOa{c!rq0xd6u$si8m7kX@VdbjU#wA|DX<?r9)@bsqGJfJM_587i0XK2rj'
    ')#*16e|@eTt`&9QbN!qGuSvVJ0`2R^d!Om_7%@*qldmK9Zv>L!UGg0zX)%0uO8NVb%s;zXy;ncP$weK=JLFoKZ~Wcy_Rs&JaVYim'
    'Em{uf3-;~%$H%ubFIm~RN8Z6KFCS?yyKhS^oYKKYS=!4?xfj@i^F6gY%hl^SbTzX}#zQS&H<f()@4n_u=C|r>e`&71Bjvg4*=_tV'
    '+K&5OzX6}{()U9F9bpL9?D=Xx^h_3gmO*2LzLS`hwC)2GR=eU}G{;~A9j5>0VP<)^j$Lyb$&|r?g@KwFJV{@_BE!M3XjU?!qzLsT'
    'v4`)-;`nv2HWU)Nwz1siI;oYPO~dc9i^Nc_MO`-Dzx~b5w9mZIlstAz@8wxP@40(QzRV)*S0-g<uaVHVS9_(pTP8uBhympgvig(T'
    '&6jzwm8sxb$6%WlR1QkCyOIC&V{0FDx9r5tSYq0F^p9?fQahc#*+FnQ3zoW>A$RI#8@F#H%-Nf{Vj3{{@%Gy|8UZxjHSe{{s7>z9'
    'kNwQ}oPK)CVE7(En>D&2io3txhR@CPh<fEKlqT$F)Jw^z-Q~ip>$UjJY=3m_R>b@F+Tww{L-020TyT;RQDRgtLLUU#-=4(XV8?#L'
    'nT_7^DOZxISi6|xO`mOAl!PrR)30_~KbQy&7t2@HnZA_!^SC*6P77hmMPOR@%@jeWPU}!wK8;}cJ7@D9-v-D)__}g54d|*o`YM+S'
    'ST4MxhMwlb(K@;JHG<iqzz6DIz+{-*NQ$b>SZ@*|js0`^J^SP1P3(FIXFPv>L|(}1Y<gXm7&R|5%`GL|z2<;wNdQh!g?U}h*No;D'
    'o<HfCoy`SV**emDkFEQXazQa)Rki*jNB#8Mg4&PH!u)rCmY(e5%=c8p-2V|0Ve=wlgz{^9H@5lB9NYxSWHbJrO0v_^7SmhDNW|V-'
    '9Q$V6eaC4N(Js60Y*m{rP$wS#>f4Op&p2cX+i0q@f3T5l#P!mRS)FHdpb1^#*h8kD-CDf@%<JV;-jP7gOK#T2FBdaT=;>++PvymS'
    'b~sV?GSq+lvz&k+I9PwvV(OiZNXX{bSm~r&h|niVpC<}kR6n_PKMNQQ{~h)X8FrdzM;jb0iS9uih^V=D$yluDHR=2%<)2>I7#5t;'
    'L+bR4ZU;uL-Y8gin33OE>>I3?Pb{F&jVgO&IRkp!aD%z<C5`R9b!{+P!+SVe>>dyOK;9Z><EZ>_-(8u2(@FEFKJ5%Pf>%2ygzjD}'
    'vCC*Zk(clFW}!U0h*<Ncjg1~H4-b+(1g8r89vAbEB}Bpj{oc&uNN=I%)8~i#&a1lW&izmFjU$A8_SOylrqeSBn~v>9BQ*XWa6Jy`'
    'ElPO%F+f@+|Fp4Z_xq`LpB#i_xowD^Qj}t6muiX0YX5j)e|~4RfX-j5PGCNd3!|M6PMLLcz1R8m{#NQS_*{pzJldsjUU#70_EM_K'
    '+o7w*0DEtPgp=NMem0(E4V<a}yC)MZvg`S}DjS$Ibgr9L4i@1GX?Cxdi+{&iC$rh&e!W_G$d0z;CgUe{ii-0gP-U6tdsRNyT9DQk'
    '*}%e=@UL!4!cbmht3Wwo$|T?PO?mu<%xaIC5`rk1k;#m+>RIAD8{17ckKnM`F6o#iEwnh_>xAO3ZDzEsY6tYQ^PBhI{?HqTRwBfv'
    'N}z1H5%5$3Z6h4d;{&zkAo8q3bMAHix<zNci$rW|)H;=5_JWCrf?`xVLom1uFG98T!RV@uP``QmLo{XNf@o~g%6ZU`PK9zObhpvS'
    '^z}LM>Rz45x%qN(N>=SP=DaWN2j3dbCWNgo&j_c%ou<nusM?jMRR5!qKfbwk2UD~$=GAGzkh^ll0B^>bQhWXBW7EZJ#`&Sxo6A1F'
    ';|F947KfO07PrP&)M)-CUY6R<U+nsWR3@?3@SM$mx?T@72Lmz-3Bg+x$L&C1J22_A_teZCy|DGuv6|kxV7VBW{_%I<7^*Z{2F9E2'
    'QwK=rc<86C>T!`YH`;jAVUb^cIQna{Z-6tVoUPtUMNLWQ^eT7v=ZfD|PnTqbe;l`P1_mc019V3DOdI$fx@#z@8rdSv=6F}1K9TXG'
    'cPLhn`|HbX8|UafJz<ci?)f8mFfFDU*?PXYDc5L>wZ2xAi=es3KGC$G%l?+Sz}(2|qB4^pI9EH`Zv3!I{gy(F);Hj%L&7Fn#r2-C'
    'Y*%i(;qV0KK-tq@=+q-8-EW5_M`ITsOX87b9wA7v^lnftdM!U~L|o@c0U;^@qgKhyM_pn~w|;g0GDf)m!I{dE%)Jo1k1XWTbI9Q+'
    'uj(SSuz7v1(R7Tiz)DxTN9(428g;LuLpA2SDg%}8ytkp*6{SsgQ{+wj@&k^IC*STxu7wQ*-Sm7N)WBXI>HRaU4w0BCI@;yEB%W1?'
    '*<alYhENcAz!y2K{h`5z;XhiXjh~JHrz=(7i238)(@{Z_yGdFcO|t!{H2JM=aN313_zvD#J=RLoQFh<s@y_COY+rizu%R11y3@GR'
    '#M_JBIm0A=5G(ARSE={w*Y~`|1mubh^hT$xYsquiayd0iGayELIKFo%D0m9b>#k$~>c?~AF>{(&^(8jHXz>Yn;zP3%A<OlCH_;#Z'
    'I~e?U%XC|c_B&$Re?XG}P}_%QHkHF-ajXTq?%1nvzT3_0KNN4*-0~@!VprI^ze-z^6)uGsSyhN#cUPSnx~blu759fzllR4{Aq$}W'
    '8GBK_vf^qb&G$2GQ1SHswA}ypI}L>w(YW&wU%X3ZxJoP7TYs&(%Hugr$I!)fNsM2p&h|@jKRv7Cm)9lF(6qzcg+h2b-%oB2w{%MS'
    '#Z7gGSEkn&XEEy5ragPJMB&NUqV)4>(*G#6gx?WvtJS}mFUWTe_w9QA!w;J(D=hc6jP|*&`p9YlM>C6BijA~57F$)ej@gZSF_>$o'
    '_9kDP_A)@${s5wXjag&g&!4e?J{MeR{;l2vDwlq~2Qvz&QN_dppW(>+IFaKhK+WH^`s=ElK{@|Ws*`a>M^Lqs(bx>V3RMA36Tq7j'
    '=TyZoXIntu4|Eka_YHtxzd7B?{df_Zi)NM(L1K)i?==)<P%Z4B9ZTO1-%{3vR}*V%fE1{c?Gx~=UwYn@K#^tZ`I75WVr3oex;BFw'
    'HXNY8{-hI)Un@#d<=y>QDat$gS#QYHb()(U^*-d+exGj`%h@K>uC+jj4Niui(0FsXpOjcShOj*sH~f9Beiw93HG^MXM_@J2V#A$('
    'Dr`m*ozqa4$iI)rp={T1hg+@oE2AuMH&&cgHS7M>a*W&D4g+@ep<js+k8H5{t}%U$B9dY7I}bfgOAKH%>-9+UmTVU<tl3mA<%#m}'
    'I{xOa7e~3yx*E0(NxaIBHG`?rROeC<LIC@KJ>WsIB6j7m%s@{p#ee<OW^1bs{n|NP-!9X6>|QBSSX90(E#0tLg3QijIl^`yIA;zQ'
    'vnyg?dq2Cr%o=S00Lax(e8vNRRL|J(?{aM`|8P`mTdfb!eI~+VZ8&Ep+aX-m?9)CB2Lbwe2=&P8`yqAg6$yJSO=6o>Go`*j4%=r7'
    'l-Lths;R1e8-qzvN^jOr_lGw*V537J*>#PLyJ%LKn~WCP^4l-J&kVX-vU$9pceRZUiBG!=Qs+4L1Qi|aj!--h8F48^b$B4lf2d8e'
    'pTD`Fmn-*s6L&XCoN!fh{dY=ywB)k5On8s%_2u{(ZnCmG?yBD9eH)Cj*a4NJA7?We6S=b^XK%C0^$lnrxw}mN^^LN)`$@gSxW`0z'
    '2$c+1z|&cEe1lh~uYJ1KYFsLGE!!GlL<0cdvfl%)yXtdU*-e$picZq?^kW6Dx-jx^Z94z)tjE2LJs-FCnzAEiIcjq|J7c}(iD`~&'
    'mheaR9f_(emS35kDX%2p#4m=8mx;+A>tCXN<p$*6tAa7IMIuQ#&VKdy{Jnpkv@4G6;SM^*n`{)1_CcjnlPRvuPGplg8yb$gmuhR5'
    'R4?01us;dou3vx05UfmVwQbMq<=3Rrkm12m{M8}g)Fmp1$$)hAnZ1E$NzZ~9nYq16tqw-Vhjn8n%Fib9SJbeeI;?$|I;^IZbwkEG'
    'fj#m^H!a>vyk+(wMg53B+=tNAcYjqI&qE1WzVrqeo&Qke*n3=Oh%?lt&t}?%uzQ1h&l)j1_yp$h3zRBHXd^WjY6lPS%Mft1HOP<0'
    '{`>KJ-To0g)y{E|vL^3nN6q(5?Ha(_x0nl`&`IA(>smkMQ;P@{LQ&Le-4|XZb+^<OM4lJZGxGfK<WwL}v$d&#zdiSaU31iZQYw_$'
    'LUNQI_hKkAq9k0;UTSHbpOU9OoPW?ei7z`@HDWFeNhA*Fqm<mwgwZI)CSSVEtLO9fvWfWLITO6Nwok#$r7aAHJz!K_o{lvv>Jv?~'
    '<$tErU0qv7{C=}&#P?&euAZ#Z(_1<fyl>|r?=H%8w+~NCJ;2*sA!GX64+zG`<*HQ4k&X@DChc(jDPpVAzOJ4_cC+41y?U}x%MYVc'
    'etLY`JxZm)WPVwLL%|R3Bu7G48|%S&Z5gG|`B?qw412$jT0YPcF8AeZ>e>5h$<^=s;w!bVsosRI128N*<J2T;<^MN+%P>4ruWT<s'
    'H%k||VO{I-M9a&Up}I|1p8n3S&liq-A69j^)L~z_^peSMDNv^ihm{r_P;HaD43wImXKJGDd3$NQur~`^6u1+ujOy!#@WEb>gFS!m'
    'GiLa2K8iLn4Z7^)^i?wJ%*Z0)ivaWBU~q#%)YUbw!NadmZUw_y1Xv}`T%S;_AEJ<Zjd4h(1}EVmR>;q8CfoJN_TRmp_-*^`J=L8S'
    'y&4NVYD+8WW!Dd@dma9i9XxCY4*$*#bM2#7=d?OU2yENu%{9PK5;zDjqE()sW0^cBPVc+<onO7h<kklLD%CrlQ+MCp2Jds7jDnZ^'
    '?&{L<$Qbjj0g)50JnbmdiIYXCbh<o0BYlk`p^TWSz1()lOQX9?O7ag^cLE01Dr9=J7;I&X4u10mZ5y|~bMDlr0|1Ns(YvHcl{_AF'
    ')Z|eu#?WSI(L!5{sn_N8Y|a_sIJ>+S>|_?Ue{r$)<tr^h{dj!bOb8NMRm(3ZUib@fLR9vT?P0fyb&}GB&`-v(k2d_VUb@uI8#D;T'
    'Y=`MlliCiXOugdzhsl5VL0h=x@1Q!f{vwok1of^lduiuMBA;CP<~%Y*_l9=y`NMF-Q=_sCp4)57&MM>JK8>Q{Dty6L_s~brB}>>y'
    '#P)|DwpR}DtXb{QernMuY&khmANQ||y3;e6Pc2Jp<qZw(?)BjsS7C}R^UKlpLR?pmDP9F-eL+0q=OpL_)g`A&QtkJC*PZCg$ur>D'
    '#=+y2=Og&i+G)f7H2_yjd}b0f3Vw4^=_bV%?j@3fq<uWtVA6SY<RPOuTf2fE_ucUCSLN&v_qAR#lBVZtsb+K9>!?-SZMi+H4wU;-'
    'bTIAHddcF8iiSo>T2^3AJl1-?d2VYfO<kF9VI`so^=i&&0jlMa)%u64$6H@QOvbHicq6PdA94R4kDJqQga+dmSoh7rj&T(&8Z-@X'
    '`mDFlPIQR^)1WbYwcPUfa#E2D2?XAzFaXWpp2UKh%yw$m(mTLs;_wt}CgHQb7U0UM@VUUwxc%azFDC;IbK&M!ZU1o-LM7w3Sy;mj'
    'quf$-AA@6hqF~7A-2UO6wM@_=T&{}}yuR+^Oje;rw*#BtN#Wb>_5f{-Fem<^^=<ikzgcQ-&gyp1tK8ZU?N|v~Id%GvKN5^gp7UY3'
    '_Va1bdM{{L^F)5ml*pV@&-?z{lmfwQdJY~-MG?}9HAuVzsV=BfX#iy9GiK<j6*W$Y-*_xVTAY&fUzk4O^RD~z?|YyHapLsaU7s|F'
    'J4CUU<vy-~uVbb2R$;KTG>GX80}r}wQ?^`rRx$TZ%#m<L4&t&M9^|4_@|Qk#a98vmi2uz`>Sb}Kmn0|AgcmXsAH(!I<yaG=<m5eS'
    'M6uJuw9=-A&*fgP#&*F}4FRvUI2lZ9e%0&s5uxy>$7x_!JT<a^I?mPp^7S{SrB7yC{@P=0>>{Tr-TuC=Y=dCqTInuT2k|_Wns00H'
    'qyq``ru!bVJKF1fTE{n+zoeRm^^YbTipMnlcTaI!h}h9M__VWLmtFQNFW>5d!j5>vjWEQ;@AF<68gi`{hoTZpTIo!l&FItCnx?So'
    '!u;#j!K96&L$AMh9Q^blxYb?tobvW;)tFWJof=WSx|ELFxjPTzvZJ2XUROyP8UN^guJyl90c4xP)*fbBk_muw%|n{4vtdk%#=SYK'
    '{rX1OC?7Ug6?Jw-TwiX+cfNn_d>NdFD<$GyX6b3Y0$Z+iDzKC6>+$8$X%9wXbvNDLo?6yUpXbtj9)APma!U5dPmh)MCF}aU2^ZjU'
    '*TVccZ!LwGG?|4rkP+x~EREMy{@Um*M$~ck2gwfkps2%UPN+Zw^cdXd5^40&&b!6wg@VWrPtIr4CP(Afk4%Vi1zk3$WBQisQokZ2'
    'ZuM;U_aefeDV{PnB7Jn?H4S$}wvw#&0D1iTUAO){nKoX{%|?QcbmynX?$o?_c_h`F+zWBA%fPqCzSJs(bF0*xW#p>st7H-JWfF|Q'
    'a+g4gS7Vv3>d7fOgc5nKJtrIUMU8IaS3Pa3$?tXb$yOO06|uZLOk>D!+S0vXxCqrE2}7W3zODAaQ2ToZvp%EtG%pV5(|0^?dm|In'
    'rB7UyXK7oRPADC(=H8J0x0iJC!6zLS&m>q^DBaqA2^|8B7o}}S2~59TE-V&n`~p@gQK2e3PJ>F))bumeY#kfL6*^UGcPHO$9O9K$'
    'fBFT%^p=y&>aE<k{&^L*VFmhb)cJTfPT;{T-Nd6MQx7+IJeJZ?b2dqz_veG|162_l?nkroakZ#~%hutKls%GN<)`cAd+_{e;D0H*'
    'R!;6O_13F*W*^3x8|AIbIiI>ZpO*$Fa>OP2Zdz$TTXAuI)fQm65Xnx5-jDk}SS*%&7fKs1?iX)JrTj-p=HyhqXU4b4j@D&HSXw35'
    'SX_q^&bq9}PNhj7mt9R4Chz5fA5=wCnURKsZvL_;mU3$gu_DtNyQ}iAz75xVb1L4q-}A6{tFOdEhG3a~tk{=efLpYB#N!NE30qEo'
    'olt9d4q77Ddw&m7-^4eeFB_c-nlvU7Ko6d^Z}jtZzqEbn(bK1m&{qA5P81#FB;nk1DIOn^(G=(sI9@KAkJ4g}(JPL8TBF;xcJ5fT'
    '?)2~5;}f83-lZlYskz%<oS(jF74JdM^yA$Ch&Z+~!0)?H0Ewlt8NbF}c4qKpO`7!g793v&C1n1%Zw9lsy)WJ9ofC=TbJA;!a`S$v'
    'T3psE|K{R#NuGb3&-*Meu}ko_0=w*Ww*sE=+L|9SbCt2Sls$8>Au;blm!*LPlk<B{54!yUSCu8~g{+iz9JY3w?G1kX&chQ`>cA$M'
    'stb3p?T+KHnGL6M^o%LMZR(3~UTX%3r!U8uHrOU+y^zE<_<qo1*ch?IvjfZrJio-cewfb7d-sQTPIDtzLQY@HbwJi&<GJYQ)nMX9'
    'VwXGbNwu@Ms6e=TXXpCn{UpDp5`WJeXRWW=<i5tZp>axwDKnV-g~c8(emua~Kj<1&;ckD#eNZ<ei9EfmhUp7SXWE<Q)(PBO;`@Zr'
    'C)eN93-N8V20QGUK5V*L#rCI(>y~<~UcJQ}69L{YKd?Z%2dF9DLH_8_D<Ivk6w5>SlwN9<KBg+bVcB^%IQVo6R!j*yG>RHde7c-D'
    '!B)})e0<CMuu{AkYZgq=rTW7U4*IH)o7L&WKks1+>@}D7b#}GwQ>+Y1&E$nybiA*j&F8`ISA&fvEybB$PC8ZKXy1lJNzDBTy=n7='
    '@W2mz@#9%Y%cv$zR0}9)m=bS?W?Qer;q=FUDql?}yw|#Ni-7f#*mV{1MIHTesL0&4+&22nSzfU%+q{n{&N10gi#q*(J`J=Va&&)2'
    'tCaZ|rGGCqpsI{&!{mLVBey=-l4LCtzs)OB4qPQvZo{dqdbf*K!4IdpDAI!gapZ?2gv^2#`I{TO<oipF2ncopMBCM)zCP)0Re|n|'
    'eOmJ1xF%N&?^Et|iK*tjaspSvL%kS}Tq{lo%bd7$SH`up!#4F}AKM7!pDsP165a||J4-$j*ZOix%B_gI1cAGK^XfFX4tE!Hh#L|)'
    'qf5nYyxCL@{k72HGB&Bfn@+ZGN2BNPQBDybJ`2L{`4%ow*%JJ>LadJs%hs*Ly_G!?t~H(4y1DDsYTsSp@+XC8EI0}fm+Ec!RhJ<b'
    'z1qX!qMuhPZ?EfU0)muFIsW4p&g3FM%!S4(_GC6am$Aq>w=|ONFS#k-zBwrfnfM5c78g%lz?nC~%Vz1*!HHq#8Y(OS>&`9s%y#`}'
    '0l4nzcMtTi|M7WjGtY@C4?VWS+Pr*Y58^o9%_?<vG#yu?c~@y7_ye?LyNAIpkDhSyf8T;hJKyaa%du1aSVrg8-xA^C*S8<u%&|PL'
    'pvU9<ea5_6F*DE1y|SD*2a=iw&spX45`y&&-m+A67<6yv`|g36qdL{<oOV?^cZ}Nf5aH+l%|03|_|J!PaX8o#qoekvnufOR2hJG='
    'Y4GvK(w@EVb-9{*xp|=;a(D=Za)@w`=J;iR9rqY~kw96YclsiWTCiOq=f&?la2KiKFbV)Rhb_&#3X{Ql7B`&@y@Y84EqK?z51_v^'
    'R)&M-vzaDdc`KC%Y%iVTn^LRYO4&q{BP7No<uzf;Kc7<#9li783K$<Sz20l%_$ztvl@^ia@bY-y^wt6?(h=y1jG~RW^1E~$h0LVG'
    '_|I0ts{6OEQ?WfM1KWAtXU?UcJ{0T;{m@S~o%PF{0f(6=Q`_ltKd!Fa&k{$celt=;ec0Jdq0+ut!1K%*dJ#(5T-nouLz0ot5T>j&'
    'r}-<&<3E2G!iJ)VD|O4>AMRP8gZkd>2c&W{$_uwz<}UVJPoJj?GMdYOKuKzGrF37ZcEJg=Grf&*IC{0328p7ov^Ur8;)hFA3)7z`'
    'zFfJK-q|7>`LnjHp!^s+_UbFXoR=PJwLCBFPO!2s7EH|{maBy|XzT!sTAqudas2z1rz-_u3tAbAUti-7A6i_q@wjd3LjUj@Z>;~X'
    'x?nGr-Ip7exV#TpVF`VHr?}hV+dQi$_+LIgpxdA}6h6ldjD)W>o+H3u<M~`O|Gi&lIR-neej9(vZT)U-iE?LTNvBV-8d4)7m#uJC'
    'sh!vWnuYBKkr^W%y<#rFbq^iF7?-Pi-<xw_#VxO1g7Nz4IK&`d@K<$Ka_qjY)s-5vDI@b|abjNF1{7;p%PnCUCK>U>NVv2ynM^_~'
    'm@~p%SWllw?SoEHsI_C4gK#x9|K+o{n0DY=dppgho&0fzE*-m^css1Oig$up+Rob+@`&1J;Cen^TRyHJ_g7=@xy$rr|Ha+BIr(hs'
    'OH6sTTwx>Me?F1R6}0KoX?>J!7bi_Et&fajZ0krr9JGeB{r%~?B!Da%ljU$<XBA-h7<P^K_JQ>g#_BQ6uQV5Ka&xmnwZ$-9{kw;0'
    '0c)S4jN==2>HbwLlj^H9i}64QwD;HH<ypi32$O$D1AAHHq;0i;H%Zu>!A6#7kU$^Hz1=q28I`2Q#m4!kiv(m_!Y2OrW*?G8y*M4o'
    '-D$^v+QBe*ik}ss8i$2Lt()h3@q|VijXA)M@&x=a)ekpJD9Gzx2ePMLQ>L*+Pky?zQXgK0zd~v8eQ(>K$$|Y6&!2f~+<q4iS!i!>'
    'c>aa<U*ivsOkUk7WJYzA{`AOci#)_By$69U-kMzN=$0bK>aSnoj2+9!;K2mhEWo)*H<9Gw`~B-7`h0Dr&F`+)KOXwIblcKF+#cx)'
    'wLr=UyFrdYxAyv2PeDDegv-O(j|uu%`pxkdub4%(Bs?EXfEVExU+ta6SgA<6r~GM*q)B?OE-<45d0eyhinY_Ma(7GP1JE2+ca?cO'
    '@P+4*ee!tswRF7Tm)8eebFt_(8Y-}}g)tXzS2VR_JvU$b=;apT!?%BG8*F&PUi`85vh9w?Iwa14JhQsw?;wPOQAPIqVn&MZR`+*L'
    '@rZlh(Re&FWJeV{Ravi8{`lQ?vLCOyi_-d>I}1sK(p|PqKn}Tf!8Wt5%$1N>X-L;C_lbZ`hO>Bj;^ao6L_fa@FgH!*T-gq40cx5D'
    '10A$iXyn>fqR-7Psm!a5(diGqQ-13jw59!Euwaf`i2sfUTf+Bi$6!6KZ3P8)i<AV&pHI%Y%;&`@;r^bpt90^Z3h{|>p?l6tSUDr*'
    '&ORu3z1$5(S!YmN$WeBxOwfU$A3zOQ=ZD3Lc`Sm6iRCPG%vbk^cap^O+60C&Z<UGf`_M{H^}78K9}_#e)$dAmXS!q1WVLfgk+-9='
    'J@^Y*<Dw2GYJ;<e;T$^-VeN97nZd!DUVc2lZ&U%Y5eD;GzZ;~&CK*<(`^W_7=VpGN9=T1ov9(FBc$mYBzu``Qj9^0dDf91iRmGfe'
    'tD8I7ip_8ZhU?AipKoZ;?=G15){5Roz+r}sEtO<8^nG0V%gW4p;@yg-=Nz_UV*BA_X!DN&3QYhJ*BCAUT;LC`0kA(7EkwF^&SUJC'
    'CjqPtWL;jQwmmEb8Eue2(}`{gX_&LN4t1B=T5cmyeLBuJ`%UsqTFGsrY3OE`Nbdaq`$9tN^fdZl^}rdC|LYsoNOCuSe9;&l^Oyl#'
    '-H%Qe#kqQwmx1@TuRtU(yeIE0yVab!CTJBcyROuc0b2h0{rZ)!7;hud?o`FPlvnFt97o*>(OJmH^%(PO&qUEjeeX01w(%lMt5u%!'
    '5(4O7fY4K?_hzCD<IW<S{c#qd7WE%P&hzui#nZ=QtS7<>F8}yueejM|dH7wL;o;VA2C;Q|9pziA_c)Z*4V<sO6{~c=uAbm02U>g~'
    '#!~Ndmj1pBLF%0JXcw)*_AvnE3jA73e|soHj%H4afqDZ+&hh>23DWfPT#;$$1ksXm<04wx<=S?!Z1>a>uA+N!ZZ5Ft_1WyDD6(%I'
    '!v5hI6=$nAsl9Xc=hGm8clCL(PsD9NRVL;55CMnezC%75cH_{p(1zObrBg?=*8Ws&r0N`-Su}Xht9=xXRitINy0*HFM2oFvjPdwA'
    'U*I#fUrRiKCVz|=F=yA+xAZ!G7g0UXf|qeAdf`}>vh{dPGs&sxKyhJFROPlu1Ml=`Ifs_N-N@vscf16#)Bou>w{-%HLwa8>^f4<*'
    '0Y<U#AI%<BTIWaW$?6AxKBzg_xs)uY74~@k;{;Q3c2folHMzA)v*qPcRd406-?Nk*F#OGXPG8mFM$S87v$8j(zEm^>TEt7tVpoZ_'
    'XR!(iuj}^Kw})5a?spSO@2|bb8X&XpY1r`m1$u%Zchp?Gr4ms~g`YlO5`YD_6umKD-brk~wj3;_N55fgj4^q(NFolos(;<5snmsc'
    'Ia?Z-4BodH?=K~7bTMkSP`<AWYyjE9j?~n(fBvcUaP-;{=Mp0C0bpHaM?JX$_0N%i2CcPlQCit|3z;3>ZUbsnfTCPZS=<~ISp{kj'
    'Nv&2XrQR!JNOI4Ged(VMr*a(pfd$<QZbz85Yo#5zZnK0^4x6elF8NB`>c@Z^8&5}u6w};cGul7&xyF(~h-+T$&1e=;EuoaDEHVAf'
    'L0|vahL0lSUcJzVXRSZYPd><!Ph<YPWAGqJv(u?VQuVe>5ka}%>-jzYU}JH$(Y@CmA9VD;YwcxX1}{yy)UjW@JvGcfAFo;E*hN@-'
    'J629_Zk>%=lc^<ve1ijO08lMj^a#HVE9>J>ob;_*SLBoU&Afp6cE-<1DtO3wOTFwmi=QvmX3|pR@dW!e@L=4KMi&*wNF(YR)mHlq'
    'LDNzxKoD2uqA@sQIz1?Fxnro3gzYKJc~9%Dc8gK(<36MfaemAnzyBLGTDBi&0bf^Msy4AA?eNhmA%DLLvr{Sgt5TCTBe6`^5+*}<'
    'af!0(i>x2~ieSZti$`EZ)bctg7sR?3xA&W0f3jMX8b**>2J~z}mv*gl<?HIilgrf^zDN-BHQ>#6Z|7vY{vS&AxQe;p_i^?0X%~}r'
    '^Vn|oT02G2JX@$ajY0a$>l0Wb27}F$bi3{m=h9h2xE8SufalNnR5IVv3#v9wU0AC$jP1s;<#<gaX^Nk|xmSMCXC*$bY(QIbF8e~e'
    'ub*!E>eO{<efs10)r;D1Ro*eEv}DvRkkyBWZ(MU~l{v*Hi$yFv1{zCL65+^wO8xCo@Q}FZbmpZ$y35QD%w{-y{_4E@t}$WoqQl#+'
    'xOdIg!JC(wo5ShG*SS&8yS?UsUS-W0Ih%^-^|1Nb<O0?|jHdSu7&yrl*}WrW=}juzmjCyc{rdKjn~p5E$Im<_*Pr{>Om^T*+iV(D'
    '5X-;bNW#YKFfksOce&1IZa0vW=G88!u};$U0C<BE`kBUYJ-_t^X!>uzyV<BL=xnwc!xzMiyxapbCSBeGoxR=S+IeV{TCB&&hS1wa'
    '&!(E@AS3}ya339>FAJ_$8f6IA)CKxF)Psr-{La~v2r9Q%=lC`YL+oZW;w@PITHEj9y3D~Mj^`$+^67dBMM}-NHRtKtuA+@%{A`aG'
    'Z}tpf8}7AujNkXoX5_*@oww0%&FZUx@&zySipUtKR4X`7UzVc4?dxqB?DS_16Bg4N@ySMw-pk9S1T)#2_MKlEV(q+Mi}~%f6iZ+;'
    'sFi+m(1-Kz7^>|DZ>x!;8tiiJYCuPcH*z@rOb;i}n`H34TWhVZ1~r>5FITzT7w<HF>@rIMxwm@VQmfPU?of?q_phIxg&U6{SRL(}'
    'a-mKy{nl|Q5A2>lMcqTo4oN3-$HJI=?lwRw%v%w=O{Jy%G%KSn+F`3s^LggOOL}{9k7skF@W1D~3UGD!RxgyZEwpRyk$}RahIMDG'
    '#&`ARZDJF)yyZ0CYP*9+hkO<{lrz=?yl?Y9A$w8(HY2OE$>I1!SB)Bk{ks>O2ERPCM7?;&W>(dNy<~pz<5E96GJuxUtQC9&BKy43'
    'k4U>{7_&v^z30^U+0Q1gv7$)3xCEcCvjZ0p$K7v^zuPOZLiZ>=0G(Ob^<mF!gtv8f{~QEGtcbU1Z+{%j8QCps7ydO;x9cL9;XXmE'
    'GkWHP5eKdBo|vtt3-GBh&ELMB_*`%5v$KQq81p>l_D1wx#WR;A(`e}mgrsqAxvVf^uO@<l8vg<CnAkVP5>z-)C5DXgZ9Nn&Ynrc>'
    '=czCJ<_0%4w0XXn#@oEZsnwm7o|KOSdJTvGax(0Q>ZA4mMv$K`rcA43Aj?DE@Qb7+T9_Y=KLP6oJ&SONS$Y2#lIYJD5STI~X4+(}'
    'JFUW)%wV0Qyr|Cl<Hsu@)bRYQ8LiokJY3M|kHTF}^F6YFjoB7BpTn2iIa8QBZV5ZWf8D9>nfcX=Cn%4nlhGgJ-EO?<0j}G+Pf~53'
    'I!+%(vCqysW|en?VbuT9P5Sb_tBr;g?&hr(XEMW)IWhXkcN4+=oz*(q)DQorbFNN$`gVPD5wczJT7@?2-6n}~;ak8WE;(l<mEKx;'
    'B7a)GD@g!O1d9Vt)NjrigNGZuJt{LI4`5eiH5kv#e|}7-4s-3-?Igb+<gjH7%$G@}2-wu9K@69QZX9>He2zu)+Qu8V5p2cmNG`~&'
    'etKd@H_<#Y>Zni`&J1x@!{5A70Zy8*{4m@zBFwx)6x`$SdEV53u`{5@^H22>xb!}Ed%bj^J_$urPKmPskk)l*WS{0MSlIIu2|UVT'
    'X*gI=zq~`i<f5d<s6y`lK&2n;rsU#vk(;Hz#|kcr5p30CH2DU7>#z)W7#Hq3c}une{BW!=h(9sIKcE)Lvp2OO!1e6sgN$8_nV7BQ'
    'yKl7@&;vnAB5KWb)1)smEIDr{4HZVd*pMWlp3UL(oJ#~$UbtiIoOI`Ynx%s?qh$A;=9Kfr@uxFDBlvaP)WO2L^FraGh3HFTJ2MFc'
    '=rn|C>=BdUA*#lLgFSQ_Hg8IF*!n!te~Vl4S*%+`%dmPPI1wv@qnG`3=>uD@ehoMm^rf(uw!M-9+xXF(AZAS~2?QR4)g_9Kp4AKC'
    'EQhCfB7&!nhdRE05UZZZa@2@s8;zS-8+xW9{rZ#T$9skFI<%!5w`oaKn{0ayKE}B^0`^=A-)rOMqM`S$RXb@6<v$`1x=n#|@t0p#'
    '7q$#G(PM2mB&($vUDz-1SC0++Zd@8b`9>P12o*1?_DA`Y+oM@O5<a|xnPlN!i}A3S4kjyWbaNH`)g}`TjRmQ|hf|ydru+OT&h77_'
    'l^lL`6L_VGOy#pw;Mx~n-H#(Y3Qf)TvNJ2S!td*e)E{1JXMuC<;T~uEdVf0f(n?GEiVvB(155?BUNe8$<_}G*@_WCruAZNm9=Yr2'
    'FsPO4UAH|WUbEKJI;ee*;BF50N6hgW^(lX2tG01^`HO94N8OF@ym-siAUw>dW_z5D#=W=jn`5f8_F8CU15bX4SVFf6^Mv#~uD(jo'
    'yKyU11TtZDNUxB7VQ#TMpo!p4e(+iXHvxm5j{niOk|OK#(k{pk=gu$Q?rW-Lw%O=C^1r(h-(cIwkR@vV3U1f74SbPv6Yjy?t~p0)'
    'bt8>RoOI-wg8+#go-fSJwPAS=v<qhTcdd5dUw*Leom+||SJpWxG&;n9=O*ZV&3Xnm<1SurpVK@T^oqHRTgVPwHy#hA&Q9RzgW$di'
    'Wsc91#rS;yu$W2GeN}#aISL4{?%)k}nSE+Y9jqxn4<b3J#s2;f%Hb}F@DBK4yWGV#NCODA*Q;t$&U$)-UL$xcDWm3g)E7$FtD(=I'
    '!f#F&FSV9mAt$!sq-zK+prEYG55T$>QjIlw-%d6}XM>)@W}0-Y_B5^4hTBHX108^UPb&3t=4@~EKbnEPCxarb^Z)L<O$wuTnjshR'
    'p@Wy;V@!;v@U^V*$aaxvC`y7ygR3i!mCvPauvU>yDH%Mf-7qLlkssVEvtYcGY4l^)*>U#sH_~=DN5IVIpwsC)OqQKH&@f!IF83?b'
    ';6vba_4^1-k9L!;<Mg@JI0!uG4cG@~=q&MMyIw9weh7|_UO4p*mF*9wHq5%PmG0}yYb`ss1C%3!9<C0)3&Ulo8TuSohDtN^DBM_y'
    '$@clEeX(7{maOG=T=II$s#M}0$jvlwhmeno#xE}F#-m(IpSIspgLZy}xh;z5R^1xTp(qi~@Upts?6OJSYw%zQM)n?B7uS^c=1Rc|'
    '+hP?jxA&4?r7PW*f;iUCr))g9`R&RRmUcjw4JX*^J9Vp6F?xzF*%*n5K`iTi>osOvXf!_FJJeI|pupvrAB{^%N3b?{Y$=vAI%4I^'
    'xXb=@GC1D0myPx@7z!^^+}d7tfO?glgGa)0**kcQ(rWlxb5r%uN7^eg*6p>XM09BTQlC&;Z_P6sv&XX!YC1NdtY2Q&Ru6o5)*H(Y'
    '-%n>I>2V=`pxvd!feeNBlmzU<aJ{jPXjHk=`F~7ZYtwpe7yT?I8D-2k6q%Hwh;$C|f=KB=2a%%s?9csw)9-n6zq+R>_O<ugYp=bo'
    '@LWGo-V<e1x-Y6uC~g+L>!mT^&Z{umB>B%*VnU##+CDy`f!}=a6&OE)YrcQMvt7bfNZ_t-W#VqVU2Z(++x>4G70iI-HWu0{DweJ6'
    'vb1%|?d>6>>Ij~!etEJz#fEJnIQMt``bQYx8&?hU6K2J!e1jbTJyryqQE$DPxD&wgS%O}*ae4TS`ry6+c2?Q65w@o>hAJhUeLO1R'
    '&*upq0?ea6PY~kXtevqYKA+#`$MInC?Hd{$x}B}xZuGvs>N&#~-j-@Z04Go9tFxHX>q(~8M)wh+4mX9d+pg}veseEu013EyG#^r^'
    '(zAMGisryuUA$tG@CEXri)l8%Mq*&imc+_%((Zny$AfI+fcP7_RB4&lb>h*3dfN~Ne&<3z3)KV9yuVxQ>lQ44p>EIXHj*tSzaS5T'
    '?WjuCC*i26{q=2sShV<0#DEF*RX%o!P8{qVpp2Q<Tm#ws<(+^2Q564p!x2)yJYj48*N#ChPZ2S3s^cNdFZ^WNO?JDnF4dkNcXDOS'
    '4<6~y5Z_np&t+%Bo*u4bmi^>#+XvmxXZo)WjfmBYz>W7<^(I{dR6ZrJ&RPDH#;SiM%|6szTcn?R&#{FNoQBpwA>l{4&3hfmbFT2+'
    'La(jItFbsHbzy!B{@oABp(Mga%Y<K6*1&Q0;WfN34R4+Lv;bA?a60e4g7(=C%IB&2yg0}ZTkQ;WFwtF-wge$ORhpzAPb{Ee#*^RY'
    'F0<0k^EX>&L}Jg*bGHkkNd4HbzhjT15)TIZR}~|&3H~r>AtB$IonDa*mL_t)y6M1sSJq4*fSOrtciLw9ufFZ$TWnQ5UK>Ll^Gl8K'
    '9J}T~*%^ny-p*Fp8mzJQo_lq{6D(rgXrb{Ze%091R|LD3@fpaxz38zlP4}!Gc<fI{N`?%<?SyJ{7+#F!MtzUlo!)ynLzz)J9V(lw'
    'qwW^MCE`Ei`)~uM*S)lA_c$CAU&Dam!%=;YPx`fY45=Pi+5h&ti)MR600P9J*M`M?)}5oB--}|<iFL<Rp0+K!jWU4j0;aP{hIM)&'
    '?7L)f!|16`O>-sMjC&=C-%X9M)wrPl{GijBe_zc2=<pu&R;_JciI5vMoy!w5oW<RA2sZ$3y!}wV-D_T^utvSoW7t@A@os!9S=`#Q'
    'GI=mRNkGMr*N*+mzdPYMm7xq>xg8>1U}%V5gH!wBpttl>S)EEk%R~n3>Y;yYiy4#SSt4)xtzK2#gP^<BYainx*U#K@7G>fl|9Afz'
    ')_-10b-q2mY+;P|6tdo1At`k3y5sh}#8lpmw>Ra%buygs^Ad;bWh$rr5Y<ZkRg|x3YbM^$Hh6D=GK)90U*GLbFO4ozv8(s$UB4@H'
    'e>vgV<-RggA8>zHzJ_xrn{g#+dFwL1r@<$Bb%j^QMg2C4pYrzlKBjQzgyKk}`r_@|5C2x#?{0D_W6)poRB3NAZhc;gW15`r%5!3z'
    'ShO;;rw1ap%G9-7$()CKzV*EA;P5%Uy>BCWOP_0bzWnH-Jguw$=BCJNI6I1|p`R$i!epS%iXa-wH(W)61qEaFCTN}bu3hO4L%#)n'
    'I_siR7eC-Mx#gAW8_Msl8u>e#dJfqkmF55T-!g6~Ma$Z^G-%jF(JQ&t@lHT**O{|sgmhq|x>^JFK1J17eVG8?xT1hX!d5r=E|?nE'
    'QoL@smSzcm<+_djbj4JN-O@>U{aQm2x=ss>DV=fPjK<C#$>8L$dvnNR-!!33(76MEHb}bUGN4MA(rzaDlPUZR&Rw`!-zbUs1^N0v'
    'f36T8NuSOMe3>aOKame!9+&Ff4wN7{5>S1)?@P|5RSDv^2Os(a)&{E60rF9kd9%^ok_WNDSlCRnsYdy<`sr+@9m;*Nn+3aAuE2J6'
    'x+52d?q3WoUFldLL=b3q0nYn=7jnK;rgJx*M@T&u%iHDH#F9N<ySXaS59A}(r<cM^`FCIQa88}N?fnaB2=^3^_IfNg+_1gaq?8vo'
    'H}8{~9s4_~tbMQB{bZ5zbz6G3UWQfVRj4$QqOMslKrU}v!cq9uA%LIF&A<!?_Xqh5h7WdKuF6|wqXwJ`qJNELu<NE%|J7ZL=q{#o'
    '!0nWd^>|4iqCRQdzopVA$aZycj&w%N_xh(>AzQ_Kal5sf^RTfYij!W>Rb?daOVl?)EVG-PR^VWf6Loc-Xyh|XH2AvMWx+5Rmu4dL'
    'hl<#0Fy#C7;L#Y^_K%N}7qvmPbQl$C6}T@ZcXl?$eI*}{XPZUyO^#W}Be%$E+qV9ynbU!=gVf7y(h%2SIWp)=m0N4<(dS4+PB2jZ'
    '#Tgt#DaW@ugQKhr_QZT0UE^7ICCTyDEHCtUr?n>YbbdU4+qD@G*-YRzP=gi5VAV1v#{qM7i>wiLs^!O!Tgt!r&;lAXOwHQp!}1p<'
    'R>v91OFJK2e@_o*Rtv*TLKaPA>(jjY0oVm|z6*)X!^B?WA&t#Z7#|I4^LvSFwFl56694)7#B+3d0zOPtTO{9MuT-J8m7@7qIHqm%'
    'P77;{(Ka(lCWUTs&Ce&eb2|d%RjtI)N|}>n>j6Qr@VW0=gR|BC;Rm!(K}#1Q`%X5iGFwSKZD@^6msYgP?NaS$P7m&h`|&Q?LWhSs'
    '9eu_vWsq`~G9L>*`5d28<2h>j&*AGDbF1Hb!^yZjzTR@}u+gAbsl>K;USEK%L>f0*r|UbOpTOQ<jPYRC_nFXWa(KLVXF$K=-;^>o'
    'O4j2;Q37kl$6SAR@b6yb>}aG4<!oo#VE|mts~LG~38#K|=+Enix9I2X>#(IWBf3FO3pLB+ZfDzy?vHeRSV4#5!)c<W9hW4gt4@X}'
    '`qMwO^Yd%gePyjWRNM3=j4+K}xkuM7Bw0SN*s-TY(>AZ%f*w7{A6x7)5POVdGi-1+{g6Cfgok-pPprCiGC6K}`t8R`7!Y)H(B{nk'
    'Qu1oy)ht&h-Am0@g3(i34~)`aY%Y#}aN%+4-7&T>wkMUUB>hZw`SEeu_zTZPnn&)0?IPgj-yVwXiE?RjB^|$h%ZO>)@PR9?-P*Fi'
    'N<!sU)zhO`Do4=flQg1<aIn=;X;l$r{=@$F9x?}M?IQkU&y%RL{LMue&i{P$y!W9Ub{N@gBx}=31+Lr6)sr2~*GuV|;gLrFJ)z^H'
    'oC7linsLzXR#g{u>!4N7)JS>|Je!w{Vn<(px*#o{Y%|}uVCTlMjpz@~UmzLke-lhEcUfO5*?{|ATDgEtKREWv+Wlv4I~}DXFWxBB'
    '?Ox6GHjN%-XgvmR%l0qt0C(n7yAOMEb82qsv-p%rZKPF%p>QtIQ>Hka!R~FAP9|N;)A{$dKc<Ml`0QR;c<XU3-N%h8CO1(F2VHe&'
    '|N8mT%;VA1X0svc_Zt!Rwf6huWZ0{9DyvVa0w#ET2r=pw=#8$EBgyh6>B{iH%sXED8nKAGo#F8d#+PsJG81b*zE42=bf@WS3O6UK'
    '+Hgy+=4y5Qsg7AaMoZYDiGXQEbNw~P@3IvMA=?&%mbQJIm*odCUu~B)x$L=r&%N=;-2KlNyILYZ(S;~#W=%`0X?1>W2+M(HX!DIl'
    '6d_AR{MtKrFQ>r3-6+e9$5j>QU#-DzE0fwy3>jh8lu|H+*Vf1${&XPHM!Ufad^N&LdHq@yVcqYD&PRG~rDyaYqkUDBgNFH;&S%96'
    'FE_$l3;#^CgqApZ=^TdT6z>4*QIFF)q2*5h@BY|_;v2$&zDBQQ{W@Z|r$_~NZW*BeGPZTvRL>}NwO$vcziJn~CnqdW4xgjv^1Mi&'
    'Dg8FlFTL$$+K`Z7ko?u-Vsp^jcW1)Ivyn2iCWJC+3D6ZHLse-~^}lH9^H#dp+c~1CaFd=u)etvvZ{mvH(KfXL>M+uc-VW%pfV$Nm'
    'Uy{ke46m)Xl(<RTVBmyhL}(*+4Zh0F*|NtmH5;hcKMQ!|xwU<>-CX|Fr}`S+DdW!IHoml415bE_M6GE($NazhLQ8mWtsla$M%TXY'
    '#Z?*9OQ{%@_FDikCFez)EqcN|7C766mA&q_pLs80I+v?dRyp$fM9ZcORz#O<GKqQX_&?r$QwWhUE<z-lBhdJBBQ6c_xQSgiJe}_k'
    '8A-x69Oq{{<*!4C-V*NBX;jf>wy5lqYULn$gL5(IpXCw|`<mqZaCL1{)Fx2UJUB)5Hn?=3O`-Gv_T&4+T-9{HX|3a<F*0Jw-HG4g'
    '654#bKLoMC7@@wL5mqi`x$?4fx(g}Pz6<{F?~7acI<O&;RmL{uJwc$)^YEM<Oyba;b{v2ls_(|!kxd>HUR!xv>22iMg2Hy?Vm}y7'
    'R)GUS6;<n7=*v82@84Xy#hfqL)4Z4GEh+CU(@C$JDCj<D^88#M>K^f`n{Y#=P7A15Gr)q%=cTWFxV~?j<70gRYRPwCTGPqlqKY9R'
    '{66=w7?!sawbb_u(Q_-6)HqZQKFxI}M~}%Udjl`0%8osi5+(?rHMXG@mzZscODCQ}uaC;$SI+Z{#e9E<2g3dR&tLg9fje?E7zOg?'
    'ULLoSh1#uF(;JDQb#r?|q@uQ?z*48wS_t9(;+OA|(~4%hi(xf%=hK=ikKua2LwL`9x$j?{SGP?+R<wPE%gViEF76))ckzhHgoJBK'
    '`A}JoQL|c_ye%ugcJ2uQ)P=xRj1qF^w9Wn4tOtlRoJ{5q>J#D8@HgMQlzbyd`Y-6-=&$e4dHu=lXtUdZH5v*clb5P~d<XNK>nyJ|'
    'q+z+|-H_Xe+JBeEi%lyTvERy?=-}NC#!1b8_q;wjR{?I-$^Ymh;CZvU;&nWjA4kJ;_da`s0CeVbs6Fl-{=yNhg<tGyIbZiS2<foh'
    'J}w<{bnR0Y9GSusiXwVHd}hCwezv%g7CVaaDl!P(Wn*l6dC8pCpV75)X%53$F>1^gUp54iL2vl98f0gk`i<AK>E-p;f!p5~(F{1}'
    'EQJ5~hga2~J$JWZK{e+hVpl6eX4Nadb$fm8>3${h@s(}NO0U8h->3VUwmwND*%qJ6yI0q~q2$l36swfJS#LRak=c*8UwmTVHFlgG'
    'YJAOe3V+}MO<cm-?N~mk+z~Y_Jt@oHrj@|PX>h;G)LN+B+oyU|J0F-=8`*&2o19~Y!K}1L@Z)y?=$$PYdQrHhaRYei{5kJ<(iKU_'
    'mpi@ZWyyMFWV-0i){~n*=M`i5nv|2OmDU7uU0jYB_Z<<L{i67<iME<Q|1)bW>BBYHx+E)^DfdFDlZ;m_yUJUthuG^feVfY%so!qn'
    '&d6BR){Xc=$MvgH9iGB|LX+vCKRN*hlV5ah4ii6p6tXv4M6Zpy+;o4(%EZ99owl3tnq8jyNIwCFv&)sHq|cTXD&#Er`w<os37HSw'
    'G?1$n{a%GY#U{uDI%?I-<u4w5$k}+Jwxf98s_)-}&(>}X=WnEO_^g%bq`ia6n*oDAkf+du3>MqXQ%@XiDdRXiRu?3~RctJ*YhLXe'
    'o*)&J|M8R8${OCj>u{y*e!d5Wxht^dO+$!Hq9-?O-D4Y)mbF`F%h0%Z7-CsJU?%NOUktB0*S?I|8Rl_i3a&vF?e*J-L=MZ!sr}%3'
    '+9Ws=Q9C`v!D?hV7i)M#tN~W-LGb3RwbUzx<HmqNMy*x7rtbsy!7OE;3v4;R8jUeSB*Ve&@YBUt93k%xc%ZGceN3tACU&{S2kJ22'
    '*2K$vhgXF2Q4Q4ZrD-=&cHbLUtD_ivjasjkv-()5JJ#pI#W>=#F*@A1|M<zCfv!v8UYI=VLCAFs=seLqv`MJf<kpah?+I?9v_Mq!'
    'V`()HePGu!(mMPIKlf5`ZuW%%->uA+Ll!Ycsk8d^Z<Am*|D4{`JYNy8qTeu|{_4fd=Us>%?&xX1x$LO8>2Dr8Xkrqc{p@s7tkH*y'
    'rW~nwR%fpR80%m7V7`0d?r)BcC)4o)bc1_Uw8zRuzR-U~;KY>QP`jeZy%<H<RhLB2COGU&B%d5@TV%kD6mO>5qM<ZsJ;oY4tu*5|'
    '+v(~3!@s?GI&6R|<rbm(;U4ELRSec~f6A^-&-+Q)P&^$~%0pYqE{fY74xXs~F)G>Xscf&7RU0Ev(`D}o*tXg9^6LIOZ`x_0RW#EK'
    '8oun=55gHT>wW0f4dg&!Yfx!dAY=arS8kJIyS+P{<v3%9&gpI~;?guAg);!eM}#kkxy{$BKYcYJn)`|Sd|`g_SN)M&x*3comrA&M'
    'D|2KVPFuc8fpXB@t;2!}f?0p^+Jtv&YrH<~Nj~Z~*@U)N4Fc!tVIAN9aLFt+O9y-9av-<tRglwZStoV90lV0%ci}rnJ>2`^WPA<*'
    'tGDLbFcoVw_C8vDZ#{%{;*pSp3BGj)X?N(Ep!(Bm%%lTghQcK%u}Ql%Umo=R(~zuS_E)*0K;CIg^fXq)XqSv|T%onT{zMPa7tmVt'
    'hS&mySAS2{?F4w;v}iQg{Q5#(P!^epK{yoqZ1$#_w=!`fUvRT!#C0RCqO0z#-yFT!+8-+GUP95d6(;m{rTF-0sUZ@lw|mpR))|E?'
    '`$hWWqXx96*2m$KpAp+e?OSh4xw?FtpZJ2g1x(W)OppwCD<AYVL29OB6HuQc8Q5NQO2~W&*P|9Pc+cDpLOIE*``fczzmawV+57K1'
    '{=%$|HZ*oqI}b{WX=VQUP7O95mEwTEl)m^AlJux7X4~XUJi(UOC(TB6SBu9S))3nxi>Zm(&rjhHIMTDx(7-URFW-qbuP+~@7_~(6'
    '!+m2axIZS(c~}F59`}){(aHa!*|Z~UWr}!Aq{FH3l0moG^{v@y7fk%0F4H)q49%cr$msW&xpC<2_i5gLrUyj;Ym@#So1WXJb%!>H'
    'T35TfpWGnovzGGs!+tp2^P=D+Ii_Z*%CfT?$J!59>#v>&A5N$&^)PR#+&(MwA+~cgFMH_Iew8x>h)~hrd)8CLChVo)GEvzfNmO>T'
    ')_(h!oWp0c6J}h6B<p+e7iSL{d=D2nhyVvH%*HEp64AA+m2B!Os_h2CVcvug*efqr^xq?4%yo^bw~9%ocvny5&C_Zuw4RK7Z}Q6p'
    'Uq_vPx{7(y*lM5N7s&Z<14@#3T;91yZ#8YM^m4iJoaQvuHKPvN?9C$&lV^lCtKhSQ2Z?s@_mA!R=uHgHqiQBtd-pe=cRn@TWY+Gc'
    'QN1swcZf(>W}lC|zN>fX!N`pUYc+dpw~uRmWlf8cD_nH`(cJ@vAT}T6Ba_d9s?-H*n}JdHfBXKd1>%m?9w=a~vkUxD`k3{z!-0y<'
    '(Fte@e}UwS)A!(%UYvDA9B(jM9Z{|BalZtKKtEGwb5?E7LoL<2#4cxkb-uDT<`^^?@(=l;tWRrXqZIxoIWKX%77On4MD^>9hl=;K'
    '+M|Zy6Y}}6dRl)*1QjTaqb*-fE&fFFw~_xIWUBw$102t01exTR+Qz=l%%ri(=X3;@=@=wyX_UOnPFDs+?GI7!zeHn19DC0#-jD9%'
    'sUs|ek`Q}4T9jKh2J|+x_nWu)y?2>q>f24d-Jc&!^O1n8-Cw^o;R#yFW$xLZO*9hx^;|gHx}k0;fW_9G$r&F8@UsC}M11Txi@weD'
    '-SHs)#Y26~3%FpvllvdW@*zXO!E>`m)!I+I6dZ<?-8(2ODQp0$a~=<$+5T$L^l{3nQww*+r;1D<&ulGTg7_6Tr~JpCS$w^H+8Yo{'
    'rS~#<h^~G6nV&jMOzj?~lhI`}{&X|~Rd8MDrX%10eQUOv$cMU$$dd1sb~1k*&C6mh3(!(c|IJM)2lAZDYGkhx|74fbniELnbDJH2'
    '$+wrGg6H3oH#P0Fs;b*XlK#M9d18C?X3UMKCWi}IepTiHsMl*UHyi1{eh3)#R|NT~JmoMvG!5ArPtq<vJ+Gf8I$UtW=T+Tj{a$EJ'
    '6e(-7k#U?*>SneU(`lwU&F^#Zd9|qsmJFa4-|D}-v&P4emtAu8-C1blynB}*Zd_C2L?$laeUBooup*DIz3w2Kch~DOCi)pF`SUv<'
    'K1)iOt2l#!sVr}JUH~unpC8B=UDGitj0;d4HSrfKf!Vnb$c`0E*4N?=E*cLQSnmd^+=a#@G#|Uk)~wzy$|>LUH%IsjotMXmNTb!x'
    'F^8Am97o0NaaFoUmCtZ29C(wSUOX@T9%jm}R-vn_+c_OB+2EN#Mskzxo?91IoOw9%#pyWA;p({g_l6cDyO~v!OkMuwS;tpgpO!j4'
    '5=_v`2RkFa3K3u6aRq^zLcUbf$2aea{}d|HbI8iDUTYn?WP`DG(Ia1g+sg4fHE+ooUY6jJo&UpU*=3&P=OdoBYIUf|eyYYc$$F1('
    'DE=q1MRH1Xuyl%v!4Zy!CAc$LnXOf0+~2MnXL$6i8F%W2jjy;WAAno@yT{yoj`X_mS%8-pImPkqr>10W%4<0wFosE1oRv<i7+ST8'
    'VMsJY2X(J$%Hb*;EYZ_g><s$^Jrj8+uAT2rrJ4NrhenFS*?l73RkS-*Eo!2$jb?}4--uR;ct4Vy!}*pzm0;&RJ~Zklpz$IXV52u_'
    '=lk;IQPycbtK#!Vx@)*i<MZ1O&^p@ZSsAsFepT46;S;N@{I;CTUP&()fzM#r1mlXdJn%*9kd3!$?{TiGAL*}!m#B`Hfb?+PXwpFU'
    'V>Yp)lm2+bZgBcUtMM&gjK-%hgY})AMY{zQJ+F*jXPLhaP!`LYGCC7CwbGcv1pOV^3$WDqOatpOw2|`@cuvmFqLX?9>ZhkI&b4mO'
    'PP`CDtNHwCQIBzrcBa!>_Pq-g)PrDoqP8~fs=YiOlit*$%%C-%94IebJuj+Rp5ldgKt@K<bw>E4`tLa){=Spey6m>~d2Z#I0lgQF'
    'xO;E)KKL3F2A(!^eeBAc?QjE^XJr_<JzvrQ!82bH>{s=)%MOdjrZG<DJFEA@J6x#^IZg}k1IQbQx}$C{?*0->Q*VG41&>C(hD977'
    'm6xSn$eleK^;-0IyYjSey%byX#G)LrDrfVRd!G`g>hC_P%I0A1mnsnh(?Q9I=z$<p-VK!uy>8YBpptLRa=xVxI_5(ez2^H9n0`O5'
    'J7T4wpm#0#XrgAibHU&R6G+MLT!5Dir6o*>R;I7p{M$XOzEgQ>)JsP(tNwSF>(;k+{l>jrt)_gSi&gN#B~x<zHFn^vOJp2<vnAZM'
    '6^u(Gum97h@{`V~se<4~ncRhwe4a1W=Sv<sZ=BgKXp|-N#T&1ZR6%_{h}{t@50Y7S3nHRsL&ol$n0lo*0Ex{Vp=T?)_1hCZ$;PfZ'
    'Tx~h_`iKgR8t=@;U;U^yi|EbQF7;&AHP`9Zjpf-;?G5t>y({o;0qQz~4fs|43w5`gtywZvW_1$##o6#)vBdV&F66s#x3!*xJ;UC%'
    'ROYQngv+TzoU&RC_8C2KZJ>cDujh2XSg!YdO23@<hD1F<gL>~agI)vs3&mglCER)Oc<G1d<hUPp8B>I3S<$hUA^NOU_u=IH4EGkY'
    'zfv<+)alpj+l&jrf=iiRnCI>{)?f4Dh{uxiLe@?5`0EQtfHImOpZF%*7alm@L$y=ufOVi+Fg1HAdY<+K)l%?*^!!z8y&0Wj$M)C|'
    'klI;ROl@oHm<%n?f9L!G@1pS6zm0c=ehCS$e9EQ)rIe8VKpzB$DV~8%4=9l7Ab$|NMS<;TQ3Hk?xzH2B+|2Sk8axHjA5i5QeR~g{'
    '{MNawzrX&?1h)g4Gm3R>@jQ&vn|iI8o~VF}Tr>9>Q25Vs2_CE7Mi<NGYCPIn5|e>y{n53$t6AtdU^h;lVU-8-G(FY+Z$B2grURna'
    'pPEc`uVhUxjs<$KoLsl=v3*Qx<XYJ=Ux`P<R$@Q3L$=zz^YzO=bdEBV;!Gc}2%90YJbcEO(fp?qdvY@2x$PNuI-amK&925Kwe17z'
    'l3EMfTx-`ZRvr62N4HDiLv_%@#(W6iU-rtec+*@5JF^8(eE~c7!N=r~{hqJ#jTy67x6bh9>@7y~zC2x`eNQvJ-n_W`v?YH=<oC!-'
    't;_f=@;F6xb;Q4xhGZ=<6dK~S-DGhgZS2_$gLmV%U#MN}rMjt(#yH+>6-}2Z4e1J11NGMTkwHL-?`*OFSmWd}ssi)z+x$C~z&9>S'
    'y{lbQMvgK6)`n!f^UTUb)8L=qcF4f}=Bm`jTGj8<n(an)?R1i(#-ZLeAK43<l%m>cs)oX5HUeC1KG`HM$%~~2GVyEYVo{l5%IMv='
    '>E|JN?N)#KzODNyMRO!4RR8+lIjU63ZCK*;wZVc+PginMcHV#JrnwLg?wh0@l5xHA$M)bMUW#_=11Sb6OR{EF0tJ9CKfGQnlpRcN'
    '!!*S+tropL3R53Fkj@1`(K!_~gL&5%i+qq)-_`eG$h*Q>`EcEiX~t~#ao`jpPTr(&9epD5v3dObcP@)Y(QDj`Oo|APK5UY|nj1_e'
    'h9dAthkHJ1)9ieXlL93jLKsb{^E1-`Rxz+6GCp6kt}?A%=O!LO(z8s(m*2U#b^g$ZX*u`zyka%Ex3sN{YBRApzjO0I;=tPQeNQ&;'
    '<&<AN$NIG-mWL2^XSr7P&fw?yP4&A_v&Hbs1`2@Q`PUD%rrkkuDf6E*3lM>u!_9X2EE%A-vOaX@d}<af+eSL44i)JRa$7Sq#i=Ly'
    '=F)$*UK_GjSFz=Hx{>UtF_G%mpI@<jh=s=WrpKe@RjI85badxEIBp^wYl<_bCj?z?Bin1Ob93LVmSw_=lf7P}fjo;x3Bewasj|B@'
    '8mA5_#=GiI$L}0xd~CqYX*JHaH;eD`F70(E({rnI@N<N{1X>z!ol7<=uRg{yc6&9!KNH^ea&$Ah-Jx13Nc8;9YbH7#{?DhZ{75+{'
    'O$}jou$l@_JK-cVuV0NgH<@|ThrGOjI(mi+pT<<qK2w3okz-Suu*c%NIiz8pUpgm_dAsTC>AaUeAD8uWQ{|Yy^mrZ9nRY^a$2rJK'
    'm&Z1!zJq}B0~wyt&}>bI3sP3gCBUwgcRG0LBM6Hu2?yWwCjKi%K<i`HyQd#6*%(aaX&&wukc0nlQyf5=z&isJw5K_?BgSLR2XxSS'
    '4!f9yd-;0sekl5DtQ5=VwyMS(@-0Cs#Lea{ifU9oKR$IA%}fWptK)S2y6jHiTD$O#=DRL|$RrIGg$=v3bXS2;QgT-NJMrhr_A+a)'
    '&h1iKRse^%%s=}R2fdkkTLbF9ID?=xhh-p`Jm_fX)`vJQ%#oM3Zx%-TJUrp&vTYS5R9Q9pqgI4;M^!rtEpPj3-D-vYtbL*^rTg}4'
    'la*S!GW^X=JKk-Ob2p=3Q9OVpq|&w0dJjL@^#KnD*?Kws$m^-XVMVJWAhf-x39aWDIn+OuL3`bM7&S4TF6>F!KWv(>&HSfV-g(#t'
    '=?VkjeIqB0x=HuH&3yT6kH(0rY+p~JQm!)J=5b$nXb)?;Sb`&Tm}c<f$d<HW)H12n`cz(aS|2}m_sTCG6ysnG;PU`pvdV4;J*;8*'
    '#@CLe@zq7`w+_i~I6wy-Dwo>#GNp_24p{RbMly=n1ddp#^IA{9v{?b!w}zdXKRk)&h7@HO@8^3^$Uj$XbZY~**W34i1#+VG_Iv_6'
    ';Dk#+(XFr&bjvyd{Fp0zhj>K$_2W!tCA4u3uacUNT=J)LMD)!AGAqm*k1G&($?+04w9UV-!a}v8_)q+RjvyW;8E90dH~#noHfI_C'
    'thOBy=f17YI#Z1dqlv}9DRn;h&wr<24Ep>MdvjsspWX!;r`|m%oH}H#C&xurDeve8x-<hG@~+u%g#jn6eG&LfemB3?M-&HQgDva@'
    '(te|bAiRD&t=rOwUH#Z8?oc^a7~0XnK~A@m8dSe^ddmRr`}v&qQSW{iSZA&9?#XOBxAmKSH_HcsqY^9Zwbv7-GunQ;@88_1o$*BP'
    'FXgU9NoY=hb;{MN9kgBDJ#i++bZ$?o2SP4y9|veTsZuw&|F|{g^I(90Tz+zv>U>_zX8ibG-j0gZ?dKyfsvA-a9d+(~3{6oyMe%dp'
    '-s*1HLEqp8ca!mOq><~eQin&A0`jU-S*+07&B*dN{l?pUMIKT^P@>W95@>)wyzZNQ>9GQ;$meX<hhkA%99AW#!z>`YTkcp95Teai'
    'h&K)vv$alTH?=c%vTIt^kLOM`HIi&xOu8^vHl%h@(7(CfbbFs+FSS-0A!)@s$?B@wc@kW8CWcQ4X-x;+!(xpYRMv3OjRmOvYtO)1'
    'PWi6_)>0RZ^=HLRDw`s6uue=~fAjf=)M2N`;WiuGx~EIi=c`uos^{FcMb8Cgme|N5Al28}tab-pcwV@twe4$}VSm92Wd1>%Ayt(d'
    '>Pn!pv?zu@y#_L?u(RX4vv7CTh&y(92WUV8yM8TZV!9FQjU$Jb9cUyZ+b^05DPli$zMj3flO~aMF77E|%I<+G_$aUR{P@!`AwXm%'
    'met64IrVDMZgsr8m$lDjqgRaK-uZ-wDf;G-<9KbBov=dOj$Aj{%2YjCERo1zZ}YC0-&(NtmYS5L{Pt#yOQ%SYVdZ^=U3*m7SB`x&'
    'cXp(+d@ZkWql-79#oZjlZ}KcQ0D;KMZmaK123PN(j}1!Fmqdl%4#LZLm3?-{U*37OWj8dN)OYA`gQ#3NlYP8%ouaN3F%o2_AT)%Q'
    '#@Kl^OO+{k{Q9lq@^S2)FN1Az8WQOTdDL>AQP?!U#xLOKi@h8;<*LCg*yrI9EPzz*#*++)^4&3o?DylCRj$_u=E^rltteZ17gZjc'
    '+H2{yjH>!nmS&Wca((~$PE~xqVx~WS^3_@cZBXn@#+x;~KNMNEU3$UL=^c=bLVNYeOgeSbFE%)|?sfZobf_a#V8rHdr?jK`acBeP'
    'n`L)Ze=~+c;y=DbjJl0ce5;D1&K^A|Rphuqj~-^Zm8jS50dpz$Srp65QQn2G*l8faw?m71MMP*_s?z0U-Cm)<&$lD08G%XlxA)cS'
    'WeceNRZh(9^Elu0NoyQWTG-Au3}GTaL)JHMmb@H|&X;Mo11Gcfle#sglS&h{%EZ*(Bp}(yFmU{CRr!GZ;mPJ?-y5k)B_3^EJL=u6'
    'VJRf<Y?qB7&PytNpQ2ZQ^n^?07;Sn|s(aIQ-<EFSO1P<q>iT%D4+(J9@iwd1>~jA3?{EYjK=L}C|NYeyj;ywOl`M<;C)l0z!DSie'
    '&(7`*zc~v5Uay713mtHL6^|l{*O~^wK>`+hl&J7F?Q%I+e*5UJ>lY|0=~`%Qqd?jMez%V?t@b0zP>qu+jj;wO!DrS>r)kA$G|L7x'
    'ZIvtBn_+1xjip6Y2$M>h<to$-UVGd4=hxQF(j13$xVk82i%OSLDodn4r_-ExkIIMFwzV7LCkjeK-PEeNQ6IhMb+NaETC|RQZs+UW'
    '(eiLI5FtzGkAHl1Uno7lH>X6Dg-<l$JF&Q_l#SN=gYT;(`-eVm7ZcL@Y*8ot=CITlaY<Zic=+k{V4LNvok$;loDHxK?g8QI`oojh'
    'RAsx9;XpU>@24&KGwlXU`f=l3&O&rZxy|p~q9#cdoxQ5~bFlHt%ivi{tD9kxp4ykCzC5-%3iBv!r)2rU|9H<fnYIyY9o{~dHO#67'
    'QWbCfKm_Dn4MkR4fUO;lM6x>FTIT>Y;)x?dRlU~0sms8=P$b_L$x6>(%~l0S%%J)|e?-RU<BYd}`n8mql9_HDW8<<_XFcuk04{E='
    'p$jjUL~ZhIe}l2hrau2j5@d4`<horf1O0hxcPwrDF)GF-c>nX2Q2ffXn*^Ae51!0wUJRPBI};YWyt}$Cbn0OjWP3}2)ch_t-HEBk'
    'JAYH(4|>N#X)z7=Ife8)qJ~7HOQ<b=IJGq0bv~7yxSzC`)fYDQw6@%it;c}91)YBJf^9rr=03WA0bj6?+!hlGk3b>b`#pA&7_z$!'
    ')&o+YCrP{6b;w`eZR_tdGTOj3^92Hp{UR}SJb}NnB{|4JCIj{6OC1U2MYYDX)^5)eYdq@EoF$+CnmDhhvY7<$C*h>Zv@^E3`pwbP'
    '!^QrN+m%-0IqvEhnM04co#u88SGM0?y0Q{tpT9TAntE8?T<Cnx>6qGOTH{^aTk&>#7pn|VBdXr>^Kxt7A5L8jXcc`;me1i;9>36S'
    'F`Iw&9`Qv9wRiVuH$A8n(Phkgmw5~-cJDchO7psh5Dpk(V<5O{f2Z}YIXp_#!3vV!^DRmY*D6VY<}8xOw-s}b{)Q_S7P}Ci#Pm=s'
    'wM4}DwNr$MBS7u`vr<ihg>>r*zTsEHOH}lgTJt#QYuhBA^FN$A)|5%N9NzAKZ(4Kf@D{JFeEiu$Z#8Jq!?*iOp7DHVoDYFe>nx5j'
    'eL)XblBhGJ#nF#Fjn2#WKHfI5J2DCRpN?sKO**&vI-IMg5tP^+=lJ=WG<G`$LbY6z_8L^l%G>K3r7nw=+OSIdwKxgV*Yx)Ou9{7M'
    '7!mT3?peex!veAR&0~wLu?xNJkp<J+_YMwrQGwx8SJ}54P@_ecKAT4;^B^g6v_m?(Xy9Y{9v27KIbQaIwlf@9$j)Zai+bbsLAUgq'
    '>uuXf8|2;%LqAra{h3)g43HmV!0Mq59hM(g%)DGar%V@x2JL;<W6b`n)Ryjy*>r87P^@T8X<p;+^jlkD|2~&o`;Q3i%)0Q?SW$yk'
    'kW@D*6HOG0!urmpB%N1fja1rfVhCpQ-V{2wI}X1aK;X7T2f$taeJ;O-cUmN;*`ELD2`r<d_+ihj6-(6q3*+lM{0bJQzjh^~{-8t8'
    '^_h!3>q0D&xi)Pk{LzT!8_m{3=FH5dmLy&Tu5ZlPwkn-wKmIJkh98S==Hh+_mUhg6m<+>yZr_>k!LGlHd~c%eMtL~bMLh9tpf+Pq'
    '3`;urFxKYmq*s)1r+PJDINM>1rUL)`D)t&_U9h5>V+m_)n_P)JKp|~F#O}g<u6p@VI*;a*2p;+y_`ET$SP!MDFHh9-yhOZunWj!y'
    'yj79gEpOe9i65_w1vN>Y+O_Q4doEq*_6%kLU|9Yp%nss|x@W{Jtn3C`+r9Mm4fB4U56jv9du=!BnG?3Z42uOM37$(&A|sIKr;j?!'
    'HA<?I@TNPdHYV-fM7!U;s3i6OKw4PsC#Jlb%)!~nO1Qo*O*9qK%vQd2HyiCmeWJ_wM(<92e>V4#nLNdQKGW=K(*W9}E@DRn5sytR'
    'hc~CUPqYcYj35=TtkjrqxU7I$G9b=5hM1RXmWgpateU3?zL%P5>yidsp<adcu=eA@$EDS`)W{c1FFQ<tzu$v@FscmDnYHUbA<Oq#'
    'yfA2jYNY{X=^z{VB-<!&o`Q$_0$Go<g|{w&O_VY{lCRdbzxsA)ax!)n@-r^&qD2o_fdT?`PH4js$X2>sk5AZC-o7TaLqltD2y{BU'
    'h`;XO)hOL;62G?6@DArQ_Y2MK3k)y2Kc3+91|h(S+AKWoWkS2R&F^bWVZ+sE6F}(}(buR5r9-n0Oe+|&neR8=z>K@Z@u>!6dYBsQ'
    '_yS;ueK=gh;6Gg(l#a?H8=h_E@NImnjP4O8c8B$C_hrs!EvF+ukk&Dh-SzNoUjbWIM-}b8?(Ld2sJrTVUs3;-Z(DCE@>39c!ato2'
    'gOFC#0rO0L!0papz4(A;f+qNibVG;IvL%#tchvJj9y=(JqJOzGb_a)!wpS1R{>C=C_V(qyUKU}(R?x$LdlDP^G0%55mt#%qMWeFv'
    'StUGI!ATaY^uQ4cIacQ+0bA{oEw<0Dnl5NduyE0NRqqvT*90=@5cojcok2wQ?EL(o=a>A84=YP&D-vxIZu0y(<34*wj!vx(JAzsg'
    '_1sl4Z?#fWg46hcv8D-47&Tk-3Hb`yPy17P_vBK?eGpkb`|0?V{pa&$q(fnkKyXCb`3%|5c4gFkjGD)!l-+tHl|^zW9zt$0bljyX'
    'YTo1JDy(p!QE=EPdD?Wj8EE)pDmfDNPv;0dqZ$63raD0%XnD~}PSuCO?O*AxQ&&53+7p;;GFE9Y@5jx@soD$?uuH7zqQMUao6=gP'
    'cKb22IKXsR-v9OsZ}-=DIr+lYw>>XaD7EWO=37kZe6%2a62a|Z%|d8D|LCgK4g01cot@X#N)l(O*seS#o7wQ*YOS~pdsrd3{NurW'
    '5&M=9eADt3WcCu6Qe(kcZmvy3Bn)>?|Jr;WK;EyBZ@pEHU&bn=-<&!E&3*6Vc^+6A?dJ3OR>(?&!|J;H=iBV<cXww`CH`!>i6;u+'
    'vhN1P<$rPMLBTEBx;uSD?x$1t!RVJ!h~&b<6hzD1H!)~AKo^(gCxAoowm{RzIQ;32ro(_)naybtqVPx`3C-j6(&~-7gg~s&6V;L_'
    '7|A;mMBmRia0S~{5u+D*R-Gy|$6M0cAHJu&%nXmMw}@o-A1-;!N8&8E7PsK6zxCMA-Q=T9!SN$vP?<JiZjl~GdN;T}I~@U&F=2Ll'
    'E+ZY_rYyx-PwuEGr~ib7jjTIWNB{h}6kOe5!?&b(RI@FOxs#JT@xJ|sJLQK6w5H-I;V%0J0cdT&a=P^<zPVr4(~Bg~_3IQWLp6lD'
    'o?)j3S=w6}|MvZpS$nxO=4L5r?Hm;_p~-05)2AC@QD0Ri&6NH&UWi4<_Q<}az~GZyma{=vuWnW_J9!5^nXuRt_hz82gF$ci^R;CC'
    'ibc=rHR+=+zgz2Of+mo#+ufi)3Kq{EQ>JFO2>qU>bq<*<6J$TX1kGC%o{|cbZQ3;$tZ=YOFrDq<{g-Kex>t~A{l<w#9+%^BHLR0^'
    '^sb`U$MKHriGADnB+&ce?op^Y2w&?n^;brVWHTJLlV0|LzR{Bb15$Xj!E1b3<+1R4zH%sMhiPlMyHwT{V2^DPd%Z*M)GZ$QdVRBL'
    'PeN+K%!0E4#J7V}k&5n`i%YZj3fxXK(wWo4D&G<z9^G@{Q~cqbUFvPEyZ*h`$9lfs)UEBx&giHij)nCKH<D8MG;4JK(7M=BNa77I'
    '>#Y18_#X4+tm<kdw2<TJpoDwBneDBs_3Hzs3-Se2Ydg|v-u#5AP{g`q_le}xmBiNGiptm3$!=6%Rd-O=|9Ya)y!E)27VXc>isIGi'
    '(r6Ba`Qn(Rk<-I9_1DiI?5edD%+f-O*ZbgcA8ne)=*oANTO!JObk|ADxc-2*R@4WfEM&wsMYoH};=MHpYh2otu>(i+hif2zbzi0K'
    'FYlb99-eOU?)9rgC0!qg!&<fUtqyc%vDZ1M2rv8shdBm#K0X!e!LdqFBklJjyYxCW4;j}tXC%sVu6FGQt<m_$8$DW|zB2s^ezipm'
    '*XQ$i^=)y}4u@AR^~SB?>z{1E%s(ER3PR_(>K#92praQZhMIIcu2WM=w|nUd1h3{wv9Hqa`-1CJ_;|kWo;WGuQlQVWvw7SP<!|n='
    'A{I-Bd+U_%7tBg7KVpFs(0Qf)-AC9!1qPmUQOa&{@_NMX>L;(Pa`@qrQaBv@lE>z4_aVdn;n7ym*XOB>Iesm6>NGMlrXu;*>yA^Q'
    'U(`vw+HdpXt^JpnOGE1<i7Yrqty$MSvPNu{e*4EOHcf&%Wrfx0OvSHgr4cNrH~j)xjZJ-2Et+0u{Vw%4eCHHQDu^Q9nu~iirA9_9'
    'mj2MT*;%Oox%X@q@maO?>yIzVL;f1eVD_p~k1lf1b>+&B{E)OdfaW?|f3WKGgzCq!NoR4v#TZ_Z{TXn7GgL>S9*9J!G7&+a6Q7;Q'
    'ZtchKOqstPh;Gu6qQQHL7fyF@a-#4lu0`+EO@sM}Gu*-5=y1=9R$OsjJ#XAI4|~+1K@jscNs^pfH(q}jlaVy}-@Sb^h?<=?TsLVB'
    'TnlArMs%QVHzLb0(Xes~?l+G&9BezNx2|5EeN~^$LcTt0U*9xy*Xx}7OqOn8J88Vy7v*2x8Pn4!zEJXhyNGwmM0GX#PA-ad4I0w-'
    '!FH5QS60iZtUKP^%-dm?pIfS8A5VkWpaPd=UMBS|mVOhI8OkoLe*8{87EMl%fH>N%*Fq2K{2|DW$iFzvNOx<$IDVoLwbVbwi*Ca9'
    'T{2>F6g=GZasoSz%YCg6y{{pP+NY5)s22V3<hy|pgdmO@RJU#_f>hjqqqQDfQ$;&Gt-co>7cj6b;vK#pG^CO@_%@npw`d&Qr+dt+'
    '*FO;EqT6**Ec==l6u&vygsTEyQw0%G>;fm2yjifKz-$|7&g7Pd7c+TO+U47WX#$pvh=*b6fWz>*XVW2=bf6M%FAjVDq+qZIw(rER'
    '?|#$&W9mzEm1Tn_uZ3SQfMWt8hyyMl$fly;0%jtJinsuZs37XK&-pTm?_9t+Dm-0X)m`0>dcvaZcs_1h$*IGf_nG|i1RnRJ^X!U`'
    'KO9V-&OMrghNJT(*PAP<wd^5Dv8UI(C4e~y?$yu27^yW_*hjy7>{{i?wlwYT^*<SAZ#K(*9jMnyZgTPnRdX(<9$Bt<?R35SGEo_3'
    'p#xAK5#v`E7|H(QlpJ@NsNC<(I=!#!o$*g^61LM^)x>URv2P!ibGJ7By!as`6!K;LL|Y!;x(((*Z_eHNo69-4dy}g1PQG*8y+27y'
    'uhv?sQg)7;<2XRa%<SifX@V=Iqd1VGF<iaD;GNys&DO1k(%HVn9(mmNn~Af_HR+M6m&w;}C1oX^H>eYAkKa5!!GX=!9+{QR9<7V{'
    '<KI1l8<g)q!d7qbc$!M|Y-%u_?s#lf^D7tSFB<$h&v=Qz)I&Ty;=R#zdV2~j<5ab}!*I|$2KT!?x>c#9UEFW_uZ{>lgm+y(w8`(?'
    'pfrY_5ZUU1a}N$_?7wsO+FB_KQUUUEyvW(2{R!!ko7?Nm9JEm2d0>~Yyky(KkiOg~y;u49jjF)-t#-Ya5IDEmp{rEF_m?w(zh~t`'
    '%yL0zPAM9ZIDVR{@N-r*-1kY@a{I|j{i9s=VO>Qq{A=4Eb_x`S+VtnAJr`51OLJ9&WN+-apw8l@vTY1|w6TT1rqkY-actdbptpWk'
    'H(fzhQE*%xdhyVRN+-o@JpAhu3FW6lxYhdZA3w8u@)O*T;x=HM8pqKyo9-ASl=8MzG+OSWecGUo2s+3%Qujdvn1r=?ys7ix<No%Z'
    'g3yje`kNS;TebXkt~ma?&!^NdkN2_q>{n{SWg=WB6SiA?Y9{&@g1aCQzZ-zo5a-jZ&*ew@YMlm?%261jD7MvQYM?wA{~Ud0k&*VV'
    'r4#kz)oCefl~rn4Zg8LTIM_s4W4etei9UT^SKKC?aOU1D@sq?{45=Y=uVJN{#MY?Gq+c%&a=7Z9(`cUaO~5fXIQzrj#rH6OhEiYi'
    '827b{?M_`a_s^^NA-BghiuLvI;JfU_)~jU3zy9bGH-pnzfRpRe3FD;@aM1NLJ69r1<m{dI)0@Y7x6Xtob3Lbeu)46u!uCAac8{zz'
    'c%b=(epBeSiWYZ%499uw)o}z=2CWg4AEUxtT+;%TN&D~TT_m8XbSJ;KF!}`Mw@>c3GBm?>eXRO&u<e|-Erx5G&#w8(=)Ke%B;0XG'
    'ZuZ_G>9SKs9B#Ewm)?jLm8__#`+D`VC}~u$|L#+>2Hk4fp69jwrgLBdVc!NY^LR7IwpKab>ZH9aO&0P3X}ozPJ8X|-dSVcjV*DNs'
    'veK^d`5IWe7+9!Dho{|NCjHfE^Y5mzAHN+ehP9W}jm%4VRXYbgbPW#9NiY=o9ysy`*plMdG^y4LiV3&&jZdI+UtYiL!-kBkQS)LI'
    '%n7W!|L&ujVEDR!9JT*)Un3Ytc_2`5dp64DyDhD4H2H&HXa4ld{5Cs0NBjL^Ke%YvXELwsM*F4SzFsL7!2C{yT~DZAy`-hOgL`0b'
    'r}uUuXiI~W$P&;@S`|TOp`(AQgeH(`0i<5u$=vdGi_aatBRpZo!mZh;t~-bEV0kdIY0(v*O6%tn^Q(<_%&3<3#2uhrsnrMoK9q9N'
    'KJ>Y>X92r0-85ojS~7)}?92e72K4Oj{xt4Y&2iAH9;L_e`8+MEbZgl?PJev{{WE|{3jgV|yI|6<$cjDD#2qKn24r+^>i4=F=`;Sc'
    '-gd<_1DgHvDArf_oU6rhZ~h&h9`#6r-}W*e_2om8`t9wwSMf{i?2&Dm2LN0M?<V497HcAn?@8x&aIZPByIXU^M91ST?9_|;9H5Un'
    'aEsG-ZDA@UcTUC^bmBUT`kPaJ^|MNSZ8i9&;rh=KA4&c8V;<`K?ETrfIMK&9K{QDjB-<`FM5hDxdwt!l?dfPeG!0?So$G^ZC7w84'
    '@BXKe;_LfYpX68Yvvq^jRh#Je`7x_OUuee*Ox%>@L@7mBBCL@_pWh#2M95<QbwA8_p~`Dej2y=~C$D*CB$tjsmA-Eu`fuLJH<-IK'
    '{?n+`Hs8%!(d1B6)F7Xn{@8jpaE1*o7p@y4QV4qaUFq`owL7O-Xb#pyHi6d9H5GKKFj-zBa_3|>etsh`fs4oTiH#N97R)FdqAfUF'
    'Jl|GhU!-+$j*nIuPDV0zlOT#U{oB>rl$mR9=UU3niu(w3%NX<Y_cvy<X#Lwya8I=XA+<tI0~_CRZ<}#g9>e`)%Upq0j&&braos{{'
    '_e8H<+NWW1*xwtBUb%kQ0oya?pV$2KEE8%OU9%DxYQOo|4Nmu0-S{JxLE}8!4zDXTE`7g!;Vn8#wz0q|B)G1+LMJg+?E$bLPUYg!'
    'I+B-1MFh`oohyg#>e=ih6XTxhr^mnfi|LhJyOU|S7~i6q+D~;-|5I4icYPC@o2%C{ZeFu{HmDB#DI;0f!ftP{N4H*)Rp70yUU{mk'
    'a*({`aqW2O{`ReeK0tLk@te-IV32YA#Hnb&>UD#dTv5){OQ<ZD2m7+UTI<>i(G6y+bp&Hfh-HB1lELj*I;YEROOQvW+VC>_^+hK3'
    '5|uGhwmZ#Ubuz-CfuecV=tx)dMr^QUs%??UBAK5TuZ%^TZbP2u)1y?G5r4p)CyiCzVu79uR)Fx)=cYfL?5-zmkI`#Ax8;abY%^W$'
    't6SfT?l852T_3s-dTr=l9f{uC0DdV@D|(p(j0Q1B7x!uT;EIcpG~TZET=)DZ8h&%**FnZel{<h&Mpb`QiM4^!!R}I0D9`7P6>QKU'
    '8d5jtY1(4z)s9us1}hN<ti%ZSTXDS`j^___Ol*)-y?^w7ywAtfiqA=$&21H#oo%k;5?S>ZRM2d->_8n6m}E|4LFshrzyZW}d$dt9'
    '`Wz-!P>(w>VsKb38-tGc-NE=ddj94acy-O3AW6!b7hxxMTle;J5_VUr-4)iMz0s^Cjs4~6Pxmi?j_Q(!L)Exwd)J=1%O(#V%hw~('
    '&1Pl%<XVT<zxl$)<_`116I6GgZ|d_^YvS8|{IgGHh5sGQ*w8Lt=e_!QkbdsTG3``Nt5sv6g%|Ko=e=xj!Ay)wn;WceM$vIbKYs~x'
    '8TnkRxXoEe7WVyXLQe2;^Shqf^NKv`;i)odKHn0N_Z*SGAXER7CmPTs9`D`>r?n4QdQP&+285<P=sM$n`B**e#+E&Q<cmYGR&M7O'
    'mSI%=t=Y4kF#$(1k!Q7wfru{Nh>1U1v)|dzoe;HkeyWs;u|{XgwYuj9jIq{g^zirIqH$Nb$K2&L+M>oSKvsBxvs7E1HhY(zxe?S5'
    '5XrO;EeJXU4ti92?fd=++kUMzIn7&}37QmVewm$8WA-d7zq-8uFWyW8dP{}%4vLhhU#mTCNd<yb!%%v@`dH^YF2Sst?W`<r)`Nh4'
    'zXf$u*51xMIjP>v2T0pA&qID+w$q<)<?ovojeP8{=%PB?en;U@=y*|ogZdG6iEbPjYa~a3aQP`dvV+QHf7#PwSFZv+RS4}=embG8'
    'W^Oqg%#MT&{qVQ3KFxPY8tZ3k{$7im8Nk3|d(5|70^HYi@;D|5hIcz|y?5?f-;#o<LP+N&o~#Om)w7k`tYjC}Zq@e1wsia9FVigi'
    'Lb6}8x#}Ec2QGX3*zZ7thv2liX9u0X%p0*a7=I=qpL1LM5<QaQPU6V~o|}2O@_j{I?<#Gl^wOIe{onb;m9|?NX<Yjln1Oj#U&D!S'
    '!0t?k<Z&e{mOZ2As;6p=Qf647a_PGqMlgQw5ZlsB(yG(Hyw|`O{#)U??)Z!R_=AF+@5lw6e)S{Te80I(E-gC#AbPWR;Ii`8_SS`h'
    'VWU?7O}TqM1?~Ba*F}vSmdRZ${#N1;Z~TGjqDi*9Vx#oiTc;5((<RH3*;zp<>HBs3N+a?Vis2z4<tJO4uXj$7q&THam5D^8AXLR)'
    '-bx)H_+ueX<8!Y;;W&_UVU%a1`p>uB0UcT#!4M8a^+kvAEpgnqUH4^cn@rz_)oG{+=~$NccaNS7`j_i-bP~2hJzm~1_0UO|&zCMM'
    '<L4s2u3tfY^YhDb!5IF=^^RTNz=I)B8JKkKJhM?x$s}{fii5RrL#veBsV~Ze#cH_G_lR@}q2YDxPaXm#m+Cw`BG>j1$5!e;-WTUf'
    'TwmTaH0+IThybD7Yd;O^C|X+IXRW5zDvrl{3@yr1hv=aomzPG$7~d+b)>t2oNZ`yD3WZi`S8?)YfnPts-hGl*u-#F`u8*{DFDKzu'
    'x<%WpJ$6$_jGp?TVVzhN^uC`SeM%y8`Ej2e#u{lwRw3xGSpvb3{1C|w5T(h_-<Rtn;a&4$@o=A3!BRI(`_>_DTjCzvcMp+@4!QXu'
    'KKAtcsRLYPG)2nS_G`Qb^?6+38b{)~?)!_R9P-;m+xY(5Pw;viqim1`fl8;WU-FmXqkK})9o$`3oB4vhL?paqmrMuI-#{&eVA7iz'
    'k*g^5vh^U6YH>U~z4Fz=l1ndK|ML8Nt(V1Y+_gQ_toNkbbz4Gxcp+1xAv=_N$#7YO_9OlaAI>QryA6IXkQKN>j&yb`uB%;)-v>RI'
    ';NcGjsj&a6gSY1O?yNlSU#gEytiJK%4FXzRv$&EK|HNhQS)$_vBEaBSmumzx8am_X2@^zncf_dMnMw~e9)6=+(<okmD*XCR4W~<Z'
    'SU0QL(?^#kxAR8dzsTH6I1(80G!n31((Ts+pt~)}C9T5UUoYf$vc-i9X!f4)$Lhf@C=qoV<oB2L&!-#f2HWhm)ANh)zTN1!j`lKi'
    'Ie`*qO>fmgy;$a@A-xs@DZE3~OR{N-tJfIr)00^xARuF``QcTZ2kE%1RJY`BuEQ&RG_&<Rx7p~#m(hc~c@<u7n)OMm-L2&Mpb#_{'
    'Z|y?IHn;w+#m*ynr-S!veX?=S30fBMehO~|v;Mtw)PHl$XWDEXD(axfvcS47`)WPITYZ!itm9HoErA+0pp9kMj@=X>mW^XdEoA-1'
    'ZBXPA$d0zproGqW_7|G^pkG&;|NJG@$cf2refjrvKcjOXjNc`i*19OwM?TJwXVgPlg_67hPa~!-pQHtJT9PqQebK@CQfrPxCK*@D'
    ';_-1pj*j-LPbPfTz3qnmVF$iW=kI##oxyVdBThHxb*X|eFo#s9%kEy>QNR<7d$pj6KMLi(6W(K?^`4%WU$DKs?|M6o&^q5ApPXG)'
    '=nnB!ao)t*D^wjfEx{f>n}hMUppNh{X-=+evu?iCp=H)!j$T76w8pNynj|KHc3{Ifd%9t7@oDY}5&qRRX2&w8Qk#i+?$ZZO?Z{<X'
    'HNGEVT1~eERtL*OhAEF-8H9voCHewMyY46_fysbrn0LPM3q|PK!R=Z7sb1lfUmU~pDaT>`%~4Q7rioujcBq}rhu7uWtL^~yzlV1b'
    'n8oCkSDA0p)uL)*84|0-Q2RL@*?CKd&4E7wOL)AB0{xdSsQhjPi*L<!m1aAXh3QUhmcF%tp7Oy~2qu*q;)Nrh_mSz-1kDsEsR22y'
    '^9%_^(nT94rR#(I<DiKM1+8-SZ||3U?K{Rv4_RhQwy)Vfc#X{^6WjgADWhrg4}`e~(2x6AR&R>RvAL$8G(!GlBYk22K8rriz-_te'
    '=|?fpK<MY6yqgR26SMB558>j$9eJO+$GiXCB7#lpU-#jdC~)lCg>XjUvfS=2<Du{M27<k~lNFatx(YVOBw=#qHwHA$f4;VWdbMsd'
    '5LzxQd1ALDn}l*Z#66}Qt6I;%LZ^Ax-@PC`97%67-lq4<?s!mu^`~C34hA|Ov%>e<?X#z_yRJNc{_1<zYmo3lfbm!2`ICCM9}H<{'
    '`5knMZ}x_16nL&4W`AJ-^0&af>#R!GB8r7O(zLfxYKV5e-wC32oYy)UL@B@fd8K7rYsp%5aFf25Ml#Nec$f9q>Sy2|MpMvUJete_'
    'jhe-m88Ux~9(}s2^5#*>;#8xKgY>-a%T8xE>*5k?$LpW}L2H&FN(AovF~2#*7AieQt8?S}4KF<vM{097hx`Wi0#9x+?Z`N&j+N_p'
    '1C3kPd)6qP#Gi^fF%Pf$%J+?9Q~UXiIIPq@AhYlVsm1N^k?gZR(K_(9bk9G;Y#}1E&k4AVrc`O(fhz1~MBdG&IJ;wE&aE;1J=^=o'
    ';cRp{u2!iB-GBQO%G>gj^~bZyf+sF{!{I8S5}l8AIu&1SN21_ehv_j>h;(14LKTAtv@=azSb)~20@q93ZylpA`$lf|-@?9f`8OwF'
    'Zb$m6Y2L>*+##$OVwaZYC)uDodF;C+Tigd%=={A97%9zPE06RFpPYrOhZk-xy~Uyvq2aXqnp}tkvR&|}=S6N7O6zy;re1)0sw2(l'
    '9MQ<^?n1YNv3=>vGbAG7IS48FoY>uLeETD5As${rV15(f*)T2*7fvhNmGHe*s{Hy4FMO~l6^{;PV1sTa2ujIZ!7D*9!a$jyQ)f8-'
    'P8X-f5`BLTAMNR~cD;nEU+I#MhW-GklC7|v>hRT@2E<ele!8$*k{10|!vvZ5tQzw(0W=St2lSxW8y`yj>wRAd>3AGpXFZso9qS-F'
    '44aF>f~zeez5t(cR=;=9$&}Pk;>})ud9y#Y!^v>IP%!%~C0VV$;EtZx_NRx0(A2{afUC<WE}i7+6S$A`FC<OARd<2)w2@RPEijLP'
    'V_^9hH+Sr%uLZxleMs+TlCK>1(iM4(SIfb^UoYLc_K=g)Bem*S_dmJyzPH%X)ES=I!0_ErT}`&`ZLX=z_&i&%k-t(7)I0{7T<140'
    '5(uzwIV_dtb+G?N*1cW>+W)ue8^0}dq+co3S4j#r)<#P*g}Ca?xod|hB;Yzusle8ew%vGpN48om)j5AB{La}?-VLvpfHOD1><G0d'
    'OAxpEvh9jZM&%yEE*OeKYwHcS4spcz@(Zk4;V6Wr)#LR!%rPj?@18*}1cQnH^vC+gCshQS4>bV#IIa0Eg6W3D2We$dlYz0`ikmm!'
    'HO-jgn~r^?>&;q88CMT;Ze!Bu;~sRR&*OTk4Jbpy1Wr^S=QpP|irue@f8t_`0|Tx;xFv<0n)thQL&uG06?@UK*yvs_8%3U%Q)%Pa'
    't>oa-Y3mQ_$~Q>f&o7A3oDVy-<tuEQf4HMM<@#$9J>yhvUY<h%<-PD_;hvO^zwatNuRk7sNx_%T=9)DXr9+<dJwQ=AJyJb=se74T'
    'dDg0)dwxBd#aQ|2mW12?QD}V6``UT>yspjCRJ_^8Dp4Zb?_GA6LsYixo_0!J#ED|H@|3q8tDZx`UOd-6JT@iZ#c3vv7Z-Y7Y<~5J'
    'uzJZH;DPSl%6Dyg&D)G$(Hz2U{p#aSUAK8GQm?PWgE7|Rb<Rk|733PP&iRkq?5IUxm50j(k&n{&C9?)Z|Mpc3^KI^v;PlI%uIO!m'
    ')ykcYwn<^&1aiG4e-Nn4bQkSR#qOIutA*dzEGX41-pH<U={+ray1U9tmsXtK=%y3>{Ac+ms3TM6Bo34aEg9l@4fmo;bXjPaJt|kP'
    '(4lC2f;$q}trk><8Ep5+ws;4z*mnORA(Gp!c{13YT$Ue%`2Kru?oPOYCpjMh_`>aauy?D(eWqU5pMnTZpHD~I!oz9|>{z)Su7}SZ'
    '(>~lz@CEH&mg&i1Dh;(#I=|Hoy85G#+ON+5IS1iZ-+Otci?suPYd<FQ{SXuyi$B%7ZR5A+>GHLd9z(O5q6nX4a+w$JQBdA4f=NFP'
    '$;XNeo?g)kZMX55|8$E3<^siRo%*b#eD!4X7<`dSS))cxTgs$~z-2GMu9e(HH~Y(;yGGvv>x1eW#&)ZIHyJmor_X56J_o&*0-3Mt'
    'kN*NfB2?o)>fi32YcS}U=$Knle1F^NaT*s$eay28fLce(;!|^(;$(+FDV413_!-5X9?ZPXz4}Nu_gl5Ut{s1KJ{1dWA8T%Pb`QWs'
    'V&13t*Q!t}gvG{9mu%r}rU0@_6nA0jo;d}xN1ZJzcA&+u+0j?sH*eNz%f7!{*a|ExFF#*}g{g=*CNMxmXThhNE}UeXhWmUuyr56!'
    'yvQc2eSO<#4oq&4^v=|iA`GR>p-aQOjKllO=k>A8Z(55G$F_|#`%ljY=pYH#&d9n@10P|0eqC$&>h*S28-985KH-ifc4}nhz1m6$'
    '8{D<>9_qgsEkNKt=Cn3)g&tLy!)KFY+Q0icrkvhahI}S{mZkk&+R%J|ZSITBXG5=p_M$d7=k~|8I#p&&0#Y;W9Hx~<|Fr<gVon#`'
    'eMI(GJsSXKt9@;Z6TdzKxxD-DXKesx<1;)ItGb0@<(3}p(X`y{@Q40La>$?--5ZDXQ#3Yw=haJ{uBGkqX0<t!i2V(Mzvdqjw6Ug5'
    '|MmsNEg)?C0f04atkGfKet30&Hv>tY9SH+jYz{*YOlROyKjq$B-)zfc>tXLmC=lw;{`!a-)469(=H4a`*<JtNJqk8DJtg?iBCUyL'
    'z{FU_sZPZOW>|Gyh3ZG)u5`E$s|+<C4%w^wz)uGy1zyfvq!Be!V+eV4Mmxil*D8Al$lrV{DdjrRu+w6AK-rAjZd0L_3Y`9@;<P^!'
    'y866p?BRXdtgm`dV`c-hGZXqEOSA52<p9;Um#=nv%4&V~=MirZzdpkbJUJN|A$gY^)NgVd+qzy}p{;t*0uP5a4P1=Xe(k1<p{`6-'
    'aW|G-l5sj4w%zq)3bQKCfvrT%=?Q(F^TqX7mm5EiB*${23f(yjO74tJd#4fgr*SY~-pc^iD1pR6UWu2vd%e#L_>W8;&Px>jexy3x'
    '=?tG$Cmv34e1nh5THXBlqrh>eAyqZ+CFrcI$&vp21GL)0v<P@JFAxT8!^m^;z_Ow@+fqdVy5mYh^`w3KeIE=paK_V-(O+(bSCach'
    '<A;;=q0lJLtKB0$F`uh2gtctS76!e_YVI;#vB`Y0c(f|>(y<=i>9)EdQNxexu%wmr!)KwaO~)=D!iSIs_^o05_%A;pwt`w$;iW}>'
    'Wn~SB!0VDS_f$A5c&A~{lQ+)#`;v`#PGu2{;|Kcgc>;0imup*RHW-%IJZxLGSvBQrI{C!~-L;of6;JnJdd?!`upY^2eZHb6J7W56'
    '3)S%6A}M!}nbjLRT+^_@?75QJ9yONKp%PZr1qN(C<D}c90^@Q4f6w=T>|3kz-B{+Y@@qd6FffZ}R@P|iQ+gh~hL1fU8Rz7(O{&v&'
    'yrK`AEUTPm=<RgQj0eHVCo57y9NA9ETBj%d`lfCEgsoP>q`L+hT(Y`tkU!GICsd{K(MAtj2@aUEmat_lkfC5d6&sbEJ6L`a!fWK^'
    'g?5~GE)+DZ2p#Zr>sG+u9N<bCJL((;TBCD2S{*rOFdS!GU$y}Lx*80cbkDdCs<RO>YcY5x4o1QsJnp@|Vfthq)VoSY8RW_Y^KZF8'
    'IO4zlTia?mz_^sY4(A;&60W!AxlW6gfetjeUv6&YJ#5skN_$RESt`0by#s1S4G<}}TKC5)b)Fkvd6M}FIl~%D{Q6E4TC6Dt>2WY!'
    'R#+lYW2+i{eFaY@$-AkM#lvCNW^<flOzThQPSr@j_88fOUvHlB{N3rBd#jJrUp>FJ_$Vho-R;sHz#Hs$NbN$jDY~sYZ)x&gF1Nd4'
    'QL8B1=70f;(QDF>o^F6j6O4)KPq)2;m*rOH_7X@e@9%WD^<Q0Hyw88UL`TFOvUm@beNyc*ol$8CEH8r)P+P+Cv~O@x16z?s4m6ND'
    'w4*)rlCnlw?>A|$F8^_1<@1=Cb`WPDBuA&wKb!>KNQc)qQrMg_H8QR`r7k({v(Oz3kGSO~=gSoq>ZfkMOCCk_7SzKMnmYY(z%OC@'
    'w1In-$3{+>G%#P<srvoR`6!B`<(F2^#1T;Fas4>QA!>0iE6-Dv=r3omQ`==Y#IV&nYiyg@8=o_i%eEOoZM{Ad!K_+R(0M;MzOPqp'
    'U;fn}q7wZC-tu!S75MJ`$JH7~JY2TW4uFC?YGN24cm~1`VZPe4@=6-aeRB^amP%;14fJLg2C!w+4ybNuC^Pxduf9{r<<g~UD#NJv'
    ')VP5v?;a04+q=57L$N1ny4j$7=(xc#?i>-98cMI{-XK~6^nK&CkFdB(%ErpCb&;m>lh^n?Ul8>5pdit$L*nqZ%}&N5vzWA``iSn7'
    'YKuW%;IW%Iw3-EdpD#Q05AGJ5=M5#vU9YU&qs)A-=nUv)vs*n}>%Tsk{Q1rrnB(oZ_^opNEhoC(1+TUqkMj3;-keZzFuc$I{>`h!'
    'o2MEkgQ@SrL#f2D6>nB98o5(KQL5H1g^TXn`RU`~XpM<=_jv<Zyp^I#H0;ea=~|+d9_L(x#}nKBY4G<VR`0ZCY+x-o7t&>@kL6Su'
    'uov(=kvs2z9|5~&c`-A7dOq%=(uxUYwXgi#xceG0{K}T$Uej9Cz4n0@_OZu<MiUy86FHz$(@)B!tlX&6x6&Ls1+Udbkp`a=K<lWI'
    'BEoMD8~PHue`)ieyRq$7Q|`9`zY~5vTe|Jxb~dF$yD7<WRBE67JwMd1B{*2jdZFF1sAd1@d$Uqww2ySPYmI>N>ZdQ@FE<H~8P-eg'
    '3DpWNGj3%`+#i8Qs9V}(;&$^qV)I;MoryngU|U~q-nP?x*3MmJLdBm4QJtmH`c)mD`J&za?SBXhh-J7jJ)6+y4?14Iv|#O-OVNE6'
    'hkl?#w>LQ^6!lLXZ>n7wlfIx}TL1<^%j6aw8m0N)@wPXiTYQB1o!<ZaCFju0QtZAjgK+Mzk7OtdO{$glrnPyuI)>p*yEyPzQuRK!'
    'X>SC}`1JKUEZ&Xwf~j{N?Tt8#`#0yAD<EMBn}2)ux>-)Wwegp1n?dtX8G#eG{~%`PDeg@Xd2&ck<aGT~?y{w7>4kIJ_-5=o-~=(S'
    '=Mvk4QFjJyHuE9+9_^TC_s65IojcF-X7aAcujQg9lu80#6!W#asR8s2C&sLFtBJb$;$|=5T0IbIF2oX2x^QFR<}A|PinL`c5%^nN'
    '5ADrQclX&#*<Fp^-QtGz9t(Z5maZ#yDb=l!4bZa&pj{4DH!o*}G?d)}y7;>m9}0PW21BG5E~1O_M-tJcN;KL*+W+OD2FSTU>Crui'
    '_@L1Aa8P>9%GN9wZjIvOlhp|>KS#yv_SiIHry^m8QRQ_{;)5(a##0`Rcg8t*o2{%uuSMLN{d7yn>>Q)_V$_V4yy|9f&x_3?U6PRZ'
    'LHd2fbngfZ&jPF&2d$FK1=-^kL>GEr)XV+W(Papm?KI5&{4m{isPzBqcOOwOV=5Fm8)l=7Jlr>*bq#3U9v&u6jOYb`NZ#-5A1zmU'
    '_D{<zSH8S-JI-n!`6dW_xZ4J4ovGEUObhWn>Nn5Ot0k4}e#mf&*;ldK*8a;fX5T4B^dOA{25LSR9XfoYHJ2D7&`{_e7JZ`^92mwu'
    'njJE5`?tz9?=2K#k{>hjx5v;EwMGL8*WlCR7L(omajK2DX%!pU{6$j&YY$xRwJYW0twnlZjtRcKuGR&z8upy=u@Lv|;G6_}*@RtN'
    'n4#4l?r06FS1MLXcIq9rKu=~=<fc(Y+cRehu*m9GsoEn4Hm-WjfwjI=E`y}>B4^YVtxF~Cdg&q*eoSXsl3CX1^>5F#yJ4f$Yj4Qj'
    '5Gdr$?%AjE#u!@V+ZR;pOxpu_Fy^i<e)ajVF=BOi1V4#t-!4s8NrQjpzE39$O2flaLK<)JH$PPF@C%qY^#@p{PX<YAK0W8{wWC~!'
    'O%b-t3uig^dA|2o;9^EK$N#yQ_R_5C;FN1mMErRQx=ri@?g?aTZD;C__uVMsYLWNn<O7IA$7#0g57I@AT}_J}wKZTYa=Avg4ILfs'
    '%$=5`VcD1&=p$7YhjnL-=@t`qb>Q$ZpPh{}8U6Y#Wr>7IDZMchqttciV%y$S7ToOdNDV7yTI%}7y)2-|5}iL(S=jT*EFo8`3jWIR'
    'R<c<v{xr>&IV31wx9jKQ^;drY5XkHvBVyZ-w!k`V9Ni8xW5%>Ml5u+Wdg!l63rE3mbbU17VnJdq7j1e^V!4D3%R6bT?w@qy8aiq2'
    'S?NDN%;+X|4*c{z@03l0Z((^&ZA0@`YooME@MPT`)d$=dEtcJ3L$HKoF!Z9jJlh954(r~q+5vxUL-RNRd)?@auH;|+H&WIPxGNfH'
    'Lb>VM7b*@#y)ciNubR$$Lf-@9QNzBI2fdw3R5(Akm4kD=h@Al1?BwC<en(n^d*I7{7ufXZ&2Mg|$2~p|08+neGYJQo`ti5WO-vi`'
    'VtDJ1ccaH>ueUM>=kZB!p$&Zuc8u8cCLlLy(;r6fb%LXW%rzr|qSZ3^^^fbqnGa45oW;-eUxWZr35TH1h=zwLPQ4zOCz9*l-CG17'
    'g;_1y%emNw;u2^<L_V62TTU(8vNj*}qg@$9{pAmLrr3;ZyA3FkjQi7Y@M*lABG2kq?$!J1Z8qRPP?L_#zC>4BonXXdpVG@0Azmn*'
    '7Spz%IhvF)8O1%M@<Q6Gzy4-@F!P(^rF`+FLMiN*f=%8U1dF=M)i#q6GoS49vUYTyPx|z}BnT4f`MKD=tn__sgNU~$`8C!b-^}nJ'
    'QsC>?=j9)>tEKnw;TV50ROeO<pHB8Fy}f7ZB7)N`FU{TsSbUisTf!ov+6(ZeJ<eJM&_;E!J4K9*9G9~PSQN;c;eY4%Ci8q>?Oy)4'
    '1%d<C-w7IewoIESH?WHSY_R_(S9Ym<7tH<304tcKJK(j_mbk6&;nw(cZSF2`ns_q#IZdy~?>t;iCCB0Nj|dEcL1i+!{6z;NmnL)b'
    'whApw#=6CrmA4o{sN2h5N)`1h_SN-;*eSJpEhi^vVId7xyxdrfQ@-`%zrj9w4Mf4BCgHlZ;3m)Sa<i&Le*lKVN`8UbPhBTiaqr8)'
    'pNu*TkjbAc+t(X<a9y9x_AXh@QD?Ep{U_-jysPlf=g77nf0AM;CBTU?_^I6v&659lPBL$KsC{F)@C_+7mp<P{B&5-}XGI0Nyc!A8'
    'UE-_NipS#Vg-u7?ePS>1pAWi`ub?Uz3&=rIyywmq_Pzlea*OF#sFK#fdS++;wFc@@Lgk}2*4@u2gmQ7Lad&<xJalF+A48^NZ)c@_'
    'GAVw~_tn_)lU*O3H94lCzD9U}wEn~ybM0~^`8KLO=h4NLKI`_;3MxF#z)ABu14qM5wGV@uo?VtiL?pPmxLnrY;P~5P*e^N?$Rl6>'
    'QS<wQ$8P#U>2_@%KH{%>KkgR$$*KySsLdEz<~{HltjoZCBYsL6n5<iDU^yH#P5g1o25R(c5dCn+x;CResQJg?S$kB-R8>t%-z~=c'
    '73!RiO+}w+d0v8MaBsdbgVtYidzC7)O#2#4RCb5knEO1H?s^6#o?Bt$AFsYmmrL?|y!)QJd)w)#q~Z+mC}!mRdfzZCxj@6}^Laef'
    'qUtGd!?zc&S{RB>`7A})Q?&TlF)kmTJ*n-whpqOn?++bMp|JsX+j8G~kb}jstv|>1(MI2bFbIqC7;U%d7~a2IZGL%f16;E6*R9iX'
    'CVB_=FsLq{==A%SM0aEV!ySLTZ`z~F&FxUSs^IXLq8qII*uCb=b6MJQk;acJi5zLsQL<j-d5Cr~$8RYC<u?uB@7;=BJ*5R)DO(iq'
    '9$BX~{qx~%{WgRYiGYLD3~6u5IVDgp<{K4laQSli7Zua%U8(N2Z5H9gF6E=%AIx=T7fB$8#24-%J-<&J$D^LegEj2O*Xhls)*!~i'
    'HI?{Yce5{@s%t$m#ZkqVhO}c2@aSbKbvh^cUI85iquhF!NA1XL&z+8mK4r;2`F3SbM8@K59e;B(zIHhZc6}R`7SLJ!Fmry79>`D}'
    '-BRAJR+%L_I{L_}cnvaPnwV!^FaPBUCA3a&%uyi_9GX?@I;cF<dPHmS@1856@qiZhX=1@obfuSK-raAfTYL;uZsdCai9M(l<1_a#'
    'f$K*hd!5V4a}A(pxo3B-?_tTZe9u=f3hn`u6|<@Ta2){HVFt6+vm#WAX)+L^4&329KN!=im#vGh-VSgpTYa?l`sL?2E*%Ykn7Riw'
    'JGffyPi<@p@vu8~Q+9an9g}~1L(%!_@N{Nr>3r<erebL@svE0_=&nb?rC;r6pYqP%IHB|2EuS;U8R*2kd<VFqgPup*&M4T0hx`O3'
    '%@K6>iGOon0OUIR{y-t9{Dm*ve)G``rQXZAkby<3b?SbtqH>8ahfb}zd!7<Ilg2~0hAFg+ijA*PgSb<diDa`bMctS7dvB-wlA<>O'
    '?DeN<4SqDslYUq^FjgUk%|RcF<tJFON?(HIAN*mEs_q_cIkB~EEIq!@K2DXmJPI$Jomy7Ku=M)%V;gf0X4@@m7xnfUB1H4t)x<XW'
    'vZ0n}tjg=fKAG|9(+3yZPP4S#i)C+`T59|$xsczM&a79-^eay+6mWE(7(bs__3ECQBV#3C+}znu%&s#5kI8FwKjaB9U6&Z(G7p9o'
    'n)ohjzUg(RgfOqS6o)VetN|}Xepclkhvi_j!8fIE{nw9ODvOUn7~rg)Jtl8-Nq=@8kB->hYYuL7BV#X%)hHcS>THmF=67Y^h9Li{'
    '&hqcWpGB!wl=PU!izs%uosawf_IC6$^K>0XJI3TDc&%4GRDf2t9rL}oh_%Pz$Tq4F9hU@k53rPvsZAM3clBYrRdjN0ej9L)rL}e|'
    'wc7StE1!Pnw>C4HO^nS?6IHQm4B5@qCKv04;Tm7<wooiIucON5@@lQ8gZpbjEVg;I(lk{XDdN+;M_l3@H2T<de!4Xz_1}HX`2nJO'
    '${?EvVyjXJA4MvxeeFT)DrBQ48H4`p*z6#}(|eMmPBAYr_qo7yJgKVP^Xd!lk!EL}PC&=*bov6+_@{@^FYTYs*sT3*f^!MV$<wsE'
    '0tm?65ZuBb2hv5&5=l}ju-bE)USdPY@)ZZ+$2KE^aoXMTu#mi&A7de+{d{-^->*+IVQF=!#(@GQsQDOOj7@6gR}l35c(43v+fuw+'
    'b+4~2^l7xjg4mMQZ6f#n2)zOok4d|8C{L!!wqzfOUmbBYOcM6Q%^Ii4q~2hYK+DGWsz49<@d0l(2VcHAg+4QX(!T9W2j^YyAn)U6'
    '_*iPfKx%X%YF$#sl_=Of$As7(|McdN)%#|Ty3szi*->TVy{YVG)4V<0gxzbp&AY?$US6l`N&VRzjD``$R8R6XGN!lcwM?H+JOH>|'
    '{DPXB8h>opfBh^DMI}>Rr%O0B)8-4SzVGXW1weo(QkkMVh!(sG=($`RgR_hHfSWh_@EEMv(@)>bMtyW=m;<u|PmkshX<@&73|~=u'
    'Gf0ifvBEKKKs~{|Tgwq_Ak$P`m}$GFmidow)C-ClE;e^xj3w$1Z(Tok?JGf+)0OB)Y}b~&i*!QV-@HGuGX}%*6+ZN1{Atk_1H&sl'
    '?pyYj9b+f8u<H3LPmiSu1V_qdT&EBS?>4_$SZy9l;>ZEF^Yyhd9X94XwwF`-SLc$U!Zx5OjdYdZ#WX6hn`rIM`7}~>VwrXo<iCzE'
    '@_(ZL`CtFz?ff{|{m=jYpZ`b5wRO=Mo>m+-RvD=xQuq49PW;Y|mfXhPn0Ngu;np7KM(x($tmskJUbij-DFENTi`~KGRXW}~_GY`F'
    'CxbUi{t7s2c1icm{v;OLc8+(^Xb+>tgsHd9Sr1t<>-Or8r%#d>k`6yK%a)Yg&O5)GJ#>7A;}RcTlh?k|RG-{<x(!OykI)28xmH#0'
    '_Xl1@!8xyf=NR5ZVfjKM++lt{P16*_i~9K06RR;a317!v16(-O+H>2G;f<6dNtPGI#6wTkAvAsqbKR8XT0^#O6_+>rVjZGUl2>wz'
    '15*RPwFcGR`4-o}OMwJHJ1|8_t5hQ;{yMS(bgc$WD2t8YWL)KTUIlNp^eZq3=kk0OQWT^-$R`Qa=-xG7Zms2_`^Tm#jyXru3Z4!G'
    's0Dp=!1@$pt^9?-GYsT!ERm@YV)}o{A5JUT^4eMa2o04@<M~F_WIx}F(v3gPt4FgL)$wD4D8Ka1i+k>ll+Zy(a`x440yR&PFA8^b'
    '>NJ|Q7V-k^Xs`aXLI>W6HnpE%r!LET(VWr)(_&n(+-DbmeE41srvZ6V&JEzuswci&hq-uokR>)nHJG}9K0r*=0diVq+I74-sf{n5'
    'y|m2+_!ZC{ecI8hmh7FO>xnG2l**GU&--k1wQ0)h$IVLtaW`9RW=t~xR#omYJ7m~x(SegcS(k@Ie`WpUlskjH?Ws1Se*yw!S%vI*'
    'lxwfI>PKk~CbfR=Pbm+Yua(e}_y-8I`qNwxhnTHVV*ZI*wqPA^PV*2l&KA+Awd@6e`8xcm&)z>{O5-*|9ugF75!!k+$-Hr#hHBg3'
    'CbDzfL{~oS4p_Cg&99$5QNpMxx380nSHQm)Q6ZRTYP$i3Wz1RckJ!k&b$<oOWyYhtR~BXixjq@=j}=K`sbH6J$k~Z&o^JOqOh0`J'
    '8$0`4O|++aoyDSuA}b&NJ7eTS+|(w{2QF4R*YRqm`_D*21C8e&UbZUSP6^Z+uXCX<*WmUoZ>mB`W{+`~ozJTmmBNyA?37{i?_*B)'
    'C+lyQDX%AJ6W=52DDbYe`|OtxE}YEWMsxC1u{SSrUNPT(G>z6zdP6XIR{D-^Q`A;S;_`PYK9wQX@>`W;X}1Jt78JV!zFilkBT}zv'
    'r+})p_P>j?uO`OK#wE4ZA3hKx62jgUD3gkqlSghz@6p<E+8}q%i9Ye#d1yw_11KCrnr+kht*Za2gRRXskYc<~llCec{ubt{2EFqB'
    'Qy^>P&5xRoPq*3JH;kqrf_f*8DULNx(L_b$aJB`H&4E4ZzlW_3C=g=TH87uQtUKaV0-v?_X&OPvzX7+=Y_8Ym)vh%A`laf7N_t!q'
    'q1@(h`|!aUM{e>r@$l?e?NVq5GhYaZb;?ufPrdf5yux&Le{qesH-Xj5ujk)+D8sk!Yjxa>!C-W16#SG|lY?+x!^Ss9`xmM`5zD>2'
    'Nl#A=&o}^*L6pNu$wrV#d0)%!UW|}k=9xUT3DtGn-7nEB)OT7xwk@$eiNRaazSn4%%~NJJ%T`pt$KO#?1zdtQ4ORc*zzlHH>0?eC'
    'SN|I@!`-=wnAbnlmMVj6(L23=i6%1SiBJQMg}ktC7@tH2Z$3YFR0J$inJuxatn5nzfdU7><6z@rN4iv$px$)p(CDn}Ie1)f5BAU@'
    'x(!zHo4*E7{*cjL9~goSTBy^Y5!O?@bQ6)acfMnaeri3IS4OXzzQ@S58nJ-_kNQsQ?nbcG3S51G`^Lq`kIQ$>#PjRr_kG1rzd;^G'
    '`a$7N%7^VE-JO;!UnHuu5ct`)52Mtkvb+TXUtU-u$~T%NE$DUVw{6$LRe>eq5!BkQZgMf&xr3j8sOWQBxVZcJUfDIzoyYn)C%5;f'
    'pVS`Zm<}tob;4PjsA##D(rt&A``fdm=4UhVfl|AmKIcieZMy<Es#Ju%4E&4}Y^gGTE%`suuDKKUkKUEc{&Kk5(&pzOG_%NRwYS*Z'
    'qpD6SG4^`dM*v#hv+a$%c&qFLo!{4rRbhgmwpyk0&(AP$QylEI1|xG8D6>a<KVA`4NBO+3(uiOt_oSkK4P_0#%7VD%gy!K&md*#S'
    'F1}wqxPo}2@2C^8TkLa%OlGt%{qluQTtl81wxZ<eA%_XGxDv&S_YvONYc+Q~KG48?5)IUL6?SxXcn6^By<d>gD)Cm^XG6M%Q8r;F'
    '`_<h9D*nGkPSl2~-DbgL*K_*!;Z4*xH*Xon-S6X?%&%%*`_HBmJCnsRo}b!h9&DTS{u*$&Pqp?yxTciebL3QENEKDVP3LD&U$CF$'
    'V;(kmc*m@yYl(Yxdc()csMw=7DgZos-p)F4N!6y2EG|r%yBt5RhvFo*JQDyn+&IL($S>#XF&L0W{1ZGE$=VE|DdH$h6@%FLW0Cy+'
    'M)obUI~x(3jDXeXp`ohL>VA7h?Q-Y|&-Mx1=oPGS=GTEgHkk(82G9G?HV@vvMe`>u)Vj&*a3m41@m!rQ!N$ptYj4R~O9JOb&SwYP'
    'ynfQk*}Wo;*N-s<0v!f}Ms8fF#21V(G>07h@AaNuo5~N*b|hPE7WLy1&Urqp&gZPj?T}k9g(kf=N?oM*f(F%I4-o<T#<q8j1Lwls'
    'F5i8RS2H{IjBZ<-hznG2u&Z(RpTSJS7NyfYu<zq4+0v*>8*#g44V}WE5;uaGqHuTdb$PbV<*$jBOPN`xbho?NUd^_}9+*IL=6`Bc'
    'U|mq>RGI(fi#pKEbfF8-QO!A3=i9mTRGnMC%${wg7>X(t!EoXHU#711X+8I8|1AcMm}XK5Q;MVqB|T7hfuceol|m1H`+a@qp6T;@'
    'bG@re>pXXl-Q(C@3Po@nE2_!4>0FTpU73;d=IL%UBA6<pM>8}f;*}@e`|tdcAQO!;voY=;9+#wvSYlC<6STkT0`A-d-o3Un3$RVU'
    '*5BrxbsM!}Z*?89tNTFT;(umc>E&I_ig)gtkB#Ubp`CAO{JYWne;`8sRxx+(PDk_Vvo(HT&l5U%y9@8Of}cZ?jW1Q;9i$IbAOo}|'
    'kG9iCoCD|Tg;g%3?M^PyN%DVjzVe>E(mODC6qk&+vvxGOPm{x6B0gq;img2#=_!E0cX~*Xw3gDXeF+VCh4Onff;7rWZ*U{hZ)F%f'
    'Eb^p3<6mP8`Kc3a=?U$?P>ktGE3X-0DfQ0|o*hmZkn}EFysgf=3Y4^TV6I>JtFo$DzSu3dn8&dn4ZWbBlz=N;8MBr3ub@}|2pM<H'
    'EPyyXC)}&rF0H_BF?3sQ6F66(W(oN2jcRmRlViWPuPL~!mXmKdss(C`Y=s?y{(iKzZkgxdN^kf-p=kC8pb5*zr<Fs(!<F?7@n0Rg'
    'xb!Wf1+27L(z;;{t<HPUM-mCf8}G#ZQBDPaPT!YH2;E-h##Y)RpXG2SRrkMv&+=+A6&`+WfOiy*_{|qoKFtJLICZw;PWr(7a49(&'
    '-WmigWIb3Y(xTPtd{@i*tLLBBbzoaWr#pAO>?>hpO)EbFz5+Wd6{V8K07U_JNZ&Ad8*7L<+e=AxU0o{hdcGtNpXY8OC}ex4*m-}z'
    '+P(p_<k#+Y$jnW>yaT5BZmF)fLH=)XG9G%uZfbr<k+epU6u$NaVs%EXs+ZjR%?4RL<0kb$Eo3&HA5IU4s~Psiv+I37b%yqk!Ei_#'
    ')lYNRYB0OsKr5aCy~}Yj;O5+n+>ANN=I&)vnr~@~oifkCuGZ6BC%jcJZ+^FMj{Q41(P8Gga8}yjz-~iPM@p^7de}I2;TZWfxJ{yK'
    'mQKCmHm%-;%6!kgs1j`wmzq?-FNW$@&lP)P!*WOJZR*0`pY-l_3RaI^#yiNSu;aJ8J(?aZ$B*{ato#VqzzOtfX%aVszT6X@Zd0kS'
    'FdEgWNV$VRyKG3%wb2dTLfLEntW-{aIW5|>8-I_Uv=2_l8%V3kmSFF|^SxiH@UPG!Y-{EXy7;K(Zlx7sjjdPC%?`-?Qd6Z__|}GG'
    'rK3*D;-EysMONuFT~%9}cWD3WWUsP#>@CZt&dgWKN;<sHeucNLI%(uYx88ZsfE8UYL=%^So%*G2>w_DN4hsx??TIQdnU#WN>~>6k'
    '5svV5t%&KX&<1_19k#@>N3ZHru#^?)zl9v%A#4xSy>F!!EAnzMmfWxmt<Hh)hxSx(3<a!tvD>G(d;W{=X7w&nyQi`1T6f5xFAYYT'
    '?l8Ccm3byuEq{1N2qq=NQy;GL_q)w(+$yi2jJ;c%1~81KOnjUO%_2=0sToOb)LHNOfoDq|&3-4n;UzrK4O`Ae<V8rAaSNS*{|4rA'
    '5NzfXTKMzriJIcI7tf!oQGE9EH(=aqz($mIy>3ooq%l{XO>gE6g~Q|9k=3!qbo|FMZDEbqm|~aI7x)#V1?~NMYa_2bN<Z0WFt(P>'
    'MoM>x>v~^*$&+F5?vDeRG{g><1f6|$*g9hubZM~+bQ0F=G>Tp@D?OoBg`Xa5?{|;cSBhMEn)9^#Isq>f|G#z15Y?SVW@RCT7k-Ql'
    'v%_8+#O?86R8hDa?$E<7+%>6FPA!%nb3hzBbO|qR44R6+2JUnwdM`R+X$p^O=lQW_342@J%(j|-vL<o;OLg<^a#2q%rGw!;nr5I{'
    '$A!&%?BxX!Mz%CPAAis7>0g%A-C;k0<iROxuS3u3dDlZH`}3{dS`3LRH=pN93XP#||FcK-n>%r2v3YgE``c-0IW#4ea8YQt<=A=C'
    'ABe##L*$Fb`oHr)g^d6XY2b57&UDy5ku7@S6&2cxnlaj0K$wb&(u`u!rS#pDl|f!Mx0t_{(emgHjg;z(zLY6;fALa&>EiHjG4($5'
    'Q(`$14XW7!wdxg{1FcR8E}hRtsA25x!TK?`MQ(gB{X=Di^4Q$)tP$MNUCU`P(fHP}^V;H475z|fmgtXgJ(uBj?QSSRhv%^M@(|4)'
    'y7=eGqfM#meQ~}R*kgG7&V(LXX?Hp^)G8gA&d8YJ({sKq`;GhfvOu#XSY?f{sQwe;ritk8j|kjLlH}cM0#j5Gr^E7qc@VF1>%Oc5'
    'Wo7$bovO2vWC5h8j7`lLS8aKB(ir3<Q;c(uUxkoXM0^fF{{}=k>Wj02PHu`^(}qCl(<Mi*?On0fHBmdAikSsq>pHIXsShShN=_i6'
    'nQyY40jHC`oKBwUwrj-H<0z2O`Zs_eZMzS6t8$0I-kIwawur29lZvGmbDs93d<pgY7H+SeB*L@F=J>kXgTC~-9UHA0aJZC9cy{rb'
    'nqR4fi+i=*{t0xNqfv;&*1XzVgcQIcZ}k`>cSd+G>Ss=^wK~&XyV)y?eJOk%+IwaN9O~Axty|?i(d0H(<wS}7Iq|TOc==sfKjL{`'
    '1{QVk^PR*a-!Oao#8Rhi$FgAM_4uw>5T4u+_;Oh95TahRipkepW24m}eX4)~+-HUpYL67Ucpq3&!p8GASTQ_WGxIG%_1bNXJv&?B'
    'o?f6lXi>sjZk>*okJE<l&v&dIYmsr^k(u1=`!5XTV7%f=VDZi#k>JzyP3A8(tNLpowA2Ii;%H|uf5F%HB9mK<zt8KJ@2aPMuP12-'
    'RQE;cd@&h11y15nwX8F_+{<ZYV>10fIo&$au_n}q;_I~y*~h;Ic`_lOS~R;vmc!#>&^zXqO|QtCx|3=|MpTeiO$sZOv80Hd+xZr5'
    'c%b$iZpMw?Fo3Mgkx+8BABgMfmQr^={|lyIZz7enc(1ai#I)u-J(s3?q<%2`Wy$0<vgoCK*K4XQxnAi4yUKTJbC}h_m6!_Yq)d94'
    '1O}@5EUhO+^*3k}yVu}4y3Cit+={pM?ev*w@^T(BwTG4G8<DwOCg((+k<q>yR{`|Zi|)h4=a_$+gJDy7e_CQ`yu&az@k%X@_|-i('
    'vqXAR8r#PYwo@XCSGw}XXir-7Yff<H>K}K}U>Kn8y>FWL0Ep&!xhe6a*<>Ffg&;?RTE&aMus?q(5vI<5?`<Ev{Js~xN97eYCqMU1'
    'c`2OGGhGtfcE!pzgv2oNl9LX9hd6{T%`w0S#BO~eSARgJJ%SuKp1Xy>HasfY0;^wL*~*yzNPGnrOM9``tDNHRWO8VllfdC-YV+Hf'
    '_dxIVDoI7s+Z5Aqej+-^m>9m{m?|aj?c+`lUg_Anky{*)DnI)IcmTypZ@ooE#O;aHg5#|E2$>GX-Y~+(kK1>jfphTaAeqZ`+oM~L'
    'A#<t}R=qh^{AG57m&t(+G@pS^!A^Gn28#<<lzMD6%{^K5e9qS%(+;LnE-r5+0%!p{;5q4p?Zo@Ml1U%iEZUYF;g0{YLksx}Cj@p#'
    'x!b5A0xyW>pFiSGo_zC`D=f~?ZNLJ4;y=!AIBo0Vtn_ZGbWpqGM{?3&?GWw*>Nl^dHITS}2-g+A&-JKt-6d<=c`@IxzxhM#KZ3X$'
    '_9*w2fx1&E+B|qmFX?i)eq^WBjU$r9eqR{}t-&Pq*9LW0wr-~(WIdKTpsxCwRQYcVi%G*Aljym)Ok?Gj&qtF%pg+og9u<|8BMsdi'
    'BEiS5H88=`172^F2__S5uf+q^@x6VuRXPf=+b1BFdXa`pw6z)0+de1i)6e|&2TXnoF3teq<gcg<*j21mu|Y2&pskqW1?rTr1zoSc'
    'cI;dzw&Q6eVCo3oFD_KG-Oq-wC-QN9{`^YA<NO^$1MVJb|MEhb?fE+%bE>&x7Nb&?C<9wvut$B_uIlpNr|P5rh}kaqO>fMp!~k=^'
    '!CC;IvD4LEbD}n@8{koi|C|GIUj)DU`rJ5fa~c}fZJx<q2J&1^{7Sc)!Dj!QKPD}@%z@}gz@T}pyQ^irb=(r`7_!Jr)E322?(S}i'
    'e=%J5yUQ5=^c&#0&O7IGcRkK_C(rHiMjeu*KeTG$^>LTFan&-(9=D~|QN`N8v^z*T-}(zxwB-H3zmX^votzR2dJGnkTh^lG?|W-9'
    'l=T}8;Sb!D-c+BIFWlY2m_uKhO!WCS_td%HWhdb#6G}5MhVOEDG@DdsJ-xZVV>*Ejn?)<9_vNz+_?_KPn2p3jjarmP)0Wj0!oU1i'
    'c#QqQdvj;JGdSARPU$PJF@WEu>Ph+9%3De0d%O8V6R8{RGxjvDCJuP*l~<h|$m`)Zp!)EgPVL@on-$^Vb7rrT-h*4+BXC9lI|rYi'
    'Z_dm@$X!8Gmm`1KvS&m>%V|=KWvJ7+Z-*3ox%Q2A5Y%nV>vKQCHI?CRR{4OpKkQej(we(Sn@gg8yCP9@7S3Q1Bmf+Qw@JP0Z!z|A'
    'bzTQ}dNBHf<^6mu9hw8Xc6+Rq_i5fQ1^zE@u_%341^lp-GhXZ!@Z0gq7fK(J2A#a)!z@3%okfmJx8^`Eu_v$Q6$)M!g;7}mviEx9'
    'Iuz&W#V7%;BV(Za8Y!do;Y~e{Cr~#VlN;QmOKxr~j^x}pTOTE;VEKINU%AHCjMs7X@Y<Yl!(M{u3P+lg8oZ#JQ>1k+?AoV2<&5IT'
    'J2_ZaEuE)EvVaonQP~xz7&{duQt<cXBR8g6&Sr3<(cy_{&MQN!Dc3dR)VvMsYfF2U-pbk1UVV5f&$v6=Y4m@7UC+#cEu78b4qa}v'
    '56xF=Sq8OAe@~p)+S$<>n51~_wYk&ht*K^cA6ml`S7}T~74hrx<-=)SQ;E}Sgy^)z{o?$v!t?b;uvkFx`Y#alD-8zc9eV{oN|GY1'
    'wJ}!rq2(LsP3PZf$G__DohbJ%V~KFR(>Zp}P3INiBXL|B>FXNw!_`Y@_A>Am(5_Ndh6+aj&J_}Ot`?4<H-G`YrBD^!`Nf9U8uoQa'
    'ZI_LU$Q?$d=(a0Z<-<wqp1L&7DrwWc5dQ?pypXlJWiypHED1as<aRpg@KM`^_rZPinD~;;kQ>Z~n@`&4q?(Se1k_&FZDc=LAxeJI'
    'rTO?onN_Q(JER`{i*Ka&>7Gx~s`>tO;nIRKN5^jSmIdJ<94}DX>_y;ezU+RqdXul$ka6?Q#@!}q$jag(OpePovwwmj(`qIPef#mp'
    '!>9r{)9NvN3e=n?h`Q3u2d}=WO}Arp&GaiBEWJU8hAZ81ty+oId+Y0Hus&|085rH@)-_sJr(t3Dtx=qef6vR7mC217*PODgt5xmK'
    'ij5_Ft~F%(vFdMwRm+MtcYS4$yD2`FhuQ?2<z<zAog{X`)6UkPE|w`sp~+}Ii-_s3F|o>2#7o&$^yU%!0GpPbd{$NH((7^GPt<O^'
    'lb+Xf*Hv>e-j%=z$fx~%F|YrpG7|KSK^`sU!bU^2Ixyq$;hz2)!^g)wI*r#aFgz&>!ahU2fHlsfdh?p2FA2QL(-Gg>&F<^l@LIx5'
    'vh1pNV8_mGUCoaNL+PWxAA@+yRPUu3TiIRy4J3Z(Xa1Q%2#p-f=dgb`cI7bBPwriG`E@%Q_3s&zXL{HLWPW>cG-{tii-bNgNg7GB'
    '^Y&7P6rQMSvkq*k(|^LMc@v*l?&-Nf#;X$nXHV{--Q5RG=+mGgr_xj#c33Qk9t&?MI5-$@&*sBZ)>MAkjM@MYCi!EWSJwO0l4XB`'
    '7~uYG+hdtpUl{sgue?8ZcjNI!&XGY2t3V+)ySOjvdq%B419xJsbet10jNF#WdEq(-kx?vJJ~dm1?o#iMR{GDrPfMRW^`P@XCaQY8'
    'IJN%nfm9ozM^5UWE+dw<w=PJ!OYz0^_1F5GQw%hy_s&9ZKz2FYI;4R<OpV2f_)BpR;fH?_z5R9*S0;6OT>o0`6QMPE!a^A>pObGf'
    'PXT#MM+kO447IWHnCN4zti~AM7tlE4tNT*$)hCts+)0Gqg_C}KfIK8GuTIljo~lCQ?_}_BL_(u$m;$Ty@!Hoc{v;DjI-C^t`<mUi'
    'wN_Zi?2kB}1@hU~Y6Mi_Avnu$p`GiE-mmeq&YFGQpK<+a-mZK)$CVUCelEtNwIR3C)exMvO}oTo<;Z`FsNk!nIxDM#Gk^|i1)1dJ'
    'v1a3HK5rf6y*d;AHFgR2cS|<O+Os3`Cq2~4VKX@P!7?+$AoiTJ2-_P7JG~g%4mi3Wtcc4O-e&xVDI0U4KHZ}`^G+Q3Y7<ZUX8Bhq'
    '@VCX(*-S^tx#w`UQ8Di?J<nv7hILr(gS?6;<?0s0I<bGklT&FrtD6woBZ%)(klNEcn$SA&*ykksoyEPG{}ar9?=AMJzYJ{@-t018'
    '>dQJ7a**6iKIls{zACcWD%YKHcUW@Fw!qU_o1dEG3jg*hkJnWWvN#Tka95SKEd=@bb#pMYmJ>0HU&HS-i0o15tH_Sjn0dGdy+-)i'
    'LFp!GZI{c(;-+=KhZ{*k`_@3hlE<@-Php)g`--KSjh-@4OTTj#@|WW{xKp~jn~e(VFqC@g%~WRcwATcaP#jv~gMQvyB3m$=>$ao5'
    '(1fhYb{~Z;LAnm!5I$=YDPhUbe%#*v{MmNfYf<s$Y3M-gybCs))((VMYC@%)DibXnb9s%Zigo7wI3?P366mdS>2NX!k^GQ(YDD3k'
    ';XYbsi&d;JlKiXxo{v)vP%9nC<3IGrnQfNglPwk009RD+Rv#$*vFI+@d9rQ1F}3d<M_PM4($=NByDiD)U^`-_Ps(pliyquuFMm8F'
    'f|w##es%B_Ht_ovus*yBp)2>xGOE_Afn8UY%8GJjq?t+F325CxO>jOg_~cuZw-PF)AvTtt`J73X!dVc0LecYN1PNt|ovcEzcVrVc'
    '?FzTu9b;zcd}AI;l506OqYQRL|C!5zA~tg_Y(K7mUG)7`rQ#v;q`Kn<v#DHJ1B;)ZY~{s>=c6t#xIHW&*>E@Ji;CenR}pCC)%-}l'
    'Q8mPUhjAGBT(SQw^<C#M-@}wh-`X<`3y-C<PnszHck0LQAKu|+TBUUy5b@<PRL0LMgp^w|ve^lnpG)(cpRYuGo^(n*>KcO19(gJJ'
    'vNEyg)NjYnlV!JcUOcVGDGmIWg3tKhJ&vXC<=p=4$m(*l!H;KW_u>Rjm`cl9QJZ<(8TDJ{8DC(tvN;m>RrRf3(%PE(&c1K6IohDZ'
    'z=2-`OA?~h#H^q2vN*{1EiS$V!*gs~^~VQwi<MU9q%@tAjS}bKeC)JwG}-{&-geRG3ABUOa;X+y9GW`zC!GJihOOyww|~H6{C6*+'
    'sz1m`Q-v{NTBVDq-~QU%jRQ9ab+pkY2!oib_c#}2{F3E#7e`-xXuRq7d*9}8M!y%PPV(+(_37_NJ0bY~-dk={8F+Ev23J^rK$)io'
    'A5tWeP0DgF<90G%<6vR)-D~AY%`fw;KJTv3hT<#cxOOM(^jmIX2Y6fu|4g;mOm;ti)=oK~MPbmi&W*3_a8I2ET~y7ujI5R4=&jO!'
    'o3pz55c&I{G(4yu*i{FQW5Fx?QCm^Wv(>xPE?Q&{%gCVc^TXBKG0e~}e%v-LH3g!UXmg+6=mXY0jHA^A>WN5C?BAH#suA{?>szC?'
    '=QeKIYiV0H?7eZyHrN5<<UDQYQ^q^|@GnvH>Lxy$Zt!_Y{HD>0zyT{_y|PZXE3WQXV;eB3qC@4uwbr3uteuv3&<kaEWi-6g;iYJ~'
    'D{Xl#jrD|i%zk`qi@@9Iw#`0yf7{hh;3*|H0}YTrkuZ3+Pv`;CyV|Px+PT3EJM;0abBX)Stn-@3;6h$g3Y>U@@r=2T(*pgU1-v15'
    '30Gx_HTjUPdtXfs_o#^?DrTG-#f?4(dtT_?=~2f>hBdVgXcFerpE0}NnMZGVF2i@%UCd9f<9gX04#{8L6Qg%D1vC@d7+pV*=M$v)'
    '=;BSiNo|S%ICM<--D(He`q6!%{7kR@w|4OW*V7F~C=l%QNqs}V<^|`%TV>k!|HUDqVUo<^IycijJp!LOM>n2Mf4U>Lgs2Qw-?*+#'
    'i{0n39<#lmaVXX3jhVz0w=?{dVf_60mn6hFNHH~PUqgTOk}k5eunxOOw^Zv)1dS*9ZD{YHT9CtfBixWrt=}#Pym>4%XbZjf*NR*F'
    '-sZ0xMF1BF@)*aze4UPa8^b&1ZT#wTt&$lF#N=wWxGsA+EadmvtOa;M4L@<z-P{4iJVZ-hYDx{O<}%HeypuDc%<*K}zO28)d%rrD'
    '<<5npXEV{OpZ@XwvsQX)K<?-AcPj3Tx~@zN+Z|AHSFYwc7i=fe{%Vf2kZLrlC&(usSF8!R=Cx={-$IUYub#FtM7}m}ei-p*2gIrC'
    '2nnyeVFin;?&<qnV?$eLAKCM|F<D%z&9&VwlATi~IC(f^tGL29i$U{-OqDfW+n~sK(aBvzX*y~BGXBLk<BK()$T->awY-Dj%qp+s'
    'X#Z5(Ewm*jrUCzk!w0iziZLV`D-DKu>?lmIr%lB}Z+O`G^x3*PTKNzAZQrZe&km6#Mj=m4?p>r53}$ktdn1JQ=lPw5Vzz7hdSkh5'
    '@hz^h_bLUx4<Grmy>e^)`Cm#L1eH<ee%9=(a_#H-uGmz6^}ZCbtRWw!`|3@61WY1bH*Y;bN9mgAH`>+#a7v)j+a}etx9ApM0hHEW'
    'cK@^*@i!PCU8f;=XFqGLLp?aey8Ro>yqar0?<zC1dt=PZ&*Ac5F}2p9HhylL@#!S96|%qWBOesFGi_qmZ%iku&9~Z2PoZP@tP}Xg'
    'Xu+YzQQr0aKMSYqtdl<rsgq=)eiHMgKdqo`y{h=AurP1bZIis#1<$?jo8xG@e6#PEinr5YewX*h$4XJifxc$18*L@<;vnq&@Q&rm'
    's93QK2f9y@xVq{a4q1;zD;Dj{^HD_DkB#q(2Z-z~+EX<jfIU~cGIX>xr?;ruh&opAw2kLk^?^QBMt=jX@^`6wN|ox%8GOgBDYNCd'
    'CQW?pQ@r4|B++36A-=~ukydIbIWB4EE=zoZl|QR^+_SQv&LP*{<a0O|gCj9demWc6{xTp8T!8amasc`GeEr?(rIEiqp}1|sgrUf$'
    'kh)79@4O#oZ+#%^U7vzy-3&l0jmL<%mtH&|&1MTIpJ{_%-6+%E9sV*AhNIhgeOw=3*3jVl6O+jRs597e4_eY%^m=eftbKK<u8Ede'
    'V<QOz?A-MaBJ8eH0jh4$X=S0`JCom_Lj2l%mS`{0<c9YZ??s~<vAtYz9~RVO_xq-D%-YF<zcKhzO?!t+64Dv9M_1>Xq4=B1=e^gG'
    '{SiHRT{ur+_@54%?~Dhtq*W3a_kOVgi`Ogn1bXc@_Tq7G;EC@ZRjD`cw;zC7jiAWI`&;SW4C%qH0q))EsMo!6z3zHmCNj_aH5Qby'
    '`;kBgN6UYzpmRGUFM6!1!_8}1!iYNfHNc@#q5K+HO}(267K`~=pVadzZVC<S`n(Xtpq1kGV@yv<>vH_7E59y>r>Z=M(L9oR*E?un'
    '^VLN7{Joe;B-r`0y5^c#!~;V04+iW^RI<z5`T43y>!#;(YYJ>FpbC0JmLbf5_kRnr3Qj-v*L*z1n{Pfqft}jD<<j-Em;Gce((#y)'
    'cDqAFb`D9`;=VVT8Nz1O+Hxo71n(<&FSfrrLHEe}iqc?!_@{HMH!r~V#c@+3g<nuvw3Dt9snr(*&ood&uR_Ny&-Z~%&#hH!%d?xu'
    ';XCQl>RajI!VGM}CUAYN-WGpN!}CvX&)tYIJE$wFuRO8;Fz>Ob>8LRS+r~V+tCzIe&=xWhW6rvC%bH7m19oxqs}2|qMszqVG<Hq4'
    'T4nV$7_H~UZ%|fcgk3phwWkyBfgq>0cH)v#f6_6e@mVXzGc$T!n;Ztk>*b>$t`XNDy8MK6dnh}`=9WFp$90USPA?RoP8Im)cUJ$&'
    '_FlD5aUA#E4_a1b6K?J5(zqNH^sPU<)~Tguu<SySfWcs`kdLVo^d4gadoKn=(jK`n<Csg~;0giHazCDT7BK5&tNXcO{GTh9=RPOx'
    'R5QE41Tog7<Rh?ct+gah&PSqsxOS)r(BC(`0NojIdU~DY0CEOp_<4@b#C7=o@%~`QEN{y}CLR0F&AIe&PU5Nhkl1dC7@!;5@)8e`'
    'K6<Ra<@w-LOgYddFDehJe+dDBH?FmtABdP58W6p_``oX=jX2`>1Mi9b(qr<);~L9@*Db?S(GJ{xDqeWf%h$!+baLm<Hr08znl_An'
    'd>+cSewDTyC|0VsUV9&9HG8%i&_8~&HubF%c-$q=X8GC+x5iB&yUW$7w(Z>se6<d0*LHmC?H{{yY_F2B^RWH^#ePX<e*g@SLA=g8'
    'lX|!|4@lVL*Z+8b@&LZ<`Ozf&jyhN#+fRUa)ZzAI8&<*3adtHA3*VE@P}7;$QbuXdD6iE>Sn49|;608+>sK%!jJ2!;HUyM@`t=<*'
    'K7Ax#3bwoBtj?oiH(6Pf8NbS&pjGOmdhQDJ%quyQ3Bj>#5e#frA}S!=No{0*7n+!0*=ZnoJ<7mJ>z|J4?{ssK|Lk@`tryyr*RW^F'
    'tE_%SXAfwyx((tn5f6*N?(mM=DCtb9%zF#IdE&jPHmMJH`F{-(uVl5FNOJ!O{_v!PJ`A2S8wh!}xyIwXqfE*=xA*=~UN+pFM9I~?'
    '@@**xi6ob$huSmI{RXN-20Tcg3^3Zv@Uq=Lkl6Mp)*r#ozT&4nLX&NdUw7Z>KvfilJ5^0%Ncej|8k9a_Ll4we>{KG)aMz1_Z(gnt'
    'BWj0;<%qM}^Ru(vBj3%MWfO_rZGZJ@h&+kkEu<c<38P^?2A+1(68}4t)2Y5I-Q7!iZca&SMn6AUAslEzNc7pOI?x`_MZo56F)S{Z'
    '@d_-BK={3!{`j}q7b*X_Eln6=!o*`B{O)qOac-X2o_eD1SB@ng1Ga&*&<kDGS##)Fet&KSEx`TG-p`22hlA(tnGTNtY>a`QekaDr'
    'meqTIYv>~b@N@4a4v*26SFT5=x2ykoJ~&lJC7>}Gt&c0zZ{Vf&b2q|vs9IEk@4HrW9&CA5#NhjGkIC@oACv@WeRnOZ17FWbA8W6B'
    'iq636#<*5#)IbTAwBxqbTQiuZ;^Y3cme{%Ay}v&Ht{&Qx)S#9~j&<9n+y3O{1^hM0AM1Mm<7>KmoY-O5sNObDIe&zpNgns~CN0SH'
    '*1}uGDL|jI)~el}kB)9OladvnEY!`akT&bTSAsqCL@!g1=TEmS8sB#M#>;(d+%1EVu`0c|Eeu*;8ZHMnv(^04%!NO#)z$aU;N%&^'
    'H`|4{ehdy4cd9tlp2m;#_IksnTH-a@zxOscup&i$athe62!70J+jlCq2jP-+y-ufb$2k?i@(oErh@7x}`s=oz(8aVGAKx`r>>Ap-'
    'ms8`qH=~<3#HRo1zb|p!JOp5r#$B*Ex7v^A_wSKxB05jLqlbS(@-1D(WMOj<^X@fT=0SB-iSp5>a`U06T&wAh{G6C<`?gs3{^7}P'
    '%J>?5ZT>k3U-7#kxEPo6w%^YGen#SXQr@L*v&Lqy@6WKHdx(z>5tg8=xga!TTKEJ|On6f<@w(VZvr_!idz$;qAkTCJG^zIO<jP@S'
    'tLaCd9UK~MdJ!GAx+roat``kO2VMnBH1j(Q!GfBuhR4uW?53TSJ<z0-xY3SAKYT`Ji};>Nuv#4NarUj%+B3pjfXx?5MHzDV_}#o^'
    '-qEI2;nKw^23OCrxu9z{x;#+xC##yHd*y0EWo(jL7xVr*zuaCdwOXGdYb)uMp7koB{TykrnCxbBFI!@l1`L*|_O7a0O#@99VUfMI'
    'wKzTQ8K8~&Si_?#sHB|MYw#7X@SiTInEWM7(}y2#&GXfrWutH@J{7e#qpyjW=ic=|fkR#!QS8W?AH|XI$tTsWvV)#S?)H%OGM+Sc'
    'kamk>Thp)pzk%fpzL2+UWf)(1#x#OJ>if3KLxBljXNzj;FQn3N#G9w<w;e9OwWWfWKMQ<4I=q_gTxRiZB?cQc)u>asd{KV=A~N}x'
    'IPYb7>cM{)`gAgLm5HzGa_-8b!<&5wxiGJTMT66ocOJ&<!`d}kMaAzt-=!^WH*p%rc$rEd6z+HX?l12?^x6#X6y??INJc}awk*ac'
    '|I5`AJ2h7;Fse@{^9og=_1ZRVKnKO|TzgelowetIQQ&43y~_U0qF1`*L7nj5V5DVqLXC81QcN>6fqnysH@OA*-zh&7VRAOPdN=cd'
    'b!Ds$_Qn{xh1w&plsNqZIBb&lcF*Zd%>diJeYnc(->V;w6MPkCuqXSdi7K>lpo?a7?UdF5=MPu)w!2^Mcf0kYM~@!nYBAluj1gL$'
    'qtmc8G;0?8fX_<Q>mzCFbhq>V;okyu)ZQpb@8Y>sw#Urf!CQ;t+1ooh_O{qvtmweD2jk6GIJtt=ZHVB-sARx=6?FK<bxo#vT_hF#'
    'kUeB5@QDiYi$g-924{`DW$VKyC+A>6AIq2a<3s?+egt5ua!TKPt=TOz{obr2D`G}G5${=KAEkQv3dbud{Fxe%`K9Zs?eEV|O4=y%'
    'Culd+DsW}oHhhvh%=+6MGCGl^&5)hk>x^4GYV@7e*Y>c#7OQVNof}^H!se5+(J;0&hA^RD?8+x6|MBzG#zbfbLEfvY^-h*OjCr3B'
    'xFvE9H|rg={*1(s?qH2otc$mtwczsz_rpyYW1)7GrEsqsR-bMF*p244O;w8@-q}Bd3cf_Q&)WQSd=-=0Jp&ZyIhKi9R$>V1>@r&!'
    'X)o-u@3*Ta-s3W{emW3dH*TRM$KE<}nKAKI8^e^taQknORU(fDi)b}vFPG?0gU!zN_85h(L6`nKaAu;`_ue}hm|a)i@IuL^xA@9!'
    'ceCipP}o>%uCv*Gv}cRtt!3@W_lHX!>h^U2+e!$Rp6BvAe#GXt^7?+ce)S8rMESLurj?#Ina)+L;}E;@ZnIvZ12ZL@*m*rPYy$Xk'
    'YhOaTPoexg|9G<VC2Y2aBHyTq2T;3P?GWP)Vd?(8;NkmqnF_l0plgn+ENNpO&+p3BE?-}g#rK{i#XIGDAw^Ry{D8IT?Jv*!<!^W<'
    '$&V!YR(5`cY2KL|_xT!g+WEN9wTQLvMa^Gx>wb7pt$EAr?v~b8ZaZu@p7=v;%g;XcIxK7OyXcmhI^X&6BCRU8f<~acwdp?3E=oG`'
    'TG7cuP_!<aD6NBdDm;FzwR)SgEvrbImeaF%Kn_*8bdaYH@xT3`5BPb_U@E&a`Oojv!X?2_%l2^p2ic|NZCGIyBIs>yEuB;s&>>8>'
    'vrJ3G^3V~CsJ`De^lZGL+(lEs#T7N1c8ZF!*<$Z?$F8f*AHUh|Z7xy0gTV?jRI@tNyHc(};s?7v2<&A#vUVGI)DJ5Dsk?v8)NTl`'
    'bZ0Ekz}jt`xtYFZz%>qR8xq&j)Yk1+*N{(dev$tDv-YYUSk?P?QRw9LtH{GaEo1K-EMDosH_jT}#sE4G9(xwMb*CXY(st~^x0pFg'
    'lSdNV&t3zrq^*8=VRFjd4wPEMrZ&gpQNICh*H`^4bcEofIrNN!J4j=6ZWu^>_!I*d^2jxQ*eSAr6gwqaQRL`;{WQQfj@$wi{?*q{'
    '<H_^FHF4N~JO>bZF6gg1;<{@?n#|Xf{CGO4&<j7pqk>M{O6)}Az<ZvI`;=&>6(rsDi)WWY=fl`n!(RE{0?2K1fWcL_Q9E2#o0qd@'
    'wP`Jn0N)o;Zrd%j5BSj`--F;K*W0gC#f}kjb;|QPbWO2MceN)VXxf3|n_k~7@u~YS?{>z4Dk|A+82O=NhvL#pj$%OfUAXf)5kow^'
    'r19k9Pz`Nl7}9iAk-5qjMAVtd8~%9wpol3bKe@j&Ozs^{zxvJ}hyqKy`A7K}P`}!$y*sZ>E3GU_$9uJ?+Jo-n%-yjgv|$bnt1Vk!'
    '(4HRl`4IB`H5R>V&v>0^^H#Jmnon-@{GDHvy_Kh}(nSJTCZoZ!`b~VWa|VMz{bIMX!tO$abEVEwjY4T{J;sgbx%}EE&OmZx{Ti(m'
    'bhBrTMYtIk^#}B;%YhV9UO@PTEh)Sdk>>g>@txK1J7rIg(NOJ`cdd;lA%mV(G6&Mtkal3wc+Lj-ZdF?qH`)mN>}@O*6RpyFd;W`W'
    '`YAH=)wNOwo^2($jHQ;o0Y+y$nC?dH;bbZ8fJ1j(7gpM%Gm%NX?s!uxEz>7>N@qqp;al9fZs6x9lXPrE`SnT2?z1m=Fz<k8Es0yM'
    'oAFyLrl;my3Io>c%@thfy;7rcjfcl|hn`-x2+t(&$UkADBiy>&cS2s!NvIkM@lpQ`g0$Z~EF}Gm@lB?C1hev`(`ZjDq<%O3=!U?y'
    'HTK-k1=E*OK2Xma!6DP<KBJg^f$ASlcQ#cx@3>$(4bIa3*QZug_uot1Jt2ce|4O7F5F`;@@s8@!dHmVp5x`oX7muwYd|9t9?))sR'
    '5BlzS4*20>c8scJfb-sQn=0E^B<@Xr{aN?4{H>Iu^yXYPvMhA#UG|wS5vJVzd`bs4$5+x3=c55RALU|gc?8{6)sWAc9oo&=x$NMr'
    '^L{QfJ^A|%x>ODSmj?{T>#JI2FAZ|p?Ulo8nlH-M<4G?EthNqwd($sXwKHL>+^9VN3(916g%5}Ose_832``7)r#lJzgY2{9ZTx57'
    'I-ndJlWbqn+GcFCFInivLN<|_BeA4|<J+`Wpr(S-!&L|`JniGZLBQyrV}6_;q04^eBi-(;FUtGlX!T~eUpy9Eyx6=T>b*<;;`s}d'
    'lVgqk2;KMX@CaHv!|OHqVQFQm@K9OQ>07Ht_S)i^RHXZ1UzGgOz5VSoGpHd-p+|YsfBYLH2pw>K_Sm31eYhYW?_Fwhx0dr+L=Hbt'
    '=)m9_5xm=M;%%TS$c}4D%{p*1_d50V!`(eOt3tir|I7};f&B4$=6qb?h6s4+>Ko~i1~uN7mMsp_4o5S$p7T_Qll%~a2j8#8<s{oJ'
    'xp~)j8lR;AL9cyhv>x7^t$Gz3@gxx>?q6ThZmgN}5C1wdVB{Y5nub)JV6r?^-Y9vQ+)h9tJd-u?X)KCL5R`A|1mv&VDYE<YN;?zb'
    'kLyGn?yiF<&7}Tsj({ZYXN0^sbd7X-YaEsvZ@BFd{vM6*szRSWr^UYZ9B#ixx9iO-m6DJ>Nq+u4m-*`m{aSMneNcFKc&g8<@IeXW'
    '-$GEbHJe>yBG{&*WX@y*I2N}kR@Fc6%0b-m#<qbaLsorHs(NPVyX)rK&U(#}`r-yt<Uoz9Q3J4?qAsr{r^l}j-VvlBXrAB_wh2!4'
    'R%A)qC1E0ze$48g(OoX(acyLQLEkgA{bl<ST6-dTRQ!6pCz*+2IYPzf#$k?p`PC|`J^$ScsXIj42V2>#?EKF3;|Cqj@vWMZo}FLG'
    '@^qn0uJK<m?d)df9YJa3^~T)A{lpb3S+E}1=n&Bd1CE#tj4=M;hkTJ7YD>MBD)nS9dC@^~hfv90HD^n<QJV^R>$BT-+dH_gO_+-D'
    '9O9#}`GJ>>-eqD&uWX?AB+z)xHp6u~21ma^Z_~zHdt?`ITn|OB>|_m`r{`G>&c$Yp&Nq(O6cHLZ&U7tqeV>y9klow3T{+v20CK}-'
    '=rrugM4794R3GhW;>YWu&`gJAD7?)CE8D9xT1N0h?XG-~**D*gUr5L2)qE1O^5pBWO9HUZV;AxGDs!T(YFS(XXBb<|XCni}PB8c5'
    '-%gbFiohPy*z}6=yVBt7O4R4vNdaaXb7;ve({>aT*;>k|GX|!*yu!bSn(JCbF2-K#RY<Oy#Lj1PJT@U<@ze2djAvJJ=KE6jjtW^e'
    'TQ0VvT7183Y(UHhnb3GG=G^pn^R9QLJL`=p$-NVUEHKU`2;yO~vfF%=&TPZ=VW_kve&;OAK<Bvz9?Ebg1Gg;wp54u+yPT2>yrZrE'
    ';`uNOJ3IcC3Cso3A>G^07rAGa%D@Rrj;9`4Ox{;I9pZld;O~N8y(Cd(8InpHuL&<Vw^dl53Z%CE`pap1m3F5v>fzh&ZiqELd5aNQ'
    '$Jonpcfk|e%4dEw)^2a5u%GWND{g=Jx*+}P>(K_;HpXQM^ZsDoeOZ-qX~~&!ncZ$m^+2>P?fz0&AHB}1hjqpLLvFFl5fldLTk?1l'
    'H=S;O`P?i5ece^K0rRUrQ2PdU2?}@c8LY%nJicBnIoUUg;`MP~$!KLr2e4jrR?Vv4C^ah8Qs=cNOY@h5uRE+)&CK;IovKAI+M&u}'
    'asB1<SpjLA=!g&kC0g4ueJSB2`~7n@Aa-p`W6mg-yJIhQPLtlu*b`M30CO%v+MAdYPOFPNmzO{>^))l2jT1)wn{Q-=b6c$kaMWt_'
    '$9cpsBJ-?MJuc`A(rNNZa0!nM*W9I%e(mmk+Z?QPjV$vHb-aP`8#OkS>EdiPeE~~L$`AJ~`qb*%+&8Rzo}J!AT;0j))-<%nKE4a%'
    ')@;frcQxVx`wuwGa2f2a_(td9X}9ow?|MX_?bD(F+M7z#Emk+?SAP(?DFw%VsvMnp|CEQuu+@EbxiT@p4XC-$stujFyc<;Uy5Eg5'
    '89+l>9k;~Nb94tCc+Xs>+hzY!#lP?Reu-3m`o5&Kt^0o$xtHYq-a$|PZv4VtskOI^?SXAiyJk1}#N;=#vl*1!+o#N|Bl&1|cTP0C'
    'KZ0EEgA*HGA?DJF2&VZPcvo&Kdvc2+F5ssNN-B3pyG+F2Os^O?nSIureYbOC=HcBqjhlnkt6g37`3Bp$3y53C8qQuJ@7CxfpSL@W'
    '#3w&p+rZx}D$qxU&i9T(9|F1myoJMNHG5)Ui9c>w_4EX4X~39`@!MN9+SO)PDdyh(?5@VcxDyTs{wICy{Y2-CW;Fb#UoW1ruzVfO'
    ';DnBnLEFPO6xU)e_x04Z^1A+-!IETubN#ezd&kYNXe_KL-gRz$Vhv%dZQzt|uT5v#E$)nM{L|Zi2ejSO*X2t6eSU}qJ_nXA;$o{Q'
    'cq@Q%tq~IF{G&@xgSc~hXVn9Y+W;7jW{tntJ?SWvCNO5Xkr>9|YB1ohF8At=Jhs*sJGaZL3DfTMsldZcX7w|yr!Qs=uegS*bR`-6'
    '`mR~XJu6?at!*l80_<R{dM1e97labk#40dWpW4q)G9|jXB69i8i^#YHi+!Lu8u0`C(QN+N>`8nF5usW$<)BRZlb60dYAbU($yrz&'
    'n7dGmI`q3e%%69L6suHp`uQ^~pZEBAi1cm$5*~GPTgU7kZKt(IzOl_^U)^>G+>3h^@1c^A)d5zYR@Q3NN%ewIE;S~U<8c+L76@Uo'
    '#n|}O!B;((5s?;!?oe7e16OLsIw<~N{=B{E?yACWRBu?>OP_W=RM)(3F34yH?Z^GgURz#|%f)-;|6NeZbdtp2%j8dI-gyP=#UzUl'
    'm#uDF$v%zVsf22C5bxk*`>3m!t8^u3uzz{a+Llak1m3&#D`C@T$j!W@RO{^<_e3CWwMXY<{%~sOD)JhtR4$(?&sX?8kn3Tw8qV`H'
    '=oT0L7}Q4KgjdSIGCUy4<IdHkCDCs755R4&b57C_!(KPx@R4)%k;MM_NkN&$w~KfFnlaP$Q-Y!v{oQrF-z#nR_)?=XJ*k|>$(Svk'
    'Uo496B$X9|Eou(rXKU|5^Je`n&A$@Cwl=v7Nxyz4{*q>BKT^>vvuH<Wh0_tI-cl)?3`D@F(f~a4ee*A9SI^*O6W=?~Y0iG0hC9=U'
    ')~ZCVF@gb?b+TMMqgdj8&pWfKpP|q|?u6q|(Cz%V)*toWeXjliTYcZ>jLG-^3C%jmU%jO4(E;Iaz8(GBmX+pc`-fYnm&;yANw~T%'
    'X}@`5$2Wg&Sy@*ujVk8T2p+RPh<^D1`GSo>woo+j2pn<sxx2z=WHKH^Y9tL>#~0l`H&O_lC2DzyQV|GS?{Q54f9GuW9$|&rjnQ2Z'
    'v|nLwnvVL9y9n>9r_ip%x869fKJS4yX_<c4$VZu#IYzAYgZ|`$Ul2dQV{*bKsy`%FhTi|-^`p}tR}0Q(JE=D~gNs6KGH{ni`Wu8l'
    'S*ruP#>c5!6&U{0sW~w8fH$EzT+(27P;ahV<FRlZ?5CsJ=rNs>Y4MwbQC(8$6-A8>6at$!FxEe!dX-{Go_jYonoh%FSX(86Gd@o6'
    '>BVH#%dOj8wv^KDVr--nbK_8+0FD$-T^+SF`Q<~wqU5~V%IoZxz197+ucv6}wJaOs)>C9-K?|`v)V8&#dmHiWtsAiSXEK^qmwLy<'
    'qP>Hh)aLnC>>urNhe^ECPfrWf-rcG}-DabfyugusdU!r>!_9-#HDx*-?r!Jo|Jb^==X3q9`?oY<!Zaf(HKCFYa;`{SP$-8aN(Y6%'
    '{rCP}JU%ziJq^2Bd#%0K-mk%@LboP%A#Ba>WF?}tLBd4O5mt0(#QD}QFX0{X-}z1RX}tdF;|(L_Q&%e{pV=GWsn_V@MIHTaT98sc'
    'eP0!-o$cvSFOTx#c#*W4wlmlogH9SvYe)+hant3YT8plNap0dt?}zIPbsF8y!1r`HgVoSvx(W!^{A7p(3NXT4ho?S&(Co;on1Im6'
    '_qa1QyJ88-leg9$AH4?>daxvCZZq6<xTXK=XQBJ0Zdd!oM=7nbGd=09w#JIPHZR+e`aP75^K)3rJ5mS?4&OY#mtJQlC=VY4LIP@|'
    'QL8NiWb}ZZy<>;24=C}6JM~sC%PU6@Es?$U%PmR3nlTj;0D$h^plrlHRMKgmVMp-f^R6tF6E$T1^7C?&ycn+LfPnfvo5{o~b#Kib'
    'l>X{FzC_mvx<sE)esJtnf>L}~K;;#N_(X~5L6qA#F7B<}F}3&6gz5besSaE*2Rpy3u=uviV#mkp{`I4~j4au2_ouTeZMzk_+g@#3'
    'HC9Ke?FVSL)NKPT;*NG;Fx|D;#pxW~&kVyqLvB^+&d<6em-~|!*rLG{QHB+ux@*qtt&bS$4|mYfv@I<#PV6^VOHpL|X0rqOTb$!I'
    '&Yl{UnfJa~U3!2q>u3A}iG-nbYK%wSvk%La>h`%Sag%AZ{sV~sX5-S&|9e%}&`{Qd{^-iR@zT_{wCytR808Vk&qg;*(V2N&sm<o`'
    'MX!OichEzA7)>aAt!q9e-dxcuKRP9{)2IPddG<R<JLtsi+xmGqmmsJIlL^*OG^|lkJ*+nvRwKeY+2c859#>k`saTcnqKbH*HC9yc'
    'ffU$fPq^Mz-zpO#lEc;c?ax<{El+ji*uz#LLKd+k8k>Sz>k%sho1(I1UHi~2b7!!WcFpA$0s7+8pzqo>jE1dYSM3MZ7=s760Y9f+'
    'tCV}cy_Qv@+h|5#+Zry;Q(ZfK=TPU$Z<qAat`~>mh3?+a>oSytnrgHiMW?8Geac{K=ug+zkXrJmkf>U)zV0+GVP@`+_f3(Y-g<mL'
    '9p+wZtANR3;B9(!tYSiU%Nfrrmm;zXBia-)RjY7cWky5a*%W@^7L{+&*+D`hUy^ENx@+u-?ypZ)Pv{FD)6kX4v|-6D<#w~$b8MZt'
    'YD?#`Y6I)9Oj6+Edf>Yjy{}z&;^iWPLwKrj@+S_J+jeD|M_k;!YgE7S^H(p>IU30~@*yj|4;~-Hj;3z%;o?nf%Uh<<nWW2Wm(eV?'
    'k~svO(>}w!CUVN}uD;559-X+GgLT~SOJBd9H~F8B>AYochb_Jy{DC43KJtca*%2!uu?~Tso!qLa3#alIA)l|8ZqqTPsmk7dwkj5K'
    '6V#<vL;(2suu0H;-7coL{nh0p8hSSMeh0KS_h-opDWR&!YE%IQxICbB?ZFbI_BfX;ZPasi%P-YFX$<GL`lat?&o}F4lvwxk-aQO`'
    'bjwzL^W9gevf=XK6>|aRR&JLv0gHuE1FJ3t;uNl|=D0}qQyL6zHqm<0n>tz?A*y(8+OL~45Zy-qnv|H+A>8+G+u-r*qqoOEC+CUw'
    'YF%UW@sc3x>shQWkF?V%0QlGwQDWZEVcB}^H(AN{)BZkn*VuAHTqPwzlG1aD+*o=4_R#cFhkm^8u_eR#)!>tC$>R)*bp(H3TqEzB'
    '=ySmv2G(M?Jm1cl$E}M$8IukYR0KeJ{qdjt7+G9LGRL<|>h7>q3Nvc{t8=xVDma5me|+e0O&<M(%(l$DO0~T{MoAU5HV_yfHbBk_'
    'oyFEy#+9WsTkaR*iTn&!+*DC1ra`p<q-rY?4*%*qB5{0K!Elghf-$*mILO|R-X`hRn?k>g(0%7KzDn_GG8>aB+SKyGV<W@aq!j=m'
    'sllmYUaRigHYvlGZHTacI#zO)`hgx?(v7*LYND{%l3n&$Q4{ORmBdwKXdq`k%hmA>h;H6#_V^fe_{>v$4wu-jwmt0Walr#!C+r$d'
    'EBnRQai`-qHZ?!Z$~Z!{f?Mk`<>9!u7<LrSq}AQ1d`wza>c6wqLp_1!3H4X+!Duqajn@8A8Lm;KtgCag$E?7m@O#ewOV-S$jI6ib'
    'wVjsyX)gAuXqg^|u6#)hvT(FBG7p;^B=5Y-LiXk`(F=z7qti|uyHC2<xo3k7)p|+iTk!tnH_w`MyvfH2W);;uHS>t<-&T%)Ddol?'
    'A@gtb2>}Oj(FGY--Uw1BW3NSi2bE(kOz+_$T?m*m@tN~-e(hk1_}c?lno%mK!soA~j@wb~x-DO#TWao>;T}*z@LUo5)3-ifowtDc'
    'soNBaV+?oHb_e*X>=UoMxj^j3Lft^?-IeL#pI>>jm;*OX7MR&^<y6lN`Ca9q>kV5y7UIqcsL^9`>X$cVqje%xUu{31_T}{ACL_7S'
    'yxSpj2OFiN=r_V4#dWz~{a37Q^~ILhAFD0{9|ZjJTz#{*vuqLi(WcFPe$=9c+@Gd~zuG^lMT}Vd9eD{Qf=YF87(VlCvA)%X+_)>('
    'N&SbD*U0ZIrqS@Mo@f<dyVDtO-4}G&EgKW7HJyU><?OTTLLN8j^TPK;P<o_|n;i<pe0~`3h~uq-il=T>PpZTDzr6<pxx<4w+G<Z4'
    'K6+B`)B^ZUIql|G&OnL1X?GF|)}vZuc?ybt(~Y_eWoS?NVRuY}<_&Y3wbl?*C(1+D_>3#RI1JKvWD3*gPF1;~0Ht+aj-edff3E#M'
    'Vzt(+DI#!RyYly!ACqMJ?klA5Fzfo0WjEEteg6@FTq`@3)6rS>vhh!61yS<p9h1<lgjz+?YskQ?omQ;~!~8LqT`GA)Eu_n-D-shO'
    'Hp_=gV;utr2)dMY4FF(zM4noesx&9>)${$*{q+ln<ucVTYtOukC@+k>0lMH)E$)f!-eLAS({82Q6ia!~jaFp<Na)a4KSNb|(8n1x'
    'J^A)0VU+4d_&U??=EBu}_^X_y+Hm<=cpb6V9>jVsAzx4FEDSl>eMP4lE()GuAhgr&N_?{UGCiX%3+x4jKBYb)jN<8lwxZ&;v`E{0'
    'EPs2c>RW{{XrYN@4J9hWcI)e(H)o@|A9c>xOZPec7X5?n3Sz6QbpF4+mb>a*IUi@*(GOh#`o)2MuVf+on2#43uI2t>@tkf=5CuQC'
    'Y+^4^<Oo^PvrT{5Q=A{hArf*sx$M0wrFI1pQ~XUM-__~Ue0HbL`c;;GdQ*LJ6K*L6PD&ywEWLo?WJHhX#w`QqB{$Rn6@=&IF^~rp'
    'zHQd0`nd-V%z+XVuFxI~(rs<Vi?`zmUpco#4t}_Ux{KZ=@Nlo?>_}J12BFgiUfM!hZvDYrv)Gz&e5#n|)xv!LvX%W1;4iU~w?*9O'
    'a(p7VzWfd`n{OSI&y;%oI|v@)Hl?xnuG7F+=DR}Mp@gR{K~TOCF}Kenr9K(BTb}y}+xKKx5YXF_^7o`G@2&6B$KEmny(?^|Rmop}'
    '?C9s$*k=F?KLk!no|JrC0kKmE(>I#lMjLbCQ7^dk+_>{^XL(5(w;xb@{m_8Kz0Rw0i5ZMf+kD11YJVsJ7JPmD>oaVcvd}1HwXRe='
    'w!^H%lJB6fylFqVGY0h@eMI&kOrtmdxEUp}%NNgw2zQ2U<=g<SNgO}ArB7}1Fdq~NT0Hs7$FzwB3H)u>IDOypp;T^T<H-yu@1Q1$'
    'UGMEv>+UgdT(?H!ddKZc{WkTjD&AW{-ov{|uO9^+JYTFN4yH77``2%IRaZo($EXT=h3C`S5C*^w5MM*fn%17)WiYP<?~z-?@U@BE'
    'DlHpCJD>GuO^tD4C>$@;^x2<wyG37<h0fpSf4CE^Xv7hk$MvE&V#UcKeQBRw!_zD8aq&mNMd)E)9&}%MPY-cc%vkou^v_(cfH&3n'
    'Jte|5^BHaTqbpPUF5<Yn`gfphNsju5`{=VPSC}p>!tHr&^hct$$LeNC<{J0@%OcRG$3N;81lP*RB5UIHXZ0D(C{JsC!0P)W()ZGE'
    'Us+DrpME1v?R%wXq+yrNvwSob;#OwNv*zNUPp_=wE-MvjDBh;f+fB&>v{4?HZ7kWV9*FhW`{6X4`ssgW%cEb@)s^wX^-MVI0KBm+'
    '$yKD|SFu;t?X_n`Dh$WXRV<~<E4t7$Ao<lfP&4TEsx{0N<Gys-iu|Nzy+rs#2sb4L2fW+0_CG!3pQ-t(RWr1tvTBV9#_s#4;SwAT'
    's<+^Az^l0u;%UUhpy<t|k-RnY=Zp=IyfL~X%UU|9P91jbVh{XmXk)$i^Zzo+^xfE=MNusl?(>|SjyYe-C-9J~Vj{7Tw>ROO*mI>R'
    'QIO8^qokJrdk5Xus{O2y!XIND0JugpT5~RtZuMW?9;J>XKzY^Jyp38K?>m>XyyMo*>YiwoOS@**tM-iZemL0zY{a=xwO{ZE#~&xE'
    '9IwiwVY=kvBOJZR&MUWZ`ln+fpj*14wk@&E7JUB(m+?Fk$Ge@J%k6u%8|~B;TK3E9-WOAY>8U<zipfF3SG45<y6y{SrZGT!y-NGD'
    'fL(3+)3JNB{DyMF)rM{G+Hcc}a<D`X<3%lAon9J$+*G>ir$><0zS9_KScfjnLO}9vonuWM4E&9teFu}f#0u^6!D;;JFl9YG+X+9t'
    '7I0smbOJs@OES6jn=|sfdeot})CSvq0PDks)P!j6F6l`|b?y2&m`Ysmltz~Xc9rXa(TU}|^LsB$nL2&wSrf_k<w^G=U<Rhd(wDO8'
    'X`s}vHD+|DNkx5B=W;Fk`>JtYJFRBP;Bx7lZi{$FD=??^s+;WH2=MrK-9^9An=WdxIO1x;Y=&R+9S{|>mp@jG>oaVL!LCVd%dg($'
    '!MD+DzD^;oTAtRgTfbiK(?j7egBj~Of(w03b?3jjy%4Eemr<=YzyrKh_O3-%>uu|{^^^;(pHlN8l7P#mzfUUfidqG$%I<@&x;Ldl'
    'jTGQ?`&^eedhMB`AtJ1@`Okj_L-thOvdyFjrH4T8v8dJdl14Mf6W^}$n*YdOR<uCX-qEZPv~Et%{Y+azai>SoeYXES#{EUBd2X7x'
    '+c52)Z*T+c=^kBdxLCuUoakIwiWpxzyU~NeNgR<YCR=$~o&`PKRj?N0QwSIOD}49`;>!)vG^K>=@@`(9pjFPJem+NpU~(9KdxZ1^'
    'lOZqB0Uqq9ajAQv%hWt;Ew*uLeA7!a3M$eV(YjAOtVNWhiGb!rf=|}Caa~!T2=qWzzQV7cb--oIeUWMO7+FX8JO4_i`pQ|AWWKA='
    'XM9eYuYxUBE}<lk_Vm@POeDm3aoY3{J?Xfk$rShO$#BKIv%Ye5e!jM3H%XOfIX*oLH=q{W<w1VbEV=sw<W=R=CQh^WSL0d|vN}#K'
    '9-6uv$NgYX^NHryvm0f0v{A?F&W+slGcNLeKK_T~0;|gV9QPu&MD1#D>Q|!rGe9l1yMZoxtMY2`^Zq%5%!@E%lE))AAow*}qB@RS'
    '%4O7pZq~fx=X&Nf<uUMY4%;ys&*e1h{@<p;(HE&CPcy~fB(A#AYMULCN6vA6iWrB^a9SwzD14pJ)+a2x)kvNqA-M0;`W%ub)K70-'
    'n($~XV~5&peQ!Mc!F$qbMdI<gxwk%>zo)-$AL)^JPO2~_+)H!zk3jTV_YHKb--OEqqC#6&28fs0x5~74U;XruqOEru2wqMC%|@H$'
    'EB6|lfDI6A;^wl;KiTlPXPj2VobK+ZwACQD2Faz`VK9X4db_?nu2Xz9uU7hXQoYXofBnt0R?b?}Fs2J32JnGC^*lAjeeT3v^V72n'
    'T?RnbJ0z^oBi2O=NIKGdBruDYc*&RzL3!d6Jnx_hFH9l!mMngK^j&~0fdb;}jvDSle7M`_Z7%H%=Zy{}j|2eIy5s5{TaLok(p>u7'
    'Xo4=jcwNF5)STA#y|298H+RG3?moKi0^rAgp}URP?rsp6!HZ1}>dMkl@vHE(&k1#O9W-ByoGko&By`bf^IN08@j5Ia;I=x=H4T}W'
    'o{_U`?NX@VRW|dV|A8?_?Oq+=OwIKA6DK=6H`arsQje)=z*W2|(Kz2Q#l*m>BGRgUw0cD^7JdE@3u~k{YZaq|vX)zOi^9%Dx&QCL'
    '_ROrE2eT+$VvR6)rONCB(0}lo%3I`lNIqEObxa4+bTa6%9-UMPZtBOX%)Tk0(+_!k%oyg1EEA!*Sv*tW_g+LV?+JHt<;_9NKGw7C'
    'F0G>IgNb%J?#{boFyAKZ1M)Nezn+CPLHf0$!asUTr=hP}br$Pn_#|2(<6*|HKil7R=XgKo46sSoulMj#qrRO*3J!d0BS>1c4K#L6'
    'Lp#y6)slUl1EOJrm1kc)+^CM7J6oqwJrzUx6C6YY_h(N1{liJJiVvae+pPtH!Bpz!5ZS+If*`q#;H}W}rL@1sheMma?n4S%OD%3w'
    'S=PxZ<+so!^OlM)QFXp=aXhLrn7^t1bO3hhw2nObRQv6^cPc15>7~`KFsh8vyXeqtdDva#ha<h~a_EjiQDu5y8Vds^Ca>LD`UY<v'
    't=z*_*1mjCm-PDMC8e05*X<yEx7j2!j^o7MYfE`Tleud|v!QYQ<1mBSa;;{mczKUMbqT#~DuLX@BfVpC!}xePbzpI#O#c+Wxc<fA'
    'K(!cqPYlL!_KNR^M_y=2C|n?WPYt&hK)b<0UkHacqe-6?mxW9HvaU-g4jLoz*dD)c{z(=4maxgT;Aa2&=`5;N<1!QfrqkQ})C3w+'
    '*6gHu#@Mt3YjvxKNBQ}Bjw7sD!LCN;&4L&A1OcVVX4kP(t(2u(_rcd#A5GzH1O9g~bvJ$wYkX;{L~MIDNs$M><RFzs+QfZo6V25v'
    'y>K0D5Ka+r21Ou~_=SS(WR*C}{S`h6Dl)sNJ`QDPuSEuX`iH;5QUjMq<4o^r6W4gvvJ$fM&Ysgp#mxX2fI{qwd!Y<-Xf;VJi-kG|'
    'fL*t-;Mp7XkEm`7b^cFW3kS7x)c>8A1l>#W?J5I6eqrX<Y*zh@@8an~%vmugZYthd9H<)4mV0$+AuGE2_ujW!Ay@D|Tb`eLt-(X@'
    'XhttY7U&(~fA6tZ$xEXpK!p!@iZ07Rjq|oBvF~uwOo{e4dYk(JR2tcn@fog*-ta7L$ZH?Hy^G@Ncrq4E6K?T#Jm8Nk!|waH53e%w'
    '&(qS!;RX|T%8@yZt9eD|cc?&-3AZ#)a6h~+A&W@cI{@0o;WAtotbYAEvw~bt5Ij2Ka6R{cQ6vV!{@)xRM{*PKpqWDs{8M>a>_o}5'
    'CJZdQ$BT=`qQ)S_iaZhPY`snvFaE{0Wk1+jM{sg_sXHQEe*E$|LvN88WH$1fvn;D69fAFUdlTDA;MOPSndQJev6BouX6t?jUP?i#'
    'GOFepruoLLx|GP~@}WK>UOIHPCx1PhO{fvMOxMoU8T{tlErR(};tsNNLJ}0|0^RZPXu@+V>lV#Q5qc|d&#)6^_jj-IsG=OoRbw?{'
    ')Pex(5lFeyXc%^%!r9oOtL&Bh^2Nb}`lZRf1N3rfCq@F}x#!+)Ev+#&1#(TSUKfxhDJ6Sm)x=%P984E(z{JfRS~-`i4{>gpl8{Y&'
    's9fGSQShr1Odo6y%WqKg5CKasq)Tn%9Cfc4bv`R*mspnGb#m@C%NRyg77fY~8%SO7iKH>#K<BBpEwoYPuw)4S<r&C0{>@=05jlgo'
    'PAg<zHjUZ?yL7$3vSZB#>xrv%0*bj=&9PUqv-*dOh7Q${#!3P}w31B*42d~cv$<H5>R`Tb$mrkRX0_HO>*u(n*-#x?_7ZPVdE!fa'
    '_j=={xmX1k404!n7Wq0Mzy3}uVfuW4;+jLkgGCSQE?O)0O}+v$x4b##<<>vHMt4>{-POxtF^p6+0_&9-3QNfADc%%i#3!q|rCO8{'
    'kY}^f?5kz>)ic-GBv#CAgTmwBDgkkg#M^4r90rG<j%{TZ{JS{73DeRm7|7mRa3F66?qOG%0pA;!&WGCwR=rGG=y(s?U$$D4LtjH4'
    'BRa9V5<b)T=6q)F_3EIVwaU-Gz9*v%46S9}GY4RoYSo`@a%JIIAcDpgKaF)g!pOEv^lNuOhz_K(OUp?6C^7VfoBlUhCT1rBq;U(T'
    'h#U6rd<IuW_qj<-xC}gzNUPm8yH4UNqqX?G-`i)ob%3`!*E_Yh<wT`&t&i7p=b&9$$Yb<}oN^r8_>I|-yNww*U*3N_HJk3sGuJDb'
    'i(BvSS9aaq{((MqXLu<ed!0)Gvx5}`2-|W|b71?jFcB#XKA(+yOKH`sJRjwJAf6|13!7QTee}~8mwI-d@(BD6I)S4iiS(SxHY|FN'
    '?Tyh}bi1w(;Hs}b5_7jRCGFjws%QLNlYtN%i6q|45?JAvb#^nIuZ3vzt8>v?Jqm1v<MnRI>GFv0ua9(x+T*P*M4;+Ca{AI^6s9#~'
    'W`l@cnwN%*0cZe%j_2+mo$a&=dde@B;@)b_aP_OxZf>hn*W_CVw?PEATYbZj89B<SG&wHi65-cGB%_}6TBp6E?vB3a=vH)-vc<lX'
    '8Xa(N&(Gz_SiM%^$;)HCU*23s1U5j){n&FT_45b7^1J-n^WVQ@i3+D(ZQVMrG0g4NYmb$_Tz=K=^0WB(t98j4JU=;-YLs?I#<zo2'
    'B|7}z=fg7_ZC|mbjKK2426>pAsvT$xzUokk-=7)?HgCFencluvx8tILQ{VNg$6Qa^T4rAb5`8xIX!ue9q2A@}l_%VPbAYp+5U%SM'
    'x_H4#wxu6KFGM%EXnmK&hI(2l_)y)UmhQ>fl%ZqBKMt;XdWWyoO+p+=c8kney@aZjVZTWq`ozz-;+<OH6!&|Lamth_4|&E^ux_95'
    't<!0Lvp<F%n&-C!!{}t&;A`$vA2vQZ*a+^;ccGJHxX;0nsXoxoF{^2C{;O-;_xwuUE(oVvlrIcx*w0JaSqjY(yAK<j)^ex?1h0y?'
    '!;agfwcMwUPUG9ZzgfK=J}0Le;H>+xExnJ#qZ!m@-=A*~AZnUlH0gMfir*91et@oU`=nZV^4;aEl@5%_%RRmn^bNKcPpV>@^CbXv'
    'wY+$z;-K?pq*SdzflXgY!f*ZNs0=kSm2^<}*PT$>L}O0quP^Akw)&HryEaSMXlLnsUS`#qucF<9AC>fn8uCVXi@ubDwio2M@JuP~'
    'Y8A13DE+Q`;DIq~a=Uaallz$-?&VT9Kury7tcMSw)a;b=NjyVh`BELupS;A)hwi3@ot!@r%bcbU@ARp*1oi4i+sb#X{^naK2q`|i'
    '34;UfR8r^ivRTAfr+s4&Q&K&2#x<OJPNCd+cFX-z;9fd;+=NK4vAK*>S*l;xJNw~oo1=x&TPfYa56_&=>-Hwg*s5pM`5RG0_xfcy'
    '+0;a$-6R6xAQVGOgQiw$_2)*dy*B1}w%5fg2>L*W9p(n<znF?wUPEl>k1hOsD^-xas;3bDiye9!b34Z`RbTgrX&i}ImZGoUkJK*x'
    'h1BX`IJKhLxCdy4RLZstb*2Wj@e{UG2SHYLTG=>p=T}d~y3(bI7ddNEL^{r^inkv^p5dqYY&Nr_Z@(mmd&MPVx*>Y=0$%U7>8jhF'
    'pDM3?Jo+q;P7W^z)MfC-+uKF!*WY{;7V3=y`qIYRQ<>!}{Uy{pn*_i%(8+AMnDtuiJWhF{ct-2;n~Vs3iM$?tYD8P|Y11kuUAQIJ'
    '3P?XF^|kSvlh`No*N|jahT5~LpYz!bHk#=s-Aq4xS}lA&z0TRR(GMvh_TyC*P!k;E=SN}9bt?xmHm#$hd8L<IW-h^L4gB!IlB_nd'
    '61N0@d-t$@Wky?m`F0yljgOsI^Lm#xvgP!soSXP7jr!B>dy<bIht<mcboyF#IX>RN0w@Re7rUnb{`1R4??Sstc*Qf<75KBMb+*Sd'
    'blDvQv4L6dnKtg05xOO>SM$-1u8kVU>!7Whw(EbF6Z%|Wy(KmybbQ{DBd^g5fAv1?F5PWvxN_kA6G<A`r8$nnw<92|td{|w3vTWE'
    'iyd+uCx3p2Kx2H_$0*u|V-efua!q|7N&3lFs#S@o-x=b^*TM4mx%rd43);sHwPq$H#|`nRqwUR;Ty2H1u9Y^L_s5z<vmKmXs0hNd'
    'M%zK^#CYu&=RG99{1@R?E6*!%hDN_VkqZKt8&7O?2T>S$Xuy4F-b<wsL~94|FISJgs|Pz+cj?e~R66PhEq}WrITrU1mqg!m?Ipr}'
    '%C_<z9-0CD0)D>C0F!V0D;lH&TW!s5m4^r5bLHw28PbiL%R|&TP2p$vKAEwuCWA|wfvT0S=KN8Ib~rs>JpinTAL@)nw!XS?Kir8!'
    'x$&tTN`cUMuWQUBcH!}R5<mWEk}U6_RsRUCVwyXH$8r<Itde@QlbsGG)a205NTK?y4iz>TFE-<1u2o>=hdc2^ESJ<O*$LCoo{j+t'
    'M&L>(>;TFlz2A-c--YO7JZ*6u5f~0Ij5Mq3eOiLAtTT?d*BHX)?4j4L;9Z{VLBD+!YOcXslcOGe`SzU;Ib_`ET`Kt{y>*2>Alt2d'
    '&|LyYTYvs3@_rtMRP}S)*+UO!_xq{8`n%EN6SOS3*xgjl^v`GB77%T;-89XuhRI)|gl2nxuxb*6+V|}pOAy`zPrYnD1I*TJA&{?i'
    'ZMP{BFS=mc^{i?_o3d@v0et;-)Zv6Oe|2SPBnV3g%YypcckGOH%u~VdbibFnV{c#c+TT4`@TpPBG`!WbG3R!@tcn#s>pJY{$n|ec'
    'gCAW=H>s(<F`fV6&iuk^<6E+4o}Gi=!imZW?a+Fj49|WZ8$}XYqA$0EqW7L|1ZY@qx0V`n?6Tzd^^ofpL5uHqmK4+aeOR7{i{E|%'
    'eRklFNV9T2-R~7~9@miy;v#082|4Nnc)MoT2kuDoUc&v5^^H41hTx|f!(P2Tdks2BNPJ&qVRNdIoB{3DKYljbXpoz=OHTbsDFU4p'
    'oO8IA47j2Cz0y_PcCNT$mn>`7t<+C<Nw6lb+id_sd&?tdo=hG#WvA)%{)ATJu4CojIc=~(saA0LZ#%I_89jUf`IciQr_*G6^o@XE'
    'k^n*PxJ0}b7MhQ1V5io!m9WFV=nL{C_Oh937wBoQfONkt^wqyOloym^`B8gW8dIpiI<sfmai}e`>8-lJ!hGyE9lI3h5g&*ty|=A('
    'dTx~tDWH(tYPF&Jt=356Y|1E;WF7nYmEF>^-{Hp<@VZHuMY3&f3A{RPCZ{tg4o0+O)tv_yPnTQla>$GLNds#o)t|LxlP1q#ol^3q'
    '*UvU=`<;X1NdNguvco1@)GyzAs5wZ_N-6C6g?jh&iS&S>f}f7-94?l%ORYIrue<myYm_h9=__3i-o3_WI2AKYFFIAJ%47jZ(68^0'
    'b*!yhxDmb%&-SjxJ?hG$dhKD2zqow((%`b5FF8UYjeK-BCME>$h!MtCv3TXU0{RFmyna@^_jKN~n}o9d#W(ERx7ok|?sVT^{N4(A'
    'gXfkpWCISYqk416RC-LcUf*u*(P1*77AFJS-;t>ck<&bz3T^z#Dz9t)$LY!$kVyaDV-5Ylb?W7|yWK{@HBUPHm=BKYY;o+V%~p7x'
    'wdr!L_O0F<XG&$kEfhWNOK<D=kCr6#(0BbUGOzi4=2j{?B>Zr4egos#^0>HRX$xxJ0i@Esb*JHE5J(I{jvAgxsS8}+3{Qt*D>z_^'
    'Rd#_f-<(f+%1ju+VC}o3%sBB?Mw-CC_#&giNdk5}9xG&<IH!=aoEApUB0z%|8dT#Eu<ahRDxATrT{B@SSxGn%#{JwoAE*A>j0|l6'
    '-o2_iTYB7ZH2Zf>kTeJZ0EmR$D?nvRiENxq<w7`K?v_o0xW%D3!7pu)d3E3TT9^lvwFDh}v**r}<S@SoGV`A7GBCNiD*JD~Wthw='
    '3-3^AJ~!G<PSCTR)Zp=@oGNeWXm}A`;@Ok+ZF?H5c7(K`lsRW)O;luR_u=BiflRWWZMInkaNGR;n}=*#2i*685vAEg`BgQIe*25P'
    'ZC@vz;HfK3?&NTBKnr0}F<zH~uE^~rw6S0vOCZ{S9e#n0raI>fHgMpci2d{F+S@WGj3&`aCbuV<U{+ds#mSJVB*8&FjI_oY>Isj@'
    'j!5IlkzF-%Wa94VIz;2mdWAFALs=g@{x~VSyDnA>`By)i|Dh{B622e9S6?f9?m@2?&7QtSwLOL#hcnmNRK(-;EEVS5$BJ^F&R<p+'
    'rQni^x9hX~HXKZ*iB^+TOAVXc_E#@KVQaN;?-J9If)RJUDE0gXR~m%YbD&;r%O07R<dQe8id8;vc&PXz`A&C?R(bVhhIdBmvow?o'
    '-wClBHgXXC`MD}Bq32J4naDJl>&X3TZ<{5vL*_060>oA`sVit7b=Gs+t=fxtDG0vhM@ME|s%}~zx@}jR9`&iDkMY}a;M32iyGfLL'
    '1!fKvWORB?yUyFV){@5`9pgjRI-C?GnW5;ZR|Cs)g~01AE1XRyPylaOqmT=!T1{s+U@VoNUkzqE(a*=<kq$kxgh?%&gvc(fW-^pP'
    'gPqwBm*WNVVhrFwT8qa6(uVEcrVDrWXJj}@`lJ2w0?t;;{K-6z{XyX()gXB0KVD)>-7RYH8+0r_pxqUz{^jxW489KnWOd2BTV0fo'
    '=Wle2H&^m#VPP^QwK0^&>FelX<%o1v_jPPYh@T3bG->_nMv}PmB<J*YPpe+`T1^*eHfWgAQqPqcJ2}2J3E~n1gTQ45D|ZXI-@D&U'
    '|8jcYW}BlOpB5o=yL$eJUG{7(<bM0&Cru3=kk3cGa=f8wZq7gV-l9D9;LSij3PF`COj#>FuQTIsU+U(vCm+|cUy;ye?^L}FZig*M'
    '&D)_g+_T8__Tc`V6W^xbVtN@@<S-m)*b3F%g54ozUM;<!4-VM9uxHBw@7;#)H9v%r?rqncq<FL<#-p8@2e=Me@q8ZXe$`t1u4|qC'
    '2t<!R8`$9#AC7comWN<(7Cetf(j>k2)}NM#^&P=i41zTVsMS%s?}MD~Ce8M?bQ^vD{!T5D{=V8&AoAbbV(s~XGbRIWyfm16Hm?x}'
    '9wG?LM5JZ*wT5TA^;eR!gLE;#*5|y@bhchNI7T$d4!0h0I;OYcGx51z^*ry--h*GA07-l4;jPy!{_<Tn<Lb>wcz9ZwpReN~-3Rm)'
    '6iCqfv?HwVmA?AjDDQNbGN^xoxWX@x^Vu3}vyQS-F5@q2{N6W1=-+KWQBhHssLFYEY^Z3HI4CuXT#=;`!-pg)Z><kKsL8;@cm9C%'
    'l}V8c$fGj(D%NUqdVyH3p^eJPoMC^ukfhxnH{LM(F~SxL^NnepwS2v6R?5}*K_}-b+NqJ++vmPKU-jDFv$kFm#iBU-jL%<8*@U~<'
    'W}9Nm)Y^1o=%=%MJ#6<UowU6)zt{-cU2tjAJdLr=OTBNNqw_n~N~6?$I`{$VR=b&`saK~*v}H)pz+J9Hulu;DhTe8xKl8WNuRp}L'
    'o{_35x-k?3f$QK<Tie3aO$-Z^uU{h1BwC%}hcf=#y>YLQK*~E8`@XnP`5!I~qbvJhAG3k&ro(QQ)5_1+maA2+iyT+s=caa7_z>C7'
    '9<JsND)>?=4@Sd=z{qhX#vz4br*(`S8n?c}$fpKwCp!6hL_n=HFH3G4TdR#q>BrX(6LPH6%<`S=12Kb?7$zRoC(*;z#lG8?fL@6n'
    ';>X$Obgi!IOTKiSd*cgHdTxU7wQTJgWMf<U(&yQHx9XAy=68<RU?we%{Q5|tQ})Od^}L>H_X|*oqt9gWMK?7_i@O~~Z?NZ7lTNjH'
    'K~s8Hf`ieg6YB-|IUM_5XPceX14;$&pU*sWPI&FUP6y*O7y9p}cd51e&*!-<z88J&gzBN~JI}ndzj0XGK%Fsv6({385M|Ns5o@nv'
    'Df4IkDm^U~13SjgXRf#pbV+|7x*vnVzM$@OSa!Vbtkqwor;jI?+!pEmNxEI<txEo_vSQ`*J#bUxJQ?Wd6<>_{-!ZE$Zf(kHBki9K'
    'sGP;IePzqz=0NZ3i<#08hEJ9XzcuSlJn-%u%*?8`g^c~zXv7P2?FtQGn|qfV(^%Hx5qCbOTyhWwVx^kK!Rg=pyv-v${s7Xw9V}?_'
    'p8THcg$5Om9l)>g^Br;z`{f5-Jt&n4znj5u_3<hx`P9WxtWN7=9A(tietWFSYhwHO@xHZ<8#<Db-8$7BMYkJBTi{B?GJkksTN&65'
    '9)wL&t5G#s!KI@dFWS#!Q0}eo)rVW}fgf#Le;gSaK%w*rd1mY1{wOK?(wexc-}>DeaI1g6e!ZB5<6iY>pjCuFT$6IFpyqhDbvup5'
    'VRYN=I@o=JVc~wb<n-~TL>TvvBbTqAzvu5)ufBdyJbl5cw=?m*YNkrQ&D0pLaQh?<t!p%28mO*m`*wT<=O*gW2Dn*C4m4liJTWO;'
    '>cBO{>$cn;E5Wt)uP=Qb7-AV-^`wO8Cn#?Dput2>liKQ|O9!W>cXGWb5o;L6HaUkaf^~7rm2Q814-L^7YjfyXFUFnr1CYMUY5Vo#'
    'X9+?~Uj+@B2WE3kU}sj!ldP@91sRy3|MF)~)w%f@RUAv!O27vXd%&-|?K{<u#06$SkPH}V`L*Qn`XaiEzy46~gc>z?ot5ts&st5g'
    'd0twyLJ-*JS^u!4pRm!zm4~TQ<D)9{OLvQ(Z*73P*<_9Kb+S6Z+Ismt!*<&X&QsKHUwlGtKYkRJN9ulaRvv=A^~z&0uME7S@B4^+'
    'f0UFaJc!LUE$aLK&IXJJqc_vvA3E9cFF<6-Rr+Py<k63elfo|#oeFfpMXM3t?96Y&84Na();vD_5vI62BEZvMoRY`q6lqq@U3A^-'
    'oQ4WhdrZ2Jf3J;jJ^&T%#qJ&A>>qfh_&vYS{0|mc9jbJ^e%eqG)Nn?(fP>O>!b;s;e_U?_y>C<qa7>wtV`biKwd*hneVB9UE`P9o'
    '($=1zQ;j*@S0`lg>q}n)V800F<u-o@-xmOe#nYt?wHq5BWbH{#rBQ$LD0X65pL`82Kx)$8qj+YmaegIhBk1Uw`&AhEh2QR;d#LoA'
    '4>%o(N1c40g@=S#PBvM|b=MfY4(0S-SHpYT%4%R9Rv%_f%=kCkPseJ|o^OxtEI-dS-S#@EUP`@ifZ^kPPlSGXGdfR4T-fM9+s(GK'
    '{z4Ldi?5`&FLO)^giHf)uCGz84POJhd;vvA(vBfIE8j?U_$;b>>nYNkgTLRE)8$OZ&OaZ2vquVgd)h==dDBhrhk`2!@b}7Ak!$5!'
    'rR+QbB)3a}ygVtPhDPY^vs*?wTaITzzj0@!a#}hA^z^Pzi|Gvh<zwKuTC~z_9CgpNhWP?2>2CU1)`zI3fptEz0!zE1A{`X#Zm_FJ'
    'f70E!y(fJG`%Kxw;^6C_G?ZK0_W5-g`e^*SZ<jcnX|WP&U%OHsTJ@?h?Wt;gJKY@zjFH;@yo!Fe(a4_7ynaH!QyNYOSB|@BRP!27'
    'QN!KPEl{uW2DVOR?H33B`LG%tg#8@6KG&Ps{&Y^#<<4kkVg0>f0)y%G_-a2YJsK+dC+MvR{*2jx1BCD3w)H7{j|2<RTQwzg7Ab9i'
    'eg9B-n!6=ENnV?Fkua`8xp#BqRl*6}=HZHG3no7rsx`HDSXTctnzq6RbVGat;kw={qWNi2QK<TavViSoo&M^-`~5y~=9A^SlbGKl'
    'm2wr6te+C&NOa%{<PX%hsd208ZGEXaPp7NBcKuqpT54Ic2rVxJT0SA&{wLB@JOmgS{rMdG!^#dS@V{K+3?DW*Ej?+w4qgl<gYa@N'
    'CW3l<;C4S-6ppY%txv}1M;b62r3Z!J<*pa&h=)5vROF%WjPL%NCo9zo4;<y-VRA^>X3oH$WktK#(<G0hGkHC{z3HuX={A)@Qk3D`'
    'YK{I7!~A;-PXooqFLc*a3FDwQxDN!LOXFX?1kBmSEML+io_<Th$=>gcrff`R6w3Op;XIt<tT{{k9e3>zmKZjRTFq$^o2jQB%&i?D'
    '#0$D#9fBRz=mTEA{hqV(u`I)n`LTb|)m_}I?hd8Vle#~V^?ru*4(-|12DNp+(K(Mgm%5?h%XQgB#8bGu&Tif7BQw3&+Bg8Bkn=5m'
    '{Q2<CR_$}uN+t|Ur{Bmpa^p9$zfvGOt;aPwTx)kgN9s@srrD!Ez10^75Iufu&AvDvZIm{P_1-{y#NYZPDYDOBe(R9yT|1f`aq|*f'
    'duLT4l2N#9VWQOM5G8sz`sxgCqroLMwwnY6%`&k)#;hC2us+#G(6&j3HORH@^J$}3&VPQRRl~&&BtC1<_Iu6S<ejsbJ5Q5Qy|v>_'
    '1B%AinZIv&rF_A=^Z<X@<pKNgHlywMynPyCJsWoX+pKf&V>=30KU}Zdoj9oX2Jy5$N5}nKyv4Jtl@|@|UbW<U?*hdu#QFv|Z7}%E'
    '(PQA=mQIfD-;X05Y%9lpgKd6lH+PCnR`7N3JGXl8<aXs;X#T9xP(KP{9bB4d3S;Ribt(pUEHYs?iou5_n9Z*dDUaFpWIdkk=k@^g'
    '&x=&1Ml%sDG{t!V<~RM#9|w(IEMzV;q^&`|GxV3qUTXcirQVm7=1`c6pTg*yB#;~!ZvbbZ#6*uGIx>_n*v*bkj_GrQk><Nz<r;q%'
    '|N61&xdN^F0?`V+9x7%|SZY=;CWWP)2Zl?#e9e%Tf#ti6rjf>jY%G>bc=H?Ok0gI}0dYsJ@<(SM0On;l60GNMFRMDp^xFJ(9JU})'
    'g27G{VP3d4CZCgKp9cL}*Qz`8VP=|uWc8T82Xq3|`HpU+*=AmfFMPPvog+Z|>i$6uBllN-&_x37T@LVO*dA;j&pm|{nc|oRY&%2O'
    'pm8@t<o<CvQ4z^Qr!#})`A|75H4m<K9C6nNA|83YM$`s*jiw0n)7^q3`xUouaElRkF1J@`6JgiLXP+TGb8{Te+yKf92W+?rVO-8?'
    'f1K?T^_UYc?M2=ny(%t8sMDPP_Yo>wD$9Sq?W%bco|~tWe!d~OvNRPfxa(Z)e$Yjf_oh3!G{p(}52vYNcP^Mc^1Gee+`7Y%?PkT$'
    'xJ$jylfm&#N_DRM^NDRpA4HxkOh1R;7S3W~Ozj+b;?v!p)_uv3jF^UEirg`5GfgA|Q6sNW>(KfwdoIEcb*Sz6;rkLD+s%f29R8ap'
    'Bjw$pg`b>GNxC9ZeF@&4{HfuprD<)scBZ2`6h-W~o{S#UYraRPt;6XweDQ;zKCLOCjdw<ut5P$s*}dli>-<;u49<Ib1eKHN!3-RB'
    '$Y49^1b3>7T`*zTacG}Md@Y!L-*is}7=5C?m3HkfppbE!Y}LxfeZ`qno-e=npj4RE!RFuG*TShcM=BS0Y{H#T+$Qp;G^%o!VeUWZ'
    'GEpX4_4S}}pr^9PXJk6dq<!Km0SHGY#T%2uXV*#w-6vGuvEs-3w<o>&81IOKjt!~x=S>ir-G5}u*A`sCpj#f_7st?D|KX9w_`sP;'
    'Z+L4jTb0G2x5B|<zZuk)41_R`?TRsCDgNc5!RLlk34=e5&g?zTM{{{gcRtDp@`(I&9j1rVOT5o-qzJ<GVA^ohhxxQwbKD)gb6#wy'
    'dg!vf;j7aCH>11*|Kh+mk@$TvE#py*pUlZS3zz%jA{QxJ^k@4;ecfV<$^x;y2V{?$9XB~eNjrm%jVSIH?sH^IPA{78I$>p}8TvmT'
    'lRh<G4TTEk?yaaNm4`~lDS|eYA!`fD6ayWsA7DEZ#<9LOp@{ix&1;iUF-f{HCVhCjWP!)}fD-D{+tJ+szj_o#fNIBtc;^poYVLDj'
    'mRss=+lFDzK$eFhz8(~_IU#mfeY;C)h8Z;vrDqkcU(iy5>fG?6=%a$sK=Fa=5WW7@jc|9ckm^BJey{ETL~b_WfaT=Jy!Ub@)z!VJ'
    'N|S?ZCnh+J3d*2|7iRY)>hCaeR`1OXF7WguuNJF0*j2p2ZTZ88hk+R9zni6&{m(w7?saf{+!I{!3iqQ9y%DGFk-3)@E)yMXDd@#&'
    'pSLs5e=Zi4M$?S<SbF|~BLYo694IZmKOWVJYO^_IcfsorEw8v;f0tse_NI~S+WPyg`UL)f2-)xKh<rI{!J5u;RS<<YZ~1<j9@lrT'
    '<vXqK6)BYmG!do$=35;9ogcIKSuu9F8*!g@K2E~H1-m@hHQsm6+*b<qLuUgXRI_uA*yhT@PXUm`f9m^BX&L-67PXF4vR<S0g8%sx'
    'WaQojIoJ((-9^dkY(G^8@Vm7#x!oYI{g0_L+fkO;!tk{il^}*h1P21nD2fP(fZ~CSf+!+`pg3Lo?*D{uA9rG^i>kHWXH8}9RI5QX'
    '&d}+ew4b%!7>mr{(Ujuje6_UBmc8n7?!wwl`gTg!hn1k<dGm7?4(QQN(ROpb_~lfqVXjN3nvw8Lb<n)>uNpQvM3?B?ovdG98ZE`x'
    'qh0TY22`>}I;!Qj&+~BntiFpf_!W!!eaj94q))bwx*W}pj;b~j)>edi<%s8xa_E)KH4`h=*#lDTJ30M%2Dtg&ULw8pn3|$}F9H3g'
    'YDyv^O%KDrGf~V(w8LsrYdnta?wP<oAyj$|#FH9cuAzaMVq@~G%|9}*tG712;p&%jlQZ_{{!W7OJ?@~Nv1e;c+5?~TFh6$7yCU9K'
    'AOC{KB<&HaF0{hMiV*MkE&zb<#ivb`u+dz{Mda!UyUv`eRXJhUf4ojCznFWic))%cc6*bVzN}2A_Zl(27WF&i1>@PRI!oLz?^Lhz'
    '-Z$(YI5pf_a;eXgwWXj1TdxTZc9UgDi})^yYHvj!A%X&k$|!&CDN272OCpqSuu53$@8#7Heq41Z(4~)aKcHEvUG<mvf}wipo62AN'
    'ah)Qji|jj2*4f?L$TEMHCfnSoz@rp<w%JKHoPNh^-nYBE@ur9qAl?Zptx2n2o2=B3ZojtI)p|nam9;APAO`+8KbtI2&pnYmFS|y='
    '7R#tP;WgLd**{Ta=sMOI4$DX{iMnf~=<|7@$T3x=h?fa34?*lambOZ-SM9ImaVXIk(!Fc1uFk(~d4DrrMi$c`rzdAl8)?sQOd-jE'
    'XnsphNuNb)*(&C9bxP&_c?2D7mERlnxVo?H?0KvLz|1kk8gM+MKTN}((4X>0H%k@AKBbqMl-&gw?3{$^P_xY_IE5kh_@K4dxroEe'
    'p5v6lu+Fkk9V)*J^t;k=wWK@OX{wAj&doQu-~|hHdqmy7RZeTD@@OBIracN&2k(YlNk*9kFZ(AXqD6bvE8@zL-v^GeT_0+rt<yZl'
    '8RB=p?_BFf_C-ES>+3_lp^)a|gR?u!&P(9-wupUc6L}tSF4r&~awOrA0^rhIsC?n)IadH59dWnH@2snzsRuVHC#qKlb%$Std*|q@'
    'YFkxaNPhWsB!$^ly7%wYHUp8YCTS)^ujHuR2QfTmsOuqU6kI4c+VO84HJ9A4d2iK0dQ0|?PW8mC?Am*^_9XOEU_n~;`aF0^$#7>O'
    'fv141HqB!-cRM}`xX)mY*O%7sWE6cUR0a6qWhI!j!p)xU))w~V7|!biG&qiY<GuR+f${5!=Fd6*$DVFAHFrB4rS$#=pb}3#b&|D<'
    '0vGf@SY`5NQMWBL`^U=OK-pR9b4u2l_eM+RSlN~hCi_PF;Sd8F*dHO(;z_DovwN#NSy9}pMJZb6lr8Ql9}mvs-b<R!<twTby3gV5'
    'W=<vxaN!IgyB$0P;|tH)I`>FnlqQaq?0QFqS9ckIP}Ux2{w|`LE9G4_f00!ApiJ1!#TR%){RwwZv?33g%-nesh8k{C(?l$;p6+Yh'
    'htEAPg-SDl-Iw%)T7PfA{4+-yxX`CuwbTqV<|q#8Lx7m7dw)5ogMnIsu@3gHp36_$&s9C{8IKMUaEG??>eq%FSlwtZU?WDS%<usN'
    '(x>~+Yu=ve7rF)ECv%K!1^VwZI3%i+F>j8qH?DR)qpc#oem`dSpIla}TQOM>LAN&YxVU~<YbQ#hm#5F-?{jMF&z-bQU}nDcqr4P*'
    'BKQiEX6=HEZl1OuS%fkFUTFIa>qY!mtA2KTIg8gHt5<1{yYY@Z2T^VQzN$a{aEDtjVKX5k8@@Ic@x3gp-Xt6?zFfT9H;?W9E!EJj'
    'fAX&qJ!yPrjUpe*8Y!t9mOQVI-9~A7{v7sdr`mf4u$OaW3bgw0ggD<k%F(mOO-$U!RF(|HMBMU$eeVXJ^jv{LK&KBrG6cSbj!Kut'
    'r|QnNEpV_=16!f#K#xhOms*Rbs;d2MHe2*6;67z4(4ef`uJ93yb+;-FRjbwb+_>^+R^eWCW3oZCL0Y_Dm<#7qHUq=p;Zhyx{aiM;'
    '&AJa%J6r(TS%<E-lFD4Yfb;ymuP1H&-JU$zee1D+!_Ib0e-6g>eds~AXEx7}&Zp2N++_wGB>|GMl3~+}ZZ_Us^#|s-i)nnJ4@&Yt'
    '>DV)GfN_Px9jd=yt#74A;7o8>ytj|b`_lYg)#FlHe+QpQr?3yt%dG7<dg^S|=u>yvX!EfD)71UTTpfr&V@aP6$t^W5+4FLcA`+5`'
    'cW-`Ls1=$!zoaGNui)$q&G(<d?ShDSkr#P@@~A=#nb;UCFu9ACde#b2J`2Wm#i=F$#y3bp;M8tK)IF0Q3Hz*p0$n-!&Go1u9#U~!'
    'fy(!lvZA#?TYDFN-mN`-_|}qy?nN5zyHaqAt8SYK>dVJIpH^?lfM8b-@(aF`PQF6fso2(8&yM5<H?%7w<#w7#htvFPChX%tfJMF='
    'P_-5B5?%4V6D`QNZ@V3&LAlj;i!my@YIyon_$#AlOdqwuZ?!^sV^p{1Y#`)>9(0K>JojFshkK=;MkD+#3qNlS^%gqIZV+yo(xSf*'
    'UfXuNJXi%h)*P(YLgVlNk4bwPG$$22-`rb7M;I@mQOls(t4&oF%dHOjX~0mXHX5v0_{}yc&g{-YW&rZ+EgxJhTzgJ%v)*(wPBZre'
    'J(PM!sYYDho@}So`i_#6^ir#&)-ajsVR38>`<2nTHOw10a$^h50w&57l7j5^JTT2^bx=O0myHpO%jJVo4aeeVtaZe#UQw#?DB0b@'
    'qiYO~_KTn(v~}Ga-+YTob|0bnT4EUSqKo+&-L)VJ4M&w~vpUt?r`486fWDa?YYuUK&J>+-(8WhsmClcN+JMIPx|d7$4jvMf4HhG&'
    'e_c|%Y|UZ2g|A$sh|2-+!Y-}LyOUodWn#xJhF!_)Tr_+9_$}~y%{h^-1&{DbHz~vS<|PSjcT}Zur@`siv2tcKZ9TRRX#ex)YF2UK'
    'k8zT5Bx-iIUx^%d{~XeO#=W1f^>boWk2UYmyG%OHpM7?l`>s30h}jR-x^i^}z1S7fJ<HxTMM%ENqR_SFfLc*Ux(wpLZjr$S<usH%'
    'Xy0wlR5o;bQP;Ms?Fqhqv3$4-9rb76dERfC;v+g8&eiZBQmoVeowSl$@2xFRp_fpnU(|stZw!6NV>ZvIW5;fLkKLwPJ*6^8)Xd4&'
    '{gB{n9L$%f4g5R`1)8LpSBEm;-V-d{IEF6u`hLf!rOmghM0%~@!sPO+yn!)K!!{b&<J)P(HfG(~{)Y;pb;{bWA*vWa)~NR_5_N08'
    '?TC2g*>unicjjPIx>u6TCE}fd(b^5o5G~?St^R5U?#bP@a$PJvQf`~kX05aaTXjv|dWPdpp|jfMeiPvx;bs5oU7MRKkp59>5Fc>M'
    '`tvg4mA{K(yWMf$Mv=$Kr>9}y9^wu(yzN+TOw^m_ed9iQ!Ty>Uu69aAF0I#w3?k;`)e9QkN<N)0h$$O29`55wyiVYnU%!HOXA?&<'
    'P{jL67A~xadv}XIh@a@Z9xi>4ZVQ0AL{?`!D+AAYh`+6l!LfdC0kq~;DTLNR2sH+~tSL^k=5|`1jE6bfB>+_^c*xYgb*sn9*5l7I'
    ';MuqnMagi13i~u}FR8)r`ASM!w*$nagY#Ste!cFi!+`Tar6!GM(lB?Or*D<kZ+I}PgHciMDV$oL6Xy&X9?C!U)(F7GO*O!VXf90X'
    'n)p(v6~^?Oos)&T6sf57{t7e9(~B9m(O$}+F_HBZzede7WwC?m#eJ(RZ>wn5tytpd%C0wNTY<uE&9gvrKDDc^LB8gjHS-CkECO>o'
    'AkUhZ_V^uU3X(zW^0lU_D^5D1U!0^3+xq<L_t$v%Lq0We00vJ^5Xz95w}jp}SN3ehtY9p0SKKSMWnQ(>3em%@jZuRzpXu}+9<1;m'
    '?{20y?{c)s>7F#IMf?G}$XC8H2?YtM;fK6&zYW-C1;(w-+N~_IhIl*#ynu^j`=M9Y=|@NUWH+t%EKNV+TPTwS2_4T}vgd-soxCpg'
    ';WYq$&1QV}7xRGphNBH-FKXXv?`FiKt9<Lq)XU&Yy=rZD{oCMW$^NVjUA>7FynLBFEv0)4_TSk%#dP+m5#i+DTwyK~o|K0^K;uxm'
    't*shg+C*@d(SKpSAa14c;a(DMPR|6(ZgjkR4+4Cn$@$5m^QZXmKo`-7&4ulvUB>&yh21H^^io4&`#}w*d5T%|dh}$HSL18qhotwR'
    '^7VjnFF;`K`WVUI9RaTWU7`$xc4>b*n&alhW|A00_UkG(oOO!tMhvakumCvco5m9UqTkkOQ4+!~eATHX0<Ymu+2GgUF6;1Txsgg7'
    'vv;)at;SF9PwcJw_58V<K8fR>2olq$SmaG<duKn=T)0-I^QkyC5K+5cl<{F)HaacoAds65-alxHRJEN+dUNz4x}HiBR1NS(dp&=-'
    '!td4@{h89`s?_Z+i@cNCJ1Q~RVPDC1MvbL<?rgq|VPfy-Zr3JKb6k%~qfHz(0`7e3>Q(pw;q~7n!V}@zSlgM70GkKr(Wj)>cRItO'
    '-+x}cpI-8mm{vC{t>l+WZ??W_&Pt}mdG8OJ9ahm2{9daivoa!<lyORAVkqrWVEE2iCrrA@lz$RL^UVa~;lM5On;U*}G8uutngOmJ'
    'sr6_-oz5+lybP8L)E!46#AZ!`dpdQx5}xA=jF3oYCxuP<CbsNDy`;Q0Qf2DY4+y_{Wrd!!Wqzv8usQhaQ-5Bw!Xg2oR^<-2)x^)a'
    'Q#n8iO+bpF5zOg_Q5d!GKyUSR`pR#33(l&%?!$hTd|vLPY@8NF{-VTDmxbTsCjS1q!v4I4k@#1#Jbg3A9`oq=G4PX4eavswB0zS0'
    '%h{pT>$_*JjdOanN9LTbtHNsT{r!XMUD7Ge@1Ln#J!WL(n7Q(&Jj%lc&qBuRZ_5^1jFCfN^h&tnlW`}s&7WSB1ULG3xS@9P)_6>7'
    '=*#Xcwo9ng8GfJNq+IBz*cGz+WBdqD>wa?SP6U2e%W6AsP5UYF@zvWZKyY`W^5w`Ck!5WQZ?de~?8N#+XH4)mDXoX>&BUgG4Xlr1'
    ';g8$<jfJdx2qDTcK13V8WYHWccWOU5xJs#YY<y&d3Y=a_3_fDiKxgXZs8yT2fa<L*7za-2&F^MSWP|Nz!D?9aNdS3u1ED3`A=u^n'
    '!#2WRyLy-V+cv@28sFDEYF*lBY5BRX^got1LVlgq$r0ZY=Y|Vj+|YP*SU0NThHa%-&?@f5B$Fll2FmrD=nwmC>>1}@!>#S9eH*5H'
    'q=EiwI?E;v5Z|?X>EY#{8S%dX^7Z+EEt7KGE46BFmt-o#CqE^EqR+DQp|fYD6YWiWNGM$DyuvHGo{iwFvE0S<jwnTnw_KOKX9S#k'
    'tF~6}qhVJN_RpP@!fG-n%*QOB+n3$Bsyx00cP|i*vQ8>CK?rJf#|cW3P=#7<&5^ELtyWDXqt@Zc4_dvcm$*C9<d*|IGqv*OLAuw8'
    'S$YS+;#)=8@DrA_VX@v>LvlaMawfK(c(Yy~-q2pt2m5fp6&m3SaKRCMBwO(3Tp?NQ=yKqF@*UMesjsgYwL*cL6l|9pZ(Mq&xcE>C'
    'E*yK;gzWP>*5dE2?_p#w-9dutd6m%)69-{>=PkSF3o+Cs#r>p5&U3k1^Liz8KJKhA+#Is2#u019aGS#6BUISQ0oT?NDS3}C0PXUf'
    '{scyTHyur>{@)d<%KZ6W*+%9ghK7+e59qRR8B$$oWl}Y)$=oK5u}pZ$$r7|K1gq(x*xwCd_b-cY)EIJ6a_>0Hd-hx~r^dD}X%+C^'
    'bNl<{v#V6z&|)F_!1cCK#_~Ek@55u(yhGlXFmDjsc_fL0eka3Xz0V%l97bflrYwQJ5*-)XTog7(yV;eD-l`Ew*;@J5gBZ=I$5lm0'
    'VvAm`OUOkG^Of_Rce}}e`0W(&*JN9^;^JOB=JeT2FhwQi=(FOOk8#ZzLE`&o)56x=D7$1DSW^Kd)ZdMPYo+xhz&+}mEVZWJihgG*'
    '1OCiNek7-8XVp3ub}|v6kpoGwaFg{#+in@3_N{tv#a7AHuD9B~@#mxLPUip&AL*n&?6zNsc2leT?-Ys@9eH~BPp87~adje7@E$GV'
    'XHJ5}6j>WLotfb*OxtZ{J7)o%JZn6xc!t}}JcZ+!2+{t)aj=+{y0u}_ZnVOY+G8tczXn}+`Z7v)oBdw;Sw+7zJhLb&j)ppZud?Hr'
    'zma}jvA>=;!MFP^9jB|QJFahj(Q8|a#z1qTsx|v|X-To^vD2+r379j`g_lVidgTWFE%fhWW9_m^#rplN(pzGB(>*gAGag*x%U9DM'
    '<+8NuV`ezrAJv)4Xs%G_t6oFBn}aI7DSuIRPdD?*U^fH~`OLc%?<J9g@qKqQ(?9F{cGOM#;nb6xyTY-cO;@G&<oGZjl`rYsdRv;s'
    'Cll!x{Z{X;0Q$)sj+sU8J<RPdnJpwpp7NujpFsxqDHSg3x@b&iIaZH!I1KBqGQ3BTci8yHE7J+W10uoKfa?B|*O57tR;`M7jtB)}'
    'D<NmL_PzGskLnn(Iu++Z1%HiD<?Zs=`0dQC{+J%P{cTJ|-2ppku2n$o9MV3;uCArtCu=Sjmf|48^O|i*o0JsVyVF*)An;TEit6P)'
    'EO=-M>g{LuApno}^s=Fj`zeg3ovt)8IC@O3-Th;N8n<$<&z?8myb8r3M;mxhdu@P_$XLpMJ(X;4-23_TQQy^zerfJ*t)J4gD?VJ&'
    'AYr`JwqEpL*LE8rKwJ55ETs1Yn6F#pz4^)4s{md;wjG)Y&(sA@w;&0m$!m+Q%VwPf*-<eszO|Yy*-aTYen4w-tI)k#KVxt0n&XEN'
    'Ml-AH)Yi98Uth99$-Lj;yUolqF@8SfPBWw){OXVg&B2g&6{PW9*+pEgiH&1jvM=w;xVc*N)bB~CjlPwR>Q2@yX6pvie_|)}EP|Iy'
    '%jm2uny8PVKIDHJoVr_+eue$CVo6+<r){NiE$q(hCI2bL!S^DWpmzNB3F;sZfvVAWOlPg7ZI!>&>D@hFD|a<|SAH#_#+feY<ji<='
    '@NV^m*>6`zUIpKUlC$%|fAd!0oznTf>TW)1j_TR<G?<I!Qnx*}XZu~Q=wVYhalJ6}u=zAw_iOw2hv}kBATX5~Q+X?(v3;z~$?N#G'
    'l~GdE1<8Ri2ugmFWgLf$)NHF_fgV-iD_iB?cj=?ds%dEe7)cd9uD!va^o%BVX*AI|(dZ)?zHPnoHZ}0i^w{y5R#6Wl*z#{OpxSLK'
    '+Kdtc7{wSQUqby{{~oY2oc`WWaDW<)2QEFh-oBCVV6Kko13Aqz>>;tAGPb85jrCc`MxUop)YDoCK9fylsu0yLFdk28&k;T6t1r|X'
    'FGfQM@wY_I+$sv7ZQ~vPc-w~!*W=8FyzPOrB=xXGqVM~8)E|oEbQ%=-xBK1_8{6aG`Sg4f77<{^e%{+H%Hg56#gQBI-1nALv_Dqn'
    'TQ00$O<OH(yklmc=sjGTyj%Uj_N(`wUHiQ8*KTp&ZurM*jTzZJ)E6Ob?ALE1yXKo_>dSxFrUB-V&{w=7QbDCMt|!&}_&zXlKc(I2'
    '-89bM>~?#Z!JTLZ<3+Dx6z6QGDT_`W)$WT!2fB$b2~U&q`ukak9BNIoo^^WOgAel@C&Xmiry-ddHpV(|y{f0u*c@Lk)HfTySz!z<'
    'ZduG0aoSH?m`Q!B^Fbxvz{JvMQRmOydE<0>R$HEVnoT;v@hrB_e=xO>el4U^m)pH8$9KauzW8Fb=LFc7#S_Kw*S%{O@yU#83a_<g'
    'b~-s5O?aiJjLUD*+IwX1XWOm@f2M9p(><QTab}epm3_++;MvS+mDC1k*H85W$YN2&JvM=@HkXUI5vb3HMmP}qUP>mp8*ar7{I<@?'
    'g~nWdC8G!BD19DR3jj;)z1A6c8}Ji!HI%gHR&{-;w*I6(9r}SRQJ|?Fihc%gO{=2DP^VM8(6M_z4DnU$UTgC6t4Jip+qyH;YF@uL'
    '<9Kj5s-8!{%-E}K<58mTQLlu_qy%KS`?^N6^HC|{MjX~qhxxt~tH*slvX3euxw5$P=Z721QPU{zqD?S;m2F{SCogOhM+wg_)VJCh'
    'oVxI7^5ueKcq_y6QF&UuH3~m3)Ql;AR7Ky>weIiK(n<l%-aLrutI8KAy#@cpPoEtoh1tm|t+_K_6A1QK@s%t~mzdP&&hj{nnAKq}'
    'd+ofq7mc2p_U&iW9V^Pi_{HKu-{oFXL6*;Ro?j`I)GG)g3y5J?7&1^N=9DnQS6RPzO_4h_)=jb>h|swicT38XE4~}aGu~uE3+VD1'
    '3q#kP%FyzKxD|81n{{f-_utt~Ho&Ok^bzitZIuRZtDgs4-h{ym-^715^k*iW$G~^DAbsSE^Q)H`{bA!tzXKr_Ps#oB<B!aVrWkdN'
    'W53nne#!hU(#8<&|6X%8V&sE8P&UMuLiRf#?anoRTWtUXMy~IdCRFI^8c^qm#tOdADpM6<*ppe^t<lZIFXgqKY@S|1(wOuPx{^O{'
    ';`%jjPx%r{po>0uxGMgyKdg;P(b4<7BCT`ehJ}9<h~D#^#JSOzIAnW*Jk4eU6%)i{lf3WCX0vezZ}ni!m7dq0H(N;xht(?VUgw@l'
    'WBD!DUVYVgl595gklF+<>coz3>~+{c-|uSr=+KK)t?nutuAvJ2XSbn~&DpLk)Y)z^TH4S_K>H?<d&J{lx#bUbG4itdBzYq_AAdEs'
    '|5c2FkEzr6e06wz7cVkR2D&aVsvx5G0O4S4cx*PhzaG;PSaJk#K+?Ia+wc|W{~5$B*JJ?>@i)o^pI5EY=+9Bk+l8*49M4T}wmH_H'
    'Bhnz&xFMWxweedYPW*!@XFZIOdR1x7o+eKS1kPa<IojvEt4@KoMM4QVVwa}2HE&eRi6dfB{4T4|d<_}hobs^OBJ<t5K4627N;yoK'
    '9ZYJIQO^&|d}S>@OH=45ZB7LE?0QM>YXGU6$LJ4qzv0)qcz%6cA}U4vA^qkqG(Yfu%TR=MDGl?zzdh68h&Jg}ZTEU{u5h9pf3Tz8'
    'r!f;AClWIV6sgmjJSh0l^hXo-MV_`3vk8|8px|Q~Z%%45=WIPDv2ly7V6#lW-`&s-n!`rKdTnvcEA1NvU~}OqPa84VS++iUCRX?z'
    '^6~qN>Q^!a?M$le(e+=y$lrqA=XORjHStO`_LcE>G(UBiE%7`aS1TxcV^e0Y48Aq(I;abgvFUb7zaX#Dh&w;ucJyt(KV0Zpz2fI!'
    'T?C7IaHjQvxSI=o``qT$c$lTSv`AyPlWV~Rl_st4@z2{$fm)+oZVpUQu-u10-uvKXbLwK1yjkAW8>RH`8%^RZu@wsY+f6nva#o+s'
    'j0$t8ZJnQ%9@6M+z_xvSlWObJuYm*OOYH&FV*9o_Lo4Q~<dj`|99~@Zu!q2Kcz#Cnx|>XZS#f>`$JH&7$i|h}2hHEvnX<3iJm~8a'
    'w}m6$N!La`S8cJHlHd@xw$4#@dMI$_$uzoMdCY7l>(-{(s2{F#4DUK#k;j4GBZ$!>Q&WM@^Jkcy(ylKM#4)+t56#8$)*E`Qc1+Fl'
    'YD*f<loWy9%U$ogP8j5BG<2XIF9o)GG+*=myMb1UxhTVpJAFPL>%}G{^y7~TgI)t*R;LcM;pbcDMVulm+rd$#1at?7I>6y^Yz)Vb'
    '@tm_)pH}pe3H`n=ojdG<X3PKP4Pt%29zt-?cj3cg?jo;BSxwE8;nr(9+<@Zw?$1Rk?r^wmH8;Ji=F!XV;#nRv(i$ht-!!@zo{wtN'
    'J^Z;hz4vd9fZM;BhpxHPAAT-P+~5|fiqR5Nzx+`?SNC%=tXi%Ah=#)puKR<_)e=sfA0&=u$5QJ8P1HXqhEB5?JnJ)83i|hc;Z{5n'
    'Vr6|!Mm2Xe1H)UoN2{d6*GF$fE<0B)jl&lkD$D1m{yc9*L+sq!I{^Oy$ad7xm;7@rC((2-6J93li}@NJZ9Fv`B<Q^&#!>4yqRhm='
    'e?99=jm%L~TeUI(+r!GFwP=9pMyL-iRQ<_S!BOc|>rJSNzdAj-_Yz1i`{kNlaA7~FIjgmOaF%<f@8mjgsZ4K8O-*~j{ELsGMN98i'
    'TbIr1L!oE;GK~U#5ZLRviNvq`wd0vKNUO{Rx*m<{fw~rbGyL$E_yci+EWtZ%w%P4IV~DAYCTB$pjoEp4W2&q@0w8_`v<>(nYcqFj'
    '(sy^ORKP5|?CdJ9pVVIY5!T~xQ1oXt!h0IeFOi8!TYk4?<(xsWWjaRNu2&k124vQnGqs1KMoTD_pVf7ZVdeNRjKBV@7q(A>p^Cm&'
    'fKZPHKKG1^yc2HT*3qThy1eDCbSEgTJg8kB(4Y*092-jtyHRfsnXE2*e*Fql%I>lsGCh?EQ(u@qB~8x}cT@ESwB+&8yH}hu35<|Z'
    'Jd(dbOVZJn90=|et@`5y2#GPeoCtoJ!T5vvJJo@ps2)h$W3qFWxJN%Pvu~j7M}twcVOu{w!ZEtI7fr_eI_llKatAJJ)CY%Y0HUjI'
    'Ls&`JJlG+=byaCc{=yite}T>A281{Z3ri(Wf`;Z`J7JEirMIrd{-#9Ic(Gn;cttl=HDwlEA=}F46a_e%&X|jS-o3xej$Ew^wU=rU'
    'W&E=r;6x)yKUZ$Mc?r*xx%)LB>6%z8t^a0I3Ioz&u7rrPi<beQV~A^i5mZ}y+<9NNPut!MHZI_DvE5LvTQRooapK;YL$^nI%|ngh'
    'G7q;8<v$v%wBy$4hc+1&>Mx7BSFM$OW;1&bR_{Uj<h<VUS-b0PtzJIWTa38k*Kl(}pWy7>SV5E`NzeYdBiv{BAn~5)yW)k*W2ry?'
    '^G(>+Q6EL#scgG2`fhO6Mc=t&y%7==+7x=vfw#Bo&Zst<&g}#Lr6b!)Yt^j&B6h%;yC2)V=DpwJPH#y$h4N0*Lx1->^ou(FOKEw{'
    'q;E_Ogd6%`wm}m>@404Ixpn77_J3oI8<8vn#<qOeLiy3$zCOreHVlTlHNBo^;yV76BWC#g)sfXaD(Zsl8Q2E#DZ;kOy9<j<o|LzJ'
    'kXFZ39>f)0iDU^N8e0mRH(h3Xu4(j7(T<48q;$8_d06Frjx201F_C+vmXYP6P8SD*N~`?beDHmz0qS*6Gtb5hlJF(`3E?f<A3V5{'
    '$RIx85Dw66H#4<*Fz0L~B2oon&F-FBt|kWc2s7*sPl~zYgNx%o(?!3o^xRQr)#G00(j$ywE!n7X&w$q6j<05$_8%3UHN6tJi}h$*'
    '({<2meT*-*+Fz!%aNa^SS1dsZUg%#@SRXm`-YKW%Q$;~hny-%@vFY(~xm~m0%D$((Y+u7K?=V}QP3AyE)i;Lim1^|yR`&-;f4b(('
    'C{?jA49HS3-?Ov2OhEGM{|VK3)xRkS4V>QFLA+Ln_`TGs{)}VYZuz5z7(m3j^&Y<QkNuS3%Ek2v{_d9Udl){U{no8A{zZOKzk}r4'
    ')~i!fdrm@h7k*kZVTRHkd?`JO7f^puKYi9jH^jWXo;849JkXCL{mox3wMtfF&}VO_^MFq+5t<QgtW@N2SkgN|b?=}_T{$r1iF;nJ'
    'sc(SszK0yySvjuC`JqA`4vnsVek+gJW?3HnNJ8#Z{(Q^qesgg4bd1N(-QLPKd{H-;2*^h^X6>;3-W_`T*BW@<pC`}0@94Nn+`1Us'
    'sde46DZlCIXnJtc2+P$L6&W9#EoXXSFvCWTeB1}^blFPjBJR27UsDXp{OR2yZyzS|LM)s-6TTF1mr@tv2l}3@U0#2{YGkFuZaa#%'
    'O0|~uo7A&4h-(?@Ob+a^jipR%^(Os7S680s@^jO=?61i**onfP)S-E(?NzJBiwq#CrC#53?S{o)2d!mKeaTLj_V$|;J-t1&fkML1'
    'VTsav%3Sd(j}|<1&;}<UC1Ubk3**o7PIivQ<N!*OgafLc!%3|ZV)P$e6K>oN(FtGdTv5HO$9rN6YD~w!)SUc6354J+_q;%~|IK4E'
    '*TYKCiAzxn7C3x(_cZ`{Z+qls#Il3R1lvu@nXNNp3^zyExNRqZgT)TzNhf;;C#Pobhm+;WdhmV46jkhlSi)*mJ^3~H=N_4gZoM%$'
    '#uQuLRkn%XXZHwg@@4?KPnI6pazaJXpsa*WT|e;#M0Gk!R@w|Z;AGG7<kOUjx;Axh-SE9L0)(EH>|<cjMeAh??ADcupTZrU#K|*c'
    'RKUs_kW2MHK?YaSTeLqkI-?8Q#dx;4(GRDN;u8*n*Golx)Z>iCre!fD!jBKc5^`V|uFjO$zmdnIrj9-i5Rba!-MNz6Y<9}4`KcY<'
    '<I!&*-KxFA?_TfO_HsY|(%{?0gCc*7t@M4in;O&SzzEg74!B%6SF_mw@VlsWQ1Xh{e)weDlNV5V^|!P@%Xdw5dlq7*$_x;(|NO95'
    '$aOa)5?`N1esj>~`_`lXLc61~E3$L#vwq{ikM`%ayP-L%`fXVlhCpg~(z0Z??!ujh;__wYq#0Xz`soKfT|etsJ*)3cM=s`Iq)q%j'
    'zP--#Js$ZF1pgD#+OAK{##3vRZY54TX(!)WOmTZ<{qdtxdg$d(i#2D?wF%mDZ+DKC^K6%O-h)oM!Hd4oAgIgv+$)tUVK4Fj{$SJZ'
    '2GlH7`Xl~u1?9=HCR>ly=+zHP<)vxWCRGc;D^IQLD#ND@ua3)z4@2(^2pw=q7Ti*qPG<gA&<qIu&Q>PA7x7NRiqKkgn15jI@Hi>6'
    'RNa4Yq-AG!XE|P>8%I#BsNXE#%&@e{|BlDEU%me1a6GdLe!Fj4Bv1pS<~{gU%=XGLlz9H=x$ohwd>c^SYY@l%VEyoC(7xM2PRjLG'
    'y{<diXijWHz6m00_Vtvw$uKWpVmd5%Gt%L$TjCGt<uoItbE1Ih#hXR%>-sR?Dn#{?%#Q4GH>|Dt%uh8*@msS`lj{dpWM6E4KgRBx'
    '4kicXHxrJ_3RKJ;7vU?IsP9eXw>6c|Q?&LrH@?kijdYO1m_C$$Huu?7LpSN%%qx;5%lCHJhAQ7?*IC>F<YP9!)1VjK=cn68l!~~r'
    'd=5mHY1$1~L>@OBd%oJCs-{o5bMv`(Z0FhJo!;JkX1>65z1o4NjZ>~S7EB0@#=ZR~_JR9D<n-SHd-j4|ao<9U1*?a~>0QE_DA$xW'
    '5F~Na??7KLr)>mM2^cL(HNd-Pg0bp{s5H;+-D>SIginap^bJ-x<0DsID>>Q6UBBSM{5truTYwH-=s=huuuAdKO{(RSS|eEWn(;27'
    'pl?G0HpZgH-u4dRCJb*<sULA}Kk-a+dD9o~D3-v9x8a<kZo7BgzfZwp9JKw3vBB>W{L{<hvTxYFa_O--FFW?c(tp)a<yD&Hb}-%1'
    ')6b)%{D5z`>WY5dSuRlYn@_#h&yb3G``w^RK7d+pinhN}t%+atNe566b%W1-+^#7IQDq(WP;jIsr#gX1>gICp!u_CbQMc8bM{E%!'
    'ap!tRyj4;)o<*EsNF6_0q8CG(#mD|M-1IF1#$)ET$318?$@Wj<eeV0=c4loO=xmU0nUO!oKNFdDzVjYcQ&jkTold=G1t6a6s;D>e'
    'uxBnZ>+#KR_I%E$hvW>1&weZI$!t?$#I#zso)D>aE~nByBU&1>@&cWhPmXQ5RIRT+)3^6tk=!eHdi>^B<VDV_sC5b#`gyY8gkc3>'
    'miz}Azend`^gCq=B2A`XJ1h4pl{_}n$8@DuUK@N^?yJ^kc#iQud2IXZ!+KPzTN~rw{4)V=qTtfEI%3An4z;v8{na}+4zz|>H?CD?'
    'D`TBK8ZKJhB(JBH(`{`g2j!N+S{Ko|uYNjEzO~nlrk+2cd-N*e_QOl>a3v?IY~JKcRph$pGpS#@XA-OuxcDx2z&agBU5(-L;e^_4'
    '&ZFo}5S#k$;s`@ucfRWq5v}QrzArZ$b6e=MSqGU!?0i#RrTOp&LK;cBe)sd8+UM2sbjLaoA$JcZhMotneIHn1wI$YmmZp32x7WU?'
    'AM)@;(Cg1<?Y5+E|K3CK>gQQ$4vIKvD%_oY=NxsC>-snv6QDlvf^dN}ZfYgRP(A;yj8;c8Hs4^rX|*c^P$7ueSdXEIg*L+Fot_8v'
    'qEDi_ux`U_!Gh1|Zzp93D)D=DU~x078yp{_rD&~z@S05T+siIfRd+R!&KiPX{9^y6-FUm@zXFCt_UG5>*YY9{>Gv4=q=Bu7KYfH)'
    '*QN}Qw#mV0v!mV<U4SmLc{>H_I`VaO+9CU35FKgJ^6-G*S7O7}PG^Vwu_t=#PYH}E@=mAo<3-_Ncf1O>u$%Uh@5!7$_w*)sLlfpt'
    '`Jei#!e30A{eD)Fr^>MXK258`4@cXA>w_HPC2JBN-~&+maIb=6iO8G&I#Tm-yN%)>(T(SF?GChGrQMyq!tKLgR*x_5SD1^j43;OA'
    '>beqqU8(P~t<J6+*xLTRho&K-{a`zWYegN%xl4`XvGKc;up7P4_dyOleI<UZw*Dr(FxNjg3HB|>ybtUl1(!$b+qtv`(8`J0wEdDo'
    'Avj7z^9S&lq-B^`6z@J@;PG1K@3@97oeIA_;1{#U-`hvI+w6QN!FV;pU}ko{(m}4bX6=;%G44-JqSSQqL9et2pI#6Eb#gEbNXGpX'
    'cKv|lNosk<KGJzua&#^19E0&5>fq%+B8S0+w*s)$c=P%+p55R^Ez9279R{V(m+MP>8~?R`&1WZQkFI2QZ(7Cvb{ZW$P9HPgrt7mh'
    'R2$Pr-mi$Ti!7N+(o-KR>D_PdaZ2nS6JpiA$Z603LFrHX)yi!`e!u(ICd+iqUE?_X@WuX;i{0Q=&b;(~=#jxzzfA==<fk)PTnt7!'
    '+4pCkVbn()3+FB(J;eRy49Y<4HIg@jKixb--lYTW!?pWnb*aI>>%Y0<>(;6Bb>!P&L9OJAz=^Tf{+04OKV^59Ue#^s4Aa^)AEgtf'
    '&6fHOmnMe|wLJna6BJ%CIa>2vd52Y(r2MoBF5IMiC2Y*6k0tkZou2DciAU#8`mWuUn<g_whdw=He_ZsacD3>SA!GEcv>S>(`G*U?'
    '%X>Csp}gH=2*+76`+L#vbUtoRRM>kx@%e>pI_KqH`4LR?49Pn|KDDYJU^5<g>Vc4qLw0`67WlE%!}d~gTE`Otr&MKcpVNlXD^2*;'
    'tKfhHZFfI+%OUSdKL0u6j2$`48r)sC#y8q`XDFo7<9uK5OBJlDJLshTJeItNQTcGQW$9b)=#`{X?-4q(9t<+O=mXrEn^#c3ZG3>8'
    'mk!l;rH?%iGA7E~x^v#p)!8^KtLgCOTeexgu6%Lp01<TegUex{W|gC7(nPs?uA5)V`c(O1y~ifDq3TN*r<>86gY~Gh?+E%sNUF2I'
    'x&*VmCG3JN40n~mldM*6oc#{_aw9ub<i=zi9%-ynZ?5m(t|fCgUN7RbK2B4gK_HLJX4CP}_&dT^qxV_w$?a8J?NKN=Zb@jQZY6oP'
    'z%Q+=dj96anZ1dK`z|jThXrB}z6}l<A@}q-Ddzl7lfg&@KhE2yNC#T-WL`(M;b^)JD!?pmv~l|A98cUE9J~AZ|4-`j{psnOVeiQP'
    'y5QmEY1CtaWCb5f_0RTTS8Xt^jFUlK2b6uUa@m;D!S5YY*dFd63zI#5ID<RrC0z93vJBkH;rKq24hM0MHEfujtu@MTAKGuLct^~F'
    '1Fz2Lw>2(Fa~@@X@^-L9kP6dy%i+3>ow2UhoOsP<_pQ8UBU#rfm+H8-F9VIvhn_SC*We^S(r?;pRG3kv;Gt9F+q%};)E@-aN3H%m'
    '8Tt;?*kTlV$Mx|8rf=PKWxX@#678;fzo8p0!^?YF-VyU9@{|8K(w&{#siwT+k)SpU4rpw)t5zD9g!i#KGmmH=pY6JD$RkEpu=5mc'
    'AQ~6tWa3AleV;R>tT*k$N=eP@{2Q8Iz0(9Lp}Sm>OLJWX$Aja)cj9rKuM8u4tM_fHx?KK7?O9#8iw<}6BW(0LHj@+~safxf+m(eP'
    'v})TOd1+mrIH!OD(!VbLE}`EXUM+Z>IYm4wov->gr96?*I-S&$Y(Dv|q<K3zFS8L>=l)!nNLr@+ooIpM_+Tv~how%q$NzLmi&-Ez'
    '=Du4EAm8mbL9$o&#d@zdu+bA5^;FTnU+Yx5;T14P@8!9*Wz`@#5e>Sv58d*>`zhe;IM84}p@a2vqypvT<=+07Ke2iXDtHgAI9sxa'
    'gD(}qg9gI0-rn@Dn+6L_ymF6uuoIP7+uXn!J0Iy${pD7-%j<h>FiTkJu=yhPbsn$EvB193oITK;#d&Z-4pC9R186O3(7{Q2J!ZQU'
    'rTnxbrT+<W?f7yUVZ>a%_<as2%6{<He;Lar@Pb-U@0#JZq(<ZWs98quB17ZSM(b*aeZiYx+hyqa`D-cCYK8GF>^D^*A)Oyy*DV5E'
    'XU?*_d}+ae;uJm$j^o40z*_MbTd`0Gt_JW9ypCjSwS2J)@dXSDJ~pnhjMqn#&#X=^az5!iCZ(3}l!;bDzBa7BTic$X@O)k}D{;j<'
    '_3n~-q_-{^;{n@QO2M|@xfpZpnhhlkmIsAhPg>Ea+bZ{6z|C{sX$_jp=h}Xv6_`21QK{a1JhOUyUQISKgH}!UGa^!%DW@MROROq1'
    '$5$7bo@+l&>NRV_Mv=!!r}I#>GQqMa+n&D$Qa?ca87E6!%m7!lcAIYeiFd`N!pqV^;{5u&^jo_*Qm;LU9n`QJi<w#NXyv=+%pS_S'
    '@SAMISVy16pfMdT&$n^-KB3?GkrJ>|t=+llo133jC(Ly<h^1JN%S4u3O~H_E0^}g$QF(Y%$y=*wjhf@QIlhAhXKg(l#jg^3AJj5n'
    'zJ8aVTaru6%V{)E)nv$?6d12s-LQ0@cbwC+(mGqo9PN!?B=MDj4A1uO>am~5?fjt+5C7g>*G_oX>XqScvVBIm>j3L9txNBEt9@~6'
    'E-F?w(xq3SE(f^Qp(5lfZ~I*=v$~R4lTL(y?XmZ3`hA^kZ+Pjq<-(pVe!8*_foOpf;$;g$dN)6$Op`TZ`Nz=2pEA+-oZKqS&t|N4'
    'VH|9{H0QMECkbCwDh=SNac9W`)2$oMiPg#d_g)e<TU|Ue+Nqti_4Dfcdn@TA>+u4%YINA@ar*KeNM%0n4G}|rRpkDdZ7%Xdv>Y(R'
    '-6>_cqg;W`VnL-$=TpRKo5MGA!3Xd!>uCm@&GM5sGWoYN3KyG6K2=5-e1HhykRNV!Vu(cfY+ELe^hB=b#&*2*+iNe7O0A*Dpe+I;'
    'ig%Tdli*iYWXsJj{lDYakF%`%(&%O>n*$E60u}pd4Isw!001c|<r{(yuAEMmU>QC7?d?TmVw*W2)v~nh!oPm;9!kA``KpI=ZVs&y'
    'WCP%DHvjrGwP?Mso!5CajdR(Tqm9Hl`#E>A1jpo^z56XM;BW#X+0fD1#))l^ooaQjkZj?PpV!yEH;4K6!3$Fv98`z*pY*;~FKt<M'
    '94x_(i_SUT8L`9EUVZq8!JC~Zgp<sSq3PjHD=WlaVknX}3G7dI7988-n+u&*!DjGxd5ul}yq=hzcI7^uTKRW0SU_7X_vwog+}rIv'
    's`r}OF!8t13AuCd)fGBdum0M_iq#+0%ER>EJFn=j`;oVw_?+#_IebVMJKDbJKY@L7zc##mRvQDR>yJO>`+lZFQ07MH`h6_jPP@&f'
    'ZUjhbn9^m?eA#Mg))4U`e=KFS*1=pfA6d}T6}NfbR+r<Kwm{Oc_7S2<>F)Jhe6ehYyZa})r~59a9mapq_<Kt}OjMr8iFWGSAp4}c'
    '(*_H^P*l;mT+{PzK794o+Th~#Z-ZL<x)J2|dA1nLmdT&=GMT||(hI9*t8Tp+7`fkJ6;U36zayL>{3i*3GG>WWD=7T@Gu2P}#tgh<'
    'Gz;q`ud_uQY6i*k_8c#d%inX2rXC_|o;OYUH>7bP!Md;J)cF${`eEr^<6ywKxe2|-@6UMi{a0r*R{G;sv<gzB<yl4tyGPu-eYhvb'
    '_K7(&<o>a#mV0Q9vi%)*Mf&(;d8K*sod4-cYSwoKv$B1?hRwbtzE(D0*asaOa>j~D@91m`2kbyRa-|ZZXZ6y$DbW>+#)jdgl`6H?'
    'Z_bb-UViiNw@m1tFJ_woe%J}m06ei&>4+Xav|jN1IsY-DqKFD7+^ZtiX0PwXnf-&}HDD}vE?G5ZoM(cHFzu!jYKRi$phpQ`#u*zE'
    'Wxq-Pt{DWpP~hF<4gY^cU2D_1UK{-^Mwu{XQjsP)=%gZ25ibxDMUkR%`0UU9e_r^#zGvKH+t<3*TGwGWy1%~o3aI?aw-r`3<r$-{'
    'LZiQG1nGXT7v$W*dbdmo^ooL*?J(MiT)mz)Bk(UQvjNZ=oi`@6<35wqs3xFeYg`8MU!C`unz)*kbR}3|y(@Qgw4`qb$T^<_vHrEV'
    '6G+qvf51nM${u$4`3Yccd1(I$SL1Md?R=(mpMz5{u61TbH?V*2Q6)<G<<F#k#*Db3(KMUy<_>tRmVWAKRN!61+e1CvMWtFP<4EBD'
    'NvSK+Aqj)oxKuA$@4a>}^LUrZUVPGPS^wV80?MEpA7MSZ%eO{bJ098BpY|+&i_?tN9u?LFhMMlL+X#2wV+uX~Yz5$g9i8e05RP@q'
    'nHW%eHR62`1LZ6K<5B&^zTqCm(l(qk;6#g#^Whm?yxZ_w4l3eG!3=mO^3!D>p0ksN+D!_>&Lzxsj3ziW>Hvwp6ZYKMq_A9n70R#A'
    'u~LpdN;Xh~Fy;EJH5pgqaeWl$HrQB6s!@FrEn!~H@QwS?YTmPlO5&%q>id*<=r7L1;oL{E`XPBT-MeI^t>1n`({!h7dQB=iC|yl('
    '4<2_kkBpoBb=jOT&r?=ea|!yc?~eZS+0cis*G#bUvc4?QcF$3laevq_66;gGyoyVP{?1`hhd1R_d2re&`P*Z%y9V3O^MHT$x~<)_'
    'Q>wkv3j-3V7bR;#GFVL?)BHzt^a{d9{q`w8ZCcl17XtKb_ZI){w>QWn`TD(=GkBoz_754A^KG-AQ%}g;)Vniplz*nyNXX8{sPKEX'
    'lTrDfDm8b5@SWLjU~8YTFHjKQQ>`k$%l9AthII`-(WQglwdJ@BS<HAP-9KLQN<Z#O<pK{;)PB_VahqgzJj*?cS;A<ToeKb}A*r=d'
    '7tFB;&Dp?d7O@cg_7Ei*zc0(<n6{bTn@*RPlkSA$^)5^1FV;e%w%$fj>%F+`uR+#HB6D|M1xYw}MGc_EU4GGE8sKEPaL<MTU4H($'
    '<Tc1A<j=L`em06a0N(o0s*pivLdTWmHJ)v;O6AoVz(6@{_J_@eRl9WSU#8o)U?=HZZz|~Bi<UBcaA`F9_s%wqwSvoeiJz*F6D{RA'
    '7_PhYc8DA=fdzCD&hwwWs&&9YqjRO`u}j|(o+gz(ggmN$dSk@&%Sts%uwz+->I3M94-&Xy>!F=(x~B9wE+_Yj*>=as@wGNGd0V_*'
    'F*MYPVdWT1)LAwbDti0+QdsM~E-lu2SfA*T7Z316Clpb-EPuX{<{a{!J)s|0>4peMXvC{444%|GZZH?JxCeB15@AR8@P|pa@znq$'
    '(4_&Wc8imYI_rwKveDhKr+#@pZ=T8DIY7kzsP}@q7_|7Aw>`e$_QENk;s#LwwbgH@v##44z(5N_grYy;)(}R{7-f7B+FyE6qrH_%'
    '#mm9Y-0p(!jh_xUe)sirZB61!p-Rji4ptiuulvcN!92t4z3!>zA#{W!>%2zOY!;k{mEpuiZ|doAeAC~>T$TIK_p+QS{YMiRnm^q_'
    'P?wrCv97TiU8@_xv7v)E9Ew2WRXzaLvbT+=i&YH!P7(b{jqGEKa#Wa+rd>=nl=~BU<WtND`=HoqN8F2FpAA@wOl}M7Cm@JT-4&rN'
    ')m*%#>WaDK0iD@9Zy~o558^sEfwNSp#y{lS*BZYr_Eow#>H9nepJp;G14ArZalbq?0CKijY2bH!HSIcY;2SP0udGH_CWdzL=uKLk'
    '#r3W<n;zFh2&;OsxnIUY+M7f0<OCV<`E)3cpMOEf?<&Bh^P5|IaI^8}0IjtyRji$w-r1KmFh!P#Wq!spbwLat*Jm6t!LB(x!re<h'
    'nZi*Dz=%vCs$VlCCUs{fz#A{|5EJ8HKHi_K%zT<TenE_Cq&>`PB+9P`KJ8H9n#*tMyPXTom$WoSn-#Sl3C6Ox-X|BWzSK<yo%gU6'
    'x8o^%CR1qW@;^V-Lc((i?&a0P#>}=)^@QjhnmjR^ZlKV!`n6KBFK-IWE$r@Lx_3PGrO95_6<+Sj*HBC-94KUgciQ@0=CSv0{({SH'
    'v&XgqJst+LzQN*Z^RoN|?~fn1tPJ-k`v_b&R%#vxa>Y9i2yX<+ngzt|LNr#!X<H%%`H#C4z@<-2oyxC|za86ZO&>lchZ`Efm7?}&'
    '4P>5P9jL}8;wA^6xh_&brK|OXfj~1%VkjK=mCo8&jxVV=+0@6|Mkc+6b|V&h+h1RCXr++5{L@1jbLw7!OR*|zm)m0@&cCzoR|_Ws'
    '91UmHjY8_xQT6fhE+dMUXP1sVP2}E0rE4jDhlVD}%%<N*^|y~HX|}~kpl-wED<5IeHmhGP-og*u1DrfVYl$e_X4dLU`joxmyn&D('
    'vQ&}9siM-pPIc?`7x`L^yYyJ$dA=L|@|%>R=kRd|<1q)%b}4*m9@58j+P2S+HS{f#;;Zhgr6Jih@z92~^EjhUQ0@=N=8|RhpJ0;L'
    ';=7n3wT3d~?%1ynWD0iH-zxcO2nr(W$ozQsZ`EoZQ7f}lp6~3={(5EK321~2w$B;QtrnxY_uZP$$(H+0o=d)ts}FNOUlRbFYCk{9'
    '!dZ`~dI?n}frK27EJ<~C^YbmPyR)rm<Kye>uJmt-K3JgngRI4yecn89{rouWC!HCVPRjRtw;Zi9J~cb_-#H8s^n0J<FOz7fvQ=|}'
    'yEJb8>CQ&BE}H1lC)(v|>3Tf#V#p22>gY}1AH{;R$^OYUk0xrr%8gRrQ(nq=P(SOxys4cMU)bJe9ds)K#5CvONJ-qg)x6tmt0g@S'
    'meypiBqUAu+uiHC>r+XGK{tD7zpkAdb?jxX$@}X%QKj!~+-(2!MU;&z^LtOe_jhWmjj!@I5#LK!`lIllTF^T`I3%x@8`FC989w??'
    'p&Z(O_w`5}c%`|WM>Tx_2Sa0l(efHll<v=$6DpkrVBVjGdkdQLZX{>p=Iu2fxr?(y<sE(WXg^8o{(7_<Rki~y9}>Md-#7e;(iZG+'
    'RXZI|1sc4zz4GC_Kjc3j=8otL54(Q7)3ZxiNE@vYw14$`6H)Vf^-P}is&=)&zO%s4wzO46!xF^vX&Fc)S3c2Yzq|TQ&&C~Hze;2m'
    '{k`A9Hm^fj)T))v<1GDY;0{zeDMCvr`&9LXj*^Peo=xn-4fFO=$t!?#+#{+|#hdj;y;U#-eGU_t`>psw5>(dy?fDnDkA#e8&*@X5'
    'hi9;7sIG~|k2ABTnh#9|d3kHZpH`o^Io$`mxPz9tO>N>p=ca!dqtP0(x6SKVp!*KdsxUuaBXMH)#I~RQuB&twkBxk$ba(y<+p`L<'
    ';l6o+HLXE6(oJWHcvRFy$n-p|=cmIpyEMA51AOX<sPmdxKx7G3_+MWpA^9(%jKKFr$+B6NzPib<nLPU^<}iW(h<bN=5>C5!<$!zO'
    'zP70fcue8VZM<r(I1<|v*dN^<lOXp(>cPnW;kwhY|Ma96Ex}VwGu361)Yeh4S;E|TghG5^+umuY#e6wpNZ~U3<5dDzyCzk+?pW80'
    'g7t+vvQ#g%(!wu8>i5^jbk7gO=MD}oo>lz=GO`6G&*LlIR<Ad9;7Ik)5WBAdn*INFY13_Z&fzA$w6$1HGA8R<jJ=pG-o#G-`)A?e'
    '_S^q^K!?hbxCyscrq%aoV`8SKdwiR=viy8^k>!)9afQ@m+n{Q>=fwj#7Y5i@>mU6O{K37kv!eHd&BgBf+nGo0U;UV@4?eq#dISGx'
    'K$w@!o6sA33$G)9w362+ooQ#c-oxpHzRHW-E)~r`DdIZi`@Z7g&r=9lgg)(LG(Q(t&d5xD^Fvx~zF721pX2vpqq@|<zzw<>&UscK'
    'DDu6yU!4(99SRV!$?W=Tw4M#M#s)r{DY<T*&**Krsdo7)KtENZHv*<VACX2#6h4c^kyzvCw{gR8T^Ns;3jVr_%;FJ&>kA3i4P*w)'
    '=wTD{!uk^E-doLz)Z}kVb(6L_1}-|pcida?RO>e{jd97O*$bA7DJZBB!>WE~?r9M+QLH22Fs%tj%y08PzlN|6bSJti4qi~jG#Le#'
    '9TSYV({q*WLw-~ai*~hj`r!k)$0m}GRMqBz@E@x|?D=B?=ruN-_&MiaOw+3S-5m2b-I{`7kv;RKZ@6?rJ}b!Ce~8w6I++LCCo7@w'
    'LH2-OTwtu;fA@eDr?|%mO0*&ZujvG>wMyG{oX}?;D8R=sA~)4uqraPHl{;&F-qDOB>@V1qLTKvVRlHK!zR6-i_`kl2KWP(jG`D6J'
    'oIicBaWo2Mve>JF6|fR-x|0&U6Va~fcG6RKNlU}y%0p!`rqF;F8oV^^_P!w=Y(OKWba_$y_SVIKR4?tZu_V|>&)V0ZNpZaNk1U}?'
    'DZd)*Ca`&V@k_W2Z;128F`ZFs9i^14;7_QwpLHJVo8D}hQGdePqj>ZC-1Y8=oJ*hm?)Dr&>ow1>ZeMXZCFJ#p=77m4YP`G9_D(Or'
    'O>Na}e1L6pM@Mz*MU6kWY+UE~y4T^1{RDqTU#a}#soTk&SUAa+>m$oQ-QP~x{762S?&`ShQ=D^x_e-GkM32EUAv6cl=9^*vPClB@'
    'u+Be5FT9s_B#C&E2jx}d1^V+-scu`jm~U9A;DL{X_4h6*_mZ(*nBe?$UvtN8HyW4f1%U3MMQ2Pd=gP%jlbNpLTpXNzl<v;2P<{|}'
    'zgK~fU)?meHU?@p<Vw_sw)DkC>IDf@_c?&%N`m#uR9e4<<Pk3;<}(>3q*iCh-3gd^JoLU@l;{D~C+DHcoC-|CC&{mmlz?aT%NZZ;'
    'NeHjKjf-55aErO@(XtS-n$nwDjrF4JziawmSX;d(wIR_(c-XIKF2Qaic%<c8{}!61F%XHE_|sX|>(m&NcU*7n<PYctX=>uIlq0YE'
    'hZKM|tz@l6+zf+-B&vkou^7GAWU!sotGp`<+Pc?DgJ9dC`G~!nJPZEzOdC78Z>OLR9j{YYi`rc8#Ayw1)HvVY4*Q6Q*G;7c*8Pw='
    'e}seh{U&0t3CcT8C1kWmpsS?Td9oYw1EUFP+<t!4>=EzZMeB0y9u~)K<uxhNHY?HKY;rHa&Ecyn=Ptv~$f@{=eUg%w^%>jEDCw0S'
    'n!d#Jfksc8-^}O74i2ED{OZTaDi{M5<Ra<gA#DPAB`B1w9a4qfaPm%wT#dnb;9u;}u^kCC%PVnT3~0tk_JW);`dcBti*l)!lxpbK'
    'Y`uPbGGWSBz7&zCPfr-JXO^t!<Kno8s;8t8mm72s8RRi8YsU`y=<(O>>A3!YW0O9F9(`cT>f;XX9}<eAd8fgI|Mm*IGOZ7ct!u5F'
    'DgUi@WoPmo?Wd-00XQ#K^r_XqeHFAp`|5LWx?MR3(wEC!8Tnjn%xF&gxn{LU1R336Fyj`#dP}E!%*=vsDfOPlTGkcgX*F2zF%_-q'
    'IJsxx?Wh7>yEmk535>b#R+{6s7B;e70`IOeNw0!6VJ+<BkilvbqJDhx5FKFVp;n}M*&654t^F8w#wSl=g!yn1*q`fCl+dR&r;j)Y'
    'U~e5IYp>_7RxiaV5l@?)cFC%h%<R<LtiuhL|Lz$-&;0|{@_5p|H0k<A!a!$n`beA0&}2q#7$SFTGrzp=`y%P<kVCAeB4C68%s*l&'
    '9QUG4{yM2(jhWS^eWCt4-$QoU8tJ~;8T@6}8V_H@6lo4%XSoz_QStcGuf{I$f%faQLdQ!W8xV6wPNxI<(w1il{4gbp?~E(gTX{)e'
    '(Ck-dP#>F@XZImjqlbRV8Hcr-XpN=l*N|Lgh4u9L7&wQ|xH7#QmA|{(c)?DdcmD#Xx8%zCp;YPh-aDIH-4S!)qrbT?$eA5S3oKRO'
    '%DS<CM!cI|1QY`2%^`^LJN0efbftiZu4s#Y!X&#rp{fOTuZu6CR3i*?x{H?25r@lnHJv_*AFkJM)2A=`=UxT}33z}%ee$W_sNflJ'
    'uXjLmEqUah_<EU>_yrC?eQkbf23K#QU$b|6wMyes`9v|qphPKjazp>^uPz<hu@6d>nU1f`6WLmdvfkU#m(lv0CY*D3ca!G!MS`=Y'
    'ZQO1%MKq@Mc3vj=GA<zRFx(+)1RgCGqes0pR(|t1Oe)6`;M|B^Uj%2^sUtjXsoQ+1s|c9L8dvUU&iy$b8r%-l-qOOG-gd&(-<U6Y'
    'U_fh1$nVz^$-MW}s%y8;zdTgDR&<PRv7X!RevtdJh*m<oegI(-midkH=y%sGcxfM^P+uh4ZQlJO8lx6lJt|d0tL!Y68xOM4W@N5='
    'b#$u#{2inn?&=%bjzJ9wqaZ6b@@b|oKFYj`4hdXyqSy*Di#hx6$`E-EO|NIYheY>@*8yU=?QKfQyn6`;#A$i2=I@_h9jk+4F|}=F'
    'UB#+5xqevFAv62pv)7e%uiUcm0lzZZ@D~5x7vY#%8}s>X08DzqvK+-o!H?&bV$$!|IUNS`$IsVzOG}IGmO3Kltb6vgj^%x+wi%L7'
    'f;{vO!K%2)RSp0=>13IE$*kb4;ELWfv^(#a*_0P*F*&tYe;E5-6x~Vw^Utj21o;wX)fr9o>D{CAFJK+oE%=P!or$xG;JbpOjT`!w'
    'Unzc$8uh=^I3B1=v)#AIOH;y`CD;`^UjHkWN8I#R7ZKRu`R%MHai+_3m+iU#dH$VybWFS4ALH)VcC(qwTrZ2Mujz^0=>;^@ndG*u'
    'SBFo=(5(gFzT2aQL7og6Y5jCSL+6R^?n{e^x%VvoRm;Aw(ZcHn)lrr7tJA-Xb76_rX<fg(4SICjmrxj~rw@4$69hL;*qPbG=S=-n'
    'eCye>_w#=@2{2x-l^3$Uf)fnf?T$;?84fG~Se1iDANj7`b`7|HT}_^zJZH!mGx5_e$GA43pR2}qbM$;nQ6BTfw2k#Xzr8a%|9U$T'
    '31~Dm^jv7_hO6~wsOYP^cR+HB_GQ-_ZBzpoicEFtaK+PE-Vfa~fMf39;61t@qP=_e!O!J2SdEbGFTdHJqZKyFvo4ozZfZ3zT1FLV'
    'Khzt6d?v)uUqAjb_1n%cGM~p|Y~;R@#gx*@hDi;`=M0n8%a{daNN^hSNrzzm?OPedKvD>creB<{QEA!(H_^5JymY3aaaqd^0WJLj'
    ')h6<v?W5$MQ*<90&oagWH49ru`P^HUwQtW)gQ>LzF2A|ZD38%EOA8X&#x>8^>jO!NqRWn}iD3KL#5kvi&>wH072OCi=3Per<1sCj'
    'PB#5C?BEJ{MSJD<v3SgKZM2eqxUTfZgRyciR<$*@Zrt56Go;W}onMUAhXQj|S$-=hQr`;GYs>PVOg~)K)pWfBDjE*XTiHuJw2n+?'
    ')887U?QQ>?Z-K|qy&BiwN0ABa^<mQFW@Z5-;~<}o`<s}Yp?IV=ANt-anRmfmy4xW{Bb!H1z8P<f26p2*C34Hh5Nbk^pZ;*tx~Nxo'
    'dEBO7wM;wJhhF4(eLKH8GBOr1wcP5Y_jkbhitee`V{=&5Y<BVFcQ2G&V}F6a5jxn5Vqk0VUUX6Fr(@+^{RCIT;d!}^A}Z{T2GyI-'
    've<YnJSTnd&|6hX+Wb1G1!qmlAbRS!|4p@2%H447Tr;rI3Wl9GG2FVu?qSz{eHDlEwcIsc)?wfNljMc`UinwpRJ-aHKVW#(ZDNtU'
    '_&y1+T0A0bTM@SLv!VAfAzcKwK+PcP?r)y&(N0A6<(B%Z4<USS>-DvyP=s8U-YNV?dMJ)p{T{h72GA8HJT7cBxORUsWpa|q2W6^H'
    'R)Ml+xK95)8jU%1(A#1ak6Oi*?yt^p-7=W$W;RpHH<=-{xZ|}>)HCZsHG^(;R$1jRc?uh(ag-|0xV$Y|o%!w!Kc~cQR7&x9&>c4#'
    '40i98*YOs+|N7!DtX6&p>%RWHL_*JPt<lMrXovhNm3T#f0cG4+eRRgMh5g)bcU=qdxcAnn6!HK#9E(OEWGeEhd<CbsF&m|SdnL~O'
    '*>2y_%h3dUPHAC1k3P4QQW?rw%;uVyaCGl$e2}fmCv<6gsV}b0%4BX8N2jQgZ2n*#`X#20^mS85l;y9lEmzh;OKFAaJvc%wYh}FX'
    'iG5E#6%AbSUAuJ{Evn4fYL!L`S1%Piht-PGtPEB&jPE%0+J_DM^v+)Cm1y>y7?mG?ptd<2^QFrEyoR5^lkAl~W4&5=pEnyD2#0ql'
    '$|j=2JNlV5cPlYH-G^qiQn#NYP+icX-79wZ72Q>6Sk74X=hN25VEM3Y(sEmKR<UZDQ$n1<Eu+#XEUJ$0v$Q`v?8PlySt!@Cw!-~*'
    'eMr<2kb&D>)`m{2YQHh_50UnLtQ_Tszve1aE&G!)r$!fDO~7`ey2(}#6s=%*r)KzOAKzPSeKQ>Eu8gmZSk7ESN$}hEnD4Ls1zlzT'
    'uq}kqiYjC3@z<|mJ`sk{BB@Z$=3eN`v-ezUf`-=zF?dzldQ0>V`C0UHq)qFQ-4_#N;ZlC{@6zmpM^SJ%h%@}2Z6gcNy7i%7-|NfX'
    'w%%s{^u9Lt_hW5^|DFBdMs}hz9WS2po47YFgVpELQBPKLDs+*#ei%n}Q)&1u1%KG+*d7hef2kbCf>AB_`IG72kC3EBJwy^yepkBp'
    '#=4|WCk?adh~s7Rvvh}(*X0h+z!^|BmBZK1zwgF>&zSsiSo|jHd^9>eLzo&tz^gm@<>NB~ZRo2j5pEM!p5q%zSw_Ne{IvxUt+dzc'
    '`tKQcF9Xwq|HrSC+cRF3p8kTNJ}?j}=~@JU=Rusu$04m9VCjdGW7^wWbjpsuO6pez$&fr<GimZLnpL5}w}&&-UA$oAx;oE03v8Ro'
    'Yp<GXz#zRaVfC@xCyKT^a9J|M2gU9B?;VB1uC#wa-1@XtTKRg<eLq+yALpYW69*~@yu?xj)LKOydgNWA6i!U<{6LSY(AdS62v;)%'
    'x$2e`Z&<rxzMK4S?o041Nw}D{gbh|y?A|cMX{FaX3>0Qkd1%-?g<akI5RZAQHk)iB3`z0MN0A0m*v>d_K2VgSkOK0hqnt0qe*VKV'
    '`+jXI^&-n(vy2Zmc(Yc<DD+S)y|q><B(Ku8%U!%L`$;M7+Az#5`9ptFn~GAS%)g1-t$JEo-(4ot$;3&BAFtjhMlI|K`i8;P?4$3Z'
    'KOQ13Uon*dV`%T9`FDaSjR{jZh!-U7R3}SetTdWLX?AM`P2KA0L@9o4Pf_z>I?D3r6D-QO2Ppf>cs4~BZR-XZ7A=_ebyPyTPESkM'
    '0(eRY@i-3i`bK$?w~vLy4+Ic$luO&)3YN5<u(nq!?+w)Oy<eRyz~Vyhc&luEQuf%_`?{PqUhpG6iuS$uDXf|D=0-Yw^YStYw&abq'
    'YtFr-KdynziaI>9iq7-79q93*#YHXk*Y9Z>!`tO9_v*B-K?ClV&G61fKdiaQtrT2OHl@!VhdI4mrJYoKRtjN49Zr7fJ%r}3mo_?2'
    'mfz=ezkbg7N#omk|9BMR9=ZMB-^$9%?NIX<J>8YEW9J=nS>vI1_zraB?kU#=R!g3Ljd7Am&!0|b{b8C``F$tT4ssQM{QF&Lb@y}l'
    '&2LV&0Jb-&xCFn}Vf^99@|AfHm#YJ9D1VZgqhGDZSEdI3%j;WijEdx7dQ=|FhI-qQ6-id^D<y*2em~)$Azgm;mRID=2d)xO=VnxW'
    'p7wKcKY3;KMZPhf8CVYvwZ}`_%)v?#OwSvt-lUe_+<U%>K&pz<^uV<sX-l#Gd5=-8Bme7Lf&B(V3LR^d7Z7$oxE0igr?b&5XXFtL'
    'M_+9J8bRoy61-cFNvE{FcRQs-Gv?&?F+ZDDwXKwGt@c(=ukkUrRzDwnYiOE_sN~nLiME=mf9Z!@f4<FI<ExLj-t_S99{QtAlZNSS'
    'NWSKc<$FY0ZJb3Sd<^`3^XtwyL}nS|^6h4P9RK>GlF8yh6dZTk5IdV)H*x3_aE$@fZAOpN5E+9VStNuWbbq{=NLtmi7J*nn|5<@<'
    'K)zo2p(%?R81gZ4n&j{=A43PjbE)&{OW&cqdYWn5Rrv<;gk6F}1CHSs8?1ELB}So_<u1MVlH<l6Zko`uzh<{3d)4Tw>@pQ2Bf2rN'
    '_HVvBPMY3RdtaI}^y28j6d@A1PE~@UD+npaH#k~uEQH&WZ`Z65c2+25BOHKJE5T0B9eG1=#ne97Q(y%nj*4F#pG#9u)&;4S+H5NV'
    '!O1)W+Gz7zYNDfT5)dmk5!?tn$zgQD_{|cf!w;Yp=Lmhc*lbok`)AA-y@wX6_Xk64|Mi0}X1gW48tzo7e$#O~Ak>)ORThWWvCp&y'
    'n|qt?WJW24dIf(ul(q5mLFP+><L*nmQL~jvX<GfBjuk^wJZkjgQA-s~9}HkZ4d7LLDCs^MgJ&LNMA^rvVpuz`LWMd4{_%(t!W{GE'
    '=WH*5O34m_0kcw0e^hvVyLM{b-Z6qd(U0$Vc&tu!szG$zZ?iE<J%w!u^FH7n8f)r&PQGW-tNE~V+`Mj8`Wn_}yjzVY{z_hca`^4L'
    'kMYQX3)PpQQVhR-`~iA4Ch%|rU$V-4Hrpt>EVRP~qPfm7IUg3b+ar(Nps1?T_aa1lfjmSnLA|QfO9<BOV&(n*TKzVU3t+M@AFt9+'
    '$DY3S9VG5)`86EzjJ2(7wso?1E3|;Ekh9v>acd2&zNs>&I=H1JgDmnc-+CPOlAm^_qv1!&9~IB*`WbIi?&=rE0N@=a4)i`Y>aLe%'
    'Cje!euU#FgV;`mmPBwGk<FeP9${`D6IcY)O`EY*h_G#AmOD(lznn#uGbY<R<GkzHCrTm|-Olv3WU~5)f|AWJY!LLx(7NSXQZHKUW'
    '-|ln3Y~pLbbafYwa6L7=)A4{YDy79iUlG`F5q%}K#(<pV>cVgC_Ix_s=R&>Mpd7L+EVQG7Y=2@=^o{xB=2xRcOS8dy1-8^|Yt4>U'
    'O+38Nif)X(zh4G^6CJRpu05c(`AlsEIu-xkiND{nXBVY|Yfztuhua_ZproF~aqD)jdcmwTg}cXxaq(AekRnGr6ww@)RyQa5{U<<|'
    'yM|5mHI4Vfi_6ge_Nujc6f}07{U>W#5BSX92JOs*U*V^>sQR$V(LUphpyLM<zh8@9tyl6)RWFl(_RA+_-h9P(;!4$OU`t;22W0Zo'
    'Z+hIBmxg7&UWdvCu{6D8{zaem;a+NFyBmO>rX$NMl^|5T;Ryad>?_Of@Y2ztM9A@nl|eEGw|Q|fs0zVd@PGWlK9uhXcUq7yGmO?S'
    '^Smk_R-qgz8Eev>t4I~BF=E@;c6nb^Top^dhOeMC2`?55(L{R{`m-NvlWrd|jeD2=@ku3^zI8!E0(bkmuN9}I(y27B_vfK?GR?uZ'
    'wZtvYM%m$O8+m(#?KsD~|Cfm5<?zXs=84uBi1MC&E9H9gvNM0avi)7&Ms}SnPOAyMdzP9X4_+7VhYJAJ?b12VWRv-TQPzgHFY~~e'
    'g9SU8epb!b`y(u+^T(>d>n<bNsCFJHZu`g2ibh3?a<o$MSJ2go$LAgl?nb#?#x`^I$ydXqY0lag8NZNP_l86lFfHxsgJ(Lug|iud'
    '$R;}$*e=7nBOH5H<G06Uh}GP;b!m6pBcXNHH!27WX!$Ph4n7i|lb&APpD4t=T!zxUU8YF!&Xuk+^>Wq8?m1yvI?)<-s)*P*>BS3|'
    '{_SnP>Wj(jF{=wwv%nvtD!fLv?f$NnEH>G4c*FN4CoPrEC>GY<qb@G{qIxQWoBG#zV%fVErDJ`sta4}Zcd0;e^>5E<{;JZb6L@8L'
    'c`@n=Oo4&p=`rG)hj@bVd0Fkb9nv#liMPLH%*eM{mm2vHko4aYdKeXwJVqdPK<Rj}{P~j&&l`GXfp~ZEG*3rzuj*Zlmjs345TLbz'
    'dP8bW{<T<co#O`?Bnp-7&pN(GdXqk{kM!mOyk-KsiKw||DS7(C2Nu~8hh$`|)=~0_HIGKt1A<$y)!{e*%1YQuOp;dymu#y?I}~8*'
    've$DK{q{b5yon*+*{aL&wxx7>A+|co;lF(BMeOd)$LqSW8B3OvQ+-(&q;ZF8+^a66oWI#<<2)QT>QwosWb73?+PwF{P%Pt&Ot5JR'
    '6v}DQwQMXe4&xtx7`tt-|Clthj)Y(CbNP=;PI}c^vLIdNaQ%ZhzSC>;C&$G!D`WV<el&1F7AnoC<uv6?0wMb`=*?Btn1RM8I{xYb'
    'J0S?uF0$B4$9lt)YnSS(camFzr_gR9#LM9k>ph+C32vV$2%)9NQLIRG7a4E4<@jay!xDP?+QEL}30U5L|MKw+WXt0LjIDdkxjnj_'
    'TE;Ft+N!QzkG8!OPL;#CPRgIHSj%?TdG&y^U6yt7S*z+Ugh%D0)ku<-)3>qTP>kF9<xP^Wja{FoWsOVLfZ65~nLR$k<FZBN@R;19'
    'EvHBu=Vi;bnv>$zdV=NN<}|H{4eeW#uFK5wcqqE)!~EUIFUYU%|FSx48>%zNg`GGsgXP1aoQ9F6&j#>5-h;<jife`dHo3`kwlw&x'
    'Q65f+*cEq;Y;$JSieE_K^zYlPR3TOn>z^LV9!D_aWTBO&rERGEX$$pBYUVK+QhKw)jOg{Y+-Jx)n|T&jBPt4zh^rd;#U2qFK!g2c'
    'w%N0FXUxRfLi+WeEz5E~ZJx)SkB_G$JwylZeQVw^D$RrUOsw~e4YuXU+3C9%q9T{)a(fQ?>k{=ja8ARl&zj3Xu8vXQQ|>pTaQmwl'
    'jxW0p?B0BZ#W%&;!CmX)r|}VKn%UA>T|<+7z*&Aw`#s)DA4_c|j5}=&gN<;DseFI%WQKE9L8_CiGZPp4AD;xQT|QGOU})@~y4<h{'
    '7xJ9ZsrrJ~Zvp0-D`<X>R`e^^Ul(0fz}~{MsEr>V!B2l0$)8dIG`sVffes$wq%rxO?-jh{Zqr?$-WF!5%O45GW3zFj@nF!s@Ax8Z'
    'lI9wj9l<x0JkW1^dC6&mDHrumfOS{fKXrEBLH!tQRGq_#@P0nQv?H&yrqf&Wjq3vEn`UVq94$QSd+z!kM1J|)@l<6*mpb<ieC!Re'
    'RUb<S>P!O1Z&Z~VH$`I&kq#e=?RW&$fAQvuJk!B0KtB@bPb2pY|2)RZm;kg+`RTju*5DM{zc<trs1S5Koh}eKzGggRs<tr~^iylr'
    '9XMMeuIBBc84ABWdreJ|UhF^^9qs&5wh%iUxKn4{eh+VEtFv)Gr*w%hu0A`F!eJU>`v7~ayQNmx2KVqKwZgGGDzaBc;l-j2S3m#W'
    'F{j_38CA5*88+b>%kwB+HDl+z9j#mkeU_PbEqE@M8;y@1h+&`j+xi-Sct^W@B)t96Vn$>|;-(9vh<(R{=-)ntf+oj1;4r1rJcGeU'
    '-&3~_9ak(`5eLEZ1Vg3j>{HvbFE_x;S-B*PX5f7ls8j+k+WP!Yg{{v!wP>}*1nK<tdosgd^%|~9+xvao(#!iRg$%QGxu7BM*1wDz'
    ')7!emrn{rC!%fXPs<~$795~JzUFD!JSZ`InThvS&m0Mxc294i75IAyocRpJ4gtC08JBl*C`n5cx4abE$^-jHarOk4!>68;N^G+7w'
    '!+zG**OU<8LXD`|FPNqzup@qo&J4pwzx&V<l*_#-OG)i8!o87&>umcKrO~QVtU)c3gW_ym>7tNz`oOl@6ir&bk?+|Xyrz-LC@vPQ'
    'kRM&W=4Q1LGWK_W-Ck)m$gD=TU8#$4cH);6p7o?7?k&k1r9V=8IJ|m`{@I{|3YUIguQDdDi`{y$98IE)+MQi9tmTnd%SK8G{M)}X'
    'gC!1{R^}oIto#WUo7NT_I)nGCDQ(W<+k5ISQtp{@hfRVy%_~R`!0oZUijEDQ$`fh9klbG1PtK!{Q)=45k3U!w5ut8F_T_++Z>1;<'
    '$NE#H3o*NN)7w&?Zb}`)ti~i@z0mf8Nn3U80aYH1LJhS>L4TrTJ`siKFsV3XwDW&`Ha1W2mE&<$ti*TPrYqIGy^|!O8e;HvdhH?n'
    '%I!@WnbW-F!nY{4<mL+R$2@N5D^Ff;wg+=Rl5upc<ifFj;eUP<APs;9<aigPx{vQy#LDPn9W1{Ke#u!v#`SVx^wdK-hE^NSIDXz#'
    '<u7_l=WF5JhaP8sA=Eh%aD@#<9P57m?OlAQU8)*S)sDMd-St0617Ut~+C5jcU*L%Pnnr~Z6m8BH$jA6r+v8!A3->!JU~(w^3zjr6'
    'b~DHZplHyzIlsP42D)de?Ohf@dN>`={q79Eqi(V$JigPnW=(bCs2a1D8rS4DhBc8nx=OrXS@rQc0Vhp{I2S7^DZ09}3#kL}yJzQQ'
    'wWQI%YXjCmzmzaL-|Jth$Ic2a?Qg{;ut!vPh#R0;wov>!s98PCJ%WG*$mi|q3;I&3wcd+!4XkNhdRYDE+b8+%{P$60$S*NapsCWF'
    '6}MU=i|KANOLtjSCz3}wWSsTQKNlm{zSq+A;<1u|WL7w8fHykbbz@A31Y5WDpTEw4josFOUK9fzg6N`YBKJN8#}gk<??dyTk}5SF'
    'GE7RiZG3<Z4?G!m$J4$&i_5b?G##Xqpwr6u*(Q?bJ?CWndtdt5A`pz=N(>RC<%%7T)b*3l{-V$Q=1gnaK&r{DZoHOFW#s1MP0;G!'
    '&%T1Ga=+3$^hK2|VSkvj{Q|My__vS0n7!O%XURia{wG)Z9R_kx>L`sFRjXm$KdJcG4_=V_YJInd(kp*oe0y8HrVxg9_VBxC{r%$Q'
    'FK3qjJ^(him+8OvI+)%x>jFbgzMmX_4jrd!v-0{pZkITUN&VXpGyXl|VKi{%asZdE-M^y%!&rk0<JO4Do1|5;%+i!9B`%%c{M)7;'
    'eU39~NsL<Is#Phk9!lJay%5WK>*}#LGfBEzN|#R<X3>LOQrOLXRpTYUmG+gAiGIbs<L*s4@=ICKp~N4q%MkQ;YW}gU-Iv<@oYaE4'
    '7p}C97Z{Fip*i7$Y~GA!Q)cj$CZnTSUt%5<pM-H2?^*BT2=LC?m#0`L#Q(U$Z*K9yG@smL<=+q89+_F!^5=1BP<}pt95%Hn)7$_U'
    '+v{UzYfA9v>Frp=^2i~CV15m+k=9Ggh{87ZPEJgbZsU2m{F{?_qE0Lx5ahBCfIpe(vsyTeyH`YMbk#f1+<#6Te%OVe!L#jllQCCP'
    '@{gF7yN7Dn&HS<dm=mU+>}LW~nT>xscDnt;txEs%nC1bf+XIv<yS=sUX7|Q>w}l;NTODI^wgndBo5?vJwCkIm)lbsLAWq&cH=G4$'
    '`dFooD{O5z^WS_xrIOjuJ+#fa#O~_;zz{6&ITY<Xk7g+`1{^13WQKfca&>;IBfNOSM9^9C_3{}9z4BcYpG*~I!G@M@CYQr+USyk}'
    'xVdk9##(~42i4nP&^HcFJ9m#(gL|Q}CG?XT9-obTaW`bg0ZV@St`kV_R_nndyFDa6ce*b!{X^?`h}*yW@M0O+kUwwx24$-B-oEDj'
    'b;*5t=n_O0qC+!%ajJ$Ru68_a{5h$)*x7r|S1MF=^x}w2#AS7dH^7!v1s|^V{MDW2gWhB<cXz2_eBiQ(ptZDV@T_b!QXq&+T?A9H'
    '<s1!j4Y^Tyz`oM?0z?cZFRkYkVG@R!YvLIGmb&3{x7B}s^|cBx9^I{11`s%o&B<Rx+_{)|KIiD99h|up-*3%6F=y|`mymz2#Ik|6'
    '+8u_lwV7Xu-15z9J3C<VKDD`qwfW(sxLNFX$MWl)`Nk}qPbTC<>!J1ijp)uTM7&3&%iY}e7x+}}c8-l1#{powZ{3ISo)85)Pvt&x'
    'X02Pp_zS0E_QNy(MN&QeL(VNThuS{G=zgVg*7^1DuoTZP`rye!qaLqGVWY+~MW=Til6XV!onGnQV*hN>Aa+6t2;44Dvw!n%M(*X$'
    'dUMl&hEaj}Z6SCn?}6Fc-}cY3=YPBQdulKXyu9+J`CinL8T*%`iqM+@@35yw-26Bh#hRpdk={)I{^P&XF7`U@Aqt!2$Euhl=?S~K'
    '*dE*BEzIr3@@jP6RBwCg8g+t;aw2)eV}r}qld6f)Z+6`IvZz*i;FW#b<9h$sr%*0;nv0HpRtzz%gxeJyS8J}aC)cz6T17#pRzi*2'
    'ur`?Kng}?^6RX|9Iai?4TEBIeXFG27;teTi@QR<)bM@bQfVBhg>{j8{#TAYYpO*1YjbT>oC^eYN03NN?{T4x5{_Ly-fLvRraQ?YS'
    'E&N$Om-lb4*(bY_U77nWUoLIY@^A0gUDK1D0u0EGKO_q(KbXkrDQtVM&U@KPR^<sG9xmoPuCO}3PsU}7!m6A3bw6lBEg-Gd!m*N1'
    'w9Yo0Z3gbS^t%tEhj2PSHh2WiMXGO+*k+`a2>+c`OJlscSbufafE76Qg!yvVhilYh|0>_Z=E?P==XoMFr;qtt)v@+p96T)GS9c;W'
    'WyG#rD3MM{0NcSm7r2HVceaK>g3ZT$L}n_WUA$zX3wnk(QDlnw!l+oX&S3r90&Xw%^2h)9FiZW81pV~I`0aBEx{AhXSlgNLp*2@9'
    '@zFW2E=?l{=fDwr;^KZXtkr_DySVJ>#<Nd|4KkQj2I&492=bJ4*wStIZWUgm`P&aZ-mc?Ho2gC?19n^_+4tK+_eP-0ZnV%?Xmwmn'
    'lI_Nq*2E%&_=&e2;SKwkQJ@lZwQFlf<W;U-sw9876Cs@R(^=Ch+TZnO%h6B;S|a2w6Jla{pU`k0@+Lc3(cW4r?}}jB-|d?9np8<z'
    'RiSaC1)`YRoYo%$H1hVs;Ca7Gap=$f)yclQ7Tyh7*}yW5nR?fl`(Rj<Hx2;a>wR*$sX$Wiq~=p#c<DFWc?oJgoi_dr4YYE>yXOdH'
    'Zv(fzhu3DY4Swf9Ih|NJyi~2DZsxmPYp&YBJbZMZqxQb3bD&ePi;@ZA1K@}hqG4^*u{ds%f5~H~T)%boUQAt-nwRzBl3mQ&FAt?m'
    'P7Q*=cDA~kwA8I}gY|Utu!e)`u<Gsl*z=E#pYHI7VHV%+q+F$Ve8iCPT?8r&236bB8#@f->ZCWFFIDK@UhFV<-Ok~YZasNyo;1$4'
    '#c_`b(vy;Jj}P3B*Xad74SQ9Fuys0KWi@J0J3af<4P|K;OUm2u;qh4QghRWub#MIqD2B%Mb6w!(uilXyrKPtikepkKi&CYe1KaB3'
    'SmdRmen7e_sa5is;xl-xXzxxQcJ(pHPRf8sA2Wi5vXb5PrJv5i@l$FK=z8FuBR-K{bypY3rM|ol@TOU+DcYF{j>W`Z(d)04^-A4Z'
    'yVrc#*Y;ugS`L7yE2_`QZJ9g>u6?=fe>}B@%s$_?wW%Wm!{D})5rM3Y+2Jv3jXD+3#BbN3a(s8EV)c2t!mDFio{9U}!YJ_sy`&z~'
    'iBl`bm_7W%ow0S<&;Pxr2EP-Ep;`caR$F~ryAyhcA$$1^0N&Hlfb|Kq)vq0pX8Ut$<2UW~+EnkYH-{Ssq@$hkM%vz8;%%>0i%FJS'
    '{OaAc$332XpFGU$KN@3&`8SQL%ZnXR-~KBZ58i<vDSpS|&i!}J;ygGRry9XKyQJS}oiFQ3^Sk@Zzg540dyVC9KC9DMjyB%o<Eic5'
    'H>@G1!t=BjqbIr7?pKodgN*)rOZ2+fdkn9U!<>rQipq!EC!YC-_DQc0s_AnY+rIXT?&8PKW;JPXlH5vpBiV6J@hW@thQr%=R5UtO'
    'm+Hh^^DpG!$K%U4g)NtSS1y6?PV(vV8XDs`VR6tf`DWR{Cv%K4e*IBw9ejRUYy<2rX7AII>oo=YoLz}k-k(6uXbMvJadSFp5F6*8'
    'YD^&Vmh{)qRNbAX<z7(X+mYjGaY<i#S{<tV=4RSEKYmy)*pa#E#H(etupos$Vry!5snqLe23$!Cm#hJLt0~Pr?(R99MPQ{ChtjwE'
    'hPm_P!d{5aHM71+9{$5Ku&Bgr(<1pNKd&p@CVxbmUZW=N<O(-i_{%CLxJVhr=D>n)w8@L$UM7TM2?HSxcRPl3&rR@brk>o$SblqI'
    '{M#2_4Oi0}U8sdulJ-S?RXQ~``RZ)GMQbW;f|EKfN#?C_li$?nwYi;o$4d(+mHkrx8cUK4wXhNJ$2w0PWjDCa|KY>4-+SH{{Mjg}'
    'Ad63{U7&uszqOikXe}S%S-qP_pZO#6bAF9+)#2k}erB~Q$WgBFQcqz6ikJCow4D*Luj;=(T^K15a-_dSx;GfL*K&Q1v!M8eiTWg='
    'TOAb~w*#beKE|%v6M9jj77TVEJ()<<9Pqp`)0nq*3HRLY7-(yW>90>Ae!2-5@12)8-KEX*GWblAIpesK%R-5ez@}Um{G6p7vGcnF'
    'uusl<>NilIWB>=|<xRWGQr!uitPyR^D2CmiPiy{<s4Lr1Rf~e(LKLGC6F`|F3J4Ae4u}&zh=NR_41$QFe*5kF;(70M@6dbKs;V`K'
    'C3^2kRU6AT_;!FA?)S0jKd;Z^&1Aj6+-58KH1PC;&Ki^SJ|I&*>pS*zH>()seuLF#g|bz6GlhxF7K>jTf_nAM4z1A6s3cv->SDZg'
    'zmwf-h>7IO01F<mR`=Y$a|pDtxNW7(QQ`mXUR<d47vSgblAlAJSZ!==y(Zh;^^Z?(#BZjPj^KILAodC~wu{oj(=nBjdL4Dw2h?)E'
    'JUIKUf->{nJQ~4JTGmF7JCdGPhID-Eiy~&gKNxH`N=Ww8$19AZ>J`@Kvmv&d@>`u;&F%d<{b+;AYoxVSMIIOjs9G*9uPX<7^N-ov'
    'jc3~OuyL8*M!g7xrs>@aXg~Hc`uN?m==m)L)#^I_Dm2;IPN<sGuaJ<v(0PlykMHKuYWEdzlmbtRxZjKLDS@5GpwTjh8f2O1CTJ9u'
    '@U_d(8Wz6(&CTESl5(vF<4Kq6XWp>HJ+Mu_MmxQ`>8E=w^1QEEDvH^;!^Wd|)Rf~|G@v4Av6=7NX(7Lj?bkxb0YB~6_GtHqlc6u0'
    'SM#~gqT}QST+_MwQ3Noxo56&+ZEHy^WnQwTwEnT6zgW~9`t;)R7E_?-l_VZ(pZpHE+))rQz0FHnvHI6{FsM{@^dU&>{=1@wZuRh}'
    '6Yq9;Y!B!pud|m5wlhO@ghP$=W@WB<O-H8FC(*-pPO&}BuP=h2?)MefYMHGc?zqs#*>Nm-)ON%?=1P`l>W%Kj=A-rHJ)dql+DurN'
    'Ze6&xgjUB*y#Jh%d~84W^v$he)pVafy!GLD$j;TAAO6n!Xc3)qn2o;NayWGBK|K!W#|yg+^5&RjR`z~85es^fY29{xTyRrN8i8(#'
    '8+s$=)an8L>_^|yE>zE;VLvAF56`Ft#39AF?)l6nVq3E2e=gyxq89DAFpjOGww3b9XVN#|oYw8{)w)ccx-T=me&eL`^-|cf96~kk'
    '+cqN4PVrC2PDuQAfmituJbT?!Bj~9u8m20T*B?ustWL9adeyM&<=)k6*cm5J)3Hv@n$Y!&q@q!AT0FgfUvJOY3GUj7!+-M}-SiO5'
    'rVYv5cc(ijvx4a5h06dQJ;PmVHr9vcX>hbp8&kUk40_DqMk6a9VSx(MsExg96W{l_2XJhCrCr<{{Q9UyhkNUfUa9D#-3AJ_PBCf;'
    'kFfLL<OxAPB$m|YF;tF40x`7=*{as2nJd~E;5x{@Ebi*_3QE64r~!)YC=bWKd~CL3UTisS9qLH`@4LR<LbE7y@pWS>kAnOQ{42K{'
    'jC=iEtGe&P&D;EOR;#6Qw|*+kWo`fL3c?hrt;eTqTQl?OFCVKS+xSo}ed0e__z|!>f<=(nDqW^=DXdu?NqStWPI_D!o`g@%(dh~7'
    'bWJ=id{2p{^;`bc6pfv9_2iozFU#65AHYmf018Pe&6QlGNnL_#$e`U-2KZ=Col>#%{68~&P?Hx&&iWILNH*EmX-=zOdU~JSircB>'
    '4I}g~u2R8w?f>|s%f7_rd}QkCs3tw~X%!CR{j}2%?>02*@r%iPE|rf%V!!_*(X)?gN;P*@7o9&!@byVV^}y~`LgG;q)n0Vw{pxp$'
    '2^yeJa|&K&mxG;L)j8({w-XvZ^asdkG*N3`ExW&N6+7ih5B7ChV*%TTUh=uDglCKSBVLvue-;4emA3QW9K#cXvdaoiwm(#fKHPm>'
    '{gbnvx@k|93J6-#Wv<fiq-vIrlL<8Lm`JFNhrK1yZLO+*ic2GEFJ!t_7;#GlI~x4?eQ&8occ(T1b#=hP!x3TWUwCP_LWTO{TeEa+'
    '$!khY9kjKR{zMgbc?4L5#FkG#FG0}I4l+2a#-~G^a7Ki$e|^pE+P2zry}nY`$aj=v<o5u&6GX0R;=a$%*?FW*4&(z;6C*g1HTI%z'
    '{q^e)KvuOgA6d7De76pry0SKk#f)D5=FZUaGWLVd^qMu23<&~P=!*%Ds|5n#jeUh{I`=%fPLdui@MQBH!gw4tmxqDh@2&G#_@pSb'
    'H)ls4nyzar;rOe6XikLsa^`XKHJ8|o;eSfJnG6VV9!f_k8`RwoqByIW+P|f2t^O`~ZB(0nKsbT=-1ajru4u#BRXYW-0a&|!`MqOO'
    '+R}ptT3VRcyH2f*hTv39#iO=u>g_DE_m0|jvOagf+&;A(CI%$lvkm|YL!<MDbJ;0AX1y?{ix2P?yo2^{?l^{4b$R(7$<;Mqec-Rl'
    'bUQ3_prvK)YppB#yKZG*y3~kQtHPRo4TQ}{R!5aB>F@dsJeYJ6_bpcS&*%zu#L=%$?bSLajnd@_%^%k6GOET8wi=JG)V0*6rj~Jj'
    '+~MPed(GzZIV?@pDilU#<+Lf!1G|QLV`#4+)?zwx#@TY!dBVT>TtQ9J)ujoz&ydkI3C!-g4NSAf*`IOvAuy0GID)TRAWH@qkbmK~'
    '-f)JUeRFqnS8K2%*8y0BM;!v4*>wAp{P-l`G`XZyHX)VR(OEfdQ>7<749UN%@$A@o;GN&CoM=xfOg8uN<rNC&?(V2NsWovj9j~uS'
    'QZ26rUx{NnAFTev9bBi~`Y3C&H>gvS#%bfJMkU4@&6{s%*e{V^bc2CBz~5-9yXP33jk~MKhw4=}75C1YyTfHplgS}|N|PwQY=3=='
    '!!=erS5ROsRD^dys0JIHGEp5E<xbpU7j&Zp);#x(l%FDF?t0Z=b%`LNhi2o&R{;5qdvIpN<<jnK*T#;x|LPxT^82L*?P8mZ5sQ3`'
    '^?~sazfItof)(-Tnv>;mG~&dy2b>yVbvpzmmSpox7?65VFc$L{$8$d5YgW46%;DLuZrg9PKAm!Y$Kjmnca~}tpQ2Y!tBJSsc6k%N'
    '_2ISjBByT|y~X3qSm_^n(tEE*-0H9%7chASOP<MVb&!n@nz;Ps3*jnPdUzLZx5i@Ps<djKmH9%x8Z?+P0<Khhi!^w=>ViG3Rjw=n'
    'i_89Jr|&aB@2qdN88rY;M*fn{jJp+MsQt@l9idmC`xSYd*K6g`s(iACR)07Ow2n+~;%!H;0FHV=NjSvwaKI0&3lPT8(Siq$%-B2n'
    '$75@LIsEi7_Ov$s^|`ZB`x#!(vVMtjyZyOru>|pYt;2mhF1HUfB>q2!^+X!YY5ZxFOxnWwwZdDU`>`~IWcmtZRq`W<)~Xlz8hrTq'
    'w30}RgYK}AYaHv1UiR#SJ{5S-nJ0yPo({|#PgRF$az5hhWNcN_v+1^bac5KKq~e4uE}|d#)yh72%p!^&k-xoikR99wvFK73c<FZT'
    '40ogoi~#kRMg4cRV3cM!|3YqXJavPddz!b+rV(ZF;jVadU&#1HDC_rX3)GoS`Sk>TzEL+%;ph75AA0LIaM2E%H~rY3$LozOn#9?l'
    'zN85ujluV51&Q6xlHqe*_2<uhj*Z?yxsK%0XuQPIWCXbB<8uDRw;m`aO}<sfsQ!AuFME^K6VrEfx*6^{-d`o1#dR4(=SB{?31&V^'
    ';YEP#JOQh3WpEn4m;%_F*E$ewPf0`FZ+^Hw;O_H5+aQxqr*nHZsP)}wLuW}Sr_#3BW7pK2I@hQm^S>&8m2rYm$}G-57vJ437}ZV('
    '6|0Z79yD)z`^Li?{P01UCbQSlyFLh!6T0$RSokyZ9937avXc3%(y&6m(TG-;4&2j)zHqL;F_bEpOCfNGIQi4H1U@tTS=_&`ZhZ6C'
    'XQ_>L*>_jV5f1_!8D&z~F5O@K$b=4lvf|y6;kV#DS3Gz2d_P}>tSe^6KABnd=gv1!!H5^gBO*?Zu-~e@+rK(<hst!PpXAx5PDpe9'
    'SmTQ2ns4_LxAIk|0*!YpJ0O;k{<eFoif40s>)jj+lljMboq>78U!`iTcj?{><yCIpfBa#f!mrz34DW$st>1JGi<S9A)7xn{<*mGT'
    '86@U$R2@O!4Ls_14e;MilCt1Y8DqzL#5DIaHTU1wd+7*&b`U}R=J!R@7}bY(8NMP-D2*q8e4{zLRcJarBfI^R@?y@F%qimW<=yvF'
    'vxaRjE^qa=-&<8+QeUo{<7k20KHZCtFVLT!A54KIh0;fD^C~TEzInMu%zJ_dT{b%p8)swAtPaJXS}~ebCe6Gy*WUJ@g-879c-B#!'
    '-kCc|Gic^8%mrFlyWcyu`Da8BEAuhn+@+;c^|`gK?^n3NYT@E=drV=w=Z9JHg1`jn>qdKf0*mj6Cj8XSo=>I1pZqCSB&$fRD82Jf'
    'XB`l~)Gy|D$d0*hJ=>Jp;BwZqj^k>XS^>hVN&SV4%B6%S!;n^`U>WW@ebNM+`v>vd_4Vx_DzFxt3UefvH}6-En6#3sQdQUJsXCsl'
    ';epUA^-6~7C{|vQA>N#XZj|P$nLQdz4@d=vHc+RdrDyQ)rIAvh95Q*C=3+S=Njt<;e{;MC>CLILnsf5;A@E1S$&*Aty)#auby=gk'
    'extgR;_h|8ss8pxZD#D_*n|}Q@Cq<oYsdGYz1rq>_kwH^KJWa~EgP4N#M6_xf5(r~?T^#-&yEgW8sqlP#42C|<?!P^kyz#{P5B~x'
    'S{z<-ftJzqo~@n-MrW#1e>p%Mu-uB7LO-9NRmLWih++b@85mY61bT-H3sy+-3cdQEpc2mwyjfi6k~<0iqS)DbCEbr#lQXk@9ZL#P'
    '%*6f!u|5`-JsRZp$A2Yt)=2-9Gk?#ei}ZwWD_ykmKG7<b(Ez!~543%2udIfAIM<z8)<3*VT5FephG>w*gYR4^^Bgyk$J-vBAl>}+'
    'Gw99NqPLC?EtFnWxdF><DnOVGzmeYh%%=MCiu7N%+3T<ZW4+Yghb!=YDU#8IsF%-dMx8drT$xvDyFYFjgc1D19WS%gh1`5zK?XY2'
    'nF=ho9*4t@dfx8f>0@>GWj(Rkbjj1|j8lxBdAJ~#_u>y;g)?d*)Xog=^*b^gF2aZ%;jMpjCEh7f$*C$R#<QCZ-1fj|riv7+P7>-J'
    'zgc&l&X}xpN6Ony;}T9}#!Z;F-HIlO?5}ipjrHJC1>~aF3X|j?{?75U^VS3F2CUz08Ou9j!|f$5t;@9!^e3)2r=|WrTFP^>s14oQ'
    'nX<G^xFAp8Q<0qq-A-S_r>zH8L5j$bhl^kSn4NyD8$1()1Va57h$)6^@jcDx*8%p{ppfn`GbTMoL;PwF*xsUid3$HX<8ryY>Eu>='
    'I{ODf*~~#zcOu$Qe)ynZBq5&YQ;_pZ=Y4Rk^`hBoj+3Q1B)XUij6EQOlS*~fxt$+X6Wbq&YI#@@yq!PhBdsM$f<Y>OUt%T=$I|Pk'
    'V+-$HyQ%9&k*!6aMgUgWv&*hFEte+h!d-#Kky@o&jnschC{*Hv4>yMAa@?pdGCw|E3=dfD)&bOQaPu3uxc=tvtaP+juNL=rwt9px'
    'tzfpW9c(tc&d~-IdcIBO!>}_qstinhh}+TJZ`NJ6d%Jce9wq0^{*IjXIco1i36Gjb={FAq)qBI;WWYDF$t--*%Wi8C92e7Q>S2I!'
    'n(JR;S8s;t_m;UH0^D;9pFX#pAs<wh@k_2@hv#DuhPlsOU>?o?^)oQ8ZA-D+2K(yh{9(EFpDsDHiUw01#J6;y>Bq`({$i=?fqX^O'
    'h8zgjZno~$&P1h)n!urd+pJJ>bL%l|E7rV!bwMT!e6|M?9Ek9%0~0PIYgcE)WhZz6olg4X?x7_Bmfb(L`k6!q`#pBYyl4vEc75Si'
    'G!0kB$x+_#i_1}As9*g9JSu3kG>vLcSNVf#O@dDMX_gK9S1q1ImQb6T*m%CT!E&4Iu0B!4Prs=aR$f(v%7yLynTDeCQ3ca8EM(vL'
    'mq%w=-`vSq7bzO!d_OVeDP3tF4)PRp?xkE<KNiE`<+?~v{oUE272H?Sg=KTH+En^VL?c%BJBvE>C07c*%l-6QZq-jt@&7u?qbI4;'
    '+H{l<3STaRi}eHGoW3th;8iN$w#?;Wt8cy{vRduJA+^hOR9Qp?G8cnko}Qj7Ke{~ozwbbuk=FgvMqSN?Y$ZRGq&3s&p~bl+f5&+_'
    'eUM8DYFBrYs0jI}cn#vt2iPx1=OwoN3j+sELBZoA3CJ6;qebCYKRGh))u9E~;Jb%!@9`R^8NmR@$!=L~DIV&VhEtEqfMir2l`Zsr'
    '1C+9KAHgmE&27fJ%5DvVwxnO9w*1DG9r5G8IgtuTc!?U{<UKN0`L1M@T{d}%dR%tPakTH<$-7zqFk;bcOVlJ<+=AYmiS#(ED*U`g'
    'M%`MS9&?*IdqpqW@Bh{_CihOTuf@HyWpEoEB!tU(j*8)Pk<^*%2%YQ!nImOmf@xLw%zF2Z0tg+aRI5f_7MS?okDrf%CBY-H@oxO^'
    'A%e>hL*HL^QNxuXotRo{Tpd&4{bALX`|w(Gh^Mr4%jlb3G=|9j=<b^ZwXNFQvbNnnzvH6Eb=MudLfr&g*!=3b&I0$p89TPOT7o0b'
    'QNz!Z<WgGcS5!5dGtl2O;r+X5mT&XvZ52*0)j!6<wTzBMHfoiFbD0KD*zf0Z*BZM6=U1mdy!~3eKck!Pj^|*@b@NNn(;+pwtSZ7`'
    'YBTNe@iLq?zK*uRWCxQaXf>L#quLSn`h_-zJIMENZy0j&o{`f0`iq;T;baOZmuDh~r^z4O;PZ!`q(;6>kv-Jg`1rm<h8gwRR|9u*'
    'dmjg@t@_}DqaT?yx|U+K9rJF=SA`f7NH**L{OYH~wqLR!OecoOsv+W+B{6vFo3LWMvw<4F`*OQ^Wg8jDt56Yd%gu)#yai91sPqK~'
    'oaRJ@mBv#@bAyTMub*H2*te$|^hOE;!sJ=^As8DueJ;HYH@Zv-{XBrwHfAC{c+PpeiDbN6I~!&<q&jYr4hwpFdGP^WCE+38sOavG'
    'SC@eU9+;ex2{mjt7%_)|fD6L`I(>T62Ui_634$fpU_Ysp-^hl(FfSWvmHn=-byk;cTz)T4{PnYjawZv7%<?b3Id3aBoW<SPPJ2q;'
    'wO$eO?tpa%-V;)H->vW0_~RR3vu#`6-kyhYk_G5WkqrLrY%fbG|5mfwxVm$xd9Ah$4nO`-_krLV|8W@%7#>3SQARsW1?Q8vovFLg'
    'Sh648u(4onU1GXep9s3Mo*><8g}-mu*3~TC-iRV-Oq_1P+T%O4f9D0{>0kJANBiR48`l7p$FH!c!S-QOaWvV}@qR7*<a8rE_iP}<'
    'hjPfiIS(yni_>@aahvzU?7LN*TOi=g>Wcd5?$^14!uQwfqw1}!fa~q)WSB~W@eEvSTeO=qX&?2W(OS~#GZ~q1c-SlR(k<)swy)L!'
    '4bU4)UjA@NPUYi-J^%R5X!B@+X<Ph`o1O7@TQs*P#zU?hquI}<kM>ru(H1%3GA!@k&tv|8Ba0?h8!wqzek1ZJxANP&d27>rt>4B+'
    '{g)ScnfC!!-^<XQDfFS;m|}7L_?+UU(m1`0z4~zjUTH0{65o|_>4tqrw{udNc4j&%o6n%ii7oCRUaR^x$-F@L)ve5^`sq{YWg(#h'
    '3T3c#YkKSb#VzLfCsZBVIq5S7S1y)&8-v~+L0ap52y3s_(IRCw@Y{L3>>&px+FRI|KyE+3Z>-O9O{C88d)VFVBf_}8CoNWerRA#I'
    'bH;gGUuSz^k!_-4km@U!EUMe2IV|s>eLLvCE=^gfByU^()NhtO5q@<Q+M_i4ynM}jc7)1ytz^5&>QBbILQWU*G!ocmpX&u4SVrM='
    'v<hr<@$79{`OUS?Z#+0qXMJ<j7h*SLywM`Ee*Qx(4!p)eexF($Qa+bl0&Xy;X)vszgLv}VZLP01-ygZGj&G4&O?wP)$`?f?tlr0Y'
    '<2KzcMy>U-ZaF8V2X3<4uWvEvy71wMXz&sQ)9)c~3p0GVeyk4Kq$fe^qV~8R=fW0d|NcO5X_mT>Hazn65kTgS#h=&cJs=F8sZ0TS'
    'tG;#MpPsM2$>CItE54i}Xk*stEJoXPes$qW0*6H69cK5rbuWFvY+Uc)?jJ6~QO9yQx$+lIy6u%G9sE>K%@#0CgrC0?eot$(;H|}I'
    '5C`&u=V0u~uI8TC00|4-AjU~dEets?Te?3Q;kRxEP~EmYJRc_beO@=EK{Zx@XlBRiN)V4fJ_$(Oell2>kM(Ud`Lx^z(a`IM!mqws'
    's}FRzlxj&>`P_9~xA1TO4f0eM>4U`dk7+fs%Au&`cUClq&tB;;Hfq9e9$qt=J%q*)Hu=W_O0teob62Na?)8JO6|`K0d&R1_Cy4!v'
    'c+c)dNOc<r+JqW;-`I9{Qzo75%<`W`V^@O*Fa6v53$6pjHIYlHQ9CUsq}F6k(B&_*J*SeMUwJ(1G4(ocfhnROdaavHx#`!RRMyM('
    'y3`(C@6(qB-GkS$&gm;nz?pw@IAJ4n)(VIKDluPQGP2xI0Fa4W_IkOh>}%lrxTbrO>8`qLmbFK#^Tpi_PQa$~l!H6Bbr6iT3<k#j'
    'UTr@6^+`NsUV?CD4B-U?zSYHD|0H$J+2G<k5>vBe5E0N93}MVtT4D?If(OHpZyN_tS;Pb~b|GbPVcJ)82G!e^`m2{?d9@?dUh?u$'
    'SFthq<j-QC9&NPxMA8O>&2DiNAC;<coWfj-dY*6#i4jDv(%=rhy#(YkF`T&=6JS);>z6n7%g+PnS@Yn7JbK2nxy@wwJeaks_KDr!'
    'O6^7a^?H6v%^g45F6zf!o4;MkD8st@wc^KH_REvcOTC|aVE8HpZtX4n{B;Ss-;5Wxdvz(|!)*VePX}+|{J2!5Q=RONK@vY{^(Jt='
    'J&6`YMD33J&XnoH7fF5yQ~Ay)m$dhzy6g;mcQyF+2P|b^*}t=w_DZXJGkcJzwl`@cjZ1rA+?xR63bPJBb#Ig<Z_UQ=`*=U@{czws'
    '*6uS#7isgNU0&l@Ym7B#+|zz}fB9aFyOpLD84->pFJ)7IG>?51_G$N4Bh31JVO}7$;*}{J(c0|XHYaVg+?TQI$^}|)sQx%xy_LE;'
    '*r0dO2EX`r;lFsa)k7Ur*X5fd+O1$PTj^gMfm28^Z}Q@xaaxbbtKCrroJ4EvRSK)e<CfhZW{)@_+@2x9)Z0L{PJKfC>bdeRua#Hh'
    '$256$hV^SLf1l#6cM`s6+x`gq(kYz1)_l3%Wlo@jHSs5QZG%08s=dLi-CLP+;w*QnGitr+SP^yq<pYS<9FEIK;9&jNIVQ<UT6Udi'
    'AFm(T*P<?i_1-7csR<I}fqu+GqONZx{kFP;orU8ko1($GgWGLSf){E6k?xPLgUt!*jVqn1lYPGU8@}H6HSgH~JiGyl>+5;w6t8__'
    '@pv5o`a(H4J4WuFW6e$qHPBes#<j!QdQ9K12P5Ol<u4u+rd8rprwu&3VYBqKq%xjNgJg4Z<Mk20k3KaXWl~g&4#qB$X5l8)Mo?!v'
    '?Xu2iQ+aRKnsq21myE8A-tZFn`F$ITxaC*JzH|sH3didKELY(eG0*lLE=xO<4t6{ps2#Wq-q5m<8J&Bob8xSHxpLOGMzV{&7E|L|'
    '($$0Fb^hT4_LQbF<N_jp?cAyrNgsWO%a7NyorQ+(uyqN1t+R2PFJr=|-m_|NwN=}!X7^fq%StIUf8JC6rjVmWZz<bJ=NIQoeS#!?'
    'Uhj8%olw*#>gz=MH_W`YoaU%xmpo_Ds*QA^KiF=g@`FD>L<Zdk5qNs1@YbvC(cUOkdv7RST+r?FH~+zC`pkiIrXA(DxAI-{dmZN*'
    '6qF>(_4>kk$zM)zde>Ic9|7t*OOeRv?R>JCSeEs4d$?vz1}m;Z6udt5o43v{9}BPAL89~z128Uu@5ZTB`bH(B?!BdF3jC=p`qQ+R'
    '63|)4uDKTreQ;@Iq@g{9SWjZ2+Zaasa6BuOoeDy5YW%~=b=W_kV=7x74o?d_Woh$NvkzBygq;RQ1#1W2S?!6ptA_kSW+Q(mN>^12'
    '2@&ZprzWwi>;hzOqtkgC_C5I2CH~cG;IsTO7aq^+TWX<ex1!5igX_z+{&8L%3>rv>Ge7S{!}AqYcP1z!o~g~A^t<fAcFUh|s3`Ck'
    '8XL*-xU?TXKNWpc_nCb$N39{zRJ)FdB*7(>#l{-Bmk<`xPaideqHwpi@VdNr<o><A<^{JjFF<lwYXx!HE_d@<x!R=2-2CMkq)^?A'
    '(gpFZp-f<?GT@H3IU(PY=rRr);ZPW@;k*u0x{Dr03+g_O0Hk{?E#K6mEeu|JSvuTrw1f>O8@*zGe{(obifk`76aETuuMQaTahP*z'
    'PouYY7%WTUZmmlyVd6%wSGg=LwQBh<hD}jN7A<h<a%3?%*T1E0X@=^K*j$4@zOFs*3`l=^bVGZMSC#1Gv^E1^%lLg@H8Q5hjwW0F'
    '%(d>*ZaS%3f~w6)woz`k(op5k=`DE@!nX9B2{rS+KM#NT*m>o7FP88TzS8k@VcH%xwg`eo+@^bKNCc<zpj5;BrPg6?OJns}+~_IL'
    'x|vD(T%Eek*>aXGWW%m6xCxFZ_UCIXHiF-j7KbCfinM0T%Qw=|-^}b_Y<1tDu)N+U$1_0MnqUuI6||FX1A0QIO4s}&&S+b!idgu;'
    'Th-_w^oQ49og)oaK*r;<^<}~V=YZI8Gk<Q9_@mmS-O}s0$l8CBe%q*3Pj;tHk$;?a`ec<_X%0rO!|S7KU@{otYHtTO-`T(YZ=;Or'
    'I)vjbuxp<Qr`r;f-Ozy^-#XJWkPVh`)3J@O{D&6s<ROvDY>rsBPcs*v&F}E|XnPq3+pN4UA7ob5kzXAXfv?m)e($q2a`Lci=+1A+'
    'VOeA#n6Eu-><Aa;rQPecTJHS*)}K&v+!UTSh$Z}3O#hG*Dal!Nh?HiFHaZRHU;ZN8%&W@N;|lNm;bU7}*qSp5iS?Q5x~pp=JIPXW'
    '_e@X58{5clgf4N9Ve3UsmWO%Sd;FoCUD7U(Rp(Ie665N>?*K-m6OVwrHz1};qdC5oCe4e>E!DJ)cE#DfGFnIYTck3CfOqm{69v#q'
    'F#6L`13f-i?ZKVcL3dZ>b49Rg68~>bI^X?BbRZA|svqWUZR_tL@^OlF^ER7)T0O2C65Pw~b{cDWNfIV_*4H8rW0-xlraQDuh6piJ'
    '2IV{6sLB@btFP|JW!kIp$dsCv#L*S4R{kiqLYe?(M`xy2wczBj#K~!YML)?^C;*yWD}NB%-lZoHbn;aNDo?)7X-T%-=A-+Yiz33C'
    '_xuGd-#urtSYE|<6R0Ad&kTczv~8(!f2%`a@<>{SyWJtlfTc<E5WGgCz4~pXZKYK-^Xi(`#%u>SqJMiI)FYWt$i`k!=#dfb+_@$U'
    'R!2Gn+HJJeq5qz|j=D(M?>jA1=#{q)d1aU@&P|-jn<yo9^bGsGg+*fAH=Ufb?{A;*6jpewS9Hp3xp#!>$9$TtWI>w`<$YSMzGkBh'
    '<Z^bM!)S7}Z&acFP>`uM@?I8+J(96N0+s~=7dQM+>pkorPFgtnp+dz&zyz_^`KD2e{%$wEo~fw_?~Q4R?rd)Z#&0*A^~*k)yVQJh'
    '8?4v>`gj1Vj(ghE%Go-}2dt_Y_OH$nCYE4qH8A>gLNfWF3!Tg7+;qT{dfOr8Q#vHoRQI%|@LBJ)-&p1VROo~BY|f8OPdWHifuWYS'
    'WA^IU_Ns>d;yki`yT!>VX)o3%h!d3dTNJdl!MAM>CkJ+z7mwK1AMR?{-bRCjdfjfj!nIgBweVNdn@;`F^0S@s{S+YBjQYjn_^gg~'
    '`ULi{63Arr^kfw{*C65@HJXU*idIgm`?1st+o-&_{UOKaK4~61vs|UXFMulV%<wowrO(gYX&@Wx$A7{2bCj92Qk_jen7rj}h{`R|'
    '+y%{JZ1mTmBN}1vF@IXu%Z|ExXT+@5ntd=+tZ)8k77h@{rMbf}tLV9l1LN1%+<rIpiCvP6=~XP>^Hx1J5q<ZyNDg<ztNRpo@R;(d'
    'O88OXr`%3GM<+q3EkA=ZcxUMaFhd&k`+-i&ZR*fJ|MJ~;k%6m$g6f@K9LhpRx$2i`u`-#1nOo3!0bl?Mi82fVpJ}&w3wd^oUe%ix'
    ')|qFkTKYnLb3QyCm;3UHsnl0LfBlxT{pI$3o?6z~z-Dw-Lo$93DEpT<PZt~OE)AfQN%xJS-Nw0|Y!3_eASFC)mNh4z4Hn>J5UTL?'
    'iVN%ZA6x$A$>!B3eADk^3}V<%R%66=Z{9jB##ZNej&VqU7Zu8D!O8tkh5PpF-HBeoCTdGJ+=KswzdS3j(h~N+6|d2wwBP<?dnXhr'
    'w*iP-{X=A~c^@KF^Zxt-&bG7nr3KL@B_d!RE%gi7x`I%l!PS~+dvmy!aCf}gkxS8;Qei1q9>8t!(}n781p22*G)$`{N|Snf<I@C&'
    'n-*Mpi7Q_`0bf-umCBuj-$XT5vZpVs&~|`KhRzio9L{*y{p@^pWOU%2GC2JFo#rbh1g^*Q$n(C+=&>k-rwady;6C<DGO!e4bn`PX'
    'Q)KBJzVKweEg!7{fGhN|JXemQ)s?s;+S_I5G>|Sd^W!_)c`vzBA=W!z7x!;wcaq@;8pY)zLHS5j$)PqBo46r3i->Hf@7@-?g67$w'
    'gh69}zIv-xsy5ec;xT78l|^Cy@(f^#?$3faO+UcgUX2%n@`9`0Yai~aZeOLvsJgNi-tb*slmlT8XiSB?{@+&GyB$u{V{9LN^E1|m'
    'bfm3-B|PJPeCKlOReQYAT`RA>Vh`_?8Gblpt?zx5SK)-PSI~R)Sei<mT`F5*g2{zDBZR}?=A<HDj-NVAY>n)GlBsp8^T#ZH{oObE'
    'F=P7*SljL6v9M`96sO7FhU|G>E>=-<NYD3dL}rhr#I<{Ooo`8#?{+n&?&$zU>(vEi_(Y(@2dVW`vVZ+qU|!V#vm-E2&Po?{-`XMR'
    'eoX*H5iQ}zME0&&hmMX8pw65SF>d#z*F5*QAw0(-=8Ac*Q}@WeCzs2-c`v)-Z|<TFoSQTBgH8yQZP)4KG3_(kGLUBNslB;Bvu`nS'
    '<x(o4wRDMJ$BT7$Ua6vE4QQ4}gR1zU&NbsfHLGbqLKh|I=TDOAEhW)&864-kL$f{FKTNVYHdp<Nj7l>M{R`%zG7>_5d(VJwe>Uk0'
    's9N7OUoNY6=qgWDCLmb+$$-I-j-SF0*Z;WFpq5(vp*r_ouiIEJK1~rLa(u&d8h}%}p4zb69%0#bghbSgR6d^AF_CCO;+#2Jmrl67'
    '!}{9kQF||6o6!%~mu<0ZHII|=Zug7<A90EPbY5icbGkWMG+J~vmeWu`hSFTSd;v@$HE&^m$tuJ_fV#*L5Nor8yR6vV`F3s8e>`>O'
    '_V0!BO5?uLur%A?);m5=L~9Y!R5wJLGOZ^?VocEvSXwB;R1Eu*s1~H7dn0$o+GkU4JfNF{Hx?tV`FQ^733kKM(Wrha`6Ayr3qve@'
    '*c=<}+qCj}Qtnuse7lxERH@fV-HA2PqlK`=2wY5z`ei;Rit&?U{dTJQ9e*RE?Vq2@28C9~lI0))3K*L6p$)I{)=OG7uH7<!FFobb'
    '4G*~cd0TYWn-e1?N8h#TJaKuSjE_RxLSXceIW1-m%r!axcvM05=4R~zU&8wIqkrPw+KF@3YW122zt*lCVFZf$!xAJ=QwPJB3B3R<'
    '{5<Wp-Yr09Ywy=~Bf&x7txMG09XEeI7dBARrF{N&>t^<DM)sq5Z3r0t=!n|TU9-D$`P1C%^U3n*SKor*bOk?tA8Sozz3eQbKPlM5'
    'OPiD+ts~;vt;Wyq<Lh5HcLg+<xNYsa{C~9C`su%c_ZfYP=cKNgh=MwYE;%|Z3|MV5tgp@QICCMoE!0_sW_MO!MlM-cmo~;`Kc9Bo'
    '^JZcTAV4vy{y)xWKszvaYnO(-X7Al?CB_GHG(OFs>nGif8sW4$n(JzH>0D*t`k5R`RkyfVmnAd;gX$^z`PHQxH~u^4d}?cd3TyS8'
    '-MeHRpS-$>*4~D3&461~w#MIGx00DpVmDL^Pb3dr#X^_rFqygS;Wcn=?dqDl;;#LCqe#9rSI<BEZH*p7`{Hd%kMUU^9xn_!aF;7v'
    '$L;cVsg{k$uGbfYU56fC@_B8!hc0<nRuatIy3U0si{&(6%Iv@WvFIRAdpBZMdtNoEEuxRaCC4YYhn8=plIi4b)}0z|M1SxPK`$eR'
    '2W2$(_nR@6+QD~_uMgr5RJzyeI5JD@Z%+jSHwkP(0WZY63jADIPeN8wmbel+T=!;c#B@S!mmK=1=LT57ZEt+(_2^PJT=P!mlxpO5'
    '*i1T4@(J*w8-l;{CfTCivd-~qSE}_HBoDqSwgQy)vQQTD*Ggzp3k<`7+%whcV%o&ndM;i1o;Q1`<18D&`%%uD#|vH?%z;zg|J^eV'
    'L<)Ug-Y!Bb=|gR3wOh>W`{q(66a2jWdl_K5`@b}CFpNE_sSI!6eD8z#fuG9cMqfkRg5h_zJzApVs)`st-@dXN++mfNW#>mJnsrdU'
    'S$*&9bZZ7`_pq*Nf1rHXx_#Byh@zaAbEJ~Bx0713B2udIlzZNTY?W5!v~&Gb9|8KW{|))hr>9V~kNfCL0L_*B>4tUh!>gr8p&RMz'
    '+uH8U)jQ;drw&sWtk$f&ogwMssCIVcZ&6n2lg$Jb$VNMEG2P$%62{n)1;!@(UM@l8XXM-G7;Q%Hk;JD%smw<#dT7{LuCNA}br|Q|'
    'e_U6`1WjTbN&BIHD9yVx+M((4ZOOyP&qo|CL>zq`?AB>itRTSdMFXj8(R>N7Xo22r;hen|{GD&_amv}(i?DXDKN!6A9P}n}gHv|L'
    '^CeM^J?6r=PWb)pjrxDPM|oK%`Lx5cjG1JPuv)aM<L~;l2#;xA)+)zaeWncUdwKUfhBK&36KLfmTc&E^T))w``HR;Zt{&KVTs(j8'
    'c&9&E)dA6hBIA$8DJN(HqYuic&$Hq+-dB+6V;gH`_e{YcAEJMPcrsEq{$+IqCN-VweQt9qcJD_2s`y?V{PnjGk-tIc&UiD-Oo;a!'
    '%dhll0-sEmh)s~oq_NL7xj20pHQ+o|%IL-(k_r78%|Qz)1*@wk*q`M@EjwT(UA#&^UecAXy<&-0PdKRAgb2C*Wd49Ml~{vw+MhEL'
    'lMV&t37qb;jaD^Roht&Np|R(O`?c4GFml*j`kc)b3wXy6^zU6np|Y9{N9|S7a!Orhr@i8S`uV%~z--HIB3CW(n5VPCs<9<rh9w>v'
    'Ct~a|*>FrCOC3Yhfj)2C`>{BgU8YX*tLM7+HaiDYD2p9D4f&FlArM~hwL80LG-SVpb^`W-UdKRc-m@LvwYGFwqFPF|d<f#&v%NJt'
    'hEt|W%jlZIhvNNvZ!BH}7mTo_pyfZ3Ri)Xf3yRX^R#m*9vP4d1Sa`w~_x;%Jtc9EaX6LLEo4_BHJfhlW^12ubWQfWj$kL9R{OWY8'
    '$taE%`&;lFR`#$I4VHQ~$?_9x<VM6BI*;o+jP3@Lsg*4r=eT#RSXrI;|Jg;e^1gHf!g6aKRXZUxCXCtd9g_)`JZZIQuT)9M$e_|E'
    'XuLW8!(0rOBoOt;<90gY-(fbN+;6A22{b|sc8%)cI%$-e-PY+opF7cMS7~gRdHL6;wp-o;7P1wTm-ym4_x&49&Ig&*+6~_4HRQrG'
    'AG|C-%~>ZI!=u~n+Jay#Dl=octL<peRHy9fQKiZ&a=*K=|MvMnM=}^K2g5Oc@;82OxNKo_#zb+takAy@)&aG2&(7*~x`DIGWg`#7'
    '-JL-k$in!qbtMk7K#BOLq@7Fo&K>W6dkG*X`q-x%#<i-Bx+>)=k-ZL?umqO_S6^!WxZKNZiCjW@LJvoYTM158ehow|*PT4mBh-5&'
    'FW%B+;<)pPW&C?@9TVMzUf}I!4;+g18TQRe=Z1JYy2C`f?v!BvO}pLAk&DUKo$T{G61~*pcwM;h@vv`9?&{>;JR2f?-JY!K^~ZPW'
    'w6t0*2lY9)-SA$h0!REH7Hcxs%sZ(@{&6Xs7xC~-olhj!+l@I=JR^5j>;xWE69G_<$XLP4-KN#kTVUnqBR)#w36cz`39!&AL$|qo'
    'cjyt`&aU*hR``b;e?^-~usE<~LcZ}vskr9-qI(mof0SUJR*aKOGV62z*Ng!(q4eMH4X&Ti7luh)eAaYCa3Bemux4?T$OC48KvEjc'
    'CKS9F#c891-^Z&z-gK&RtDr{(U4}9mgM@3tn>xWO_yBtH|K?0Lzh3QnPL8!9FUtq?#gx0G6BsQYcsARahHT3AmZwr6K-$ykDOtK#'
    '_-@sYT;ER~r?2b@!_ubM5kv0Uyn46ad4-1cN4hXrxO$we1!ah6ys)i2%k3&JJr#Z<wa0jT%W<liO@nO(E)Tcz25+<TOg&Y=PfQrX'
    'V}JNNmd}W*{FjHEe)Ab9_x7Z-pU{;zlGOI^+U^wWrSLqM(y>nGPy9Swgj3Yo9in&dNxYbs*$x7|WMZGu&7mBwwOc(&-F}M4U%ip>'
    'K7ozf@bEm;-d3i0a(`B@38HTe!J+bPVAbo!TnS%iEr%MiNOn#pX_jc6XN_I+4|d63g-$;GItEceh&{xgA2k%xc<NUU)rT69(3QOH'
    '7u0sJpLL3k)ft45w?mVaa@ynkn>_OtWX|c)sj=u3_hECrU--bFe^99Ma4@v5i?sg3$t!gQ`vH46e0Ctxy4xuN$StC_-(erj#XMLC'
    'VKCXf?vYiC+>>j6kxt!52fO}oeQ@9Fd2g0>qOt=8B{n|R*U7&+^Y|iOs8z2skl5_fh$pX@dmcAibRd0;iadW@fz7~ewTMHVgkE3l'
    'T}6VJ#=X)q7&~vty^y3=U6VTsd`w!?-~0z`VxvbxXm*DqRWg9o>UV@zaeUUtX2hZ6!D3!`Zr95x;(W_cOW2EH{nb1-C(KkG=a>pR'
    'XZf{djhLOPb#C?JlWAW6I5T+=oy3~(psy?7{b6b`(S)Y&Z2DLY|1PGDFCHqNxQqSknGJSCuF~Q19O*Ur8F??={u3nZf%Kk-CH&)2'
    'kOY-DH|4IS$!Njs8LbP1M(BPc*G4}F<Ju=%gXW8TN_}3EFIrYNli@P#Rq%CLU5s8%$3U6{T5cQkgkC;|zk1~bGmHM{Fx5N>RMPCn'
    'XvnEEN4ywo@b>=33w<zqv2?!}pflqUX)6BJ|7b>w<wl9NOfI7+ea~1B-7b!+mbJ8h@1mc+(VVSvI=tS`qtBd+nE5`LHHY;Cz7KZ!'
    '{1LBSHl0zK<#%R84f_u3qkHYLBXQg*21#LA`@Eqw*wYxr7tXIv40j&;l>&o-F?r386~1COwr4vkRn-^|rff5K>~nRsL}Je<n%mb`'
    'q|!w_NLGjT;v|X}Z)%lgW)>g2>}1xM`aj?Pf>cIrkU9Bn`LiQO)647|nFAER+4Y07A)gPwcETXB)oAFaqxx25&7Z$oa$;l~2Mv-@'
    'YclEG*-E!rf92j$`thg<Qq@b0b{Xxd7IQCIqF@e}lZ)($3gGP5{g<NbFQzF1G#1Foc8F%qrl_y@vT{bJ<W-#~hmn+xl5f?E>$~Oe'
    '_Zs9nYN@C!hYk1atriuw%66*~?5&u-k|cC7i_3MGeCp%#yr;c+LmQKNZv%HW72X>k&f<QDqSh4wYsnn|mp|W#$CUNax;!U{#cWMr'
    '*jwvL1}^7z9ZL^&fdPcXsx_)B=K-yKF*{W99Gnxy_WvPJ)H&%yi-+`gmp2lFips9}tEau|K@J~d=e({Sdt()9KD)Q-@b$>3{J9wV'
    'pu$e9+Mn2+`601EwDbLXnTnOUiw2#kt%kk#Mjx>243PMzUM=l^_&}ETdtv2SpYN<%dmmNYxz$}4(v+Fw-RF4&O^kzu*q}7)k?&!T'
    's*B2(rDv~bIX6b1$%G&6ij`U8iVT|FVdB@<T<$oRPTR#0bH+vM;W923`+yf1NW^%3&>r^bdTzSa7<>=2RkOnk1G2k8CTn0cV6Nx3'
    'xs<a7Vdh<KGIP-+{q3o^Lhy*3;)lBsRqpASo1gqMdbMf%MKEI?6-f~8u15yY!cBSz1L3y3GiDQwG(m;4S2!7HNQKnF(repsBT|e1'
    '^#Lw4Wdv9Ip+jUJ{)tXIUa_nw-&UEz<WUXX)?M#ocDT6!O@_^TNL%Wa&E`oTs{~{*hJgAU^_8mYeh!ly`T25pesw(2Yq}(?TbnCx'
    'Z1u-wjkXuTbicFAF0|yj#{BgEG9rz6H%7qlL{><C95aozP#&e(dQH5&?!-UM0L^>Pe|d&xkM9iDmo0M-pE?Xz7DG`zaKq)PEUxeA'
    '?oSjnMT0mQ^9JD`*N4Cvs%UYw!FCOGxMbrxHGQ&)o^o?sHy+}DL|t9ea%>d+EvAntrkNtrln@D_h@yi~Bz-Fqs^9+J?@7=3J*Jy$'
    '@4eRAYwzoP{pZu2wY_I1Jb|Fo7IrA6)Hty*PbPVht(vkOG&c8y_r&6{UbR3#$>xnuF@L6wrGH_@%Fau&{;brW-S^k-$DRK67;2pR'
    'EU3;}!Mx-2p5V!Icq061O~<Kx`cM<yo}cV^5~ChaVsz!!)6J#7#EI6idNE;!alGgi?WK3epkB(Q{Ogk;(dpn{5BwJ__V5B#!AdoF'
    '^t_Tqh(kHe{^;<`IVjG>Jm<s4H8hz0SXM6VVsSlluuz=DrYURZiO=4G)eGqV<}X}DB=vFYXbe`h7TN(rL>Wz^!>gz8`Bi9KThn1h'
    'dGJRu7)vDHTbE5?t<jZ1YbVa^2XL}>*i<9US(-GDz&H5S`K6k7y+U?Ejq^|Q3g_JPl4XTe;=Jq^EbkuTP3$+)R<OXCcdK$7%3>WB'
    'OENIJ)oZuGVZqvg`I!>VIoDm}`MW1xACCI|c+s9e>(__IIP+D_oZYX0Kiva=taI=!w28CaQ~mFBTR9vnEhv~~k$pb9$x^!D^BJ!_'
    'r%2w;4JId-#~<FQwQRzhJlLEhsmtF9{_fPYv-G;8oK1`DHmnmPx`u_jOaD|JR_f<*z4`^Abf(iWz9@PAAYHzmowQb9)l<Bsf4rsD'
    'IfSQZr<S#hso1jvgQkhLI<;bBOwO9shEQ~bZ1V1K`rnb5?bzO?=4Va_C%gK2rzcSYCtEjaw^STNV6ykazs>Fu*iPW|m9ec9T^(lh'
    'efJFTa9>%~wH=<sx?Ac=RE<xDJ@~SZ&pe>%mD}`s(yh*yrDl!RW^-J6`*`Ltp8wN-$)_Yt?h3ZSiz6+aR@f2U<UMJl=E4W}s53H4'
    'bxs|die0XajlD8D8TF?)n|iW<Rqxt}v-D1XSf_6=l~$bAPycNV5f(no&$~gvtyfim>V;2`;oATS)J~6yx)U{w6<xg=4F-?X*u^!d'
    ')h>B|uR_R=(L~$^AX-XJCp6?A%jxUqC)i@E`lj@UabQ>E;a-|Q3`>j+#JWsmG8&HdKzUJHEG<a$pcxuvA;%AO9=|U}(>32e3VJ+5'
    '=V`njl{!{ds{QI)^o;yAWHPP#7AvD+dLB^Gqk3QpSj~zt-KpFKv(sW2cvR!}z&Tk@ckDu|IXFPv<vqDb?863WzF2)24K#cB<C_vw'
    'nl|RA)X(=Ayj{1*Q$8<um%)3v;9K3~=*ndmgZtS01u@_5zHMNXH?PSm0Ex|m4juVd8rR!rUf;4o<<<PXUmQ)?Qdhv)>hj=&S*5!2'
    'PtdzqmGOzA#m;#)iHh;cj(V5~g>gZUD}}0-ZsLh2`!-InjdLPTa6zx4xASh){LP#CvnZ}Rgw}4rFyClg58WZKkETME{Ja($XgK=+'
    '-pN<b82v@EGgIgVfQqINP2TRvNig?bScYlpR84w!hckoz^$THML|x585J2*Y7dYh#V>P{Y4)Eq>445#j)m*bP@kk6ERzPT7+>ZY4'
    '^gWM-#WAf*8~RoTz~!sOcS8WHc-C+4qA-L%v&Mz~C@ZBB_OwV@>?z>2H{OgHVb|SE+lr!(Ll^OV9{}GAQJS1P^(6;Q2RxwK=m1*3'
    'dR=zl&LWV6oS%-!M~}7EyN2gywC!`zbT!<p_KoG!>x=HSygLz(vp|DOU^`{U=FFu1(U1yu--)_dmV3^No5H@ntk#=FYKEGu{`OVO'
    'nqvt#Z4N#Ckxou!US8<$CsysZQ<J}g_M^ks!`<_GRvM>BZ_h+8!F0TIyG%ZIl$T}d^7!Mq{ld~VwTv&|&cC^4$aq;}=s2&=NAeVV'
    '%R}j+N_b2O_Q&g#NUbw|Hh0^6xpEW%lX&^0JdonB5Wh{KeUOdGjC-8#CPCD8HWL5z2L(z*DJse%Q$;I@k;B0L!y$a6Hh}?zYz)^r'
    '_wM>Fq{E&xjJ{uEKdGI@yZ#LSC^g;CAYB@k4)8LfNnt$i^8fnXSc#49y*?8hnDCO@MaD(|Rh;P;g*N?XKqga874~+AIM$P?Y$WrU'
    'GBzu<j@AT9fdnmksF0010|q_bTCbm<)}F3PynM_SvodPkhtVGcFB8C$9$oQ#j#jz71`R>!(eO=2$owbZp5bP@-=pn)$k7GZXj8dL'
    'JeRX;0$w!v`t$!fZ>QhN%V-nn>g{VS$R*)^6B-kHrW%-nD>Li-RCWliZh>#@zHsWem=A^@t&h9&6>x~#*@JsXd@WdS_4#oBPgmX%'
    '@A9;IXtm0(V76%%_qE~|oe^_>mB4@;0@T@sRnO(}iCfvz#v(TF(8a!ndOO|dT*+K9n@**s-p`-`nCZ_~L2BjeA;p<T(YS4ki?q-|'
    '_;9$|2OjNj__pJ+d1)st8f~rh|Bah7d_VeP9a(GMv3xDWL&8P!cQRXC)aF2)1;76Mz?d)QvjMW5jE0iACuz*~#{;Va^eTg7&uMxc'
    'F0aJvb$4x@fS2`sbt|3Iz1XECj6jBd6_8^gQYL;2yUxo}7W})nWGqOvNmAJ)R@Y=pMQb$gg4aQVJ@)H(^*$YX;D{HK!RHH(Sbr^@'
    '9!IsC(;Q<7b!=$XtZTsX!`T5jt9O$8`6ubiego)GuXv?lqt6vnbWfXspdZxnr0s3W4xMWo>|ArlOk;@Y>kNZu)z;br<f(U>4dmN='
    'r`jaZa*k;?y&rz_dJ~xEg#i$@&Ky@;|B>kDnXZ_lQ%|@H%}FgPjT)m<^SboV^=Auao9b#!tKgsnqPuV3_rG3ybL-Dv7`3eH3Nrcm'
    'cPiKXmc#o|9V7N{_{J)-`i*;S>E_u+%O%FU%wD~V`~aK#aju}9r<vOmBBYYb(dMsgF$DGU(ymn41F&Q2&JRy!kB3t5b^5TMAZ19!'
    'zH{bvsXM?$HWqlLFG0hehkQ@3M}32rnd^HtSvHdP_<mok&0ITmuQJkjjtT4e@Lzq5`r-9uXICEwgKlG^^??@-@F=u0+L<gskIZ9N'
    '+JmV%A-?HIhoF(Y>hTn6O{tH+db`ykvz~C-*|3L^gH^^Rh^xz=e-e!MNq7CYekzk)bGw9AVvhj`&nwFOA`-jxu33Q5Riie~%eaig'
    '`gFG0=K<^$mudqv#}58NC--C`+Fxka6z@NsAonrpVl+2q$7Qy7WBgdISaz3-t;@dj0Vi~mOFHKZb6J1t7y9vaTj_Z*$yobt(oojs'
    '>vEw!N1}D0j@KjEhJQLDGCN!@!@DEbcGFCho|`7(5+KX4)6Qn%$!@M)fZ9`QBhGXCa+<@(@llK4o$ZyK_*F!Pu<OVl*I(Z|DGutV'
    '^RI4-39Zrt>Dzu?Lw4J87VZ7aZ5|BGc@W8W!oCJ^-Z`;E<#?6yAp2}O&N9N>Mjqd#)Alm*31>dJBvZQatZv`EA6~x~Zy6=R_X~qs'
    'Pnx1i(}$cWQ*U}36_pXyn|03p-WNPKrdxbJtd-Ay6!x$dFGJvVUMyBEV0NFuF#<#V=QY1<etXB)uCZz|&_z+7gF`Cs4Rd6>*wh-|'
    '2wg~*Cf6Ws`@=E!2Xs`-#;`JTD6Kpy4X^t#46OP0KmkPpC9QT@nLd!8&+#hoY75?|!`m?jQ7NF5sa_H)nnd2>?>r}5TkB=`Agz5Q'
    'zYZ#~-RhM4+RU5J#<e4Rwxrc_(ph8Tl$gBSf%*HrX(i?I+3v0T^s3x!CXMoUpB{SW)Ocf@PEn1{esP#^vh1goZSJ<qgU*%oP5iDJ'
    'p8*FYfnCYKQ{9{Wp<?9n_~EE9UBwlJ=GK6f%Sjzd7cjAY`67@1zgc0uI=7>ooAU#RT`nZ80hjdr(wIkEeR5HxE!UV%Fs4g4xGN4f'
    'N_*jV9*ogY1jX2mCNw|6wZ`D`y<QW5=U&??hdcXuqt_e`S_0dti>yiV3<s@zw<WIOs}z=TtVLb0)_VCE7Ph}$k-vPlT|w~>m|qOC'
    'tGK-dmAS%P<Z=NV6zL5snaZde!*BmfM*cConQq!lHhlG%&z@C*TK6ilb*C4-qH2!uo7zTyb<@U6#%@!)oIyNqixq#q>yIhw!4nis'
    'hLwY6HZ7^XW^Z&jSq^GBWsITlfb>&xfpnc+G7A;S<H_XEmgt9p9)I)xm)=0dE4915Y+FQ;x~&y*mfs02yl(e59WM?Qyx6)6(NwCp'
    'ld)jov`T!480aFi&pi=`B%Izg1!=B&YvWL~e||aRCg-Q!EN;R&G*AMxv=<d`jZ`Orc65h6@<zvn_53y(8wBb(<~xt_U0WVi`F*8a'
    'ox9InpIHDnb;8~oqd4k6T{)Pg@BUg+NIC5^2|uh~vw9z>&p=ia2+WFy_HdNu@5(Sm+K6AFlw#6dGFB1f+pB0zUkk>FGW9%OzJ=OI'
    '6o1bRYu{;kIr=obQzfWewAw1`&l_`j+c6&d&Q`Cz2RAu61F!XvvI%!jAVN|5OYX`0iXBLi?Sh;blmHgBHbsxR{muh28gqw|wRL!D'
    'sFGXxn{3E?T|!#-Cy#=d-K#wV`RRXO^~Ipgun-ijypL@TtUc!((p7Cjzom&=$F;@ntZ3>F_u-?;<mx{hx;kfrq|9t%LAGwUP18S}'
    '#R?nHGy@KB__k_18I`~F8x~vd>HKDB8a#E~*Osfg5F;0_!S7kW^!e?bDGA{e)NHWhi@@tyQS1C)m1CC*Z(Nn$<NCm~MLjqfV(m>{'
    'f@ibhKp9ucd#T>fWZJ2{tdr4w3u!XQ%<@MRe|S=Dp<LcF5@UH>8;Ryy@~g0_xrdUJtCPb=Pu>QDe9kS_sI{|EvUuy}q7FW8K7EFY'
    'RvQ^SPfE3&4APaboeqBI_gu5*$D`N)(Ml#%KC+3xiw))?!`b!2`zvxyQUGCe@^<de%hw8dga<7mGxu-e<)fuzzooPh8$X9UJB#(&'
    '=cjX#Z1U2xYWSeGuFJOTZVc8LJDF-6pqi^czS(x$HF-UoC-jJ#&eGu(zwf{{4)$O3>LMC2Y1P{4-Czs6rO#FR<;gO;zIojSqeD}('
    'v+%;?mZ~ehK|nMyy+3A6{Q8c^m)^TJ?2z$we;d8-S)}vB&9uKA-Ka9XS)u{6B!Ty84UobQ|Gq{jo-}$&J!9ICS{m%;<AU@^2=@+t'
    'aDP4qgbxdiMcb1G+VvPkHOC2LcytgZ12LIbKTthqgFA~n)xuYX;qSXWN+&9I=Fw$X$g_&#n?nd(+0bltIJ)BvJ(<2nw$l{c{M5a1'
    'j)1j#v*B?nUh-wziPs_Q&h{>*#<w%szA(VQe1?1CktUpV$Q7S>>!K4@X?f>v@M-Koci1PuvvifNK&An>VU$}PlTP3CN2)e8^_!qZ'
    'FLxg?hC+)Q=4;LG{ioAnP)uWY;ia{-q0zIiK4@pL=xh<ALNjW4aMb&~sSc!z9Q3xjO!Vh}nXKv|t9RTif_V0s42k`HJtn-$JZX)7'
    '{fjb0MBwNP&%@QDBHT!*T17U;K{fkhgZ`_b*Jc%0j#^tLS$|u+x%^x=as~&J!+rWLO~1`Y>n)LAFj@lX?75%)__64tIorb4BTiQb'
    '{q8ahYxJod1fj>a-dtud6Ea0(UArRvx!lD&&7>r3C3MFwU=DQLNjt5sG~Zm$XWgxZuYP_Q^}_A$euaZx>F{u9UpMvp{!YM@$&W{_'
    'R*H7V9OWDz3N(1O>AvpIOFE(&ye^K(Z~7@LVpuixof@fAnMh~JPd5T&2z}ZnP(LjX#TD(odYC@$R?Xx|!6K6#kI1RIEr4V9|K&PJ'
    'Iqo;%i8IgZKxzIqy=hU$6D=N#JG|&BTj==HQ#s%~*>2Xfm5-pRol^9D^lFrDAj02n^=b|85r;nahC7{J^y=3ytiEOB<TwboQ`NE_'
    'Z_?}g&-w82ons{!EA4;z;pF$U^yapJC;10$=8VIZx6gaM)C&`T?yG6@E*$4Te=UoHV9P=bIfIP-l^o%B)Y5Kb2QfoM{Hw&}6DQK('
    '{ikyoMZv;BYr67IrB>8%wN}@TKkGqm3F&(Al($gZ6&3f`+yisP7S4&033kCTJ0*esfX6H-g>?}eIp<HTvh9)e@BS>XRHNz7HrgNG'
    '{f1V%p0;JLw?6p$TN4K@H*rYiw4sD}esG`(Gxm>3{Dp1yoq>13dy>x5zlq9W`WJ5xocKMrA4Tk;k-)MR*X_REu9FeSLoaph8@t+_'
    '04hg3o7$z*KAZi)_I}r*y{GqAQK9~ewG>Y!MI-~OJh)gyfoN2J{n*8Bt)8?$r0$$no%3_vU@G3~Y#H|s(>|BpsNDTaxvzBI_)vdP'
    'hnmKAy1wUBtiL6h;GS`-VSLf;{7nH{XRc_!I39cQ8o#~Yo8bQ&JxVA0ww<JY-I4x?U}uzk4^N%i^<=JI{1w=Kt&TJ8&52xY_ra~s'
    '?zh!b-+s*4POR)S=4<`C2ai>xF{PENK!LVh1R&qt2Su9byKC+gU9;~ZqF&I(QEvo-IuGBaYistL-umP6SHR7^wxMt4GoDojPs>}q'
    'oPYi(iuAC8!0PF9y*ZRM(i%I*?WeOe;LT=wv=XcK`hRJBE2Y@6F)aYQt;7>*K0q$aUy_fX?YZDt184`8cbh9X{qfCiub1uG4`+Ej'
    'pCIz@FT2#xByypO%t$J_1{YjxAK>7SW@%aPEVieS(Y5V9-R#Y7#Hp#`7R1j`FI=t>|J@{i^B0fLn=SSG8i4gD!3z8%g6`Y?-n>EF'
    'uS(pq^u=3*<5g9!NPE2vcN!Yde$qr&UyH5OY32%2-L)q6Haw3O^sN1FE))ZV$(2;>``R43Dq54$tSUY40*F}Jsr~U}=y<L^bqAp@'
    'nB1-+tJb(bKsst>2J$v9|DoO!j3;%aMd%gzpH86C7XfXzgV|eA_R1Tx8L{8M_fl1?($Vr@Fj3Z}{Ybo{r>0--Y|gD?y*YpFMng&='
    'u(h@h5+E4E$Rq9@>)PPAhqG51URXj4h^(uiP3Z5FVFKH<3=@YQ75`FwUC)gBVxY6su{dnDQIlq+Vt3~C_-&;JiJtNOVL8sT1=1Ot'
    '$HA{2Q^9MaJuArP=$<g5qU^Bh)oN0*z>LqXj(D9zd+|6dqX`wl9^U>`$57elp5^VezC7Yut+b!2!$~;Wq+mEM4Sw@2St>17lKqM&'
    'qjGrj2b5SZwto?}s+F^wpV8a>*`ey!M)xro*Pz1@Yc%2dswQB4aVXRAO{e+fV8*_Y^dqy({_cI4UdL;FUpfKDo7-3<*#ch!p<!uB'
    '@~pYSbBip>X7fmK_IDMdyJm~W_J5?!sjQ^>A6G1eGSK#gJ!-DT5TCB&-+S235iu)aDMb9Szi2yAt@pM~`A_iHe^0e}P@x{J0YJ5n'
    'ny2qkL0pttUT{jU4T|W}`o&dCFZJw-_{Y6dV(k6&s7b;XW^TZ{s(qThs!0DMk*`R7fq@ZJu!bCP2-oniBvOIBb&t($>ReC%-yO3`'
    'YWtBD&r3q`t&MlVWVlI(x1SHX<IF~%?%Wnvhwc%AM#mwFl->u43@wrs+M6f8e~uKk*&hLbwA_^StD^{us4NlV4G~>xrZ;PE2(gyK'
    'Lw}@<emvIISfXZR(gKaHOZ#xz?}ocWR35Jz*U|f3U5ImjdS;ZUehj=Oz9<=C`gaHy*=O|`fNXuUEXGYhe|fLjvNY?ofBRv&`%h%T'
    'BHXTQ!M<DRrYO8~ByN+C_q#U{*S^*oS0ArU32}i(Wzhz3u1qch?V@2@_)JF=Gl-;hK&$&BZE4{zuiIGw@~#NA9;J;&P5cK)(n`0|'
    'ZCt&vTxIe@v}oPU#_T;=?z!%kxUg5)qw0?&M<jfj2wlNH-xC|IBwBXJ|LwJ`ckI+QojYm+?R7x%3*a87eYsIzxl@i`Q}SRz*R7Ge'
    '-uLlfP(=2T6oj(3;fe5l>CJ%&;A$cMeA<c85{|DQKHI`o1jFr~|3@VEYOJ*DVwb?Ga~kvp0uOWgr9OOu(O`hi_MJMoW%;u$fnDO@'
    'xu3<$*)>l2^*~RO)?*Uxv&Ani)~NF#Tz?AroeI6HJh#l_R&{s&LRl{I^QC_ZjhS5o<Yk;20MP5~Cc9+Y#RF{4f4Fz!I*G;EizBV9'
    'h2PlH^4E8IO$%4OYtL&vG}-BNT@TSLDNn%Tw*Kbt!C{F^*{IZH1J3Bps{7TF$p7EC(7wBv!dBk<fg{;)E<0H(sYX%oo98{P^6+$z'
    'CxN$tI-Ah1)z{5py%-Jhrb@?qSxxk_%N$#-xqrTD4BN|`h0KTSr(~A&{<IH~UMphb*9pPm6x#fB#3QSHCWTibW;E>B%%R7e$JuQD'
    'C6)51T!Dx|w*s6h%kgm5>t0ek>)x8JEktWv@%@~iYm>h>A(BeJ{tE2WUiY6~{UnFSOgggVO4MP+cm5W-bMvuS2b~9V+DG9|<<5N$'
    'OasxG;^(=xiSh<kek~N6*%-Pv+G`_havz*NZy?>X)8C#l7MV#Yg^hYRlr{u0f_$^8H#9T}eCl>=uE=)z5}obR`R|vRQ&w*dX$|v&'
    'sa)|wM7d;~)1hYuc1!k+Q#zo3@%B6tOm}og<*_sdg#8_T@1Ete8}`%2Slop7Oa1gXVoFA{m@Yqr{z7?m@j?ct&ojB!p1g*vTjR&#'
    '6)m=#qm2FZ-)32+uf(Er`J-izP2;tWknj?kcJC$HTV-)>GPkfdIn#Oh@w&sBpD^IdAcU7RpZ;N@cI6CLJ{^H)21H+#waO2tRtIP^'
    'PD`KFG+_n<UD$iiA>;1P)@sr6p5kh5tk;8H`vH40W#8?o_+A|K>tNg=()#*?hZW2R2Y>&ehjpRATKvwhvEbh8c=tW)W$FECJ%*f('
    '#E;}Uyq(6!UNKBC7fy}8FfMdZRm0Zw9*&>n7BsAJa;N>*-C6(<_sG5Hvc$itz2EzNDBOFwy>Ez-MJFx%T5_&kpsWI@jg&+MFH&q8'
    'ij$=?+B-zCELVi-ZCMX{-yVV)Rz$~Lwj`;{s>p1_BJaQauu<jeVK5xxsPVKv@~rWRJK;%nXyZQE4S+79CQoxEHES6m)|I_9jMp>S'
    'TAbxa|Db=LS@u}6I{zq>DDwYA*w1f7mM_=Yd<V|8nU-G278VDz8{Sq3mdJ2(VD|Q^48PwWWp`QE3LBILHQqwhH#=oazpkxc6HOfT'
    'i@T&Lj;6kTb#rGUHI3)V^F|DpQdum=^N~$b!~sIG=VItA#Prw-=IinRzU2pjw&;>S6QQNo5@G}>9ru0DZa&J_P-<oIt@Xo`;))hJ'
    '{m-YdXkLd^sN)W6+cQdppA;WEE%mJLAyCj-`SBFG+(n+w>-2cpEn6i^xK;8VK#ufxMlh@o&6@KK|I?K_?9;9GJFV)C3j}oIft%)~'
    'R|=g@c=4xYV=D~>q(i<7(5<m<fof+2dT&V;KT8R*fa@%~8&xn2sqxCjMcr8Zci+Kyg7!bq^Li0KC5fC-WUGGdKDxNKl&gH#kjCpe'
    'w;kv&^WEyFThS*S1H?RI=WzZx9kJuDsxY&=#%?I6Q~c_2tj-`{(}}yq<(pq6W_sKueT*p{>S{X#!fSfV=BBl;J@PtLTc=_yD{jTp'
    '4}x-$s+0F6@1YBk?6|z{Q=^sl`)+GUIy~0Pt^FEp02B<wp756V=16qew^7nMWA?JNQ0~G>;2zoJ1R5&%>lg?@6!3lE)cYK4LmnX)'
    '4YG2L*#3Cz?r0tMe)+==N3kd3oe{cpELl0t3>MZS%0PUFKE@_KRVC;kWl-ANQ_YT^HP(E6a~JtQwszTgQg4P_V`!Q`-E-VEzk|b?'
    'oXvX@-O2K7#kS=#M1$ZmEE}hu4nq+CK}dEv_Mq%^Qp(&H8X=P&!cN|b-0&DPX2aT*8dds!YX1B%qvXC-FRL{!)6ugp{RP`}0~~}J'
    '<@-HqBW`ZQh@{cUIG0Nv2JP{EtP3JjRRj%KP;|FY=9HX;&s#L=>h5j#i(@x!;2hGpuv&c1UZd4!JIiVv_?-jtd1GXs7Jppv#V&t!'
    'J+67=NF1F~yMg<rAE*p8(e_!esrg53+`krtiS?iVx0pXW5PDzbDuitg#)0$?<4qskcl(!OtaPxXS)Jfb)3O@5TJc>mQE0^o;y+Z;'
    '8TjxSNS)vh`-EGPm<<Xz|DE53H0A4)i%XQB$96QFUv=T{(C*(rF!GZyUpPoGZp<c9SnWD#UogpI9uvU#$T!Js3vIIQMBjXy)gD7X'
    'M&b7o{kwN(T|I<#O1b1;e6%!Ijfl-2>+ve5>h-?8eD+TJp+3J~76$R1&X(sDB@%NakXJ+Hj{&WjfDiD*zizah2R<*q{Lsoveq%sX'
    '^x5U@oonuyeTv8FJ+|sA>R>aj?_nZYVY!SdtJQV>;?MU{w^n(}L{1d#h^K_(`YUzI=Hz;Qx9p!!Y_$WgMe`LgnLYdv$X0Rs3vttW'
    '^48wcmxqUmn){vmtg)qr`K|(gcv7Ktz&JOGn{rHDnEZRaP*9_%K)%ergWr1yG5ox^P}{Ah`o1`t^u6|QI2s<AEPm#nJ8&6M6Qp8m'
    'aQnDC!>&DVh~wuDw6mS0q?ZHH0;QhIjczJ-ZKGiE^J|1fypf#db*e{J)D(E5hZC<-^coUL@FD_lup7pwyLj6Uy{|eB5knmlWUvp5'
    'TYRp)Bw^FR-!&J#92zlD$%a24URT~u2T^4~^eM98H|C>D*6i5D8qv=H1kPvmr2AKop98u?7v<fAnF7FJlr7+aJ>0IKTUn|`s#F^{'
    '88kt)efV#mxrKCdqsW&PdPJAcNNprNP4{;B9Qf_w)FEm%*M@CY(Rba?mORN)ACBo19yWs(8q`)eUNOC<Df}Ji)FZ#xk8cj&;bSff'
    '-+N!}e3!`Ma?GyDH7zBvYYQy05&KoaY;$6*kY#EsU3be|BO8TV^#6$18e2AdL&J5n@)sV}KE}WOM%UWs?*C;7rL<uUyl;kBxLqI1'
    '+Uj0&7CW#lARln{VQui1KW=}Od_qEqU+b!c4p)t7c39HeT}NGtZuRkSoZj!b7_m<t6L|6x<3F;NR(mSi=yi)vw4v=$4BRuudEjlc'
    '?Z)$DF!q8?)><DqV0G;D^;aTZ*(wY+Td={kF7X6t|ML0@19rVAe3I&NNIms|n&czf7^W}p%B#(tsy-c_&C{)&--h~1j&6~TK#oZC'
    'vt{kpd9FZ#CmV}$i684tA8-HmiSe`d2Aa%T0#U;2VQaH1pNF+R{W+I|i1HZb59{7hTAQ!x@I+tJojoH9{cC;PU0dS1E;Y!Na%&B4'
    'dykz2ZF~FkKP>j+$N8FdI@f?K8z5b-xd<6~-DAJ*@Jm;dIM!6)a4YVv%kT^};o*j)>fnv>YIm3>J_}XxzHfm0I+8Qip1*x<(>ZKa'
    '9XXOHqu=S8OC;1}%3bK^$Eq`Q3$2H3%G_uNKO#$clh%u>PY;MS$GywgFRc04s*)nox>uY{DtT+^hofGr>3cjwvp83phttR)7zh>Z'
    'nD2!hAmgq9<KVhvcP=Df4UEBSL|W`v8|d=t$n>?xx^?uL+Y+h<@2Ya_`2T$T3vzI8v)ZXYdF0jIX2JrkZ`<Mle@bL>U!T-Fm&xV!'
    'l<Zo%O6BHA^0!E@d5Tu^d{j11hsyRnJ9$OHr^Be=c0b>C<XGGkF!h=+BpR=x_aZKy0#=EsF1yXjEgbR9wJ()o62)F#c|MBvEH)fd'
    'y>gD-&ZXn*c$CK*vJ=e5oO_Uv-`)ds;!iL4YpMI?0%kW+dBOTNMf9s<R8+)cq;tIN>@udH@}+iY0#srO&&^z$FvX-BAo%os9Fz*Q'
    'O-$ZUcVoc6c@d(~gUNnWg|vO`q}KDVwj1DWCEiE7*E!u-6#x$ETX601rGZR?nSX0s5^?$H2b;-LH5(v1AD!9Ve$%U5m(T7`_v}tW'
    'isPTi`%{m-V^1U;?56L1oyHg3%_5}wjmC;6bJ??t{?l)2&k@DyMsLTr(b=oI22H+uVDBX@=|b)1a`59V+gaa&pQWZH2#S}jrRAve'
    '1U5Fa1Kd%*XO4M$%`b1$!L`{~6pXTMzJkB(gN|!e+Io!SZVi^dAmA=O3-R`<On>)bH?M=ohrikV6ZA>2TTWk(R}~{A?s&Q?mPf2x'
    '(>_&l1U*FpQ+bU$yEUwYGl%cr>Sq!_DF7U9=zDLxcr&d-=QnTKFIMOkYL&;0#p#-A>-Y;9_?6b&tNW#1*HfEj?DtM%C;MDRC~`;K'
    'uFo2Y0uIWT7qw>CnoDzLp=^5IiCZ_mKcAy<*TV6|Ccjrj2JfkKIJIiTwPOcF8DkW-p)-&YHu@KCzeWhLeQa$Xf4{16338cVvC+qR'
    'Tt3q`<EN|jqAG$vKCjrj=#!(mygv+@NaLngc-A<zOXV@TQKf0;ek7qF=dD^b|IBbs$T;q@eTAug0yMv5*Osv$E^p;EhtAJ6?fsi~'
    'DocV34twB}s&5xYp5nIGOGYaorVocnuP~6OaQc>G(jW`E+AKN4r0QLv;~eWZ*r4HrUxL%X%#7y+ew8la&;RS&b(70DsDCk@4Xk~I'
    ';Z?cYJ<D7k;=n$!cCSh4GLHXP{{t)G;!db`tvfn32|_;fl-0gEk4VpEsj-r9uVM9HU;5B^zxw6q@!{rJamhZu<pW9o(YurY@iF-1'
    'wT4zO-=Wj3h;7%mUUnWZ+9coiPW3goA}*a1-MY7V(<&ZXIQ;2cjl-n@r&F^&o!n}AgDW8<Ro(hz`FvO^*B6JjR>S;e<%r~!herTj'
    'e^=G?BTpg%ZXYhLc2Gwjd5q&h6+wVi=ZAj>=T4O@UaRoQdfH&SeYUo@#%bzj1t}Xzabq{%8)}Y^|KqcoputdGsKcXf%jiwx!?JZ7'
    'I0#>=Rhq}~lSmKGUt9zVNsRBtTREG4t4s%DsE(Q1>n(J&8yQ6HcP;h)j$ixcR(5I!vPb0U?-N#TlhNaPi+R2KY)<|_oF>nwwzw$$'
    '_N^>BIo@|Njh<EKAF_JBG?>4Hy)SQ`#_cZwvY3p;);N8REgEFNv$|bh?xcj^l`PPEfAs(-7M*i=lirl<n$YftClhu%Z!XU#U~0|f'
    'R?HJc_ih6l&hzIReOKLu7nwR@<+IuEj#}fd2tCerzl}HAqB%L7+#_|J9{|2Dwo21FF3o@MVbHd?Nhb=**<@N7ar6n#Fye{8_k}zr'
    'd2I}IY{OeF)fKss(hTgDs?)rE!dK?|cu!L`YYao|bG}n2^x1aeQU1%5s}_!5MHHUxW^ucz!Y$Al=2O;rwEH#Qt6FJ2WfaD592@2|'
    '?#wGB*EEtyrJ8m&w(4{h&0Z|(gb&@8CTY?A<;g#G1#uN4>|yY{5@27ZwR+)Tz4Y>L-Kch&m^<ckuCx175olwjchAfDDG_VN9O)kC'
    '>EOT`*1%=idOIRlwaPEvD0}h=j;(5!D}k((-#R5>m#o_Qv-hCZ7FMn<=2L^HmS3MX+=gOY+SuVFF1F(=HKaZZn+`KX8_uxUC0QT&'
    'H_tofqBE(cX~N8Q1Pljmvh*MY3$m>VTk%_&*zBDlCi{6!L3XEcmD}<Hm&!QWp+k3sWz_7os;L+fl*yLh{<~MBWl;w-Gl#{UUUS-t'
    'sUDP!JlO$M>Pf^?9&Mr~UM(w<ZC{nar47wHOM2Bo7BAXPv?aVo_cbAJE<Y$6^h>h$t3#@}aTaqUTXK+$yRhR+puPwZ+}S+2ytRsI'
    'X*C)Y?EVm(NE^<QGF>_DVi5p)<H{1nhr8t!%CVPP<=lIxfBEr?QjKBTw6*D(b?a5DZu4$+?C+;T_u87L>O*{wIyC94X&7Kp9)QY='
    '!vf82h2=S2m&dfuT3pk_#9~$)(PWbR^6!N}jvaM{F+)TFu(f)bgnEa3Bkp-OEd{JT+Zslp9Dop-YLAym%5Ve{ommgwtsFqO&!AJO'
    'w)W>d%BDHfDF5QkSS`hO#J9BDXbDc87FjY?C>wM~)H0ox3gJ`&`5v;V$q&E17RAl8AlM$kv-VARQMq2M?;mS6-TJjicVUeB`I!Fl'
    '8@jNqxS_5&Y=hTt-~PK#TOc8LuVFEq)l}wLK!i6%S|b{ZDC|OM!z(iwL4pJ4ceQO;wKz6n#^3kTy!y+Nf3Taame|f3S&p<1Qko-9'
    '+&QDMwRBf?EiUxq$qH#d18UZ8_r^;nWH|7$htob&&9|goq4I9GU0~liDfSAm^ouuPx~kEyscZ}=X(UCZwAz+7wcB9Ap7~|PEzK9N'
    '*0Wt-90v1ca;gs4xU-h6qj}LDe$_CVZp+O1&AYp8#^aI9{rU_v{uxB--m5`j2=5j2INk)c$HbSFSuZDgN9rPY8|mZS-PdM!Y}K1m'
    'mFW(K2O6vb(uVl%wsx)TJ$7C7!6xPYZ_e`kAl6{{dnsA^u$1;kdu#W+eJcie6ks)6^(S|%H*(x)3+_AF;!sjG!n%Fh!C(o-YC%n('
    'Cpq1pM4pk*?134-c|C}_XneRb`AtN2^v(p6jS<zL_Y4&Z_bsZG<{RGBjh%V#>GzR=;-kxv5^LEsA(pLdeq7HhR<W8&^QSt;w8hW='
    'dyBx@zCzPnvB7vYb{)S_M9r6X=``#-cF?}r((j0nGF7%fX6xjnbQ}9w^WEGx-h#i(demW{Y|6#vFViZ)zy4-<UlBh<>GR#!mY=qB'
    'V~wMzXKnA@nMw#(>pOE5nPY(?-ALxIeln->WyPp9(aM>!FI_&j)+9HFZG4MKRd3Dwa36C9N3gvf9n?b)*B0B^vpK-)cLS<(OkTm>'
    'erFg`I`~AX`f)s*$<Bk{EY}QrChIK;zi(^z5)C-UD2qkCqsG5Fl+IJ=NLF0CE_NQX(6c_BTnw8D83NNi;Wx|dm5CR<y<(*6X2tv-'
    '@ixAH>@n&)l`4w;a;o{?yWY!RulHADm;ZFy7q!D%k@I%<Plr9opGkLy&2|NBcY3qe(VBfLR@tRYU4L+U=f08jew7QR-8X3A*@T3_'
    'z(TioV|G3LrDh-e`Q;2qe%y{N@A4GR|0}76^H}{s1(eXh`;+rnGW#yQ`7^j0jMo((nUGB;fo=D%Fz6=RKZK-h1@4|57n28D?_Ym;'
    '{Ru1*XN@+&Awjc!2O_I%S!kYij-)eXEgO$>q6Vlb-<zONW>T~RZ#5<R23T?cuNDf&SMp`PtCMp24R;dz>pKP0wAFnn;$Q7u^*b^*'
    '%LN*P$ML7U4JtwH%Mj+P`=C<^`P6ocBI#61TQHi=&)4~1@KS%7ZP0i=r6T!K^YI^E{PkPfdNdHFmbUBSvftz&wfX4K4@ujcZi&l@'
    '-m?_#r-^syGnqB-rqtuPC3~BBxLkk3SA8(1-5puEV!>rxu2BE>oVG=wc)(4ru6F!G(WmhAKIx=e-Mr~<!#iu!{Qv>P?i9aupvftx'
    'ORD#%P`S5HGjG>qF5C%*rzmCi#&THhQa?RPzBkJLy(YV#PNF{tz12n>5vNOXfVD4!VYdx)XWzB;=G5wyi153+o@QWU;-n1LFkgV('
    'p6KcsMrO=9ZSF{i`}J}1a@tjF<Gr8L=SGqrJLj@6m+bkiC(d-Rvl!JLwE){+E<?YuVS6Yi&dd!nSxYUqlix?>nmv)pc16j(hBbht'
    '-`oLg{ht!uDUo=5knn4=R(nUgha6VFiAxNUtjR4?;p$C40Jn)emfbat+CXukZQJ$IN?={Ot4`Jy*$#1PA=4iZpt{v-d#(jis%<mc'
    ')zBM<ZlYFy56CmVXH>bvR?FN&IcRrgYpjO^7Y+T&holbP;6`QmI;LPh>m})!I!U*4<>y;rsgdvUt$PPVB?i3gi^|xDSNP`+mNwwA'
    'dizk8q&dqYa~WNSPb=X2a`)s|03b7Ci<MV;sNkkRE#Z@fvsLSN9#D|94>62emFj5V_gXsj*fG6Pzad2MQI8(;#7Wm!V=(#XWfj2}'
    '>|`(qkmeYNmrHEX1mII8Sn@l2*L)-;cktsa@@RQ~&mJP?b*wVXu_iB_4IvH5LliYK)VF0uXID*##c+o+&`sdRSc29aark$hB}~G`'
    'kYsxOX=f|uBXISr^X-y59N$b<se1!ibdCVC+w?z6_3E|LodK&sj$g)G!}Zz(lZOqrv$ufqb+IdL9ccQjS?FupoYGc$r*D7Rvhnj9'
    'wcEGrIh}(FS=7F`QJ#|^P)iT?O2^c%IWN~$kl@q90JVqU9bE?a-P{X{9RidF-QAfo%H#9vM2*<{)GalI(eHkSX2hxSz3=PP%omO*'
    '-xTZWdgXLp?z{_ARIS{wHpqNzR)*7Yt@;*B>8UHMp3TCZ+_{58x+xcYuVcc)d?M$qpI*XseC1#Wr?C}%Rv&RG!NhLqNSMjL@aWtl'
    '9`lg`bj5VOj^lFa9%|gAvKNn<G;Yw^s}X8D?|WZNq#ELvs;}N}e=3h2X79K^2S<%txq&^RUO76?0pG%nMpZrd1h%7F4T+OHn13Dy'
    'o!g0Nz|1=tQtMiIbNb3>&oS-+`TvGyNv3{%oMg~Tma%-{nj?E7^z=F&mehjn-ph{S9Dsg;fu^-iUN_~8G;Reh4$;uzFLKCztR}Mr'
    '*FdYZogyO=Qi=|C{oymonq;kvi7sQWA3vN8>Bm?V5LX1B+{Dg{zE?As<cI>QU8!ETw&x-Cv`9U8f`zz%2=HawScTUic=;OR<dOgO'
    'L<+S(3?xwp|A9V4X!pXD6CG+;Z>#jWdxn7Pm%b6Zt}s82b)~EB7T+3b%B=Cc2J`vkCO{A1{58--m1pd%?*G$a6y-4Awdvkry&!z9'
    'iZ_A<TE<Sa_1;ohHvBSu0q<*zvuzj|Fr1(G((C}P<#hv5uCZIcJYa~8*Gs7aHNAfI*LO-6L#{0Mmgupf6<<BD=jF3OLG9T08yEH5'
    '%`{6Fxuvo-zQuq?pXk;)VoU&QV|YH|&_mazZ%Xg+0$>*5^XX4l7UhX^@U6JM1{(;djAtc&2gKKQ)u*@3)^Ye+UFrWflVau&3Fr|s'
    '`s2;em=!7R(3%aYjD`FsbxWNlBL|>9`{nh;4Ic^pS5G-EV=6Z4fQC<pm)&p{gi9Hvd5N1!f{W%?d$tcvaWp<#_dCIev&I7!Dr1Gv'
    'r+BC7g>-Rk8`Ayv+(EPP3D%XxU2tpD>ex7`3U=Lx<0!g|im#RA%IA+cCQAnZvH+;iS?AjCtFil}^VS3{eWT|jp`Jo#a_~+g4Emji'
    '7gr4%+rfNDZRSoPR)~c^y5be7-^S})p^&4j?ybtt2mXn*GVc+hEuPv2BE<dinwt|;BuH8rywZ&{F!ui9htKdyn{Z=hYRMP151$!V'
    '5>JHwxqKO=J6_hyz2-&3RUmvgH%aN&ZS!~^g=4da%Pa;6P97c!WN;aj+mTeyKEltBNY*um8+CSz^Y(C-+FJGV`p~e;enuti0#@sO'
    'IRJL6s?ex6F&pXqg`J2st8I>dZW(DKK4)IyVK3=`o_D*=N&DwN3*5^|xi?h%9zL4k3g?eVS(o*AjHAuG)y=agt)9G9m0Z;(of_mv'
    '>vTYVlG|EDmIya$qDMcaDW*_|({B&`%~6dz({!~B_fyXp`V?-u-_07XC9Ce$Uv!K8b}C1Fm<^r7<usajwX;@*n&6{<AeO@+O%U3w'
    'Bs+d}vekqJIncMicsqZ~s(jeT!};+HG^%#5q>62{%hHXWx@!s5$nkOG=vn5Hc?u=bI4+aHBl!E5>(#lK+~h|zdasWGSNHVB{QUg+'
    '`wniyL=NS_A7Syv2<woAAW79opvV(;i@F2ih}whsF<PiN3#6OsS@*BAX8MXFV*%8)?%Be7$$)7R&DWh3#y{QuwwU0o`DhiSX*<9U'
    'RWsSzR7|?DAn28Ydq=m~xZ=!|th1L1>U|&zl!h(G>TfN=I1lC9!^W=*s6$W8v`KhBo!0Q>fqL(KpyQe;G_by~#J=Zce&<5Lnq^8G'
    'Qy@7mZ}pgsHkch(HGuTmb)hzJ_KL{uh27#cO?)p!!Vq(};!oG8$K|h!^d@=MPB<EP5vhz+9N=)FknVmZjGt44Z^2m3ECf#_x3BLx'
    'z+UCBOqPz&Q@R|h2Q=e)4O<0+Es!pLzCka@dsAh#W+#nwh27I;43e3z1$1+Ku{+FSY20UVdIy404MH~XvtP=I+jvx}masnvP(xm;'
    'QY0<8`p&xm>&X4_!s9fW;SMcp%=Ha?HL@x8SEjQA4k!>um%(=$ZzT4yEx;!7Kn@~R8s>}M=h;oFw4HbPAxoz-bTc_xt1vR##jlSu'
    'z~&h<v-aEPWSHgO)c4!nBn&C{<lNMxC9X5FzmI0kXD`!KJj6q<-mKt0Ss6cKX`#?aEF9P4R{cbeniCNJ;gZ_~2W2fE9F80r+2*4_'
    'v~Rqm<=3e<sgJ=wkS3O<of4r=;P%rJwoG0-<fDg}RTm|v-FPKpg)89ys{0Q1w2>{)zXAbl0miFdLhrqIa)VH%2?-?8ZGQV3$$)W*'
    'lf8TIeeWgTw~IzIr_Jdz5N0dpPl7KcU;7UwB0OFMRXjU@{28ec&tqYaf9b}I=^b=XT<NS1Sa&|<x!$o21^WZ1o=tA+(`;t!8zVut'
    'dxqCEBZ%l-EgGw2w%7B*<+hh7X2O+0em2dVR9Q|x?VuDFB~WqDiHSm%O#1`aERx0VHhjsKX0QPoITb}(3CqabTi%OgX@pJM%$n|V'
    'CF1p-?y#<V#!suwWEY$|pIbtT@|P5<A2UK-<ba6djYN@|xyvclg&7*9BBKSzjCM>c5!Mos=b3Aq$&531Zn-lj@onw;@7gDXZme2#'
    'Mo6^NMUs%%nh6Dh<nKuIKs@2;In{0Cn-ljcQhWC8(=8LJ@7Q3qF)4@E^3qr^(k_%HGUhC|@Wlw(b*<--!Ek2w*IKujY$_+^cp9_%'
    '%IJsSZerwR!*_#fhZv6`U(akT2jXd69Tfd5Y#s0C{aNQA5UI{V9NzZ$Q`Ak*7S#23B`T6mKDE>3Qux3UI)*wofrYR56mM0u;wEyS'
    '?;2_)QFPTgXB~mLUS^+HCQ`K{nUn|0)Q8Y0<R1uOAsuh|28o4v?bDjk&9g^>Xt@Z-h0dllY}cH_esAzRu8MS$dye6&kmO0by8C?x'
    'Ev2iFF9>H2PrE|XH)i+qBsE???U$Y0vYHGghs?D<i7>J(=UfvXJ*+pL%ATcAraG`^hr{c7!3C4~0<*;@=@9gUPwHxs&)_Zppg%q|'
    '{bJt@6gkx0O?EyFoh{~l1f#F@{G60evi~rk)=@anlmZYcl$*ZjBszYcc%tQSb}_{d(fLk!o_YJxSe*@-mFaAM@U2?V<oV9?G^0C}'
    'P-~AaRms!MU4NI=H%V@>V+n>`t&~B`Hqg90n)fqi&tGb#yYX<l;_O$}F1NM~?Aa|_4%CMDAmm{(foe1{^YsQRF2+nUyQwFV-b^Rg'
    'ezm?XNTt%I;;nS)5=8}u%XE9?HeKP=WGOE<DLD1yt|WcIl{VUy{bpQ`xwi*7y_4Z^E|Tsn?f^+bi5U`;<tU&;uJR4twVbIo+SnMW'
    'VK?B7EN4)sS`W3!MqwM<n0T*-)!RyHHw<N%s<>M8xXdufc-uVW=`p<+jqHQ*Ot8=>P$g-<3|xP&Vlk4!IZjDD;bX%s-<8bCF>j7q'
    'v7$4V@c7Fa=V@M27c7=$cpmP>jiW&MylBPU#f>$G)}Qovx1!;m`CwWKxSu-Ld#`oFJeFa<$#$GezB)_!`O^^_pRieQMvt25X46w1'
    '`P5<n&R1)$<wAGmjs@k=tuk7&oCfJ^va%Ly5&j70ka#l3zvk8ZMKEd{i-cBcq})omUgPKel+<3g^zb%6EV_ENb){bE$J1(_<lths'
    '8!e}Ijd3fO@65W9yRhEra;|;)fJFu-fn4oa4leVD$UNi{q-7JOMG5mHr~@n_5$7<UoK@$iZa#j>qJe!$PVN(PcgSd(w5%=`e6Sr1'
    'qIxaDtjZ>P*V%5h#_sieKI^7=u~8iF)|vEyX+)Chs=LajonyAYCOu|-Ku!yTYB?Q0E~vckY1MBeU9)B&$glmgLSA%s8tu86l&eNG'
    'mlD+L_i?&W|0$L!rBa?P+saH1bUh<RNN;ZGk|!=coKd9k+NaeO1!TkpPB8lzrFTSccGAYk3D%f(_NG}_mUmh1Zc@tQ*Sb4TB&}^T'
    '_%7S1r*q9ytbHh;`nZrqxAP$7KZLgcT9jLfEmKk(F$$ihs;ly-)pWOyp@pC6KleK(bkrJ4NY0wqbB0;W-|%{ceT%IQrxmw<5NZ#i'
    '?$dHec4<gSjDrOq9^TBBxe1@2&t^wPC=FK`??kF?GlO-g)o8bn=B_O1r9(jO($|0gqUCf(VgD+D<PiF(NxqS}X^t1Y3Opz9MuQk`'
    'PMb<RF&q}kI#Z2T@}4L4a2mQ>Yk28yv=4f$yN?#p+!)FsbA~)z`&<xN8v0jeD__b@>aj`Ggh%>*N6zEkwRE@XrQ}4owod4|on*AT'
    'NUxbYDOflSms3wCN(!7B!{ae{Hx5qP#du{NEnWLCh}lb#`y!bx8@?!fM`fc17jtKwm0%YyyV}^iAs6`Fe9W9`tfD5mPISVi(4H$)'
    '?zYoW7-YtL^Pt3va8>Y+c<h=-xjmk)a9Cx?z`}!KBkkBujsvdUpfN8Bnl4Pndo{dMmE%}(F0}1wlqpFtwfAaR26l!NU*mx0QgBD{'
    'l{Q>=79g(Qf2+IU@xIV6g;SEJS!m?yEn+ppx9P2EwAQ8kWHIq&RuMURCluld|0d2gO{J9Rxi#X5dORZ6hj>@lOle~*-tU@|>wSB3'
    'o{J<xXe7y1Lj2CvuQW5o<7lo9YFv4NF$=<}wfj+e6o~Fj&&1!aWV?5vk&ilhi<1hjZstrTze4;R-evjV62HdHKEK?h*}akt6izuW'
    'yNuR0mCY0HD@ySh6!8|^^@++Jh2C1|2G^M`LglLf?}qXU{xu7CbuPPdNyIK63#rHMdUySP?1VlEQ)(-D6uz7D50d@lR4C!~_DPIn'
    'h8TUy9qah6$`xDv(OzGr+TQp+G~0ySNtP^|<(Pm@GvaV7Bl`^2F-`SaZ$hVq_~cui^maAuG||1#H=}C#DL4!D#r<==oWI-0`F+@}'
    'Y_P->?&c$b?(Pt687sXNo)@5*m|KuOe(rNWV@b|wUj0tJ(}HTg;Tr37rR6EUO=-e2>47-kCh437Tt+_OFVR~Bjk^8geWg@sWyzy-'
    '%uZ(f#DJiFr%0(!)cnW*gCTjT`+CnjH+<S=cGRjmYGv4r?o;U=mJU_dbhXK7z9sOqC<~XFgAe9n^KGS`VT7e95(BdlrhHiGDUH`j'
    ')vs_lH(c=3*Ss&5C^N{yY*VS$E;R48p9j0=fwu^?t)Fuw+jkqTy3R#v`NFz73x;b|w-RvXcfL6_&^GGIOsDtS9qh!Bt!J?syPa3N'
    'n5dC<GGgxXr~1AcY)7Zf<CEYtr)bNZsaks5fO@p-F-EJno5CCAQs-c9HnBDw8pKt>&(gW}h^&(nZbYw}p{MS(PwSP1q--WT&TNaS'
    ';<ZwGkxH-{9`%$rY@Kwk@7U-LoyRJ7Vo@%Fnyc;hPC{vKYM2)n10@uTNd9J?Kp}Hxl)|<6^}MBejI7Z?tz1dhxNbTVuDA4LWPq>s'
    'de#$9xO=BEF1o}xx$|l=Op;kw6CF%esuOGYXT`aks}g7+F&(s<F(|b?5!dheVE*i8<3<mj*f2|EOP#ySAlXRfQ_3<D&y?A?r-mn#'
    '?k>{l%`;xgM9XAw!%;{-*e$q%LuMooo==%+w3j8jV{eqW<|X)i%su5R`^7#~8yj?6ne`%0X{kYGEWXHvPu@VVKYJQSU{9uzlE|7A'
    'ZEsuAfQ)VSr?7ulgPQ(jF*aNs**yMKgRb8f@ny7$>LMsVgeMF!aOmbDGa2ta8E&{iM3$MVFV;lEEvb{*WT-|iNzI3a?8r6DIFl}%'
    'jzS0e8EVy;sZhx-^R8*?dT+a1aAIm9raU)FB$`<U_Ff@J#8xX$?yjHgY_;iFFHPE;J9I?Me1zHWi_Y+otm55ua9lLGR9HI1tFqeU'
    'v#Bh%x$47gGMcqXceYcaYWyjwtbJKBpP`k`alddg$xJ!?+>FTCR8<FVu@v@g0+T=#7wf(3IK3S%7Mm3l9BrVddK@0RX2kXPf|PRM'
    'd9b-F5Mz1~c^<pw&!<Gk|9m$Kv4u7pB;qGNv{iX6=H5*Bz*E*u4T)9Z=%t9el<JKs#2u6%`C7Wl?2db#x&Dqo%wNK?fpE$gw}!!F'
    'coi%J;amXA#1Ezw<>XCqt%!=`iwDzL@!*Nlp{=r}^3F}&r;?$G8>%c8?XmPs>ve8aC|&8z;zMCB2tDeAmQu&TEX_|2(VkGw3Vaqn'
    '2A$m)W|kx=S|I9ohp5h+{875N9pzZLQ;KxZEi&v!@3_LW>#Yo_nsz;pCG}N5XsFIEl=sO!XMHOxuBu#so?{7hY0Ob_yUCh?@VF7L'
    'Czq{p56bI4C?uAOY@n<Y?U@hvVA*tUmzAZlnL@AkQ+t#PelGWtAvuY!%V{Q<?{}FkR9GZ~c!@4dT6avjwpzl#n;tfWMSrsKmnwcJ'
    '6kNo`cD)qIX^VkxkA>JfI>VPI*Sgyr1rvB>9d(cQX=9s_TBp!Bp%A5|FSIMjAx~)sCwDmMYnZ`hjXS}5VSk#XP)_T32TY>R7w|<s'
    ';a${c!?i*Ad%f#@jbnt~gq%?7VBA%^>$)!$j8f?&+0`l2z<q>~i1>!R<!H#NN}5aL+KcXp;Pd@cnvEKe81M8^7_AubA%!q361v{o'
    'PM1QXZMLs~aQMVZJH{KKFm)Ih`Mc!vikph~Zoba-+)}=Dw@d|Ta%iRzl@7F%%_2Pq2`pLcB+MZSb*0U~!&k58n+zw`$_;cBj*GFX'
    '5Jt)?p;@nsegY~X=pJG?p;hbMvDJ3JUshmdsg=p-(=s^YNO~_%hI3~Iqn{<&hx5%UZ1k1af1klWl)Q01)KXk4crhHo(^6P+7K6F*'
    'X>in{q$(!aSgXWtgcx5c<?sB1XSVB^&*TZ5YltpaJnfOj3oR#Q)U0c9{oc%Aox?=YxsvCLm{2&T_iO2CS>Mf;<#}ivE7S)#KAXqY'
    'X1!F4F@Z@APt4|d^RUds#`831E~kt1E*gx^GoE#9#0;<JL%w+_(Jv+#UGH}K18)JVxs=htSw2-7)GpwjS2__ssg~RUC0t<pnP@ZM'
    'mw9iT>Pww~d%#x~;+C%se0j66-^!WYHIEv)Qj+E5z5i0bJ^y_8w&cvox9{Itl3^NuB{kL5LAsutNW$Fs%LIe$SkZV+VGW4`Ss^QM'
    'rZm>{J*!KCwvqJx<8uG);hSM{=Gp*o%HN(Jj^8-hlysH{E5Q(lp`0KH1jE2ELvkD`QxuPj7>)5VO;L!*i!?!CH~{mq&X{m0L4uV$'
    'Er47CrBIqd5Ll*onIc3O5m8zeaYSS&isl(u6e$5id5RWfSe9v=;W&grNbnXw<Rw|tr3)#fh!7md;1W&I97d8nN02;DlN3py2rpn9'
    '0Rwab^1AR!3q}FW<VYOFFqz~CL?%#?5IBM%1O{eM5<_JarzI2<2$)7KEHop_FioSfAd55&Ku*@`9LVU$Sv~+LFndi?UIcv>x1dX$'
    'saZmh6q&W;DzTHP0fsD5-+y=9^8hv>;slPtfKeIcC;_KXQ4mp*K?oROC=#J$oDd0^!T=#O&LcP~a417zB8Ca~&;L?0rE0ao<}0;!'
    'tLX?kp!@i8`BzQXW|Cm0#i?1*L@6a1f<9fEQ%%iGB}IHRwo}=>e*lVfCR<;t2u8EQTGu7jWDRYt3lh700Rxs<1l!Z!LC+h;TB>lH'
    '>6o*p-2lFs*_vqU@x)9?@>HE#^9*aProT?VZqxtEqWq6Bdt<FHtP0AS2f_yoEr8XCQ(%%7Z!9M+riSq%|KHgrLWu;y%N!z!6eH0v'
    '$;%`KY*mnXz^qK-B+YXI|Is!PilI;eV_<}YWdX+|iG(>G*q#UzI8MSe!ZR3d*$YPlgXd5TSSc`iiJ~z^An6ab3E*&G3k04QNfJQe'
    'WK0D9f(A7!urrcFfZb7&2!CRmgv3c4E=o8|;}}f?>lVOl#`-KEw7>~4Ay62KA&A5<81P33Dxd@kreGupYr^NYdGkk}DiYXRUDHg*'
    'Uk+VTz*cUgpgsP$<SgxfT+G1^KratQxTUY92Zyu+>c(nw`_cR2fp1|xZuKcpN`4RY71E_8H`O1-SF;1AB#DwB83xc|dAc*#7T30w'
    'L2rRse=cM_IH1N2mEK2S2I3iq_xjStm8@1;jd-%f*5a+)+lk&Aa&-w{R&Dkl9F__i?`-dXEvhdV{2kd>6L?4Wc4|%>25=OQoMA}1'
    '+2E!IfR_QNE1H?n)~cA+bxrqvcbxs*qi~Lv>_S@bk`CR2L12E@;TQe9f3PVCTmJ#XS$_ou;Begd*Sux(oH9MwE+VNdmH=)1V#aoC'
    'hSp$?<<=gp$0TP+-tRB0{_C6dw<2vXgb}D?YB($}02YXjmu&(91~fUAYhIZGhbR)rUpVs@PB|_f@db=Uo&{8tWQWdeAxk0`L^m@1'
    'LnXR}cGlky5S6KHDU2yCmi9ikzz0p|^nL2$&>&z2V0HNZ#xw#~UIX_xTmG_vqL@@9PF*h{3;3h(@^GsemUf06HJ}qOQ&etot8})q'
    'fC+|VUd*!AsAlq|G;492?zPSi-|Kj~ozzIz;`s(!O2;#{G~U0j#9R3efYEL=(v@2n$Mb|#x|wX`Ypr~>@(ShoJ%6@>rdMlDffPxF'
    'Y-)jJ6X*>KV9#wf98>j$o$nuQ>eWuI8UGC%wc!3O`+U_GJA~Ux%W5hJ+|~~#TYwDq)<bG4$T%$9)z&6^Rc_Xj6AQ9V;5t7joGq2G'
    '<12{=9WP$iiszrRajQ$)FQ7H5-7j_zto?ESCYs&<d;qm8iOC?_z;K2}1P+!kNnlWzk`R(Wa2RB|Jjjee0!tG#hJYxI3L*%9G)96P'
    'TSg`9qeZ;Oc^k}almd*2AcrPVju9}7!Er{W7zPE<F@i*B7_g2oA_&|(NOws>maPaX!2-t%6a^DsqqLONMr%je`=3BpkuOO+N5bhC'
    '=m7Mx6<*7YexUpYil&IK`|ztEdJdk}em<P{_|FLe7%o)2+q17=ykL2-=mQ$GR5*bDRv16vpBH%dKOZGk0I4^0!E-yu=KReR<kp&a'
    'P25{9%SQKTES0GV@%PpnE2BJ<@!j$3B)|D04#)A{g8T#d`3A`I%P9Qw3sx->KvZ0-)}k{ZDnJ7K0=HaBVuw@K((T^d|5_9BDu7{1'
    'JIhZ`U&3PxJOv$`Fjuv$B8g*3OjyPUCZsr%gKlO$u1%Tt0*Wn)K8Fv2x{bnKYJRfjohK4NP*x=1-BfA&8sc@y3Z9a|Qao!;B$ZvO'
    '!h}-+X{>4|CoHFm?28()vZ87FM}M@jqym_j86aa<G~nUvDUVk8_5NK2zfcC*Q2$)F&rfIFvNRoR%{?Q4LWsdA3<rkK(IQTQBpNs&'
    'kYMw$APW*NAixy>4`n$hM&v-A&(Po#BS|2WC-1+K{Z|gyHkTjwGAQ7zoR{ZJVRANJ<7;!X`TlWlsok4Eab0`{{p$(;uF%d;=Y9WT'
    'Q*6<Sm@J8$EHIKRF$jgCu#5`?5E?Gfs7T?cOye*|VK7DDq{v}}go~gCf;k!%DOu$2{~?)Yo%|h{JSc}59)VGSofCNir7)|~LU92`'
    'C{Q}10*n&~$s;lif`dR{0xUBEZZ%~%ih8R7mz2axB$mJjf!q`%C!eT6t&wJ%xj1mGk075|fN=XRdHM6`{O98NJ0ZjS%EJ3J2=KUA'
    'o1AJ|yq&$S!|&kl|Mf5R{sQ0{2rk3c|8?slfc(P4kC&Oi;W~y6<fj+FIFBITf4-N;+XBW|^Hz;ulN`2%^YBS!1I6tpz^+}_JUDFc'
    '{8Hn52LB~v`*TsfNa3R+y<I$2H<E5hz(HCu$zbh*M;)``8blte)o8m<3B)SkP_0<_-%jQ%9A9U1U&rLP%KkwSuKRAmuy)-Jsu!&Q'
    'TWpViF8iz6-zd+o<K8E64Iuh+$RO0+hFu%vhST4TAs;m57iIKYT>~}re?pUhA7?>nC)-LQXcNiqLfRv*0eY>fAYTONrYZ>CK;7*2'
    'n8|X+rEmEwow_M;f2UX0iZ>b+w2EiDfV>3qn}We6=_8UxyHZIv&Y)i=S*m!Q{R@?Sr)YmB*so*nCFB03y8Ih1>XR%7$i@4~q+f>p'
    'A74@Z^L=S>lPkUW`KucJ9^-ns)bwiu=QoJ|4AD6)e4TuD8SnG7vzxWdaAB3+V8PMa{qN^ZesKJ%_456K<JbH4PXE52Kfl%`Zv!LP'
    'pWA}u&C4?`@0)Vu`7LHmpN^+0r<_|YHwyfT(^y)ff7Ey@5<oTE@b6z20B56c3tr?L%kOXG^JDqbF_j(5b1LyFH%T$1D+SQf`*qCx'
    '8=>(c2*Ele199o%MlRBKG(M>wF5N1YQxtYN*&86dDd&C$uulP4C@XM+)w?)1<ZQ2Y35YLFjZ;<4WO<1tkdKYI*DlJ%?_4@=pLnC-'
    '7kdL{TV#P3KW>UWyCDe1ZJ+#JmevMXK&A$J>B_RE2H7po?=RpUtqM>TA;Z+6vp0J;(fh#)?Do*>7Fvj3r~H}HSP!pTW}Qu0jVkt~'
    'uLbgt<=Ql$b8Gh3CA{6i159|&5(e`7yvcE%^rjPM?cHrh{Hus!&3#;}$`qtJ?|J>Gr#EVOW%0t{MT;&ha@&Wqj@+ML-G9|BbOe6W'
    'lYFNE&`l%J`wxyaULyW4^0Ws_kKc9>{|%nsndX+$7dQ5KNkt8A0f?F&Bz9p=!AC3ExLBjHUsyZzlAP{9qH)3a&y4aP^7X3|m_N#3'
    '?Dp;348}0I#q#pXIz;>;>-d9&;7@9wUk0xKU{>S({+q`2IeY^bX@J}r>^)>nd2pyk7_wyogu!yQQmDp*<2tlB554ze|9#`NIQYNe'
    'G;GB<+XC?7ze||^=d@j968yNyA9}wR2X+rCFjd>C0UOW##g|!?6a?Ps(q<}cCGq}$!OZ(4!aDE2_)7puTnixI1u@q?C9!e~;E$%j'
    'cU^mx6#vFdF5SuxeoEH0g~Ps7;FwycZ>Hn7cMBYxVNd$}(9C-C*sQi2$uyfz<zElV>=*G=DxG4R?OLtcXxYbK_VAl*_TiJV==l~%'
    'x>GH+Z3TP5^A^R;+gCK#x3_mTZZ`7TmiqtU<j)rOO&==wHx37X-8IRjOSRV`)DBR;ZJPWC`)hW52S)HuZ(Dt0Jyzm<$t78PWFeUo'
    '?Ir&Pw1Z6aYB%SbOvaK^KN`!~LO8>`5y6`d)5ohwmf)r;VEDB&0a8%ooby|^k<P-k{mku7*+<{+&vmTG`R`mJ_;`k+SX5aZ3>(i2'
    'czX=8&v=85vyk3Z16KIAI_OsL2ZDIqa>^XCKG<BH5A404lnGOiK!J#<f*rTkgH+F2m07Fyg|U<*KiKf%#$FX}M!jAKaBenA`>fu|'
    'M|9J$JTG)_OZfh?`p%vONMB4<=!d=7;!V|lg3RQHcz&>%v0Ksh44{~rZr>YIfG7Ux{Rs6el1oJcU8w?!d;d7o05V&IKWy{?<hwlq'
    'Ol8m5-;_F^TJ0GHFa-?#b4#;(E8=>wG%f&ue^3o8TyTakot}^J4Y0`O5F|AB4?rjGzu$Xb3wg`_a2|&lo<Rl6$YdGA1sGT%is2GM'
    'U^u~}v_w%1$<we*6S#!qz%VI6hAD>TU>vrOgMW2H=zn$7=HrFAzhjW^F3tf^R;wCl<G1g~^Zx;O9Qh6'
)).decode())
DESCRIPTION_SOURCE_ROWS = {row['path']: row for row in DESCRIPTION_LAYER['payload_changes']}

def description_predecessor_selection(selection):
    """Authenticate the full new layer before reconstructing published 7b bytes."""
    require(isinstance(selection, dict) and selection.get('description_repair') == DESCRIPTION_LAYER,
            'Missing/changed exact eleven-path description layer')
    layer = selection['description_repair']
    require(set(layer) == {'version', 'name', 'base_commit', 'base_tree', 'allowed_changes',
                          'payload_changes', 'diagnostic_before_blobs'}
            and type(layer['version']) is int and layer['version'] == 1
            and layer['name'] == 'description-initialization-repair-v8'
            and layer['base_commit'] == DESCRIPTION_BASE_COMMIT
            and layer['base_tree'] == DESCRIPTION_BASE_TREE,
            'Changed description layer fields/version/published identity')
    require(layer['allowed_changes'] == ['M\t' + path for path in DESCRIPTION_PATHS]
            and layer['diagnostic_before_blobs'] == {
                path: DESCRIPTION_BEFORE_BLOBS[path] for path in DESCRIPTION_DIAGNOSTIC_PATHS},
            'Changed independently fixed description statuses/diagnostic predecessors')
    rows = layer['payload_changes']
    require(isinstance(rows, list) and all(isinstance(row, dict) for row in rows)
            and [row.get('path') for row in rows] == list(DESCRIPTION_PAYLOAD_PATHS)
            and hashlib.sha256(encode(rows).encode()).hexdigest() == DESCRIPTION_REPAIR_CHANGES_SHA256,
            'Changed independently frozen ordered description payload bindings')
    require(hashlib.sha256(encode(selection).encode()).hexdigest() == DESCRIPTION_SELECTION_SHA256,
            'Changed complete description selection')
    old = {key: value for key, value in selection.items() if key != 'description_repair'}
    raw = (json.dumps(old, indent=2, ensure_ascii=True) + '\n').encode()
    require(hashlib.sha256(raw).hexdigest() == DESCRIPTION_PRE_SELECTION_SHA256
            and blob_id(raw) == DESCRIPTION_BEFORE_BLOBS[PATHS[1]],
            'Complete published 7b selection not restored')
    return json.loads(raw, object_pairs_hook=unique_object)


def description_predecessor_sources(selection, root):
    """Read all eleven real current files; authenticate and invert eight payloads."""
    description_predecessor_selection(selection)
    incoming = {}
    for relative in DESCRIPTION_PATHS:
        path = root / relative
        parts = Path(relative).parts
        require(all(not (root / Path(*parts[:end])).is_symlink()
                    for end in range(1, len(parts) + 1)),
                'Description source contains a symbolic-link component: ' + relative)
        require(not path.is_symlink() and path.is_file()
                and path.resolve().is_relative_to(root.resolve()),
                'Description source is not a regular in-root current file: ' + relative)
        incoming[relative] = path.read_bytes()
    require(hashlib.sha256(incoming[DESCRIPTION_DIAGNOSTIC_PATHS[0]]).hexdigest() == NATIVE_IMPLEMENTATION_SHA256,
            'Description runner differs from authenticated loaded implementation')
    require(hashlib.sha256(incoming[PATHS[1]]).hexdigest() == DESCRIPTION_SELECTION_RAW_SHA256,
            'Changed complete current description selection bytes')
    require(hashlib.sha256(incoming[DESCRIPTION_DIAGNOSTIC_PATHS[2]]).hexdigest() == DESCRIPTION_TEST_SHA256,
            'Changed complete current description diagnostic controls')
    restored = {}
    for row in DESCRIPTION_LAYER['payload_changes']:
        raw = incoming[row['path']]
        require(hashlib.sha256(raw).hexdigest() == row['after_sha256'] and blob_id(raw) == row['after_blob'],
                'Changed exact description payload: ' + row['path'])
        restored[row['path']] = inverse_reviewed_repair(row, raw)
        require(blob_id(restored[row['path']]) == DESCRIPTION_BEFORE_BLOBS[row['path']],
                'Wrong complete 7b description predecessor: ' + row['path'])
    require(set(restored) == set(DESCRIPTION_PAYLOAD_PATHS), 'Incomplete description predecessor set')
    return restored


def validate_description_selection(selection, root):
    old = description_predecessor_selection(selection)
    description_predecessor_sources(selection, root)
    # Published portable4 is independently fixed; current entry bytes remain
    # mandatory and its two-line predecessor is checked by the native14 path.
    require(digest(root / 'tools/tests/test_run138_current_ci_entry.py') ==
            PORTABLE_SOURCE_ROWS['tools/tests/test_run138_current_ci_entry.py']['after_sha256'],
            'Description current entry test differs from published 7b')
    validate_native_selection(portable_predecessor_selection(old), root, description_layer=True)
    return selection


def verify_description_tree(root, revision, *, before):
    expected = DESCRIPTION_BEFORE_BLOBS if before else {
        path: blob_id((root / path).read_bytes()) for path in DESCRIPTION_PATHS}
    raw = checked(['git', 'ls-tree', '-z', revision, '--', *DESCRIPTION_PATHS], root)
    actual = {}
    for entry in raw.split('\0'):
        if not entry: continue
        metadata, path = entry.split('\t', 1)
        require(path not in actual, 'Duplicate description tree path')
        actual[path] = metadata.split(' ')
    require(set(actual) == set(DESCRIPTION_PATHS), 'Missing/unexpected description tree path')
    for path, blob in expected.items():
        require(actual[path] == ['100644', 'blob', blob], 'Changed description mode/blob: ' + path)
    return actual


def verify_description_scope(root, selection):
    validate_description_selection(selection, root)
    head = checked(['git', 'rev-parse', 'HEAD'], root)
    require(re.fullmatch('[a-f0-9]{40}', head) is not None
            and head == os.environ.get('GITHUB_SHA'), 'Actual description HEAD differs from GITHUB_SHA')
    headers = checked(['git', 'cat-file', '-p', head], root).split('\n\n', 1)[0].splitlines()
    require([line[7:] for line in headers if line.startswith('parent ')] == [DESCRIPTION_BASE_COMMIT],
            'Description repair must have exactly published 7b parent')
    require(checked(['git', 'rev-parse', DESCRIPTION_BASE_COMMIT + '^{tree}'], root) == DESCRIPTION_BASE_TREE,
            'Changed published 7b tree')
    changes = checked(['git', 'diff', '--name-status', DESCRIPTION_BASE_COMMIT, head], root).splitlines()
    require(len(changes) == 11 and set(changes) == set(DESCRIPTION_LAYER['allowed_changes']),
            'Description repair differs from eleven exact statuses')
    verify_description_tree(root, DESCRIPTION_BASE_COMMIT, before=True)
    verify_description_tree(root, head, before=False)
    ensure_portable_commit(root)
    prior = verify_portable_scope(root, description_predecessor_selection(selection),
                                  published_revision=DESCRIPTION_BASE_COMMIT)
    prior.update(source_sha=head, source_tree=checked(['git', 'rev-parse', 'HEAD^{tree}'], root),
                 description_base_commit=DESCRIPTION_BASE_COMMIT,
                 description_base_tree=DESCRIPTION_BASE_TREE,
                 description_selection=DESCRIPTION_LAYER['name'])
    require(not checked(['git', 'status', '--porcelain', '--untracked-files=normal'], root),
            'Description checkout is not clean')
    return prior


def validate_description_pass_receipt(receipt, expected, selection):
    require(receipt.get('description_base_commit') == DESCRIPTION_BASE_COMMIT
            and receipt.get('description_base_tree') == DESCRIPTION_BASE_TREE
            and receipt.get('description_selection') == DESCRIPTION_LAYER['name'],
            'Wrong receipt description repair identity')
    validate_portable_pass_receipt(receipt, expected, description_predecessor_selection(selection))


def portable_predecessor_selection(selection):
    """Authenticate the new diagnostic-only layer and restore exact published f04."""
    require(isinstance(selection, dict) and 'portable_diagnostics' in selection,
            'Missing mandatory portable diagnostic layer')
    require(selection['portable_diagnostics'] == PORTABLE_LAYER,
            'Changed exact four-path portable diagnostic layer')
    require(hashlib.sha256(encode(selection).encode()).hexdigest() == PORTABLE_SELECTION_SHA256,
            'Changed complete portable selection')
    old = {key: value for key, value in selection.items() if key != 'portable_diagnostics'}
    raw = (json.dumps(old, indent=2, ensure_ascii=True) + '\n').encode()
    require(hashlib.sha256(raw).hexdigest() == PORTABLE_PRE_SELECTION_SHA256
            and blob_id(raw) == PORTABLE_BEFORE_BLOBS[PATHS[1]],
            'Complete published f04 selection bytes not restored')
    return json.loads(json.dumps(old, ensure_ascii=True), object_pairs_hook=unique_object)


def portable_f04_source(relative, raw):
    """Exact reviewed entry-test predecessor for the historical native14 layer."""
    if relative not in PORTABLE_SOURCE_ROWS: return raw
    row = PORTABLE_SOURCE_ROWS[relative]
    if hashlib.sha256(raw).hexdigest() == row['before_sha256'] and blob_id(raw) == row['before_blob']:
        return raw  # Explicit f04 historical input; current validation below is stricter.
    require(hashlib.sha256(raw).hexdigest() == row['after_sha256'] and blob_id(raw) == row['after_blob'],
            'Changed complete portable entry-test source')
    return inverse_reviewed_repair(row, raw)


def validate_portable_selection(selection, root):
    old = portable_predecessor_selection(selection)
    for relative in PORTABLE_PATHS:
        path = root / relative
        require(not path.is_symlink() and path.is_file()
                and path.resolve().is_relative_to(root.resolve()),
                'Portable diagnostic is not a regular current source')
    require(digest(root / PORTABLE_PATHS[0]) == NATIVE_IMPLEMENTATION_SHA256,
            'Portable runner differs from authenticated loaded implementation')
    require(digest(root / PORTABLE_PATHS[1]) == PORTABLE_SELECTION_RAW_SHA256,
            'Changed actual portable selection source')
    require(digest(root / PORTABLE_PATHS[2]) == PORTABLE_TEST_SHA256,
            'Changed complete portable diagnostic controls')
    for relative, row in PORTABLE_SOURCE_ROWS.items():
        raw = (root / relative).read_bytes()
        require(hashlib.sha256(raw).hexdigest() == row['after_sha256'] and blob_id(raw) == row['after_blob'],
                'Current entry-test cannot use its f04 predecessor')
        require(blob_id(portable_f04_source(relative, raw)) == row['before_blob'],
                'Complete f04 entry-test predecessor not restored')
    validate_native_selection(old, root)
    return selection


def verify_portable_tree(root, revision, *, before, diagnostic_blobs=None):
    expected = PORTABLE_BEFORE_BLOBS if before else {
        relative: blob_id((root / relative).read_bytes()) for relative in PORTABLE_PATHS}
    if diagnostic_blobs is not None:
        require(diagnostic_blobs == DESCRIPTION_PORTABLE_BEFORE_BLOBS and not before
                and revision == DESCRIPTION_BASE_COMMIT,
                'Unknown published portable diagnostic tree authority')
        expected = diagnostic_blobs
    raw = checked(['git', 'ls-tree', '-z', revision, '--', *PORTABLE_PATHS], root)
    actual = {}
    for entry in raw.split('\0'):
        if not entry: continue
        metadata, path = entry.split('\t', 1)
        require(path not in actual, 'Duplicate portable diagnostic tree path')
        actual[path] = metadata.split(' ')
    require(set(actual) == set(PORTABLE_PATHS), 'Missing portable diagnostic tree path')
    for path, blob in expected.items():
        require(actual[path] == ['100644', 'blob', blob], 'Changed portable diagnostic mode/blob: ' + path)
    return actual


def verify_portable_scope(root, selection, *, published_revision=None):
    if published_revision is None:
        validate_portable_selection(selection, root)
        head = checked(['git', 'rev-parse', 'HEAD'], root)
        require(re.fullmatch('[a-f0-9]{40}', head) is not None
                and head == os.environ.get('GITHUB_SHA'), 'Actual portable HEAD differs from GITHUB_SHA')
    else:
        require(published_revision == DESCRIPTION_BASE_COMMIT, 'Unknown published portable scope revision')
        current = read_json(root / PATHS[1])
        validate_description_selection(current, root)
        require(description_predecessor_selection(current) == selection,
                'Changed complete published portable selection')
        head = published_revision
        require(checked(['git', 'rev-parse', head + '^{tree}'], root) == DESCRIPTION_BASE_TREE,
                'Changed published portable scope tree')
    headers = checked(['git', 'cat-file', '-p', head], root).split('\n\n', 1)[0].splitlines()
    require([line[7:] for line in headers if line.startswith('parent ')] == [PORTABLE_BASE_COMMIT],
            'Portable diagnostic must have exactly the published f04 parent')
    require(checked(['git', 'rev-parse', PORTABLE_BASE_COMMIT + '^{tree}'], root) == PORTABLE_BASE_TREE,
            'Published f04 diagnostic tree changed')
    changes = checked(['git', 'diff', '--name-status', PORTABLE_BASE_COMMIT, head], root).splitlines()
    require(len(changes) == 4 and set(changes) == set(PORTABLE_LAYER['allowed_changes']),
            'Portable diagnostic changes differ from four exact statuses')
    verify_portable_tree(root, PORTABLE_BASE_COMMIT, before=True)
    verify_portable_tree(root, head, before=False,
                         diagnostic_blobs=DESCRIPTION_PORTABLE_BEFORE_BLOBS if published_revision else None)
    ensure_native_commit(root)
    prior = verify_native_scope(root, portable_predecessor_selection(selection),
                                published_revision=PORTABLE_BASE_COMMIT, description_layer=published_revision is not None)
    prior.update(source_sha=head, source_tree=checked(['git', 'rev-parse', (published_revision or 'HEAD') + '^{tree}'], root),
                 portable_base_commit=PORTABLE_BASE_COMMIT, portable_base_tree=PORTABLE_BASE_TREE,
                 portable_selection=PORTABLE_LAYER['name'])
    require(not checked(['git', 'status', '--porcelain', '--untracked-files=normal'], root),
            'Portable checkout is not clean')
    return prior


def validate_portable_pass_receipt(receipt, expected, selection):
    require(receipt.get('portable_base_commit') == PORTABLE_BASE_COMMIT
            and receipt.get('portable_base_tree') == PORTABLE_BASE_TREE
            and receipt.get('portable_selection') == PORTABLE_LAYER['name'],
            'Wrong receipt portable diagnostic identity')
    validate_native_pass_receipt(receipt, expected, portable_predecessor_selection(selection))


def native_predecessor_selection(selection):
    """Return only the complete independently pinned c2af v5 selection."""
    require(isinstance(selection, dict) and 'native_repair' in selection,
            'Missing mandatory current native repair layer')
    old = {key: value for key, value in selection.items() if key != 'native_repair'}
    require(hashlib.sha256(encode(old).encode()).hexdigest()
            == 'ffc171f8f6c7b3097a8edc8d71e0e82fe0b123ac77c68cbc36009e9b83f4b379',
            'Changed complete c2af predecessor selection')
    # JSON roundtrip prevents a historical consumer mutating current identities.
    return json.loads(json.dumps(old, ensure_ascii=True), object_pairs_hook=unique_object)


def native_predecessor_selection_bytes(selection):
    """Restore the original c2af JSON encoding, not just its semantic object."""
    raw = (json.dumps(native_predecessor_selection(selection), indent=2, ensure_ascii=True) + '\n').encode()
    require(hashlib.sha256(raw).hexdigest()
            == 'c3562224a372d442434ed28bc861aef370cf18e72d69faf9b97b0a8652247bf5'
            and blob_id(raw) == '02ae2c0e2092a40257ecf8e9aca83f5776470853',
            'Complete c2af selection encoding or Git blob changed')
    return raw


def native_predecessor_sources(selection, root, *, description_layer=False):
    """Read all eleven real postimages before returning any exact c2af bytes.

    No cache, healthy-root fallback, missing-input completion, or old-byte
    admission is provided here. The new runtime must authenticate this boundary
    before any unchanged v5 source and inverse checks.
    """
    native_predecessor_selection(selection)
    description_sources = {}
    if description_layer:
        current = read_json(root / PATHS[1])
        require(portable_predecessor_selection(description_predecessor_selection(current)) == selection,
                'Description historical native selection mismatch')
        description_sources = description_predecessor_sources(current, root)
    layer = selection.get('native_repair')
    require(isinstance(layer, dict) and set(layer) == {'version', 'name', 'base_commit',
            'base_tree', 'allowed_changes', 'payload_changes', 'diagnostic_before_blobs'},
            'Unknown native repair layer fields')
    require(type(layer['version']) is int and layer['version'] == 1
            and layer['name'] == NATIVE_NAME and layer['base_commit'] == NATIVE_BASE_COMMIT
            and layer['base_tree'] == NATIVE_BASE_TREE, 'Wrong exact c2af native base')
    require(layer['allowed_changes'] == list(NATIVE_ALLOWED_CHANGES)
            and layer['diagnostic_before_blobs'] == NATIVE_DIAGNOSTIC_BASE_BLOBS,
            'Changed exact native fourteen-path boundary')
    rows = layer['payload_changes']
    require(isinstance(rows, list) and all(isinstance(row, dict) for row in rows)
            and [row.get('path') for row in rows] == list(NATIVE_PAYLOAD_PATHS),
            'Missing/reordered native eleven-file payload')
    require(hashlib.sha256(encode(rows).encode()).hexdigest() == NATIVE_REPAIR_CHANGES_SHA256,
            'Changed independently frozen native repair bindings')
    restored = {}
    for row in rows:
        require(set(row) == {'path', 'status', 'before_sha256', 'before_blob',
                'after_sha256', 'after_blob', 'hunks'} and row['status'] == 'M',
                'Invalid native repair fields/status')
        require((row['before_sha256'], row['before_blob']) == NATIVE_PREIMAGES[row['path']],
                'Wrong independent c2af payload predecessor')
        require(all(isinstance(row[key], str) and re.fullmatch(pattern, row[key])
                    for key, pattern in [('after_sha256', '[a-f0-9]{64}'),
                                         ('after_blob', '[a-f0-9]{40}')]),
                'Malformed native current digest')
        require(isinstance(row['hunks'], list) and bool(row['hunks'])
                and all(isinstance(h, dict) and set(h) == {'before', 'after'}
                        and all(isinstance(h[k], str) and bool(h[k]) for k in ('before', 'after'))
                        and h['before'] != h['after'] for h in row['hunks']),
                'Invalid native repair inverse hunks')
        path = root / row['path']
        require(not path.is_symlink() and path.is_file()
                and path.resolve().is_relative_to(root.resolve()),
                'Native source escaped checkout or is not a regular file')
        current_raw = path.read_bytes()
        raw = portable_f04_source(row['path'], description_sources.get(row['path'], current_raw))
        require(hashlib.sha256(raw).hexdigest() == row['after_sha256'],
                'Changed complete current native bytes: ' + row['path'])
        require(blob_id(raw) == row['after_blob'], 'Changed complete current native blob')
        restored[row['path']] = inverse_reviewed_repair(row, raw)
    return restored


def historical_source(relative, raw, predecessor):
    """An explicit c2af map cannot broaden or weaken any historical digest."""
    if predecessor is None:
        return raw  # Explicit v5 interface, never the current CLI admission path.
    require(isinstance(predecessor, dict) and set(predecessor) == set(NATIVE_PAYLOAD_PATHS),
            'Incomplete exact c2af predecessor mapping')
    if relative not in NATIVE_PREIMAGES:
        return raw
    restored = predecessor[relative]
    require(isinstance(restored, bytes)
            and (hashlib.sha256(restored).hexdigest(), blob_id(restored))
            == NATIVE_PREIMAGES[relative], 'Unauthenticated c2af predecessor source')
    return restored


def validate_native_selection(selection, root, *, description_layer=False):
    implementation = root / 'tools/run_targeted_native.py'
    require(not implementation.is_symlink() and implementation.is_file()
            and implementation.resolve().is_relative_to(root.resolve())
            and digest(implementation) == NATIVE_IMPLEMENTATION_SHA256,
            'Current native runner differs from the authenticated loaded implementation')
    predecessor = native_predecessor_sources(selection, root, description_layer=description_layer)
    old = native_predecessor_selection(selection)
    validate_selection(old, root, predecessor=predecessor)
    require(hashlib.sha256(encode(selection).encode()).hexdigest()
            == NATIVE_SELECTION_CONTRACT_SHA256, 'Fixed native selection contract changed')
    return selection


def verify_native_tree(selection, root, revision, before, *, diagnostic_blobs=None, description_layer=False):
    """Independent actual-tree mode/blob authority for all fourteen paths."""
    native_predecessor_sources(selection, root, description_layer=description_layer)
    raw = checked(['git', 'ls-tree', '-z', revision, '--', *NATIVE_PATHS], root)
    entries = {}
    for entry in raw.split('\0'):
        if not entry:
            continue
        metadata, path = entry.split('\t', 1)
        require(path not in entries, 'Duplicate native tree path')
        entries[path] = metadata.split(' ')
    expected = {row['path']: row['before_blob' if before else 'after_blob']
                for row in selection['native_repair']['payload_changes']}
    if diagnostic_blobs is not None:
        require(diagnostic_blobs == PORTABLE_BEFORE_BLOBS and not before
                and revision == PORTABLE_BASE_COMMIT, 'Unknown published diagnostic tree authority')
    for relative, old_blob in NATIVE_DIAGNOSTIC_BASE_BLOBS.items():
        if diagnostic_blobs is not None:
            expected[relative] = diagnostic_blobs[relative]
        elif before:
            expected[relative] = old_blob
        else:
            source = root / relative
            require(not source.is_symlink() and source.is_file()
                    and source.resolve().is_relative_to(root.resolve()),
                    'Native diagnostic source escaped checkout or is not a regular file')
            expected[relative] = blob_id(source.read_bytes())
    require(set(entries) == set(expected), 'Native tree has missing or unexpected paths')
    for relative, blob in expected.items():
        require(entries[relative] == ['100644', 'blob', blob],
                'Native tree differs from exact reviewed mode/blob: ' + relative)
    return entries


def ensure_repair_commit(root):
    """Read only fixed public3393 if the new depth-two checkout lacks it."""
    require(BASE_COMMIT == '3393ec85076a7a4e246e94e98ddf81f6b73ede2f'
            and BASE_TREE == '7dd9461bafbe546e1c5ef5eaacc750267b416b2f',
            'Changed fixed public repair object target')
    try:
        checked(['git', 'cat-file', '-e', BASE_COMMIT + '^{commit}'], root)
        checked(['git', 'cat-file', '-e', BASE_COMMIT + '^{tree}'], root)
    except ValueError:
        environment = {'PATH': os.environ.get('PATH', os.defpath), 'LANG': 'C',
                       'HOME': '/dev/null', 'GIT_TERMINAL_PROMPT': '0',
                       'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                       'GIT_ASKPASS': '/usr/bin/false', 'SSH_ASKPASS': '/usr/bin/false'}
        code, raw = execute(['git', 'config', '--local', '--includes', '--name-only', '--list'],
                            root, 10, True, env=environment)
        require(code == 0, 'Cannot inspect public-read repository configuration')
        keys = raw.decode().lower().splitlines()
        require(not any(k.startswith(('url.', 'http.', 'credential.', 'include.', 'includeif.'))
                        or k in {'core.askpass', 'extensions.worktreeconfig'} for k in keys),
                'Public repair read rejects credential, redirect, or included configuration')
        command = ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                   '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                   '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                   'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                   'https://github.com/liboyang42-cpu/chengyin-ios.git',
                   '3393ec85076a7a4e246e94e98ddf81f6b73ede2f']
        code, _ = execute(command, root, 60, True, env=environment)
        require(code == 0, 'Exact public 3393 read failed; historical repair verification is unavailable')
    raw = checked(['git', 'cat-file', '-p', BASE_COMMIT], root)
    headers = raw.split('\n\n', 1)[0].splitlines()
    require([line[5:] for line in headers if line.startswith('tree ')] == [BASE_TREE]
            and [line[7:] for line in headers if line.startswith('parent ')]
            == ['cf7b3e7f0f7c2105b23c439f2314d6163886c126'],
            'Published 3393 commit/tree/parent identity differs')


def ensure_portable_commit(root):
    """Read only fixed public f04 if the new depth-two checkout lacks it."""
    require(PORTABLE_BASE_COMMIT == 'f04f1cab7ef92afcafcdbde411dde71b4a605820'
            and PORTABLE_BASE_TREE == '75569d4e6d8ed5c23ee9865164a8d01c2e346116',
            'Changed fixed public repair object target')
    try:
        checked(['git', 'cat-file', '-e', PORTABLE_BASE_COMMIT + '^{commit}'], root)
        checked(['git', 'cat-file', '-e', PORTABLE_BASE_COMMIT + '^{tree}'], root)
    except ValueError:
        environment = {'PATH': os.environ.get('PATH', os.defpath), 'LANG': 'C',
                       'HOME': '/dev/null', 'GIT_TERMINAL_PROMPT': '0',
                       'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                       'GIT_ASKPASS': '/usr/bin/false', 'SSH_ASKPASS': '/usr/bin/false'}
        code, raw = execute(['git', 'config', '--local', '--includes', '--name-only', '--list'],
                            root, 10, True, env=environment)
        require(code == 0, 'Cannot inspect public-read repository configuration')
        keys = raw.decode().lower().splitlines()
        require(not any(k.startswith(('url.', 'http.', 'credential.', 'include.', 'includeif.'))
                        or k in {'core.askpass', 'extensions.worktreeconfig'} for k in keys),
                'Public repair read rejects credential, redirect, or included configuration')
        command = ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                   '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                   '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                   'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                   'https://github.com/liboyang42-cpu/chengyin-ios.git',
                   'f04f1cab7ef92afcafcdbde411dde71b4a605820']
        code, _ = execute(command, root, 60, True, env=environment)
        require(code == 0, 'Exact public f04 read failed; historical repair verification is unavailable')
    raw = checked(['git', 'cat-file', '-p', PORTABLE_BASE_COMMIT], root)
    headers = raw.split('\n\n', 1)[0].splitlines()
    require([line[5:] for line in headers if line.startswith('tree ')] == [PORTABLE_BASE_TREE]
            and [line[7:] for line in headers if line.startswith('parent ')]
            == ['c2af90a5e11a789ca8dc99eb8daae2c1e84e0700'],
            'Published f04 commit/tree/parent identity differs')


def ensure_native_commit(root):
    """Read only fixed public c2af if the new depth-two checkout lacks it."""
    require(NATIVE_BASE_COMMIT == 'c2af90a5e11a789ca8dc99eb8daae2c1e84e0700'
            and NATIVE_BASE_TREE == 'bb341123236a28027becc55e06f35cb294bb718f',
            'Changed fixed public repair object target')
    try:
        checked(['git', 'cat-file', '-e', NATIVE_BASE_COMMIT + '^{commit}'], root)
        checked(['git', 'cat-file', '-e', NATIVE_BASE_COMMIT + '^{tree}'], root)
    except ValueError:
        environment = {'PATH': os.environ.get('PATH', os.defpath), 'LANG': 'C',
                       'HOME': '/dev/null', 'GIT_TERMINAL_PROMPT': '0',
                       'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
                       'GIT_ASKPASS': '/usr/bin/false', 'SSH_ASKPASS': '/usr/bin/false'}
        code, raw = execute(['git', 'config', '--local', '--includes', '--name-only', '--list'],
                            root, 10, True, env=environment)
        require(code == 0, 'Cannot inspect public-read repository configuration')
        keys = raw.decode().lower().splitlines()
        require(not any(k.startswith(('url.', 'http.', 'credential.', 'include.', 'includeif.'))
                        or k in {'core.askpass', 'extensions.worktreeconfig'} for k in keys),
                'Public repair read rejects credential, redirect, or included configuration')
        command = ['git', '-c', 'credential.helper=', '-c', 'core.askPass=',
                   '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
                   '-c', 'protocol.allow=never', '-c', 'protocol.https.allow=always',
                   'fetch', '--no-tags', '--no-write-fetch-head', '--depth=1', '--no-recurse-submodules',
                   'https://github.com/liboyang42-cpu/chengyin-ios.git',
                   'c2af90a5e11a789ca8dc99eb8daae2c1e84e0700']
        code, _ = execute(command, root, 60, True, env=environment)
        require(code == 0, 'Exact public c2af read failed; historical repair verification is unavailable')
    raw = checked(['git', 'cat-file', '-p', NATIVE_BASE_COMMIT], root)
    headers = raw.split('\n\n', 1)[0].splitlines()
    require([line[5:] for line in headers if line.startswith('tree ')] == [NATIVE_BASE_TREE]
            and [line[7:] for line in headers if line.startswith('parent ')]
            == ['3393ec85076a7a4e246e94e98ddf81f6b73ede2f'],
            'Published c2af commit/tree/parent identity differs')


def verify_native_scope(root, selection, *, published_revision=None, description_layer=False):
    validate_native_selection(selection, root, description_layer=description_layer)
    if published_revision is None:
        head = checked(['git', 'rev-parse', 'HEAD'], root)
        require(re.fullmatch('[a-f0-9]{40}', head) is not None
                and head == os.environ.get('GITHUB_SHA'), 'Actual HEAD differs from GITHUB_SHA')
    else:
        require(published_revision == PORTABLE_BASE_COMMIT, 'Unknown published native scope revision')
        head = published_revision
        require(checked(['git', 'rev-parse', head + '^{tree}'], root) == PORTABLE_BASE_TREE,
                'Changed published native scope tree')
    require(checked(['git', 'rev-parse', NATIVE_BASE_COMMIT + '^{tree}'], root) == NATIVE_BASE_TREE,
            'Published c2af native baseline tree differs')
    headers = checked(['git', 'cat-file', '-p', head], root).split('\n\n', 1)[0].splitlines()
    require([line[7:] for line in headers if line.startswith('parent ')] == [NATIVE_BASE_COMMIT],
            'Native repair must have exactly the published c2af parent')
    changes = checked(['git', 'diff', '--name-status', NATIVE_BASE_COMMIT, head], root).splitlines()
    require(len(changes) == len(NATIVE_ALLOWED_CHANGES) and set(changes) == set(NATIVE_ALLOWED_CHANGES),
            'Source changes differ from fourteen exact native repair statuses')
    parent = checked(['git', 'cat-file', '-p', NATIVE_BASE_COMMIT], root).split('\n\n', 1)[0].splitlines()
    require([line[5:] for line in parent if line.startswith('tree ')] == [NATIVE_BASE_TREE]
            and [line[7:] for line in parent if line.startswith('parent ')] == [BASE_COMMIT],
            'Published c2af commit/tree/parent identity differs')
    verify_native_tree(selection, root, NATIVE_BASE_TREE, before=True, description_layer=description_layer)
    verify_native_tree(selection, root, head, before=False,
                       diagnostic_blobs=PORTABLE_BEFORE_BLOBS if published_revision else None,
                       description_layer=description_layer)
    ensure_repair_commit(root)
    prior = checked(['git', 'diff', '--name-status', BASE_COMMIT, NATIVE_BASE_COMMIT], root).splitlines()
    require(len(prior) == len(ALLOWED_CHANGES) and set(prior) == set(ALLOWED_CHANGES),
            'Published c2af history differs from fifteen exact repair statuses')
    ensure_creator_commit(root)
    require(checked(['git', 'rev-parse', HISTORICAL_BASE_COMMIT + '^{tree}'], root)
            == HISTORICAL_BASE_TREE, 'Historical baseline tree differs')
    historical = checked(['git', 'diff', '--name-status', HISTORICAL_BASE_COMMIT, CREATOR_COMMIT], root).splitlines()
    require(len(historical) == len(HISTORICAL_ALLOWED_CHANGES) and set(historical) == set(HISTORICAL_ALLOWED_CHANGES),
            'Published b75 history differs from nineteen exact reviewed statuses')
    parent_history = checked(['git', 'diff', '--name-status', CREATOR_COMMIT, BASE_COMMIT], root).splitlines()
    require(len(parent_history) == len(PARENT_HISTORY_CHANGES) and set(parent_history) == set(PARENT_HISTORY_CHANGES),
            'Published creator-to-3393 history differs from its exact statuses')
    old = native_predecessor_selection(selection)
    verify_creator_parent_tree(old, root, CREATOR_TREE, before=True)
    verify_creator_parent_tree(old, root, BASE_TREE, before=False)
    verify_static_repair_tree(old, root, BASE_TREE, before=True)
    verify_static_repair_tree(old, root, NATIVE_BASE_TREE, before=False,
                              diagnostic_blobs=NATIVE_DIAGNOSTIC_BASE_BLOBS)
    verify_creator_current_tree(old, root, CREATOR_COMMIT)
    verify_creator_baseline(old, root)
    require(not checked(['git', 'status', '--porcelain', '--untracked-files=normal'], root), 'Checkout is not clean')
    return {'source_sha': head, 'source_tree': checked(['git', 'rev-parse', (published_revision or 'HEAD') + '^{tree}'], root),
            'base_commit': BASE_COMMIT, 'base_tree': BASE_TREE,
            'historical_base_commit': HISTORICAL_BASE_COMMIT, 'historical_base_tree': HISTORICAL_BASE_TREE,
            'creator_base_commit': CREATOR_COMMIT, 'creator_base_tree': CREATOR_TREE,
            'native_base_commit': NATIVE_BASE_COMMIT, 'native_base_tree': NATIVE_BASE_TREE,
            'native_selection': NATIVE_NAME}


def choose_simulator(data):
    require(isinstance(data, dict) and isinstance(data.get('devices'), dict), 'Invalid simulator inventory')
    choices = []
    for runtime, devices in data['devices'].items():
        if not runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-'):
            continue
        for device in devices:
            if device.get('isAvailable') is True and device.get('name', '').startswith('iPhone'):
                require(re.fullmatch('[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', device.get('udid', '')) is not None, 'Invalid simulator UUID')
                choices.append({'runtime': runtime, 'name': device['name'], 'udid': device['udid']})
    require(bool(choices), 'No available iPhone simulator')
    return sorted(choices, key=lambda d: (d['runtime'], d['name'], d['udid']))[-1]


def core_command(group, output):
    alternatives = []
    for identifier in group['methods']:
        target, cls, method = identifier.split('/')
        alternatives.append(re.escape(target + '.' + cls + '/' + method))
    require(bool(alternatives), 'Empty Core selection')
    return ['swift', 'test', '--skip-build', '--verbose', '--parallel', '--num-workers', '1', '--filter',
            '^(?:' + '|'.join(alternatives) + ')$', '--xunit-output', str(output)]


def xcode_test_command(group, run, simulator, result):
    allowance = '120' if group['name'] == 'app-unit' else '900'
    return ['xcodebuild', '-xctestrun', str(run), '-destination', 'platform=iOS Simulator,id=' + simulator,
            '-destination-timeout', '60', '-resultBundlePath', str(result), '-parallel-testing-enabled', 'NO',
            '-maximum-concurrent-test-simulator-destinations', '1', '-test-timeouts-enabled', 'YES',
            '-default-test-execution-time-allowance', allowance, '-maximum-test-execution-time-allowance', allowance,
            *['-only-testing:' + method for method in group['methods']], 'test-without-building']


def parse_xunit(raw):
    require(len(raw) <= LIMIT, 'Oversized xUnit')
    tree = ET.fromstring(raw)
    require(tree.tag in {'testsuite', 'testsuites'}, 'Unknown xUnit root')
    result = []
    for node in tree.iter('testcase'):
        cls, name = node.get('classname', ''), node.get('name', '')
        require(cls.startswith('QuestifyCoreTests.') and name, 'Unknown xUnit method identity')
        if name.endswith('()'):
            name = name[:-2]
        identifier = cls.replace('.', '/', 1) + '/' + name
        require(METHOD.fullmatch(identifier) is not None, 'Malformed xUnit method')
        require(node.get('status', 'run') in {'run', 'passed', 'Passed'}, 'Unexpected xUnit case status')
        children = {child.tag for child in node}
        require(children <= {'failure', 'error', 'skipped', 'system-out', 'system-err'}, 'Unknown xUnit result schema')
        result.append({'method': identifier, 'status': 'Skipped' if 'skipped' in children else
                       'Failed' if children & {'failure', 'error'} else 'Passed'})
    for suite in tree.iter():
        if suite.tag in {'testsuite', 'testsuites'}:
            if 'tests' in suite.attrib:
                require(suite.get('tests', '').isdigit() and int(suite.get('tests')) == len(list(suite.iter('testcase'))), 'xUnit suite count does not match cases')
            for key in ['failures', 'errors', 'skipped']:
                require(suite.get(key, '0') == '0', 'xUnit suite has non-passing outcomes')
    return result



def parse_core_transcript(raw):
    """SwiftPM xUnit records process success, including XCTSkip/zero execution.

    Require the real Darwin XCTest started/terminal lines as independent evidence.
    --verbose makes SwiftPM print successful child transcripts too.
    """
    require(len(raw) <= LIMIT, 'Oversized Core transcript')
    starts, rows = [], []
    pattern = re.compile(r"^Test Case '-\[(QuestifyCoreTests)\.([A-Za-z][A-Za-z0-9_]*) (test[A-Za-z0-9_]+)\]' (.+)$")
    for line in raw.decode('utf-8').splitlines():
        if not line.startswith('Test Case '):
            continue
        match = pattern.fullmatch(line)
        require(match is not None, 'Unknown Core XCTest transcript schema')
        target, cls, method, outcome = match.groups()
        identifier = target + '/' + cls + '/' + method
        if outcome == 'started.':
            starts.append(identifier)
        else:
            terminal = re.fullmatch(r'(passed|failed|skipped) \([0-9]+(?:\.[0-9]+)? seconds\)\.', outcome)
            require(terminal is not None, 'Unknown Core XCTest terminal result')
            rows.append({'method': identifier, 'status': {'passed': 'Passed', 'failed': 'Failed', 'skipped': 'Skipped'}[terminal[1]]})
    require(bool(rows) and len(starts) == len(set(starts)) and sorted(starts) == sorted(r['method'] for r in rows),
            'Missing/duplicate Core XCTest start or terminal result')
    return rows


def validate_core_evidence(xml, transcript, expected, returncode):
    rows = parse_xunit(xml)
    executed = parse_core_transcript(transcript)
    validate_outcomes(rows, expected, returncode)
    validate_outcomes(executed, expected, returncode)
    require(sorted(rows, key=lambda r: r['method']) == sorted(executed, key=lambda r: r['method']),
            'Core xUnit does not match actual XCTest execution')
    return rows


def parse_xcresult(data, target):
    require(isinstance(data, dict) and isinstance(data.get('testNodes'), list), 'Unknown xcresult tests schema')
    result = []
    def visit(node, ancestors):
        require(isinstance(node, dict) and isinstance(node.get('nodeType'), str), 'Malformed xcresult node')
        ancestry = ancestors + [node.get('name', '')]
        if node['nodeType'] == 'Test Case':
            identifier = node.get('nodeIdentifier')
            require(isinstance(identifier, str), 'Missing XCTest method identity')
            url = node.get('nodeIdentifierURL') or node.get('testIdentifierURL')
            if url:
                parsed = urlparse(url)
                parts = unquote(parsed.path).strip('/').split('/')
                require(parsed.scheme == 'test' and parsed.netloc == 'com.apple.xcode' and target in parts, 'Wrong XCTest target URL')
                require(not any(t in parts for t in ['QuestifyAppUnitTests', 'QuestifyUITests'] if t != target), 'Conflicting XCTest target URL')
            else:
                require(target in ancestors or target + '.xctest' in ancestors or identifier.startswith(target + '/'), 'Missing XCTest target binding')
            require(not any(t in ancestors for t in ['QuestifyAppUnitTests', 'QuestifyUITests'] if t != target), 'Wrong XCTest bundle')
            if identifier.endswith('()'):
                identifier = identifier[:-2]
            if identifier.count('/') == 1:
                identifier = target + '/' + identifier
            require(METHOD.fullmatch(identifier) is not None and identifier.startswith(target + '/'), 'Malformed XCTest method')
            require(isinstance(node.get('result'), str), 'Missing XCTest outcome')
            require(node['result'] != 'Passed' or not node.get('children'), 'Unexpected nested result/repetition in passed XCTest case')
            result.append({'method': identifier, 'status': node['result']})
        for child in node.get('children', []):
            # Test Case children include diagnostics/activities, not new methods.
            if node['nodeType'] != 'Test Case':
                visit(child, ancestry)
    for node in data['testNodes']:
        visit(node, [])
    return result


def validate_outcomes(rows, expected, returncode):
    require(type(returncode) is int and returncode == 0, 'Test process did not succeed')
    require(isinstance(rows, list) and all(isinstance(r, dict) and set(r) == {'method', 'status'} for r in rows), 'Unknown actual result rows')
    require(bool(rows), 'Zero actual tests is never success')
    identifiers = [row['method'] for row in rows]
    require(len(identifiers) == len(set(identifiers)), 'Duplicate actual tests')
    require(set(identifiers) == set(expected) and len(identifiers) == len(expected), 'Actual methods differ from exact selection')
    require(all(row['status'] == 'Passed' for row in rows), 'Failed/skipped/incomplete selected method')


def validate_summary(summary, count, simulator):
    require(isinstance(summary, dict), 'Invalid XCTest summary')
    for key, value in [('totalTestCount', count), ('passedTests', count), ('failedTests', 0), ('skippedTests', 0)]:
        require(type(summary.get(key)) is int and summary[key] == value, 'Wrong XCTest summary count: ' + key)
    require(summary.get('expectedFailures', 0) == 0, 'Expected failures are not passes')
    def contains(value):
        if isinstance(value, str):
            return value.lower() == simulator.lower()
        if isinstance(value, dict):
            return any(contains(v) for v in value.values())
        if isinstance(value, list):
            return any(contains(v) for v in value)
        return False
    require(contains(summary.get('devicesAndConfigurations')), 'Result does not identify selected simulator')


def plist_records(value):
    if isinstance(value, dict):
        if isinstance(value.get('TestBundlePath'), str):
            yield value
        for child in value.values():
            yield from plist_records(child)
    elif isinstance(value, list):
        for child in value:
            yield from plist_records(child)


def select_xctestrun(products, target):
    products = products.resolve(strict=True)
    candidates = []
    for run in products.glob('*.xctestrun'):
        require(not run.is_symlink(), 'Linked xctestrun forbidden')
        records = list(plist_records(plistlib.loads(run.read_bytes())))
        if any(Path(r['TestBundlePath']).stem == target for r in records):
            require(len(records) == 1, 'Unexpected extra test target')
            for key in ['TestBundlePath', 'TestHostPath', 'UITargetAppPath']:
                if key not in records[0]:
                    continue
                host = records[0].get('TestHostPath', '').replace('__TESTROOT__', str(products))
                raw = records[0][key].replace('__TESTROOT__', str(products)).replace('__TESTHOST__', host)
                require('__' not in raw and Path(raw).is_absolute(), 'Unresolved test product path')
                path = Path(raw)
                require(path.exists() and path.resolve().is_relative_to(products), 'Test product escaped build root')
            candidates.append(run)
    require(len(candidates) == 1, 'Expected exactly one matching xctestrun')
    return candidates[0]


def products_digest(products):
    entries = []
    for path in sorted(products.rglob('*')):
        if path.is_symlink():
            require(path.resolve().is_relative_to(products.resolve()), 'Products symlink escaped build root')
            entries.append([str(path.relative_to(products)), 'link', os.readlink(path)])
        elif path.is_file():
            entries.append([str(path.relative_to(products)), 'file', digest(path)])
    require(bool(entries), 'Empty product inventory')
    return {'files': len(entries), 'sha256': hashlib.sha256(encode(entries).encode()).hexdigest()}


def runtime_environment(environ):
    require(sys.platform == 'darwin' and environ.get('GITHUB_ACTIONS') == 'true' and
            environ.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Ephemeral hosted Apple runner required')
    require(environ.get('GITHUB_REPOSITORY') == 'liboyang42-cpu/chengyin-ios' and
            environ.get('GITHUB_REF') == 'refs/heads/migration/native-ios' and
            environ.get('GITHUB_EVENT_NAME') in {'push', 'workflow_dispatch'}, 'Unexpected run scope')
    for key in ['GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT']:
        require(re.fullmatch('[1-9][0-9]*', environ.get(key, '')) is not None, 'Missing run identity')


class Diagnostic:
    def __init__(self, root, output, selection):
        self.root, self.output, self.selection = root, output, selection
        self.deadline = time.monotonic() + 2460  # reserve finalization before job's 45-minute cap
        self.receipt = {'version': 1, 'scope': 'selected-native-diagnostic-only', 'status': 'INCOMPLETE',
                        'selection': selection['name'], 'selection_sha256': digest(root / PATHS[1]),
                        'expected_count': 65, 'actual_count': 0, 'groups': {},
                        'coverage_boundary': selection['coverage_boundary']}
        for group in selection['groups']:
            self.receipt['groups'][group['name']] = {'status': 'NOT_RUN', 'expected': group['methods'],
                                                    'actual_count': 0, 'actual': []}

    def scope(self):
        return verify_scope(self.root, self.selection)

    def save(self):
        self.receipt['actual_count'] = sum(g['actual_count'] for g in self.receipt['groups'].values())
        write_json(self.output / 'receipt.json', self.receipt)

    def command(self, command, seconds, capture=False):
        remaining = self.deadline - time.monotonic()
        return execute(command, self.root, min(seconds, remaining), capture)

    def read(self, command, seconds=60):
        code, output = self.command(command, seconds, True)
        require(code == 0, 'Read command failed: ' + str(command[0]))
        return output.decode().strip()

    def toolchain(self):
        return {'xcode': self.read(['xcodebuild', '-version']), 'developer': self.read(['xcode-select', '-p']),
                'swift': self.read(['swift', '--version']), 'sdk_version': self.read(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version']),
                'sdk_path': self.read(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'])}

    def collect(self, group, command, seconds, result):
        entry = self.receipt['groups'][group['name']]
        entry['status'] = 'RUNNING'; self.save()
        code, transcript = self.command(command, seconds, 'stdout' if group['kind'] == 'swift' else False)
        entry['returncode'] = code
        try:
            if group['kind'] == 'swift':
                transcript_path = self.output / 'core-stdout.txt'
                transcript_path.write_bytes(transcript)
                entry['transcript_sha256'] = digest(transcript_path)
                # Emit only bounded XCTest identity/outcome lines, not compiler verbosity.
                for line in transcript.decode('utf-8', errors='replace').splitlines():
                    if line.startswith('Test Case '):
                        print(line, flush=True)
                rows = validate_core_evidence(result.read_bytes(), transcript, group['methods'], code)
                entry['result_sha256'] = digest(result)
            else:
                documents = {}
                for part in ['summary', 'tests']:
                    raw = self.read(['xcrun', 'xcresulttool', 'get', 'test-results', part, '--path', str(result), '--compact'])
                    documents[part] = json.loads(raw, object_pairs_hook=unique_object)
                    path = self.output / (group['name'] + '-' + part + '.json')
                    write_json(path, documents[part])
                    entry[part + '_sha256'] = digest(path)
                rows = parse_xcresult(documents['tests'], group['target'])
                entry['actual'] = rows; entry['actual_count'] = len(rows); self.save()
                validate_summary(documents['summary'], len(group['methods']), self.receipt['simulator']['udid'])
            entry['actual'] = rows; entry['actual_count'] = len(rows)
            validate_outcomes(rows, group['methods'], code)
            entry['status'] = 'PASS'
        except Exception as error:
            entry['status'] = 'FAIL'; entry['error'] = str(error)
            raise
        finally:
            self.save()

    def run(self):
        runtime_environment(os.environ)
        self.receipt.update(self.scope())
        self.receipt['run_id'] = os.environ['GITHUB_RUN_ID']; self.receipt['run_attempt'] = os.environ['GITHUB_RUN_ATTEMPT']
        self.receipt['workflow_sha'] = os.environ.get('GITHUB_WORKFLOW_SHA', '')
        require(self.receipt['workflow_sha'] == self.receipt['source_sha'], 'Workflow revision differs from source checkout')
        self.receipt['runner_image'] = {k: os.environ.get(k, '') for k in ['ImageOS', 'ImageVersion', 'RUNNER_ARCH']}
        self.receipt['toolchain'] = self.toolchain()
        self.save()
        groups = {g['name']: g for g in self.selection['groups']}
        core = self.output / 'core.xml'
        # Build once with normal live output; verbose compilation can exceed the
        # evidence bound. The exact test execution then reuses these products.
        require(not (self.root / '.build').exists(), 'Preexisting Core products are forbidden')
        self.receipt['groups']['core']['status'] = 'RUNNING'; self.save()
        code, _ = self.command(['swift', 'build', '--build-tests'], 720)
        self.receipt['groups']['core']['build_returncode'] = code; self.save()
        require(code == 0, 'Core build-for-testing failed')
        self.collect(groups['core'], core_command(groups['core'], core), 180, core)
        devices = json.loads(self.read(['xcrun', 'simctl', 'list', 'devices', 'available', '--json']))
        simulator = choose_simulator(devices); self.receipt['simulator'] = simulator; self.save()
        derived = self.output / 'ui-build'
        build = ['xcodebuild', '-project', 'Questify.xcodeproj', '-scheme', 'Questify', '-configuration', 'Debug',
                 '-sdk', 'iphonesimulator', '-destination', 'platform=iOS Simulator,id=' + simulator['udid'],
                 '-destination-timeout', '60', '-derivedDataPath', str(derived),
                 'CODE_SIGNING_ALLOWED=NO', 'ONLY_ACTIVE_ARCH=NO', 'build-for-testing']
        code, _ = self.command(build, 1200)
        require(code == 0, 'UI build-for-testing failed')
        ui_products = derived / 'Build/Products'
        ui_run = select_xctestrun(ui_products, 'QuestifyUITests')
        info = plistlib.loads((ui_products / 'Debug-iphonesimulator/Questify.app/Info.plist').read_bytes())
        require(info.get('QuestifyAPIBaseURL') in {None, ''}, 'Live API configuration forbidden')
        require(info.get('CFBundleSupportedPlatforms') == ['iPhoneSimulator'], 'Non-simulator app forbidden')
        require(not (ui_products / 'Debug-iphonesimulator/Questify.app/embedded.mobileprovision').exists(), 'Provisioned app forbidden')
        # Existing helper makes its one necessary isolated CI source archive and
        # uses no identity/certificate for the ephemeral simulator's ad-hoc host.
        code, _ = self.command([sys.executable, '-B', 'tools/build_simulator_keychain_host.py',
                               '--source-root', str(self.root), '--commit', self.receipt['source_sha'],
                               '--simulator', simulator['udid'], '--approve-ephemeral-simulator-host'], 1200)
        require(code == 0, 'Isolated AppUnit host build failed')
        app_products = Path(os.environ['RUNNER_TEMP']) / 'app-unit-linked/Products'
        app_run = select_xctestrun(app_products, 'QuestifyAppUnitTests')
        manifest = read_json(app_products / 'questify-test-products.json')
        require(manifest.get('commit') == self.receipt['source_sha'] and manifest.get('purpose') == 'isolated-simulator-app-unit', 'Wrong AppUnit products identity')
        require(manifest.get('targets') == {'QuestifyAppUnitTests': app_run.name}, 'Wrong AppUnit manifest target')
        require(manifest.get('toolchain') == {k: self.receipt['toolchain'][k] for k in ['xcode', 'developer']}, 'Wrong AppUnit toolchain')
        require(re.fullmatch('[a-f0-9]{64}', manifest.get('source_archive_sha256', '')) is not None, 'Missing source archive identity')
        self.receipt['products'] = {
            'ui': {'configuration': 'Debug/iphonesimulator/unsigned/ONLY_ACTIVE_ARCH=NO', 'xctestrun_sha256': digest(ui_run), **products_digest(ui_products)},
            'app-unit': {'configuration': 'Debug/iphonesimulator/isolated-entitlement-section/adhoc-host', 'xctestrun_sha256': digest(app_run), **products_digest(app_products), 'manifest': manifest}}
        self.save()
        require(self.toolchain() == self.receipt['toolchain'], 'Toolchain changed after building')
        code, _ = self.command(['xcrun', 'simctl', 'bootstatus', simulator['udid'], '-b'], 180)
        require(code == 0, 'Selected simulator boot failed')
        for name, run in [('app-unit', app_run), ('ui', ui_run)]:
            result = self.output / (name + '.xcresult')
            self.collect(groups[name], xcode_test_command(groups[name], run, simulator['udid'], result),
                         360 if name == 'app-unit' else 1000, result)
        require(self.scope()['source_tree'] == self.receipt['source_tree'], 'Source changed during diagnostics')
        require(self.toolchain() == self.receipt['toolchain'], 'Toolchain changed during diagnostics')
        self.receipt['status'] = 'PASS'; self.save()



class NativeDiagnostic(Diagnostic):
    def scope(self):
        return verify_description_scope(self.root, self.selection)


def validate_native_pass_receipt(receipt, expected, selection):
    old = native_predecessor_selection(selection)
    require(receipt.get('native_base_commit') == NATIVE_BASE_COMMIT
            and receipt.get('native_base_tree') == NATIVE_BASE_TREE
            and receipt.get('native_selection') == NATIVE_NAME, 'Wrong receipt native repair identity')
    validate_pass_receipt(receipt, expected, old)


def validate_pass_receipt(receipt, expected, selection):
    require(receipt.get('status') == 'PASS' and receipt.get('scope') == 'selected-native-diagnostic-only', 'Not a selected-test pass receipt')
    for key, value in expected.items():
        require(bool(value) and receipt.get(key) == value, 'Receipt identity mismatch: ' + key)
    require(receipt.get('base_commit') == BASE_COMMIT and receipt.get('base_tree') == BASE_TREE, 'Wrong receipt base')
    require(receipt.get('historical_base_commit') == HISTORICAL_BASE_COMMIT
            and receipt.get('historical_base_tree') == HISTORICAL_BASE_TREE, 'Wrong receipt historical base')
    require(receipt.get('creator_base_commit') == CREATOR_COMMIT
            and receipt.get('creator_base_tree') == CREATOR_TREE, 'Wrong receipt creator base')
    require(receipt.get('selection') == selection['name'] and all(type(receipt.get(k)) is int and receipt[k] == 65 for k in ['expected_count', 'actual_count']), 'Wrong total executed count')
    require(set(receipt.get('groups', {})) == set(GROUPS), 'Missing receipt group')
    toolchain = receipt.get('toolchain')
    require(isinstance(toolchain, dict) and set(toolchain) == {'xcode', 'developer', 'swift', 'sdk_version', 'sdk_path'} and all(isinstance(v, str) and v for v in toolchain.values()), 'Incomplete receipt toolchain')
    simulator = receipt.get('simulator', {})
    require(re.fullmatch('[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', simulator.get('udid', '')) is not None and simulator.get('name', '').startswith('iPhone') and simulator.get('runtime', '').startswith('com.apple.CoreSimulator.SimRuntime.iOS-'), 'Incomplete simulator identity')
    for group in selection['groups']:
        actual = receipt['groups'][group['name']]
        require(actual.get('status') == 'PASS' and actual.get('expected') == group['methods'] and type(actual.get('actual_count')) is int and actual['actual_count'] == len(group['methods']), 'Wrong group result count')
        validate_outcomes(actual.get('actual'), group['methods'], actual.get('returncode'))
        if group['kind'] == 'swift':
            require(type(actual.get('build_returncode')) is int and actual['build_returncode'] == 0, 'Core build did not succeed')
        for key in (['result_sha256', 'transcript_sha256'] if group['kind'] == 'swift' else ['summary_sha256', 'tests_sha256']):
            require(re.fullmatch('[a-f0-9]{64}', actual.get(key, '')) is not None, 'Missing executed-result digest')
    products = receipt.get('products', {})
    require(set(products) == {'ui', 'app-unit'}, 'Missing build configurations')
    for name, config in [('ui', 'Debug/iphonesimulator/unsigned/ONLY_ACTIVE_ARCH=NO'), ('app-unit', 'Debug/iphonesimulator/isolated-entitlement-section/adhoc-host')]:
        product = products[name]
        require(product.get('configuration') == config and type(product.get('files')) is int and product['files'] > 0, 'Wrong product configuration/inventory')
        for key in ['sha256', 'xctestrun_sha256']:
            require(re.fullmatch('[a-f0-9]{64}', product.get(key, '')) is not None, 'Missing product digest')
    manifest = products['app-unit'].get('manifest', {})
    require(manifest.get('commit') == receipt['source_sha'] and manifest.get('purpose') == 'isolated-simulator-app-unit' and manifest.get('toolchain') == {k: toolchain[k] for k in ['xcode', 'developer']}, 'AppUnit products do not match receipt')
    require(re.fullmatch('[a-f0-9]{64}', manifest.get('source_archive_sha256', '')) is not None, 'Missing source archive digest')


def report(output, summary, root=ROOT, *, native=False):
    path = output / 'receipt.json'
    if not path.is_file():
        text = 'Targeted native diagnostics: NOT_RUN. No finalized receipt; full required native gates remain separate.\n'
        print(text)
        if summary:
            with summary.open('a') as destination:
                destination.write(text)
        return
    receipt = read_json(path)
    if receipt.get('status') == 'PASS':
        expected = {key: os.environ.get(env, '') for key, env in [('source_sha', 'GITHUB_SHA'), ('workflow_sha', 'GITHUB_WORKFLOW_SHA'), ('run_id', 'GITHUB_RUN_ID'), ('run_attempt', 'GITHUB_RUN_ATTEMPT')]}
        expected['source_tree'] = checked(['git', 'rev-parse', 'HEAD^{tree}'], root)
        expected['selection_sha256'] = digest(root / PATHS[1])
        selection = read_json(root / PATHS[1])
        if native:
            verify_description_scope(root, selection)
            validate_description_pass_receipt(receipt, expected, selection)
        else:
            validate_pass_receipt(receipt, expected, selection)
        for group in selection['groups']:
            actual = receipt['groups'][group['name']]
            if group['kind'] == 'swift':
                result = output / 'core.xml'
                require(digest(result) == actual['result_sha256'], 'Core evidence changed')
                transcript = output / 'core-stdout.txt'
                require(digest(transcript) == actual['transcript_sha256'], 'Core transcript changed')
                rows = validate_core_evidence(result.read_bytes(), transcript.read_bytes(), group['methods'], actual['returncode'])
            else:
                documents = {}
                for part in ['summary', 'tests']:
                    result = output / (group['name'] + '-' + part + '.json')
                    require(digest(result) == actual[part + '_sha256'], 'XCTest evidence changed')
                    documents[part] = read_json(result)
                rows = parse_xcresult(documents['tests'], group['target'])
                validate_summary(documents['summary'], len(group['methods']), receipt['simulator']['udid'])
            require(rows == actual['actual'], 'Receipt does not match actual result evidence')
            validate_outcomes(rows, group['methods'], actual['returncode'])
    # This report is evidence only. It never promotes a partial run to success.
    print('TARGETED_NATIVE_RECEIPT ' + encode(receipt), flush=True)
    lines = ['Targeted native diagnostics: ' + receipt.get('status', 'INCOMPLETE'),
             'Source SHA: ' + receipt.get('source_sha', 'NOT_RECORDED'),
             'Source tree: ' + receipt.get('source_tree', 'NOT_RECORDED'),
             'Actual methods: ' + str(receipt.get('actual_count', 0)) + ' / 65',
             receipt.get('coverage_boundary', '')]
    for name, group in receipt.get('groups', {}).items():
        lines.append(name + ': ' + group['status'] + ', actual ' + str(group['actual_count']))
        for row in group['actual']:
            lines.append('  ' + row['method'] + ': ' + row['status'])
    if summary:
        with summary.open('a') as destination:
            destination.write('\n'.join(lines) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['validate', 'run', 'report'])
    parser.add_argument('--source-root', type=Path, default=ROOT)
    parser.add_argument('--selection', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--summary', type=Path)
    args = parser.parse_args()
    root = args.source_root.resolve(strict=True)
    if args.action == 'report':
        require(args.output is not None, 'Output required')
        report(args.output, args.summary, root, native=True)
        return 0
    selection = read_json(args.selection or root / PATHS[1])
    validate_description_selection(selection, root)
    if args.action == 'validate':
        print('Validated fixed selection: Core 44, AppUnit 14, UI 7; Apple execution NOT_RUN')
        return 0
    require(args.output is not None and 'RUNNER_TEMP' in os.environ, 'Fresh runner output required')
    temp = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
    output = args.output.absolute()
    require(output.parent.resolve(strict=True) == temp and not output.is_symlink(), 'Output must be a new direct runner-temp child')
    output.mkdir()  # never reuse old results, even on retries
    job = NativeDiagnostic(root, output, selection); job.save()
    try:
        job.run()
    except BaseException as error:
        job.receipt['status'] = 'FAIL' if isinstance(error, Exception) else 'INCOMPLETE'
        job.receipt['error'] = str(error)
        for group in job.receipt['groups'].values():
            if group['status'] == 'RUNNING':
                group['status'] = 'FAIL'; group['error'] = str(error)
        job.save()
        print('Targeted diagnostic incomplete/failed: ' + str(error), flush=True)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
