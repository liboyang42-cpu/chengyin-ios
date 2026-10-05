import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
class WithdrawalSupportBindingTests(unittest.TestCase):
    def test_normal_roots_share_scoped_reader(self):
        root = (ROOT/'App/QuestifyApp.swift').read_text()
        session = (ROOT/'App/AppSession.swift').read_text()
        self.assertIn('.environment(\\.withdrawalSupportReader, session.withdrawalSupportReader)', root)
        self.assertIn('source: WithdrawalSupportReader.Source? = nil', session)
        self.assertIn('approval: @escaping () -> WithdrawalSupportApproval? = { nil }', session)
        self.assertIn('self?.walletCommerceScope', session)
        self.assertIn('WithdrawalSupportContactView()', (ROOT/'App/WithdrawalSupportLandingView.swift').read_text())
        self.assertIn('if case .finance = resource', (ROOT/'App/CooperationFlowWorkbench.swift').read_text())
    def test_copy_is_revalidated_and_local_contact_only(self):
        s = (ROOT/'App/WithdrawalSupportContactView.swift').read_text()
        self.assertIn('try await reader.contactForCopy(displayed)', s)
        self.assertIn('scope == reader.scope, !Task.isCancelled', s)
        self.assertIn('.localOnly: true', s)
        self.assertIn('.expirationDate:', s)
        self.assertNotIn('textSelection', s)
        self.assertNotIn('openURL', s)
        self.assertNotIn('print(', s)
    def test_interrupted_and_unconfigured_paths_remain(self):
        s = (ROOT/'App/WithdrawalSupportContactView.swift').read_text()
        for requirement in ['.task(id: reader?.scope)', '.onDisappear { clear() }',
                            '.onChange(of: scenePhase)', 'clear(); dismiss()', 'withdrawal.support.unconfigured',
                            'configuration = nil; loadedScope = nil', 'guard !busy']:
            self.assertIn(requirement, s)
    def test_reader_fences_and_synthetic_separation(self):
        s = (ROOT/'Core/WithdrawalSupportConfiguration.swift').read_text()
        for requirement in ['session() == scope', 'approval() == review', 'value.market == review.market',
                            'value.expiresAt > now()', 'fresh.scope == displayed.scope', 'fresh.approval == displayed.approval',
                            'fresh.configuration.revision == displayed.configuration.revision', 'Task.checkCancellation()']:
            self.assertIn(requirement, s)
        self.assertNotIn('synthetic_support', s)
        self.assertNotIn('URLRequest', s)
