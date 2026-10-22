"""Source contract: chapter and offer writes use an approval, not the offline harness. Does not execute Swift."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ChapterExecutionApprovalTests(unittest.TestCase):
    def setUp(self):
        self.flow = (ROOT / 'Core/CooperationFlowService.swift').read_text()
        self.content = (ROOT / 'Core/MerchantContentService.swift').read_text()
        self.session = (ROOT / 'App/AppSession.swift').read_text()
        self.root = (ROOT / 'App/AppCompositionRoot.swift').read_text()
        self.coord = (ROOT / 'Core/ChapterReplacementInvitationCoordinator.swift').read_text()

    def test_real_transport_approval_is_not_the_offline_harness(self):
        self.assertIn('executionApproval()?.permits(operation, endpoint: configuration.baseURL)', self.flow)
        self.assertIn('!(transport is any CoopFlowOfflineHTTPTransport)', self.flow)
        self.assertIn('dormantWritesEnabled: Bool = false', self.flow)
        self.assertIn('case .invite: return writeApproval().chapterInvite', self.content)
        self.assertIn('case .respondChapterInvitation: return writeApproval().chapterRespond', self.content)
        self.assertIn('execution == .injectedOfflineHarness { return permitsWrites }', self.content)

    def test_host_defaults_closed(self):
        self.assertIn('coopFlowExecutionApproval: @escaping (RuntimeDependencyContext) -> CoopFlowExecutionApproval? = { _ in nil }', self.session)
        self.assertIn('merchantContentWriteApproval: @escaping (RuntimeDependencyContext) -> MerchantContentWriteApproval = { _ in .init() }', self.session)
        self.assertIn('execution: .injectedOfflineHarness', (ROOT / 'App/MerchantContentFixtureScenarioView.swift').read_text())
        self.assertNotIn('execution: .injectedOfflineHarness', self.session)

    def test_three_exits_are_exact_and_default_closed(self):
        for name in ('chapterInviteExecution', 'chapterRespondExecution', 'offerWithdrawExecution'):
            self.assertIn(f'var {name}:', self.root)
        self.assertIn('{ _ in false }', self.root)
        self.assertIn('{ _, _, _ in false }', self.root)
        self.assertLess(
            self.root.find('api/merchant/chapter-application/invite/respond'),
            self.root.find('api/merchant/chapter-application/invite").absoluteString'))
        self.assertIn('MerchantOfferWithdrawalRequest.path', self.root)
        self.assertIn('.canonical()', self.root)
        self.assertIn('canonical == body', self.root)
        self.assertIn('merchantContentWriteApproval(context).chapterInvite', self.session)
        self.assertIn('merchantContentWriteApproval(context).chapterRespond', self.session)
        self.assertIn('permits(.withdrawOffer(id: id, reason: reason), endpoint: context.baseURL)', self.session)
        self.assertIn('chapterInviteExecution(context)', self.root)
        verify = self.coord.split('private func verify(')[1]
        self.assertLess(verify.find('effects.releaseInviteLock(plan)'), verify.find('intents.clear('))
        self.assertNotIn('sendInvite', verify)
        self.assertIn('func releaseChapterReplacementInviteLock', self.content)
        self.assertIn('row.action == "invite"', self.content)
        self.assertIn('row.station == nil', self.content)
        self.assertIn('mine.count > 1', self.content)
