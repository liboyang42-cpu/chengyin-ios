"""Source contract: chapter and offer writes use an approval, not the offline harness. Does not execute Swift."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ChapterExecutionApprovalTests(unittest.TestCase):
    def setUp(self):
        self.flow = (ROOT / 'Core/CooperationFlowService.swift').read_text()
        self.content = (ROOT / 'Core/MerchantContentService.swift').read_text()
        self.session = (ROOT / 'App/AppSession.swift').read_text()

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
