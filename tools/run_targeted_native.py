#!/usr/bin/env python3
"""Fixed, same-run native diagnostics. Never emits a full-CI completion receipt.

TN2339: compile once per configuration, then select exact XCTest methods.
Only the existing isolated AppUnit helper may archive/ad-hoc-sign a simulator
host. This runner does not copy source, upload artifacts, or use credentials.
"""
import argparse
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


def validate_static_repair(selection, root):
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
        raw = path.read_bytes()
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


def verify_static_repair_tree(selection, root, revision, before):
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


def restore_creator_inputs(selection, root):
    """Current15 -> exact3393 -> fixed b75 inputs; historical domains stay fixed."""
    parent = validate_static_repair(selection, root)
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
        raw = parent.get(row['path'], path.read_bytes())
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


def validate_creator_changes(selection, root):
    published = restore_creator_inputs(selection, root)
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


def validate_reviewed_repairs(selection, root):
    creator = validate_creator_changes(selection, root)
    repairs = selection.get('reviewed_repairs')
    require(isinstance(repairs, list) and [row.get('path') for row in repairs] == list(REPAIR_PATHS), 'Missing/changed reviewed repair scope')
    restored = {}
    for row in repairs:
        require(set(row) == {'path', 'before_sha256', 'before_blob', 'after_sha256', 'hunks'} and isinstance(row['hunks'], list) and bool(row['hunks']), 'Invalid reviewed repair binding')
        path = root / row['path']
        require(not path.is_symlink() and path.resolve().is_relative_to(root.resolve()), 'Repair escaped checkout')
        restored[row['path']] = inverse_reviewed_repair(row, creator.get(row['path'], path.read_bytes()))
    current = read_json(root / REPAIR_PATHS[1])
    repair_hashes = {row['path']: row['after_sha256'] for row in selection['static_repair_changes']}
    crop = repairs[0]
    require(current['feature_batch_support_sha256'][crop['path']] == crop['after_sha256'], 'Current crop support is not genuine')
    require(current['feature_batch_sources'][crop['path']] == {k: crop[k] for k in ['before_sha256', 'after_sha256', 'hunks']}, 'Missing exact central crop inverse')
    require(current['feature_batch_support_sha256'][repairs[3]['path']] == repair_hashes[repairs[3]['path']], 'Current admission support is not genuine')
    for row in repairs[4:]:
        require(current['followon_support_sha256'][row['path']] == row['after_sha256'], 'Current static support is not genuine')
    pins = re.findall(r"^CONTRACT_SHA256 = '([0-9a-f]{64})'$", (root / REPAIR_PATHS[2]).read_text(), re.MULTILINE)
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


def validate_selection(selection, root):
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
        require(digest(path) == expected, 'Source digest changed: ' + relative)
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
    validate_reviewed_repairs(selection, root)
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
        self.receipt.update(verify_scope(self.root, self.selection))
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
        require(verify_scope(self.root, self.selection)['source_tree'] == self.receipt['source_tree'], 'Source changed during diagnostics')
        require(self.toolchain() == self.receipt['toolchain'], 'Toolchain changed during diagnostics')
        self.receipt['status'] = 'PASS'; self.save()



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


def report(output, summary, root=ROOT):
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
        report(args.output, args.summary, root)
        return 0
    selection = read_json(args.selection or root / PATHS[1])
    validate_selection(selection, root)
    if args.action == 'validate':
        print('Validated fixed selection: Core 44, AppUnit 14, UI 7; Apple execution NOT_RUN')
        return 0
    require(args.output is not None and 'RUNNER_TEMP' in os.environ, 'Fresh runner output required')
    temp = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
    output = args.output.absolute()
    require(output.parent.resolve(strict=True) == temp and not output.is_symlink(), 'Output must be a new direct runner-temp child')
    output.mkdir()  # never reuse old results, even on retries
    job = Diagnostic(root, output, selection); job.save()
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
