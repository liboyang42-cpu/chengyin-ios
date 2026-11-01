"""Export reviewed synthetic UI attachments after the same full-run shard passes."""
import argparse
from pathlib import Path
import tempfile
import time
from tools import current_native as n


WANTED = {
    'HomeFeedFlowTests/testTypedDestinationsAndPriceCurrencyDisclosure': ['Home feed initial content'],
    'HomeFeedFlowTests/testEmptyStateIsNotAnError': ['Home feed known empty state'],
    'HomeFeedFlowTests/testPageFailureRetriesAndDuplicateFullPageStillPaginates': ['Home feed page failure before retry'],
    'ActivityFlowTests/testNullableTicketValuesStayUnknownAndDetailCannotBook': ['Activity detail ticket information'],
    'TicketWalletFlowTests/testWalletDetailEntitlementsBackAndReopenNeverOffersCodeOrPayment': ['Ticket wallet initial content', 'Ticket detail entitlements'],
    'AccessibilityPresentationFlowTests/testHomeChineseDarkLargeTextRemainsNavigable': ['Home Chinese dark accessibility3 reduced-motion'],
    'AccessibilityPresentationFlowTests/testTicketWalletChineseDarkLargeTextKeepsDetailEntry': ['Ticket wallet Chinese dark accessibility3 reduced-motion', 'Ticket detail Chinese dark accessibility3 reduced-motion'],
    'ReferenceChatTaskFlowTests/testMessageKeyboardKeepsSendActionReachable': ['IM long draft with keyboard visible', 'IM long draft and pinned composer'],
    'ReferenceChatTaskFlowTests/testMessageEarlierPageAndDetailReturnRetainHistory': ['IM earlier history retained after detail return'],
    'MerchantOnboardingFlowTests/testRejectedBackfillNeedsConfirmationAndReadsPendingState': ['Merchant reapply native form', 'Merchant native confirmation before Cancel', 'Merchant application acknowledged with pending server status'],
    'NativePresentationPatternFlowTests/testGalleryEnglishPagesClosesAndReopensAtSelectedImage': ['Media fullscreen English light reopened'],
    'NativePresentationPatternFlowTests/testGalleryChineseMaximumTextDarkReducedMotionKeepsPagingAndClose': ['Media fullscreen Chinese accessibility5 dark reduced-motion'],
    'SocialAccountFlowTests/testDraftSurvivesNestedReviewAndCancelThenDiscardReopensEmpty': ['Social draft preserved after nested review and cancel'],
    'SocialAccountFlowTests/testChineseLargeTextDraftCancelKeepsTextAndKeyboardDismisses': ['Chinese social draft large text dark mode after keyboard dismissal'],
    'NativeSettingsReuseFlowTests/testMaximumTextLegalMissingStateBackAndReopenInBothLanguages': ['Settings legal missing accessibility5 zh-Hans'],
    'PlayRouteMapCameraFlowTests/testOverviewCurrentAndOtherStopPreviewFormCompleteInspectionJourney': ['Route overview current and inspected stop remain separate'],
    'AccessibilityPresentationFlowTests/testRouteMapChineseDarkLargeTextMarksPreviewedPinAndKeepsEquivalentList': ['Route map Chinese dark accessibility3 reduced-motion previewed pin'],
    'ModuleFlowTests/testProfileOrderReadbackAndBack': ['Order detail – synthetic data'],
    'PlayRouteMapContinuationFlowTests/testChineseMaximumTextUsesFullListAndExplicitRouteDisclaimer': ['Chinese maximum-text route navigation'],
    'PlayExperienceFlowTests/testOrdinaryReadFallbackUsesFreeStoreCardsAndNoOrientationAnswerForm': ['Normal read fallback retains free-exploration store UI'],
    'NonCashRewardFlowTests/testNormalAccountRewardDetailCloseReopenAndBack': ['Synthetic My Rewards normal account journey'],
}


def export(plan, output):
    output = output.resolve()
    n.screenshot_safe_directory(output)
    receipt = n.reparse_actual_result(output, plan)
    n.require(plan['scope'] == 'full-current-regression' and receipt['role'] == 'ui', 'Only same-run full UI shards may export')
    commands = n.read_json(output / 'commands.json')
    argv = next(row['argv'] for row in commands if row['stem'] == 'native-test')
    bundle = output / 'ui.xcresult'
    n.require(argv[argv.index('-resultBundlePath') + 1] == str(bundle)
              and not bundle.is_symlink() and (bundle / 'Info.plist').is_file(), 'Wrong or unfinished result bundle')
    assigned = {row['method'] for row in receipt['actual']}
    wanted = {'QuestifyUITests/' + key: value for key, value in WANTED.items()
              if 'QuestifyUITests/' + key in assigned}
    published = output.parent / 'current-ui-audit-evidence'
    published.mkdir()  # Never replace another export.
    report = {'kind': 'SYNTHETIC_UI_IMAGES_NOT_VISUAL_ACCEPTANCE', 'identity': plan['identity'],
              'index': receipt['index'], 'receipt_sha256': n.digest(output / 'receipt.json'),
              'selection_sha256': n.control.digest(n.control.encode(WANTED)),
              'selection_images': sum(map(len, WANTED.values())), 'expected': wanted,
              'status': 'INCOMPLETE', 'files': [], 'methods': []}
    deadline = time.monotonic() + 60
    total = 0
    developer = receipt['toolchain']['developer']
    try:
        with tempfile.TemporaryDirectory(prefix='ui-audit-export-', dir=output.parent) as temp:
            stage = Path(temp)
            status, version = n.screenshot_probe_command(['xcrun', 'xcresulttool', 'version'], n.control.ROOT, min(deadline, time.monotonic() + 5), stage, developer, True)
            n.require(status == 'OK' and version.startswith(b'xcresulttool version ') and len(version) <= 512, 'Unknown xcresulttool')
            report['xcresulttool_version'] = version.decode().strip()
            status, help_data = n.screenshot_probe_command(['xcrun', 'xcresulttool', 'help', 'export', 'attachments'], n.control.ROOT, min(deadline, time.monotonic() + 5), stage, developer, True)
            n.require(status == 'OK' and all(flag in help_data for flag in (b'--path', b'--output-path', b'--test-id')), 'Unsupported attachment exporter')
            for ordinal, (method, labels) in enumerate(wanted.items()):
                folder = stage / str(ordinal); folder.mkdir()
                identifier = method.split('/', 1)[1] + '()'
                status, _ = n.screenshot_probe_command(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(bundle), '--output-path', str(folder), '--test-id', identifier], n.control.ROOT, deadline, stage, developer)
                report['methods'].append({'method': method, 'status': status})
                n.require(status == 'OK', 'Attachment export did not complete')
                for label in labels:
                    name = label if method.startswith(('QuestifyUITests/MerchantOnboardingFlowTests/', 'QuestifyUITests/ModuleFlowTests/')) else label + ' – synthetic fixture'
                    images = n.bounded_failure_images(folder, method, 64 * 1024 * 1024 - total, 1, allowed_names=[name])
                    n.require(len(images) == 1, 'Missing or ambiguous requested attachment')
                    filename, data = images[0]
                    destination = published / filename
                    if not destination.exists(): destination.write_bytes(data)
                    total += len(data)
                    report['files'].append({'method': method, 'attachment': name, 'path': filename,
                                            'bytes': len(data), 'sha256': n.control.digest(data)})
            n.require(len(report['files']) == sum(map(len, wanted.values())) <= 28, 'Incomplete screenshot selection')
            n.require(n.control.source_identity(n.control.ROOT) == plan['identity'], 'Source changed during export')
            report['status'] = 'COMPLETE'
    finally:
        n.write_json(published / 'audit-index.json', report)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    plan = n.verify_plan(n.control.ROOT, args.plan)
    if plan['scope'] == 'full-current-regression':
        export(plan, args.output)
    else:
        print('UI audit images require a full-current-regression plan; related plan skipped.')


if __name__ == '__main__':
    main()
