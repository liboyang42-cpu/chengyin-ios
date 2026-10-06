"""Source/fixture checks only. Swift execution and Apple UI checks require their real targets."""
import json
import re
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

class PaidProfessionalContracts(unittest.TestCase):
    def source(self, path): return (ROOT / path).read_text()
    def test_grants_are_independent_default_nil_and_cloned(self):
        s = self.source('App/AppCompositionRoot.swift')
        for grant, typ in [('workshopPaidProfessionalReadApproval','WorkshopPaidProfessionalReadApproval'),('workshopPaidProfessionalWriteApproval','WorkshopPaidProfessionalWriteApproval')]:
            self.assertEqual(s.count(grant + ': @escaping @MainActor (RuntimeDependencyContext) -> ' + typ + '? = { _ in nil }'), 2)
            self.assertEqual(s.count(grant + ': ' + grant), 2)
        self.assertNotIn('workshopPaidProfessional',self.source('App/RegionalLaunchConfiguration.swift'))
    def test_normal_account_receipt_entry_and_separate_recovery(self):
        self.assertIn('makeProfessional: { session.makeWorkshopPaidProfessionalController(reference: $0) }',self.source('App/AccountView.swift'))
        view = self.source('App/WorkshopPaidInstallView.swift')
        self.assertEqual(view.count('WorkshopPaidProfessionalEntry(makeReference:'),2)
        self.assertIn('controller.installedTextReference(receipt, appearance: displayed)',view)
        self.assertIn('controller.installedTextReference(outcome, appearance: displayed)',view)
        self.assertNotIn('makeText',self.source('App/WorkshopPaidProfessionalView.swift'))
    def test_precise_protocol_routes_and_write_separation(self):
        s = self.source('Core/WorkshopPaidProfessionalService.swift')
        routes = set(re.findall(r'return "(api/workshop/purchased/[^\"]+)"',s))
        self.assertEqual(routes,{'api/workshop/purchased/professional-targets/list','api/workshop/purchased/professional-targets/detail',*[f'api/workshop/purchased/professional-operations/{p}' for p in ['submit','status','cancel','history']]})
        for marker in ['url.query == nil','url.fragment == nil','request.httpBodyStream == nil','String(data.count)','4_096 : 512','(try? value.wireData()) == data','request.cachePolicy == .reloadIgnoringLocalCacheData']:
            self.assertIn(marker,s)
        root = self.source('App/AppCompositionRoot.swift')
        self.assertIn('route != .submit && route != .cancel',root)
        dedicated = root.split('func sendWorkshopPaidProfessional(',1)[1].split('func sendWorkshopPaidInstall(',1)[0]
        self.assertIn('authorization.consume(request, context: context, revision: approval.revision)',dedicated)
        self.assertIn('try authorization.validate()',dedicated)
    def test_exact_command_has_no_source_body_or_owner_claim(self):
        s = self.source('Core/WorkshopPaidProfessionalContracts.swift')
        cmd = s.split('public struct WorkshopPaidProfessionalCommand:',1)[1].split('public struct WorkshopPaidProfessionalReceipt:',1)[0]
        fields = cmd.split('enum CodingKeys:',1)[1].split('public init(reference:',1)[0]
        for forbidden in ['ownerMemberID','sourceJSON','sourceJson','paidAt','payment','token','termsDocument','rewardEnabled']:
            self.assertNotIn(forbidden, fields)
        for marker in ['currentDraft.targetDraftId == body.originalTargetDraftID','confirmedMode == target.mode','confirmedMode != .unresolved','reference.item.status == .active','LOCAL_ADAPTATION']:
            self.assertIn(marker,cmd)
    def test_unknown_and_prepared_never_authorize_replacement(self):
        s = self.source('Core/WorkshopPaidProfessionalOperation.swift')
        self.assertIn('safeToReplace == (state == .rejected || state == .cancelled)',s)
        self.assertIn('commandHash == command.commandHash',s)
        store = self.source('Core/WorkshopPaidProfessionalPendingStore.swift')
        self.assertIn('guard history.state.terminal',store)
        self.assertIn('history.matches(old)',store)
        self.assertIn('try old.wireData() == command.wireData()',store)
        self.assertEqual(store.count('storage.remove('),1)
    def test_unknown_body_cannot_be_restored_from_history(self):
        s = self.source('Core/WorkshopPaidProfessionalController.swift')
        recovery = s.split('public func offerRecovery(',1)[1].split('public func offerNewReview(',1)[0]
        self.assertNotIn('preparation.body(',recovery)
        self.assertNotIn('TemplateAuthoring',s)
        self.assertIn('try store.save(value); command = value',s)
        self.assertIn('WorkshopPaidProfessionalConfirmation(command: value, lifetime: life, purpose: .create)',s)
        self.assertIn('purpose: .cancel',s)
    def test_action_lifetime_is_captured_before_task_and_old_disappearance_fenced(self):
        s = self.source('Core/WorkshopPaidProfessionalController.swift')
        for marker in ['displayed.begin()','displayed.revoke(); guard appearance === displayed','action.claim()','action.live && self.current(displayed)','displayed.action?.revoke(); lifetime?.revoke()']:
            self.assertIn(marker,s)
        view = self.source('App/WorkshopPaidProfessionalView.swift')
        self.assertIn('ownedTask = Task { await action() }',view)
        self.assertIn('controller.close(displayed); ownedTask?.cancel()',view)
        p = self.source('App/WorkshopPaidProfessionalPresentation.swift')
        self.assertIn('guard selection?.id == expected else { return }',p)
        self.assertIn('guard selection === displayed else { return }',p)
    def test_late_unauthorized_side_effect_checks_lifetime(self):
        s = self.source('Core/WorkshopPaidProfessionalService.swift')
        self.assertEqual(s.count('try check(lifetime, write: write); onUnauthorized(lease.context)'),2)
        self.assertIn('try lifetime.check(); guard lease.isCurrent',s)
        self.assertIn('current.revision',s)
        session = self.source('App/AppSession.swift')
        factory = session.split('func makeWorkshopPaidProfessionalController(',1)[1].split('func makeWorkshopPaidInstalledTextController(',1)[0]
        for marker in ['self.compositionViewerRevision == viewer','self.workshopReadConfigurationRevision == configurationRevision','self.currentWorkshopPaidProfessionalWriteApproval?.revision','self.currentWorkshopPaidInstalledTextApproval?.revision','self.currentWorkshopPaidInstallApproval?.revision']:
            self.assertIn(marker,factory)
    def test_current_generic_draft_cas_reuses_real_reader_with_bounded_paging(self):
        s = self.source('Core/WorkshopPaidProfessionalPreparation.swift')
        for marker in ['for _ in 0..<10','installReader.targets(','.targetDraftId == body.originalTargetDraftID','value.businessType == "TOPIC"','defer { bridge.revoke() }']:
            self.assertIn(marker,s)
        self.assertNotIn('payloadJSON',s)
        self.assertNotIn('TemplateAuthoringDraft',s)
    def test_five_states_and_modes_are_fully_localized(self):
        c = json.loads(self.source('Resources/WorkshopPaidProfessional.xcstrings'))['strings']
        for key in c:
            for language in ['en','zh-Hans']:
                self.assertTrue(c[key]['localizations'][language]['stringUnit']['value'])
        for state in ['NOT_FOUND','PREPARED','CREATED','REJECTED','CANCELLED']:
            self.assertIn('workshopPaidProfessional.state.'+state,c)
        for mode in ['CITY_ORIENTATION','FREE_EXPLORATION','UNRESOLVED']:
            self.assertIn('workshopPaidProfessional.mode.'+mode,c)
        view = self.source('App/WorkshopPaidProfessionalView.swift')
        for key in re.findall(r'professionalText\("([^"]+)"\)',view):
            if key not in ['mode.','state.']: self.assertIn('workshopPaidProfessional.'+key,c)
    def test_real_service_and_host_regressions_are_authored(self):
        core = self.source('Tests/CoreTests/WorkshopPaidProfessionalTests.swift')
        for marker in ['testCommittedLostResponseRecoversSameUUIDWithoutDuplicateCreate','testQueuedConfirmAfterBackPersistsIntentWithoutSendingAndCanCloseUnknownOnServer','testClosedSuspendedRead401HasNoLogoutSideEffect','testCurrent401DoesExpireSessionOnce','testColdHistoryDiscoveryNeedsNoBodyAndReadsTerminalStatus']:
            self.assertIn('func '+marker,core)
        app = self.source('Tests/AppUnitTests/WorkshopPaidProfessionalNormalFlowTests.swift')
        for marker in ['testActualNormalPlayerMerchantClubContextReviewAndDedicatedCreate','testNormalGenericTransportRejectsSubmitAndCancelEvenWithWriteGrant','testHostedActualSheetCloseQueuedActionAndReopenKeepsFreshAppearance']:
            self.assertIn('func '+marker,app)
        project = self.source('Questify.xcodeproj/project.pbxproj')
        self.assertIn('Tests/CoreTests', self.source('Package.swift'))
        for name in ['WorkshopPaidProfessionalNormalFlowTests.swift','WorkshopPaidProfessional.xcstrings']:
            self.assertIn(name,project)
